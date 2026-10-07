import Foundation

enum ServiceStatus: String, Codable, Sendable {
    case scheduled
    case activated
    case running
    case terminated
    case cancelled
    case partiallyCancelled = "partially_cancelled"
}

/// Summary of a service, used in boards and search results
struct ServiceSummary: Codable, Sendable, Hashable, Identifiable {
    let uid: String
    let runDate: String
    let headcode: String?
    let `operator`: TrainOperator?
    let isPassenger: Bool
    let status: ServiceStatus
    let origin: [Endpoint]
    let destination: [Endpoint]
    let cancelReasonCode: String?
    let cancelReasonCodeDescription: String?
    let cancelReason: String?
    let lateReason: String?
    let plannedCancel: Bool

    var id: String { "\(uid)|\(runDate)" }

    var originName: String {
        origin.first?.name ?? "Unknown"
    }

    var destinationName: String {
        destination.first?.name ?? "Unknown"
    }

    var isCancelled: Bool {
        status == .cancelled || status == .partiallyCancelled || plannedCancel
    }
}

/// A service on a departure/arrival board (ServiceSummary fields flattened + stop)
struct BoardService: Codable, Sendable, Hashable, Identifiable {
    let uid: String
    let runDate: String
    let headcode: String?
    let `operator`: TrainOperator?
    let isPassenger: Bool
    let status: ServiceStatus
    let origin: [Endpoint]
    let destination: [Endpoint]
    let cancelReasonCode: String?
    let cancelReasonCodeDescription: String?
    let cancelReason: String?
    let lateReason: String?
    let plannedCancel: Bool
    let stop: Stop

    var id: String { "\(uid)|\(runDate)" }

    var originName: String {
        origin.first?.name ?? "Unknown"
    }

    var destinationName: String {
        destination.first?.name ?? "Unknown"
    }

    var isCancelled: Bool {
        status == .cancelled || status == .partiallyCancelled || plannedCancel
    }
}

/// Train Describer position
struct Position: Codable, Sendable, Hashable {
    let tdArea: String
    let berth: String
    let at: String
}

/// Association between services (join/divide/next working)
struct Association: Codable, Sendable, Hashable {
    let type: String
    let category: String
    let location: Location
    let cancelled: Bool
    let service: ServiceSummary
}

/// Full detail of a service including all stops
struct ServiceDetail: Codable, Sendable, Hashable, Identifiable {
    let uid: String
    let runDate: String
    let headcode: String?
    let `operator`: TrainOperator?
    let isPassenger: Bool
    let status: ServiceStatus
    let origin: [Endpoint]
    let destination: [Endpoint]
    let cancelReasonCode: String?
    let cancelReasonCodeDescription: String?
    let cancelReason: String?
    let lateReason: String?
    let plannedCancel: Bool
    let trainClass: String?
    let powerType: String?
    let category: String?
    let source: String
    let position: Position?
    let associations: [Association]?
    let stops: [Stop]

    var id: String { "\(uid)|\(runDate)" }

    var originName: String {
        origin.first?.name ?? "Unknown"
    }

    var destinationName: String {
        destination.first?.name ?? "Unknown"
    }

    var isCancelled: Bool {
        status == .cancelled || status == .partiallyCancelled || plannedCancel
    }
}

/// Response wrapper for service search
struct ServiceSearchResponse: Codable, Sendable {
    let services: [ServiceSummary]
}
