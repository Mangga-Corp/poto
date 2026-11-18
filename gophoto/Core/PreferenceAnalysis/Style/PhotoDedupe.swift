//
//  PhotoDedupe.swift
//  gophoto
//
//  Mode 2 ("all my photos, alone", 15 Nov): before the heavy analysis, near-identical shots
//  (bursts) are merged so only one of each is analysed, then at most `maxPhotos` are kept,
//  newest first. Cheap: needs only capture dates and FeaturePrint distances (`StyleInputs`).
//  Stricter than a scene: photos of one session with a different composition stay separate.
//

import Foundation

nonisolated enum PhotoDedupe {
    nonisolated struct Parameters: Sendable {
        /// Two photos at most this far apart in time can be one burst.
        var maxSeconds: TimeInterval = 10
        /// …and must look at least this alike (FeaturePrint). Provisional: calibrate from the
        /// `style` log; stricter than `SceneGrouping.Parameters.maxImageDistance`.
        var maxImageDistance = 0.25
        /// Photos analysed after merging (decision 15 Nov).
        var maxPhotos = 100
        static let standard = Parameters()
    }

    nonisolated struct Item: Sendable, Equatable {
        var id: String
        var takenAt: Date?
        /// Higher = better; picks the photo kept from a burst (nil: the newest is kept).
        var quality: Double? = nil
    }

    nonisolated struct Result: Sendable, Equatable {
        /// Photos to analyse (one per burst), newest first, at most `maxPhotos`.
        var kept: [String]
        /// Burst groups of two or more (kept photo first).
        var merged: [[String]]
        /// Kept after merging but beyond `maxPhotos`.
        var dropped: [String]
    }

    static func run(_ items: [Item], parameters p: Parameters = .standard,
                    imageDistance: (String, String) -> Double?) -> Result {
        // Newest first; photos without a date after all dated ones; ties by id.
        let sorted = items.sorted { a, b in
            switch (a.takenAt, b.takenAt) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.id < b.id
            }
        }
        var parent = Array(sorted.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func alike(_ a: Item, _ b: Item) -> Bool {
            guard let d = imageDistance(a.id, b.id), d <= p.maxImageDistance else { return false }
            if let ta = a.takenAt, let tb = b.takenAt { return abs(ta.timeIntervalSince(tb)) <= p.maxSeconds }
            return a.takenAt == nil && b.takenAt == nil      // both undated: the image decides
        }
        for i in sorted.indices {
            for j in sorted.indices where j > i {
                // Dated photos are sorted by time: stop once the gap is too large.
                if let ti = sorted[i].takenAt, let tj = sorted[j].takenAt,
                   ti.timeIntervalSince(tj) > p.maxSeconds { break }
                if alike(sorted[i], sorted[j]) {
                    let a = root(i), b = root(j)
                    parent[max(a, b)] = min(a, b)
                }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in sorted.indices { groups[root(i), default: []].append(i) }
        var keptIndices: [Int] = []
        var merged: [[String]] = []
        for key in groups.keys.sorted() {
            let members = groups[key]!
            // Best quality wins; otherwise the first in order (newest).
            let best = members.max { a, b in
                let qa = sorted[a].quality ?? -.infinity, qb = sorted[b].quality ?? -.infinity
                return qa != qb ? qa < qb : a > b
            }!
            keptIndices.append(best)
            if members.count > 1 {
                merged.append([sorted[best].id] + members.filter { $0 != best }.map { sorted[$0].id })
            }
        }
        keptIndices.sort()
        let kept = keptIndices.prefix(p.maxPhotos).map { sorted[$0].id }
        let dropped = keptIndices.dropFirst(p.maxPhotos).map { sorted[$0].id }
        return Result(kept: kept, merged: merged, dropped: dropped)
    }
}
