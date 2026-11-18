import SwiftUI
import SwiftData

@main
struct MyApp: App {
    init() {
        AppFont.register()
        Task { await FaceGroupingAvailability.purgeLeftovers() }   // Brian 8245a3e, restored 16 Nov
        #if DEBUG
        DebugFixtures.prepareLaunchState()
        DebugFixtures.seedIfNeeded()
        DebugFixtures.diagnoseVisionIfRequested()
        DebugFixtures.scheduleDeletionIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .font(AppFont.body)   // default for any text without its own font
                .appDynamicTypeLimit() // Larger Text grows up to AX1, so every screen stays tidy
        }
        .modelContainer(AppDatabase.container)
    }
}
