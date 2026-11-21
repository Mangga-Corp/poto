import SwiftUI

// The app's three button styles. Every state (normal, pressed, disabled, loading) is defined here.
//
//     Button("Continue") { … }.buttonStyle(.potoPrimary)
//     Button("Back") { … }.buttonStyle(.potoSecondary)
//     Button("Edit") { … }.buttonStyle(.potoText)
//     Button { … } label: { Label("Add Your Photos", systemImage: "plus.circle") }
//         .buttonStyle(.potoPrimary(isLoading: isSaving))
//
// Primary and secondary are full-width capsules of `PotoDesign.buttonHeight`.

/// Tinted Liquid Glass brand button: the one main action of a screen.
struct PotoPrimaryButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isActive = isEnabled && !isLoading
        let tint: Color = !isEnabled ? PotoDesign.secondaryBackground : PotoDesign.primary
        PotoButtonLabel(configuration: configuration, isLoading: isLoading, spinnerColor: PotoDesign.onPrimary)
            .foregroundStyle(isEnabled ? PotoDesign.onPrimary : PotoDesign.disabledText)
            .frame(maxWidth: .infinity, minHeight: PotoDesign.buttonHeight)
            .glassEffect(.regular.tint(tint).interactive(isActive), in: Capsule())
            .contentShape(Capsule())
            .allowsHitTesting(isActive)
    }
}

/// Lightly tinted Liquid Glass button: a secondary action next to a primary one.
struct PotoSecondaryButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        PotoButtonLabel(configuration: configuration, isLoading: isLoading, spinnerColor: PotoDesign.primary)
            .foregroundStyle(isEnabled ? PotoDesign.primary : PotoDesign.disabledText)
            .frame(maxWidth: .infinity, minHeight: PotoDesign.buttonHeight)
            .glassEffect(.regular.tint(PotoDesign.primary.opacity(isEnabled ? 0.15 : 0)).interactive(isEnabled && !isLoading), in: Capsule())
            .contentShape(Capsule())
            .allowsHitTesting(isEnabled && !isLoading)
    }
}

/// Text-only button (Back, Edit, Add More Photos).
struct PotoTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PotoDesign.buttonLabel)
            .foregroundStyle(isEnabled
                             ? (configuration.isPressed ? PotoDesign.primaryPressed : PotoDesign.primary)
                             : PotoDesign.disabledText)
            .frame(minHeight: PotoDesign.compactButtonHeight)
            .contentShape(Rectangle())
    }
}

/// Label with the shared font, icon spacing and loading spinner (the title stays in layout so the
/// button doesn't change size).
private struct PotoButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let isLoading: Bool
    let spinnerColor: Color

    var body: some View {
        configuration.label
            .font(PotoDesign.buttonLabel)
            .labelStyle(PotoButtonLabelStyle())
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading { ProgressView().tint(spinnerColor) }
            }
            .padding(.horizontal, 20)
    }
}

private struct PotoButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

extension ButtonStyle where Self == PotoPrimaryButtonStyle {
    static var potoPrimary: PotoPrimaryButtonStyle { .init() }
    static func potoPrimary(isLoading: Bool) -> PotoPrimaryButtonStyle { .init(isLoading: isLoading) }
}

extension ButtonStyle where Self == PotoSecondaryButtonStyle {
    static var potoSecondary: PotoSecondaryButtonStyle { .init() }
    static func potoSecondary(isLoading: Bool) -> PotoSecondaryButtonStyle { .init(isLoading: isLoading) }
}

extension ButtonStyle where Self == PotoTextButtonStyle {
    static var potoText: PotoTextButtonStyle { .init() }
}
