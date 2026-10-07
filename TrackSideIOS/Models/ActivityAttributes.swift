import Foundation
import ActivityKit

/// Attributes for journey tracking Live Activities (multi-leg)
struct JourneyActivityAttributes: ActivityAttributes {
    let routeName: String
    let originName: String
    let finalDestinationName: String
    let totalLegs: Int
    let operatorNames: [String]     // operator per leg

    // Display preferences (set once when activity starts)
    let showCountdown: Bool
    let showNextConnection: Bool
    let showProgressBar: Bool
    let showOperatorName: Bool
    let showPlatformBadge: Bool
    let showDelayBadge: Bool
    let showFinalArrival: Bool

    struct ContentState: Codable, Hashable {
        let currentLegIndex: Int
        let phase: String               // "boarding", "onTrain", "connection", "arrived"
        let headcode: String             // "2V40"
        let statusHeadline: String       // "Board 2V40 at Platform 2"
        let statusDetail: String?        // "Arriving 14:32 (+5 min late)"
        let nextAction: String?          // "Change at Clapham Jcn — 12 min"
        let nextConnectionInfo: String?  // "Then: 1A23 GWR to Bristol Temple Meads"
        let currentLegArrivalTime: String? // "10:42" — arrival time for THIS leg
        let finalArrivalExpected: String?  // "14:55" — for the whole journey
        let departureDate: Date?         // For countdown timer
        let arrivalDate: Date?           // For countdown to arrival
        let departureDelayMinutes: Int   // Delay at departure
        let arrivalDelayMinutes: Int     // Delay at arrival/destination
        let overallDelayMinutes: Int     // Max across remaining legs
        let departurePlatform: String?   // Platform at current leg's origin
        let departurePlatformChanged: Bool
        let arrivalPlatform: String?     // Platform at current leg's destination
        let arrivalPlatformChanged: Bool
        let hasIssues: Bool
        let legCompletionStatus: [Bool]  // Per-leg completion for progress bar
        let lastUpdated: Date
    }
}

/// Attributes for per-leg Live Activities (one activity per leg in a journey)
struct LegActivityAttributes: ActivityAttributes {
    let legIndex: Int
    let totalLegs: Int
    let headcode: String
    let originName: String
    let destinationName: String
    let operatorName: String

    struct ContentState: Codable, Hashable {
        let phase: String               // "upcoming", "boarding", "onTrain", "arrived"
        let departurePlatform: String?
        let departurePlatformChanged: Bool
        let arrivalPlatform: String?
        let arrivalPlatformChanged: Bool
        let scheduledDeparture: String?  // "09:42"
        let expectedDeparture: String?   // "09:50" (if delayed)
        let scheduledArrival: String?    // "10:15"
        let expectedArrival: String?     // "10:23" (if delayed)
        let departureDate: Date?         // For live countdown
        let arrivalDate: Date?           // For live countdown
        let departureDelayMinutes: Int
        let arrivalDelayMinutes: Int
        let isCancelled: Bool
        let cancelReason: String?
        let connectionMinutes: Int?      // Minutes to catch this train (from previous leg arrival)
        let lastUpdated: Date
    }
}

/// Attributes for single train tracking Live Activities
struct TrainActivityAttributes: ActivityAttributes {
    let headcode: String
    let originName: String
    let destinationName: String
    let operatorName: String
    let uid: String
    let runDate: String

    struct ContentState: Codable, Hashable {
        let currentStopName: String
        let nextStopName: String?
        let scheduledArrival: String?
        let expectedArrival: String?
        let delayMinutes: Int
        let platformAtDestination: String?
        let platformChanged: Bool
        let status: String
        let atPlatform: Bool
        let approaching: Bool
        let lastUpdated: Date
    }
}
