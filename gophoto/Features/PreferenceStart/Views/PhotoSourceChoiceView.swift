//
//  PhotoSourceChoiceView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 13/11/26.
//
import SwiftUI

enum PhotoPickMethod: CaseIterable, Identifiable {
    case suggested, manual

    var id: Self { self }

    var title: String {
        switch self {
        case .suggested: "Find my photos for me"
        case .manual: "Choose photos myself"
        }
    }

    var subtitle: String {
        switch self {
        case .suggested: "Poto looks through your photos and groups them for you."
        case .manual: "Pick photos from your library yourself."
        }
    }

    var symbol: String {
        switch self {
        case .suggested: "photo.badge.magnifyingglass.fill"
        case .manual: "photo.badge.plus.fill"
        }
    }
}

struct PhotoSourceChoiceView: View {
    let onChoose: (PhotoPickMethod) -> Void

    @State private var selected: PhotoPickMethod

    init(initialSelection: PhotoPickMethod = .suggested, onChoose: @escaping (PhotoPickMethod) -> Void) {
        _selected = State(initialValue: initialSelection)
        self.onChoose = onChoose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("How do you want to add photos?")
                    .font(PotoDesign.largeTitle)
                    .foregroundStyle(PotoDesign.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                // Both cards take the taller one's height.
                VStack(spacing: 16) {
                    ForEach(PhotoPickMethod.allCases) { source in
                        PhotoSourceCard(source: source, isSelected: source == selected)
                            .onTapGesture { select(source) }
                            .accessibilityAction { select(source) }
                            .accessibilityInputLabels([source.title])
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, PotoDesign.sessionMargin)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(PotoDesign.background)
        .sensoryFeedback(.selection, trigger: selected)
        .sessionBottomBar {
            SessionPrimaryButton(title: "Continue") { onChoose(selected) }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ source: PhotoPickMethod) {
        withAnimation(.snappy(duration: 0.2)) { selected = source }
    }
}

private struct PhotoSourceCard: View {
    let source: PhotoPickMethod
    let isSelected: Bool

    private static let cornerRadius: CGFloat = 24
    private static let iconTileSize: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                iconTile
                if source == .suggested {
                    Text("Recommended")
                        .font(PotoDesign.smallLabel)
                        .foregroundStyle(PotoDesign.tagText)
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(PotoDesign.selectedAccent, in: Capsule())
                }
                Spacer(minLength: 8)
                PhotoSourceRadio(isSelected: isSelected)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Wraps onto more lines when it doesn't fit, never cut with "…".
                Text(source.title)
                    .font(PotoDesign.sectionTitle)
                    .foregroundStyle(PotoDesign.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(source.subtitle)
                    .font(PotoDesign.secondaryBody)
                    .foregroundStyle(PotoDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSelected ? PotoDesign.selectedSurface : PotoDesign.surface, in: shape)
        .overlay {
            shape.strokeBorder(isSelected ? PotoDesign.selectedContent : PotoDesign.border,
                               lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var iconTile: some View {
        Image(systemName: source.symbol)
            .font(AppFont.system(size: 22))
            .foregroundStyle(isSelected ? PotoDesign.selectedContent : PotoDesign.secondaryText)
            .frame(width: Self.iconTileSize, height: Self.iconTileSize)
            .background(isSelected ? PotoDesign.selectedAccent : PotoDesign.background,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Radio mark: an empty ring, or a ring with a filled dot.
private struct PhotoSourceRadio: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? PotoDesign.selectedContent : PotoDesign.primaryText, lineWidth: 1.5)
            if isSelected {
                Circle()
                    .fill(PotoDesign.selectedContent)
                    .padding(4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        PhotoSourceChoiceView { _ in }
    }
}
