import Foundation

enum StopKind: String, Codable, Sendable {
    case origin
    case call
    case pass
    case destination
    case stop
}

struct Times: Codable, Sendable, Hashable {
    let `public`: String?
    let working: String?
    let actual: String?
    let estimated: String?
    let delayMinutes: Int?
    let delayed: Bool?
    let cancelled: Bool?

    /// Best available time: actual > estimated > public > working
    var bestTime: String? {
        actual ?? estimated ?? `public` ?? working
    }

    var isLate: Bool {
        if let delay = delayMinutes, delay > 0 { return true }
        return delayed ?? false
    }
}

struct Platform: Codable, Sendable, Hashable {
    let planned: String?
    let actual: String?
    let changed: Bool
    let confirmed: Bool
    let suppressed: Bool?

    var displayPlatform: String? {
        actual ?? planned
    }
}

/// A calling point. Location fields are flattened (OpenAPI allOf).
struct Stop: Codable, Sendable, Hashable, Identifiable {
    let tiploc: String
    let crs: String?
    let name: String
    let kind: StopKind
    let arrival: Times?
    let departure: Times?
    let pass: Times?
    let platform: Platform?
    let cancelled: Bool
    let startsHere: Bool?
    let atPlatform: Bool?
    let approaching: Bool?
    let terminatesHere: Bool?
    let line: String?
    let path: String?

    var id: String { tiploc }
    var displayCode: String { crs ?? tiploc }
}
