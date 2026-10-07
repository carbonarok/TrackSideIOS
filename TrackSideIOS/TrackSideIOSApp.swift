import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct TrackSideIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var liveClient: LiveClient
    @State private var journeyManager: ActiveJourneyManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let client = LiveClient(url: AppConfig.webSocketURL)
        _liveClient = State(initialValue: client)
        _journeyManager = State(initialValue: ActiveJourneyManager(liveClient: client))

        // Register background refresh task for live activity updates
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: JourneyTracker.backgroundRefreshID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                await ActiveJourneyManager.handleBackgroundRefresh(refreshTask)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(liveClient: liveClient)
                .environment(journeyManager)
        }
        .modelContainer(for: [SavedRoute.self, FavouriteStation.self, JourneyRecord.self])
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await journeyManager.handleForegroundTransition()
                }
            case .background:
                // Schedule background refresh when app goes to background
                journeyManager.tracker?.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }
}
