//
//  SceneGrouping.swift
//  gophoto
//
//  One scene = same day + close place (or close time when there is no place) + similar image.
//  A scene votes once, however many photos it has (burst shots do not outvote other days).
//  Photos without a capture date (WhatsApp, downloads, screenshots without metadata) can only
//  join a scene through image similarity.
//

import Foundation

nonisolated enum SceneGrouping {
    nonisolated struct Parameters: Sendable {
        var maxMeters = 100.0
        var maxSeconds: TimeInterval = 3600
        /// Image distance (FeaturePrint) at or below which two photos look alike.
        /// Provisional: log the distances and calibrate.
        var maxImageDistance = 0.5
        static let standard = Parameters()
    }

    /// Scene index per photo id. Indices follow the photos sorted by id, so the result does not
    /// depend on the upload order. `imageDistance` returns nil when it could not be measured.
    static func group(_ photos: [StylePhoto], parameters p: Parameters = .standard,
                      imageDistance: (String, String) -> Double?) -> [String: Int] {
        let sorted = photos.sorted { $0.id < $1.id }
        var parent = Array(sorted.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in sorted.indices {
            for j in sorted.indices where j > i {
                if sameScene(sorted[i], sorted[j], imageDistance: imageDistance(sorted[i].id, sorted[j].id), p) {
                    let a = root(i), b = root(j)
                    parent[max(a, b)] = min(a, b)
                }
            }
        }
        var index: [Int: Int] = [:]
        var result: [String: Int] = [:]
        for i in sorted.indices {
            let r = root(i)
            if index[r] == nil { index[r] = index.count }
            result[sorted[i].id] = index[r]
        }
        return result
    }

    static func sameScene(_ a: StylePhoto, _ b: StylePhoto, imageDistance: Double?,
                          _ p: Parameters = .standard) -> Bool {
        let similar = imageDistance.map { $0 <= p.maxImageDistance }
        guard let ta = a.takenAt, let tb = b.takenAt else {
            return similar ?? false                       // no date: only the image can join them
        }
        guard Calendar(identifier: .gregorian).isDate(ta, inSameDayAs: tb) else { return false }
        let close: Bool
        if let la = a.latitude, let lo = a.longitude, let lb = b.latitude, let lob = b.longitude {
            close = meters(la, lo, lb, lob) <= p.maxMeters
        } else {
            close = abs(ta.timeIntervalSince(tb)) <= p.maxSeconds
        }
        guard close else { return false }
        return similar ?? true                            // no image check: time and place decide
    }

    /// Great-circle distance (haversine), metres.
    static func meters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0, rad = Double.pi / 180
        let dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * rad) * cos(lat2 * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, h.squareRoot()))
    }
}
