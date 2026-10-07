import Foundation

/// WebSocket client for live change notifications.
/// Subscribes to topics and notifies registered handlers when data changes.
/// Handlers should refetch data via the REST API when notified.
actor LiveClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let url: URL
    private var subscribedTopics: Set<String> = []
    private var handlers: [UUID: @Sendable (Set<String>) -> Void] = [:]
    private var isConnected = false
    private var reconnectTask: Task<Void, Never>?
    /// Generation counter to prevent stale receive loops from triggering reconnects
    /// after the connection has already been replaced.
    private var connectionGeneration: Int = 0

    init(url: URL) {
        self.url = url
    }

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

    /// Create a new WebSocket connection, start the receive loop, and re-subscribe all topics.
    private func establishConnection() {
        connectionGeneration += 1
        let gen = connectionGeneration
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        print("[LiveClient] Connecting (generation \(gen)) to \(url)")
        Task { await receiveLoop(generation: gen) }

        // Re-subscribe any previously tracked topics
        if !subscribedTopics.isEmpty {
            print("[LiveClient] Re-subscribing \(subscribedTopics.count) topic(s)")
            sendMessage(type: "subscribe", topics: Array(subscribedTopics))
        }
    }

    private func sendMessage(type: String, topics: [String]) {
        guard let task = webSocketTask else {
            print("[LiveClient] Cannot send \(type) — not connected")
            return
        }
        let payload: [String: Any] = ["type": type, "topics": topics]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        print("[LiveClient] Sending \(type) for \(topics.count) topic(s): \(topics.joined(separator: ", "))")
        task.send(.string(string)) { error in
            if let error {
                print("[LiveClient] Send error: \(error)")
            }
        }
    }

    private func receiveLoop(generation: Int) async {
        guard let task = webSocketTask, generation == connectionGeneration else { return }
        do {
            let message = try await task.receive()
            // Check generation again — connection may have been replaced while we were waiting
            guard generation == connectionGeneration else { return }
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
                print("[LiveClient] Stale receive loop (gen \(generation)) ended, ignoring")
                return
            }
            print("[LiveClient] Receive error (gen \(generation)): \(error)")
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
            print("[LiveClient] Connected, fallback: \(fallback)s")
        case "changed":
            if let topics = json["topics"] as? [String] {
                print("[LiveClient] Changed: \(topics.joined(separator: ", ")) — notifying \(handlers.count) handler(s)")
                let topicSet = Set(topics)
                for handler in handlers.values {
                    handler(topicSet)
                }
            }
        case "error":
            let message = json["message"] as? String ?? "unknown"
            print("[LiveClient] Server error: \(message)")
        default:
            break
        }
    }

    private func handleReconnect() {
        webSocketTask = nil
        isConnected = false
        reconnectTask?.cancel()
        reconnectTask = Task {
            print("[LiveClient] Reconnecting in 3 seconds...")
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            establishConnection()
        }
    }
}
