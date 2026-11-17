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

struct AspectRatioPicker: View, Equatable {
    let selection: CameraAspectRatio
    var onSelect: (CameraAspectRatio) -> Void

    /// Same size as the gallery shortcut, so the shutter row stays symmetric.
    private static let size: CGFloat = 52

    /// The camera screen redraws many times a second (motion, detection); compare only the
    /// selection so an open menu isn't rebuilt underneath the finger.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.selection == rhs.selection }

    var body: some View {
        Menu {
            Picker("Photo Ratio", selection: Binding(get: { selection }, set: onSelect)) {
                ForEach(CameraAspectRatio.allCases) { ratio in
                    Label(ratio.title, systemImage: ratio.symbolName)
                        .accessibilityLabel(ratio.accessibilityName)
                        .tag(ratio)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: selection.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(GoPhotoDesign.tagText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
                .background(.white.opacity(0.1), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Photo ratio")
        .accessibilityValue(selection.accessibilityName)
        .accessibilityHint("Choose the shape of the photo")
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
