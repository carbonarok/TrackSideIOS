import Foundation
import ActivityKit
import UserNotifications
import SwiftData
import Observation
import BackgroundTasks

/// Tracks a calculated journey via WebSocket, refreshing service details
/// when trains change and updating a Live Activity with the journey state.
@Observable
final class JourneyTracker {
    static let backgroundRefreshID = "com.trackside.journey-refresh"

    private(set) var isTracking = false
    private(set) var currentLegIndex: Int = 0

    /// Fresh service details keyed by leg index, updated via WebSocket
    private(set) var legDetails: [Int: ServiceDetail] = [:]

    /// Updated leg info derived from fresh service details
    private(set) var updatedLegs: [CalculatedLeg]

    /// Callback to save journey history when complete
    var onJourneyComplete: ((JourneyRecord) -> Void)?

    private let journey: CalculatedJourney
    private let liveClient: LiveClient
    private let apiClient = APIClient()

    private var handlerID: UUID?
    /// One live activity per leg
    private var legActivities: [Int: Activity<LegActivityAttributes>] = [:]
    /// Tasks observing each activity's push token updates
    private var pushTokenTasks: [Int: Task<Void, Never>] = [:]
    /// Legs whose alerts the server sends as notifications (registered with
    /// the device token), so the app doesn't post its own as well.
    private var serverNotifiedLegs: Set<Int> = []
    /// Tasks observing each activity's state updates (dismissal detection)
    private var stateTasks: [Int: Task<Void, Never>] = [:]
    private var topicToLegIndex: [String: Int] = [:]
    private var settings = LiveActivitySettings()
    private var fallbackPollTask: Task<Void, Never>?
    /// Track previous platform values to detect changes (keyed by "dep-N" / "arr-N")
    private var lastKnownPlatforms: [String: String] = [:]
    /// Track previous delay values to detect increases
    private var lastKnownDelays: [Int: Int] = [:]
    /// Whether push token support is available (paid dev team)
    private var pushAvailable = false

    init(journey: CalculatedJourney, liveClient: LiveClient) {
        self.journey = journey
        self.updatedLegs = journey.legs
        self.liveClient = liveClient
        requestNotificationPermission()
    }

    // MARK: - Public

    func startTracking() async throws {
        guard !isTracking else { return }

        settings = LiveActivitySettings.load()

        // Build topic-to-leg mapping
        var topics: [String] = []
        for (index, leg) in journey.legs.enumerated() {
            let topic = "train:\(leg.service.uid)|\(leg.service.runDate)"
            topics.append(topic)
            topicToLegIndex[topic] = index
        }

        // Connect and subscribe
        await liveClient.connect()
        await liveClient.subscribe(to: topics)

        // Register change handler
        let topicSet = Set(topics)
        handlerID = await liveClient.onChange { [weak self] changedTopics in
            let relevant = changedTopics.intersection(topicSet)
            if !relevant.isEmpty {
                Task { @MainActor in
                    await self?.handleChanges(topics: relevant)
                }
            }
        }

        // Start one Live Activity per leg with push token support
        for (index, leg) in journey.legs.enumerated() {
            let headcode = leg.service.headcode ?? leg.service.uid
            let attributes = LegActivityAttributes(
                legIndex: index,
                totalLegs: journey.totalLegs,
                headcode: headcode,
                originName: leg.originName,
                destinationName: leg.destinationName,
                operatorName: leg.service.operator?.name ?? ""
            )
            let state = buildLegState(for: index)
            let staleDate = state.departureDate?.addingTimeInterval(900) ?? Date().addingTimeInterval(900)
            let content = ActivityContent(state: state, staleDate: staleDate)
            do {
                // Try with push token support first; fall back to nil if entitlement is missing
                let activity: Activity<LegActivityAttributes>
                do {
                    activity = try Activity.request(
                        attributes: attributes,
                        content: content,
                        pushType: .token
                    )
                    // Push supported — observe tokens and register with backend
                    pushAvailable = true
                    observePushToken(for: activity, legIndex: index)
                    observeActivityState(for: activity, legIndex: index)
                } catch {
                    // Push not available (e.g. personal dev team) — start without it
                    print("[JourneyTracker] Push token not available, starting without: \(error.localizedDescription)")
                    activity = try Activity.request(
                        attributes: attributes,
                        content: content,
                        pushType: nil
                    )
                }
                legActivities[index] = activity
                print("[JourneyTracker] Started activity for leg \(index): \(headcode)")
            } catch {
                print("[JourneyTracker] Failed to start activity for leg \(index): \(error)")
            }
        }

        isTracking = true

        // Initial fetch of all fresh details
        await refreshAllLegs()

        // Only poll as fallback when push is not available — with push,
        // the backend sends updates directly to the Live Activity.
        if !pushAvailable {
            startFallbackPolling()
        } else {
            print("[JourneyTracker] Push available — skipping fallback polling")
        }
    }

