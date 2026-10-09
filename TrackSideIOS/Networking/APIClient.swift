import Foundation

enum APIError: Error, LocalizedError {
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
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[APIClient] POST /v1/activities/register → \(code)")
            return code
        } catch {
            print("[APIClient] registerActivity failed: \(error)")
            return 0
        }
    }

    /// Deregister a Live Activity.
    func deregisterActivity(activityID: String) async {
        do {
            var request = try server().request("v1/activities/\(activityID)")
            request.httpMethod = "DELETE"
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[APIClient] DELETE /v1/activities/\(activityID) → \(code)")
        } catch {
            print("[APIClient] deregisterActivity failed: \(error)")
        }
    }

    // MARK: - Generic Fetch

    private func fetch<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: http.statusCode, message: body)
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}
