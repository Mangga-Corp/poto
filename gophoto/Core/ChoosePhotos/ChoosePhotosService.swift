//
//  ChoosePhotos.swift
//  gophoto
//
//  Created by Sebastian Darren on 12/10/26.
//

import Photos
import UIKit

final class ChoosePhotosService {
    private let imageManager = PHCachingImageManager()

    var access: ChoosePhotosAccess { Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }

    func requestAccess(completion: @escaping (ChoosePhotosAccess) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { completion(Self.map(status)) }
        }
    }

    // MARK: - Albums

    /// The system albums that can hold photos, in the order of the Photos app. Video-only albums are left out.
    nonisolated private static let smartAlbumOrder: [PHAssetCollectionSubtype] = [
        .smartAlbumUserLibrary, .smartAlbumFavorites, .smartAlbumLivePhotos, .smartAlbumDepthEffect,
        .smartAlbumRecentlyAdded, .smartAlbumSelfPortraits, .smartAlbumPanoramas, .smartAlbumSpatial,
        .smartAlbumBursts, .smartAlbumLongExposures, .smartAlbumAnimated, .smartAlbumRAW,
        .smartAlbumScreenshots,
    ]

    /// Shared albums live outside the user's library, so every picker fetch asks for them explicitly.
    nonisolated private static let pickerSourceTypes: PHAssetSourceType = [
        .typeUserLibrary, .typeCloudShared, .typeiTunesSynced,
    ]

    /// The albums on this iPhone. Empty ones are left out (with limited access, most albums are).
    /// Slow on a large library: call it off the main thread.
    nonisolated static func fetchAlbumSections() -> [PhotoAlbumSection] {
        let system = smartAlbumOrder.compactMap { subtype -> PhotoAlbum? in
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                .firstObject.flatMap(makeAlbum)
        }

        let topLevel = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        var userCollections = topLevel.objects(at: IndexSet(integersIn: 0..<topLevel.count))
        var seen = Set(userCollections.map(\.localIdentifier))
        for subtype: PHAssetCollectionSubtype in [.albumSyncedEvent, .albumSyncedFaces, .albumSyncedAlbum, .albumImported] {
            let synced = PHAssetCollection.fetchAssetCollections(with: .album, subtype: subtype, options: nil)
            synced.enumerateObjects { album, _, _ in
                if seen.insert(album.localIdentifier).inserted { userCollections.append(album) }
            }
        }
        let mine = userCollections.compactMap(makeAlbum)

        let sharedResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil)
        let shared = sharedResult.objects(at: IndexSet(integersIn: 0..<sharedResult.count)).compactMap(makeAlbum)

        return [
            PhotoAlbumSection(title: nil, albums: system),
            PhotoAlbumSection(title: "My Albums", albums: mine),
            PhotoAlbumSection(title: "Shared Albums", albums: shared),
        ].filter { !$0.albums.isEmpty }
    }

    nonisolated private static func makeAlbum(_ collection: PHCollection) -> PhotoAlbum? {
        let title = collection.localizedTitle ?? "Untitled"
        if let album = collection as? PHAssetCollection {
            let assets = fetchAssets(in: album)
            guard let cover = assets.firstObject else { return nil }
            return PhotoAlbum(id: album.localIdentifier, title: title, itemCount: assets.count,
                              cover: cover, content: .album(album))
        }
        guard let folder = collection as? PHCollectionList else { return nil }
        let children = PHCollection.fetchCollections(in: folder, options: nil)
        let albums = children.objects(at: IndexSet(integersIn: 0..<children.count)).compactMap(makeAlbum)
        guard !albums.isEmpty else { return nil }
        return PhotoAlbum(id: folder.localIdentifier, title: title, itemCount: albums.count,
                          cover: nil, content: .folder(albums))
    }

    /// The album's photos. System albums show newest first; the recently added album and the
    /// user's own albums keep the order they have in the Photos app.
    nonisolated static func fetchAssets(in album: PHAssetCollection) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.includeAssetSourceTypes = pickerSourceTypes
        if album.assetCollectionType == .smartAlbum, album.assetCollectionSubtype != .smartAlbumRecentlyAdded {
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        }
        return PHAsset.fetchAssets(in: album, options: options)
    }

    /// The photos with these identifiers that are still available, newest first.
    nonisolated static func fetchAssets(identifiers: [String]) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = pickerSourceTypes
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: options)
    }

    @discardableResult
    func thumbnail(for asset: PHAsset, side: CGFloat, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        return imageManager.requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                         contentMode: .aspectFill, options: options) { image, _ in
            DispatchQueue.main.async { completion(image) }
        }
    }

    func cancel(_ id: PHImageRequestID) { imageManager.cancelImageRequest(id) }

    /// Loads selected assets (max 1024 px) in the same order as `assets`.
    /// A few at a time, each written to disk as JPG, so they are not all held decoded in memory.
    func loadItems(for assets: [PHAsset], completion: @escaping (Result<[PhotoItem], Error>) -> Void) {
        let ids = assets.map(\.localIdentifier)
        Task {
            let loaded = await Self.loadWindowed(ids)
            var items: [PhotoItem] = []
            for (id, photo) in zip(ids, loaded) {
                guard let photo, let image = UncachedImage.load(contentsOf: photo.url) else {
                    completion(.failure(PhotoError.loadFailed))
                    return
                }
                var item = PhotoItem(image: image, sourceAssetIdentifier: id)
                // Only an uncropped 4:3 frame keeps the EXIF field of view.
                let w = image.size.width, h = image.size.height
                let aspect = max(w, h) / max(min(w, h), 1)
                if let focal = photo.focal, abs(aspect - 4.0 / 3.0) < 0.02 { item.focalLength35mm = focal }
                item.isFrontCamera = photo.isFrontCamera
                items.append(item)
            }
            completion(.success(items))
        }
    }

    // MARK: - Sliding window (18 Nov)

    nonisolated struct LoadedPhoto: Sendable {
        let url: URL
        let focal: Double?
        let isFrontCamera: Bool?
    }

    /// Picked photos as JPG files, so they are not all held decoded in memory.
    nonisolated static let pickedFolder = URL.applicationSupportDirectory
        .appending(path: "PickedPhotos", directoryHint: .isDirectory)

    /// Photos loaded at the same time: 10, or 4 on phones with ≤ 4.5 GB of memory.
    nonisolated static func loadWindow() -> Int {
        ProcessInfo.processInfo.physicalMemory <= 4_831_838_208 ? 4 : 10
    }

    /// Results in the order of `ids`; nil = that photo could not be loaded.
    nonisolated static func loadWindowed(_ ids: [String]) async -> [LoadedPhoto?] {
        let folder = pickedFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        removeOldPickedFiles(in: folder)
        var results = [LoadedPhoto?](repeating: nil, count: ids.count)
        await withTaskGroup(of: (Int, LoadedPhoto?).self) { group in
            var next = 0
            func addNext() {
                guard next < ids.count else { return }
                let index = next, id = ids[index]
                next += 1
                group.addTask { (index, await Self.loadOne(id, into: folder)) }
            }
            for _ in 0..<Self.loadWindow() { addNext() }
            while let result = await group.next() {
                results[result.0] = result.1
                addNext()
            }
        }
        return results
    }

    /// One photo: 1024 px image → JPG on disk, plus the EXIF focal length (the original data is
    /// dropped right after). Nothing of it stays in memory after this returns.
    nonisolated private static func loadOne(_ id: String, into folder: URL) async -> LoadedPhoto? {
        guard let asset = fetchAssets(identifiers: [id]).firstObject else { return nil }
        let manager = PHImageManager.default()

        let jpeg: Data
        do {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            let image: UIImage? = await withCheckedContinuation { continuation in
                manager.requestImage(for: asset, targetSize: CGSize(width: 1024, height: 1024),
                                     contentMode: .aspectFit, options: options) { image, info in
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    continuation.resume(returning: image)
                }
            }
            // Encoding leaves autoreleased buffers behind. On Swift's task threads they are only freed
            // when the thread goes idle, so without a pool they pile up until every photo is loaded.
            let encoded = autoreleasepool { image?.jpegData(compressionQuality: 0.9) }
            guard let data = encoded else { return nil }
            jpeg = data
        }

        // EXIF focal length (camera-vs-eyes angle) and front camera (selfie). Optional: a failure is ignored.
        let dataOptions = PHImageRequestOptions()
        dataOptions.isNetworkAccessAllowed = true
        let lens: (focal35mm: Double?, isFrontCamera: Bool?) = await withCheckedContinuation { continuation in
            manager.requestImageDataAndOrientation(for: asset, options: dataOptions) { data, _, _, _ in
                continuation.resume(returning: data.map { LensMetadataReader.read(imageData: $0) } ?? (nil, nil))
            }
        }

        let url = folder.appending(path: UUID().uuidString + ".jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return LoadedPhoto(url: url, focal: lens.focal35mm, isFrontCamera: lens.isFrontCamera)
    }

    /// Files from earlier picks (older than a day). Recent ones may still be on screen.
    nonisolated private static func removeOldPickedFiles(in folder: URL) {
        let manager = FileManager.default
        let dayAgo = Date.now.addingTimeInterval(-86_400)
        let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < dayAgo { try? manager.removeItem(at: file) }
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> ChoosePhotosAccess {
        switch status {
        case .authorized: return .authorized
        case .limited: return .limited
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}
