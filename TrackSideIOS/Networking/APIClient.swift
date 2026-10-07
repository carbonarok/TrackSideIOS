import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, message: String)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
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
    let baseURL: URL

    init(baseURL: URL = AppConfig.baseURL) {
        self.baseURL = baseURL
    }

    // MARK: - Locations

    func searchLocations(query: String) async throws -> [Location] {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/locations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let response: LocationSearchResponse = try await fetch(from: components.url!)
        return response.locations
    }

    // MARK: - Departures

    func departures(
        for code: String,
        to: String? = nil,
        at: String? = nil,
        window: Int? = nil
    ) async throws -> Board {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/locations/\(code)/departures"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = []
        if let to { items.append(.init(name: "to", value: to)) }
        if let at { items.append(.init(name: "at", value: at)) }
        if let window { items.append(.init(name: "window", value: "\(window)")) }
        if !items.isEmpty { components.queryItems = items }
        return try await fetch(from: components.url!)
    }

    // MARK: - Arrivals

    func arrivals(
        for code: String,
        from: String? = nil,
        at: String? = nil,
        window: Int? = nil
    ) async throws -> Board {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/locations/\(code)/arrivals"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = []
        if let from { items.append(.init(name: "from", value: from)) }
        if let at { items.append(.init(name: "at", value: at)) }
        if let window { items.append(.init(name: "window", value: "\(window)")) }
        if !items.isEmpty { components.queryItems = items }
        return try await fetch(from: components.url!)
    }

    // MARK: - Services

    func serviceDetail(uid: String, date: String) async throws -> ServiceDetail {
        let url = baseURL.appendingPathComponent("v1/services/\(uid)/\(date)")
        return try await fetch(from: url)
    }

    func searchServices(query: String, date: String? = nil) async throws -> [ServiceSummary] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/services"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = [.init(name: "q", value: query)]
        if let date { items.append(.init(name: "date", value: date)) }
        components.queryItems = items
        let response: ServiceSearchResponse = try await fetch(from: components.url!)
        return response.services
    }

    // MARK: - Activity Registration (APNs)

    /// Register a Live Activity's push token with the backend.
    /// Returns the HTTP status code. Non-throwing for 503 (no APNs key configured).
    @discardableResult
    func registerActivity(body: [String: Any]) async -> Int {
        let url = baseURL.appendingPathComponent("v1/activities/register")
        do {
            let (_, response) = try await jsonPost(to: url, body: body)
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
        let url = baseURL.appendingPathComponent("v1/activities/\(activityID)")
        do {
            let (_, response) = try await jsonDelete(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[APIClient] DELETE /v1/activities/\(activityID) → \(code)")
        } catch {
            print("[APIClient] deregisterActivity failed: \(error)")
        }
    }

    // MARK: - Generic Fetch

    private func fetch<T: Decodable>(from url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
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

    private func jsonPost(to url: URL, body: [String: Any]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await URLSession.shared.data(for: request)
    }

    private func jsonDelete(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        return try await URLSession.shared.data(for: request)
    }
}
