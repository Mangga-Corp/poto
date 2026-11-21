import Observation
import UIKit
import os

/// "Find my photos for me": scans the library, groups the faces by person and lets the user pick
/// themselves. Every visit starts from scratch (20 Nov, user's choice): a full scan and the people
/// grid. Nothing about the chosen person is kept after the screen closes.
@Observable
final class FacePickerViewModel {
    enum State: Equatable {
        case idle
        case unsupported
        case needsAccess
        case limitedAccess
        case scanning(FaceGroupingProgress)
        case done
        case failed(String)
    }

    static let maxFaces = 600
    /// Photos checked per scan: favourites first, then the newest.
    static let maxPhotos = 1500
    static let shownGroupCount = 4
    /// People added per "Not here? Show more people" tap: two more rows of the 2-column grid.
    static let moreGroupCount = 4

    private(set) var state: State = .idle
    private(set) var groups: [PersonGroup] = []
    private(set) var covers: [String: UIImage] = [:]
    private(set) var pickedGroup: PersonGroup?
    private(set) var pickedPhotos: [PersonPhoto] = []
    /// People on screen: `shownGroupCount` first, `moreGroupCount` more per tap, each with its face.
    private(set) var shownGroupLimit = FacePickerViewModel.shownGroupCount
    private(set) var isLoadingMoreGroups = false
    /// The limited-access question was closed without scanning: `.idle` then waits for
    /// "Scan my photos" instead of showing the loading page.
    private(set) var isWaitingForManualStart = false

    /// The first scan was started. Coming back to the screen (from Your Photos) keeps what it shows
    /// instead of scanning again.
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var result: FaceGroupingResult?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private let service: FaceGrouping?

    /// The last closed screen's cleanup (its scan stopping, then its faces and thumbnails deleted).
    /// Every screen shares one analyzer and one folder, so a new scan waits for it: otherwise
    /// leaving and opening "Find my photos" again quickly deleted the new scan's data mid-run.
    private static var pendingCleanup: Task<Void, Never>?

    init(service: FaceGrouping? = FaceGroupingAvailability.makeService()) {
        self.service = service
    }

    var shownGroups: [PersonGroup] { Array(groups.prefix(shownGroupLimit)) }
    var hasMoreGroups: Bool { groups.count > shownGroupLimit }
    var faceCount: Int { result?.facesByAsset.values.reduce(0) { $0 + $1.count } ?? 0 }
    var photosChecked: Int { result?.photosChecked ?? 0 }
    var includedPhotos: [PersonPhoto] { pickedPhotos.filter { PersonPhotoFilter.isIncluded($0.presence) } }
    var groupPhotos: [PersonPhoto] { pickedPhotos.filter { $0.presence == .group } }

    /// Called each time the screen appears: scans only the first time. Going back from Your Photos
    /// shows the same people again, as the user left them.
    func startIfNeeded() {
        guard !hasStarted else { return }
        start()
    }

    func start() {
        hasStarted = true
        isWaitingForManualStart = false
        guard service != nil else { state = .unsupported; return }
        restartScan { await $0.requestAccessAndScan() }
    }

    func continueWithLimitedAccess() {
        isWaitingForManualStart = false
        restartScan { await $0.scan() }
    }

    func dismissLimitedAccess() {
        guard state == .limitedAccess else { return }
        isWaitingForManualStart = true
        state = .idle
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// Before 18 Nov every other person appeared at once with an empty placeholder face (faces
    /// were cut only for the first six). Now the next few appear with their faces already cut.
    func showMoreGroups() async {
        guard !isLoadingMoreGroups, let result else { return }
        let next = Array(groups.dropFirst(shownGroupLimit).prefix(Self.moreGroupCount))
        guard !next.isEmpty else { return }
        isLoadingMoreGroups = true
        let more = await Self.covers(for: next, thumbnails: result.thumbnailURLs)
        covers.merge(more) { current, _ in current }
        shownGroupLimit += next.count
        isLoadingMoreGroups = false
    }

    func pick(_ group: PersonGroup) {
        pickedGroup = group
        let facesByAsset = result?.facesByAsset ?? [:]
        pickedPhotos = facesByAsset.compactMap { assetID, faces in
            let presence = PersonPhotoFilter.presence(of: group.id, in: faces)
            guard presence != .absent else { return nil }
            let face = faces.filter { $0.entityID == group.id }.max { $0.area < $1.area }
            return PersonPhoto(id: assetID, presence: presence,
                               thumbnailURL: result?.thumbnailURLs[assetID], faceBounds: face?.bounds)
        }
        .sorted { $0.id < $1.id }
    }

    /// The screen closed (photos used, or the user left): stops the scan and deletes its faces and
    /// thumbnails. The next visit scans from the start.
    func clear() {
        let running = scanTask
        running?.cancel()
        scanTask = nil
        hasStarted = false
        result = nil
        groups = []
        covers = [:]
        pickedGroup = nil
        pickedPhotos = []
        shownGroupLimit = Self.shownGroupCount
        isWaitingForManualStart = false
        state = .idle
        guard let service else { return }
        let previous = Self.pendingCleanup
        Self.pendingCleanup = Task {
            await previous?.value
            await running?.value
            await service.clear()
        }
    }

    /// Stops the running scan and starts `work` once it has stopped and any earlier screen's
    /// cleanup is done, so two scans never use the shared analyzer at the same time.
    private func restartScan(_ work: @escaping (FacePickerViewModel) async -> Void) {
        let previous = scanTask
        previous?.cancel()
        scanTask = Task { [weak self] in
            await previous?.value
            await Self.pendingCleanup?.value
            guard let self, !Task.isCancelled else { return }
            await work(self)
        }
    }

    private func requestAccessAndScan() async {
        switch await PhotoLibraryAccess.request() {
        case .denied: state = .needsAccess
        case .limited: state = .limitedAccess
        case .full: await scan()
        }
    }

    private func scan() async {
        guard let service else { return }
        state = .scanning(FaceGroupingProgress(photosChecked: 0, facesFound: 0))
        do {
            let found = try await service.scan(maxFaces: Self.maxFaces, maxPhotos: Self.maxPhotos,
                                               skipping: [], anchors: []) { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .scanning = self.state else { return }
                    self.state = .scanning(progress)
                }
            }
            try Task.checkCancellation()
            result = found
            groups = found.groups
            shownGroupLimit = Self.shownGroupCount
            covers = await Self.covers(for: Array(found.groups.prefix(Self.shownGroupCount)),
                                       thumbnails: found.thumbnailURLs)
            state = .done
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed("Couldn't scan your photos. Please try again.")
        }
    }

    @concurrent
    nonisolated private static func covers(for groups: [PersonGroup],
                                           thumbnails: [String: URL]) async -> [String: UIImage] {
        var covers: [String: UIImage] = [:]
        for group in groups {
            guard let face = group.cover, let url = thumbnails[face.assetID],
                  let crop = FaceCrop.image(at: url, face: face.bounds) else { continue }
            covers[group.id] = crop
        }
        return covers
    }
}
