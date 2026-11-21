//
//  CameraAngleSelectionView.swift
//  gophoto
//
//  Custom preference, step 2: the camera angle. Create Preference saves the placement and angle
//  as a new preference under its combination's name.
//

import SwiftUI

struct CameraAngleSelectionView: View {
    @Bindable var model: CustomPreferenceFlowModel

    var body: some View {
        CustomStyleOptionPage(
            step: 2,
            stepCount: CustomPreferenceFlowModel.stepCount,
            title: "Pick Your Camera Angle",
            message: "How high or low should the phone be? We'll guide you there.",
            selection: $model.angle,
            isOptionAvailable: { angle in model.isAngleAvailable(angle) },
            // The last step: the button names what it does (HIG), and the name it saves under is
            // shown at the end of the list instead of over the options.
            primaryTitle: "Create Preference",
            savedName: model.pendingName,
            isLoading: model.isSaving,
            onPrimary: model.create
        ) { angle in
            CameraAngleArtwork(angle: angle)
        }
        .navigationBarBackButtonHidden(model.isSaving)
        .appAlert("Couldn't save your preference", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        ), message: model.errorMessage, actions: [.primary("OK")])
    }
}

#Preview {
    let model = CustomPreferenceFlowModel(onCreated: { _ in })
    model.placement = .ruleOfThirds
    return NavigationStack {
        CameraAngleSelectionView(model: model)
    }
}
