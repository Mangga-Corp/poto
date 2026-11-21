import SwiftUI
import UIKit

extension Color {
    /// `Color(hex: 0x6C30A6)`, sRGB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension UIColor {
    /// `UIColor(hex: 0x6C30A6)`, sRGB.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// A dynamic color that follows the system appearance (Light / Dark, set in iOS Settings).
    /// Resolved by UIKit and SwiftUI at render time, so screens switch instantly when the user
    /// toggles Dark Mode — no view code has to check `colorScheme`.
    static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        let lightColor = UIColor(hex: light)
        let darkColor = UIColor(hex: dark)
        return UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor }
    }
}

/// The raw, appearance-aware palette as `UIColor`. Every token has a light and a dark value.
/// Read it through `PotoDesign` (SwiftUI) or `Theme` (UIKit), never directly from a screen.
///
/// Dark values follow the dark-mode design: true-black canvas, charcoal cards/sheets, deep-purple
/// tinted notes and chips, a slightly lifted brand purple so it keeps its punch on black, and
/// white / light-gray text.
enum PotoPalette {

    // MARK: Brand

    /// Light: brand purple `#6C30A6` (≈8:1 with white). Dark: lifted `#7E4CC2` (≈5.6:1 with white).
    static let primary = UIColor.adaptive(light: 0x6C30A6, dark: 0x7E4CC2)
    static let primaryPressed = UIColor.adaptive(light: 0x55238A, dark: 0x6C30A6)
    static let primarySubtle = UIColor.adaptive(light: 0xEEE5F5, dark: 0x35234F)
    static let primaryBorder = UIColor.adaptive(light: 0xDCC9ED, dark: 0x5B3E86)
    /// Text and icons on a selected `primarySubtle` card. Light: same as `primary`.
    /// Dark: lavender, 8.6:1 on the dark tint (`primary` is only 2.5:1 there).
    static let selectedContent = UIColor.adaptive(light: 0x6C30A6, dark: 0xD7C3F2)
    /// Border of a selected card. Light: same as `primaryBorder`. Dark: 5.6:1 on the dark tint.
    static let selectedBorder = UIColor.adaptive(light: 0xDCC9ED, dark: 0xB794F0)
    /// Fill of a selected choice card and of soft status pills.
    static let selectedSurface = UIColor.adaptive(light: 0xF5EFFA, dark: 0x35234F)
    /// Icon tile or tag sitting on `selectedSurface`, one step stronger so it stays visible.
    static let selectedAccent = UIColor.adaptive(light: 0xEBDFF6, dark: 0x4A3270)
    static let onPrimary = UIColor.white

    // MARK: Neutrals

    static let background = UIColor.adaptive(light: 0xFAF8F5, dark: 0x000000)
    static let secondaryBackground = UIColor.adaptive(light: 0xEFE9F3, dark: 0x2C2C2E)
    static let surface = UIColor.adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let inputBackground = UIColor.adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)

    static let primaryText = UIColor.adaptive(light: 0x29232F, dark: 0xFFFFFF)
    static let secondaryText = UIColor.adaptive(light: 0x6A6173, dark: 0xA9A3B0)
    static let disabledText = UIColor.adaptive(light: 0x9A91A2, dark: 0x6B6572)
    static let placeholderText = UIColor.adaptive(light: 0x8A8092, dark: 0x7C7684)

    static let border = UIColor.adaptive(light: 0xE3DAEA, dark: 0x38343D)
    static let divider = UIColor.adaptive(light: 0xEAE3F0, dark: 0x2A272E)

    /// Text on `primarySubtle` (chips, privacy note). Dark: soft lavender, ≈9:1 on the dark tint.
    static let tagText = UIColor.adaptive(light: 0x55238A, dark: 0xD7C3F2)

    // MARK: Semantic

    static let success = UIColor.adaptive(light: 0x1E7A45, dark: 0x3DBE74)
    static let warning = UIColor.adaptive(light: 0x9A5B00, dark: 0xF0A43A)
    /// Light `#B3261E`; dark `#D23B2F` — still ≥4.5:1 with white for the red "Delete" capsule.
    static let error = UIColor.adaptive(light: 0xB3261E, dark: 0xD23B2F)
    static let info = UIColor.adaptive(light: 0x1F5FA8, dark: 0x5C9CEB)
}

/// The single source of design tokens: color, typography, shape, spacing.
/// UIKit screens read the same values through `Theme` (which wraps these tokens).
/// All colors are dynamic: they follow the device's Light / Dark appearance automatically.
enum PotoDesign {

    // MARK: Brand

