//
//  StyleGrouping.swift
//  gophoto
//
//  Groups the photos of ONE shot size into styles with complete linkage: two groups merge only
//  while no pair of photos in the merged group is opposing (`StyleLimits`). Unlike chaining on
//  nearest neighbours, 0°, 4°, 8° (limit 6°) cannot end up in one style through the middle photo.
//  Afterwards every photo is checked against every style: a photo that fits more than one style
//  (typically one missing the dimension the styles differ on) is "shared" and splits its vote.
//

import Foundation

nonisolated struct StyleGroups: Sendable, Equatable {
    /// Photo ids per style, each sorted by id; styles ordered by their smallest id.
    var styles: [[String]]
    /// Photos that fit more than one style → the style indices they fit.
    var shared: [String: [Int]]

    /// Styles a photo counts for: its own, or all it fits when shared.
    func styles(of id: String) -> [Int] {
        if let fits = shared[id] { return fits }
        return styles.firstIndex { $0.contains(id) }.map { [$0] } ?? []
    }
}

nonisolated enum StyleGrouping {
    static func group(_ photos: [StylePhoto], limits: StyleLimits = .standard) -> StyleGroups {
        let sorted = photos.sorted { $0.id < $1.id }
        guard !sorted.isEmpty else { return StyleGroups(styles: [], shared: [:]) }
        var groups: [[Int]] = sorted.indices.map { [$0] }

        // Largest pairwise distance between two groups, nil when they contain an opposing pair.
        func linkage(_ a: [Int], _ b: [Int]) -> Double? {
            var worst = 0.0
            for i in a {
                for j in b {
                    let d = limits.distance(sorted[i], sorted[j])
                    guard d.shared > 0 else { continue }
                    if d.value >= 1 { return nil }
                    worst = max(worst, d.value)
                }
            }
            return worst
        }

        while groups.count > 1 {
            var best: (a: Int, b: Int, d: Double)?
            for a in groups.indices {
                for b in groups.indices where b > a {
                    guard let d = linkage(groups[a], groups[b]) else { continue }
                    // Ties: the pair whose smallest members come first (deterministic, by id).
                    if best == nil || d < best!.d { best = (a, b, d) }
                }
            }
            guard let merge = best else { break }
            groups[merge.a] = (groups[merge.a] + groups[merge.b]).sorted()
            groups.remove(at: merge.b)
        }
        groups.sort { $0[0] < $1[0] }
        let styles = groups.map { $0.map { sorted[$0].id } }

        // A photo fits a style when it opposes none of the style's other members.
        var shared: [String: [Int]] = [:]
        for photo in sorted {
            let fits = groups.indices.filter { s in
                groups[s].allSatisfy { m in sorted[m].id == photo.id || !limits.opposing(sorted[m], photo) }
            }
            if fits.count > 1 { shared[photo.id] = fits }
        }
        return StyleGroups(styles: styles, shared: shared)
    }
}
