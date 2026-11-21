//
//  TiltGuidanceRig.swift
//  gophoto
//
//  Created by Sebastian Darren on 29/10/26.
//

import RealityKit
import UIKit
import simd

@MainActor
final class TiltGuidanceRig {
    let root = Entity()
    private let phone = PhoneRig()
    private let turnArrow = TiltTurnArrow()

    init() {
        root.name = "TiltGuidanceRig"
        root.addChild(phone.root)
        root.addChild(turnArrow.root)
    }

    /// - Parameters:
    ///   - degrees: swing size; sanitized with the same rules as `GuidanceMotion`.
    ///   - yawDegrees: how the phone is seen (`TiltView.yawDegrees`).
    func update(frame: TiltFrame, direction: Direction, degrees: Double,
                yawDegrees: Double, guideColor: UIColor = .white) {
        let swing = GuidanceMotion.tiltDegrees(forPitchError: degrees)

        // Konvensi arah dari tengah:
        // Saat mengarahkan lebih ke atas (.up)   -> kamera belakang naik ke atas (target positif)
        // Saat mengarahkan lebih ke bawah (.down) -> kamera belakang turun ke bawah (target negatif)
        let target = (direction == .up) ? swing : -swing

        let progress = min(max(frame.progress, 0), 1)
        let pose = PhonePose(yawDegrees: yawDegrees, tiltUpDegrees: target * progress, liftMeters: 0)
        phone.apply(pose)
        phone.setOpacity(frame.phoneOpacity)
        turnArrow.update(reveal: frame.arrowReveal, opacity: frame.arrowOpacity, direction: direction,
                         yawDegrees: pose.sanitized.yawDegrees, color: guideColor)
    }
}

/// A 3D arrow that curls over the top of the phone, in the plane the phone turns in.
/// Down: from the screen side, over the top, toward the back. Up: the same arc, reversed.
/// The arc stops above the back edge so the arrowhead is never hidden behind the tilted phone.
@MainActor
private final class TiltTurnArrow {
    let root = Entity()

    private static let center = SIMD3<Float>(0, 0.042, 0)
    private static let radius: Float = 0.052
    private static let tubeRadius: Float = 0.0021
    private static let headLength: Float = 0.016
    private static let headRadius: Float = 0.0078
    private static let trackOpacity: Float = 0.28
    private static let segmentCount = 40
    /// Angles are measured from the screen side (+Z) toward the top (+Y).
    private static let startAngle: Float = -50 * .pi / 180
    private static let endAngle: Float = 132 * .pi / 180
    private static let sweep = endAngle - startAngle
    /// The line stops where the arrowhead starts.
    private static let lineSweep = sweep - headLength / radius
    private static let xAxis = SIMD3<Float>(1, 0, 0)
    private static let yAxis = SIMD3<Float>(0, 1, 0)

    private let track: ModelEntity
    private let tail: ModelEntity
    private let cone: ModelEntity
    private let head = Entity()
    private var segments: [ModelEntity] = []
    private var shownSegments = -1
    private var shownDirection: Direction?
    private var color: UIColor = .white

    init() {
        let material = UnlitMaterial(color: .white)
        track = ModelEntity(mesh: GuidanceShapeMeshFactory.arcTube(
            radius: Self.radius, tubeRadius: Self.tubeRadius * 0.7,
            from: Self.startAngle, to: Self.endAngle, arcSegments: Self.segmentCount),
            materials: [material])
        track.components.set(OpacityComponent(opacity: Self.trackOpacity))
        tail = ModelEntity(mesh: .generateSphere(radius: Self.tubeRadius), materials: [material])
        cone = ModelEntity(mesh: .generateCone(height: Self.headLength, radius: Self.headRadius),
                           materials: [material])

        root.name = "TiltTurnArrow"
        let arc = Entity()
        arc.position = Self.center
        root.addChild(arc)
        arc.addChild(track)
        arc.addChild(tail)
        arc.addChild(head)
        head.addChild(cone)

        // One short piece of tube, repeated: revealing the arrow only switches pieces on, with no
        // new mesh on any frame.
        let step = Self.sweep / Float(Self.segmentCount)
        let piece = GuidanceShapeMeshFactory.arcTube(radius: Self.radius, tubeRadius: Self.tubeRadius,
                                                     from: 0, to: step * 1.05, arcSegments: 2)
        for index in 0..<Self.segmentCount {
            let segment = ModelEntity(mesh: piece, materials: [material])
            let angle = Self.startAngle + step * Float(index)
            segment.orientation = simd_quatf(angle: -angle, axis: Self.xAxis)
            arc.addChild(segment)
            segments.append(segment)
        }
    }

    func update(reveal: Double, opacity: Double, direction: Direction, yawDegrees: Double, color: UIColor) {
        root.orientation = simd_quatf(angle: Float(yawDegrees) * .pi / 180, axis: Self.yAxis)

        setOpacity(opacity)
        setColor(color)
        setDirection(direction)

        let drawn = Float(min(max(reveal.isFinite ? reveal : 1, 0), 1))
        let travelled = Self.lineSweep * drawn
        let headAngle = direction == .down ? Self.startAngle + travelled : Self.endAngle - travelled
        head.orientation = simd_quatf(angle: -headAngle, axis: Self.xAxis)

        let step = Self.sweep / Float(Self.segmentCount)
        let shown = Int((travelled / step).rounded(.up))
        guard shown != shownSegments else { return }
        shownSegments = shown
        for (index, segment) in segments.enumerated() {
            segment.isEnabled = direction == .down ? index < shown : index >= Self.segmentCount - shown
        }
    }

    /// Puts the tail at the arc's first end and turns the arrowhead the way the arrow travels.
    private func setDirection(_ direction: Direction) {
        guard direction != shownDirection else { return }
        shownDirection = direction
        shownSegments = -1
        let tailAngle = direction == .down ? Self.startAngle : Self.endAngle
        tail.position = SIMD3<Float>(0, sin(tailAngle), cos(tailAngle)) * Self.radius
        // Placed where the arc's angle is 0, so turning `head` about X moves it along the arc.
        let along: Float = direction == .down ? 1 : -1
        cone.position = SIMD3<Float>(0, along * Self.headLength / 2, Self.radius)
        cone.orientation = direction == .down ? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                                              : simd_quatf(angle: .pi, axis: Self.xAxis)
    }

    private func setOpacity(_ value: Double) {
        let opacity = Float(min(max(value.isFinite ? value : 1, 0), 1))
        root.isEnabled = opacity > 0.005
        if opacity >= 0.995 {
            root.components.remove(OpacityComponent.self)
        } else {
            root.components.set(OpacityComponent(opacity: opacity))
        }
    }

    private func setColor(_ newColor: UIColor) {
        guard newColor != color else { return }
        color = newColor
        let material = UnlitMaterial(color: newColor)
        for entity in [track, tail, cone] + segments {
            entity.model?.materials = [material]
        }
    }
}
