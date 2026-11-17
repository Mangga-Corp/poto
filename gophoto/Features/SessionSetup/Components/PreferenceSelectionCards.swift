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

    /// Name and "Last Used" side by side; stacked at accessibility text sizes so the name keeps its room.
    private var titleLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
    }

    var body: some View {
        HStack(spacing: 14) {
            if let style = card.customStyle {
                CustomPreferenceThumbnail(style: style)
            } else {
                PreferenceThumbnail(image: card.thumbnail, cacheKey: card.thumbnailKey)
            }

            VStack(alignment: .leading, spacing: 6) {
                titleLayout {
                    // One line; runs as a marquee when it doesn't fit (Larger Text, "Last Used" beside it).
                    MarqueeText(text: card.name, font: GoPhotoDesign.cardTitle, color: GoPhotoDesign.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(0)
                    if card.isLastUsed {
                        Text("Last Used")
                            .lineLimit(1)
                            .fixedSize()
                            .goPhotoTag()
                            .layoutPriority(1)
                    }
                }

                MarqueeText(text: card.summary, font: GoPhotoDesign.secondaryBody, color: GoPhotoDesign.secondaryText)

                if card.isUpdating {
                    Label("Updating your style…", systemImage: "arrow.triangle.2.circlepath")
                        .font(GoPhotoDesign.smallLabel)
                        .foregroundStyle(GoPhotoDesign.tagText)
                } else if !card.chips.isEmpty {
                    ChipFlowLayout {
                        ForEach(card.chips, id: \.self) { SessionChip(text: $0, onSelectedCard: isSelected) }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingIndicator
        }
        .padding(14)
        .goPhotoCard(isSelected: isSelected)
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
                .foregroundStyle(GoPhotoDesign.secondaryText)
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
                    .foregroundStyle(GoPhotoDesign.primary)
                    .frame(width: 44, height: 44)
                    .background(GoPhotoDesign.surface, in: RoundedRectangle(cornerRadius: GoPhotoDesign.controlCornerRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Style")
                        .font(GoPhotoDesign.cardTitle)
                        .foregroundStyle(GoPhotoDesign.primaryText)
                    // The app analyses the photos with its bundled models; it does not train a model.
                    Text("Add reference photos to personalize your guide.")
                        .font(GoPhotoDesign.secondaryBody)
                        .foregroundStyle(GoPhotoDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(size: 15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(GoPhotoDesign.secondaryText)
            }
            .padding(16)
            .goPhotoCard(fill: GoPhotoDesign.secondaryBackground)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the photo picker to create a preference")
    }
}

/// One line of text that stays still when it fits and scrolls as running text (a looping marquee)
/// when it doesn't, e.g. with Larger Text. It hugs its text like a plain `Text` and is never wider
/// than offered, so it drops in wherever a one-line `Text` was. With Reduce Motion on it wraps instead.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var gap: CGFloat = 40
    /// Points per second.
    var speed: CGFloat = 30
    /// Rest at the start of every loop, so the beginning can be read.
    var pause: Double = 1.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The whole text on one line.
    @State private var fullWidth: CGFloat = 0
    /// The width the text actually got.
    @State private var visibleWidth: CGFloat = 0
    @State private var start = Date()

    private var overflows: Bool { visibleWidth > 0 && fullWidth > visibleWidth + 0.5 }

    var body: some View {
        Group {
            if reduceMotion {
                label(lineLimit: nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // The truncated one-line text sizes the view; it is swapped for the running text when cut.
                label(lineLimit: 1)
                    .opacity(overflows ? 0 : 1)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
                    .background(alignment: .leading) {
                        label(lineLimit: 1)
                            .fixedSize()
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullWidth = $0 }
                    }
                    .overlay(alignment: .leading) {
                        if overflows { running }
                    }
                    .clipped()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onChange(of: text) { start = .now }
    }

    private var running: some View {
        TimelineView(.animation) { context in
            let pitch = fullWidth + gap
            let cycle = pause + Double(pitch / speed)
            let t = max(0, context.date.timeIntervalSince(start)).truncatingRemainder(dividingBy: cycle)
            let offset = t < pause ? 0 : -CGFloat(t - pause) * speed

            HStack(spacing: gap) {
                label(lineLimit: 1).fixedSize()
                label(lineLimit: 1).fixedSize()
            }
            .offset(x: offset)
        }
    }

    private func label(lineLimit: Int?) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
    }
}
