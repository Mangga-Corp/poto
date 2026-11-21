import SwiftUI

struct WelcomeOnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let galleryHeight = geometry.size.height * 0.63

            VStack(spacing: 0) {
                WelcomeGalleryView()
                    .frame(height: galleryHeight)

                VStack(spacing: 0) {
                    Spacer(minLength: 18)

                    Text("Start with your favorite photos")
                        .font(PotoDesign.largeTitle)
                        .foregroundStyle(PotoDesign.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Add photos you love. We'll guide you to match them.")
                        .font(PotoDesign.body)
                        .foregroundStyle(PotoDesign.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 16)

                    Spacer(minLength: 28)

                    Button("Choose Photos", action: onContinue)
                        .buttonStyle(.potoPrimary)
                    .accessibilityHint("Continue to choose reference photos")
                    .padding(.bottom, 14)
                }
                .padding(.horizontal, PotoDesign.horizontalMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .appPatternBackground()
        .ignoresSafeArea(edges: .top)
    }
}
