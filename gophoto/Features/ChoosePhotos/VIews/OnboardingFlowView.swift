//
//  OnboardingFlowView.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import SwiftUI
import os

/// Runs the analysis of a newly created preference and shows its "Your style" card (first launch,
/// and Add New Preference). The card appears only when the analysis is usable: a run whose
/// required Vision requests failed, or that found no readable framing, shows the retry screen.
struct OnboardingFlowView: View {
    /// The style card's primary action. Returns an error message if the destination cannot be opened.
    var onFinish: () -> String?
    let preferenceID: UUID
    let onAnalysisCompleted: () -> Void
    let styleButtonTitle: String
    /// "Choose Other Photos" on the no-person screen; nil hides the button.
    let onChooseOtherPhotos: (() -> Void)?
    /// Fewer than `HumanSubjectValidator.minimumValidPhotos` photos show a person, so nothing
    /// was analysed: the opener returns to Photo Session Setup with this same preference, which
    /// shows the warning (`PhotoSessionSetupView`). Nil: the no-person retry screen instead.
    let onNeedsMorePhotos: (() -> Void)?
    @State private var style: StyleSummary?
    @State private var failure: AnalysisFailure?
    @State private var analysisRetry = 0
    @State private var finishError: String?
    /// "Some Photos Were Excluded": enough valid photos, some invalid; analysis waits for Continue.
    @State private var exclusionNotice: HumanSubjectValidationResult?
    @State private var isConfirmingExclusions = false
    /// Style question (taste rules): shown over the flow until every unclear shot size is answered.
    @State private var styleQuestion: PreferencesViewModel.StyleQuestion?
    @State private var isSavingStyle = false

    private static let log = Logger(subsystem: "co.mango.gophoto", category: "analysis")

    enum AnalysisFailure: Equatable {
        /// Cancelled, or a required request failed: running it again can help.
        case analysisFailed
        /// It ran, but no photo showed a readable person: other photos are needed.
        case noUsableFraming
    }

    init(
        preferenceID: UUID,
        startsAtStyleCard: Bool,
        styleButtonTitle: String = "Open Camera",
        onAnalysisCompleted: @escaping () -> Void,
        onChooseOtherPhotos: (() -> Void)? = nil,
        onNeedsMorePhotos: (() -> Void)? = nil,
        onFinish: @escaping () -> String?
    ) {
        self.preferenceID = preferenceID
        self.onAnalysisCompleted = onAnalysisCompleted
        self.styleButtonTitle = styleButtonTitle
        self.onChooseOtherPhotos = onChooseOtherPhotos
        self.onNeedsMorePhotos = onNeedsMorePhotos
        self.onFinish = onFinish
        let preference = PreferencesViewModel.shared.preference(id: preferenceID)
        let usable = preference?.analysis.map { $0.isCurrent && $0.usability == .usable } ?? false
        let summary = usable ? StyleSummary(analysis: preference?.analysis, photos: preference?.analyzedPhotos ?? []) : nil
        _style = State(initialValue: (startsAtStyleCard || usable) ? summary : nil)
        let currentAnalysis = preference?.analysis.flatMap { $0.isCurrent ? $0 : nil }
        let recoveredFailure: AnalysisFailure?
        if !startsAtStyleCard, let analysis = currentAnalysis, !usable {
            switch analysis.usability {
            case .usable: recoveredFailure = nil
            case .requiredAnalysisFailed: recoveredFailure = .analysisFailed
            case .noUsableFraming: recoveredFailure = .noUsableFraming
            }
        } else {
            recoveredFailure = nil
        }
        _failure = State(initialValue: recoveredFailure)
        _styleQuestion = State(initialValue: usable ? PreferencesViewModel.shared.pendingStyleQuestion(for: preferenceID) : nil)
    }

