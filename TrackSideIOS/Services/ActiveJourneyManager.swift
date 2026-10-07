import Foundation
import ActivityKit
import SwiftData
import Observation
import BackgroundTasks

/// App-level manager that keeps the active JourneyTracker alive across view lifecycle.
/// Survives navigation changes and app backgrounding, ensuring the Live Activity
/// continues to update and can be properly stopped by the user.
@Observable
final class ActiveJourneyManager {
    /// Shared instance for background task access
    private(set) static var current: ActiveJourneyManager?

    private(set) var tracker: JourneyTracker?
    private(set) var trackedRouteID: PersistentIdentifier?
    private let liveClient: LiveClient

    init(liveClient: LiveClient) {
        self.liveClient = liveClient
        ActiveJourneyManager.current = self
    }

    var isTracking: Bool {
        tracker?.isTracking == true
    }

    /// Callback for saving journey history. Set by the view that has access to ModelContext.
    var onJourneyComplete: ((JourneyRecord) -> Void)?

    /// Start tracking a journey, stopping any existing tracking first.
    func startTracking(journey: CalculatedJourney, routeID: PersistentIdentifier) async throws {
        stopTracking()
        cleanUpStaleActivities()

        let newTracker = JourneyTracker(journey: journey, liveClient: liveClient)
        newTracker.onJourneyComplete = { [weak self] record in
            self?.onJourneyComplete?(record)
        }
        tracker = newTracker
        trackedRouteID = routeID
        try await newTracker.startTracking()
    }

    func stopTracking() {
        tracker?.stopTracking()
        tracker = nil
        trackedRouteID = nil
    }

    /// Returns the tracker only if it's actively tracking the given route.
    func tracker(for routeID: PersistentIdentifier) -> JourneyTracker? {
        guard trackedRouteID == routeID, let tracker, tracker.isTracking else { return nil }
        return tracker
    }

    /// Called when app returns to foreground — force reconnects WebSocket and refreshes data.
    func handleForegroundTransition() async {
        await liveClient.ensureConnected()
        if let tracker, tracker.isTracking {
            print("[ActiveJourneyManager] Refreshing tracker after foreground transition")
            await tracker.refreshAfterReconnect()
        }
    }

    /// Called from the BGAppRefreshTask handler to update activities in the background.
    static func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        guard let manager = current, let tracker = manager.tracker, tracker.isTracking else {
            task.setTaskCompleted(success: true)
            return
        }

        task.expirationHandler = {
            // Re-schedule if we run out of time
            tracker.scheduleBackgroundRefresh()
        }

        await tracker.performBackgroundRefresh()
        task.setTaskCompleted(success: true)
    }

    /// End any live activities left over from a previous app session.
    private func cleanUpStaleActivities() {
        let legActivities = Activity<LegActivityAttributes>.activities
        let journeyActivities = Activity<JourneyActivityAttributes>.activities
        let trainActivities = Activity<TrainActivityAttributes>.activities

        let total = legActivities.count + journeyActivities.count + trainActivities.count
        if total > 0 {
            print("[ActiveJourneyManager] Cleaning up \(total) stale activities")
        }

        for activity in legActivities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        for activity in journeyActivities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        for activity in trainActivities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
