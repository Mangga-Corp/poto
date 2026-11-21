//
//  PhotoPickerController.swift
//  gophoto
//

import Photos
import UIKit

/// The photo picker: albums → (folder →) photos. Close and Done are on every level, and one
/// selection is shared by all of them.
final class PhotoPickerController: UINavigationController {
    var onCancel: (() -> Void)?
    var onDone: (([PhotoItem]) -> Void)?
    /// Asks "Update your style?" before Done. Only for a SAVED preference, whose style is analysed
    /// again when its photos change; a preference being created has no style yet.
    var requiresReanalyzeConfirmation = false

    private let viewModel: SelectPhotoViewModel

    init(viewModel: SelectPhotoViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        view.tintColor = Theme.accent
        // A sideways drag on the grid selects photos, so only the screen edge goes back.
        interactiveContentPopGestureRecognizer?.isEnabled = false

        viewModel.onLoadingChange = { [weak self] on in self?.setLoading(on) }
        viewModel.onError = { [weak self] message in self?.showError(message) }
        viewModel.onFinish = { [weak self] items in self?.onDone?(items) }
        viewModel.onSelectionChange = { [weak self] in self?.refreshDoneButtons() }

        let albums = PhotoAlbumListViewController(viewModel: viewModel, sections: nil) { [weak self] album in
            self?.open(album)
        }
        configure(albums, title: "Select Photos", showsClose: true)
        setViewControllers([albums], animated: false)
    }

    private func open(_ album: PhotoAlbum) {
        // A name too long for the bar is shown in full above the content instead.
        let contentTitle = fitsBar(album.title) ? nil : album.title
        let next: UIViewController
        switch album.content {
        case .album(let collection):
            next = SelectPhotoViewController(
                viewModel: viewModel,
                assets: ChoosePhotosService.fetchAssets(in: collection),
                contentTitle: contentTitle
            )
        case .folder(let children):
            next = PhotoAlbumListViewController(
                viewModel: viewModel,
                sections: [PhotoAlbumSection(title: nil, albums: children)],
                contentTitle: contentTitle
            ) { [weak self] child in self?.open(child) }
        }
        configure(next, title: album.title, showsBarTitle: contentTitle == nil, showsClose: false)
        pushViewController(next, animated: true)
    }

    private var barTitleWidth: CGFloat { max(view.bounds.width - 160, 120) }

    private func fitsBar(_ title: String) -> Bool {
        let font = UIFont.app(size: 17, weight: .semibold)
        let height = (title as NSString).boundingRect(
            with: CGSize(width: barTitleWidth, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: [.font: font],
            context: nil
        ).height
        return height <= font.lineHeight * 2 + 1
    }

    private func configure(_ controller: UIViewController, title: String, showsBarTitle: Bool = true, showsClose: Bool) {
        let item = controller.navigationItem
        item.title = title
        item.titleView = showsBarTitle ? makeTitleLabel(title) : UIView()
        item.backButtonDisplayMode = .minimal
        if showsClose {
            let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.onCancel?()
            })
            close.accessibilityLabel = "Close"
            item.leftBarButtonItem = close
        }
        let done = UIBarButtonItem(image: UIImage(systemName: "checkmark"), primaryAction: UIAction { [weak self] _ in
            self?.doneTapped()
        })
        done.tintColor = .label
        done.accessibilityLabel = "Done"
        item.rightBarButtonItem = done
        update(done)
    }

    /// A compact bar title: the same size at every Larger Text setting. A long album name wraps
    /// onto a second line; long-press shows it enlarged (Large Content Viewer).
    private func makeTitleLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .app(size: 17, weight: .semibold)
        label.textColor = Theme.text
        label.textAlignment = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = barTitleWidth
        label.accessibilityTraits.insert(.header)
        label.isUserInteractionEnabled = true
        label.showsLargeContentViewer = true
        label.largeContentTitle = text
        label.addInteraction(UILargeContentViewerInteraction())
        return label
    }

    /// The selection can span albums, so the count stays visible on every level.
    private func refreshDoneButtons() {
        for controller in viewControllers {
            if let done = controller.navigationItem.rightBarButtonItem { update(done) }
        }
    }

    private func update(_ done: UIBarButtonItem) {
        let count = viewModel.selectedCount
        done.badge = count > 0 ? .count(count) : nil
        done.accessibilityValue = count > 0 ? "\(count) selected" : nil
    }

    private func doneTapped() {
        guard viewModel.selectedCount > 0 else {
            let alert = UIAlertController(
                title: "No photos selected",
                message: "Choose at least \(ChoosePhotosViewModel.minPhotos) photos to create it.",
                preferredStyle: .alert)
            alert.addSecondaryAction("Leave Anyway") { [weak self] in self?.viewModel.done() }
            alert.addPrimaryAction("Keep Selecting")
            present(alert, animated: true)
            return
        }
        guard requiresReanalyzeConfirmation else {
            viewModel.done()
            return
        }
        let alert = UIAlertController(
            title: "Update your style?",
            message: "Adding these photos will update your style. Continue?",
            preferredStyle: .alert
        )
        alert.addSecondaryAction("Cancel")
        alert.addPrimaryAction("Continue") { [weak self] in self?.viewModel.done() }
        present(alert, animated: true)
    }

    private func setLoading(_ on: Bool) {
        view.isUserInteractionEnabled = !on
        topViewController?.navigationItem.rightBarButtonItem?.isEnabled = !on
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addPrimaryAction("OK")
        present(alert, animated: true)
    }
}

extension UILabel {
    /// An album name too long for the bar: every word is shown, wrapped, above the content.
    static func pickerContentTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .app(style: .title3, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Theme.text
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityTraits.insert(.header)
        return label
    }
}
