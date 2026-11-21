//
//  SelectPhotoViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit
import Photos

/// The photos of one album. Its bar and the selection belong to `PhotoPickerController`.
final class SelectPhotoViewController: UIViewController {
    private let viewModel: SelectPhotoViewModel
    private let assets: PHFetchResult<PHAsset>
    private lazy var selectPan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSelectPan(_:)))
        pan.delegate = self
        return pan
    }()
    private var panStartIndex: Int?
    private var panSelects = true
    private var panInitialSelection: Set<Int> = []
    private var panLastRange: ClosedRange<Int>?
    private var panHitLimit = false
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private var didRestoreSelection = false
    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1)))
        item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.25)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 12)
        return UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
    }()

    private let contentTitle: String?

    init(viewModel: SelectPhotoViewModel, assets: PHFetchResult<PHAsset>, contentTitle: String? = nil) {
        self.viewModel = viewModel
        self.assets = assets
        self.contentTitle = contentTitle
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        collectionView.backgroundColor = .clear
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)
        collectionView.addGestureRecognizer(selectPan)
        collectionView.panGestureRecognizer.require(toFail: selectPan)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        var gridTop = view.topAnchor
        if let contentTitle {
            let label = UILabel.pickerContentTitle(contentTitle)
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            let safe = view.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
                label.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            ])
            gridTop = label.bottomAnchor
        }
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: gridTop, constant: contentTitle == nil ? 0 : 8),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        guard !didRestoreSelection else { return }
        didRestoreSelection = true
        // The screen-edge swipe goes back; it wins over drag-to-select.
        if let edgePop = navigationController?.interactivePopGestureRecognizer {
            selectPan.require(toFail: edgePop)
        }
        collectionView.layoutIfNeeded()
        for index in viewModel.selectedIndexes(in: assets) {
            collectionView.selectItem(at: IndexPath(item: index, section: 0), animated: false, scrollPosition: [])
        }
    }

    @objc private func handleSelectPan(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: collectionView)
        switch pan.state {
        case .began:
            guard let index = collectionView.indexPathForItem(at: point)?.item else { return }
            panStartIndex = index
            panInitialSelection = selectedIndexes
            panSelects = !panInitialSelection.contains(index)
            panLastRange = nil
            panHitLimit = false
            applyPanRange(to: index)
        case .changed:
            guard panStartIndex != nil,
                  let index = collectionView.indexPathForItem(at: point)?.item else { return }
            applyPanRange(to: index)
        default:
            panStartIndex = nil
            panLastRange = nil
        }
    }

    private var selectedIndexes: Set<Int> {
        Set((collectionView.indexPathsForSelectedItems ?? []).map(\.item))
    }

    private func applyPanRange(to index: Int) {
        guard let start = panStartIndex else { return }
        let range = min(start, index)...max(start, index)
        guard range != panLastRange else { return }
        let touched = Set(range).union(panLastRange.map { Set($0) } ?? [])
        for item in touched.sorted() {
            let shouldSelect = range.contains(item) ? panSelects : panInitialSelection.contains(item)
            setSelected(shouldSelect, at: item)
        }
        panLastRange = range
        selectionHaptic.selectionChanged()
    }

    private func setSelected(_ selected: Bool, at item: Int) {
        let indexPath = IndexPath(item: item, section: 0)
        let id = assets.object(at: item).localIdentifier
        guard selected != viewModel.isSelected(id) else { return }
        if selected {
            guard viewModel.hasRoom else {
                if !panHitLimit {
                    panHitLimit = true
                    _ = viewModel.canSelect()
                }
                return
            }
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        } else {
            guard viewModel.canDeselect(id) else { return }
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        viewModel.setSelected(selected, id: id)
    }
}

extension SelectPhotoViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { assets.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        guard let cell = cv.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseID, for: ip) as? PhotoCell
        else { return UICollectionViewCell() }
        let asset = assets.object(at: ip.item)
        let id = asset.localIdentifier
        cell.assetID = id
        // Voice Control says "Tap Photo 3": each photo needs its own name.
        cell.accessibilityLabel = "Photo \(ip.item + 1)"
        cell.cancelLoad = viewModel.loadThumbnail(for: asset, side: 120 * traitCollection.displayScale) { [weak cell] image in
            guard cell?.assetID == id else { return }
            cell?.imageView.image = image
        }
        return cell
    }

    func collectionView(_ cv: UICollectionView, shouldSelectItemAt ip: IndexPath) -> Bool {
        viewModel.canSelect()
    }

    func collectionView(_ cv: UICollectionView, shouldDeselectItemAt ip: IndexPath) -> Bool {
        viewModel.canDeselect(assets.object(at: ip.item).localIdentifier)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        viewModel.setSelected(true, id: assets.object(at: ip.item).localIdentifier)
    }

    func collectionView(_ cv: UICollectionView, didDeselectItemAt ip: IndexPath) {
        viewModel.setSelected(false, id: assets.object(at: ip.item).localIdentifier)
    }
}

extension SelectPhotoViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === selectPan else { return true }
        let velocity = selectPan.velocity(in: collectionView)
        return abs(velocity.x) > abs(velocity.y)
    }
}
