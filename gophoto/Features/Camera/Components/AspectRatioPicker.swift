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

/// A UIKit button with a native menu (checkmark = in use). Its text size is the app's, like every
/// other menu (`AppFont.maximumContentSizeCategory`, set on the window scene).
private struct RatioMenuButton: UIViewRepresentable {
    let selection: CameraAspectRatio
    let onSelect: (CameraAspectRatio) -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(frame: .zero)
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.layer.cornerRadius = 26
        button.layer.borderWidth = 1.25
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        button.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        button.tintColor = UIColor(red: 233 / 255, green: 223 / 255, blue: 244 / 255, alpha: 1)
        button.setImage(RatioIcon.image, for: .normal)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
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

/// The button's glyph: a rounded panel cut into a top-and-right band and two blocks. No SF Symbol
/// has this shape, so it is drawn here (design units: 76 × 61).
private enum RatioIcon {
    static let image: UIImage = {
        let size = CGSize(width: 25, height: 20)
        let path = CGMutablePath()
        let radius: CGFloat = 8

        // Top bar + right column.
        path.move(to: CGPoint(x: 0, y: 19))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: 76, y: 0), radius: radius)
        path.addArc(tangent1End: CGPoint(x: 76, y: 0), tangent2End: CGPoint(x: 76, y: 61), radius: radius)
        path.addArc(tangent1End: CGPoint(x: 76, y: 61), tangent2End: CGPoint(x: 59, y: 61), radius: radius)
        path.addLine(to: CGPoint(x: 59, y: 61))
        path.addArc(tangent1End: CGPoint(x: 59, y: 19), tangent2End: CGPoint(x: 0, y: 19), radius: 4)
        path.closeSubpath()

        // Left block.
        path.move(to: CGPoint(x: 0, y: 26))
        path.addLine(to: CGPoint(x: 31, y: 26))
        path.addLine(to: CGPoint(x: 31, y: 61))
        path.addArc(tangent1End: CGPoint(x: 0, y: 61), tangent2End: CGPoint(x: 0, y: 26), radius: radius)
        path.closeSubpath()

        // Middle block.
        path.addRect(CGRect(x: 39, y: 26, width: 13, height: 35))

        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.scaleBy(x: size.width / 76, y: size.height / 61)
            context.cgContext.addPath(path)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fillPath()
        }.withRenderingMode(.alwaysTemplate)
    }()
}

private extension CameraAspectRatio {
    var symbolName: String {
        switch self {
        case .threeFour: "rectangle.ratio.3.to.4"
        case .nineSixteen: "rectangle.ratio.9.to.16"
        }
    }
}
