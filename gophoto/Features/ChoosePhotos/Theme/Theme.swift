//
//  Theme.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import SwiftUI
import UIKit

/// UIKit view of `PotoDesign`: the same tokens as `UIColor`/`UIFont`, so UIKit screens never
/// define their own colors.
///
/// Every color is dynamic (Light / Dark). Views and labels resolve them automatically; a
/// `CGColor` (layer borders, shadows, shape strokes) does not, so resolve it with the view's
/// trait collection — `Theme.stroke.resolvedColor(with: traitCollection).cgColor` — and refresh it
/// from `registerForTraitChanges([UITraitUserInterfaceStyle.self])`.
enum Theme {
    static let background = PotoPalette.background
    static let surface = PotoPalette.surface
    static let stroke = PotoPalette.border
    static let divider = PotoPalette.divider
    static let text = PotoPalette.primaryText
    static let secondaryText = PotoPalette.secondaryText
    static let disabledText = PotoPalette.disabledText
    static let accent = PotoPalette.primary
    static let accentPressed = PotoPalette.primaryPressed
    static let accentSubtle = PotoPalette.primarySubtle
    static let accentBorder = PotoPalette.primaryBorder
    static let tagBackground = PotoPalette.primarySubtle
    static let tagText = PotoPalette.tagText
    static let disabledFill = PotoPalette.secondaryBackground
    static let destructive = PotoPalette.error
    static let onAccent = PotoPalette.onPrimary
    static let cardCornerRadius = PotoDesign.cardCornerRadius
    static let buttonHeight = PotoDesign.buttonHeight
}

extension UIView {
    /// Runs `apply` now and again whenever Light / Dark changes. Use it for `CALayer` colors
    /// (borders, shape strokes), which are `CGColor`s and never adapt on their own:
    ///
    ///     card.applyLayerColors { $0.layer.borderColor = Theme.stroke.resolvedColor(with: $0.traitCollection).cgColor }
    func applyLayerColors(_ apply: @escaping (UIView) -> Void) {
        apply(self)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UIView, _) in
            apply(view)
        }
    }
}
