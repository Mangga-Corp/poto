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
        case .suggested: "Poto looks through your library and picks photos of you"
        case .manual: "Pick photos from your library yourself"
        }
    }

    var symbol: String {
        switch self {
        case .suggested: "sparkles"
        case .manual: "hand.tap"
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
        VStack(alignment: .leading, spacing: 0) {
            Text("How do you want to add photos?")
                .font(PotoDesign.largeTitle)
                .foregroundStyle(PotoDesign.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("You can still add or remove photos before the analysis starts.")
                .font(PotoDesign.body)
                .foregroundStyle(PotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 12) {
                ForEach(PhotoPickMethod.allCases) { source in
                    PhotoSourceCard(source: source, isSelected: source == selected)
                        .onTapGesture { selected = source }
                        .accessibilityAction { selected = source }
                        .accessibilityInputLabels([source.title])
                }
            }
            .padding(.top, 28)
        }
        .padding(.horizontal, PotoDesign.sessionMargin)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PotoDesign.background)
        .sessionBottomBar {
            SessionPrimaryButton(title: "Continue") { onChoose(selected) }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhotoSourceCard: View {
    let source: PhotoPickMethod
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PotoDesign.cardCornerRadius, style: .continuous)
        HStack(spacing: 16) {
            Image(systemName: source.symbol)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                // "Recommended" sits above the title so it never squeezes it.
                if source == .suggested {
                    Text("Recommended")
                        .font(PotoDesign.smallLabel)
                        .foregroundStyle(PotoDesign.tagText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        // On a selected card the usual tag fill matches the card, so it uses the
                        // surface fill; the border keeps the pill visible either way. Its leading
                        // edge lines up with the title below.
                        .background(isSelected ? PotoDesign.surface : PotoDesign.tagBackground,
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(PotoDesign.primaryBorder, lineWidth: 1))
                        .padding(.bottom, 2)
                }
                // Wraps onto more lines when it doesn't fit, never cut with "…".
                Text(source.title)
                    .font(PotoDesign.cardTitle)
                    .foregroundStyle(isSelected ? PotoDesign.selectedContent : PotoDesign.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(source.subtitle)
                    .font(PotoDesign.secondaryBody)
                    .foregroundStyle(isSelected ? PotoDesign.selectedContent : PotoDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle" : "circle")
                .font(.title2)
        }
        .foregroundStyle(isSelected ? PotoDesign.selectedContent : PotoDesign.primaryText)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? PotoDesign.primarySubtle : PotoDesign.surface, in: shape)
        .overlay {
            shape.strokeBorder(isSelected ? PotoDesign.selectedBorder : PotoDesign.border,
                               lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    NavigationStack {
        PhotoSourceChoiceView { _ in }
    }
}