    /// Re-subscribe and refresh all data after a WebSocket reconnect (e.g. foreground transition).
    func refreshAfterReconnect() async {
        guard isTracking else { return }
        print("[JourneyTracker] Refreshing after reconnect")
        await refreshAllLegs()
    }

    func stopTracking() {
        guard isTracking else { return }

        // Cancel fallback polling
        fallbackPollTask?.cancel()
        fallbackPollTask = nil

        // Cancel push token and state observation tasks
        for (_, task) in pushTokenTasks { task.cancel() }
        pushTokenTasks.removeAll()
        for (_, task) in stateTasks { task.cancel() }
        stateTasks.removeAll()

        // Remove WebSocket handler
        if let handlerID {
            Task {
                await liveClient.removeHandler(handlerID)
            }
        }
        handlerID = nil

        // Unsubscribe from topics
        let topics = Array(topicToLegIndex.keys)
        if !topics.isEmpty {
            Task {
                await liveClient.unsubscribe(from: topics)
            }
        }
        topicToLegIndex.removeAll()

        // End all leg activities and deregister from backend
        let activities = legActivities
        Task {
            for (_, activity) in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
                await apiClient.deregisterActivity(activityID: activity.id)
            }
        }
        legActivities.removeAll()
        isTracking = false
    }

    // MARK: - Internal

    private func startFallbackPolling() {
        fallbackPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                print("[JourneyTracker] Fallback poll — refreshing all legs")
                await self.refreshAllLegs()
            }
        }
    }

    private func handleChanges(topics: Set<String>) async {
        print("[JourneyTracker] WebSocket change for: \(topics.joined(separator: ", "))")
        for topic in topics {
            guard let legIndex = topicToLegIndex[topic] else { continue }
            let leg = journey.legs[legIndex]
            do {
                let detail = try await apiClient.serviceDetail(
                    uid: leg.service.uid,
                    date: leg.service.runDate
                )
                legDetails[legIndex] = detail
                updateLeg(at: legIndex, with: detail)
                checkForAlerts(legIndex: legIndex)
                print("[JourneyTracker] Updated leg \(legIndex) — status: \(detail.status.rawValue)")
            } catch {
                print("[JourneyTracker] Failed to refresh leg \(legIndex): \(error)")
            }
        }
        determineCurrentLeg()
        await updateActivities()
    }

    private func refreshAllLegs() async {
        print("[JourneyTracker] Refreshing all \(journey.legs.count) leg(s)")
        await withTaskGroup(of: (Int, ServiceDetail?).self) { group in
            for (index, leg) in journey.legs.enumerated() {
                group.addTask { [apiClient] in
                    let detail = try? await apiClient.serviceDetail(
                        uid: leg.service.uid,
                        date: leg.service.runDate
                    )
                    return (index, detail)
                }
            }
            for await (index, detail) in group {
                if let detail {
                    legDetails[index] = detail
                    updateLeg(at: index, with: detail)
                    checkForAlerts(legIndex: index)
                }
            }
        }
        determineCurrentLeg()
        print("[JourneyTracker] Current leg: \(currentLegIndex), phase will be determined by activity state")
        await updateActivities()
    }

    /// Update a calculated leg with fresh service detail data
    private func updateLeg(at index: Int, with detail: ServiceDetail) {
        guard index < updatedLegs.count else { return }
        let original = updatedLegs[index]

        // Find the origin and destination stops in the fresh detail
        let originStop = detail.stops.first { $0.crs == original.service.stop.crs || $0.tiploc == original.service.stop.tiploc }
        let destCode = journey.legs[index].service.destination.first?.crs
            ?? journey.legs[index].service.destination.first?.tiploc ?? ""
        let destStop = detail.stops.last { $0.crs == destCode || $0.tiploc == destCode }

        let freshDepartureTime = originStop?.departure?.bestTime ?? original.departureTime
        let freshArrivalTime = destStop?.arrival?.bestTime ?? original.arrivalTime
        let freshDepPlatform = originStop?.platform?.displayPlatform ?? original.departurePlatform
        let freshArrPlatform = destStop?.platform?.displayPlatform ?? original.arrivalPlatform
        let freshDepDelay = originStop?.departure?.delayMinutes ?? original.departureDelay
        let freshArrDelay = destStop?.arrival?.delayMinutes ?? original.arrivalDelay
        let freshCancelled = detail.isCancelled

        // Recompute connection minutes from previous leg if applicable
        let connectionMinutes: Int?
        if index > 0, let prevArrival = updatedLegs[index - 1].arrivalTime,
           let prevDate = parseTime(prevArrival),
           let depTime = freshDepartureTime,
           let depDate = parseTime(depTime) {
            connectionMinutes = max(0, Int(depDate.timeIntervalSince(prevDate) / 60))
        } else {
            connectionMinutes = original.connectionMinutes
        }

        updatedLegs[index] = CalculatedLeg(
            legIndex: original.legIndex,
            service: original.service,
            serviceDetail: detail,
            originName: original.originName,
            destinationName: original.destinationName,
            departureTime: freshDepartureTime,
            arrivalTime: freshArrivalTime,
            departurePlatform: freshDepPlatform,
            arrivalPlatform: freshArrPlatform,
            departureDelay: freshDepDelay,
            arrivalDelay: freshArrDelay,
            isCancelled: freshCancelled,
            connectionMinutes: connectionMinutes
        )
    }

    /// Determine which leg the user is currently on based on train positions and times
    private func determineCurrentLeg() {
        let now = Date()

        for (index, leg) in updatedLegs.enumerated().reversed() {
            guard let detail = legDetails[index] else { continue }

            // If the train for this leg has an actual departure from the user's origin,
            // and hasn't arrived at the user's destination, the user is on this train
            let destCode = journey.legs[index].service.destination.first?.crs
                ?? journey.legs[index].service.destination.first?.tiploc ?? ""
            let originStop = detail.stops.first { $0.crs == leg.service.stop.crs || $0.tiploc == leg.service.stop.tiploc }
            let destStop = detail.stops.last { $0.crs == destCode || $0.tiploc == destCode }

            let hasDeparted = originStop?.departure?.actual != nil
            let hasArrived = destStop?.arrival?.actual != nil

            if hasDeparted && !hasArrived {
                currentLegIndex = index
                return
            }
            if hasArrived {
                // This leg is done; if it's the last, we're arrived
                if index == updatedLegs.count - 1 {
                    currentLegIndex = index
                    return
                }
                // Otherwise move to next leg (user is waiting for connection)
                currentLegIndex = index + 1
                return
            }
        }

        // No actual data yet — estimate from scheduled times
        for (index, leg) in updatedLegs.enumerated() {
            if let depTime = leg.departureTime, let depDate = parseTime(depTime), depDate > now {
                currentLegIndex = max(0, index)
                return
            }
        }
        currentLegIndex = 0
    }

    // MARK: - Live Activities (per-leg)

    private func updateActivities() async {
        for (index, activity) in legActivities {
            let state = buildLegState(for: index)

            // Set staleDate as a hint to the system — generous interval since
            // BGAppRefreshTask isn't reliable for real-time updates.
            // The widget handles expired timers gracefully without needing isStale.
            let staleDate: Date?
            switch state.phase {
            case "boarding":
                staleDate = state.departureDate?.addingTimeInterval(900)
            case "onTrain":
                staleDate = state.arrivalDate?.addingTimeInterval(900)
            case "arrived":
                staleDate = nil
            default:
                staleDate = Date().addingTimeInterval(900)
            }

            let content = ActivityContent(state: state, staleDate: staleDate)
            print("[JourneyTracker] Updating leg \(index) activity — phase: \(state.phase)")
            await activity.update(content)

            // End individual leg activity when that leg arrives
            if isLegComplete(index) && state.phase == "arrived" {
                await activity.end(content, dismissalPolicy: .after(.now + 120))
                await apiClient.deregisterActivity(activityID: activity.id)
                pushTokenTasks[index]?.cancel()
                pushTokenTasks[index] = nil
                stateTasks[index]?.cancel()
                stateTasks[index] = nil
                legActivities[index] = nil
                print("[JourneyTracker] Ended activity for leg \(index)")
            }
        }

        // Schedule next background refresh to keep activities alive
        scheduleBackgroundRefresh()

        // Check if entire journey is complete
        if isJourneyComplete() {
            isTracking = false
            saveJourneyRecord()
            sendNotification(
                title: "Journey Complete",
                body: "Arrived at \(journey.legs.last?.destinationName ?? "destination")",
                id: "journey-complete"
            )
        }
    }

    private func buildLegState(for index: Int) -> LegActivityAttributes.ContentState {
        let leg = updatedLegs[safe: index]
        let detail = legDetails[index]

        // Determine phase for this specific leg
        let phase: String
        if isLegComplete(index) {
            phase = "arrived"
        } else if let leg = leg, let detail {
            let originStop = detail.stops.first { $0.crs == leg.service.stop.crs || $0.tiploc == leg.service.stop.tiploc }
            let destCode = journey.legs[index].service.destination.first?.crs
                ?? journey.legs[index].service.destination.first?.tiploc ?? ""
            let destStop = detail.stops.last { $0.crs == destCode || $0.tiploc == destCode }

            let hasDeparted = originStop?.departure?.actual != nil
            let hasArrived = destStop?.arrival?.actual != nil

            if hasArrived {
                phase = "arrived"
            } else if hasDeparted {
                phase = "onTrain"
            } else if index <= currentLegIndex {
                phase = "boarding"
            } else {
                phase = "upcoming"
            }
        } else if index <= currentLegIndex {
            phase = "boarding"
        } else {
            phase = "upcoming"
        }

        // Platform info
        let depPlatform: String? = leg?.departurePlatform
        let arrPlatform: String? = leg?.arrivalPlatform
        var depPlatChanged = false
        var arrPlatChanged = false

        if let leg, let detail {
            let originStop = detail.stops.first { $0.crs == leg.service.stop.crs || $0.tiploc == leg.service.stop.tiploc }
            let destCode = journey.legs[index].service.destination.first?.crs
                ?? journey.legs[index].service.destination.first?.tiploc ?? ""
            let destStop = detail.stops.last { $0.crs == destCode || $0.tiploc == destCode }
            depPlatChanged = originStop?.platform?.changed ?? false
            arrPlatChanged = destStop?.platform?.changed ?? false
        }
        // A platform that changes while tracked stays marked changed (red),
        // as the server marks it in pushed updates.
        if let shown = legActivities[index]?.content.state {
            depPlatChanged = depPlatChanged
                || Self.movedSince(shown.departurePlatform, shown.departurePlatformChanged, depPlatform)
            arrPlatChanged = arrPlatChanged
                || Self.movedSince(shown.arrivalPlatform, shown.arrivalPlatformChanged, arrPlatform)
        }

        // Times
        let depDelay = leg?.departureDelay ?? 0
        let arrDelay = leg?.arrivalDelay ?? 0

        // Scheduled times: use the public/working time from the stop data
        var scheduledDep: String?
        var scheduledArr: String?
        var expectedDep: String?
        var expectedArr: String?

        if let leg, let detail {
            let originStop = detail.stops.first { $0.crs == leg.service.stop.crs || $0.tiploc == leg.service.stop.tiploc }
            let destCode = journey.legs[index].service.destination.first?.crs
                ?? journey.legs[index].service.destination.first?.tiploc ?? ""
            let destStop = detail.stops.last { $0.crs == destCode || $0.tiploc == destCode }

            // Scheduled = public or working time
            scheduledDep = (originStop?.departure?.`public` ?? originStop?.departure?.working).map { formatTimeShort($0) }
            scheduledArr = (destStop?.arrival?.`public` ?? destStop?.arrival?.working).map { formatTimeShort($0) }

            // Expected = actual or estimated, only if different from scheduled
            let liveDep = (originStop?.departure?.actual ?? originStop?.departure?.estimated).map { formatTimeShort($0) }
            let liveArr = (destStop?.arrival?.actual ?? destStop?.arrival?.estimated).map { formatTimeShort($0) }
            expectedDep = (liveDep != nil && liveDep != scheduledDep) ? liveDep : nil
            expectedArr = (liveArr != nil && liveArr != scheduledArr) ? liveArr : nil
        } else {
            scheduledDep = leg?.departureTime.map { formatTimeShort($0) }
            scheduledArr = leg?.arrivalTime.map { formatTimeShort($0) }
        }

        // Countdown dates (use best available time for accuracy)
        let depDate: Date? = leg?.departureTime.flatMap { parseTime($0) }
        let arrDate: Date? = leg?.arrivalTime.flatMap { parseTime($0) }

        // Connection time from previous leg
        let connectionMinutes = leg?.connectionMinutes

        // Cancel info
        let isCancelled = leg?.isCancelled ?? false
        let cancelReason: String? = {
            guard let detail else { return nil }
            return detail.cancelReason ?? detail.cancelReasonCodeDescription
        }()

        return LegActivityAttributes.ContentState(
            phase: phase,
            departurePlatform: depPlatform,
            departurePlatformChanged: depPlatChanged,
            arrivalPlatform: arrPlatform,
            arrivalPlatformChanged: arrPlatChanged,
            scheduledDeparture: scheduledDep,
            expectedDeparture: expectedDep,
            scheduledArrival: scheduledArr,
            expectedArrival: expectedArr,
            departureDate: depDate,
            arrivalDate: arrDate,
            departureDelayMinutes: depDelay,
            arrivalDelayMinutes: arrDelay,
            isCancelled: isCancelled,
            cancelReason: cancelReason,
            connectionMinutes: connectionMinutes,
            lastUpdated: .now
        )
    }

    private func isLegComplete(_ index: Int) -> Bool {
        guard let detail = legDetails[index] else { return false }
        let destCode = journey.legs[index].service.destination.first?.crs
            ?? journey.legs[index].service.destination.first?.tiploc ?? ""
        let destStop = detail.stops.last { $0.crs == destCode || $0.tiploc == destCode }
        return destStop?.arrival?.actual != nil
    }

    private func isJourneyComplete() -> Bool {
        guard let _ = updatedLegs.last,
              let detail = legDetails[updatedLegs.count - 1] else { return false }
        let destCode = journey.legs.last?.service.destination.first?.crs
            ?? journey.legs.last?.service.destination.first?.tiploc ?? ""
        let destStop = detail.stops.last { $0.crs == destCode || $0.tiploc == destCode }
        return destStop?.arrival?.actual != nil
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Whether a platform has changed while tracked: it moved since it was
    /// last shown, or had moved before and is still there.
    private static func movedSince(_ was: String?, _ wasChanged: Bool, _ now: String?) -> Bool {
        guard let was, let now else { return false }
        return was != now || wasChanged
    }

    /// Check for platform changes and delay increases, send notifications
    private func checkForAlerts(legIndex: Int) {
        let leg = updatedLegs[legIndex]
        let headcode = leg.service.headcode ?? leg.service.uid
        // The server notifies for this leg; keep track of values but don't
        // post a second notification for the same change.
        let notify = !serverNotifiedLegs.contains(legIndex)

        // Departure platform change detection
        if let platform = leg.departurePlatform {
            let key = "dep-\(legIndex)"
            if notify, let previousPlatform = lastKnownPlatforms[key], previousPlatform != platform {
                sendNotification(
                    title: "Platform Changed",
                    body: "\(headcode) at \(leg.originName): Platform changed from \(previousPlatform) to \(platform)",
                    id: "platform-dep-\(legIndex)-\(platform)"
                )
            }
            lastKnownPlatforms[key] = platform
        }

        // Arrival platform change detection
        if let platform = leg.arrivalPlatform {
            let key = "arr-\(legIndex)"
            if notify, let previousPlatform = lastKnownPlatforms[key], previousPlatform != platform {
                sendNotification(
                    title: "Arrival Platform Changed",
                    body: "\(headcode) at \(leg.destinationName): Platform changed from \(previousPlatform) to \(platform)",
                    id: "platform-arr-\(legIndex)-\(platform)"
                )
            }
            lastKnownPlatforms[key] = platform
        }

        // Delay increase detection
        let currentDelay = leg.departureDelay ?? leg.arrivalDelay ?? 0
        if notify, let previousDelay = lastKnownDelays[legIndex] {
            if currentDelay >= 5 && currentDelay > previousDelay + 2 {
                sendNotification(
                    title: "Delay Increased",
                    body: "\(headcode): now +\(currentDelay) min (was +\(previousDelay) min)",
                    id: "delay-\(legIndex)-\(currentDelay)"
                )
            }
        }
        lastKnownDelays[legIndex] = currentDelay

        // Cancellation alert
        if notify, leg.isCancelled {
            sendNotification(
                title: "Train Cancelled",
                body: "\(headcode) from \(leg.originName) to \(leg.destinationName) has been cancelled",
                id: "cancelled-\(legIndex)"
            )
        }
    }

    private func sendNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Journey History

    private func saveJourneyRecord() {
        let legSummaries = updatedLegs.map { leg in
            LegSummary(
                headcode: leg.service.headcode ?? leg.service.uid,
                operatorName: leg.service.operator?.name ?? "",
                originName: leg.originName,
                destinationName: leg.destinationName,
                delayMinutes: leg.arrivalDelay ?? leg.departureDelay ?? 0,
                cancelled: leg.isCancelled
            )
        }

        let maxDelay = updatedLegs.compactMap { $0.arrivalDelay ?? $0.departureDelay }.max() ?? 0
        let wasCancelled = updatedLegs.contains { $0.isCancelled }

        let record = JourneyRecord(
            routeName: journey.legs.first.map { "\($0.originName) → \(journey.legs.last!.destinationName)" } ?? "Journey",
            originName: journey.legs.first?.originName ?? "",
            destinationName: journey.legs.last?.destinationName ?? "",
            scheduledDeparture: journey.departureTime.flatMap { parseTime($0) },
            actualDeparture: updatedLegs.first?.departureTime.flatMap { parseTime($0) },
            scheduledArrival: journey.arrivalTime.flatMap { parseTime($0) },
            actualArrival: updatedLegs.last?.arrivalTime.flatMap { parseTime($0) },
            totalLegs: journey.totalLegs,
            maxDelayMinutes: maxDelay,
            wasCancelled: wasCancelled,
            legSummaries: legSummaries
        )

        onJourneyComplete?(record)
    }

    // MARK: - Push Token Registration

    /// Observe push token updates for an activity and register with the backend.
    private func observePushToken(for activity: Activity<LegActivityAttributes>, legIndex: Int) {
        let leg = journey.legs[legIndex]
        let destCode = leg.service.destination.first?.crs
            ?? leg.service.destination.first?.tiploc ?? ""

        pushTokenTasks[legIndex] = Task { [weak self, apiClient] in
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
                print("[JourneyTracker] Push token for leg \(legIndex): \(hexToken.prefix(16))...")

                let state = await MainActor.run { self?.buildLegState(for: legIndex) }

                var body: [String: Any] = [
                    "push_token": hexToken,
                    "activity_id": activity.id,
                    "service_uid": leg.service.uid,
                    "run_date": leg.service.runDate,
                    "origin_crs": leg.service.stop.crs ?? leg.service.stop.tiploc,
                    "destination_crs": destCode,
                    "bundle_id": Bundle.main.bundleIdentifier ?? "",
                    "connection_minutes": self?.updatedLegs[safe: legIndex]?.connectionMinutes as Any,
                    "phase": state?.phase ?? "upcoming"
                ]
                // Name the previous leg's train so the server works out the
                // connection from both trains' live times and updates it when
                // either changes, even with the app in the background.
                if legIndex > 0, let previous = self?.journey.legs[safe: legIndex - 1] {
                    body["previous_service_uid"] = previous.service.uid
                    body["previous_run_date"] = previous.service.runDate
                }

                // The device's own token, so alerts arrive as notifications.
                let deviceToken = await PushDeviceToken.value()
                if let deviceToken {
                    body["device_token"] = deviceToken
                }

                let status = await apiClient.registerActivity(body: body)
                if deviceToken != nil, status == 200 || status == 201 {
                    _ = await MainActor.run { self?.serverNotifiedLegs.insert(legIndex) }
                }
            }
        }
    }

    /// Observe activity state for user-initiated dismissal.
    private func observeActivityState(for activity: Activity<LegActivityAttributes>, legIndex: Int) {
        stateTasks[legIndex] = Task { [apiClient] in
            for await activityState in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                if activityState == .dismissed || activityState == .ended {
                    print("[JourneyTracker] Activity for leg \(legIndex) was dismissed/ended by user")
                    await apiClient.deregisterActivity(activityID: activity.id)
                    return
                }
            }
        }
    }

    // MARK: - Background Refresh

    /// Schedule a background app refresh to update activities while the app is suspended.
    /// Skipped when push is available since the backend handles updates via APNs.
    func scheduleBackgroundRefresh() {
        guard isTracking, !pushAvailable else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshID)
        // Request refresh in 5 minutes (system may delay further)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[JourneyTracker] Scheduled background refresh")
        } catch {
            print("[JourneyTracker] Failed to schedule background refresh: \(error)")
        }
    }

    /// Called from the app's background task handler.
    func performBackgroundRefresh() async {
        guard isTracking else { return }
        print("[JourneyTracker] Performing background refresh")
        await liveClient.ensureConnected()
        await refreshAllLegs()
    }

    // MARK: - Helpers

    private func formatTimeShort(_ timeString: String) -> String {
        if timeString.count > 10, let tIndex = timeString.firstIndex(of: "T") {
            let afterT = timeString[timeString.index(after: tIndex)...]
            return String(afterT.prefix(5))
        }
        return String(timeString.prefix(5))
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
