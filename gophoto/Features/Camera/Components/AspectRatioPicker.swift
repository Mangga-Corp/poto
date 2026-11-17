//
//  AspectRatioPicker.swift
//  gophoto
//
//  The camera's photo ratio (3:4 / 9:16): a round button to the right of the shutter, balancing
//  the gallery shortcut on the left. Tapping it opens a native menu (checkmark = in use), so the
//  choice is one tap away without a permanent control over the image. The ratio in use is also
//  shown as plain text at the top right of the camera.
//

import SwiftUI
import UIKit

struct AspectRatioPicker: View, Equatable {
    let selection: CameraAspectRatio
    var onSelect: (CameraAspectRatio) -> Void

    /// Same size as the gallery shortcut, so the shutter row stays symmetric.
    private static let size: CGFloat = 52

    /// The camera screen redraws many times a second (motion, detection); compare only the
    /// selection so an open menu isn't rebuilt underneath the finger.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.selection == rhs.selection }

    var body: some View {
        RatioMenuButton(selection: selection, onSelect: onSelect)
            .frame(width: Self.size, height: Self.size)
            .accessibilityLabel("Photo ratio")
            .accessibilityValue(selection.accessibilityName)
            .accessibilityHint("Choose the shape of the photo")
            .accessibilityShowsLargeContentViewer { Label("Photo ratio \(selection.title)", systemImage: selection.symbolName) }
    }
}

/// A UIKit button with a native menu (checkmark = in use). UIKit so the menu's text size can be
/// limited (`LimitedMenuButton`): a menu of two short items over the camera image stops at
/// `AppFont.photoRatioMenuMaximumContentSizeCategory` (the ratio is also shown at the top of the camera).
private struct RatioMenuButton: UIViewRepresentable {
    let selection: CameraAspectRatio
    let onSelect: (CameraAspectRatio) -> Void

    func makeUIView(context: Context) -> LimitedMenuButton {
        let button = LimitedMenuButton(frame: .zero)
        button.menuMaximumContentSizeCategory = AppFont.photoRatioMenuMaximumContentSizeCategory
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.layer.cornerRadius = 26
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        button.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        button.tintColor = GoPhotoPalette.tagText
        return button
    }

    func updateUIView(_ button: LimitedMenuButton, context: Context) {
        let symbol = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        button.setImage(UIImage(systemName: selection.symbolName, withConfiguration: symbol), for: .normal)
        let onSelect = onSelect
        let actions = CameraAspectRatio.allCases.map { ratio in
            let action = UIAction(title: ratio.title,
                                  image: UIImage(systemName: ratio.symbolName),
                                  state: ratio == selection ? .on : .off) { _ in onSelect(ratio) }
            action.accessibilityLabel = ratio.accessibilityName
            return action
        }
        button.menu = UIMenu(title: "Photo Ratio", options: .displayInline, children: actions)
    }
}

private extension CameraAspectRatio {
    var symbolName: String {
        switch self {
        case .threeFour: "rectangle.ratio.3.to.4"
        case .nineSixteen: "rectangle.ratio.9.to.16"
        }
    }
}
