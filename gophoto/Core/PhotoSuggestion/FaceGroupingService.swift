//
//  FaceGroupingService.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 14/11/26.
//

import CoreGraphics
import Foundation
import MediaIntelligence
import Photos
import UIKit

nonisolated struct PersonFace: Sendable, Hashable {
    let assetID: String
    let entityID: String
    /// Normalized 0–1, origin top-left (project convention).
    let bounds: CGRect

    /// A face the analyzer could not assign to anyone.
    static let unassigned = ""

    var area: Double { Double(bounds.width * bounds.height) }
}

nonisolated struct PersonGroup: Identifiable, Sendable {
    let id: String
    let faces: [PersonFace]

    var assetIDs: Set<String> { Set(faces.map(\.assetID)) }
    var cover: PersonFace? { faces.max { $0.area < $1.area } }
}

nonisolated struct FaceGroupingProgress: Sendable, Equatable {
    let photosChecked: Int
    let facesFound: Int
}

nonisolated struct FaceGroupingResult: Sendable {
    /// Largest group first.
    let groups: [PersonGroup]
    /// Every face found in a photo, by photo. Used by the solo / main-focus filter.
    let facesByAsset: [String: [PersonFace]]
    /// 512 px copies on disk, used for face crops until `clear()`.
    let thumbnailURLs: [String: URL]
    let photosChecked: Int
    /// Library photos checked in this run (anchors excluded), newest first.
    let checkedIDs: [String]
    /// Anchors that were actually scanned (thumbnail exported).
    let anchorIDs: [String]
    /// Newest / oldest date among `checkedIDs`.
    let newestChecked: Date?
    let oldestChecked: Date?
    /// Photos still not checked after this run (they wait for the next run).
    let remaining: Int
}

nonisolated enum FaceGroupingError: Error {
    case unavailable
}

nonisolated protocol FaceGrouping: Sendable {
    /// Scans up to `maxPhotos` photos not in `checked` (newest first), plus the `anchors`
    /// (already-known photos of the person, see `FaceScanMatch`).
    func scan(maxFaces: Int, maxPhotos: Int, skipping checked: Set<String>, anchors: [String],
              onProgress: @escaping @Sendable (FaceGroupingProgress) -> Void) async throws -> FaceGroupingResult
    /// Deletes every face and thumbnail this scan produced.
    func clear() async
}

