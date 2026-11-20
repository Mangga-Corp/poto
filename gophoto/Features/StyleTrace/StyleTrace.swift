//
//  StyleTrace.swift
//  gophoto
//
//  TEMPORARY (16 Nov, Reynard): shows how the taste rules grouped a preference's photos —
//  review (Mode 2), scenes, styles, scene representatives, votes / knockout, answers, target.
//  Everything lives in this folder. To remove: delete `Features/StyleTrace/` and the lines
//  marked `// StyleTrace` (PreferenceAnalyzer, PreferencesViewModel, PhotoReviewViewModel).
//  The "How it was grouped" button is no longer on the style card (20 Nov, removed from the UI);
//  `attachButton` is kept for debugging.
//  The trace is saved per preference as JSON in Application Support/StyleTrace/.
//

import Foundation
import SwiftUI
import UIKit

nonisolated struct StyleTraceData: Codable, Sendable {
    var createdAt = Date()
    var mode = ReferencePhotoMode.favorites.rawValue
    var review: Review?
    var shots: [Shot] = []

    nonisolated struct Review: Codable, Sendable {
        var candidates = 0
        var junk = 0
        /// Burst groups (asset ids, the kept photo first).
        var bursts: [[String]] = []
        var overLimit = 0
        var selected = 0
    }

    nonisolated struct Photo: Codable, Sendable {
        var id: String
        var scene: Int?
        var styles: [Int]
        var vantageFaces: Double?
        var pitchDegrees: Double?
        var centreX: Double?
        var size: Double?
        var takenAt: Date?
        var isScreenshot: Bool
    }

    nonisolated struct Style: Codable, Sendable {
        var photoIDs: [String]
        var scenes: Int
        var votes: Double
        var targetID: String?
        var representativeIDs: [String]
    }

    nonisolated struct Shot: Codable, Sendable {
        var key: String
        var photos: [Photo]
        var styles: [Style]
        /// What the Mode 1 rule says (single / clear → style n / ask), recorded in both modes.
        var rule: String
        /// Style indices behind the preset's candidates, in candidate order.
        var candidateStyles: [Int] = []
    }
}

/// Collects the trace while one analysis runs (analyses run one at a time).
nonisolated final class StyleTraceRecorder: @unchecked Sendable {
    static let shared = StyleTraceRecorder()
    private let lock = NSLock()
    private var data = StyleTraceData()
    private var lastReview: StyleTraceData.Review?

    func begin() { lock.withLock { data = StyleTraceData() } }

    func setReview(_ review: StyleTraceData.Review) { lock.withLock { lastReview = review } }

    func record(key: String, photos: [StylePhoto], groups: StyleGroups, sceneOf: [String: Int],
                votes: [Double], rule: String, targets: [(target: String, representatives: [String])?]) {
        let shotPhotos = photos.map { p in
            StyleTraceData.Photo(id: p.id, scene: sceneOf[p.id], styles: groups.styles(of: p.id),
                                 vantageFaces: p.vantageFaces, pitchDegrees: p.pitchDegrees,
                                 centreX: p.centreX, size: p.size, takenAt: p.takenAt, isScreenshot: p.isScreenshot)
        }
        let styles = groups.styles.indices.map { s in
            StyleTraceData.Style(photoIDs: groups.styles[s],
                                 scenes: Set(groups.styles[s].compactMap { sceneOf[$0] }).count,
                                 votes: votes.indices.contains(s) ? votes[s] : 0,
                                 targetID: targets[s]?.target, representativeIDs: targets[s]?.representatives ?? [])
        }
        lock.withLock {
            data.shots.removeAll { $0.key == key }
            data.shots.append(StyleTraceData.Shot(key: key, photos: shotPhotos, styles: styles, rule: rule))
        }
    }

    func setCandidates(key: String, styles: [Int]) {
        lock.withLock {
            if let i = data.shots.firstIndex(where: { $0.key == key }) { data.shots[i].candidateStyles = styles }
        }
    }

    /// The trace of the analysis that just ran (with the last review for Mode 2).
    func finish(mode: ReferencePhotoMode) -> StyleTraceData {
        lock.withLock {
            var result = data
            result.mode = mode.rawValue
            result.review = mode == .allOfMe ? lastReview : nil
            return result
        }
    }
}

nonisolated enum StyleTraceStore {
    private static var folder: URL {
        URL.applicationSupportDirectory.appendingPathComponent("StyleTrace", isDirectory: true)
    }

    static func save(_ trace: StyleTraceData, for id: UUID) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(trace) else { return }
        try? data.write(to: folder.appendingPathComponent(id.uuidString + ".json"), options: .atomic)
    }

    static func load(for id: UUID) -> StyleTraceData? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(id.uuidString + ".json")) else { return nil }
        return try? JSONDecoder().decode(StyleTraceData.self, from: data)
    }
}

@MainActor
enum StyleTrace {
    /// Saves what the recorder collected for `id` (call after the analysis is saved).
    static func saveRecorded(for id: UUID) {
        StyleTraceStore.save(StyleTraceRecorder.shared.finish(mode: ReferencePhotoModeStore.mode(for: id)), for: id)
    }

    /// Adds a small "How it was grouped" button to the top right of `controller`. Not attached
    /// anywhere since 20 Nov (removed from the style card); call it to debug a style card.
    static func attachButton(to controller: UIViewController, preferenceID: UUID) {
        let button = UIButton(type: .system)
        button.setTitle("How it was grouped", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak controller] _ in
            let hosting = UIHostingController(rootView: NavigationStack { StyleTraceView(preferenceID: preferenceID) }
                .dynamicTypeSize(...AppFont.maximumDynamicTypeSize))
            controller?.present(hosting, animated: true)
        }, for: .touchUpInside)
        controller.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
    }
}
