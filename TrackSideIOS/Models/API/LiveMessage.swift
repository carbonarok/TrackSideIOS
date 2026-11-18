import Foundation

/// Messages received over the WebSocket connection
nonisolated struct LiveMessage: Codable, Sendable {
    let type: String
    let topics: [String]?
    let fallback: Int?
    let message: String?
}