@available(iOS 27.0, *)
nonisolated final class FaceGroupAnalyzerService: FaceGrouping {
    static let thumbnailSide: CGFloat = 512
    static let batchSize = 25
    // No time limit (Reynard, 17 Nov): a deadline made the scanned set depend on how fast the
    // phone was that day, so the same person got a different photo set each time.

    private static let directory = URL.cachesDirectory
        .appending(path: "FaceGroupData", directoryHint: .isDirectory)
    private static let imagesDirectory = directory
        .appending(path: "images", directoryHint: .isDirectory)

    /// One analyzer per process: a second live instance crashes the framework.
    private static let analyzer: FaceGroupAnalyzer? = {
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        return try? FaceGroupAnalyzer(workingDirectory: directory)
    }()

    /// Call once at app launch, before any analyzer exists: removes data a crash left behind.
    static func purgeLeftovers() async {
        try? await FaceGroupAnalyzer.purge(workingDirectory: directory)
        try? FileManager.default.removeItem(at: imagesDirectory)

    }

    @concurrent
    func scan(maxFaces: Int, maxPhotos: Int, skipping checked: Set<String>, anchors: [String],
              onProgress: @escaping @Sendable (FaceGroupingProgress) -> Void) async throws -> FaceGroupingResult {
        guard let analyzer = Self.analyzer else { throw FaceGroupingError.unavailable }
        await clear()

        // Photos not checked yet: favourites first, then the rest, each newest first (17 Nov).
        // At most `maxPhotos` this run, the rest next run.
        let assets = Self.candidateAssets()
        var favorites: [PHAsset] = []
        var others: [PHAsset] = []
        var unchecked = 0
        assets.enumerateObjects { asset, _, _ in
            guard !checked.contains(asset.localIdentifier) else { return }
            unchecked += 1
            if asset.isFavorite {
                favorites.append(asset)
            } else if others.count < maxPhotos {
                others.append(asset)
            }
        }
        let queue = Array((favorites + others).prefix(maxPhotos))
        guard !queue.isEmpty else {
            return FaceGroupingResult(groups: [], facesByAsset: [:], thumbnailURLs: [:], photosChecked: 0,
                                      checkedIDs: [], anchorIDs: [], newestChecked: nil, oldestChecked: nil,
                                      remaining: 0)
        }
        let selfies = Self.selfieIDs()
        let anchorSet = Set(anchors)
        let order = PhotoAssets.ordered(anchors) + queue.filter { !anchorSet.contains($0.localIdentifier) }
        var thumbnailURLs: [String: URL] = [:]
        var checkedIDs: [String] = []
        var anchorIDs: [String] = []
        var newest: Date?
        var oldest: Date?
        var facesFound = 0
        var position = 0

        while position < order.count, facesFound < maxFaces {
            try Task.checkCancellation()
            var batch: [MediaIntelligenceImageAsset] = []
            while batch.count < Self.batchSize, position < order.count {
                let asset = order[position]
                position += 1
                let id = asset.localIdentifier
                let isAnchor = anchorSet.contains(id)
                if !isAnchor {
                    checkedIDs.append(id)
                    if let date = asset.creationDate {
                        newest = max(newest ?? date, date)
                        oldest = min(oldest ?? date, date)
                    }
                    if selfies.contains(id) { continue }   // front camera: not how others photograph you
                }
                guard let url = await Self.exportThumbnail(for: asset) else { continue }
                thumbnailURLs[id] = url
                if isAnchor { anchorIDs.append(id) }
                batch.append(MediaIntelligenceImageAsset(id: .init(id), kind: .url(url)))
            }
            guard !batch.isEmpty else { continue }
            for try await (_, faces) in try await analyzer.insertOrUpdateAssets(batch) {
                facesFound += faces.count
            }
            onProgress(FaceGroupingProgress(photosChecked: checkedIDs.count, facesFound: facesFound))
        }

        try Task.checkCancellation()
        if await analyzer.state == .stale {
            try await analyzer.update(subprogress: nil)
        }

        var groups: [PersonGroup] = []
        for try await (entityID, faces) in analyzer.allFacesByEntityID {
            let id = String(describing: entityID)
            groups.append(PersonGroup(id: id, faces: faces.map { Self.personFace($0, entityID: id) }))
        }
        groups.sort { ($0.assetIDs.count, $0.id) > ($1.assetIDs.count, $1.id) }

        var facesByAsset: [String: [PersonFace]] = [:]
        for try await face in analyzer.allFaces {
            let id = face.entityID.map { String(describing: $0) } ?? PersonFace.unassigned
            let converted = Self.personFace(face, entityID: id)
            facesByAsset[converted.assetID, default: []].append(converted)
        }

        return FaceGroupingResult(groups: groups, facesByAsset: facesByAsset,
                                  thumbnailURLs: thumbnailURLs, photosChecked: checkedIDs.count,
                                  checkedIDs: checkedIDs, anchorIDs: anchorIDs,
                                  newestChecked: newest, oldestChecked: oldest,
                                  remaining: unchecked - checkedIDs.count)
    }

    @concurrent
    func clear() async {
        try? await Self.analyzer?.deleteAllAssets()
        try? FileManager.default.removeItem(at: Self.imagesDirectory)
        try? FileManager.default.createDirectory(at: Self.imagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Photos

    private static func candidateAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let skipped = PHAssetMediaSubtype.photoScreenshot.rawValue | PHAssetMediaSubtype.photoPanorama.rawValue
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) == 0", skipped)
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    /// Photos' own Selfies album (front camera). Skipped before export, so they cost no time.
    private static func selfieIDs() -> Set<String> {
        var ids = Set<String>()
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                             subtype: .smartAlbumSelfPortraits, options: nil)
        albums.enumerateObjects { album, _, _ in
            PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
        }
        return ids
    }

    private static func exportThumbnail(for asset: PHAsset) async -> URL? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let side = CGSize(width: thumbnailSide, height: thumbnailSide)
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: side,
                                                  contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let data = image?.jpegData(compressionQuality: 0.9) else { return nil }
        let url = imagesDirectory.appending(path: fileName(for: asset.localIdentifier) + ".jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// localIdentifiers contain "/" → safe file name.
    private static func fileName(for assetID: String) -> String {
        Data(assetID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    // MARK: - Conversion

    private static func personFace(_ face: FaceGroupAnalyzer.Face, entityID: String) -> PersonFace {
        let box = face.bounds
        let topLeft = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        return PersonFace(assetID: face.assetID.rawValue,
                          entityID: entityID, bounds: topLeft)
    }

}
