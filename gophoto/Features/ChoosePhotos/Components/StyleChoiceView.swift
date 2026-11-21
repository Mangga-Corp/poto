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
        // Laid out inside the safe area (below the status bar and the navigation bar's Back
        // button), leading-aligned with the page margins like every other screen; one scroll view,
        // so the title, the photos and the buttons all stay reachable at any Larger Text size.
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                LazyVGrid(columns: columns(for: visible.count), spacing: 12) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { position, option in
                        Button { onChoose(option.id) } label: { tile(option, letter: letter(position)) }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                            .accessibilityLabel("Style \(letter(position))")
                    }
                }
                if question.options.count > 3 && !showsAll {
                    Button("Show other styles") { withAnimation { showsAll = true } }
                        .buttonStyle(.potoText)
                        .frame(maxWidth: .infinity)
                }
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, PotoDesign.sessionMargin)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PotoDesign.background.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The shot size this question is about, as a tag (like "Step 1 of 2").
            Text(question.shotTitle)
                .potoTag()
            Text("Which style do you want for your preset?")
                .font(PotoDesign.largeTitle)
                .foregroundStyle(PotoDesign.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Your photos show different ways of being photographed. Pick the one the camera should guide.")
                .font(PotoDesign.body)
                .foregroundStyle(PotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func columns(for count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: count == 3 ? 3 : 2)
    }

    private func letter(_ index: Int) -> String {
        Self.letters.indices.contains(index) ? Self.letters[index] : "\(index + 1)"
    }

    private func tile(_ option: PreferencesViewModel.StyleQuestion.Option, letter: String) -> some View {
        VStack(spacing: 8) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    if let image = option.photo?.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        PotoDesign.secondaryBackground
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: PotoDesign.controlCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: PotoDesign.controlCornerRadius)
                    .stroke(PotoDesign.border, lineWidth: 1))
            Text(letter)
                .font(PotoDesign.cardTitle)
                .foregroundStyle(PotoDesign.primaryText)
        }
        .contentShape(Rectangle())
    }
}
