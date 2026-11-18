//
//  PhotoItem.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

struct PhotoItem {
    let id: UUID
    let image: UIImage
    let sourceAssetIdentifier: String?
    /// 35 mm-equivalent focal length from the original photo's EXIF, when it has one and the
    /// photo still has the camera's 4:3 frame (a crop changes the field of view).
    var focalLength35mm: Double?
    /// From the original photo's EXIF lens name: true = front camera (a selfie, left out by the
    /// person check). nil = unknown (no EXIF, or a photo saved before 18 Nov).
    var isFrontCamera: Bool?

    init(
        id: UUID = UUID(),
        image: UIImage,
        sourceAssetIdentifier: String? = nil,
        focalLength35mm: Double? = nil,
        isFrontCamera: Bool? = nil
    ) {
        self.id = id
        self.image = image
        self.sourceAssetIdentifier = sourceAssetIdentifier
        self.focalLength35mm = focalLength35mm
        self.isFrontCamera = isFrontCamera
    }
}
