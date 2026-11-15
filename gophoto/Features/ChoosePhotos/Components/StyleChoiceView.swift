//
//  StyleChoiceView.swift
//  gophoto
//
//  "Which style do you want for your preset?" (taste rules, Mode 1, 15 Nov). Shown after the
//  analysis when one shot size's reference photos hold opposing styles and the scene votes were
//  not clear. One question per shot size; an answer is required (no skip, no "both"). The photos
//  come from one scene when the styles share one (same place, clothes and light).
//  New screen only: the screens that show it just present it.
//

import SwiftUI

struct StyleChoiceView: View {
    let question: PreferencesViewModel.StyleQuestion
    var isSaving = false
    let onChoose: (Int) -> Void
    @State private var showsAll = false

    private static let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]

    var body: some View {
        let visible = showsAll ? question.options : Array(question.options.prefix(3))
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(question.shotTitle.uppercased())
                    .font(GoPhotoDesign.smallLabel)
                    .foregroundStyle(GoPhotoDesign.primary)
                Text("Which style do you want for your preset?")
                    .font(GoPhotoDesign.pageTitle)
                    .foregroundStyle(GoPhotoDesign.primaryText)
                    .multilineTextAlignment(.center)
                Text("Your photos show different ways of being photographed. Pick the one the camera should guide.")
                    .font(GoPhotoDesign.secondaryBody)
                    .foregroundStyle(GoPhotoDesign.secondaryText)
                    .multilineTextAlignment(.center)
            }
            ScrollView {
                LazyVGrid(columns: columns(for: visible.count), spacing: 12) {
                    ForEach(visible) { option in
                        Button { onChoose(option.id) } label: { tile(option) }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                            .accessibilityLabel("Style \(letter(option.id))")
                    }
                }
            }
            if question.options.count > 3 && !showsAll {
                Button("Show other styles") { withAnimation { showsAll = true } }
                    .buttonStyle(.goPhotoText)
            }
            if isSaving { ProgressView() }
        }
        .padding(.horizontal, GoPhotoDesign.horizontalMargin)
        .padding(.top, 48)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoPhotoDesign.background.ignoresSafeArea())
    }

    private func columns(for count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: count == 3 ? 3 : 2)
    }

    private func letter(_ index: Int) -> String {
        Self.letters.indices.contains(index) ? Self.letters[index] : "\(index + 1)"
    }

    private func tile(_ option: PreferencesViewModel.StyleQuestion.Option) -> some View {
        VStack(spacing: 8) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    if let image = option.photo?.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        GoPhotoDesign.secondaryBackground
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: GoPhotoDesign.controlCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: GoPhotoDesign.controlCornerRadius)
                    .stroke(GoPhotoDesign.border, lineWidth: 1))
            Text(letter(option.id))
                .font(GoPhotoDesign.cardTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
        }
        .contentShape(Rectangle())
    }
}
