import SwiftUI

struct FacePickerView: View {
    @State private var viewModel = FacePickerViewModel()
    @State private var isShowingLimitedAccessAlert = false
    @State private var isShowingReview = false
    @Environment(\.openURL) private var openURL

    let onPhotosChosen: ([PhotoItem]) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Which one is you?")
                            .font(GoPhotoDesign.largeTitle)
                            .foregroundStyle(GoPhotoDesign.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text("Poto looks through your photos for your face. Everything stays on this iPhone.")
                            .font(GoPhotoDesign.body)
                            .foregroundStyle(GoPhotoDesign.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }
                .padding(GoPhotoDesign.sessionMargin)
                // At least the screen's height, so the scanning progress can sit in the middle.
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .background(GoPhotoDesign.background)
        // Cancel while scanning: in the bottom bar like Continue on the other photo screens (18 Nov).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isScanning {
                Button("Cancel") { viewModel.cancelScan() }
                    .buttonStyle(.goPhotoSecondary)
                    .padding(.horizontal, GoPhotoDesign.sessionMargin)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .glassBar(.bottom)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.start() }
        .onDisappear { if !isShowingReview { viewModel.clear() } }
        .onChange(of: viewModel.state) { _, state in
            isShowingLimitedAccessAlert = state == .limitedAccess
        }
        .alert("Works best with full access", isPresented: $isShowingLimitedAccessAlert) {
            Button("Open Settings") {
                viewModel.dismissLimitedAccess()
                openSettings()
            }
            Button("Continue anyway") { viewModel.continueWithLimitedAccess() }
            Button("Cancel", role: .cancel) { viewModel.dismissLimitedAccess() }
        } message: {
            Text("Poto can only look through the photos you've shared with it. Allow access to all photos in Settings to find more photos of you.")
        }
        .navigationDestination(isPresented: $isShowingReview) {
            PhotoReviewView(candidates: viewModel.includedPhotos, leftOut: viewModel.groupPhotos) { items in
                viewModel.clear()
                onPhotosChosen(items)
            }
        }
    }

    /// A scan with nobody saved yet (a saved person's screen keeps scanning quietly underneath).
    private var isScanning: Bool {
        guard !viewModel.hasSavedPerson, case .scanning = viewModel.state else { return false }
        return true
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.hasSavedPerson {
            savedPerson
        } else {
            scanContent
        }
    }

    /// Found before (FaceScanStore): their photos at once, new ones added by the running scan.
    private var savedPerson: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(viewModel.includedPhotos.count) photos of you")
                .font(GoPhotoDesign.body)
                .foregroundStyle(GoPhotoDesign.primaryText)
            Text(viewModel.savedStatus)
                .font(GoPhotoDesign.caption)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            SessionPrimaryButton(title: "Continue") { isShowingReview = true }
            Button("Not you? Choose again") { viewModel.forgetSavedPerson() }
                .buttonStyle(.goPhotoText)
        }
    }

    @ViewBuilder
    private var scanContent: some View {
        switch viewModel.state {
        case .idle, .limitedAccess:
            SessionPrimaryButton(title: "Scan my photos") { viewModel.start() }
        case .unsupported:
            message("Finding your photos automatically needs iOS 27. Choose photos yourself instead.")
        case .needsAccess:
            message("Allow Poto to access your photos in Settings to scan them.")
            Button("Open Settings", action: openSettings)
                .buttonStyle(.goPhotoText)
        case .scanning(let progress):
            scanningProgress(progress)
        case .done:
            if viewModel.groups.isEmpty {
                message("No faces found in your recent photos.")
            } else {
                people
            }
        case .failed(let text):
            message(text)
            Button("Try again") { viewModel.start() }
                .buttonStyle(.goPhotoText)
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                ForEach(Array(viewModel.shownGroups.enumerated()), id: \.element.id) { index, group in
                    Button {
                        viewModel.pick(group)
                        isShowingReview = true
                    } label: {
                        VStack(spacing: 6) {
                            PersonCover(image: viewModel.covers[group.id])
                            Text("\(group.assetIDs.count) photos")
                                .font(GoPhotoDesign.caption)
                                .foregroundStyle(GoPhotoDesign.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    // Voice Control: "Tap Person 2". Every group was just "N photos", so the
                    // names were all different counts or all the same.
                    .accessibilityLabel("Person \(index + 1), \(group.assetIDs.count) photos")
                    .accessibilityInputLabels(["Person \(index + 1)"])
                }
            }
            if viewModel.hasMoreGroups {
                Button("Not here? Show more people") { viewModel.showAllGroups() }
                    .buttonStyle(.goPhotoText)
            }
            Text("\(viewModel.groups.count) people from \(viewModel.faceCount) faces in \(viewModel.photosChecked) photos")
                .font(GoPhotoDesign.caption)
                .foregroundStyle(GoPhotoDesign.secondaryText)
        }
    }

    /// Spinner in the middle of the screen, the counts on their own line (18 Nov).
    private func scanningProgress(_ progress: FaceGroupingProgress) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
                .tint(GoPhotoDesign.primary)
            Text("Looking for faces…")
                .font(GoPhotoDesign.cardTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
            Text("\(progress.photosChecked) photos · \(progress.facesFound) faces")
                .font(GoPhotoDesign.caption)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(GoPhotoDesign.body)
            .foregroundStyle(GoPhotoDesign.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

private struct PersonCover: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(GoPhotoDesign.primarySubtle)
                    .overlay { Image(systemName: "person.fill").foregroundStyle(GoPhotoDesign.primary) }
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
    }
}