    var body: some View {
        ZStack {
            screens
                // Full-screen screens (the analysing animation, the style card) draw edge to edge.
                .ignoresSafeArea()
            // The style question respects the safe area (status bar, navigation bar's Back
            // button); only its background fills the screen.
            if let styleQuestion {
                StyleChoiceView(question: styleQuestion, isSaving: isSavingStyle, onChoose: chooseStyle)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            if style != nil { onAnalysisCompleted() }
        }
        .alert(
            HumanSubjectValidationResult.exclusionTitle,
            isPresented: Binding(get: { exclusionNotice != nil },
                                 set: { if !$0 { exclusionNotice = nil } }),
            presenting: exclusionNotice
        ) { _ in
            Button("Continue", action: confirmExclusions)
        } message: { notice in
            Text(notice.exclusionMessage)
        }
        .alert("Couldn't open the camera", isPresented: Binding(get: { finishError != nil },
                                                              set: { if !$0 { finishError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(finishError ?? "")
        }
    }

    /// The analysis flow's full-screen steps (one at a time).
    private var screens: some View {
        ZStack {
            if let style {
                StyleScreen(summary: style, buttonTitle: styleButtonTitle, onDone: finish)
                    .transition(.opacity)
            } else if let failure {
                AnalysisRetryScreen(failure: failure,
                                    onChooseOtherPhotos: failure == .noUsableFraming ? onChooseOtherPhotos : nil) {
                    // Same photos, analysed again (a new run; the photos stay saved).
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.failure = nil
                        analysisRetry += 1
                    }
                }
                .transition(.opacity)
            } else if let preference = PreferencesViewModel.shared.preference(id: preferenceID) {
                AnalyzingScreen(preferenceID: preferenceID, photos: preference.photos, onCancel: cancelAnalysis) {
                    analysisFinished()
                }
                .transition(.opacity)
                .id(analysisRetry)
            } else {
                AnalysisRetryScreen(failure: .analysisFailed, onChooseOtherPhotos: onChooseOtherPhotos) {
                    withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
                }
                .transition(.opacity)
            }
        }
    }

    private func analysisFinished() {
        // Enough valid photos, some invalid: the user is told before they are removed and the
        // analysis runs (the analysing screen stays underneath).
        if let notice = PreferencesViewModel.shared.exclusionNotice(for: preferenceID) {
            exclusionNotice = notice
            return
        }
        // Stopped before the analysis: too few photos show a person.
        if PreferencesViewModel.shared.validationFailure(for: preferenceID) != nil {
            Self.log.notice("Analysis of \(preferenceID) needs more photos of exactly one person")
            if let onNeedsMorePhotos {
                onNeedsMorePhotos()
            } else {
                withAnimation(.easeInOut(duration: 0.4)) { failure = .noUsableFraming }
            }
            return
        }
        let preference = PreferencesViewModel.shared.preference(id: preferenceID)
        guard let analysis = preference?.analysis, analysis.isCurrent else {
            Self.log.error("Analysis of \(preferenceID) produced no current result")
            withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
            return
        }
        switch analysis.usability {
        case .usable:
            // A shot size whose styles were not clear: ask before the style card.
            if let question = PreferencesViewModel.shared.pendingStyleQuestion(for: preferenceID) {
                withAnimation(.easeInOut(duration: 0.3)) { styleQuestion = question }
                return
            }
            guard let preference, let summary = StyleSummary(analysis: analysis, photos: preference.analyzedPhotos) else {
                withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
                return
            }
            onAnalysisCompleted()
            withAnimation(.easeInOut(duration: 0.4)) { style = summary }
        case .requiredAnalysisFailed:
            Self.log.error("Required analysis failed for \(preferenceID): \(analysis.evidence?.diagnosticDescription ?? "")")
            withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
        case .noUsableFraming:
            Self.log.notice("Analysis of \(preferenceID) found no readable framing")
            withAnimation(.easeInOut(duration: 0.4)) { failure = .noUsableFraming }
        }
    }

    /// Cancel on the analysing screen (18 Nov): the run is already stopped; back to the photos
    /// (the preference stays saved), or the retry screen when there is no way back.
    private func cancelAnalysis() {
        Self.log.notice("Analysis of \(preferenceID) cancelled")
        if let onNeedsMorePhotos {
            onNeedsMorePhotos()
        } else {
            withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
        }
    }

    /// Continue on "Some Photos Were Excluded": the invalid photos are already removed (saved);
    /// the view model starts the analysis on the rest and a new analysing screen joins that run.
    private func confirmExclusions() {
        exclusionNotice = nil
        guard !isConfirmingExclusions else { return }
        isConfirmingExclusions = true
        PreferencesViewModel.shared.confirmExclusions(for: preferenceID) { result in
            isConfirmingExclusions = false
            switch result {
            case .success:
                withAnimation(.easeInOut(duration: 0.4)) {
                    failure = nil
                    analysisRetry += 1
                }
            case .failure(let error):
                Self.log.error("Could not remove excluded photos of \(preferenceID): \(error.message, privacy: .public)")
                withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
            }
        }
    }

    /// Saves the answer, then shows the next question or the style card.
    private func chooseStyle(_ index: Int) {
        guard let question = styleQuestion, !isSavingStyle else { return }
        isSavingStyle = true
        Task {
            let saved = await PreferencesViewModel.shared.chooseStyle(index, forKey: question.id, of: preferenceID,
                                                                    shown: question.options.map(\.id))
            isSavingStyle = false
            guard saved else { return }
            withAnimation(.easeInOut(duration: 0.3)) { styleQuestion = nil }
            analysisFinished()
        }
    }

    private func finish() {
        finishError = onFinish()
    }
}

private struct AnalysisRetryScreen: View {
    let failure: OnboardingFlowView.AnalysisFailure
    let onChooseOtherPhotos: (() -> Void)?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: failure == .noUsableFraming ? "person.fill.questionmark"
                                                          : "exclamationmark.triangle")
                .font(AppFont.scaled(size: 36, relativeTo: .largeTitle))
                .foregroundStyle(failure == .noUsableFraming ? GoPhotoDesign.secondaryText : GoPhotoDesign.warning)
            Text(failure == .noUsableFraming ? "We couldn't find a person in these photos."
                                             : "We couldn't read your photos.")
                .font(GoPhotoDesign.sectionTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .multilineTextAlignment(.center)
            Text(failure == .noUsableFraming ? "Choose photos that clearly show one person."
                                             : "Your photos are safe. Please try again.")
                .font(GoPhotoDesign.secondaryBody)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(.goPhotoPrimary)
                .accessibilityIdentifier("analysis.retry")
            if let onChooseOtherPhotos {
                Button("Choose Other Photos", action: onChooseOtherPhotos)
                    .buttonStyle(.goPhotoSecondary)
                    .accessibilityIdentifier("analysis.chooseOtherPhotos")
            }
            #if DEBUG
            if DebugFixtures.storeName != nil {
                Text("analysisRuns=\(PreferencesViewModel.shared.analysisRunCount)")
                    .font(AppFont.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("debug.analysisRuns")
            }
            #endif
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoPhotoDesign.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis.failure")
    }
}

private struct StyleScreen: UIViewControllerRepresentable {
    let summary: StyleSummary
    let buttonTitle: String
    var onDone: () -> Void

    func makeUIViewController(context: Context) -> StyleCardViewController {
        let vc = StyleCardViewController(summary: summary, buttonTitle: buttonTitle)
        vc.onDone = onDone
        return vc
    }
    func updateUIViewController(_ vc: StyleCardViewController, context: Context) {
        vc.onDone = onDone
    }
}

private struct AnalyzingScreen: UIViewControllerRepresentable {
    let preferenceID: UUID
    let photos: [PhotoItem]
    var onCancel: () -> Void
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> AnalyzingViewController {
        let vc = AnalyzingViewController(viewModel: AnalyzingViewModel(preferenceID: preferenceID),
                                         photos: photos)
        vc.onFinish = onFinish
        vc.onCancel = onCancel
        return vc
    }
    func updateUIViewController(_ vc: AnalyzingViewController, context: Context) {}
}
