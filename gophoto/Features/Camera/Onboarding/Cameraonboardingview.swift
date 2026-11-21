//
//  Cameraonboardingview.swift
//  gophoto
//
//  Created by Sebastian Darren on 05/11/26.
//

import SwiftUI

struct CameraOnboardingView: View {
    /// Frame elemen kamera yang asli (koordinat global), dilaporkan oleh CameraView.
    let frames: [CameraOnboardingTarget: CGRect]
    let onFinish: () -> Void

    @State private var step: CameraOnboardingStep = .photographerMove
    /// RealityKit (renderer, shader, mesh HP 3D) dibuat sekali di belakang layar selama dua step
    /// pertama, supaya pindah ke step animasi pertama tidak freeze.
    @State private var isPrewarming3D = false
    /// Posisi atas card per step. Per step karena animasi membaca posisi card miliknya sendiri.
    @State private var cardTops: [CameraOnboardingStep: CGFloat] = [:]

    /// Kamera selalu gelap, tetapi card dan HP di tutorial mengikuti setelan Light / Dark iPhone.
    private let appearance = SystemAppearance.shared

    private static let layoutSpace = "cameraOnboardingLayout"
    private static let dimOpacity = GuidanceAnimationStyle.dimOpacity
    private static let cardGapToControls: CGFloat = 16
    private static let cardMargin: CGFloat = 20
    private static let cardCornerRadius: CGFloat = 24
    private static let shotChipCornerRadius: CGFloat = 10
    private static let lastStep = CameraOnboardingStep.allCases.last!
    private var isLastStep: Bool { step == Self.lastStep }

