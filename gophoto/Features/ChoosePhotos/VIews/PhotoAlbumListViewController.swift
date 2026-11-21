//
//  PhotoAlbumListViewController.swift
//  gophoto
//

import Photos
import PhotosUI
import UIKit

/// The picker's list of albums, or of the albums inside one folder.
final class PhotoAlbumListViewController: UIViewController {
    private let viewModel: SelectPhotoViewModel
    private let onOpen: (PhotoAlbum) -> Void
    /// Nil = the top level, loaded from the library.
    private let loadsLibrary: Bool
    private var sections: [PhotoAlbumSection]
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let contentTitle: String?

    init(
        viewModel: SelectPhotoViewModel,
        sections: [PhotoAlbumSection]?,
        contentTitle: String? = nil,
        onOpen: @escaping (PhotoAlbum) -> Void
    ) {
        self.viewModel = viewModel
        self.contentTitle = contentTitle
        self.sections = sections ?? []
        self.loadsLibrary = sections == nil
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84
        tableView.separatorColor = Theme.divider
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 96, bottom: 0, right: 0)
        tableView.register(PhotoAlbumCell.self, forCellReuseIdentifier: PhotoAlbumCell.reuseID)

        [tableView, spinner].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        let safe = view.safeAreaLayoutGuide
        var tableTop = view.topAnchor
        if loadsLibrary, viewModel.isLimitedAccess {
            let banner = makeLimitedAccessBanner()
            banner.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
                banner.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
                banner.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            ])
            tableTop = banner.bottomAnchor
        }
        if let contentTitle {
            let label = UILabel.pickerContentTitle(contentTitle)
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
                label.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            ])
            tableTop = label.bottomAnchor
        }
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: tableTop, constant: tableTop === view.topAnchor ? 0 : 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])

        if loadsLibrary { loadAlbums() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let selected = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selected, animated: animated)
        }
    }

    private func loadAlbums() {
        spinner.startAnimating()
        Task { [weak self, viewModel] in
            let sections = await viewModel.loadAlbums()
            guard let self else { return }
            self.sections = sections
            self.spinner.stopAnimating()
            self.tableView.reloadData()
            self.tableView.backgroundView = sections.isEmpty ? Self.makeEmptyView() : nil
        }
    }

    private static func makeEmptyView() -> UIView {
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "photo.on.rectangle")
        configuration.text = "No Photos"
        configuration.secondaryText = "Photos on your iPhone will appear here."
        return UIContentUnavailableView(configuration: configuration)
    }

    private func makeLimitedAccessBanner() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        icon.tintColor = Theme.accent
        icon.contentMode = .center
        icon.backgroundColor = Theme.surface
        icon.layer.cornerRadius = 10
        icon.clipsToBounds = true
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
        ])

        // Built again when the text size changes: attributed text doesn't follow Larger Text by itself.
        func message() -> NSAttributedString {
            let message = NSMutableAttributedString(
                string: "You've limited access to selected items. ",
                attributes: [.font: UIFont.app(style: .subheadline), .foregroundColor: Theme.text])
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                message.append(NSAttributedString(
                    string: "Settings",
                    attributes: [.font: UIFont.app(style: .subheadline, weight: .semibold), .link: settingsURL]))
            }
            return message
        }

        let text = UITextView()
        text.attributedText = message()
        text.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UITextView, _) in
            view.attributedText = message()
        }
        text.linkTextAttributes = [.foregroundColor: Theme.accent]
        text.isEditable = false
        text.isScrollEnabled = false
        text.backgroundColor = .clear
        text.textContainerInset = .zero
        text.textContainer.lineFragmentPadding = 0

        var config = UIButton.Configuration.prominentGlass()
        config.title = "Add more"
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = Theme.onAccent
        let addMore = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.presentLimitedPicker()
        })
        addMore.setContentHuggingPriority(.required, for: .horizontal)
        addMore.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [icon, text, addMore])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        stack.backgroundColor = Theme.tagBackground
        stack.layer.cornerRadius = PotoDesign.controlCornerRadius + 2
        return stack
    }

    private func presentLimitedPicker() {
        Task {
            _ = await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
            viewModel.reload()
            loadAlbums()
        }
    }
}

extension PhotoAlbumListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].albums.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: PhotoAlbumCell.reuseID, for: indexPath) as? PhotoAlbumCell
        else { return UITableViewCell() }
        let album = sections[indexPath.section].albums[indexPath.row]
        cell.configure(with: album)
        if let cover = album.cover {
            let side = PhotoAlbumCell.coverSide * traitCollection.displayScale
            cell.cancelLoad = viewModel.loadThumbnail(for: cover, side: side) { [weak cell] image in
                guard cell?.albumID == album.id else { return }
                cell?.setCover(image)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onOpen(sections[indexPath.section].albums[indexPath.row])
    }
}

private final class PhotoAlbumCell: UITableViewCell {
    static let reuseID = "PhotoAlbumCell"
    static let coverSide: CGFloat = 64

    var albumID: String?
    var cancelLoad: (() -> Void)?
    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        accessoryType = .disclosureIndicator

        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 8
        coverView.backgroundColor = Theme.disabledFill
        coverView.tintColor = Theme.accent

        titleLabel.font = .app(style: .body, weight: .medium)
        titleLabel.textColor = Theme.text
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        countLabel.font = .app(style: .subheadline)
        countLabel.textColor = Theme.secondaryText
        countLabel.numberOfLines = 0
        countLabel.adjustsFontForContentSizeCategory = true

        let labels = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        labels.axis = .vertical
        labels.spacing = 2
        let row = UIStackView(arrangedSubviews: [coverView, labels])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            coverView.widthAnchor.constraint(equalToConstant: Self.coverSide),
            coverView.heightAnchor.constraint(equalToConstant: Self.coverSide),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelLoad?(); cancelLoad = nil
        albumID = nil
        coverView.image = nil
    }

    func configure(with album: PhotoAlbum) {
        albumID = album.id
        titleLabel.text = album.title
        let count = album.itemCount.formatted()
        switch album.content {
        case .album:
            countLabel.text = album.itemCount == 1 ? "1 photo" : "\(count) photos"
            coverView.contentMode = .scaleAspectFill
        case .folder:
            countLabel.text = album.itemCount == 1 ? "1 album" : "\(count) albums"
            coverView.contentMode = .center
            coverView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
            coverView.image = UIImage(systemName: "folder.fill")
        }
        accessibilityLabel = album.title
        accessibilityValue = countLabel.text
        accessibilityTraits = .button
    }

    func setCover(_ image: UIImage?) {
        coverView.preferredSymbolConfiguration = nil
        coverView.image = image
    }
}
