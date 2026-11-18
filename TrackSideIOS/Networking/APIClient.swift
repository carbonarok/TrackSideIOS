import Foundation
import os

nonisolated enum APIError: Error, LocalizedError {
    case invalidURL
    case notConfigured
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .notConfigured:
            return "No server set up. Add one in Settings → Server."
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .decodingError(let detail):
            return "Decoding error: \(detail)"
        case .networkError(let detail):
            return detail
        }
    }
}

struct APIClient {
    /// A fixed server, or nil for whichever is set in Settings at the time
    /// of each request.
    private let fixedServer: ServerConnection?

    init(server: ServerConnection? = nil) {
        self.fixedServer = server
    }

    private func server() throws -> ServerConnection {
        if let fixedServer { return fixedServer }
        guard let current = ServerSettings.current else { throw APIError.notConfigured }
        return current
    }

    // MARK: - Locations

    func searchLocations(query: String) async throws -> [Location] {
        let request = try server().request("v1/locations", query: [URLQueryItem(name: "q", value: query)])
        let response: LocationSearchResponse = try await fetch(request)
        return response.locations
    }

    // MARK: - Departures

    func departures(
        for code: String,
        to: String? = nil,
        at: String? = nil,
        window: Int? = nil
    ) async throws -> Board {
        var items: [URLQueryItem] = []
        if let to { items.append(.init(name: "to", value: to)) }
        if let at { items.append(.init(name: "at", value: at)) }
        if let window { items.append(.init(name: "window", value: "\(window)")) }
        return try await fetch(server().request("v1/locations/\(code)/departures", query: items))
    }

    // MARK: - Arrivals

    func arrivals(
        for code: String,
        from: String? = nil,
        at: String? = nil,
        window: Int? = nil
    ) async throws -> Board {
        var items: [URLQueryItem] = []
        if let from { items.append(.init(name: "from", value: from)) }
        if let at { items.append(.init(name: "at", value: at)) }
        if let window { items.append(.init(name: "window", value: "\(window)")) }
        return try await fetch(server().request("v1/locations/\(code)/arrivals", query: items))
    }

    // MARK: - Services

    func serviceDetail(uid: String, date: String) async throws -> ServiceDetail {
        try await fetch(server().request("v1/services/\(uid)/\(date)"))
    }

    func searchServices(query: String, date: String? = nil) async throws -> [ServiceSummary] {
        var items: [URLQueryItem] = [.init(name: "q", value: query)]
        if let date { items.append(.init(name: "date", value: date)) }
        let response: ServiceSearchResponse = try await fetch(server().request("v1/services", query: items))
        return response.services
    }

    // MARK: - Activity Registration (APNs)

    /// Register a Live Activity's push token with the backend.
    /// Returns the HTTP status code. Non-throwing for 503 (no APNs key configured).
    @discardableResult
    func registerActivity(body: [String: Any]) async -> Int {
        do {
            var request = try server().request("v1/activities/register")
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await Self.session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            Log.network.info("POST /v1/activities/register → \(String(describing: code), privacy: .public)")
            return code
        } catch {
            Log.network.error("registerActivity failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Deregister a Live Activity.
    func deregisterActivity(activityID: String) async {
        do {
            var request = try server().request("v1/activities/\(activityID)")
            request.httpMethod = "DELETE"
            let (_, response) = try await Self.session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            Log.network.info("DELETE /v1/activities/\(String(describing: activityID), privacy: .public) → \(String(describing: code), privacy: .public)")
        } catch {
            Log.network.error("deregisterActivity failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Generic Fetch

    /// Gives up on a request after 15 seconds without data, not the
    /// default 60, so a dead connection on a train shows an error rather
    /// than a spinner for a minute.
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    /// Waits before each retry of a request that failed in passing.
    private nonisolated static let retryDelays: [Duration] = [.milliseconds(500), .milliseconds(1500)]

    /// Fetches and decodes off the main thread. A busy board is tens of
    /// kilobytes of JSON and refreshes every few seconds; decoding it on the
    /// main thread makes scrolling stutter.
    ///
    /// Every fetch is a GET, so one that fails in passing (a dropped
    /// connection, a gateway error while the server restarts) is tried
    /// again, twice.
    @concurrent
    private nonisolated static func fetch<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await fetchOnce(request)
            } catch where attempt < retryDelays.count && isTransient(error) && !Task.isCancelled {
                Log.network.info("Retrying \(request.url?.path ?? "", privacy: .public) after: \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(for: retryDelays[attempt])
                attempt += 1
            }
        }
    }

    private nonisolated static func fetchOnce<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: http.statusCode, message: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Whether trying again soon might work.
    nonisolated static func isTransient(_ error: Error) -> Bool {
        if let apiError = error as? APIError, case .httpError(let status, _) = apiError {
            return [502, 503, 504].contains(status)
        }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func fetch<T: Decodable & Sendable>(_ request: URLRequest) async throws -> T {
        try await Self.fetch(request)
    }
}
