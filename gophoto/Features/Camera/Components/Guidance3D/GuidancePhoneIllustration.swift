//
//  GuidancePhoneIllustration.swift
//  gophoto
//
//  The phone and arrow that show a height or tilt move. The camera tips and the live guidance both
//  draw this view, so what people learn in the tips is exactly what they see while shooting.
//  It fills the preview it is placed on.
//

import SwiftUI

extension PhoneSkin {
    static func guide(for colorScheme: ColorScheme) -> PhoneSkin {
        colorScheme == .dark ? .guideDark : .guideLight
    }
}

struct GuidancePhoneIllustration: View {
    enum Placement {
        /// In the middle of the free space (live guidance).
        case centered
        /// Resting right above `bottomLimit` (the camera tips' card).
        case aboveBottomLimit
    }

    let motion: GuidanceMotion
    /// Lowest point the illustration may reach, in this view's coordinates. Nil = the view's bottom.
    var bottomLimit: CGFloat? = nil
    var placement: Placement = .centered

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The camera is always dark, but the illustration follows the iPhone's Light / Dark setting.
    private let appearance = SystemAppearance.shared

    /// Phone height as a share of the preview's height (from the design).
    private static let phoneShare: CGFloat = 0.30
    private static let arrowSize = CGSize(width: 26, height: 74)
    private static let arrowGap: CGFloat = 14
    /// How far the phone and its arrow travel together.
    private static let travel: CGFloat = 24
    /// Keeps the illustration below the instruction at the top of the preview.
    private static let topInset: CGFloat = 44
    private static let bottomGap: CGFloat = 12
    private static let minimumScale: CGFloat = 0.5

    /// Height of what the 3D camera sees, in metres, and the distance that frames it (30° FOV).
    private static let heightSceneMeters: Float = 0.1735
    private static let tiltSceneMeters: Float = 0.26
    private static func cameraDistance(forSceneHeight meters: Float) -> Float {
        meters / (2 * tan(15 * .pi / 180))
    }
    /// The tilt arrow's arc rises this far above the phone's centre (share of the phone's height).
    private static let tiltArcShare: CGFloat = 0.63
    private static let heightYawDegrees: Double = -12

    private var skin: PhoneSkin { .guide(for: appearance.colorScheme) }
    private var arrowColor: Color { Color(hex: appearance.colorScheme == .dark ? 0xD1D1D6 : 0xE6E6E6) }

    /// The 3D colours are set when the scene is built: a new appearance or move rebuilds it.
    private var sceneID: String {
        let kind = if case .height = motion { "height" } else { "tilt" }
        return "\(kind)-\(motion.direction)-\(appearance.colorScheme)"
    }

    var body: some View {
        GeometryReader { proxy in
            let top = Self.topInset
            let bottom = (bottomLimit ?? proxy.size.height) - Self.bottomGap
            let phoneHeight = proxy.size.height * Self.phoneShare

            Group {
                switch motion {
                case .height(let direction):
                    heightMove(direction, width: proxy.size.width, top: top, bottom: bottom,
                               phoneHeight: phoneHeight)
                case .tilt(let direction, let degrees, let view):
                    tiltMove(direction, degrees: degrees, view: view, width: proxy.size.width,
                             top: top, bottom: bottom, phoneHeight: phoneHeight)
                }
            }
            .id(sceneID)
        }
        .onAppear { appearance.refresh() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Height

    @ViewBuilder
    private func heightMove(_ direction: Direction, width: CGFloat, top: CGFloat, bottom: CGFloat,
                            phoneHeight: CGFloat) -> some View {
        let needed = phoneHeight + Self.arrowGap + Self.arrowSize.height + Self.travel
        let scale = fitScale(available: bottom - top, needed: needed)
        let phone = phoneHeight * scale
        let gap = Self.arrowGap * scale
        let arrow = CGSize(width: Self.arrowSize.width * scale, height: Self.arrowSize.height * scale)
        let travel = Self.travel * scale
        let span = needed * scale
        let frameHeight = phone * CGFloat(Self.heightSceneMeters / PhoneDimensions.height)

        let spanTop = placement == .aboveBottomLimit
            ? bottom - span
            : top + max(0, (bottom - top - span) / 2)
        // Up: the arrow leads, with room above it to rise. Down: the phone leads, with room below.
        let phoneCenter = direction == .up
            ? spanTop + travel + arrow.height + gap + phone / 2
            : spanTop + phone / 2
        let arrowCenter = direction == .up
            ? phoneCenter - phone / 2 - gap - arrow.height / 2
            : phoneCenter + phone / 2 + gap + arrow.height / 2

        GuidanceTravel(distance: direction == .up ? -travel : travel, isAnimated: !reduceMotion) {
            ZStack {
                // The rig stays still: the phone and its arrow move together, so the gap between
                // them is the design's at every moment.
                HeightGuidanceView(direction: direction,
                                   isActive: false,
                                   yawDegrees: Self.heightYawDegrees,
                                   cameraDistance: Self.cameraDistance(forSceneHeight: Self.heightSceneMeters),
                                   showsStillPose: true,
                                   skin: skin)
                    .frame(width: frameHeight * 0.72, height: frameHeight)
                    .position(x: width / 2, y: phoneCenter)

                GuidanceBlockArrow(pointsUp: direction == .up, color: arrowColor, isAnimated: !reduceMotion)
                    .frame(width: arrow.width, height: arrow.height)
                    .position(x: width / 2, y: arrowCenter)
            }
        }
    }

    // MARK: Tilt

    @ViewBuilder
    private func tiltMove(_ direction: Direction, degrees: Double, view: TiltView, width: CGFloat,
                          top: CGFloat, bottom: CGFloat, phoneHeight: CGFloat) -> some View {
        let spanShare = Self.tiltArcShare + 0.5
        let scale = fitScale(available: bottom - top, needed: phoneHeight * spanShare)
        let phone = phoneHeight * scale
        let spanTop = top + max(0, (bottom - top - phone * spanShare) / 2)
        let frameHeight = phone * CGFloat(Self.tiltSceneMeters / PhoneDimensions.height)

        TiltGuidanceView(direction: direction,
                         degrees: degrees,
                         tiltView: view,
                         isActive: !reduceMotion,
                         guideColor: UIColor(arrowColor),
                         cameraDistance: Self.cameraDistance(forSceneHeight: Self.tiltSceneMeters),
                         showsStillPose: reduceMotion,
                         skin: skin,
                         arrowStyle: .block)
            .frame(width: frameHeight * 0.72, height: frameHeight)
            .position(x: width / 2, y: spanTop + phone * Self.tiltArcShare)
    }

    private func fitScale(available: CGFloat, needed: CGFloat) -> CGFloat {
        guard needed > 0 else { return 1 }
        return max(Self.minimumScale, min(1, available / needed))
    }
}

/// Moves its content along Y on the height guidance's timeline (out, hold, back, rest).
private struct GuidanceTravel<Content: View>: View {
    let distance: CGFloat
    let isAnimated: Bool
    @ViewBuilder let content: Content

    @State private var start = Date()

    var body: some View {
        if isAnimated {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(start)
                content.offset(y: distance * HeightTimeline.frame(atTime: elapsed).progress)
            }
        } else {
            content
        }
    }
}
