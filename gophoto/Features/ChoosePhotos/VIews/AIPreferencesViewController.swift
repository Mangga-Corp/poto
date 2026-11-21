//
//  AIPreferencesViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import SwiftUI
import UIKit

final class AIPreferencesViewController: UIViewController {
    /// Called when the back button (top-left) is tapped.
    var onBack: (() -> Void)?
    /// Onboarding: called after the picker closes and the user has named the preference.
    var onPhotosAdded: (([PhotoItem], String) -> Void)?
    /// The analysed framing of a photo ("fullBody" / "halfBody" / other), to group the grid into
    /// Full body / Half body sections. Nil = one plain grid (e.g. a preference being created).
    var framingOf: ((PhotoItem) -> String?)?

    private let viewModel: ChoosePhotosViewModel
    private var photoPickerFlow: PhotoPreferencePickerFlow?

    // MARK: - Navigation Bar Items

    private lazy var backItem = UIBarButtonItem(
        title: "Back", image: UIImage(systemName: "chevron.left"),
        primaryAction: UIAction { [weak self] _ in self?.backTapped() })
    // In the bar so adding stays one tap away however far the grid is scrolled.
    private lazy var addItem = UIBarButtonItem(
        title: "Add photos", image: UIImage(systemName: "plus"),
        primaryAction: UIAction { [weak self] _ in self?.photoPickerFlow?.start() })
    private lazy var moreItem = UIBarButtonItem(
        title: "More options", image: UIImage(systemName: "ellipsis"), menu: makeMoreMenu())
    private lazy var selectItem: UIBarButtonItem = {
        let item = UIBarButtonItem(title: viewModel.selectButtonTitle,
                                   primaryAction: UIAction(title: viewModel.selectButtonTitle) { [weak self] _ in
            self?.viewModel.toggleSelecting()
        })
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.app(size: 17, weight: .regular)]
        item.setTitleTextAttributes(attributes, for: .normal)
        item.setTitleTextAttributes(attributes, for: .highlighted)
        return item
    }()
    private lazy var trashItem: UIBarButtonItem = {
        let item = UIBarButtonItem(title: "Delete", image: UIImage(systemName: "trash"),
                                   primaryAction: UIAction { [weak self] _ in self?.confirmDelete() })
        item.tintColor = Theme.destructive
        return item
    }()
    /// Keeps Delete and Cancel in separate glass shapes.
    private let selectionItemSpacer = UIBarButtonItem.fixedSpace(0)

    /// The page title, shown in the bar once the one in the content has scrolled under it.
    private let barTitle = BarTitleView()

    // MARK: - Header Elements (scroll with the photos)

    private lazy var headerStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, guidanceLabel, privacyNote])
        stack.axis = .vertical
        stack.spacing = 2
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(10, after: guidanceLabel)
        return stack
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .app(style: .largeTitle, weight: .bold)   // page title, like every screen
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Theme.text
        label.textAlignment = .left
        label.numberOfLines = 0
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .app(size: 15, weight: .semibold, relativeTo: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = Theme.text
        label.textAlignment = .left
        return label
    }()

    private let guidanceLabel: UILabel = {
        let label = UILabel()
        label.font = .app(size: 13, weight: .regular, relativeTo: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = Theme.secondaryText
        label.text = "Clear, full-body photos work best."
        label.textAlignment = .left
        return label
    }()

    // MARK: - Privacy Note

    private lazy var privacyNote: UIView = {
        let icon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        // Follows the text size, like the label next to it.
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote)
            .applying(UIImage.SymbolConfiguration(weight: .semibold))
        icon.tintColor = Theme.accent
        icon.contentMode = .center
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = "Our AI model runs offline, so your photos never leave this iPhone."
        label.font = .app(size: 13, weight: .regular, relativeTo: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Theme.secondaryText
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        return stack
    }()

    // MARK: - 3-Column Grid

    private lazy var collectionView: UICollectionView = {
        // The page header is part of the scrolling content, so it never covers the photos.
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.boundarySupplementaryItems = [
            NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(140)),
                elementKind: PageHeaderView.elementKind, alignment: .top)
        ]
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] sectionIndex, _ in
            guard let self else { return nil }
            let sections = self.sections
            // 3-column grid: 1/3 width, aspect ratio 1:1
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / 3.0),
                heightDimension: .fractionalHeight(1))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
            let groupHeight = NSCollectionLayoutDimension.fractionalWidth(1.0 / 3.0)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: groupHeight),
                subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            let isLast = sectionIndex >= sections.count - 1
            section.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 13, bottom: isLast ? 40 : 16, trailing: 13)
            if sections.indices.contains(sectionIndex), sections[sectionIndex].title != nil {
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(32)),
                    elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
                section.boundarySupplementaryItems = [header]
            }
            return section
        }, configuration: configuration)
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    // MARK: - Sections

    private var sections: [(title: String?, indices: [Int])] {
        let all = Array(viewModel.items.indices)
        guard let framingOf else { return [(nil, all)] }
        let titles = all.map { framingOf(viewModel.items[$0]).flatMap(Self.framingTitle) }
        let order = ["Full body", "Three-quarter", "Half body", "One-quarter"]
        if titles.allSatisfy({ $0 == nil }) { return [(nil, all)] }
        var groups: [(title: String?, indices: [Int])] = order.map { title in
            (title, all.filter { titles[$0] == title })
        }
        groups.append(("Other", all.filter { titles[$0] == nil }))
        return groups.filter { !$0.indices.isEmpty }
    }

    private func indexPath(forItem item: Int) -> IndexPath? {
        for (section, group) in sections.enumerated() {
            if let row = group.indices.firstIndex(of: item) { return IndexPath(item: row, section: section) }
        }
        return nil
    }

    private static func framingTitle(_ framing: String) -> String? {
        switch framing {
        case "full", "fullBody": "Full body"
        case "threeQuarter": "Three-quarter"
        case "half", "halfBody": "Half body"
        case "quarter": "One-quarter"
        default: nil
        }
    }

    private func showPhoto(at item: Int) {
        let order = sections.flatMap { $0.indices }
        guard let start = order.firstIndex(of: item) else { return }
        let images = order.map { viewModel.items[$0].image }
        let labels = order.map { index in framingOf?(viewModel.items[index]).flatMap(Self.framingTitle) }
        final class Current { var item: Int; init(_ item: Int) { self.item = item } }
        let current = Current(item)

        let pager = PreferencePhotoPager(
            images: images, labels: labels, startIndex: start,
            onPageChange: { [weak self] page in
                guard let self, order.indices.contains(page) else { return }
                current.item = order[page]
                if let ip = self.indexPath(forItem: current.item) {
                    self.collectionView.scrollToItem(at: ip, at: .centeredVertically, animated: false)
                }
            },
            onClose: { [weak self] in self?.dismiss(animated: true) })
        let host = UIHostingController(rootView: pager)
        host.modalPresentationStyle = .fullScreen
        host.preferredTransition = .zoom { [weak self] _ in
            guard let self, let ip = self.indexPath(forItem: current.item) else { return nil }
            return self.collectionView.cellForItem(at: ip)
        }
        present(host, animated: true)
    }

    private func itemIndex(at indexPath: IndexPath) -> Int? {
        let sections = self.sections
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].indices.indices.contains(indexPath.item) else { return nil }
        return sections[indexPath.section].indices[indexPath.item]
    }

    init(viewModel: ChoosePhotosViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)
        collectionView.register(SectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SectionHeaderView.reuseID)
        collectionView.register(PageHeaderView.self,
                                forSupplementaryViewOfKind: PageHeaderView.elementKind,
                                withReuseIdentifier: PageHeaderView.reuseID)

        viewModel.onItemsChange = { [weak self] in self?.renderItems() }
        viewModel.onSelectionChange = { [weak self] in self?.renderSelection() }

        navigationController?.navigationBar.tintColor = Theme.text
        navigationItem.leftBarButtonItem = backItem
        navigationItem.titleView = barTitle

        photoPickerFlow = PhotoPreferencePickerFlow(
            presenter: self,
            viewModel: viewModel,
            onSave: { [weak self] photos, name in
                self?.onPhotosAdded?(photos, name)
                return nil
            }
        )
        if viewModel.mode == .editor {
            photoPickerFlow?.onPhotosAddedToExisting = { [weak self] in self?.backTapped() }
            // A saved preference: new photos change its style.
            photoPickerFlow?.confirmsStyleUpdate = true
        }

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // The header's height follows its text.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: AIPreferencesViewController, _) in
            controller.collectionView.collectionViewLayout.invalidateLayout()
        }

        renderItems()
        renderSelection()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if viewModel.shouldRequestAccessOnAppear() { viewModel.requestAccess { _ in } }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeBarTitle()
        updateBarTitleVisibility()
    }

    /// The bar keeps a title view's old frame when its text changes, which cut "1 Photo Selected"
    /// down to "1". The width leaves room for Back and the buttons on the right.
    private func sizeBarTitle() {
        let maxWidth = max(view.bounds.width - (viewModel.isSelecting ? 250 : 200), 120)
        let size = barTitle.label.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        guard barTitle.fittedSize != size else { return }
        barTitle.fittedSize = size
        barTitle.bounds.size = size
        navigationController?.navigationBar.setNeedsLayout()
    }

    /// The bar shows the title only once the large one has scrolled under the bar.
    private func updateBarTitleVisibility() {
        let scrolled = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
        let isVisible = titleLabel.bounds.height > 0 && scrolled > PageHeaderView.topInset + titleLabel.frame.maxY
        let alpha: CGFloat = isVisible ? 1 : 0
        guard barTitle.label.alpha != alpha else { return }
        UIView.animate(withDuration: 0.2) { self.barTitle.label.alpha = alpha }
    }

    private func makeMoreMenu() -> UIMenu {
        let selectAction = UIAction(title: "Select Photos", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
            self?.viewModel.toggleSelecting()
        }
        let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.promptRename()
        }
        return UIMenu(children: [selectAction, renameAction])
    }

    private func promptRename() {
        let alert = UIAlertController(title: "Rename Preference", message: "Give this preference a new name.", preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            tf.text = self?.viewModel.title
            tf.autocapitalizationType = .words
        }
        alert.addSecondaryAction("Cancel")
        alert.addPrimaryAction("Save") { [weak self, weak alert] in
            guard let newName = alert?.textFields?.first?.text, let self else { return }
            if let error = self.viewModel.rename(to: newName) {
                self.showAlert(message: error)
            } else {
                self.renderItems()
            }
        }
        present(alert, animated: true)
    }

    // MARK: - Render

    private func renderTitle() {
        let title = viewModel.displayTitle
        titleLabel.text = title
        barTitle.label.text = title
        barTitle.label.largeContentTitle = title
        sizeBarTitle()
    }

    private func renderItems() {
        renderTitle()
        let count = viewModel.items.count
        subtitleLabel.text = "Reference photos · \(count) of \(viewModel.limit)"
        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func renderSelection() {
        let selecting = viewModel.isSelecting
        selectItem.title = viewModel.selectButtonTitle
        trashItem.isEnabled = viewModel.canTapDelete
        // Set only when the mode changes: replacing the items on every tapped photo makes them flicker.
        let items = selecting ? [selectItem, selectionItemSpacer, trashItem] : [moreItem, addItem]
        if navigationItem.rightBarButtonItems?.first !== items.first {
            navigationItem.setRightBarButtonItems(items, animated: viewIfLoaded?.window != nil)
        }
        renderTitle()
        collectionView.reloadData()
    }

    // MARK: - Navigation

    private func backTapped() {
        switch viewModel.backAction() {
        case .leave:
            onBack?()
        case .confirmDiscard:
            confirmDiscard()
        case .needMorePhotos(let message):
            showAlert(message: message)
        }
    }

    private func confirmDiscard() {
        let alert = UIAlertController(title: "Discard this preference?", message: "The photos you picked won't be saved.", preferredStyle: .alert)
        alert.addSecondaryAction("Discard") { [weak self] in self?.onBack?() }
        alert.addPrimaryAction("Keep Editing")
        present(alert, animated: true)
    }

    /// Confirmation alert as depicted in Image 1 (iPhone 17 - Preferences C re-analyze):
    /// Title: "Update your style?"
    /// Message: "Removing these photos will update your style. Continue?"
    /// Buttons: [Cancel] (red text) and [Yes]
    private func confirmDelete() {
        let alert = UIAlertController(
            title: "Update your style?",
            message: "Removing these photos will update your style. Continue?",
            preferredStyle: .alert
        )
        alert.addSecondaryAction("Cancel")
        alert.addPrimaryAction("Continue") { [weak self] in
            guard let self else { return }
            self.viewModel.deleteChecked()
            if self.viewModel.mode == .editor { self.backTapped() }
        }
        present(alert, animated: true)
    }

    private func showAlert(message: String) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addPrimaryAction("OK")
        present(a, animated: true)
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension AIPreferencesViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in cv: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let s = sections
        return s.indices.contains(section) ? s[section].indices.count : 0
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        guard let cell = cv.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseID, for: ip) as? PhotoCell,
              let index = itemIndex(at: ip)
        else { return UICollectionViewCell() }
        cell.imageView.image = viewModel.items[index].image
        // Voice Control says "Tap Photo 3": each photo needs its own name.
        cell.accessibilityLabel = "Photo \(index + 1)"
        cell.selectMode = viewModel.isSelecting
        cell.isChecked = viewModel.isChecked(at: index)
        return cell
    }

    func collectionView(_ cv: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at ip: IndexPath) -> UICollectionReusableView {
        if kind == PageHeaderView.elementKind {
            let pageHeader = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: PageHeaderView.reuseID,
                                                                 for: ip)
            (pageHeader as? PageHeaderView)?.setContent(headerStack)
            return pageHeader
        }
        let header = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SectionHeaderView.reuseID,
                                                         for: ip)
        let s = sections
        if let header = header as? SectionHeaderView, s.indices.contains(ip.section) {
            let sectionInfo = s[ip.section]
            let count = sectionInfo.indices.count
            let photoWord = count == 1 ? "photo" : "photos"
            header.setTitle(sectionInfo.title, countText: "\(count) \(photoWord)")
        }
        return header
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        cv.deselectItem(at: ip, animated: false)
        guard let index = itemIndex(at: ip) else { return }
        if viewModel.isSelecting {
            viewModel.toggleChecked(at: index)
        } else {
            showPhoto(at: index)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateBarTitleVisibility()
    }
}

