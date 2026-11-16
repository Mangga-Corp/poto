//
//  QuestionPhotoQuality.swift
//  gophoto
//
//  Mode 2 (16 Nov): which photos may be SHOWN in a style question. A photo with closed eyes is
//  rejected for being a bad moment, not for how it was shot, so it is never shown (it still
//  counts for the measurements). Three separate checks (Codex v5): eyes, sharpness, face.
//  - Eyes: Core Image `CIDetectorEyeBlink` on the largest face. Both eyes closed → closed.
//    Eyes not found → unknown (never treated as open).
//  - Sharpness: variance of the Laplacian over the person (or the whole photo), on a fixed-size
//    grayscale render so photos are comparable. LOGGED ONLY: no threshold until calibrated.
//  Values are logged (category "style") for calibration.
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import os
import UIKit

nonisolated enum QuestionPhotoQuality {
    nonisolated enum Eyes: String, Sendable, Equatable { case open, closed, unknown }

    nonisolated struct Result: Sendable, Equatable {
        var eyes: Eyes
        /// Variance of the Laplacian (higher = sharper). Not used to reject yet.
        var sharpness: Double?

        /// May be shown in a question.
        var displayable: Bool { eyes != .closed }
        /// Tie-breaker for picking a photo to show: open eyes, then unknown, then sharper.
        var score: Double {
            let eyesRank: Double = eyes == .open ? 2 : (eyes == .unknown ? 1 : 0)
            return eyesRank * 1_000_000_000 + min(sharpness ?? 0, 999_999_999)
        }
    }

    /// Side of the grayscale render the sharpness is measured on.
    static let sharpnessSide = 256

    /// `personBox`: normalized, origin top-left (the analysis' subject box); nil = whole photo.
    /// `orientation`: how `image` must be turned to be upright.
    static func check(_ image: CGImage, personBox: CGRect? = nil,
                      orientation: CGImagePropertyOrientation = .up, id: String = "") -> Result {
        let result = Result(eyes: eyes(image, orientation: orientation),
                            sharpness: sharpness(image, region: personBox))
        StyleInputs.log.debug("quality \(String(id.prefix(8)), privacy: .public) eyes \(result.eyes.rawValue, privacy: .public) sharpness \(result.sharpness ?? -1, format: .fixed(precision: 1))")
        return result
    }

    /// Eyes of a reference photo, upright as shown.
    @MainActor
    static func eyes(of photo: PhotoItem) -> Eyes {
        guard let image = photo.image.cgImage else { return .unknown }
        return eyes(image, orientation: orientation(of: photo.image.imageOrientation))
    }

    static func orientation(of o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }

    static func eyes(_ image: CGImage, orientation: CGImagePropertyOrientation) -> Eyes {
        guard let detector = CIDetector(ofType: CIDetectorTypeFace, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return .unknown }
        let features = detector.features(in: CIImage(cgImage: image),
                                         options: [CIDetectorEyeBlink: true,
                                                   CIDetectorImageOrientation: Int(orientation.rawValue)])
        let faces = features.compactMap { $0 as? CIFaceFeature }
        guard let face = faces.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }),
              face.hasLeftEyePosition, face.hasRightEyePosition else { return .unknown }
        return face.leftEyeClosed && face.rightEyeClosed ? .closed : .open
    }

    /// Variance of the 4-neighbour Laplacian on a `sharpnessSide` grayscale render of `region`.
    static func sharpness(_ image: CGImage, region: CGRect?) -> Double? {
        var source = image
        if let r = region, r.width > 0, r.height > 0 {
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let rect = CGRect(x: r.minX * w, y: r.minY * h, width: r.width * w, height: r.height * h).integral
            if let cropped = image.cropping(to: rect) { source = cropped }
        }
        let side = sharpnessSide
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var sum = 0.0, sumSquares = 0.0
        var count = 0.0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let i = y * side + x
                let lap = Double(pixels[i - 1]) + Double(pixels[i + 1]) + Double(pixels[i - side])
                    + Double(pixels[i + side]) - 4 * Double(pixels[i])
                sum += lap
                sumSquares += lap * lap
                count += 1
            }
        }
        let mean = sum / count
        return sumSquares / count - mean * mean
    }
}
