import Foundation
import os
import Observation
import os

nonisolated enum BoardMode: String, CaseIterable, Sendable {
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
    /// A refresh is running, and another was asked for meanwhile.
    private var isRefreshing = false
    private var refreshAgain = false

    init(liveClient: LiveClient) {
        self.liveClient = liveClient
    }

    func loadBoard(for code: String, mode: BoardMode = .departures) async {
        stopLive()

        currentStationCode = code
        self.mode = mode
        error = nil

        // Show cached data immediately while fetching fresh data
        if let cached = await Self.loadCachedBoard(code: code, mode: mode),
           isCurrent(code: code, mode: mode) {
            board = cached
            isCachedData = true
        }
        isLoading = board == nil

        do {
            let freshBoard = try await fetchBoard(code: code, mode: mode)
            // Another station or mode was chosen while this one loaded.
            guard isCurrent(code: code, mode: mode) else { return }
            board = freshBoard
            isCachedData = false
            isLoading = false
            Task { await Self.cacheBoard(freshBoard, code: code, mode: mode) }
            await subscribeLive(code: code)
        } catch {
            guard isCurrent(code: code, mode: mode) else { return }
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

    /// Fetches the board again. A busy station changes every few seconds,
    /// so changes that arrive while a refresh is running are folded into
    /// one more refresh after it, not one each.
    func refresh() async {
        if isRefreshing {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            guard let code = currentStationCode else { return }
            let mode = mode
            do {
                let freshBoard = try await fetchBoard(code: code, mode: mode)
                guard isCurrent(code: code, mode: mode) else { return }
                board = freshBoard
                isCachedData = false
                Task { await Self.cacheBoard(freshBoard, code: code, mode: mode) }
            } catch {
                // Keep existing board on refresh failure
            }
        } while refreshAgain
    }

    private func fetchBoard(code: String, mode: BoardMode) async throws -> Board {
        switch mode {
        case .departures:
            try await apiClient.departures(for: code)
        case .arrivals:
            try await apiClient.arrivals(for: code)
        }
    }

    private func isCurrent(code: String, mode: BoardMode) -> Bool {
        currentStationCode == code && self.mode == mode
    }

    // MARK: - Cache

    private nonisolated static let cacheDirectory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DepartureBoards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private nonisolated static func cacheKey(code: String, mode: BoardMode) -> String {
        "\(code)_\(mode.rawValue)"
    }

    /// Saved off the main thread, like loading.
    @concurrent
    private nonisolated static func cacheBoard(_ board: Board, code: String, mode: BoardMode) async {
        let url = cacheDirectory.appendingPathComponent("\(cacheKey(code: code, mode: mode)).json")
        do {
            let data = try JSONEncoder().encode(board)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.boards.error("Failed to cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    @concurrent
    private nonisolated static func loadCachedBoard(code: String, mode: BoardMode) async -> Board? {
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
