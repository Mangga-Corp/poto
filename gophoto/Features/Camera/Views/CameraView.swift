//
//  CameraView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//
//  13 Nov (Reynard): production camera only (Phased · Auto crop). The developer camera (appMode 2:
//  debug panel, experiment picker, pose guide, replay, GT, blur toggle, ratio and grid toggles) lives
//  in the debugphoto repo (Lab). The previous version is in `_to_delete/pra-bersih-debug/`.
//

import SwiftUI
import UIKit
import AVFoundation

struct CameraView: View {
    /// The session to guide with, from the navigation that opened the camera. The camera never
    /// chooses a preference itself; its shot size is only the picker's starting point (the
    /// photographer switches shot size above the shutter). Nil = no preset.
    let sessionConfiguration: PhotoSessionConfiguration?
    /// Close (top left): ends the session; the app then returns to Preference Selection.
    /// Nil hides the button (previews).
    let onClose: (() -> Void)?
    /// The close button fires once, even if tapped again during the transition.
    @State private var isClosing = false

    init(sessionConfiguration: PhotoSessionConfiguration? = nil, onClose: (() -> Void)? = nil) {
        self.sessionConfiguration = sessionConfiguration
        self.onClose = onClose
    }

    @State private var viewModel = CameraViewModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var isShowingGallery = false
    @State private var isFlashing = false
    @State private var isShowingAcknowledgements = false
    @Namespace private var galleryZoom
    /// Onboarding kamera: hanya sekali, saat pertama kali install. Teksnya: Onboarding/CameraOnboardingCopy.swift
    @AppStorage("cameraOnboardingCompleted") private var cameraOnboardingCompleted = false
    @State private var onboardingFrames: [CameraOnboardingTarget: CGRect] = [:]
    private var showsCameraOnboarding: Bool { !cameraOnboardingCompleted && viewModel.state == .running }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .idle:
                ProgressView().tint(.white)

            case .running:
                liveCamera
                    .overlay { cameraOnboarding }

            case .permissionDenied:
                permissionDenied

            case .restricted:
                ContentUnavailableView("Camera Not Available",
                                       systemImage: "lock",
                                       description: Text("Camera access is restricted on this iPhone (for example by Screen Time), so GoPhoto can't use it."))
                .foregroundStyle(.white)

