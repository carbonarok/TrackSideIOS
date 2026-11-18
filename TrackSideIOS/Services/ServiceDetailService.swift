import Foundation
import Observation

@Observable
final class ServiceDetailService {
    var detail: ServiceDetail?
    var isLoading = false
    var error: String?

    private let apiClient = APIClient()
    private let liveClient: LiveClient
    private var liveHandlerID: UUID?
    /// A refresh is running, and another was asked for meanwhile.
    private var isRefreshing = false
    private var refreshAgain = false

    init(liveClient: LiveClient) {
        self.liveClient = liveClient
    }

    func loadService(uid: String, date: String) async {
        stopLive()
        isLoading = true
        error = nil

        do {
            detail = try await apiClient.serviceDetail(uid: uid, date: date)
            isLoading = false
            await subscribeLive(uid: uid, date: date)
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func subscribeLive(uid: String, date: String) async {
        let topic = "train:\(uid)|\(date)"
        await liveClient.connect()
        await liveClient.subscribe(to: topic)

        liveHandlerID = await liveClient.onChange { [weak self] changedTopics in
            guard let self, changedTopics.contains(topic) else { return }
            Task { @MainActor in
                await self.refresh(uid: uid, date: date)
            }
        }
    }

    /// Fetches the train again. Changes that arrive while a refresh is
    /// running are folded into one more refresh after it, not one each.
    private func refresh(uid: String, date: String) async {
        if isRefreshing {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            do {
                let fresh = try await apiClient.serviceDetail(uid: uid, date: date)
                // Another train was opened while this one loaded.
                guard detail == nil || (detail?.uid == uid && detail?.runDate == date) else { return }
                detail = fresh
            } catch {
                // Keep existing detail on refresh failure
            }
        } while refreshAgain
    }

    func stopLive() {
        if let detail {
            let topic = "train:\(detail.uid)|\(detail.runDate)"
            Task {
                await liveClient.unsubscribe(from: topic)
            }
        }
        if let handlerID = liveHandlerID {
            Task {
                await liveClient.removeHandler(handlerID)
            }
        }
        liveHandlerID = nil
    }
}
