import Foundation
import Security

// Compiled into both the app and the widgets extension, so both talk to the
// server chosen in Settings → Server.

/// A trackside server and the API key it needs, if any.
nonisolated struct ServerConnection: Equatable, Sendable {
    let baseURL: URL
    let apiKey: String?

    init(baseURL: URL, apiKey: String?) {
        self.baseURL = baseURL
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.apiKey = key.isEmpty ? nil : key
    }

    /// Parses an address as typed: `trains.example.com`,
    /// `https://trains.example.com/` or `http://192.168.1.10:8080`.
    /// Without a scheme, https is assumed.
    init?(address: String, apiKey: String?) {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        if !components.path.hasSuffix("/") { components.path += "/" }
        guard let url = components.url else { return nil }
        self.init(baseURL: url, apiKey: apiKey)
    }

    /// The live updates WebSocket.
    var webSocketURL: URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/live"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "http" ? "ws" : "wss"
        return components.url!
    }

    /// The server's address as people write it, for display.
    var displayName: String {
        var name = baseURL.host() ?? baseURL.absoluteString
        if let port = baseURL.port { name += ":\(port)" }
        return baseURL.scheme == "http" ? "http://" + name : name
    }

    /// Adds the API key to a request, if this server has one.
    func authorize(_ request: inout URLRequest) {
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    /// A request for `path` (relative, e.g. `v1/locations`) with the API key.
    func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        authorize(&request)
        return request
    }
}

/// Where the chosen server is kept: the address in the App Group's defaults,
/// the key in the keychain, shared with the widgets through the same group.
nonisolated enum ServerSettings {
    /// Posted after the server changes.
    static let didChange = Notification.Name("TrackSideServerDidChange")

    private static let addressKey = "serverAddress"
    private static let keychainService = "trackside-api-key"

    /// The App Group, `group.<bundle prefix>.TrackSideIOS`, from Info.plist.
    private static var appGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "TrackSideAppGroup") as? String
    }

    private static var defaults: UserDefaults {
        appGroup.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The server to use, or nil until one has been set up.
    static var current: ServerConnection? {
        guard let address = defaults.string(forKey: addressKey),
              let url = URL(string: address)
        else { return nil }
        return ServerConnection(baseURL: url, apiKey: readKey())
    }

    static func save(_ server: ServerConnection) {
        defaults.set(server.baseURL.absoluteString, forKey: addressKey)
        writeKey(server.apiKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: - Keychain

    private static func query() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        if let appGroup { query[kSecAttrAccessGroup as String] = appGroup }
        return query
    }

    private static func readKey() -> String? {
        var query = query()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKey(_ key: String?) {
        SecItemDelete(query() as CFDictionary)
        guard let key, let data = key.data(using: .utf8) else { return }
        var item = query()
        item[kSecValueData as String] = data
        // Widgets and background refreshes run while the phone is locked.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            print("[ServerSettings] Saving the API key failed: \(status)")
        }
    }
}
