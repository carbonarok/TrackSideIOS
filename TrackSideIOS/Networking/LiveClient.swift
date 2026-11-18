import Foundation
import os

/// WebSocket client for live change notifications.
/// Subscribes to topics and notifies registered handlers when data changes.
/// Handlers should refetch data via the REST API when notified.
actor LiveClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private var subscribedTopics: Set<String> = []
    private var handlers: [UUID: @Sendable (Set<String>) -> Void] = [:]
    private var isConnected = false
    private var reconnectTask: Task<Void, Never>?
    /// Generation counter to prevent stale receive loops from triggering reconnects
    /// after the connection has already been replaced.
    private var connectionGeneration: Int = 0
    /// One session for every connection; a new one each reconnect was never
    /// released.
    private let session = URLSession(configuration: .default)
    /// Failed connections in a row, for backing off.
    private var reconnectAttempts = 0
    private var pingTask: Task<Void, Never>?
    /// Often enough to keep proxies such as Cloudflare (100 s idle limit)
    /// from closing a quiet connection, and to notice a dead one.
    static let pingInterval: Duration = .seconds(25)

    /// Register a handler that is called when subscribed topics change.
    /// Returns an ID to remove the handler later.
    func onChange(_ handler: @escaping @Sendable (Set<String>) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func removeHandler(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    /// Connect if not already connected.
    func connect() {
        guard webSocketTask == nil else { return }
        establishConnection()
    }

    /// Disconnect and clean up.
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        connectionGeneration += 1
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    /// Force a fresh connection, dropping any existing one.
    /// Use this when the app returns to foreground and the old connection may be dead.
    func ensureConnected() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        connectionGeneration += 1
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        establishConnection()
    }

    func subscribe(to topics: [String]) {
        for topic in topics {
            subscribedTopics.insert(topic)
        }
        sendMessage(type: "subscribe", topics: topics)
    }

    func subscribe(to topic: String) {
        subscribe(to: [topic])
    }

    func unsubscribe(from topics: [String]) {
        for topic in topics {
            subscribedTopics.remove(topic)
        }
        sendMessage(type: "unsubscribe", topics: topics)
    }

    func unsubscribe(from topic: String) {
        unsubscribe(from: [topic])
    }

    // MARK: - Private

    /// Create a new WebSocket connection to the server set in Settings, start
    /// the receive loop, and re-subscribe all topics.
    private func establishConnection() {
        guard let server = ServerSettings.current else {
            Log.live.info("No server set up yet")
            return
        }
        connectionGeneration += 1
        let gen = connectionGeneration
        var request = URLRequest(url: server.webSocketURL)
        server.authorize(&request)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        Log.live.info("Connecting (generation \(String(describing: gen), privacy: .public)) to \(String(describing: server.webSocketURL), privacy: .private)")
        Task { await receiveLoop(generation: gen) }
        startPinging(generation: gen)

        // Re-subscribe any previously tracked topics
        if !subscribedTopics.isEmpty {
            Log.live.info("Re-subscribing \(String(describing: self.subscribedTopics.count), privacy: .public) topic(s)")
            sendMessage(type: "subscribe", topics: Array(subscribedTopics))
        }
    }

    private func sendMessage(type: String, topics: [String]) {
        guard let task = webSocketTask else {
            Log.live.info("Cannot send \(String(describing: type), privacy: .public) — not connected")
            return
        }
        let payload: [String: Any] = ["type": type, "topics": topics]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        Log.live.debug("Sending \(String(describing: type), privacy: .public) for \(String(describing: topics.count), privacy: .public) topic(s): \(String(describing: topics.joined(separator: ", ")), privacy: .public)")
        task.send(.string(string)) { error in
            if let error {
                Log.live.error("Send error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func receiveLoop(generation: Int) async {
        guard let task = webSocketTask, generation == connectionGeneration else { return }
        do {
            let message = try await task.receive()
            // Check generation again — connection may have been replaced while we were waiting
            guard generation == connectionGeneration else { return }
            // Hearing from the server means the connection works.
            reconnectAttempts = 0
            switch message {
            case .string(let text):
                handleText(text)
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    handleText(text)
                }
            @unknown default:
                break
            }
            await receiveLoop(generation: generation)
        } catch {
            // Only reconnect if this is still the active generation
            guard generation == connectionGeneration else {
                Log.live.info("Stale receive loop (gen \(String(describing: generation), privacy: .public)) ended, ignoring")
                return
            }
            Log.live.error("Receive error (gen \(String(describing: generation), privacy: .public)): \(error.localizedDescription, privacy: .public)")
            handleReconnect()
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "hello":
            let fallback = json["fallback"] as? Int ?? 120
            Log.live.info("Connected, fallback: \(String(describing: fallback), privacy: .public)s")
        case "changed":
            if let topics = json["topics"] as? [String] {
                Log.live.debug("Changed: \(String(describing: topics.joined(separator: ", ")), privacy: .public) — notifying \(String(describing: self.handlers.count), privacy: .public) handler(s)")
                let topicSet = Set(topics)
                for handler in handlers.values {
                    handler(topicSet)
                }
            }
        case "error":
            let message = json["message"] as? String ?? "unknown"
            Log.live.error("Server error: \(String(describing: message), privacy: .public)")
        default:
            break
        }
    }

    /// Reconnects after a wait that doubles with each failure in a row, up
    /// to 30 seconds, so a phone in a tunnel isn't trying every 3 seconds.
    /// The wait varies a little so clients don't all return at once after
    /// a server restart.
    private func handleReconnect() {
        webSocketTask = nil
        isConnected = false
        pingTask?.cancel()
        pingTask = nil
        reconnectTask?.cancel()
        let delay = min(30, pow(2, Double(reconnectAttempts))) * Double.random(in: 0.8...1.2)
        reconnectAttempts += 1
        reconnectTask = Task {
            Log.live.info("Reconnecting in \(delay, format: .fixed(precision: 1), privacy: .public) s (attempt \(self.reconnectAttempts, privacy: .public))")
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            establishConnection()
        }
    }

    private func startPinging(generation: Int) {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pingInterval)
                guard !Task.isCancelled else { return }
                await ping(generation: generation)
            }
        }
    }

    /// A ping without an answer means the connection is dead even though
    /// nothing has said so; closing it starts a reconnect.
    private func ping(generation: Int) async {
        guard let task = webSocketTask, generation == connectionGeneration else { return }
        let error: Error? = await withCheckedContinuation { continuation in
            task.sendPing { continuation.resume(returning: $0) }
        }
        guard let error, generation == connectionGeneration else { return }
        Log.live.error("Ping failed: \(error.localizedDescription, privacy: .public)")
        task.cancel(with: .goingAway, reason: nil)
    }
}
