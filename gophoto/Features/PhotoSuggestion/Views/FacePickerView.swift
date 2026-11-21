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
                            .font(PotoDesign.largeTitle)
                            .foregroundStyle(PotoDesign.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text("Poto looks through your photos for your face. Everything stays on this iPhone.")
                            .font(PotoDesign.body)
                            .foregroundStyle(PotoDesign.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }
                .padding(PotoDesign.sessionMargin)
                // At least the screen's height, so the scanning progress can sit in the middle.
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .background(PotoDesign.background)
        // Cancel while scanning: in the bottom bar like Continue on the other photo screens (18 Nov).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isScanning {
                Button("Cancel") { viewModel.cancelScan() }
                    .buttonStyle(.potoSecondary)
                    .padding(.horizontal, PotoDesign.sessionMargin)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .glassBar(.bottom)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        // `.task` runs again each time the screen reappears (back from Your Photos): scan only once.
        .task { viewModel.startIfNeeded() }
        .onDisappear { if !isShowingReview { viewModel.clear() } }
        .onChange(of: viewModel.state) { _, state in
            isShowingLimitedAccessAlert = state == .limitedAccess
        }
        .appAlert("Works best with full access", isPresented: $isShowingLimitedAccessAlert,
                  message: "Poto can only look through the photos you've shared with it. Allow access to all photos in Settings to find more photos of you.",
                  actions: [
                    .primary("Open Settings") {
                        viewModel.dismissLimitedAccess()
                        openSettings()
                    },
                    .secondary("Continue anyway") { viewModel.continueWithLimitedAccess() },
                    .secondary("Cancel") { viewModel.dismissLimitedAccess() }
                  ])
        .navigationDestination(isPresented: $isShowingReview) {
            PhotoReviewView(candidates: viewModel.includedPhotos, leftOut: viewModel.groupPhotos) { items in
                viewModel.clear()
                onPhotosChosen(items)
            }
        }
    }

    private var isScanning: Bool {
        if case .scanning = viewModel.state { return true }
        return false
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
                .buttonStyle(.potoText)
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
                                .font(PotoDesign.caption)
                                .foregroundStyle(PotoDesign.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    // Voice Control: "Tap Person 2". Every group was just "N photos", so the
                    // names were all different counts or all the same.
                    .accessibilityLabel("Person \(index + 1), \(group.assetIDs.count) photos")
                    .accessibilityInputLabels(["Person \(index + 1)"])
                }
            }
            // New people fade in below instead of popping in.
            .animation(.easeOut(duration: 0.25), value: viewModel.shownGroups.count)
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
        }
    }

    /// Spinner in the middle of the screen, the counts on their own line (18 Nov).
    private func scanningProgress(_ progress: FaceGroupingProgress) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
                .tint(PotoDesign.primary)
            Text("Looking for faces…")
                .font(PotoDesign.cardTitle)
                .foregroundStyle(PotoDesign.primaryText)
            Text("\(progress.photosChecked) photos · \(progress.facesFound) faces")
                .font(PotoDesign.caption)
                .foregroundStyle(PotoDesign.secondaryText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(PotoDesign.body)
            .foregroundStyle(PotoDesign.secondaryText)
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
                Circle().fill(PotoDesign.primarySubtle)
                    .overlay { Image(systemName: "person.fill").foregroundStyle(PotoDesign.primary) }
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
    }
}
