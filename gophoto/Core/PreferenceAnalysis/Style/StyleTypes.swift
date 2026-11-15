//
//  StyleTypes.swift
//  gophoto
//
//  Mode 1 taste rules (15 Nov): the reference photos of one shot size are grouped into styles,
//  each scene votes once, and the target is the medoid of the winning style. This file holds
//  the measured values of one photo and the limits that make two photos "opposing" (different
//  enough that the guide would give a different instruction). Pure values, no Vision here.
//  Spec: Docs/Experiments/Taste (Catatan-selera-todo.md, Codex-Selera-Diskusi-Metode-v5.md).
//

import Foundation

/// One reference photo as the style rules see it. Missing values stay nil: they are never filled
/// with defaults, so a photo without a value cannot separate or join styles on that dimension.
nonisolated struct StylePhoto: Sendable, Equatable {
    /// Stable id (the PhotoItem id). Used to break ties, never the upload order.
    var id: String
    /// Shot size key the style rules run within (e.g. "half", "threeQuarter", "full", "sitting").
    var shot: String
    var takenAt: Date? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var isScreenshot = false
    /// Camera height: (eyeY − horizonY) / face height, + = camera above the eyes.
    var vantageFaces: Double? = nil
    var vantageSigma: Double? = nil
    /// Phone pitch (degrees).
    var pitchDegrees: Double? = nil
    /// Horizontal centre of the person in the frame (0 = left edge, 1 = right edge).
    var centreX: Double? = nil
    /// Person height / frame height.
    var size: Double? = nil
    /// Can be shown in a question (not blurred, eyes open...). Not checked yet: true.
    var displayable = true
    /// Higher = better; only breaks ties.
    var quality: Double? = nil
}

/// Two photos are opposing when the normalised difference reaches 1 on any dimension both have.
/// Starting values (provisional, calibrate): camera height 1 face (= the guide's
/// `vantageFacesReopen`), tilt 6° (2 × the guide's 3° enter), centre 10% of the frame width,
/// size ratio 1.15.
nonisolated struct StyleLimits: Sendable, Equatable {
    var vantageFaces = 1.0
    var pitchDegrees = 6.0
    var centreX = 0.10
    var sizeRatio = 1.15

    static let standard = StyleLimits()

    /// Largest normalised difference over the dimensions both photos have, and how many there
    /// were. `shared == 0`: nothing to compare (not opposing, but no evidence of the same style).
    func distance(_ a: StylePhoto, _ b: StylePhoto) -> (value: Double, shared: Int) {
        var value = 0.0, shared = 0
        func take(_ x: Double?, _ y: Double?, _ limit: Double) {
            guard let x, let y, x.isFinite, y.isFinite, limit > 0 else { return }
            shared += 1
            value = max(value, abs(x - y) / limit)
        }
        take(a.vantageFaces, b.vantageFaces, vantageFaces)
        take(a.pitchDegrees, b.pitchDegrees, pitchDegrees)
        take(a.centreX, b.centreX, centreX)
        if let x = a.size, let y = b.size, x > 0, y > 0, sizeRatio > 1 {
            shared += 1
            value = max(value, abs(log(x / y)) / log(sizeRatio))
        }
        return (value, shared)
    }

    func opposing(_ a: StylePhoto, _ b: StylePhoto) -> Bool {
        let d = distance(a, b)
        return d.shared > 0 && d.value >= 1
    }
}
