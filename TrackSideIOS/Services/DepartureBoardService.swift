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
    /// When true, the displayed board was loaded from cache and may be stale
    var isCachedData = false

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
        error = nil

        // Show cached data immediately while fetching fresh data
        if let cached = Self.loadCachedBoard(code: code, mode: mode) {
            board = cached
            isCachedData = true
        }
        isLoading = board == nil

        do {
            let freshBoard: Board
            switch mode {
            case .departures:
                freshBoard = try await apiClient.departures(for: code)
            case .arrivals:
                freshBoard = try await apiClient.arrivals(for: code)
            }
            board = freshBoard
            isCachedData = false
            isLoading = false
            Self.cacheBoard(freshBoard, code: code, mode: mode)
            await subscribeLive(code: code)
        } catch {
            if board == nil {
                self.error = error.localizedDescription
            }
            // If we have cached data, keep showing it
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
            let freshBoard: Board
            switch mode {
            case .departures:
                freshBoard = try await apiClient.departures(for: code)
            case .arrivals:
                freshBoard = try await apiClient.arrivals(for: code)
            }
            board = freshBoard
            isCachedData = false
            Self.cacheBoard(freshBoard, code: code, mode: mode)
        } catch {
            // Keep existing board on refresh failure
        }
    }

    // MARK: - Cache

    private static let cacheDirectory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DepartureBoards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func cacheKey(code: String, mode: BoardMode) -> String {
        "\(code)_\(mode.rawValue)"
    }

    private static func cacheBoard(_ board: Board, code: String, mode: BoardMode) {
        let url = cacheDirectory.appendingPathComponent("\(cacheKey(code: code, mode: mode)).json")
        do {
            let data = try JSONEncoder().encode(board)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[BoardCache] Failed to cache: \(error)")
        }
    }

    private static func loadCachedBoard(code: String, mode: BoardMode) -> Board? {
        let url = cacheDirectory.appendingPathComponent("\(cacheKey(code: code, mode: mode)).json")
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Only use cache if it's less than 30 minutes old
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > 1800 {
            return nil
        }

        return try? JSONDecoder().decode(Board.self, from: data)
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
