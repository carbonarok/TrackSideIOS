import SwiftUI
import SwiftData
import Combine
import BackgroundTasks

@main
struct TrackSideIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var liveClient: LiveClient
    @State private var journeyManager: ActiveJourneyManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let client = LiveClient()
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
                .onReceive(NotificationCenter.default.publisher(for: ServerSettings.didChange)) { _ in
                    Task { await liveClient.ensureConnected() }
                }
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
