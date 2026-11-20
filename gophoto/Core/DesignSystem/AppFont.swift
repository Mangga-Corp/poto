//
//  AppFont.swift
//  gophoto
//
//  THE place to change the app's font. Every screen asks for its font through `AppFont`
//  (SwiftUI) or `UIFont.app(...)` (UIKit), so changing `AppFont.family` below swaps the font
//  everywhere.
//
//  To use another font:
//  1. Put its .ttf / .otf files in `gophoto/Resource/Fonts/` (Xcode picks them up automatically).
//  2. Set `AppFont.family` to the family name as Font Book shows it (e.g. "Alegreya Sans").
//  3. Optionally tune `AppFont.sizeBoost` (this font runs a little small next to San Francisco).
//
//  Bundled: Alegreya Sans (Light, Regular, Italic, Medium, Bold, ExtraBold), SIL Open Font License
//  (Resource/Fonts/OFL.txt).
//

import SwiftUI
import UIKit
import CoreText

enum AppFont {
    /// ⬇️ CHANGE THE FONT HERE ⬇️
    static let family = "Alegreya Sans"

    /// Added to every size: Alegreya Sans has a small x-height, so it is nudged up a little.
    /// Set to 0 for the same sizes as the system font.
    static let sizeBoost: CGFloat = 1.5

    // MARK: Larger Text limit
    //
    // Text, icons and `@ScaledMetric` sizes follow the user's Larger Text setting up to ONE limit,
    // the same for every screen, sheet, menu and alert: at a given setting a text style has the same
    // size everywhere in the app. Applied once for the whole app (`View.appDynamicTypeLimit()` on
    // the root: SwiftUI, the window and its scene) and for UIKit text (`UIFont.app`). Never cap a
    // single screen or menu lower; that is what made screens differ at the same setting.
    //
    // The only text that does not scale is in compact bars (`fixedDynamicTypeSize()`), as in
    // Apple's own bars (HIG): it shows enlarged in the Large Content Viewer instead.

    /// The largest text size anywhere in the app: the largest standard size (xxxLarge, the end of
    /// the slider without Larger Accessibility Sizes). Settings above it show at this size.
    static let maximumDynamicTypeSize: DynamicTypeSize = .xxxLarge
    /// `maximumDynamicTypeSize` for UIKit (xxxLarge).
    static let maximumContentSizeCategory: UIContentSizeCategory = .extraExtraExtraLarge

    /// Registers the bundled font files. Called once at launch (`MyApp.init`); no Info.plist entry needed.
    static func register() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: SwiftUI text styles (same names as the system ones; they still scale with Dynamic Type)

    static let largeTitle = style(34, .largeTitle)
    static let title = style(28, .title)
    static let title2 = style(22, .title2)
    static let title3 = style(20, .title3)
    static let headline = style(17, .headline).weight(.semibold)
    static let body = style(17, .body)
    static let callout = style(16, .callout)
    static let subheadline = style(15, .subheadline)
    static let footnote = style(13, .footnote)
    static let caption = style(12, .caption)
    static let caption2 = style(11, .caption2)

    private static func style(_ size: CGFloat, _ textStyle: Font.TextStyle) -> Font {
        .custom(family, size: size + sizeBoost, relativeTo: textStyle)
    }

    /// The design size at the default text size, scaled with Dynamic Type (Larger Text) like `textStyle`.
    /// Use this instead of `system(size:)` for any text a user reads.
    static func scaled(size: CGFloat, weight: Font.Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom(family, size: size + sizeBoost, relativeTo: textStyle).weight(weight)
    }

    /// Fixed size (does not scale), like `Font.system(size:weight:)`.
    static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .custom(family, fixedSize: size + sizeBoost).weight(weight)
    }

    /// Text style with a weight, like `Font.system(_:design:weight:)`.
    static func system(_ textStyle: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight = .regular) -> Font {
        let base: CGFloat
        switch textStyle {
        case .largeTitle: base = 34
        case .title: base = 28
        case .title2: base = 22
        case .title3: base = 20
        case .headline: base = 17
        case .body: base = 17
        case .callout: base = 16
        case .subheadline: base = 15
        case .footnote: base = 13
        case .caption: base = 12
        case .caption2: base = 11
        @unknown default: base = 17
        }
        return .custom(family, size: base + sizeBoost, relativeTo: textStyle).weight(weight)
    }
}

