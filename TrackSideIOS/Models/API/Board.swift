import Foundation

/// Darwin station message
struct StationMessage: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    let category: String
    let severity: Int
    let text: String
    let html: String
    let updatedAt: String
}

/// A departure or arrival board for a station
struct Board: Codable, Sendable {
    let location: Location
    let from: String
    let to: String
    let messages: [StationMessage]
    let services: [BoardService]
}
