//
//  LensMetadataReader.swift
//  AIModel
//
//  Created by Laurentius Brandon Vikario on 20/10/26.
//


import Foundation
import ImageIO

/// Reads the lens a photo was taken with from its EXIF metadata.
///
/// WHY. Turning "the eyes sit 20% below centre" into degrees needs the focal
/// length. Without it the camera-angle analysis must allow for every phone-like
/// lens (`LensAssumption.unknown`), and photos near a category boundary end up
/// "unknown". Most iPhone photos record their 35 mm-equivalent focal length.
///
/// The picker hands over the original file data, which keeps EXIF; the decoded
/// `UIImage` does not. No photo-library permission is needed.
nonisolated enum LensMetadataReader {

    /// The 35 mm-equivalent focal length in millimetres, or nil when the data
    /// is not an image or carries no such tag.
    static func focalLength35mm(imageData: Data) -> Double? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        else { return nil }
        return focalLength35mm(exif: exif)
    }

    /// The focal length and whether the front camera took the photo, from one read of the data
    /// (18 Nov: selfies are left out of a preference). nil = not an image, or no EXIF.
    static func read(imageData: Data) -> (focal35mm: Double?, isFrontCamera: Bool?) {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        else { return (nil, nil) }
        return (focalLength35mm(exif: exif), isFrontCamera(exif: exif))
    }

    /// From the EXIF lens name, e.g. "iPhone 15 Pro front camera 2.69mm f/1.9". nil = no lens name.
    static func isFrontCamera(exif: [CFString: Any]) -> Bool? {
        (exif[kCGImagePropertyExifLensModel] as? String).map { $0.localizedCaseInsensitiveContains("front") }
    }

    /// From an EXIF dictionary. Only the explicit 35 mm-equivalent tag is used:
    /// the raw focal length needs the sensor size, which EXIF rarely states.
    static func focalLength35mm(exif: [CFString: Any]) -> Double? {
        guard let value = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.doubleValue,
              LensAssumption.plausibleMM.contains(value) else { return nil }
        return value
    }
}