extension UIFont {
    /// UIKit text style in the app font (scales with Dynamic Type, up to `AppFont.maximumContentSizeCategory`).
    static func app(style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        // The style's size at the default text size; `UIFontMetrics` then scales it once. (The user's
        // current size here would be scaled twice: far too big with Larger Text.)
        let base = UITraitCollection(preferredContentSizeCategory: .large)
        let size = UIFont.preferredFont(forTextStyle: style, compatibleWith: base).pointSize
        return scaled(make(size: size + AppFont.sizeBoost, weight: weight), relativeTo: style)
    }

    /// The design size at the default text size, scaled with Dynamic Type (Larger Text) like `style`,
    /// up to `AppFont.maximumContentSizeCategory`.
    /// Pair it with `adjustsFontForContentSizeCategory = true` so the label follows a change live.
    static func app(size: CGFloat, weight: UIFont.Weight = .regular, relativeTo style: UIFont.TextStyle) -> UIFont {
        scaled(make(size: size + AppFont.sizeBoost, weight: weight), relativeTo: style)
    }

    /// Scales for the user's text size, capped at the app's largest size. (The window caps it too,
    /// see `appDynamicTypeLimit()`; this keeps the first layout right before a view is in a window.)
    private static func scaled(_ font: UIFont, relativeTo style: UIFont.TextStyle) -> UIFont {
        let category = min(UIApplication.shared.preferredContentSizeCategory, AppFont.maximumContentSizeCategory)
        return UIFontMetrics(forTextStyle: style)
            .scaledFont(for: font, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }

    /// UIKit fixed size in the app font.
    static func app(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        make(size: size + AppFont.sizeBoost, weight: weight)
    }

    private static func make(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: AppFont.family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - Larger Text limit for the whole app

extension View {
    /// Caps Larger Text at `AppFont.maximumDynamicTypeSize` for this view and everything it shows,
    /// including UIKit screens presented from it (the style card, the photo editor) and the system's
    /// menus and alerts: the window and its scene get the same cap. Apply once, on the app's root view.
    func appDynamicTypeLimit() -> some View {
        dynamicTypeSize(...AppFont.maximumDynamicTypeSize)
            .background { WindowContentSizeLimit().allowsHitTesting(false).accessibilityHidden(true) }
    }

    /// Text and icons that stay at their designed size whatever the Larger Text setting (a compact
    /// bar over the camera image). Give each item `accessibilityShowsLargeContentViewer` so a
    /// long-press still shows it enlarged, as Apple's own bars do.
    func fixedDynamicTypeSize() -> some View {
        dynamicTypeSize(.large)
    }
}

/// Caps the text size of everything UIKit shows for this app at `AppFont.maximumContentSizeCategory`:
/// the window it lands in (UIKit view controllers presented outside SwiftUI's environment) and the
/// whole window scene, so the system's own menus (the card's "…" menu, context menus) and alerts
/// (Rename Preference), which are drawn in separate windows of the scene, stop at the same size too.
private struct WindowContentSizeLimit: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { WindowLimitView() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class WindowLimitView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            window?.maximumContentSizeCategory = AppFont.maximumContentSizeCategory
            applySceneLimit()
            NotificationCenter.default.removeObserver(self, name: UIContentSizeCategory.didChangeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange),
                                                   name: UIContentSizeCategory.didChangeNotification, object: nil)
        }

        @objc private func contentSizeCategoryDidChange() {
            applySceneLimit()
        }

        /// Overrides the scene's text size only while the user's setting (the Larger Text slider) is
        /// above the app's largest size; below it the scene follows the setting untouched.
        private func applySceneLimit() {
            guard let scene = window?.windowScene else { return }
            let limit = AppFont.maximumContentSizeCategory
            // Reading an override that isn't set throws (NSInternalInconsistencyException), so
            // `contains` is checked before reading it.
            let hasOverride = scene.traitOverrides.contains(UITraitPreferredContentSizeCategory.self)
            if UIApplication.shared.preferredContentSizeCategory > limit {
                if !hasOverride || scene.traitOverrides.preferredContentSizeCategory != limit {
                    scene.traitOverrides.preferredContentSizeCategory = limit
                }
            } else if hasOverride {
                scene.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
            }
        }
    }
}
