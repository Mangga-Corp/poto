//
//  StyleBracket.swift
//  gophoto
//
//  Mode 2 (15 Nov): no votes (how often a style appears says how the photographers shot, not
//  what the user likes), so the user picks among the shot size's styles in a short knockout.
//  At most 7 candidates and 3 questions. Balanced: no style has to win more than twice.
//    1–3 styles: one question (A/B or A/B/C)          4: AB, CD, final
//    5: ABC, DE, final                                6: ABC, DEF, final
//    7: ABC, DEF, final of both winners + one style drawn at random (the bye)
//  More than 7 styles: the 7 most different from each other are kept (geometry, not counts).
//

import Foundation

nonisolated enum StyleBracketPlan {
    static let maxCandidates = 7

    /// Up to `maxCandidates` style indices, chosen for variety: start with the two styles whose
    /// targets are farthest apart, then repeatedly add the style farthest from those chosen.
    /// `targets[i]`: the measured target photo of style i (nil: cannot be compared).
    static func candidates(_ targets: [StylePhoto?], limits: StyleLimits = .standard) -> [Int] {
        let usable = targets.indices.filter { targets[$0] != nil }
        guard usable.count > maxCandidates else { return usable }
        func d(_ a: Int, _ b: Int) -> Double { limits.distance(targets[a]!, targets[b]!).value }
        var best = (usable[0], usable[1], -1.0)
        for a in usable { for b in usable where b > a { let v = d(a, b); if v > best.2 { best = (a, b, v) } } }
        var chosen = [best.0, best.1]
        while chosen.count < maxCandidates {
            let next = usable.filter { !chosen.contains($0) }
                .max { a, b in
                    let da = chosen.map { d(a, $0) }.min()!, db = chosen.map { d(b, $0) }.min()!
                    return da != db ? da < db : a > b
                }!
            chosen.append(next)
        }
        return chosen.sorted()
    }

    /// First-round groups for `count` candidates (positions 0..<count), and the bye (7 only).
    static func shape(_ count: Int) -> (groups: [[Int]], bye: Int?) {
        switch count {
        case ..<2: return ([], nil)
        case 2, 3: return ([Array(0..<count)], nil)
        case 4: return ([[0, 1], [2, 3]], nil)
        case 5: return ([[0, 1, 2], [3, 4]], nil)
        case 6: return ([[0, 1, 2], [3, 4, 5]], nil)
        default: return ([[0, 1, 2], [3, 4, 5]], 6)
        }
    }
}

/// One knockout over a shot size's candidate styles. Feed the user's answers with `answer`.
nonisolated struct StyleBracket: Codable, Sendable, Equatable {
    /// Questions still to ask, each a list of style indices (shown in random order by the UI).
    private(set) var pending: [[Int]]
    private var winners: [Int] = []
    private var bye: Int?
    private var finalStarted = false
    private(set) var champion: Int?
    /// Questions asked so far (≤ 3).
    private(set) var asked = 0

    /// `styles`: the candidate style indices. The order in the bracket (and the bye) is drawn
    /// with `generator` so no position is favoured.
    init<G: RandomNumberGenerator>(styles: [Int], generator: inout G) {
        let order = styles.shuffled(using: &generator)
        let shape = StyleBracketPlan.shape(order.count)
        pending = shape.groups.map { $0.map { order[$0] } }
        bye = shape.bye.map { order[$0] }
        if order.count == 1 { champion = order[0] }
        if shape.groups.count == 1 { finalStarted = true }
    }

    init(styles: [Int]) {
        var g = SystemRandomNumberGenerator()
        self.init(styles: styles, generator: &g)
    }

    /// The styles to show now, or nil when the bracket is decided.
    var current: [Int]? { champion == nil ? pending.first : nil }

    /// Records the style picked in the current question.
    mutating func answer(_ style: Int) {
        guard let question = current, question.contains(style) else { return }
        pending.removeFirst()
        asked += 1
        if finalStarted {
            champion = style
            return
        }
        winners.append(style)
        if pending.isEmpty {
            finalStarted = true
            pending = [winners + (bye.map { [$0] } ?? [])]
        }
    }
}
