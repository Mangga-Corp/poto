//
//  FaceScanStore.swift
//  gophoto
//
//  NOT USED since 20 Nov: "Find my photos for me" scans from the start on every visit (the user's
//  choice), so nothing is saved here any more; `reset()` deletes what an earlier version saved
//  (called at launch, `FaceGroupingAvailability.purgeLeftovers`).
//
//  What it did (17 Nov, Reynard): kept the chosen person's photos and which library photos were
//  already scanned. The next open showed that person's photos at once and only scanned photos
//  whose ID was not checked yet. Only IDs and 512 px thumbnails were kept, never full images.
//
//  MediaIntelligence group IDs change on every scan (its data is cleared), so the person is found
//  again through ANCHORS: a few of their clearest solo photos are scanned with the new photos, and
//  the group holding most anchors is that person (`FaceScanMatch`).
//

import CoreGraphics
import Foundation
import os

nonisolated struct FaceScanRecord: Codable, Sendable {
    nonisolated struct Entry: Codable, Sendable, Equatable {
        let assetID: String
        /// `PersonPresence.storedName`: "solo", "mainFocus" or "group".
        let presence: String
        /// The person's face, normalized, origin top-left.
        let faceBounds: CGRect?
    }

    var version = 1
    /// Every library photo already scanned (the source of truth for what is left to scan).
    var checkedIDs: Set<String> = []
    /// Newest / oldest photo date among the checked photos (progress only).
    var newestChecked: Date?
    var oldestChecked: Date?
    var lastScanAt: Date?
    /// The chosen person's photos (solo, main focus and group).
    var collection: [Entry] = []

    mutating func addChecked(_ ids: [String], newest: Date?, oldest: Date?) {
        checkedIDs.formUnion(ids)
        if let newest { newestChecked = max(newestChecked ?? newest, newest) }
        if let oldest { oldestChecked = min(oldestChecked ?? oldest, oldest) }
        lastScanAt = .now
    }
}

nonisolated enum FaceScanStore {
    static let log = Logger(subsystem: "co.mango.gophoto", category: "facescan")

    private static let directory = URL.applicationSupportDirectory
        .appending(path: "FaceScan", directoryHint: .isDirectory)
    private static let thumbnailsDirectory = directory
        .appending(path: "thumbnails", directoryHint: .isDirectory)
    private static var recordURL: URL { directory.appending(path: "record.json") }

    static func load() -> FaceScanRecord? {
        guard let data = try? Data(contentsOf: recordURL) else { return nil }
        return try? JSONDecoder().decode(FaceScanRecord.self, from: data)
    }

    static func save(_ record: FaceScanRecord) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// "Not you?": forget the person and every scanned ID.
    static func reset() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func thumbnailURL(for assetID: String) -> URL? {
        let url = thumbnailFile(for: assetID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Copies a scan thumbnail (deleted when the scan is cleared) into the store.
    static func keepThumbnail(_ source: URL, for assetID: String) {
        let target = thumbnailFile(for: assetID)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: source, to: target)
    }

    private static func thumbnailFile(for assetID: String) -> URL {
        // localIdentifiers contain "/" → safe file name (same as the scan's thumbnails).
        let name = Data(assetID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return thumbnailsDirectory.appending(path: name + ".jpg")
    }
}

nonisolated enum FaceScanMatch {
    /// Anchors re-scanned with the new photos. Provisional: calibrate on real libraries.
    static let anchorCount = 20
    /// Share of the scanned anchors one group must hold to be the person. Provisional.
    static let minimumAnchorShare = 0.5

    /// The person's clearest photos: solo first (no other face can claim them), largest face first.
    static func anchors(from collection: [FaceScanRecord.Entry]) -> [String] {
        let solo = collection.filter { $0.presence == PersonPresence.solo.storedName }
        let pool = solo.isEmpty
            ? collection.filter { $0.presence == PersonPresence.mainFocus.storedName }
            : solo
        func area(_ entry: FaceScanRecord.Entry) -> Double {
            Double((entry.faceBounds?.width ?? 0) * (entry.faceBounds?.height ?? 0))
        }
        return pool.sorted { area($0) != area($1) ? area($0) > area($1) : $0.assetID < $1.assetID }
            .prefix(anchorCount)
            .map(\.assetID)
    }

    /// The group holding most of the scanned anchors; nil when no group clearly does (a tie, or
    /// under `minimumAnchorShare`). nil = nothing is added and the photos are scanned again later.
    static func person(in groups: [PersonGroup], anchors: [String]) -> PersonGroup? {
        guard !anchors.isEmpty else { return nil }
        let anchorSet = Set(anchors)
        let counts = groups
            .map { (group: $0, count: $0.assetIDs.intersection(anchorSet).count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.group.id < $1.group.id }
        guard let best = counts.first, best.count > 0 else { return nil }
        if counts.count > 1, counts[1].count == best.count { return nil }
        let needed = max(1, Int((Double(anchors.count) * minimumAnchorShare).rounded(.up)))
        return best.count >= needed ? best.group : nil
    }
}

nonisolated extension PersonPresence {
    var storedName: String {
        switch self {
        case .solo: "solo"
        case .mainFocus: "mainFocus"
        case .group: "group"
        case .absent: "absent"
        }
    }

    init?(storedName: String) {
        switch storedName {
        case "solo": self = .solo
        case "mainFocus": self = .mainFocus
        case "group": self = .group
        default: return nil
        }
    }
}
