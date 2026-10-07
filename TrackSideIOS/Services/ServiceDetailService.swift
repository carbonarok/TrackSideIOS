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
                do {
                    self.detail = try await self.apiClient.serviceDetail(uid: uid, date: date)
                } catch {
                    // Keep existing detail on refresh failure
                }
            }
        }
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
