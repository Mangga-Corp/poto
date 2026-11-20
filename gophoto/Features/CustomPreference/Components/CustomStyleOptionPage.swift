//
//  CustomStyleOptionPage.swift
//  gophoto
//
//  One step of the custom preference flow: a single-choice list of option cards, each with a
//  photo, its name and what it does, and a fixed primary button that needs a choice.
//  The page title scrolls with the content and hands over to a compact title in the navigation
//  bar (like the App Store): while the large title passes under the bar it fades and shrinks
//  away as the compact one fades and slides in, driven by the scroll position, so the step stays
//  readable and the change follows the finger in both directions.
//

import SwiftUI

struct CustomStyleOptionPage<Option: CustomStyleOption, Artwork: View>: View {
    let step: Int
    let stepCount: Int
    let title: String
    let message: String
    @Binding var selection: Option?
    var isOptionAvailable: ((Option) -> Bool)? = nil
    let primaryTitle: String
    /// The name the preference will be saved with, once the choices are made: shown after the
    /// options, in the content (not in the bottom bar, where it would cover the options).
    var savedName: String?
    var isLoading = false
    let onPrimary: () -> Void
    /// Drawn when the option has no photo in the asset catalog.
    @ViewBuilder let artwork: (Option) -> Artwork

    /// The large title's frame in the scroll content (nil until laid out).
    @State private var titleFrame: CGRect?
    /// How far the large title has passed under the navigation bar: 0 = fully visible,
    /// 1 = fully under it (the bar's compact title is then fully shown).
    @State private var titleCollapse: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var contentSpace: String { "CustomStyleOptionPage.content" }
    /// Large title: how much it shrinks when fully collapsed.
    private static var collapsedTitleScale: CGFloat { 0.94 }
    /// Compact title: how far below its place it starts sliding in from.
    private static var compactTitleSlide: CGFloat { 8 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LazyVStack(spacing: 14) {
                    ForEach(Option.allCases) { option in
                        let isAvailable = isOptionAvailable?(option) ?? true
                        CustomStyleOptionCard(option: option, isSelected: option == selection, isAvailable: isAvailable) {
                            artwork(option)
                        }
                        .onTapGesture {
                            if isAvailable { select(option) }
                        }
                        // Voice Control: "Tap <option name>" (the spoken label also holds the summary).
                        .accessibilityAction { if isAvailable { select(option) } }
                        .accessibilityInputLabels([option.title])
                    }
                }
                if let savedName {
                    SavedNameNote(name: savedName)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, GoPhotoDesign.sessionMargin)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy, value: savedName)
            .coordinateSpace(.named(Self.contentSpace))
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Distance scrolled from the resting position, mapped over the title's own height.
            let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
            return Self.collapse(scrolled: scrolled, titleFrame: titleFrame)
        } action: { _, collapse in
            titleCollapse = collapse
        }
        .background(GoPhotoDesign.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: selection)
        .sessionBottomBar {
            SessionPrimaryButton(title: primaryTitle, isEnabled: selection != nil && !isLoading,
                                 isLoading: isLoading, action: onPrimary)
                .accessibilityHint(selection == nil
                                   ? "Choose an option first"
                                   : savedName.map { "Saves it as \($0)" } ?? "")
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(AppFont.headline)
                    .foregroundStyle(GoPhotoDesign.primaryText)
                    .lineLimit(1)
                    .opacity(titleCollapse)
                    .offset(y: reduceMotion ? 0 : (1 - titleCollapse) * Self.compactTitleSlide)
                    .accessibilityHidden(titleCollapse < 0.5)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(step) of \(stepCount)")
                .goPhotoTag()
            Text(title)
                .font(GoPhotoDesign.largeTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .opacity(1 - titleCollapse)
                .scaleEffect(reduceMotion ? 1 : 1 - (1 - Self.collapsedTitleScale) * titleCollapse,
                             anchor: .bottomLeading)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.contentSpace))
                } action: { titleFrame = $0 }
            Text(message)
                .font(GoPhotoDesign.body)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 0 while the large title is below the bar, rising to 1 as its top-to-bottom passes under it.
    /// Rounded to 1% so scrolling doesn't redraw the titles for invisible changes.
    private static func collapse(scrolled: CGFloat, titleFrame: CGRect?) -> CGFloat {
        guard let titleFrame, titleFrame.height > 0 else { return 0 }
        let progress = (scrolled - titleFrame.minY) / titleFrame.height
        return (min(max(progress, 0), 1) * 100).rounded() / 100
    }

    private func select(_ option: Option) {
        guard !isLoading, option != selection else { return }
        withAnimation(.snappy) { selection = option }
    }
}

/// The name the new preference gets, as a quiet note after the options: it says what Create
/// Preference will do without competing with the choices above it.
private struct SavedNameNote: View {
    let name: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "bookmark")
                .font(AppFont.scaled(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(GoPhotoDesign.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Saves as “\(name)”")
                    .font(GoPhotoDesign.secondaryBody.weight(.semibold))
                    .foregroundStyle(GoPhotoDesign.primaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

/// One option: its photo on the left, name and description on the right (photo on top at
/// accessibility text sizes, so the text keeps the card's full width).
private struct CustomStyleOptionCard<Option: CustomStyleOption, Artwork: View>: View {
    let option: Option
    let isSelected: Bool
    var isAvailable: Bool = true
    @ViewBuilder let artwork: () -> Artwork
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static var photoSize: CGSize { CGSize(width: 108, height: 144) }   // 3:4, like a portrait photo

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
    }

    var body: some View {
        layout {
            CustomStyleOptionPhoto(option: option, fallback: artwork)
                .frame(width: Self.photoSize.width, height: Self.photoSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(option.title)
                        .font(GoPhotoDesign.cardTitle)
                        .foregroundStyle(GoPhotoDesign.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !isAvailable {
                        Text("Already Added")
                            .font(GoPhotoDesign.smallLabel)
                            .foregroundStyle(GoPhotoDesign.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(GoPhotoDesign.tagBackground, in: Capsule())
                    } else {
                        SelectionIndicator(isSelected: isSelected)
                    }
                }
                Text(option.summary)
                    .font(GoPhotoDesign.secondaryBody)
                    .foregroundStyle(GoPhotoDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .goPhotoCard(isSelected: isSelected)
        .opacity(isAvailable ? 1.0 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isAvailable ? (isSelected ? [.isButton, .isSelected] : .isButton) : [])
    }
}
