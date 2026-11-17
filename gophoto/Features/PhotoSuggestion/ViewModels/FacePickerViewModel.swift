import Observation
import UIKit

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
    /// Photos checked per run; photos past this are checked by the next run (`FaceScanStore`).
    static let maxPhotos = 1500
    static let shownGroupCount = 6

    private(set) var state: State = .idle
    private(set) var groups: [PersonGroup] = []
    private(set) var covers: [String: UIImage] = [:]
    private(set) var pickedGroup: PersonGroup?
    private(set) var pickedPhotos: [PersonPhoto] = []
    private(set) var isShowingAllGroups = false
    /// A person was chosen before: their saved photos are shown at once, and a scan of the photos
    /// not checked yet adds new ones (17 Nov).
    private(set) var hasSavedPerson = false
    /// Photos added by the last run.
    private(set) var addedCount = 0
    /// Library photos still not checked after the last run.
    private(set) var remainingCount = 0

    @ObservationIgnored private var result: FaceGroupingResult?
    @ObservationIgnored private var record: FaceScanRecord?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private let service: FaceGrouping?

    init(service: FaceGrouping? = FaceGroupingAvailability.makeService()) {
        self.service = service
    }

    var shownGroups: [PersonGroup] {
        isShowingAllGroups ? groups : Array(groups.prefix(Self.shownGroupCount))
    }
    var hasMoreGroups: Bool { !isShowingAllGroups && groups.count > Self.shownGroupCount }
    var faceCount: Int { result?.facesByAsset.values.reduce(0) { $0 + $1.count } ?? 0 }
    var photosChecked: Int { result?.photosChecked ?? 0 }
    var includedPhotos: [PersonPhoto] { pickedPhotos.filter { PersonPhotoFilter.isIncluded($0.presence) } }
    var groupPhotos: [PersonPhoto] { pickedPhotos.filter { $0.presence == .group } }

    /// One line under the saved person's photos.
    var savedStatus: String {
        switch state {
        case .scanning(let progress):
            return "Looking for new photos… \(progress.photosChecked) checked"
        case .needsAccess:
            return "Allow photo access in Settings to look for new photos."
        case .failed(let text):
            return text
        default:
            var parts: [String] = []
            if addedCount > 0 { parts.append("\(addedCount) new") }
            parts.append(remainingCount > 0 ? "\(remainingCount) photos not checked yet" : "All your photos are checked")
            return parts.joined(separator: " · ")
        }
    }

    func start() {
        guard service != nil else { state = .unsupported; return }
        scanTask?.cancel()
        scanTask = Task { await requestAccessAndScan() }
    }

    func continueWithLimitedAccess() {
        scanTask?.cancel()
        scanTask = Task { await scan() }
    }

    func dismissLimitedAccess() {
        if state == .limitedAccess { state = .idle }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func showAllGroups() {
        isShowingAllGroups = true
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
        saveChosenPerson()
    }

    /// "Not you?": forgets the saved person and every checked photo, then scans from the start.
    func forgetSavedPerson() {
        cancelScan()
        FaceScanStore.reset()
        record = nil
        result = nil
        hasSavedPerson = false
        pickedGroup = nil
        pickedPhotos = []
        groups = []
        covers = [:]
        addedCount = 0
        remainingCount = 0
        start()
    }

    func clear() {
        cancelScan()
        result = nil
        record = nil
        groups = []
        covers = [:]
        pickedGroup = nil
        pickedPhotos = []
        isShowingAllGroups = false
        hasSavedPerson = false
        state = .idle
        guard let service else { return }
        // The scan's thumbnails are deleted only after the saved copies are made.
        Task { [persistTask] in
            await persistTask?.value
            await service.clear()
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
        if record == nil { record = await Self.loadRecord() }
        let saved = record?.collection ?? []
        if !saved.isEmpty { showSaved() }
        state = .scanning(FaceGroupingProgress(photosChecked: 0, facesFound: 0))
        do {
            let found = try await service.scan(maxFaces: Self.maxFaces, maxPhotos: Self.maxPhotos,
                                               skipping: saved.isEmpty ? [] : (record?.checkedIDs ?? []),
                                               anchors: FaceScanMatch.anchors(from: saved)) { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .scanning = self.state else { return }
                    self.state = .scanning(progress)
                }
            }
            result = found
            remainingCount = found.remaining
            if saved.isEmpty {
                groups = found.groups
                covers = await Self.covers(for: Array(found.groups.prefix(Self.shownGroupCount)),
                                           thumbnails: found.thumbnailURLs)
            } else {
                addNewPhotos(from: found)
            }
            state = .done
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed("Couldn't scan your photos. Please try again.")
        }
    }

    // MARK: - Saved person (FaceScanStore)

    /// First pick: the person's photos and every photo this scan checked are saved.
    private func saveChosenPerson() {
        guard let found = result, !hasSavedPerson else { return }
        var record = FaceScanRecord()
        record.collection = pickedPhotos.map {
            FaceScanRecord.Entry(assetID: $0.id, presence: $0.presence.storedName, faceBounds: $0.faceBounds)
        }
        record.addChecked(found.checkedIDs, newest: found.newestChecked, oldest: found.oldestChecked)
        self.record = record
        let thumbnails = pickedPhotos.compactMap { photo in photo.thumbnailURL.map { (photo.id, $0) } }
        persistTask = Task { await Self.persist(record, thumbnails: thumbnails) }
        FaceScanStore.log.notice("scan: person chosen, \(record.collection.count) photos, \(found.checkedIDs.count) checked, \(found.remaining) left")
    }

    /// Later runs: the group holding the anchors is the person; their new photos are added.
    private func addNewPhotos(from found: FaceGroupingResult) {
        guard var record else { return }
        guard !found.checkedIDs.isEmpty else { return }
        guard let person = FaceScanMatch.person(in: found.groups, anchors: found.anchorIDs) else {
            // Not saved as checked: these photos are scanned again next time.
            FaceScanStore.log.notice("scan: person not matched (\(found.anchorIDs.count) anchors), \(found.checkedIDs.count) photos kept for the next run")
            return
        }
        let known = Set(record.collection.map(\.assetID))
        var added: [FaceScanRecord.Entry] = []
        var thumbnails: [(String, URL)] = []
        for id in found.checkedIDs where !known.contains(id) {
            guard let faces = found.facesByAsset[id] else { continue }
            let presence = PersonPhotoFilter.presence(of: person.id, in: faces)
            guard presence != .absent else { continue }
            let face = faces.filter { $0.entityID == person.id }.max { $0.area < $1.area }
            added.append(FaceScanRecord.Entry(assetID: id, presence: presence.storedName, faceBounds: face?.bounds))
            if let url = found.thumbnailURLs[id] { thumbnails.append((id, url)) }
        }
        record.collection += added
        record.addChecked(found.checkedIDs, newest: found.newestChecked, oldest: found.oldestChecked)
        self.record = record
        addedCount = added.count
        persistTask = Task { await Self.persist(record, thumbnails: thumbnails) }
        // New photos use the scan's thumbnail until the copy exists.
        let scanThumbnails = Dictionary(uniqueKeysWithValues: thumbnails)
        showSaved(fallbackThumbnails: scanThumbnails)
        FaceScanStore.log.notice("scan: \(added.count) new photos of the person, \(found.checkedIDs.count) checked, \(found.remaining) left")
    }

    private func showSaved(fallbackThumbnails: [String: URL] = [:]) {
        guard let record, !record.collection.isEmpty else { return }
        hasSavedPerson = true
        pickedPhotos = record.collection.compactMap { entry in
            guard let presence = PersonPresence(storedName: entry.presence) else { return nil }
            let thumbnail = fallbackThumbnails[entry.assetID] ?? FaceScanStore.thumbnailURL(for: entry.assetID)
            return PersonPhoto(id: entry.assetID, presence: presence, thumbnailURL: thumbnail,
                               faceBounds: entry.faceBounds)
        }
        .sorted { $0.id < $1.id }
    }

    /// Saved record without photos deleted from the library since.
    @concurrent
    nonisolated private static func loadRecord() async -> FaceScanRecord? {
        guard var record = FaceScanStore.load() else { return nil }
        let existing = Set(PhotoAssets.byID(record.collection.map(\.assetID)).keys)
        record.collection.removeAll { !existing.contains($0.assetID) }
        return record
    }

    @concurrent
    nonisolated private static func persist(_ record: FaceScanRecord, thumbnails: [(String, URL)]) async {
        for (id, url) in thumbnails { FaceScanStore.keepThumbnail(url, for: id) }
        FaceScanStore.save(record)
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
