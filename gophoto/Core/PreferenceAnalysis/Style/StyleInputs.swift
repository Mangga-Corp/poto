//
//  StyleInputs.swift
//  gophoto
//
//  What the scene rules need besides the analysis: capture date, place and the screenshot flag
//  (from Photos, only for photos picked from the library and only when access is already
//  granted — nothing here asks for permission), and how alike two photos look (Vision
//  FeaturePrint distance). Missing data stays nil: a photo without a date joins a scene only
//  through image similarity.
//  Distances are logged (category "style") so `SceneGrouping.Parameters.maxImageDistance`
//  can be calibrated.
//

import Foundation
import Photos
import UIKit
import Vision
import os

nonisolated struct StyleInputs: Sendable {
    nonisolated struct Meta: Sendable, Equatable {
        var takenAt: Date?
        var latitude: Double?
        var longitude: Double?
        var isScreenshot: Bool
    }

    /// Per photo id (`PhotoItem.id.uuidString`).
    var meta: [String: Meta] = [:]
    /// FeaturePrint distance per pair, key "smaller id|larger id".
    var distances: [String: Double] = [:]

    static let empty = StyleInputs()
    static let log = Logger(subsystem: "co.mango.gophoto", category: "style")

    func distance(_ a: String, _ b: String) -> Double? {
        distances[a < b ? "\(a)|\(b)" : "\(b)|\(a)"]
    }

    /// Reads the photos' metadata and image distances off the main actor.
    @MainActor
    static func collect(_ photos: [PhotoItem]) async -> StyleInputs {
        let items = photos.map { (id: $0.id.uuidString, asset: $0.sourceAssetIdentifier, image: $0.image.cgImage) }
        return await Task.detached(priority: .utility) {
            var inputs = StyleInputs()
            inputs.meta = StyleInputs.metadata(items.compactMap { item in item.asset.map { (id: item.id, asset: $0) } })
            inputs.distances = StyleInputs.featureDistances(items.compactMap { item in item.image.map { (id: item.id, image: $0) } })
            return inputs
        }.value
    }

    /// Date, place and screenshot flag from Photos. Empty without library access.
    static func metadata(_ pairs: [(id: String, asset: String)]) -> [String: Meta] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited, !pairs.isEmpty else { return [:] }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: pairs.map(\.asset), options: nil)
        var byAsset: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byAsset[asset.localIdentifier] = asset }
        var result: [String: Meta] = [:]
        for pair in pairs {
            guard let asset = byAsset[pair.asset] else { continue }
            let coordinate = asset.location?.coordinate
            result[pair.id] = Meta(takenAt: asset.creationDate,
                                   latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                                   isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot))
        }
        return result
    }

    /// FeaturePrint distance for every pair of photos (smaller = more alike).
    static func featureDistances(_ images: [(id: String, image: CGImage)]) -> [String: Double] {
        var prints: [(id: String, print: VNFeaturePrintObservation)] = []
        for item in images {
            let request = VNGenerateImageFeaturePrintRequest()
            do {
                try VNImageRequestHandler(cgImage: item.image, options: [:]).perform([request])
                if let observation = request.results?.first { prints.append((item.id, observation)) }
            } catch {
                StyleInputs.log.debug("featurePrint failed for \(String(item.id.prefix(8)), privacy: .public)")
            }
        }
        var distances: [String: Double] = [:]
        for i in prints.indices {
            for j in prints.indices where j > i {
                var value: Float = 0
                guard (try? prints[i].print.computeDistance(&value, to: prints[j].print)) != nil else { continue }
                let a = prints[i].id, b = prints[j].id
                distances[a < b ? "\(a)|\(b)" : "\(b)|\(a)"] = Double(value)
                StyleInputs.log.debug("featurePrint \(String(a.prefix(8)), privacy: .public)–\(String(b.prefix(8)), privacy: .public) \(value, format: .fixed(precision: 3))")
            }
        }
        return distances
    }
}
