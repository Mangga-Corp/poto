//
//  OnboardingMotionDemo.swift
//  gophoto
//
//  Created by Sebastian Darren on 05/11/26.
//

import SwiftUI
 
struct OnboardingMotionDemo: View {
    enum Kind { case tilt, height }
    let kind: Kind
    let direction: Direction
    /// Top of the explanation card, in this view's coordinates. Nil until it is measured.
    var cardTop: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// From the bottom of the phone's frame to the tip of the "lower" arrow.
    private static let arrowReach: CGFloat = 63
    private static let gapAboveCard: CGFloat = 10
    /// Lowest the top of the phone may go under the instruction pill.
    private static let pillClearance: CGFloat = 60
    /// Half the phone's visible height, as a share of its frame's height.
    private static let phoneHalfHeightShare: CGFloat = 0.3

    /// "Lower your phone": how far the phone and its arrow move up, together, so the arrow stops
    /// above the card. Moving only the arrow would run it into the phone at the end of its travel.
    private func liftAboveCard(phoneHeight: CGFloat, containerHeight: CGFloat) -> CGFloat {
        guard kind == .height, direction == .down, let cardTop else { return 0 }
        let center = containerHeight / 2
        let overlap = center + phoneHeight / 2 + Self.arrowReach + Self.gapAboveCard - cardTop
        let room = center - phoneHeight * Self.phoneHalfHeightShare - Self.pillClearance
        return min(max(overlap, 0), max(room, 0))
    }
 
    private var instruction: GuideInstruction {
        switch (kind, direction) {
        case (.tilt, .up):     .tiltUp
        case (.tilt, .down):   .tiltDown
        case (.height, .up):   .raisePhone
        case (.height, .down): .lowerPhone
        }
    }
 
    var body: some View {
        GeometryReader { proxy in
            // Ukuran & posisi persis seperti GuidanceMotionOverlay
            let fraction = min(max(GuidanceAnimationStyle.sizeFraction, 0.15), 0.5)
            let height = proxy.size.height * fraction
            let width = height * 0.72
            let gridLineX = proxy.size.width / 3.0
            let centerY = proxy.size.height / 2.0
                - liftAboveCard(phoneHeight: height, containerHeight: proxy.size.height)

            ZStack {
                switch kind {
                case .tilt:
                    TiltGuidanceView(direction: direction,
                                     degrees: GuidanceMotion.tiltFallbackDegrees,
                                     tiltView: GuidanceAnimationStyle.tiltView,
                                     isActive: !reduceMotion,
                                     guideColor: GuidanceAnimationStyle.guideColor,
                                     showsStillPose: reduceMotion)
                        .id("tilt-\(direction)")
                        .frame(width: width, height: height)
                        .position(x: gridLineX, y: centerY)
                        .transition(.opacity)

                case .height:
                    HeightGuidanceView(direction: direction,
                                       isActive: !reduceMotion,
                                       yawDegrees: GuidanceAnimationStyle.heightYawDegrees,
                                       guideColor: GuidanceAnimationStyle.guideColor,
                                       showsStillPose: reduceMotion)
                        .id("height-\(direction)")
                        .frame(width: width, height: height)
                        .position(x: gridLineX, y: centerY)
                        .transition(.opacity)
 
                    RacingArrowView(direction: direction == .up ? .up : .down)
                        .id("height-arrow-\(direction)")
                        .position(x: gridLineX,
                                  y: direction == .up ? centerY - (height / 2) - 34
                                                      : centerY + (height / 2) + 34)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) {
            // Pill yang sama dengan pill asli di atas tengah
            InstructionPill(instruction: instruction)
                .background { Capsule().fill(Color.black).frame(width: 280, height: 40) }
                .padding(.top, 12)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
