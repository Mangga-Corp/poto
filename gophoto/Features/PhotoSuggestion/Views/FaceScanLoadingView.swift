//
//  FaceScanLoadingView.swift
//  gophoto
//
//  "Find my photos for me" while the library is being scanned.
//

import SwiftUI

struct FaceScanLoadingView: View {
    let progress: FaceGroupingProgress
    let onCancel: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 16)
                    FaceScanIllustration()
                    Text("Finding familiar faces")
                        .font(PotoDesign.largeTitle)
                        .foregroundStyle(PotoDesign.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 36)
                    Text("We’re looking through your photos.")
                        .font(PotoDesign.body)
                        .foregroundStyle(PotoDesign.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                    Spacer(minLength: 28)
                    progressPill
                    Spacer(minLength: 28)
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.potoText)
                        .accessibilityHint("Asks before stopping the search")
                    Text("This may take a moment.")
                        .font(PotoDesign.caption)
                        .foregroundStyle(PotoDesign.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, PotoDesign.sessionMargin)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var progressPill: some View {
        HStack(spacing: 10) {
            FaceScanSpinner()
            Text("\(progress.photosChecked) photos · \(progress.facesFound) faces found")
                .font(PotoDesign.secondaryBody)
                .foregroundStyle(PotoDesign.selectedContent)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(PotoDesign.selectedSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A face inside a viewfinder with a line scanning across it.
private struct FaceScanIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScanning = false

    private static let circleSize: CGFloat = 224
    private static let tileSize = CGSize(width: 160, height: 176)
    /// How far the line travels each way from the middle of the face.
    private static let scanReach: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().fill(PotoDesign.selectedSurface)
                .frame(width: Self.circleSize, height: Self.circleSize)

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(PotoDesign.selectedAccent)
                .frame(width: Self.tileSize.width, height: Self.tileSize.height)

            FaceMarksShape()
                .stroke(PotoDesign.selectedContent,
                        style: StrokeStyle(lineWidth: 2.75, lineCap: .round, lineJoin: .round))
                .frame(width: Self.tileSize.width, height: Self.tileSize.height)

            Capsule()
                .fill(PotoDesign.selectedContent.opacity(0.4))
                .frame(width: Self.tileSize.width * 0.79, height: 1.75)
                .offset(y: Self.tileSize.height * 0.035 + scanOffset)
        }
        .frame(width: Self.circleSize, height: Self.circleSize)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { isScanning = true }
        }
    }

    /// Reduce Motion: the line rests through the middle of the face, as in the design.
    private var scanOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return isScanning ? Self.scanReach : -Self.scanReach
    }
}

/// Viewfinder corners, eyes, nose and smile, in the tile's proportions.
private struct FaceMarksShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()

        let left: CGFloat = 0.145, right: CGFloat = 0.859, top: CGFloat = 0.145, bottom: CGFloat = 0.853
        let legX: CGFloat = 0.155, legY: CGFloat = 0.14
        let radius = rect.width * 0.07
        let corners: [(corner: CGPoint, start: CGPoint, end: CGPoint)] = [
            (point(left, top), point(left, top + legY), point(left + legX, top)),
            (point(right, top), point(right - legX, top), point(right, top + legY)),
            (point(right, bottom), point(right, bottom - legY), point(right - legX, bottom)),
            (point(left, bottom), point(left + legX, bottom), point(left, bottom - legY)),
        ]
        for item in corners {
            path.move(to: item.start)
            path.addArc(tangent1End: item.corner, tangent2End: item.end, radius: radius)
            path.addLine(to: item.end)
        }

        // Eyes
        path.move(to: point(0.368, 0.384))
        path.addLine(to: point(0.368, 0.44))
        path.move(to: point(0.632, 0.384))
        path.addLine(to: point(0.632, 0.44))

        // Nose
        path.move(to: point(0.529, 0.396))
        path.addLine(to: point(0.529, 0.49))
        path.addQuadCurve(to: point(0.478, 0.531), control: point(0.529, 0.531))

        // Smile
        path.move(to: point(0.395, 0.612))
        path.addQuadCurve(to: point(0.605, 0.612), control: point(0.5, 0.73))
        return path
    }
}

/// The small purple ring in the progress pill.
private struct FaceScanSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTurning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.78)
            .stroke(PotoDesign.selectedContent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 20, height: 20)
            .rotationEffect(.degrees(isTurning ? 360 : 0))
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { isTurning = true }
            }
    }
}

#Preview {
    FaceScanLoadingView(progress: FaceGroupingProgress(photosChecked: 25, facesFound: 11)) {}
        .background(PotoDesign.background)
}
