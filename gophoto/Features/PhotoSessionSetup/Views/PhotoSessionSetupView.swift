import Observation
import SwiftUI

struct PhotoSessionSetupView: View {
    @State private var selection = PhotoSessionSetupSelection()
    @State private var isPresentingPicker = false
    /// Brian's "Add Your Photos" flow (66303bd / 8245a3e), restored 16 Nov after merge da8cbd7
    /// dropped it: choose photos myself, or find my photos for me (face grouping, iOS 27).
    @State private var isChoosingPhotoSource = false
    @State private var isShowingFacePicker = false
    /// The picker was opened from the photo source choice: closing it goes back there.
    @State private var pickerReturnsToPhotoSource = false
    /// The card selected when the photo source choice opens.
    @State private var photoSourceSelection = PhotoPickMethod.suggested
    /// Taste rules: "Choose photos myself" = Mode 1 (favorites), "Find my photos for me" = Mode 2
    /// (all photos of me). Saved per preference when it is created (`ReferencePhotoModeStore`).
    @State private var photoMode: ReferencePhotoMode = .favorites
    /// The custom preference flow while it is open (a new one each time it opens).
    @State private var customPreferenceFlow: CustomPreferenceFlowModel?
    @State private var updateError: String?
    @State private var isConfirmingLeave = false
    @State private var isSelecting = false
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var isConfirmingDeletePhotos = false
    @State private var isShowingNameModal = false
    @State private var collectionName = ""
    @State private var hasAutoOpenedPicker = false
    /// The saved preference's last run found too few photos of exactly one person (or could not check
    /// some): nothing was analysed.
    @State private var subjectWarning: HumanSubjectValidationResult?
    /// The warning above was raised once on this screen. The check's result stays in the view
    /// model until the photos change, and `onAppear` runs again whenever this screen comes back
    /// (after the photo source choice, after the picker): without this, the warning came back
    /// each time, and raised while the picker was being presented it dismissed the picker.
    @State private var hasShownSubjectWarning = false
    /// A photo the person check left out, tapped to see why (and to check again or replace it).
    @State private var inspectedPhoto: InspectedPhoto?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let preferences: PreferencesViewModel
    let onCreatePreference: ([PhotoItem], String, @escaping (Result<UUID, PreferenceNameError>) -> Void) -> Void
    let onStartAnalyzing: (UUID) -> Void
    /// A custom preference (placement + angle) was saved; the opener shows the preference list.
    let onCustomPreferenceCreated: (UUID) -> Void
    /// Cancel on the "Not Enough Photos with People" warning: the opener deletes the saved
    /// preference being created and leaves this flow for Choose Preference. Nil: Cancel only
    /// closes the warning.
    let onDiscardPreference: ((UUID) -> Void)?
    private let showsBackButton: Bool

    init(
        savedPreference: Preference? = nil,
        preferences: PreferencesViewModel = .shared,
        onCreatePreference: @escaping ([PhotoItem], String, @escaping (Result<UUID, PreferenceNameError>) -> Void) -> Void,
        onStartAnalyzing: @escaping (UUID) -> Void,
        onCustomPreferenceCreated: @escaping (UUID) -> Void,
        onDiscardPreference: ((UUID) -> Void)? = nil,
        showsBackButton: Bool = false
    ) {
        let persistedPreference = savedPreference.flatMap { preferences.preference(id: $0.id) }
        _selection = State(initialValue: PhotoSessionSetupSelection(
            photos: persistedPreference?.photos ?? [],
            preferenceID: persistedPreference?.id,
            limit: persistedPreference.map { ReferencePhotoModeStore.mode(for: $0.id).maxPhotos }
                ?? ChoosePhotosViewModel.maxPhotos
        ))
        self.preferences = preferences
        self.onCreatePreference = onCreatePreference
        self.onStartAnalyzing = onStartAnalyzing
        self.onCustomPreferenceCreated = onCustomPreferenceCreated
        self.onDiscardPreference = onDiscardPreference
        self.showsBackButton = showsBackButton
    }