    var body: some View {
        ZStack {
            if isPrewarming3D && step.motion == nil {
                prewarm3D
            }

            dimLayer

            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                ZStack {
                    visual(origin: origin)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        card
                        if let controls = local(.controls, origin) {
                            Color.clear.frame(height: max(0, proxy.size.height - controls.minY + Self.cardGapToControls))
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .coordinateSpace(.named(Self.layoutSpace))
            }
        }
        .environment(\.colorScheme, appearance.colorScheme)
        .sensoryFeedback(.selection, trigger: step)
        .accessibilityAddTraits(.isModal)
        .onAppear { appearance.refresh() }
        .task {
            // Tunggu card pertama tampil dulu, lalu siapkan 3D selagi user membaca.
            try? await Task.sleep(for: .milliseconds(600))
            isPrewarming3D = true
        }
    }

    /// Height & tilt guidance dalam ukuran kecil, hampir transparan, di bawah layer redup.
    /// Tidak terlihat dan tidak bisa disentuh; hanya untuk memanaskan RealityKit.
    private var prewarm3D: some View {
        let skin = PhoneSkin.guide(for: appearance.colorScheme)
        return HStack(spacing: 0) {
            HeightGuidanceView(direction: .up, isActive: false, skin: skin)
            TiltGuidanceView(direction: .down, degrees: GuidanceMotion.tiltFallbackDegrees,
                             tiltView: GuidanceAnimationStyle.tiltView, isActive: false,
                             skin: skin, arrowStyle: .block)
        }
        .frame(width: 16, height: 16)
        .opacity(0.01)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Dim

    /// Layar digelapkan dan menahan semua sentuhan ke kamera. Di step "Pick a shot size", chip
    /// yang aktif dibiarkan terang.
    private var dimLayer: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            Color.black.opacity(Self.dimOpacity)
                .mask {
                    Rectangle()
                        .overlay {
                            if let chip = local(.selectedShot, origin) {
                                RoundedRectangle(cornerRadius: Self.shotChipCornerRadius, style: .continuous)
                                    .frame(width: chip.width, height: chip.height)
                                    .position(x: chip.midX, y: chip.midY)
                                    .opacity(step == .shotSize ? 1 : 0)
                                    .blendMode(.destinationOut)
                            }
                        }
                        .compositingGroup()
                }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private func local(_ target: CameraOnboardingTarget, _ origin: CGPoint) -> CGRect? {
        frames[target]?.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    // MARK: Visual per step

    @ViewBuilder
    private func visual(origin: CGPoint) -> some View {
        if let motion = step.motion, let preview = local(.preview, origin) {
            GuidancePhoneIllustration(motion: motion,
                                      bottomLimit: cardTops[step].map { $0 - preview.minY },
                                      placement: .aboveBottomLimit)
                .id(step)
                .frame(width: preview.width, height: preview.height)
                .position(x: preview.midX, y: preview.midY)
                .transition(.opacity)
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Semua teks diukur sekaligus, supaya tinggi card sama di setiap step (tidak melompat).
            ZStack(alignment: .topLeading) {
                ForEach(CameraOnboardingStep.allCases, id: \.self) { item in
                    stepText(item).hidden()
                }
                stepText(step)
                    .id(step)
                    .transition(.opacity)
            }
            .overlay(alignment: .topTrailing) { closeButton }

            HStack(alignment: .center) {
                stepCounter
                Spacer(minLength: 12)
                nextButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PotoDesign.surface, in: RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(Self.layoutSpace)).minY
        } action: { top in
            // Tinggi card sama di setiap step, jadi satu ukuran berlaku untuk semuanya.
            for item in CameraOnboardingStep.allCases { cardTops[item] = top }
        }
        .padding(.horizontal, Self.cardMargin)
    }

    private func stepText(_ item: CameraOnboardingStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(AppFont.title2.weight(.bold))
                .foregroundStyle(PotoDesign.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 40)   // ruang untuk tombol tutup
                .accessibilityAddTraits(.isHeader)

            Text(item.message)
                .font(PotoDesign.body)
                .foregroundStyle(PotoDesign.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ikon di garis tepi konten, area sentuhnya tetap 44 pt (HIG).
    private var closeButton: some View {
        Button(action: onFinish) {
            Image(systemName: "xmark")
                .font(AppFont.title3.weight(.regular))
                .foregroundStyle(PotoDesign.secondaryText)
                .frame(width: PotoDesign.compactButtonHeight, height: PotoDesign.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 12, y: -8)
        .accessibilityLabel(CameraOnboardingCopy.closeLabel)
    }

    private var stepCounter: some View {
        HStack(spacing: 0) {
            Text("\(step.rawValue + 1)")
                .foregroundStyle(PotoDesign.primaryText)
                .contentTransition(.numericText())
            Text("/\(CameraOnboardingStep.allCases.count)")
                .foregroundStyle(PotoDesign.secondaryText)
        }
        .font(AppFont.title3.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(CameraOnboardingStep.allCases.count)")
    }

    private var nextButton: some View {
        Button(CameraOnboardingCopy.nextButton, action: advance)
            .buttonStyle(OnboardingNextButtonStyle())
            .accessibilityHint(isLastStep ? CameraOnboardingCopy.lastStepHint : "")
    }

    private func advance() {
        if let next = CameraOnboardingStep(rawValue: step.rawValue + 1) {
            withAnimation(.smooth(duration: 0.35)) { step = next }
        } else {
            onFinish()
        }
    }
}

/// Tombol ungu kecil di pojok card.
private struct OnboardingNextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.subheadline.weight(.semibold))
            .foregroundStyle(PotoDesign.onPrimary)
            .padding(.horizontal, 24)
            .frame(minWidth: 84, minHeight: PotoDesign.compactButtonHeight)
            .background(configuration.isPressed ? PotoDesign.primaryPressed : PotoDesign.primary,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Animasi per step

extension CameraOnboardingStep {
    /// Gerakan HP yang dicontohkan. Nil = step tanpa animasi.
    var motion: GuidanceMotion? {
        switch self {
        case .photographerMove, .shotSize: nil
        case .heightUp:   .height(.up)
        case .heightDown: .height(.down)
        case .tiltUp:     .tilt(.up, degrees: GuidanceMotion.tiltFallbackDegrees, view: GuidanceAnimationStyle.tiltView)
        case .tiltDown:   .tilt(.down, degrees: GuidanceMotion.tiltFallbackDegrees, view: GuidanceAnimationStyle.tiltView)
        }
    }
}
