//
//  SelectPhotoViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Photos
import UIKit

/// The picker's selection. It is kept by photo identifier, so it survives moving between albums.
final class SelectPhotoViewModel {
    var onLoadingChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onFinish: (([PhotoItem]) -> Void)?
    var onSelectionChange: (() -> Void)?

    let canRemoveExisting: Bool

    private let service: ChoosePhotosService
    private let limit: Int
    private let existing: [PhotoItem]
    private let existingIDs: Set<String>
    private var visibleExistingIDs: Set<String>
    private var selectedIDs: Set<String>

    init(service: ChoosePhotosService, existing: [PhotoItem], limit: Int, canRemoveExisting: Bool) {
        let ids = Set(existing.compactMap(\.sourceAssetIdentifier))
        let visible = Self.availableIDs(among: ids)
        self.service = service
        self.existing = existing
        self.existingIDs = ids
        self.limit = limit
        self.canRemoveExisting = canRemoveExisting
        self.visibleExistingIDs = visible
        self.selectedIDs = visible
    }

    var isLimitedAccess: Bool { service.access == .limited }

    var selectedCount: Int { selectedIDs.count }

    func loadAlbums() async -> [PhotoAlbumSection] {
        await Task.detached(priority: .userInitiated) { ChoosePhotosService.fetchAlbumSections() }.value
    }

    /// After the limited-access selection changed: drops photos that are gone and selects saved
    /// photos that just became visible. A saved photo the user unticked stays unticked.
    func reload() {
        let visible = Self.availableIDs(among: existingIDs)
        let newlyVisible = visible.subtracting(visibleExistingIDs)
        visibleExistingIDs = visible
        selectedIDs = Self.availableIDs(among: selectedIDs).union(newlyVisible)
        onSelectionChange?()
    }

    func isSelected(_ id: String) -> Bool { selectedIDs.contains(id) }

    func setSelected(_ selected: Bool, id: String) {
        if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
        onSelectionChange?()
    }

    func canDeselect(_ id: String) -> Bool { canRemoveExisting || !existingIDs.contains(id) }

    /// Where the current selection sits in one album's photos.
    func selectedIndexes(in assets: PHFetchResult<PHAsset>) -> [Int] {
        var indexes: [Int] = []
        ChoosePhotosService.fetchAssets(identifiers: Array(selectedIDs)).enumerateObjects { asset, _, _ in
            let index = assets.index(of: asset)
            if index != NSNotFound { indexes.append(index) }
        }
        return indexes
    }

    /// Returns a closure that cancels the request.
    func loadThumbnail(for asset: PHAsset, side: CGFloat, completion: @escaping (UIImage?) -> Void) -> () -> Void {
        let id = service.thumbnail(for: asset, side: side, completion: completion)
        return { [service] in service.cancel(id) }
    }

    func canSelect() -> Bool {
        guard hasRoom else {
            onError?("A preference can have up to \(limit) photos.")
            return false
        }
        return true
    }

    var hasRoom: Bool { selectedIDs.count + hiddenExistingCount < limit }

    func done() {
        let kept = existing.filter { item in
            guard let id = item.sourceAssetIdentifier, visibleExistingIDs.contains(id) else { return true }
            return selectedIDs.contains(id)
        }
        let newIDs = selectedIDs.subtracting(existingIDs)
        var newAssets: [PHAsset] = []
        ChoosePhotosService.fetchAssets(identifiers: Array(newIDs)).enumerateObjects { asset, _, _ in
            newAssets.append(asset)
        }

        guard !newAssets.isEmpty else { onFinish?(kept); return }
        onLoadingChange?(true)
        service.loadItems(for: newAssets) { [weak self] result in
            guard let self else { return }
            self.onLoadingChange?(false)
            switch result {
            case .success(let items): self.onFinish?(kept + items)
            case .failure(let error): self.onError?(error.localizedDescription)
            }
        }
    }

    private var hiddenExistingCount: Int { existing.count - visibleExistingIDs.count }

    private static func availableIDs(among ids: Set<String>) -> Set<String> {
        var available = Set<String>()
        ChoosePhotosService.fetchAssets(identifiers: Array(ids)).enumerateObjects { asset, _, _ in
            available.insert(asset.localIdentifier)
        }
        return available
    }
}
