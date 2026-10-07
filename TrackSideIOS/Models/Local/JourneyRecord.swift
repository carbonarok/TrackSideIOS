import Foundation
import SwiftData

/// A record of a completed tracked journey for history
@Model
final class JourneyRecord {
    var routeName: String
    var originName: String
    var destinationName: String
    var scheduledDeparture: Date?
    var actualDeparture: Date?
    var scheduledArrival: Date?
    var actualArrival: Date?
    var totalLegs: Int
    var maxDelayMinutes: Int
    var wasCancelled: Bool
    var completedAt: Date
    /// Leg summaries stored as JSON string
    var legSummariesJSON: String?

    init(
        routeName: String,
        originName: String,
        destinationName: String,
        scheduledDeparture: Date? = nil,
        actualDeparture: Date? = nil,
        scheduledArrival: Date? = nil,
        actualArrival: Date? = nil,
        totalLegs: Int = 1,
        maxDelayMinutes: Int = 0,
        wasCancelled: Bool = false,
        legSummaries: [LegSummary] = []
    ) {
        self.routeName = routeName
        self.originName = originName
        self.destinationName = destinationName
        self.scheduledDeparture = scheduledDeparture
        self.actualDeparture = actualDeparture
        self.scheduledArrival = scheduledArrival
        self.actualArrival = actualArrival
        self.totalLegs = totalLegs
        self.maxDelayMinutes = maxDelayMinutes
        self.wasCancelled = wasCancelled
        self.completedAt = .now
        self.legSummariesJSON = {
            guard let data = try? JSONEncoder().encode(legSummaries) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
    }

    var legSummaries: [LegSummary] {
        guard let json = legSummariesJSON,
              let data = json.data(using: .utf8),
              let summaries = try? JSONDecoder().decode([LegSummary].self, from: data) else { return [] }
        return summaries
    }
}

struct LegSummary: Codable {
    let headcode: String
    let operatorName: String
    let originName: String
    let destinationName: String
    let delayMinutes: Int
    let cancelled: Bool
}
