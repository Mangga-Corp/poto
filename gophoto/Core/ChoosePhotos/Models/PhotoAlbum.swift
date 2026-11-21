//
//  PhotoAlbum.swift
//  gophoto
//

import Photos

/// One row of the picker's album list: an album, or a folder of albums, as on the user's iPhone.
/// Built off the main thread; PhotoKit objects are safe to read from any thread.
nonisolated struct PhotoAlbum: @unchecked Sendable {
    enum Content {
        case album(PHAssetCollection)
        case folder([PhotoAlbum])
    }

    let id: String
    let title: String
    /// Photos in an album, albums in a folder.
    let itemCount: Int
    /// Nil for a folder, which shows a folder icon.
    let cover: PHAsset?
    let content: Content
}

nonisolated struct PhotoAlbumSection: Sendable {
    let title: String?
    let albums: [PhotoAlbum]
}
