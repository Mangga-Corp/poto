//
//  PreferenceSelectionView.swift
//  gophoto
//
//  "What shall we shoot today?": pick the preference for the next session. A card tap
//  only changes the draft selection; Continue hands the preference ID on without starting a
//  session or saving anything. Long-press a card to rename, edit its photos or delete it
//  (custom preferences have no photos, so they offer no Edit Photos).
//

import SwiftUI

struct PreferenceSelectionView: View {
    /// Carries the onboarding preference ID through this route; selection behavior is unchanged.
    let handoffPreferenceID: UUID?
    let hasPreferenceHandoff: Bool
    let selection: PreferenceSelectionViewModel
    /// Continue, with a preference that exists and can start a session.
    let onContinue: (UUID) -> PhotoSessionError?
    let onAddNew: () -> Void
    let onHandoffConsumed: (() -> Void)?

    @State private var anchor = PresentationAnchor()
    @State private var editorPresenter: PreferenceEditorPresenter?
    @State private var renameTarget: PreferenceCardModel?
    @State private var renameText = ""
    @State private var deleteTarget: PreferenceCardModel?
    @State private var errorMessage: String?
    @State private var didApplyHandoff = false

    var body: some View {
        let cards = selection.cards
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                // "Your Preferences" with the Add Style button beside it, or below it when both don't
                // fit on one line (Larger Text): the row never pushes the screen wider than the iPhone.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        preferencesTitle
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        addButton
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        preferencesTitle
                            .fixedSize(horizontal: false, vertical: true)
                        addButton
                    }
                }
                .padding(.top, 28)

                VStack(spacing: 14) {
                    if cards.isEmpty {
                        emptyState
                    }
                    ForEach(cards) { card in
                        cardView(card)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, PotoDesign.sessionMargin)
        }
        .scrollIndicators(.hidden)
        .appPatternBackground()
        .sessionBottomBar {
            SessionPrimaryButton(title: "Continue", isEnabled: selection.continueTarget != nil) {
                // Re-validated at the tap: never hands on a deleted or unusable preference.
                if let id = selection.continueTarget, let error = onContinue(id) {
                    errorMessage = error.message
                }
            }
            .accessibilityIdentifier("preferenceSelection.continue")
            .accessibilityHint(selection.continueTarget == nil ? "Select a preference first" : "Opens the camera")
        }
        .background { PresentationAnchorView(anchor: anchor) }
        .onAppear {
            guard !didApplyHandoff else { return }
            didApplyHandoff = true
            if hasPreferenceHandoff {
                errorMessage = selection.selectHandoff(handoffPreferenceID)
                onHandoffConsumed?()
            } else {
                selection.reconcile()
            }
        }
        .onChange(of: selection.reconcileKey) { selection.reconcile() }
        .appAlert("Rename Preference", isPresented: isPresented($renameTarget),
                  message: "Give this preference a new name.",
                  textField: AppAlertTextField(text: $renameText),
                  actions: [.secondary("Cancel"),
                            .primary("Save") { if let card = renameTarget { saveRename(card) } }])
        .appAlert(deleteTarget.map { "Delete “\($0.name)”?" } ?? "", isPresented: isPresented($deleteTarget),
                  message: "Its photos will be removed. This can’t be undone.",
                  actions: [.secondary("Delete") { if let card = deleteTarget { selection.delete(card.id) } },
                            .primary("Cancel")])
        .appAlert("Something went wrong", isPresented: isPresented($errorMessage),
                  message: errorMessage, actions: [.primary("OK")])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What shall we shoot today?")
                .font(PotoDesign.largeTitle)
                .foregroundStyle(PotoDesign.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Pick a preference for your next shoot.")
                .font(PotoDesign.body)
                .foregroundStyle(PotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 36)
    }

    private var preferencesTitle: some View {
        Text("Your Preferences")
            .font(PotoDesign.sectionTitle)
            .foregroundStyle(PotoDesign.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    /// Opens the same flow the Add New Preference card used to.
    private var addButton: some View {
        Button(action: onAddNew) {
            HStack(spacing: 6) {
                // The "+" has its own automatic name, "Add": Voice Control showed and heard just that.
                Image(systemName: "plus")
                    .font(AppFont.scaled(size: 13, weight: .bold, relativeTo: .subheadline))
                    .accessibilityHidden(true)
                Text("Add Style")
                    .font(AppFont.system(.subheadline, weight: .semibold))
            }
            .foregroundStyle(PotoDesign.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular.interactive(), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Style")
        // The first name is the one Voice Control shows with "Show names".
        .accessibilityInputLabels(["Add Style"])
        .accessibilityHint("Opens the photo picker to create a preference")
        .accessibilityIdentifier("preferenceSelection.addNew")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(AppFont.scaled(size: 30, relativeTo: .title))
                .foregroundStyle(PotoDesign.primary)
            Text("No preferences yet")
                .font(PotoDesign.cardTitle)
                .foregroundStyle(PotoDesign.primaryText)
            Text("Tap Add Style, then add reference photos to begin.")
                .font(PotoDesign.secondaryBody)
                .foregroundStyle(PotoDesign.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .potoCard()
    }

    private func cardView(_ card: PreferenceCardModel) -> some View {
        let isSelected = selection.draftSelectedID == card.id
        return PreferenceSelectionCard(card: card, isSelected: isSelected)
            .onTapGesture { selection.select(card.id) }
            .contextMenu { managementActions(card) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(card.isAvailable ? "Selects this preference" : card.summary)
            .accessibilityIdentifier("preferenceCard.\(card.name)")
            // Voice Control: "Tap <preference name>" (the spoken label also holds the summary and chips).
            .accessibilityAction { selection.select(card.id) }
            .accessibilityInputLabels([card.name])
            .accessibilityAction(named: "Rename") { startRename(card) }
            .accessibilityActions {
                if card.canEditPhotos {
                    Button("Edit Photos") { editPhotos(card) }
                }
            }
            .accessibilityAction(named: "Delete") { confirmDelete(card) }
            // Visible way into the same actions (long-press still works). Outside the card's
            // combined element so its tap opens the menu instead of selecting the card.
            .overlay(alignment: .topTrailing) {
                Menu { managementActions(card) } label: {
                    Image(systemName: "ellipsis")
                        .font(AppFont.system(size: 15, weight: .semibold))
                        .foregroundStyle(PotoDesign.secondaryText)
                        .frame(width: 44, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More actions for \(card.name)")
                .accessibilityIdentifier("preferenceMenu.\(card.name)")
                .padding(.top, 2)
                .padding(.trailing, 4)
            }
    }

    @ViewBuilder private func managementActions(_ card: PreferenceCardModel) -> some View {
        Button("About This Style", systemImage: "info.circle") { showAbout(card) }
            .disabled(styleSummary(for: card.id) == nil)
            .accessibilityAction(named: "About This Style") { showAbout(card) }
        Button("Rename", systemImage: "pencil") { startRename(card) }
        if card.canEditPhotos {
            Button("Edit Photos", systemImage: "photo.on.rectangle") { editPhotos(card) }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete(card) }
    }

    // MARK: Management (existing operations)

    private func startRename(_ card: PreferenceCardModel) {
        renameText = card.name
        renameTarget = card
    }

    /// Existing rename and its validation (empty or duplicate names are refused).
    private func saveRename(_ card: PreferenceCardModel) {
        guard let error = selection.rename(card.id, to: renameText) else { return }
        // Shown after the rename alert has gone (two alerts can't be presented at once).
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            errorMessage = error
        }
    }

    private func editPhotos(_ card: PreferenceCardModel) {
        guard card.canEditPhotos, let presenter = anchor.presenter else { return }
        let editor = PreferenceEditorPresenter(preferences: selection.preferences)
        editorPresenter = editor   // kept alive while the editor is open
        editor.presentEditor(for: card.id, from: presenter) { _ in editorPresenter = nil }
    }

    private func showAbout(_ card: PreferenceCardModel) {
        guard let presenter = anchor.presenter,
              let summary = styleSummary(for: card.id) else { return }
        let styleCard = StyleCardViewController(summary: summary, buttonTitle: "Done")
        styleCard.modalPresentationStyle = .fullScreen
        styleCard.onDone = { [weak styleCard] in styleCard?.dismiss(animated: true)}
        presenter.present(styleCard, animated: true)
    }

    private func styleSummary(for id: UUID) -> StyleSummary? {
        guard let preference = selection.preferences.preference(id: id),
              preference.analysis?.usability == .usable else { return nil }
        return StyleSummary(analysis: preference.analysis, photos: preference.analyzedPhotos)
    }

    private func confirmDelete(_ card: PreferenceCardModel) {
        deleteTarget = card
    }

    private func isPresented<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}
