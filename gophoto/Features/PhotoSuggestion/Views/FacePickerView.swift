import SwiftUI

struct FacePickerView: View {
    @State private var viewModel = FacePickerViewModel()
    @State private var isShowingLimitedAccessAlert = false
    @State private var isShowingReview = false
    @State private var isConfirmingCancel = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    let onPhotosChosen: ([PhotoItem]) -> Void

    var body: some View {
        Group {
            if isSearching {
                FaceScanLoadingView(progress: scanProgress) { isConfirmingCancel = true }
            } else {
                resultPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PotoDesign.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsContinue {
                // Picking a person is a separate step from going on, so a mistaken tap is harmless.
                SessionPrimaryButton(title: "Continue", isEnabled: viewModel.pickedGroup != nil) {
                    isShowingReview = true
                }
                .padding(.horizontal, PotoDesign.sessionMargin)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .glassBar(.bottom)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        // While searching, Cancel on the page is the way back.
        .navigationBarBackButtonHidden(isSearching)
        .sensoryFeedback(.selection, trigger: viewModel.pickedGroup?.id)
        // `.task` runs again each time the screen reappears (back from Your Photos): scan only once.
        .task { viewModel.startIfNeeded() }
        .onDisappear { if !isShowingReview { viewModel.clear() } }
        .onChange(of: viewModel.state) { _, state in
            isShowingLimitedAccessAlert = state == .limitedAccess
        }
        // The search finished behind the popup: there is nothing left to stop.
        .onChange(of: isSearching) { _, searching in
            if !searching { isConfirmingCancel = false }
        }
        .appAlert("Stop finding faces?", isPresented: $isConfirmingCancel,
                  message: "Your progress won't be saved, and you'll need to start the search again.",
                  actions: [.secondary("Stop", handler: cancelSearch), .primary("Keep Looking")])
        .appAlert("Works best with full access", isPresented: $isShowingLimitedAccessAlert,
                  message: "Poto can only look through the photos you've shared with it. Allow access to all photos in Settings to find more photos of you.",
                  actions: [
                    .primary("Open Settings") {
                        viewModel.dismissLimitedAccess()
                        openSettings()
                    },
                    .secondary("Continue anyway") { viewModel.continueWithLimitedAccess() },
                    .secondary("Cancel") {
                        viewModel.dismissLimitedAccess()
                        dismiss()
                    }
                  ])
        .navigationDestination(isPresented: $isShowingReview) {
            PhotoReviewView(candidates: viewModel.includedPhotos, leftOut: viewModel.groupPhotos) { items in
                viewModel.clear()
                onPhotosChosen(items)
            }
        }
    }

    /// The loading page: from the moment the screen opens until there is a result to show.
    private var isSearching: Bool {
        switch viewModel.state {
        case .scanning, .limitedAccess: true
        case .idle: !viewModel.isWaitingForManualStart
        default: false
        }
    }

    private var scanProgress: FaceGroupingProgress {
        if case .scanning(let progress) = viewModel.state { return progress }
        return FaceGroupingProgress(photosChecked: 0, facesFound: 0)
    }

    private var showsContinue: Bool {
        viewModel.state == .done && !viewModel.groups.isEmpty
    }

    private func cancelSearch() {
        viewModel.cancelScan()
        dismiss()
    }

    private var resultPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 36) {
                    Text("Which one is you?")
                        .font(PotoDesign.largeTitle)
                        .foregroundStyle(PotoDesign.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    content
                }
                .padding(.horizontal, PotoDesign.sessionMargin)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .limitedAccess:
            SessionPrimaryButton(title: "Scan my photos") { viewModel.start() }
        case .unsupported:
            message("Finding your photos automatically needs iOS 27. Choose photos yourself instead.")
        case .needsAccess:
            message("Allow Poto to access your photos in Settings to scan them.")
            Button("Open Settings", action: openSettings)
                .buttonStyle(.potoText)
        case .scanning:
            EmptyView()     // Shown by `FaceScanLoadingView`.
        case .done:
            if viewModel.groups.isEmpty {
                message("No faces found in your recent photos.")
            } else {
                people
            }
        case .failed(let text):
            message(text)
            Button("Try again") { viewModel.start() }
                .buttonStyle(.potoText)
        }
    }

    private var people: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: 2), spacing: 24) {
                ForEach(Array(viewModel.shownGroups.enumerated()), id: \.element.id) { index, group in
                    let isPicked = viewModel.pickedGroup?.id == group.id
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { viewModel.pick(group) }
                    } label: {
                        PersonCard(image: viewModel.covers[group.id],
                                   photoCount: group.assetIDs.count,
                                   isSelected: isPicked)
                    }
                    .buttonStyle(.plain)
                    // Voice Control: "Tap Person 2". Every group was just "N photos", so the
                    // names were all different counts or all the same.
                    .accessibilityLabel("Person \(index + 1), \(group.assetIDs.count) photos")
                    .accessibilityInputLabels(["Person \(index + 1)"])
                    .accessibilityAddTraits(isPicked ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
            // New people fade in below instead of popping in.
            .animation(.easeOut(duration: 0.25), value: viewModel.shownGroups.count)

            VStack(spacing: 6) {
                if viewModel.hasMoreGroups {
                    Button(viewModel.isLoadingMoreGroups ? "Loading…" : "Not here? Show more people") {
                        Task { await viewModel.showMoreGroups() }
                    }
                    .buttonStyle(.potoText)
                    .disabled(viewModel.isLoadingMoreGroups)
                }
                Text("\(viewModel.groups.count) people from \(viewModel.faceCount) faces in \(viewModel.photosChecked) photos")
                    .font(PotoDesign.caption)
                    .foregroundStyle(PotoDesign.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(PotoDesign.body)
            .foregroundStyle(PotoDesign.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// One person: their face, how many photos they are in, and whether they are the one picked.
private struct PersonCard: View {
    let image: UIImage?
    let photoCount: Int
    let isSelected: Bool

    private static let cornerRadius: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        VStack(spacing: 8) {
            PersonCover(image: image)
            Text("\(photoCount) photos")
                .font(PotoDesign.secondaryBody)
                .foregroundStyle(isSelected ? PotoDesign.selectedContent : PotoDesign.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(isSelected ? PotoDesign.selectedSurface : PotoDesign.surface, in: shape)
        .overlay {
            shape.strokeBorder(isSelected ? PotoDesign.selectedContent : PotoDesign.border,
                               lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(shape)
    }
}

private struct PersonCover: View {
    let image: UIImage?

    var body: some View {
        // A square that fills the card's width, whatever the photo's shape.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    PotoDesign.primarySubtle
                        .overlay { Image(systemName: "person.fill").foregroundStyle(PotoDesign.primary) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