// MARK: - Bar Title

/// A compact bar title: the same size at every Larger Text setting; a long name wraps onto a second
/// line, and long-press shows it enlarged (Large Content Viewer). The label fades inside this view
/// because the navigation bar resets the alpha of the title view itself during its own updates.
private final class BarTitleView: UIView {
    let label: UILabel = {
        let label = UILabel()
        label.font = .app(size: 17, weight: .semibold)
        label.textColor = Theme.text
        label.textAlignment = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.alpha = 0
        label.accessibilityTraits.insert(.header)
        label.isUserInteractionEnabled = true
        label.showsLargeContentViewer = true
        label.addInteraction(UILargeContentViewerInteraction())
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return label
    }()

    var fittedSize: CGSize = .zero {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize { fittedSize }

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.frame = bounds
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - Page Header (title and notes, scrolling with the photos)

private final class PageHeaderView: UICollectionReusableView {
    static let elementKind = "preference-page-header"
    static let reuseID = "PageHeaderView"
    static let topInset: CGFloat = 8

    /// Hosts the controller's one header; the grid can hand it a different reusable view on reload.
    func setContent(_ content: UIView) {
        guard content.superview !== self else { return }
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }
}

// MARK: - Section Header View ("Full body 9 photos")

private final class SectionHeaderView: UICollectionReusableView {
    static let reuseID = "SectionHeaderView"

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .app(size: 16, weight: .bold, relativeTo: .callout)
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 0
        l.textColor = Theme.text
        return l
    }()

    private let countLabel: UILabel = {
        let l = UILabel()
        l.font = .app(size: 14, weight: .regular, relativeTo: .subheadline)
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 0
        l.textColor = Theme.secondaryText
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 6
        // The title keeps its line; the count wraps first when both don't fit.
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // The section's 13 pt inset + 3 lines the text up with the photos' edge.
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -3)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String?, countText: String) {
        titleLabel.text = title
        countLabel.text = countText
    }
}
