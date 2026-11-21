//
//  AppAlert.swift
//  gophoto
//
//  The one popup style of the app, on the system alert: the main action is white text on
//  purple, every other action is red text on the alert's glass. UIKit screens use
//  `addPrimaryAction` / `addSecondaryAction`, SwiftUI screens use `.appAlert`.
//
//  SwiftUI's own `.alert` can't be used for this: without a `.cancel` button it adds a Cancel of
//  its own, so a red Cancel next to a purple Continue is not possible there.
//

import SwiftUI
import UIKit

extension UIAlertController {
    /// Red text on glass. Added before the primary action, so it sits on the left.
    @discardableResult
    func addSecondaryAction(_ title: String, handler: (() -> Void)? = nil) -> UIAlertAction {
        let action = UIAlertAction(title: title, style: .destructive) { _ in handler?() }
        addAction(action)
        return action
    }

    /// White text on purple: the alert's preferred action.
    @discardableResult
    func addPrimaryAction(_ title: String, handler: (() -> Void)? = nil) -> UIAlertAction {
        let action = UIAlertAction(title: title, style: .default) { _ in handler?() }
        addAction(action)
        preferredAction = action
        view.tintColor = PotoPalette.primary
        return action
    }
}

/// One button of an `.appAlert`.
struct AppAlertAction {
    enum Style { case primary, secondary }

    let title: String
    let style: Style
    let handler: () -> Void

    static func primary(_ title: String, handler: @escaping () -> Void = {}) -> AppAlertAction {
        AppAlertAction(title: title, style: .primary, handler: handler)
    }

    static func secondary(_ title: String, handler: @escaping () -> Void = {}) -> AppAlertAction {
        AppAlertAction(title: title, style: .secondary, handler: handler)
    }
}

/// The text field of an `.appAlert`.
struct AppAlertTextField {
    var placeholder = "Name"
    let text: Binding<String>
    var inputLabels: [String] = []
    /// The primary action stays disabled while the text is blank.
    var requiresText = false
}

extension View {
    func appAlert(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String? = nil,
        textField: AppAlertTextField? = nil,
        actions: [AppAlertAction]
    ) -> some View {
        background(
            AppAlertPresenter(title: title, message: message, textField: textField,
                              actions: actions, isPresented: isPresented)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}

private struct AppAlertPresenter: UIViewControllerRepresentable {
    let title: String
    let message: String?
    let textField: AppAlertTextField?
    let actions: [AppAlertAction]
    @Binding var isPresented: Bool

    final class Coordinator {
        var parent: AppAlertPresenter?
        weak var alert: UIAlertController?
        var isWaitingToPresent = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if isPresented {
            guard coordinator.alert == nil, !coordinator.isWaitingToPresent else { return }
            coordinator.isWaitingToPresent = true
            DispatchQueue.main.async { Self.present(from: host, coordinator, attempt: 0) }
        } else if let alert = coordinator.alert {
            coordinator.alert = nil
            alert.dismiss(animated: true)
        }
    }

    static func dismantleUIViewController(_ host: UIViewController, coordinator: Coordinator) {
        coordinator.parent = nil
        coordinator.alert?.dismiss(animated: true)
        coordinator.alert = nil
    }

    /// Waits while the screen is still arriving or another popup is open or closing: UIKit drops
    /// a presentation started at those moments.
    private static func present(from host: UIViewController, _ coordinator: Coordinator, attempt: Int) {
        guard let parent = coordinator.parent, parent.isPresented, coordinator.alert == nil else {
            coordinator.isWaitingToPresent = false
            return
        }
        var top = host
        while let next = top.presentedViewController { top = next }
        let isBusy = host.view.window == nil || host.transitionCoordinator != nil
            || top.isBeingPresented || top.isBeingDismissed || top is UIAlertController
        guard !isBusy else {
            guard attempt < 100 else {
                coordinator.isWaitingToPresent = false
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                present(from: host, coordinator, attempt: attempt + 1)
            }
            return
        }
        coordinator.isWaitingToPresent = false
        let alert = parent.makeAlert(coordinator)
        coordinator.alert = alert
        top.present(alert, animated: true)
    }

    private func makeAlert(_ coordinator: Coordinator) -> UIAlertController {
        let alert = UIAlertController(title: title.isEmpty ? nil : title,
                                      message: message?.isEmpty == false ? message : nil,
                                      preferredStyle: .alert)
        var primaryAction: UIAlertAction?
        for action in actions {
            let run = {
                coordinator.alert = nil
                action.handler()
                coordinator.parent?.isPresented = false
            }
            switch action.style {
            case .primary: primaryAction = alert.addPrimaryAction(action.title, handler: run)
            case .secondary: alert.addSecondaryAction(action.title, handler: run)
            }
        }
        if let textField {
            let isBlank = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if textField.requiresText { primaryAction?.isEnabled = !isBlank(textField.text.wrappedValue) }
            alert.addTextField { [weak primaryAction] field in
                field.placeholder = textField.placeholder
                field.text = textField.text.wrappedValue
                field.autocapitalizationType = .words
                if !textField.inputLabels.isEmpty { field.accessibilityUserInputLabels = textField.inputLabels }
                field.addAction(UIAction { [weak field] _ in
                    let text = field?.text ?? ""
                    textField.text.wrappedValue = text
                    if textField.requiresText { primaryAction?.isEnabled = !isBlank(text) }
                }, for: .editingChanged)
            }
        }
        return alert
    }
}
