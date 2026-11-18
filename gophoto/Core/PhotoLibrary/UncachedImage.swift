//
//  UncachedImage.swift
//  gophoto
//
//  A UIImage read from a file that never keeps its decoded pixels (18 Nov, Reynard).
//  `UIImage(contentsOfFile:)` keeps the decoded bitmap (~3 MB at 1024 px) once the image is
//  drawn, encoded or read as a CGImage, for as long as the UIImage lives. With 100–200 picked
//  photos held as `PhotoItem`, every pass over them (save, person check, analysis) left all of
//  them decoded. This image decodes again each time it is used and frees the pixels after.
//

import ImageIO
import UIKit

nonisolated enum UncachedImage {
    /// nil when the file is missing or is not an image.
    static func load(contentsOf url: URL) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
        // CGImageSource does not apply the EXIF orientation; UIImage does when it draws.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = (properties?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation(exif))
    }

    private static func orientation(_ exif: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch exif {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        }
    }
}
