//
//  SystemAppearance.swift
//  gophoto
//
//  The app follows the iPhone's Light / Dark setting everywhere except the camera, which is
//  always dark. Because `.preferredColorScheme(.dark)` on the camera also darkens anything it
//  presents (sheets, full-screen covers), those presentations call `.followsSystemColorScheme()`
//  to get the device's real appearance back.
//

import SwiftUI
import UIKit

/// The device's Light / Dark setting, read from the window scene so it is never affected by a
/// screen that forces its own look. Updates live when the user (or the sunset schedule) switches.
@MainActor
@Observable
final class SystemAppearance {
    static let shared = SystemAppearance()

    private(set) var colorScheme: ColorScheme = .light
    @ObservationIgnored private var observedScene: UIWindowScene?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    private init() {
        refresh()
        // While the camera forces dark, the scene reports no style change. Control Center and
        // Settings both deactivate the app, so the real setting is read again on the way back.
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Reads the current scene's appearance and starts observing it (once per scene).
    func refresh() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        // The screen's traits, not the scene's: `.preferredColorScheme(.dark)` on the camera can
        // reach the scene, while the screen always reports the device's real setting.
        update(from: scene.screen.traitCollection)

        guard observedScene !== scene else { return }
        observedScene = scene
        scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (scene: UIWindowScene, _) in
            self?.update(from: scene.screen.traitCollection)
        }
    }

    private func update(from traits: UITraitCollection) {
        let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
        if scheme != colorScheme { colorScheme = scheme }
    }
}

private struct FollowsSystemColorScheme: ViewModifier {
    private let appearance = SystemAppearance.shared

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance.colorScheme)
            .onAppear { appearance.refresh() }
    }
}

extension View {
    /// Uses the device's Light / Dark setting for this presentation, even when it is presented
    /// from a screen that forces its own color scheme (the camera).
    func followsSystemColorScheme() -> some View {
        modifier(FollowsSystemColorScheme())
    }
}
