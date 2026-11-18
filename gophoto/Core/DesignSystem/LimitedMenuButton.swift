//
//  LimitedMenuButton.swift
//  gophoto
//
//  A UIButton whose native menu stops growing at a chosen Larger Text size.
//
//  UIKit draws a button's menu at its WINDOW's text size: trait overrides on the button or its view
//  controller, and `maximumContentSizeCategory`, are ignored by the menu. So while the menu is open
//  the window's text size is held at the limit, and every view controller on screen is pinned at
//  the size it already has, so the screen behind the menu doesn't change. Both are given back as
//  the menu closes. (The space around a menu's title still follows the system setting; UIKit has
//  no API for it.)
//

import UIKit

class LimitedMenuButton: UIButton {
    /// The largest text size of this button's `menu`; nil leaves the menu at the app's limit.
    var menuMaximumContentSizeCategory: UIContentSizeCategory?

    private var hold: MenuTextSizeHold?

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        if hold == nil, let limit = menuMaximumContentSizeCategory, let window {
            hold = MenuTextSizeHold(window: window, limit: limit)
        }
        let configuration = super.contextMenuInteraction(interaction, configurationForMenuAtLocation: location)
        // No menu after all: nothing will close, so give the size back now.
        if configuration == nil { releaseHold() }
        return configuration
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willEndFor configuration: UIContextMenuConfiguration,
                                         animator: (any UIContextMenuInteractionAnimating)?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        // Given back right away, before the chosen action runs, so anything the action presents
        // (an alert) opens at the app's own size. The closing menu keeps its size (see `release()`).
        releaseHold()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // Leaving the window with the menu still open (screen dismissed): never leave the hold behind.
        if newWindow == nil { releaseHold() }
    }

    private func releaseHold() {
        hold?.release()
        hold = nil
    }
}

/// Holds a window's text size at a limit, with the view controllers on screen pinned at their own
/// size, and gives the previous overrides back on `release()`.
private final class MenuTextSizeHold {
    private let window: UIWindow
    private let windowOverride: UIContentSizeCategory?
    private var pinned: [(controller: UIViewController, override: UIContentSizeCategory?)] = []

    /// nil when the window's text size is already within the limit (nothing to hold).
    init?(window: UIWindow, limit: UIContentSizeCategory) {
        guard window.traitCollection.preferredContentSizeCategory > limit else { return nil }
        self.window = window
        windowOverride = Self.override(in: window.traitOverrides)

        // The root and each screen presented on top of it keep the size they have now.
        var controller = window.rootViewController
        while let current = controller {
            pinned.append((current, Self.override(in: current.traitOverrides)))
            current.traitOverrides.preferredContentSizeCategory = current.traitCollection.preferredContentSizeCategory
            controller = current.presentedViewController
        }
        window.traitOverrides.preferredContentSizeCategory = limit
    }

    func release() {
        // The menu itself is a screen presented on top while it's open: it keeps the size it has
        // while it fades out (it goes away with its override).
        var closing = pinned.last?.controller.presentedViewController
        while let current = closing {
            current.traitOverrides.preferredContentSizeCategory = current.traitCollection.preferredContentSizeCategory
            closing = current.presentedViewController
        }
        Self.restore(windowOverride, on: window, \.traitOverrides)
        // Pass the window's size down now, so the screens unpinned below inherit the new size,
        // not the window's old one (which would briefly resize them).
        window.updateTraitsIfNeeded()
        for (controller, override) in pinned {
            Self.restore(override, on: controller, \.traitOverrides)
            controller.updateTraitsIfNeeded()
        }
        pinned.removeAll()
    }

    /// The override that is set, if any. (Reading one that isn't set throws, so `contains` comes first.)
    private static func override(in overrides: UITraitOverrides) -> UIContentSizeCategory? {
        overrides.contains(UITraitPreferredContentSizeCategory.self) ? overrides.preferredContentSizeCategory : nil
    }

    /// Puts back the override that was there before (or none), on the object itself.
    private static func restore<Owner: AnyObject>(_ value: UIContentSizeCategory?, on owner: Owner,
                                                  _ traitOverrides: ReferenceWritableKeyPath<Owner, UITraitOverrides>) {
        if let value {
            owner[keyPath: traitOverrides].preferredContentSizeCategory = value
        } else if owner[keyPath: traitOverrides].contains(UITraitPreferredContentSizeCategory.self) {
            owner[keyPath: traitOverrides].remove(UITraitPreferredContentSizeCategory.self)
        }
    }
}
