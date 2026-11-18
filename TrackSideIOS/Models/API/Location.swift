import Foundation

nonisolated struct Location: Codable, Sendable, Hashable, Identifiable {
    let tiploc: String
    let crs: String?
    let name: String

    var id: String { crs ?? tiploc }
    var displayCode: String { crs ?? tiploc }
}

/// An origin or destination with a time (allOf Location + time)
nonisolated struct Endpoint: Codable, Sendable, Hashable {
    let tiploc: String
    let crs: String?
    let name: String
    let time: String?
}

nonisolated struct LocationSearchResponse: Codable, Sendable {
    let locations: [Location]
}