    /// Brand purple. White text on it stays above 4.5:1 in both appearances.
    static let primary = Color(uiColor: PotoPalette.primary)
    /// Pressed state of a primary surface.
    static let primaryPressed = Color(uiColor: PotoPalette.primaryPressed)
    /// Selected / tinted background behind primary-colored content.
    static let primarySubtle = Color(uiColor: PotoPalette.primarySubtle)
    /// Border of selected or purple-tinted surfaces.
    static let primaryBorder = Color(uiColor: PotoPalette.primaryBorder)
    /// Text and icons on a selected card.
    static let selectedContent = Color(uiColor: PotoPalette.selectedContent)
    /// Border of a selected card.
    static let selectedBorder = Color(uiColor: PotoPalette.selectedBorder)
    /// Fill of a selected choice card and of soft status pills.
    static let selectedSurface = Color(uiColor: PotoPalette.selectedSurface)
    /// Icon tile or tag sitting on `selectedSurface`.
    static let selectedAccent = Color(uiColor: PotoPalette.selectedAccent)
    static let onPrimary = Color(uiColor: PotoPalette.onPrimary)

    // MARK: Neutrals

    static let background = Color(uiColor: PotoPalette.background)
    static let secondaryBackground = Color(uiColor: PotoPalette.secondaryBackground)
    /// Cards and sheets.
    static let surface = Color(uiColor: PotoPalette.surface)
    static let inputBackground = Color(uiColor: PotoPalette.inputBackground)

    static let primaryText = Color(uiColor: PotoPalette.primaryText)
    /// 5.3:1 on `background`, 4.8:1 on `primarySubtle` (light); ≥7:1 on black (dark).
    static let secondaryText = Color(uiColor: PotoPalette.secondaryText)
    static let disabledText = Color(uiColor: PotoPalette.disabledText)
    static let placeholderText = Color(uiColor: PotoPalette.placeholderText)

    static let border = Color(uiColor: PotoPalette.border)
    static let divider = Color(uiColor: PotoPalette.divider)

    // MARK: Semantic (state only, never decoration)

    static let success = Color(uiColor: PotoPalette.success)
    static let warning = Color(uiColor: PotoPalette.warning)
    static let error = Color(uiColor: PotoPalette.error)
    static let info = Color(uiColor: PotoPalette.info)

    // MARK: Typography
    // App font (see AppFont.swift) on Dynamic Type text styles, so every role scales.

    /// Every screen's title (Large Title), with `body` for the text under it.
    static let largeTitle = AppFont.system(.largeTitle, design: .default, weight: .bold)
    static let sectionTitle = AppFont.system(.title3, design: .default, weight: .semibold)
    static let cardTitle = AppFont.system(.headline, design: .default, weight: .semibold)
    static let body = AppFont.system(.body, design: .default, weight: .regular)
    static let secondaryBody = AppFont.system(.subheadline, design: .default, weight: .regular)
    static let caption = AppFont.system(.caption, design: .default, weight: .regular)
    static let buttonLabel = AppFont.system(.headline, design: .default, weight: .semibold)
    static let smallLabel = AppFont.system(.caption, design: .default, weight: .medium)

    // MARK: Shape & spacing

    static let cardCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 12
    static let sessionMargin: CGFloat = 20
    static let horizontalMargin: CGFloat = 24
    static let buttonHeight: CGFloat = 56
    static let compactButtonHeight: CGFloat = 44
}

/// Chip / tag look, shared by "Last Used", "N saved", privacy note and similar labels.
extension PotoDesign {
    static let tagBackground = primarySubtle
    /// Purple text on `primarySubtle`: dark purple in light mode (8.6:1), lavender in dark mode.
    static let tagText = Color(uiColor: PotoPalette.tagText)
}

// MARK: - Shared surfaces

extension View {
    /// Card surface: white with a neutral border, or `primarySubtle` with a purple border when selected.
    func potoCard(
        isSelected: Bool = false,
        fill: Color? = nil,
        cornerRadius: CGFloat = PotoDesign.cardCornerRadius
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(fill ?? (isSelected ? PotoDesign.primarySubtle : PotoDesign.surface), in: shape)
            .overlay(shape.strokeBorder(isSelected ? PotoDesign.primary : PotoDesign.border,
                                        lineWidth: isSelected ? 1.5 : 1))
            .contentShape(shape)
    }

    /// Tag / chip look ("Last Used", "3 saved").
    func potoTag() -> some View {
        self
            .font(PotoDesign.smallLabel)
            .foregroundStyle(PotoDesign.tagText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(PotoDesign.tagBackground, in: Capsule())
    }
}
