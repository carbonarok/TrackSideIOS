import Foundation
import Observation

enum BoardMode: String, CaseIterable {
    case departures = "Departures"
    case arrivals = "Arrivals"
}

@Observable
final class DepartureBoardService {
    var board: Board?
    var isLoading = false
    var error: String?
    var currentStationCode: String?
    var mode: BoardMode = .departures

    private let apiClient = APIClient()
    private let liveClient: LiveClient
    private var liveHandlerID: UUID?
    private var refreshTask: Task<Void, Never>?

    init(liveClient: LiveClient) {
        self.liveClient = liveClient
    }

    func loadBoard(for code: String, mode: BoardMode = .departures) async {
        stopLive()

        currentStationCode = code
        self.mode = mode
        isLoading = true
        error = nil

        do {
            switch mode {
            case .departures:
                board = try await apiClient.departures(for: code)
            case .arrivals:
                board = try await apiClient.arrivals(for: code)
            }
            isLoading = false
            await subscribeLive(code: code)
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    /// Legacy method for compatibility
    func loadDepartures(for code: String, to destination: String? = nil) async {
        await loadBoard(for: code, mode: .departures)
    }

    func refresh() async {
        guard let code = currentStationCode else { return }
        do {
            switch mode {
            case .departures:
                board = try await apiClient.departures(for: code)
            case .arrivals:
                board = try await apiClient.arrivals(for: code)
            }
        } catch {
            // Keep existing board on refresh failure
        }
    }

    private func subscribeLive(code: String) async {
        let topic = "station:\(code)"
        await liveClient.connect()
        await liveClient.subscribe(to: topic)

        liveHandlerID = await liveClient.onChange { [weak self] changedTopics in
            guard let self, changedTopics.contains(topic) else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    func stopLive() {
        if let code = currentStationCode {
            Task {
                await liveClient.unsubscribe(from: "station:\(code)")
            }
        }
        if let handlerID = liveHandlerID {
            Task {
                await liveClient.removeHandler(handlerID)
            }
        }
        liveHandlerID = nil
        refreshTask?.cancel()
    }
}
