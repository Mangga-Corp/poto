//
//  Cameraonboardingcopy.swift
//  gophoto
//
//  Created by Sebastian Darren on 05/11/26.
//

import Foundation

enum CameraOnboardingStep: Int, CaseIterable {
    case photographerMove
    case shotSize
    case heightUp
    case heightDown
    case tiltUp
    case tiltDown

    var title: String {
        switch self {
        case .photographerMove: "Photographer move"
        case .shotSize:         "Pick a shot size"
        case .heightUp:         "Raise your phone"
        case .heightDown:       "Lower your phone"
        case .tiltUp:           "Tilt up"
        case .tiltDown:         "Tilt down"
        }
    }

    var message: String {
        switch self {
        case .photographerMove:
            "Let the person being photographed stay in place."
        case .shotSize:
            "Full body, 3/4 or Half body. Swipe left or right to switch."
        case .heightUp:
            "Lift the phone higher until it’s green"
        case .heightDown:
            "Lower the phone until it’s green"
        case .tiltUp:
            "Tilt the phone up until it’s green"
        case .tiltDown:
            "Tilt the phone down until it’s green"
        }
    }
}

enum CameraOnboardingCopy {
    static let nextButton = "Next"
    static let closeLabel = "Close camera tips"
    static let lastStepHint = "Closes the camera tips"
}
