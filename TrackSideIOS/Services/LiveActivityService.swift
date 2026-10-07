import Foundation
import ActivityKit
import Observation

@Observable
final class LiveActivityService {
    private(set) var activeActivities: [String: Activity<TrainActivityAttributes>] = [:]
    private let apiClient = APIClient()
    private let liveClient: LiveClient
    private var updateHandlers: [String: UUID] = [:]

    init(liveClient: LiveClient) {
        self.liveClient = liveClient
    }

    func startTracking(service: ServiceDetail, destinationCRS: String?) throws {
        let attributes = TrainActivityAttributes(
            headcode: service.headcode ?? service.uid,
            originName: service.originName,
            destinationName: service.destinationName,
            operatorName: service.operator?.name ?? "Unknown",
            uid: service.uid,
            runDate: service.runDate
        )

        let initialState = buildContentState(from: service, destinationCRS: destinationCRS)
        let content = ActivityContent(state: initialState, staleDate: nil)

        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )

        let key = service.id
        activeActivities[key] = activity
        startLiveUpdates(for: key, uid: service.uid, date: service.runDate, destinationCRS: destinationCRS)
    }

    func stopTracking(key: String) {
        if let handlerID = updateHandlers[key] {
            Task {
                await liveClient.removeHandler(handlerID)
            }
        }
        updateHandlers.removeValue(forKey: key)

        Task {
            if let activity = activeActivities[key] {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            activeActivities.removeValue(forKey: key)
        }
    }

    func isTracking(_ serviceID: String) -> Bool {
        activeActivities[serviceID] != nil
    }

    private func startLiveUpdates(for key: String, uid: String, date: String, destinationCRS: String?) {
        let topic = "train:\(uid)|\(date)"
        Task {
            await liveClient.connect()
            await liveClient.subscribe(to: topic)

            let handlerID = await liveClient.onChange { [weak self] changedTopics in
                guard let self, changedTopics.contains(topic) else { return }
                Task { @MainActor in
                    await self.refreshActivity(key: key, uid: uid, date: date, destinationCRS: destinationCRS)
                }
            }
            updateHandlers[key] = handlerID
        }
    }

    private func refreshActivity(key: String, uid: String, date: String, destinationCRS: String?) async {
        do {
            let detail = try await apiClient.serviceDetail(uid: uid, date: date)
            let state = buildContentState(from: detail, destinationCRS: destinationCRS)
            let content = ActivityContent(state: state, staleDate: nil)
            await activeActivities[key]?.update(content)

            if detail.status == .terminated {
                await activeActivities[key]?.end(content, dismissalPolicy: .after(.now + 300))
                activeActivities.removeValue(forKey: key)
                if let handlerID = updateHandlers[key] {
                    await liveClient.removeHandler(handlerID)
                }
                updateHandlers.removeValue(forKey: key)
            }
        } catch {
            // Keep activity with stale data on failure
        }
    }

    private func buildContentState(from service: ServiceDetail, destinationCRS: String?) -> TrainActivityAttributes.ContentState {
        let destStop: Stop? = {
            if let crs = destinationCRS {
                return service.stops.first { $0.crs == crs }
            }
            return service.stops.last { $0.kind == .destination }
        }()

        let currentStop = service.stops.last { $0.atPlatform == true || $0.approaching == true }
        let nextStop: Stop? = {
            if let current = currentStop,
               let idx = service.stops.firstIndex(where: { $0.tiploc == current.tiploc }),
               idx + 1 < service.stops.count {
                return service.stops[idx + 1]
            }
            return nil
        }()

        let delay = destStop?.arrival?.delayMinutes ?? currentDelay(service) ?? 0
        let status: String
        if service.isCancelled {
            status = "Cancelled"
        } else if delay > 0 {
            status = "+\(delay) min"
        } else {
            status = "On time"
        }

        return TrainActivityAttributes.ContentState(
            currentStopName: currentStop?.name ?? service.originName,
            nextStopName: nextStop?.name,
            scheduledArrival: destStop?.arrival?.`public`,
            expectedArrival: destStop?.arrival?.estimated ?? destStop?.arrival?.actual,
            delayMinutes: delay,
            platformAtDestination: destStop?.platform?.displayPlatform,
            platformChanged: destStop?.platform?.changed ?? false,
            status: status,
            atPlatform: currentStop?.atPlatform ?? false,
            approaching: currentStop?.approaching ?? false,
            lastUpdated: .now
        )
    }

    private func currentDelay(_ service: ServiceDetail) -> Int? {
        for stop in service.stops.reversed() {
            if let dep = stop.departure, dep.actual != nil, let delay = dep.delayMinutes {
                return delay
            }
            if let arr = stop.arrival, arr.actual != nil, let delay = arr.delayMinutes {
                return delay
            }
        }
        return nil
    }
}
