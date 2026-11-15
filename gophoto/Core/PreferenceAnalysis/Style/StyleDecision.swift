//
//  StyleDecision.swift
//  gophoto
//
//  Which style becomes the preset of one shot size, and its target photo.
//  Votes: each scene has one vote, split equally over the styles present in it (1/k).
//  Clear (no question): total ≥ 5 votes AND top / sum of the others ≥ 1.75. Otherwise ONE final
//  question "Which style do you want as your preset?"; the answer decides. One style → no
//  question. These are starting product rules, not statistical proof (provisional).
//  Target: in each scene, the winning style's photo closest to the others (scene medoid); the
//  target is the medoid of those scene representatives, so a scene with ten photos is one point.
//

import Foundation

nonisolated enum StyleDecision {
    nonisolated struct Rules: Sendable {
        var minVotes = 5.0
        var minRatio = 1.75
        static let standard = Rules()
    }

    nonisolated enum Outcome: Sendable, Equatable {
        case none
        /// Only one style: no question.
        case single(Int)
        /// Clear winner by votes.
        case clear(Int)
        /// Ask once; candidates by votes, most first (show three, the rest on request).
        case ask([Int])
    }

    /// Votes per style.
    static func votes(_ groups: StyleGroups, sceneOf: [String: Int]) -> [Double] {
        var stylesInScene: [Int: Set<Int>] = [:]
        for id in groups.styles.flatMap({ $0 }) {
            guard let scene = sceneOf[id] else { continue }
            stylesInScene[scene, default: []].formUnion(groups.styles(of: id))
        }
        var votes = Array(repeating: 0.0, count: groups.styles.count)
        for styles in stylesInScene.values where !styles.isEmpty {
            for s in styles { votes[s] += 1 / Double(styles.count) }
        }
        return votes
    }

    static func decide(votes: [Double], rules: Rules = .standard) -> Outcome {
        switch votes.count {
        case 0: return .none
        case 1: return .single(0)
        default: break
        }
        let order = votes.indices.sorted { votes[$0] != votes[$1] ? votes[$0] > votes[$1] : $0 < $1 }
        let top = votes[order[0]]
        let others = votes.reduce(0, +) - top
        let total = top + others
        if total >= rules.minVotes, others == 0 || top / others >= rules.minRatio {
            return .clear(order[0])
        }
        return .ask(order)
    }

    /// Scene representatives of `style` and the target (their medoid). `preferred`: a photo the
    /// user picked in the question wins ties.
    static func target(style: Int, groups: StyleGroups, photos: [StylePhoto], sceneOf: [String: Int],
                       limits: StyleLimits = .standard, preferred: String? = nil)
        -> (target: String, representatives: [String])? {
        guard groups.styles.indices.contains(style) else { return nil }
        let byID = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Members of the style: its own photos first; shared photos only when it has none.
        let own = groups.styles[style].filter { groups.shared[$0] == nil }
        let members = (own.isEmpty ? groups.styles[style] : own).compactMap { byID[$0] }
        guard !members.isEmpty else { return nil }

        var scenes: [Int: [StylePhoto]] = [:]
        for photo in members { scenes[sceneOf[photo.id] ?? -1, default: []].append(photo) }
        let reps = scenes.keys.sorted().compactMap { medoid(scenes[$0]!, limits: limits, preferred: preferred) }
        guard let target = medoid(reps, limits: limits, preferred: preferred) else { return nil }
        return (target.id, reps.map(\.id))
    }

    /// The photo with the smallest summed distance to the others. Ties: the preferred photo,
    /// then higher quality, then the smaller id.
    static func medoid(_ photos: [StylePhoto], limits: StyleLimits = .standard,
                       preferred: String? = nil) -> StylePhoto? {
        guard photos.count > 1 else { return photos.first }
        func cost(_ p: StylePhoto) -> Double {
            photos.reduce(0) { $0 + ($1.id == p.id ? 0 : limits.distance(p, $1).value) }
        }
        return photos.min { a, b in
            let ca = cost(a), cb = cost(b)
            if abs(ca - cb) > 1e-9 { return ca < cb }
            if (a.id == preferred) != (b.id == preferred) { return a.id == preferred }
            let qa = a.quality ?? -.infinity, qb = b.quality ?? -.infinity
            if qa != qb { return qa > qb }
            return a.id < b.id
        }
    }

    /// NOT USED (decision 15 Nov: the guide tolerance is never widened from the photos' spread).
    /// Largest deviation of the representatives from the target per dimension, only with at least
    /// `minScenes` representatives (fewer: nil → the guide keeps its default tolerance). Stage 2
    /// clamps it between the guide's default and the opposing limit.
    nonisolated struct Spread: Sendable, Equatable {
        var vantageFaces: Double? = nil
        var pitchDegrees: Double? = nil
        var centreX: Double? = nil
        /// Ratio ≥ 1 (largest / target or target / smallest).
        var sizeRatio: Double? = nil
    }

    static func spread(target: StylePhoto, representatives: [StylePhoto], minScenes: Int = 3) -> Spread? {
        guard representatives.count >= minScenes else { return nil }
        func dev(_ key: KeyPath<StylePhoto, Double?>) -> Double? {
            guard let t = target[keyPath: key] else { return nil }
            let values = representatives.compactMap { $0[keyPath: key] }
            return values.isEmpty ? nil : values.map { abs($0 - t) }.max()
        }
        var s = Spread(vantageFaces: dev(\.vantageFaces), pitchDegrees: dev(\.pitchDegrees),
                       centreX: dev(\.centreX))
        if let t = target.size, t > 0 {
            let ratios = representatives.compactMap(\.size).filter { $0 > 0 }.map { max($0 / t, t / $0) }
            s.sizeRatio = ratios.max()
        }
        return s
    }
}