    // Split in two so the compiler type-checks each half in reasonable time.
    var body: some View {
        withScreenAlerts(withSubjectAlerts(screen))
    }

    private func withScreenAlerts<Content: View>(_ content: Content) -> some View {
        content
        .appAlert("Leave without saving?", isPresented: $isConfirmingLeave,
                  message: "If you leave now, your selected photos won't be saved.",
                  actions: [.secondary("Leave", handler: leaveWithoutSaving), .primary("Stay")])
        .appAlert("Something went wrong", isPresented: Binding(
            get: { updateError != nil },
            set: { if !$0 { updateError = nil } }
        ), message: updateError, actions: [.primary("OK")])
        .appAlert("Update your style?", isPresented: $isConfirmingDeletePhotos,
                  message: "Removing these photos will update your style. Continue?",
                  actions: [.secondary("Cancel"), .primary("Continue", handler: removeSelectedPhotos)])
    }

    /// The person-check alerts: "Not Enough Photos with People" and a tapped flagged photo.
    private func withSubjectAlerts<Content: View>(_ content: Content) -> some View {
        content
        // The confirmed invalid photos were already removed (and saved) by the check: the
        // grid behind shows what is left. Continue stays here to add photos; photos that
        // could not be checked are tapped one by one (Check Again / Remove Photo).
        .appAlert(HumanSubjectValidationResult.warningTitle,
                  isPresented: Binding(get: { subjectWarning != nil },
                                       set: { if !$0 { subjectWarning = nil } }),
                  message: subjectWarning?.warningMessage,
                  actions: [.secondary("Cancel") {
                                subjectWarning = nil
                                discardPreference()
                            },
                            .primary("Continue") { subjectWarning = nil }])
        .appAlert(inspectedPhoto?.title ?? "",
                  isPresented: Binding(get: { inspectedPhoto != nil },
                                       set: { if !$0 { inspectedPhoto = nil } }),
                  message: inspectedPhoto?.message,
                  actions: inspectedPhotoActions)
    }

    /// One main action: Check Again when the photo can be checked again, otherwise Keep.
    private var inspectedPhotoActions: [AppAlertAction] {
        guard let inspected = inspectedPhoto else { return [] }
        let remove = AppAlertAction.secondary("Remove Photo") {
            inspectedPhoto = nil
            removePhoto(inspected.photoID)
        }
        guard inspected.canCheckAgain else {
            return [remove, .primary("Keep") { inspectedPhoto = nil }]
        }
        return [.primary("Check Again") {
                    inspectedPhoto = nil
                    startAnalyzingSavedPreference(checkingAgain: true)
                },
                remove,
                .secondary("Keep") { inspectedPhoto = nil }]
    }

