import Foundation
import SwiftData

@Model
final class SavedRoute {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \SavedLeg.route)
    var legs: [SavedLeg]

    init(name: String, legs: [SavedLeg] = []) {
        self.name = name
        self.createdAt = .now
        self.legs = legs
    }

    var sortedLegs: [SavedLeg] {
        legs.sorted { $0.order < $1.order }
    }

    /// Create a reversed copy of this route (for return journeys).
    /// Each leg swaps origin/destination and the leg order is reversed.
    /// Departure platform becomes arrival platform and vice versa.
    func reversed() -> SavedRoute {
        let reversedLegs = sortedLegs.reversed().enumerated().map { index, leg in
            SavedLeg(
                order: index,
                originCode: leg.destinationCode ?? "",
                originName: leg.destinationName ?? "",
                destinationCode: leg.originCode,
                destinationName: leg.originName,
                preferredDeparturePlatform: leg.preferredArrivalPlatform,
                preferredArrivalPlatform: leg.preferredDeparturePlatform
            )
        }
        return SavedRoute(name: "\(name) (Return)", legs: reversedLegs)
    }
}

@Model
final class SavedLeg {
    var order: Int
    var originCode: String
    var originName: String
    var destinationCode: String?
    var destinationName: String?
    var preferredDeparturePlatform: String?
    var preferredArrivalPlatform: String?
    var route: SavedRoute?

    init(
        order: Int,
        originCode: String,
        originName: String,
        destinationCode: String? = nil,
        destinationName: String? = nil,
        preferredDeparturePlatform: String? = nil,
        preferredArrivalPlatform: String? = nil
    ) {
        self.order = order
        self.originCode = originCode
        self.originName = originName
        self.destinationCode = destinationCode
        self.destinationName = destinationName
        self.preferredDeparturePlatform = preferredDeparturePlatform
        self.preferredArrivalPlatform = preferredArrivalPlatform
    }
}
