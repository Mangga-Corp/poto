//
//  GuidanceBlockArrow.swift
//  gophoto
//
//  The straight guidance arrow: two blocks and a head. A wave runs from the tail to the tip,
//  over and over.
//

import SwiftUI

struct GuidanceBlockArrow: View {
    let pointsUp: Bool
    let color: Color
    /// False (Reduce Motion): the whole arrow, fully lit, nothing moves.
    var isAnimated = true

    private static let cycle: Double = 1.35
    private static let dimmedOpacity = 0.35

    // Proportions of the design, as shares of the arrow's size (measured from the tip).
    private static let headLength: CGFloat = 0.285
    private static let stemEnd: CGFloat = 0.485
    private static let middleBlock: ClosedRange<CGFloat> = 0.535...0.745
    private static let tailBlock: ClosedRange<CGFloat> = 0.795...1
    private static let stemWidth: CGFloat = 0.70

    var body: some View {
        Group {
            if isAnimated {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    arrow(phase: time.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle)
                }
            } else {
                arrow(phase: nil)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func arrow(phase: Double?) -> some View {
        Canvas { context, size in
            if !pointsUp {
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
            }
            let stemInset = size.width * (1 - Self.stemWidth) / 2

            func block(_ range: ClosedRange<CGFloat>) -> Path {
                Path(CGRect(x: stemInset, y: size.height * range.lowerBound,
                            width: size.width - 2 * stemInset,
                            height: size.height * (range.upperBound - range.lowerBound)))
            }

            var head = Path()
            head.move(to: CGPoint(x: size.width / 2, y: 0))
            head.addLine(to: CGPoint(x: size.width, y: size.height * Self.headLength))
            head.addLine(to: CGPoint(x: size.width - stemInset, y: size.height * Self.headLength))
            head.addLine(to: CGPoint(x: size.width - stemInset, y: size.height * Self.stemEnd))
            head.addLine(to: CGPoint(x: stemInset, y: size.height * Self.stemEnd))
            head.addLine(to: CGPoint(x: stemInset, y: size.height * Self.headLength))
            head.addLine(to: CGPoint(x: 0, y: size.height * Self.headLength))
            head.closeSubpath()

            // Tail to tip, the order the wave travels.
            let parts: [(path: Path, start: Double, end: Double)] = [
                (block(Self.tailBlock), 0, 0.3),
                (block(Self.middleBlock), 0.3, 0.6),
                (head, 0.6, 1),
            ]
            for part in parts {
                let opacity = phase.map { Self.opacity(phase: $0, start: part.start, end: part.end) } ?? 1
                context.fill(part.path, with: .color(color.opacity(opacity)))
            }
        }
    }

    /// The wave's front reaches the tip at 80% of the cycle, its back follows.
    private static func opacity(phase: Double, start: Double, end: Double) -> Double {
        let front = min(phase * 1.25, 1)
        let back = max(0, (phase - 0.4) * 1.25)
        let span = end - start
        let lit = min(max((front - start) / span, 0), 1)
        let faded = min(max((back - start) / span, 0), 1)
        return dimmedOpacity + (1 - dimmedOpacity) * lit * (1 - faded)
    }
}
