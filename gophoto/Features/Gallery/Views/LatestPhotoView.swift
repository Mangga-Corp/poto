//
//  LatestPhotoView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 13/11/26.
//
import SwiftUI
import SwiftData

struct LatestPhotoView: View {
    @State private var viewModel = GalleryViewModel()
    @Query(sort: \GalleryPhoto.createdAt, order: .forward) private var photos: [GalleryPhoto]
    @State private var currentID = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var currentPhoto: GalleryPhoto? { photos.first { $0.assetID == currentID } }

    var body: some View {
        ZStack {
            AppPatternBackground()

            VStack(spacing: 0) {
                topBar
                if photos.isEmpty {
                    emptyState
                } else {
                    pager
                    PhotoStripView(photos: photos, currentID: $currentID, loadThumbnail: viewModel.thumbnail)
                        .padding(.top, 12)
                    bottomBar
                }
            }
        }
        .followsSystemColorScheme()
        .tint(PotoDesign.primary)
        .task { await viewModel.onAppear() }
        .task(id: photos.map(\.assetID)) {
            await viewModel.prepareThumbnails(for: photos.map(\.assetID))
        }
        .onAppear { if currentPhoto == nil { currentID = photos.last?.assetID ?? "" } }
        .onChange(of: photos.map(\.assetID)) { _, ids in
            if !ids.contains(currentID) { currentID = ids.last ?? "" }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.removeDeletedPhotos() } }
        }
        .appAlert("Couldn't Delete", isPresented: Binding(
            get: { viewModel.deleteErrorMessage != nil },
            set: { if !$0 { viewModel.deleteErrorMessage = nil } }
        ), message: viewModel.deleteErrorMessage, actions: [.primary("OK")])
    }

    private var topBar: some View {
        ZStack {
            if let photo = currentPhoto {
                let title = Self.title(for: photo.createdAt)
                let time = photo.createdAt.formatted(date: .omitted, time: .shortened)
                // A compact bar title (day + time), like the Photos app's: the same size at every
                // Larger Text setting, between the two buttons; long-press shows it enlarged.
                VStack(spacing: 0) {
                    Text(title)
                        .font(AppFont.headline)
                        .foregroundStyle(PotoDesign.primaryText)
                    Text(time)
                        .font(AppFont.caption)
                        .foregroundStyle(PotoDesign.secondaryText)
                }
                .lineLimit(1)
                .padding(.horizontal, 60)   // clear of the 44 pt buttons on both sides
                .fixedDynamicTypeSize()
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityShowsLargeContentViewer { Text("\(title), \(time)") }
            }

            HStack {
                Button { dismiss() } label: { circleIcon("chevron.left") }
                    .accessibilityLabel("Back")
                    .accessibilityShowsLargeContentViewer { Label("Back", systemImage: "chevron.left") }
                Spacer()
                Button(action: openPhotosApp) {
                    Image(systemName: "photo.on.rectangle")
                        .font(AppFont.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(PotoDesign.primary, in: Circle())
                }
                .accessibilityLabel("Open Photos")
                .accessibilityShowsLargeContentViewer { Label("Open Photos", systemImage: "photo.on.rectangle") }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var pager: some View {
        TabView(selection: $currentID) {
            ForEach(photos) { photo in
                FullPhotoView(assetID: photo.assetID, createdAt: photo.createdAt, loadImage: viewModel.fullImage)
                    .tag(photo.assetID)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var bottomBar: some View {
        HStack {
            ShareLink(item: SharedPhoto(assetID: currentID),
                      preview: SharePreview("Photo", image: Image(systemName: "photo"))) {
                circleIcon("square.and.arrow.up")
            }
            .accessibilityLabel("Share")
            .accessibilityShowsLargeContentViewer { Label("Share", systemImage: "square.and.arrow.up") }
            Spacer()
            Button {
                Task { await deleteCurrent() }
            } label: {
                circleIcon("trash")
            }
            .accessibilityLabel("Delete")
            .accessibilityShowsLargeContentViewer { Label("Delete", systemImage: "trash") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(AppFont.scaled(size: 40, relativeTo: .largeTitle))
                .foregroundStyle(PotoDesign.secondaryText)
            Text("No photos yet")
                .font(PotoDesign.sectionTitle)
                .foregroundStyle(PotoDesign.primaryText)
            Text("Photos you take with Poto will show up here.")
                .font(PotoDesign.secondaryBody)
                .foregroundStyle(PotoDesign.secondaryText)
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(AppFont.system(size: 16, weight: .semibold))
            .foregroundStyle(PotoDesign.primaryText)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(PotoDesign.border, lineWidth: 0.8))
    }

    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        openURL(url)
    }

    private func deleteCurrent() async {
        let deletingID = currentID
        let next = neighbor(of: deletingID)
        guard await viewModel.delete(assetID: deletingID) else { return }
        if let next { currentID = next }
    }

    private func neighbor(of id: String) -> String? {
        guard let index = photos.firstIndex(where: { $0.assetID == id }) else { return nil }
        if index > 0 { return photos[index - 1].assetID }
        if index + 1 < photos.count { return photos[index + 1].assetID }
        return nil
    }

    static func title(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.day().month(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }
}
