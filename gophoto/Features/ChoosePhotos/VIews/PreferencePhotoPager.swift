//
//  PreferencePhotoPager.swift
//  gophoto
//
//  Full-screen viewer for a preference's photos, like the app's gallery: swipe between photos,
//  pinch / double-tap to zoom (same ZoomableImageView), swipe down or ✕ to close.
//  Plain values in, no ViewModel.
//

import SwiftUI

struct PreferencePhotoPager: View {
    let images: [UIImage]
    /// Per photo, e.g. "Full body"; nil when not analysed.
    let labels: [String?]
    let onPageChange: (Int) -> Void
    let onClose: () -> Void

    @State private var current: Int

    init(images: [UIImage], labels: [String?], startIndex: Int,
         onPageChange: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        self.images = images
        self.labels = labels
        self.onPageChange = onPageChange
        self.onClose = onClose
        _current = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            PotoDesign.background.ignoresSafeArea()

            TabView(selection: $current) {
                ForEach(images.indices, id: \.self) { index in
                    ZoomableImageView(image: images[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))   // swipe pages, like Photos
            .ignoresSafeArea()

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(AppFont.body.weight(.semibold))
                        .foregroundStyle(PotoDesign.primaryText)
                        .frame(width: 44, height: 44)
                        .background(PotoDesign.primarySubtle, in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
                // Wraps onto more lines if it ever doesn't fit (a capsule would cut into a second line).
                Text(title)
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(PotoDesign.primaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(PotoDesign.primarySubtle,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)
        }
        // Shown in its own UIHostingController, outside the app's root SwiftUI view, so it gets the
        // app's Larger Text limit here too.
        .dynamicTypeSize(...AppFont.maximumDynamicTypeSize)
        .statusBarHidden(true)
        .onChange(of: current) { _, page in onPageChange(page) }
    }

    private var title: String {
        let position = "\(current + 1) of \(images.count)"
        guard labels.indices.contains(current), let label = labels[current] else { return position }
        return "\(position) · \(label)"
    }
}
