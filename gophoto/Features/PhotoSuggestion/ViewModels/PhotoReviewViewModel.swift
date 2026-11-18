import Observation
import UIKit
import os

@Observable
final class PhotoReviewViewModel {
    enum State: Equatable {
        case grading
        case ready
        case loading
        case failed(String)
    }

    static let preselectCount = 20
    static let minPhotos = ChoosePhotosViewModel.minPhotos
    static let maxPhotos = ReferencePhotoMode.allOfMe.maxPhotos

    private(set) var state: State = .grading
    /// Photos that passed the quality gate, best first.
    private(set) var photos: [PersonPhoto] = []
    private(set) var droppedCount = 0
    private(set) var selectedIDs: Set<String> = []

    @ObservationIgnored private let candidates: [PersonPhoto]
    @ObservationIgnored private let meter: PhotoQualityMetering
    @ObservationIgnored private let photoLoader: ChoosePhotosService

    init(candidates: [PersonPhoto],
         meter: PhotoQualityMetering = PhotoQualityMeter(),
         photoLoader: ChoosePhotosService = ChoosePhotosService()) {
        self.candidates = candidates
        self.meter = meter
        self.photoLoader = photoLoader
    }

    var selectedCount: Int { selectedIDs.count }
    var canContinue: Bool { state == .ready && (Self.minPhotos...Self.maxPhotos).contains(selectedCount) }
    var isFull: Bool { selectedCount >= Self.maxPhotos }

    func grade() async {
        guard state == .grading else { return }
        let qualities = await meter.measure(candidates)
        // Taste rules, Mode 2 (16 Nov, with Reynard): only junk is dropped (utility images, very
        // low aesthetics). Face capture quality no longer drops or limits photos: it scores small
        // or turned faces low (full body, side poses), which would remove whole styles. Bursts
        // are merged (`PhotoDedupe`) and every photo left is selected (up to `maxPhotos`), so all
        // styles reach the analysis; the user can still unselect any.
        let usable = qualities.filter { quality in
            !quality.isUtility && (quality.aesthetic.map { $0 >= PhotoQualityGate.minimumAesthetic } ?? true)
        }
        let ranked = PhotoQualityGate.rank(usable)
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let thumbnails = ranked.compactMap { quality in
            byID[quality.assetID]?.thumbnailURL.map { (id: quality.assetID, url: $0) }
        }
        let items = ranked.map {
            PhotoDedupe.Item(id: $0.assetID, takenAt: $0.creationDate, quality: $0.faceQuality.map(Double.init))
        }
        let limit = Self.maxPhotos
        let dedupe = await Task.detached(priority: .userInitiated) {
            let images = thumbnails.compactMap { thumb in
                FaceCrop.thumbnail(at: thumb.url)?.cgImage.map { (id: thumb.id, image: $0) }
            }
            var inputs = StyleInputs()
            inputs.distances = StyleInputs.featureDistances(images)
            return PhotoDedupe.run(items, parameters: PhotoDedupe.Parameters(maxPhotos: limit)) {
                inputs.distance($0, $1)
            }
        }.value
        let kept = Set(dedupe.kept)
        StyleInputs.log.notice("review: \(qualities.count) candidates, \(qualities.count - usable.count) junk dropped, \(dedupe.merged.reduce(0) { $0 + $1.count - 1 }) merged in \(dedupe.merged.count) bursts, \(dedupe.dropped.count) over the limit, \(kept.count) selected")
        StyleTraceRecorder.shared.setReview(.init(candidates: qualities.count, junk: qualities.count - usable.count, // StyleTrace
                                                  bursts: dedupe.merged, overLimit: dedupe.dropped.count,
                                                  selected: kept.count))
        droppedCount = qualities.count - usable.count
        photos = ranked.compactMap { kept.contains($0.assetID) ? byID[$0.assetID] : nil }
        selectedIDs = Set(photos.map(\.id))
        state = .ready
    }

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else if !isFull {
            selectedIDs.insert(id)
        }
    }

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    /// As many photos selected as can be (all of them, or `maxPhotos`): the button reads "Deselect All".
    var isAllSelected: Bool { !photos.isEmpty && selectedCount >= min(photos.count, Self.maxPhotos) }

    /// "Select All" / "Deselect All" (18 Nov). Select All takes the first `maxPhotos`, best first.
    func toggleSelectAll() {
        if isAllSelected {
            selectedIDs = []
        } else {
            selectedIDs = Set(photos.prefix(Self.maxPhotos).map(\.id))
        }
    }

    /// Loads the selected photos the same way the manual picker does. nil on failure.
    func loadSelection() async -> [PhotoItem]? {
        guard canContinue else { return nil }
        state = .loading
        let ids = photos.map(\.id).filter { selectedIDs.contains($0) }
        let assets = PhotoAssets.ordered(ids)
        let loaded: Result<[PhotoItem], Error> = await withCheckedContinuation { continuation in
            photoLoader.loadItems(for: assets) { continuation.resume(returning: $0) }
        }
        switch loaded {
        case .success(let items):
            state = .ready
            return items
        case .failure:
            state = .failed("Couldn't load the photos. Please try again.")
            return nil
        }
    }
}