    private var screen: some View {
        GeometryReader { geometry in
            let thumbnailWidth = min(
                180,
                max(80, (geometry.size.width - PotoDesign.sessionMargin * 2 - 24) / 3)
            )

            ZStack {
                VStack(spacing: 0) {
                    if selection.photos.isEmpty {
                        // Scrolls only when Larger Text makes it taller than the screen, so nothing
                        // runs under the bottom buttons; otherwise the message sits centred.
                        ScrollView {
                            VStack(spacing: 0) {
                                headerEmpty
                                    .padding(.top, 8)
                                Spacer(minLength: 24)
                                emptyState
                                Spacer(minLength: 24)
                            }
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)
                    } else if dynamicTypeSize.isAccessibilitySize {
                        // Large text: the header scrolls away with the photos instead of keeping
                        // half the screen.
                        selectedPhotos(thumbnailWidth: thumbnailWidth) {
                            headerWithPhotos
                                .padding(.top, 8)
                                .padding(.bottom, 14)
                        }
                    } else {
                        // Header as in Image 2
                        headerWithPhotos
                            .padding(.top, 8)
                            .padding(.bottom, 14)

                        selectedPhotos(thumbnailWidth: thumbnailWidth) { EmptyView() }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, PotoDesign.sessionMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .appPatternBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActions
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Back button in the navigation bar, like the Custom Preference steps
            // (Choose a Subject Placement). Asks first if there are unsaved photos.
            // Not shown on first-time onboarding (root of the stack, nothing to go back to).
            ToolbarItem(placement: .topBarLeading) {
                if showsBackButton {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                    // Leaving may delete this preference, which must wait for a running save.
                    .disabled(selection.isSavingPhotos)
                }
            }
        }
        // Naming the new preference: the system alert with a text field (HIG: a short single
        // input), so it looks, scales and reads like every iOS prompt.
        .appAlert("What's this collection for?", isPresented: $isShowingNameModal,
                  message: "For example: beach trip, outfit of the day, city, or night out.",
                  textField: AppAlertTextField(text: $collectionName,
                                               inputLabels: ["Collection name", "Name"],
                                               requiresText: true),
                  actions: [.secondary("Cancel"),
                            .primary("Continue") {
                                guard let name = trimmedCollectionName else { return }
                                saveAndAnalyze(name: name)
                            }])
        .navigationDestination(isPresented: isShowingCustomPreference) {
            if let customPreferenceFlow {
                SubjectPlacementSelectionView(model: customPreferenceFlow)
            }
        }
        .navigationDestination(isPresented: $isChoosingPhotoSource) {
            PhotoSourceChoiceView(initialSelection: photoSourceSelection) { source in
                photoSourceSelection = source
                switch source {
                case .manual:
                    photoMode = .favorites
                    selection.limit = ReferencePhotoMode.favorites.maxPhotos
                    isChoosingPhotoSource = false
                    openPicker()
                    pickerReturnsToPhotoSource = isPresentingPicker
                case .suggested:
                    photoMode = .allOfMe
                    selection.limit = ReferencePhotoMode.allOfMe.maxPhotos
                    isShowingFacePicker = true
                }
            }
            .navigationDestination(isPresented: $isShowingFacePicker) {
                FacePickerView { items in
                    selection.replace(with: items)
                    isShowingFacePicker = false
                    isChoosingPhotoSource = false
                }
            }
        }
        .onAppear {
            reloadSavedPreference()
            showSubjectWarningIfNeeded()
        }
        .fullScreenCover(isPresented: $isPresentingPicker) {
            PhotoSessionPhotoPicker(
                initialPhotos: selection.photos,
                canRemove: !selection.hasSavedPreference,
                // New preference: Done adds the photos at once. Saved preference: its style changes.
                confirmsStyleUpdate: selection.hasSavedPreference,
                limit: selection.limit,
                onSelection: selectedPhotosChanged,
                onCancel: pickerCancelled,
                onFinish: pickerFinished
            )
            .ignoresSafeArea()
        }
        .tint(PotoDesign.primary)
    }

    // MARK: - Header (Image 2 style)

    private var headerWithPhotos: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                // Title and Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reference Photos")
                        .font(AppFont.scaled(size: 22, weight: .bold, relativeTo: .title2))
                        .foregroundStyle(PotoDesign.primaryText)
                    Text("\(selection.photos.count)/\(max(selection.limit, selection.photos.count))")
                        .font(AppFont.scaled(size: 14, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(PotoDesign.secondaryText)
                }

                Spacer()

                // Select / Cancel button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelecting.toggle()
                        selectedPhotoIDs.removeAll()
                    }
                } label: {
                    Text(isSelecting ? "Cancel" : "Select")
                        .font(AppFont.scaled(size: 17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(PotoDesign.primaryText)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(PotoDesign.surface, in: Capsule())
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }

            privacyNote

            // Plain text, not a button: it says what is missing, and the "+ Add photos" tile
            // right below is the action.
            if let minimumPhotosHint {
                Text(minimumPhotosHint)
                    .font(PotoDesign.body)
                    .foregroundStyle(PotoDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// What is still needed before Analyze appears; nil once there are enough photos, and while
    /// selecting photos to delete.
    private var minimumPhotosHint: String? {
        let missing = ChoosePhotosViewModel.minPhotos - analyzablePhotoCount
        guard missing > 0, !isSelecting else { return nil }
        return "Add \(missing) more photo\(missing == 1 ? "" : "s") to analyze your style."
    }

    private var headerEmpty: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text("New Preference")
                    .font(PotoDesign.largeTitle)
                    .foregroundStyle(PotoDesign.primaryText)
                    .multilineTextAlignment(.center)

                privacyNote
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var privacyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(AppFont.scaled(size: 18, weight: .semibold, relativeTo: .body))
                .foregroundStyle(PotoDesign.primary)

            Text("Your photos stay on this iPhone. They're analyzed on your device and never uploaded.")
                .font(AppFont.scaled(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(PotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PotoDesign.tagBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PotoDesign.primaryBorder.opacity(0.3), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No photos yet")
                .font(PotoDesign.sectionTitle)
                .foregroundStyle(PotoDesign.primaryText)
                .multilineTextAlignment(.center)

            Text("Add at least \(ChoosePhotosViewModel.minPhotos) photos you love to begin.")
                .font(PotoDesign.body)
                .foregroundStyle(PotoDesign.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Selected Photos Grid (3 Columns, 1st item = "+ Add photos" tile)

    private func selectedPhotos<Header: View>(
        thumbnailWidth: CGFloat,
        @ViewBuilder header: () -> Header
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            header()
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(thumbnailWidth), spacing: 10), count: 3),
                spacing: 10
            ) {
                addPhotoTile(width: thumbnailWidth)
                ForEach(selection.photos, id: \.id) { photo in
                    photoCell(photo, width: thumbnailWidth)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 100) // Padding for floating bottom button
            .frame(maxWidth: .infinity)
        }
    }

    private func addPhotoTile(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button(action: openPicker) {
            shape
                .fill(PotoDesign.primarySubtle)
                .overlay {
                    shape.strokeBorder(PotoDesign.primaryBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(AppFont.scaled(size: 24, weight: .medium, relativeTo: .title2))
                            .foregroundStyle(PotoDesign.primary)
                        Text("Add photos")
                            .font(AppFont.scaled(size: 12, weight: .medium, relativeTo: .caption))
                            .foregroundStyle(PotoDesign.primary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(8)
                }
                .frame(width: width, height: width * 4 / 3)
        }
        .buttonStyle(.plain)
        .disabled(isAddingDisabled || isSelecting)
        .opacity(isSelecting ? 0.3 : 1.0)
        .accessibilityLabel("Add Photos")
    }

    private func photoCell(_ photo: PhotoItem, width: CGFloat) -> some View {
        let isChecked = selectedPhotoIDs.contains(photo.id)
        return Button {
            if isSelecting {
                if isChecked {
                    selectedPhotoIDs.remove(photo.id)
                } else {
                    selectedPhotoIDs.insert(photo.id)
                }
            } else if let status = subjectStatus(of: photo), !status.isValid {
                inspectedPhoto = InspectedPhoto(photoID: photo.id, status: status)
            }
        } label: {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: width * 4 / 3)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    subjectBadge(for: photo)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        ZStack {
                            Circle()
                                .fill(isChecked ? PotoDesign.primary : Color.black.opacity(0.3))
                                .frame(width: 24, height: 24)
                            if isChecked {
                                Image(systemName: "checkmark")
                                    .font(AppFont.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 1.5)
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        // Voice Control: "Tap Photo 3". The photo had no name, and the state shown only by the
        // check mark or the warning badge was not exposed.
        .accessibilityLabel("Photo \((selection.photos.firstIndex { $0.id == photo.id } ?? 0) + 1)")
        .accessibilityValue(photoAccessibilityValue(for: photo))
        .accessibilityAddTraits(isSelecting && isChecked ? .isSelected : [])
    }

    private func photoAccessibilityValue(for photo: PhotoItem) -> String {
        guard let status = subjectStatus(of: photo), !status.isValid else { return "" }
        return Self.badgeLabel(for: status)
    }

    // MARK: - Bottom Actions (Floating purple pill button)

    /// With some photos but fewer than the minimum there is no bottom bar at all: the header says
    /// how many are missing and the "+ Add photos" tile adds them.
    @ViewBuilder
    private var bottomActions: some View {
        if isSelecting || selection.photos.isEmpty || analyzablePhotoCount >= ChoosePhotosViewModel.minPhotos {
            bottomActionsBar
        }
    }

    private var bottomActionsBar: some View {
        VStack(spacing: 0) {
            if isSelecting {
                // Delete selected button when in select mode
                Button {
                    // Only a saved preference has a style to update; a new one's photos go at once.
                    if selection.hasSavedPreference {
                        isConfirmingDeletePhotos = true
                    } else {
                        removeSelectedPhotos()
                    }
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete \(selectedPhotoIDs.count) Photos")
                    }
                    .font(AppFont.scaled(size: 16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
                    .background(selectedPhotoIDs.isEmpty ? Color.gray : PotoDesign.error, in: Capsule())
                }
                .disabled(selectedPhotoIDs.isEmpty)
                .accessibilityInputLabels(["Delete", "Delete photos", "Delete selected photos"])
                .padding(.horizontal, PotoDesign.sessionMargin)
                .padding(.bottom, 12)
            } else if analyzablePhotoCount >= ChoosePhotosViewModel.minPhotos {
                // "Analyze X photos": only once enough photos can count (see `analyzablePhotoCount`).
                Button {
                    if selection.hasSavedPreference {
                        startAnalyzingSavedPreference()
                    } else {
                        isShowingNameModal = true
                    }
                } label: {
                    Text("Analyze \(analyzablePhotoCount) photo\(analyzablePhotoCount == 1 ? "" : "s")")
                        .font(AppFont.scaled(size: 16, weight: .semibold, relativeTo: .callout))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .frame(minHeight: 54)
                        .background(
                            canAnalyze
                                ? PotoDesign.primary
                                : PotoDesign.primary.opacity(0.5),
                            in: Capsule()
                        )
                        .shadow(color: PotoDesign.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(!canAnalyze)
                .accessibilityInputLabels(["Analyze", "Analyze photos"])
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            } else {
                SessionPrimaryButton(title: "Add Your Photos", systemImage: "plus.circle", action: addYourPhotos)
                .padding(.horizontal, PotoDesign.sessionMargin)
                .padding(.bottom, 8)

                // A saved preference left without photos (all removed as having no person)
                // gets photos added to it, not a second, custom preference.
                if !selection.hasSavedPreference {
                    Button("Create Custom Preference", action: openCustomPreference)
                        .buttonStyle(.potoText)
                        .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
        .glassBar(.bottom)
    }

    /// The name typed in the naming alert, without surrounding spaces; nil while it is empty.
    private var trimmedCollectionName: String? {
        let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private var isShowingCustomPreference: Binding<Bool> {
        Binding(get: { customPreferenceFlow != nil },
                set: { if !$0 { customPreferenceFlow = nil } })
    }

    private func openCustomPreference() {
        customPreferenceFlow = CustomPreferenceFlowModel(preferences: preferences,
                                                         onCreated: onCustomPreferenceCreated)
    }

    private func saveAndAnalyze(name: String) {
        onCreatePreference(selection.photos, name) { result in
            switch result {
            case .success(let id):
                selection.markPreferenceCreated(id: id, photos: selection.photos)
                ReferencePhotoModeStore.set(photoMode, for: id)
                onStartAnalyzing(id)
            case .failure(let error):
                updateError = error.message
            }
        }
    }

    /// Enough photos to analyse; for a saved preference, also loaded, not saving and not
    /// already being analysed (one run per preference at a time).
    /// Photos that can make up the minimum: all of them before any check (a new preference),
    /// afterwards those whose last check found exactly one foreground person plus those added
    /// since (checked by the Analyze run). Uncertain or not-checkable photos do not count.
    /// Confirmed invalid photos are already gone (removed by the check).
    private var analyzablePhotoCount: Int {
        guard selection.hasSavedPreference else { return selection.photos.count }
        return selection.photos.filter { preferences.countsTowardMinimum(photoID: $0.id) }.count
    }

    private var canAnalyze: Bool {
        guard analyzablePhotoCount >= ChoosePhotosViewModel.minPhotos else { return false }
        guard let id = selection.preferenceID else { return true }
        return selection.canStartAnalyzing && !preferences.isAnalyzing(id)
    }

    /// The existing Add Your Photos action: the photo source choice, or straight to the picker.
    private func addYourPhotos() {
        if FaceGroupingAvailability.isSupported { isChoosingPhotoSource = true } else { openPicker() }
    }

    /// A saved preference (back here after "Not Enough Photos") is analysed again as it is:
    /// no name, and no new preference. `checkingAgain`: Check Again on a flagged photo, which
    /// re-runs the check even below the minimum (the result may let the photo count again).
    private func startAnalyzingSavedPreference(checkingAgain: Bool = false) {
        guard let id = selection.preferenceID else { return }
        if checkingAgain {
            guard selection.canStartAnalyzing, !preferences.isAnalyzing(id) else { return }
        } else {
            guard canAnalyze else { return }
        }
        onStartAnalyzing(id)
    }

    /// Cancel on the warning: the preference being created is deleted (with its saved photo
    /// copies; never the Photos library) by the opener, which returns to Choose Preference.
    private func discardPreference() {
        guard let id = selection.preferenceID, let onDiscardPreference,
              !selection.isSavingPhotos else { return }
        onDiscardPreference(id)
    }

    /// Raises "Not Enough Photos with People" once per visit to this screen (it is a new screen
    /// after every analysis run), and never on top of the photo source choice or the picker.
    private func showSubjectWarningIfNeeded() {
        guard !hasShownSubjectWarning, !isPresentingPicker, !isChoosingPhotoSource,
              let id = selection.preferenceID,
              let failure = preferences.validationFailure(for: id) else { return }
        hasShownSubjectWarning = true
        subjectWarning = failure
    }

    /// Marks a saved preference's photos left out of the analysis by the last person check:
    /// no person or more than one found, or the photo could not be checked. Nothing for valid
    /// (exactly one person) or unchecked photos.
    /// The last person check of this photo (saved preference only).
    private func subjectStatus(of photo: PhotoItem) -> HumanSubjectStatus? {
        guard let id = selection.preferenceID else { return nil }
        return preferences.subjectValidation(for: id)?.status(of: photo.id)
    }

    /// Remove Photo on a flagged photo: it leaves the saved preference (never the Photos
    /// library); the grid shows the rest, ready for a replacement.
    private func removePhoto(_ photoID: UUID) {
        guard let id = selection.preferenceID, !selection.isSavingPhotos else { return }
        selection.isSavingPhotos = true
        preferences.removePhotoPersisted(photoID, from: id) { result in
            selection.isSavingPhotos = false
            switch result {
            case .success(let preference):
                withAnimation { selection.reloadSavedPreference(preference) }
            case .failure(let error):
                updateError = error.message
            }
        }
    }

    @ViewBuilder
    private func subjectBadge(for photo: PhotoItem) -> some View {
        if let status = subjectStatus(of: photo), !status.isValid {
            // Amber: not decided (could not check, or unsure who the main person is); red: rejected.
            let couldNotCheck = status.isProcessingFailure || status.isUncertain
            Image(systemName: couldNotCheck ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, couldNotCheck ? PotoDesign.warning : PotoDesign.error)
                .padding(6)
                .accessibilityLabel(Self.badgeLabel(for: status))
        }
    }

    private static func badgeLabel(for status: HumanSubjectStatus) -> String {
        switch status {
        case .multipleForegroundSubjects: return "More than one person in this photo"
        case .noPersonDetected: return "No person found in this photo"
        case .selfie: return "This photo is a selfie"
        case .uncertainForegroundGrouping: return "Couldn't tell who the main person is in this photo"
        case .imageLoadFailed, .visionFailed, .depthFailed: return "This photo couldn't be checked"
        case .validSingleForegroundSubject: return ""
        }
    }

    private func openPicker() {
        guard !selection.isSavingPhotos, !selection.isStartingAnalysis else { return }
        isPresentingPicker = true
    }

    /// Close on the picker: back to the photo source choice when it was opened from there. It is
    /// restored without animation, behind the picker, so this screen never shows in between.
    private func pickerCancelled() {
        if pickerReturnsToPhotoSource {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isChoosingPhotoSource = true }
        }
        pickerReturnsToPhotoSource = false
        isPresentingPicker = false
    }

    private func pickerFinished() {
        pickerReturnsToPhotoSource = false
        photoSourceSelection = .suggested
        isPresentingPicker = false
    }

    private var isAddingDisabled: Bool {
        selection.isSavingPhotos || selection.isStartingAnalysis || (selection.hasSavedPreference && !selection.isPersistedPreferenceLoaded)
    }

    private func goBack() {
        if hasUnsavedPhotos || isUnfinishedNewPreference {
            isConfirmingLeave = true
        } else {
            dismiss()
        }
    }

    private func leaveWithoutSaving() {
        if isUnfinishedNewPreference {
            discardPreference()
        } else {
            dismiss()
        }
    }

    private var hasUnsavedPhotos: Bool {
        !selection.photos.isEmpty && !selection.hasSavedPreference
    }

    /// A preference being created whose analysis was stopped or failed: it is saved only so the
    /// user can fix its photos here, and leaving deletes it. Only the Add New Preference flow
    /// passes `onDiscardPreference` with a Back button, so an existing preference never gets here.
    private var isUnfinishedNewPreference: Bool {
        showsBackButton && onDiscardPreference != nil && selection.hasSavedPreference
    }

    private func reloadSavedPreference() {
        guard let id = selection.preferenceID else { return }
        selection.isPersistedPreferenceLoaded = false
        preferences.loadPersistedPreference(id: id) { result in
            switch result {
            case .success(let preference):
                guard preference.id == id else {
                    selection.isPersistedPreferenceLoaded = false
                    updateError = "The saved preference could not be verified."
                    return
                }
                selection.reloadSavedPreference(preference)
            case .failure:
                selection.isPersistedPreferenceLoaded = false
                updateError = "The saved preference couldn't be loaded. Please return and try again."
            }
        }
    }

    private func removeSelectedPhotos() {
        guard let id = selection.preferenceID else {
            withAnimation {
                selection.removePhotos(withIDs: selectedPhotoIDs)
                selectedPhotoIDs.removeAll()
                isSelecting = false
            }
            return
        }
        // A saved preference: removed from its saved copy (never the Photos library).
        guard !selection.isSavingPhotos else { return }
        selection.isSavingPhotos = true
        preferences.removePhotosPersisted(selectedPhotoIDs, from: id) { result in
            selection.isSavingPhotos = false
            switch result {
            case .success(let preference):
                withAnimation {
                    selection.reloadSavedPreference(preference)
                    selectedPhotoIDs.removeAll()
                    isSelecting = false
                }
            case .failure(let error):
                updateError = error.message
            }
        }
    }

    private func selectedPhotosChanged(_ photos: [PhotoItem]) {
        guard let id = selection.preferenceID else {
            selection.replace(with: photos)
            return
        }
        guard !selection.isSavingPhotos else { return }
        selection.isSavingPhotos = true
        preferences.addPhotosPersisted(photos, to: id) { result in
            selection.isSavingPhotos = false
            switch result {
            case .success(let preference):
                selection.reloadSavedPreference(preference)
            case .failure(let error):
                updateError = error.message
            }
        }
    }
}

@Observable
final class PhotoSessionSetupSelection {
    private(set) var photos: [PhotoItem]
    private(set) var preferenceID: UUID?
    var isPersistedPreferenceLoaded: Bool
    /// Most photos `append` keeps: 100 for picked photos, 200 for "Find my photos for me".
    var limit: Int
    var isSavingPhotos = false
    var isStartingAnalysis = false

    var hasSavedPreference: Bool { preferenceID != nil }

    var canContinue: Bool {
        !hasSavedPreference && photos.count >= ChoosePhotosViewModel.minPhotos
    }

    var canStartAnalyzing: Bool {
        hasSavedPreference && isPersistedPreferenceLoaded && !isSavingPhotos && !photos.isEmpty
    }

    init(photos: [PhotoItem] = [], preferenceID: UUID? = nil, limit: Int = ChoosePhotosViewModel.maxPhotos) {
        self.photos = photos
        self.preferenceID = preferenceID
        self.limit = limit
        isPersistedPreferenceLoaded = preferenceID == nil
    }

    func replace(with newPhotos: [PhotoItem]) {
        guard !hasSavedPreference else { return }
        photos = []
        append(newPhotos)
    }

    func remove(photoID: UUID) {
        guard !hasSavedPreference else { return }
        photos.removeAll { $0.id == photoID }
    }

    func removePhotos(withIDs ids: Set<UUID>) {
        guard !hasSavedPreference else { return }
        photos.removeAll { ids.contains($0.id) }
    }

    func markPreferenceCreated(id: UUID, photos: [PhotoItem]) {
        preferenceID = id
        self.photos = photos
        isPersistedPreferenceLoaded = true
    }

    func reloadSavedPreference(_ preference: Preference) {
        guard preferenceID == preference.id else { return }
        photos = preference.photos
        isPersistedPreferenceLoaded = true
    }

    private func append(_ newPhotos: [PhotoItem]) {
        var assetIdentifiers = Set<String>()
        var itemIdentifiers = Set<UUID>()
        for photo in newPhotos {
            guard photos.count < limit else { return }
            guard itemIdentifiers.insert(photo.id).inserted else { continue }
            if let sourceAssetIdentifier = photo.sourceAssetIdentifier {
                guard assetIdentifiers.insert(sourceAssetIdentifier).inserted else { continue }
            }
            photos.append(photo)
        }
    }
}

/// A photo left out by the person check, with why and what can be done (Photo Session Setup).
private struct InspectedPhoto {
    let photoID: UUID
    let status: HumanSubjectStatus

    /// Uncertain or failed checks may pass on another try; confirmed results will not.
    var canCheckAgain: Bool { status.isUncertain || status.isProcessingFailure }

    var title: String {
        switch status {
        case .uncertainForegroundGrouping: "Main Person Unclear"
        case .multipleForegroundSubjects: "More Than One Person"
        case .noPersonDetected: "No Person Found"
        case .selfie: "Selfie"
        case .imageLoadFailed, .visionFailed, .depthFailed: "Photo Couldn't Be Checked"
        case .validSingleForegroundSubject: ""
        }
    }

    var message: String {
        switch status {
        case .uncertainForegroundGrouping:
            "This photo has more than one person, and we couldn't confidently tell whether only one of them is in the foreground. It won't be used for your style. Check it again, or replace it with a photo featuring only yourself."
        case .multipleForegroundSubjects:
            "This photo has more than one person in the foreground. Please use photos featuring only yourself."
        case .noPersonDetected:
            "We couldn't find a person in this photo. Please use photos that clearly show you."
        case .selfie:
            "Selfies aren't used: your style comes from how others photograph you. Please use photos someone else took of you."
        case .imageLoadFailed, .visionFailed, .depthFailed:
            "Something went wrong while checking this photo. Check it again, or replace it."
        case .validSingleForegroundSubject:
            ""
        }
    }
}
