//
//  Theme.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import SwiftUI
import UIKit

/// UIKit view of `GoPhotoDesign`: the same tokens as `UIColor`/`UIFont`, so UIKit screens never
/// define their own colors.
///
/// Every color is dynamic (Light / Dark). Views and labels resolve them automatically; a
/// `CGColor` (layer borders, shadows, shape strokes) does not, so resolve it with the view's
/// trait collection — `Theme.stroke.resolvedColor(with: traitCollection).cgColor` — and refresh it
/// from `registerForTraitChanges([UITraitUserInterfaceStyle.self])`.
enum Theme {
    static let background = GoPhotoPalette.background
    static let surface = GoPhotoPalette.surface
    static let stroke = GoPhotoPalette.border
    static let divider = GoPhotoPalette.divider
    static let text = GoPhotoPalette.primaryText
    static let secondaryText = GoPhotoPalette.secondaryText
    static let disabledText = GoPhotoPalette.disabledText
    static let accent = GoPhotoPalette.primary
    static let accentPressed = GoPhotoPalette.primaryPressed
    static let accentSubtle = GoPhotoPalette.primarySubtle
    static let accentBorder = GoPhotoPalette.primaryBorder
    static let tagBackground = GoPhotoPalette.primarySubtle
    static let tagText = GoPhotoPalette.tagText
    static let disabledFill = GoPhotoPalette.secondaryBackground
    static let destructive = GoPhotoPalette.error
    static let onAccent = GoPhotoPalette.onPrimary
    static let cardCornerRadius = GoPhotoDesign.cardCornerRadius
    static let buttonHeight = GoPhotoDesign.buttonHeight
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
