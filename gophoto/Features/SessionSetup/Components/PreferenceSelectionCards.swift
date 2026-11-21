//
//  PreferenceSelectionCards.swift
//  gophoto
//
//  Created by Sebastian Darren on 11/11/26
//

import SwiftUI

struct PreferenceSelectionCard: View {
    let card: PreferenceCardModel
    let isSelected: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                HStack(spacing: 14) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            name
                            lastUsedTag
                        }
                        summaryAndChips
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailingIndicator
                }
            }
        }
        .padding(14)
        .potoCard(isSelected: isSelected)
    }

    /// Accessibility text sizes: the name and "Last Used" beside the photo with the selection mark
    /// under them (level with the photo's bottom), then the summary and chips at the card's full width.
    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 8) {
                    name
                        // Keeps the name clear of the card's "…" menu in the top corner.
                        .padding(.trailing, 30)
                    lastUsedTag
                    Spacer(minLength: 0)
                    trailingIndicator
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            // The column beside the photo is as tall as the photo, so the mark sits at its bottom.
            .fixedSize(horizontal: false, vertical: true)

            summaryAndChips
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if let style = card.customStyle {
            CustomPreferenceThumbnail(style: style)
        } else {
            PreferenceThumbnail(image: card.thumbnail, cacheKey: card.thumbnailKey)
        }
    }

    /// Wraps onto more lines when it doesn't fit (Larger Text, "Last Used" beside it).
    private var name: some View {
        Text(card.name)
            .font(PotoDesign.cardTitle)
            .foregroundStyle(PotoDesign.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var lastUsedTag: some View {
        if card.isLastUsed {
            Text("Last Used")
                .lineLimit(1)
                .fixedSize()
                .font(PotoDesign.smallLabel)
                .foregroundStyle(PotoDesign.tagText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                // On a selected card the usual tag fill matches the card, so it uses the chips' fill.
                .background(isSelected ? PotoDesign.surface : PotoDesign.tagBackground, in: Capsule())
                .layoutPriority(1)
        }
    }

    private var summaryAndChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.summary)
                .font(PotoDesign.secondaryBody)
                .foregroundStyle(PotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if card.isUpdating {
                Label("Updating your style…", systemImage: "arrow.triangle.2.circlepath")
                    .font(PotoDesign.smallLabel)
                    .foregroundStyle(PotoDesign.tagText)
            } else if !card.chips.isEmpty {
                ChipFlowLayout {
                    ForEach(card.chips, id: \.self) { SessionChip(text: $0, onSelectedCard: isSelected) }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var trailingIndicator: some View {
        switch card.availability {
        case .available:
            SelectionIndicator(isSelected: isSelected)
        case .analyzing:
            ProgressView()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        case .unavailable:
            Image(systemName: "exclamationmark.circle")
                .font(AppFont.system(size: 22))
                .foregroundStyle(PotoDesign.secondaryText)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        }
    }
}

struct AddPreferenceCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(AppFont.system(size: 20, weight: .regular))
                    .foregroundStyle(PotoDesign.primary)
                    .frame(width: 44, height: 44)
                    .background(PotoDesign.surface, in: RoundedRectangle(cornerRadius: PotoDesign.controlCornerRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Style")
                        .font(PotoDesign.cardTitle)
                        .foregroundStyle(PotoDesign.primaryText)
                    // The app analyses the photos with its bundled models; it does not train a model.
                    Text("Add reference photos to personalize your guide.")
                        .font(PotoDesign.secondaryBody)
                        .foregroundStyle(PotoDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(PotoDesign.secondaryText)
            }
            .padding(16)
            .potoCard(fill: PotoDesign.secondaryBackground)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the photo picker to create a preference")
    }
}