            case .failed(let message):
                ContentUnavailableView("Camera Unavailable",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                    .foregroundStyle(.white)
            }

        }
        // No live view (starting, no permission, unavailable): the top bar isn't shown, so the
        // close button is, to leave the camera from any state.
        .overlay(alignment: .topLeading) {
            if viewModel.state != .running { closeButton }
        }
        .onChange(of: sessionConfiguration, initial: true) { _, configuration in
            viewModel.apply(sessionConfiguration: configuration)
        }
        .task { await viewModel.startCamera() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.recheckPermission() }
            }
        }
        .onDisappear { Task { await viewModel.stopCamera() } }
        // The gallery covers the camera: stop the feed (and the per-frame detection) meanwhile.
        .onChange(of: isShowingGallery) { _, showing in
            Task { if showing { await viewModel.stopCamera() } else { await viewModel.resumeCamera() } }
        }
        .alert("Something went wrong", isPresented: $viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingAcknowledgements) {
            AcknowledgementsView()
                .followsSystemColorScheme()
                .tint(GoPhotoDesign.primary)
        }
        .fullScreenCover(isPresented: $isShowingGallery) {
            LatestPhotoView()
                .navigationTransition(.zoom(sourceID: "gallery", in: galleryZoom))
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Layout
    //
    // One contained layout for every ratio, top to bottom: top bar · image · shot sizes + shutter.
    // The image is as large as its ratio allows between the top bar and the controls, centred,
    // with rounded corners, so 9:16 is a taller, narrower card (never behind the shutter).
    // The top bar keeps its designed size whatever the Larger Text setting (it is a compact bar, like
    // the Camera app's); the controls follow Larger Text up to the largest standard size so they never
    // crowd the image. Neither moves when the ratio changes; only the image's frame animates (the
    // preview layer and session stay alive).

    private var liveCamera: some View {
        VStack(spacing: 0) {
            topBar
                .frame(height: Self.topBarHeight)

            cameraPreview
                .aspectRatio(CGFloat(viewModel.aspectRatio.ratio), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .reportOnboardingFrame(.preview, into: $onboardingFrames)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            controls
                .padding(.bottom, 12)
                .dynamicTypeSize(...AppFont.overlayMaximumDynamicTypeSize)
        }
        .animation(.smooth(duration: 0.42), value: viewModel.aspectRatio)
        // Motion runs 30×/s and redraws the camera screen each time: stop it while the gallery
        // covers the camera, otherwise the gallery underneath it is rebuilt 30×/s too (lag).
        .task(id: isShowingGallery) {
            guard !isShowingGallery else { return }
            await viewModel.observeTilt()
        }
        .task { await viewModel.observePerson() }
        .task { await viewModel.observeZoom() }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.isLevel) { _, isNowLevel in
            isNowLevel
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isReady) { _, isNowReady in
            isNowReady
        }
        .onChange(of: viewModel.captureCount) {
            Task {
                isFlashing = true
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.2)) { isFlashing = false }
            }
        }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1.0), trigger: viewModel.captureCount)
    }

    /// Shot sizes and shutter, pinned to the bottom (every ratio).
    private var controls: some View {
        VStack(spacing: 12) {
            shotSizePicker
            controlPanel
        }
    }

    /// Dark rounded panel: gallery shortcut (left) · shutter (centre) · photo ratio (right),
    /// like the Camera app's bottom row. Same in 3:4 and 9:16.
    private var controlPanel: some View {
        shutterButton
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .reportOnboardingFrame(.shutter, into: $onboardingFrames)
            .background(Color(hex: 0x1A1A1A), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
            .overlay(alignment: .leading) {
                GalleryShortcutButton { isShowingGallery = true }
                    .matchedTransitionSource(id: "gallery", in: galleryZoom)
                    .padding(.leading, 24)
            }
            .overlay(alignment: .trailing) {
                AspectRatioPicker(selection: viewModel.aspectRatio) { viewModel.selectAspectRatio($0) }
                    .equatable()
                    .sensoryFeedback(.selection, trigger: viewModel.aspectRatio)
                    .padding(.trailing, 24)
            }
            .padding(.horizontal, 20)
    }

    /// The live preview with every guide layer on top. Each layer is its own property so the
    /// compiler can type-check them one by one instead of one huge overlay chain.
    /// The grid, the person dimming / tap and the horizon cover the whole image (the photo).
    private var cameraPreview: some View {
        CameraPreviewView(session: viewModel.session,
                          videoGravity: .resizeAspectFill)   // 3:4 box has the frame's own shape, so fill = exact; one gravity keeps the ratio change continuous
            .overlay { guideVisuals }
            .overlay { CameraGridOverlay(aspect: viewModel.aspectRatio.gridAspect, showsGrid: true) }
            .overlay { HorizonLevelView(state: viewModel.horizon) }
            .overlay {
                GuidanceMotionOverlay(
                    instruction: viewModel.phasedMotion,
                    pitchError: viewModel.phasedPitchError,
                    isEnabled: !isShowingGallery && !showsCameraOnboarding
                )
            }
            .overlay(alignment: .bottom) { bottomStepCard }
            .overlay(alignment: .trailing) { sideBar }
            .overlay(alignment: .top) { instructionPill }
            .overlay { flashOverlay }
            // Guidance drawn over the image grows with Larger Text only up to the largest standard size.
            .dynamicTypeSize(...AppFont.overlayMaximumDynamicTypeSize)
    }

    /// The top bar's height: one row (close · preference · ratio), the same at every text size.
    private static let topBarHeight: CGFloat = 44

    // MARK: Onboarding (first install only)

    @ViewBuilder private var cameraOnboarding: some View {
        if showsCameraOnboarding {
            CameraOnboardingView(frames: onboardingFrames) {
                withAnimation(.easeOut(duration: 0.25)) { cameraOnboardingCompleted = true }
            }
            .transition(.opacity)
        }
    }

    // MARK: Preview layers

    /// Person choice (dim + tap). The Auto crop is not drawn: the green pill says ready.
    private var guideVisuals: some View {
        PhasedPreviewLayer(dimMask: viewModel.selectionDimMask,
                           isChoosing: viewModel.phasedInstruction == .tapPerson,
                           cropWindow: nil,
                           isReady: viewModel.phased.ready,
                           aspectRatio: viewModel.aspectRatio,
                           personBoxes: viewModel.personChoices) { point in
            viewModel.tapPreview(at: point)
        }
    }

    /// The distance bar while the distance phase runs (green zone = enter band).
    @ViewBuilder private var bottomStepCard: some View {
        if viewModel.phased.phase == .distance, let lo = viewModel.phased.sizeEnterLow,
           let hi = viewModel.phased.sizeEnterHigh {
            let centre = (lo + hi) / 2
            DistanceBar(sizeRatio: viewModel.phased.sizeRatio.map { $0 / centre },
                        tolerance: (hi - lo) / 2 / centre,
                        isOK: viewModel.phased.sizeRatio.map { $0 >= lo && $0 <= hi } ?? false)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    /// The tilt bar while the tilt phase runs (green zone = tolerance).
    @ViewBuilder private var sideBar: some View {
        if viewModel.phased.phase == .tilt {
            GuideVerticalBar(value: viewModel.phased.tiltNeed.map { max(-1, min(1, -$0 * Self.phasedTiltZone)) },
                             zone: Self.phasedTiltZone, symbol: "scope", caption: "Tilt",
                             isOK: viewModel.phased.tiltNeed.map { abs($0) <= 1 } ?? false)
                .padding(.trailing, 12)
        }
    }

    private var instructionPill: some View {
        VStack(spacing: 6) {
            PhasedInstructionPill(instruction: viewModel.phasedInstruction, isPlain: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.black.opacity(0.35))
                .animation(.snappy, value: viewModel.phasedInstruction)
            if let flash = viewModel.phasedFlash {
                // A phase just finished.
                Label(flash, systemImage: "checkmark.circle.fill")
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.green.opacity(0.9), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: viewModel.phasedFlash)
        .sensoryFeedback(.success, trigger: viewModel.phasedFlash) { _, new in new != nil }
    }

    private var flashOverlay: some View {
        Color.black
            .opacity(isFlashing ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// Tilt bar: the green zone's half height (the tolerance edge is ±1 in `tiltNeed`).
    private static let phasedTiltZone = 0.25

    // MARK: Top bar, shutter, permission

    /// One row, like a navigation bar: close (left), the preference name as the title (centre),
    /// the photo ratio in use (right). Both sides get the same width so the title stays centred.
    /// Fixed size at every Larger Text setting; a long-press shows the Large Content Viewer instead.
    private var topBar: some View {
        HStack(spacing: 8) {
            closeButton
                .frame(width: Self.topBarSideWidth, alignment: .leading)
            preferenceTitle
                .frame(maxWidth: .infinity)
            aspectRatioLabel
                .frame(width: Self.topBarSideWidth, alignment: .trailing)
        }
        .fixedDynamicTypeSize()
    }

    /// Width of each top bar side: room for the close button and "9:16".
    private static let topBarSideWidth: CGFloat = 64

    /// The preference in use, as the screen title: plain text, a label (not a button).
    @ViewBuilder private var preferenceTitle: some View {
        if let name = viewModel.presetName {
            // Runs as a marquee when the name doesn't fit (long name, Larger Text).
            MarqueeText(text: name, font: AppFont.system(size: 17, weight: .semibold), color: .white)
                .accessibilityLabel("Preference \(name)")
                .accessibilityAddTraits(.isHeader)
                .accessibilityShowsLargeContentViewer { Text(name) }
        }
    }

    /// The photo ratio in use (changed with the ratio button next to the shutter).
    private var aspectRatioLabel: some View {
        Text(viewModel.aspectRatio.title)
            .font(AppFont.system(size: 17, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText())
            .padding(.trailing, 20)
            .accessibilityLabel("Photo ratio \(viewModel.aspectRatio.accessibilityName)")
            .accessibilityShowsLargeContentViewer { Text(viewModel.aspectRatio.title) }
    }

    @ViewBuilder private var closeButton: some View {
        if let onClose {
            Button {
                guard !isClosing else { return }
                isClosing = true
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isClosing)
            .padding(.leading, 8)
            .accessibilityLabel("Close camera")
            .accessibilityInputLabels(["Close camera", "Close"])
            .accessibilityShowsLargeContentViewer { Label("Close", systemImage: "xmark") }
            .accessibilityIdentifier("camera.close")
        }
    }

    /// Shot sizes like TikTok's camera modes: full body only while the person sits, the
    /// preference's shot sizes while they stand. Hidden without a preset.
    @ViewBuilder private var shotSizePicker: some View {
        let options = viewModel.shotOptions
        if let note = viewModel.phasedShotNote {
            Text(note).font(AppFont.caption2).foregroundStyle(.white.opacity(0.7))
        }
        if !options.isEmpty {
            ShotSizePicker(options: options, selection: viewModel.activeShot,
                           posture: viewModel.posture) { viewModel.selectShot($0) }
                .sensoryFeedback(.selection, trigger: viewModel.activeShot)
        }
    }

    private var shutterButton: some View {
        Button {
            Task { await viewModel.takePhoto() }
        } label: {
            ZStack {
                Circle().fill(.white).frame(width: 68, height: 68)
                Circle().stroke(.white, lineWidth: 4).frame(width: 80, height: 80)
            }
        }
        .disabled(viewModel.isCapturing)
        .opacity(viewModel.isCapturing ? 0.5 : 1)
        .accessibilityLabel("Take photo")
        .accessibilityInputLabels(["Take photo", "Shutter", "Capture", "Take picture"])
    }

    private var permissionDenied: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera")
        } description: {
            Text("GoPhoto needs your camera to guide photos. Tap Open Settings, then turn on Camera.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.goPhotoPrimary)
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    CameraView()
}
