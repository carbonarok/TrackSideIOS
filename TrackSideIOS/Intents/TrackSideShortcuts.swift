import AppIntents
import Foundation

// MARK: - Station Entity

struct StationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Station"
    static var defaultQuery = StationEntityQuery()

    var id: String  // CRS code
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

struct StationEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [StationEntity] {
        // Return entities for known identifiers
        identifiers.map { StationEntity(id: $0, name: $0) }
    }

    func entities(matching string: String) async throws -> [StationEntity] {
        let client = APIClient()
        let locations = try await client.searchLocations(query: string)
        return locations.compactMap { loc in
            guard let crs = loc.crs else { return nil }
            return StationEntity(id: crs, name: loc.name)
        }
    }

    func suggestedEntities() async throws -> [StationEntity] {
        // Common UK stations
        [
            StationEntity(id: "WAT", name: "London Waterloo"),
            StationEntity(id: "PAD", name: "London Paddington"),
            StationEntity(id: "VIC", name: "London Victoria"),
            StationEntity(id: "KGX", name: "London King's Cross"),
            StationEntity(id: "EUS", name: "London Euston"),
            StationEntity(id: "LBG", name: "London Bridge"),
            StationEntity(id: "BHM", name: "Birmingham New Street"),
            StationEntity(id: "MAN", name: "Manchester Piccadilly"),
            StationEntity(id: "LDS", name: "Leeds"),
            StationEntity(id: "EDB", name: "Edinburgh Waverley"),
        ]
    }
}

// MARK: - Next Departure Intent

struct NextDepartureIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Train"
    static var description: IntentDescription = "Get the next departure from a station"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Station")
    var station: StationEntity

    @Parameter(title: "Destination (optional)", description: "Filter by destination station code")
    var destinationCode: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let code = station.id
        let client = APIClient()

        let board = try await client.departures(for: code, to: destinationCode)

        guard let first = board.services.first else {
            return .result(dialog: "No departures found from \(board.location.name)")
        }

        let destination = first.destination.first?.name ?? "Unknown"
        let headcode = first.headcode ?? "????"
        let time = first.stop.departure?.public ?? first.stop.departure?.working ?? "unknown time"
        let platform = first.stop.platform?.displayPlatform
        let delay = first.stop.departure?.delayMinutes ?? 0
        let operatorName = first.operator?.name ?? ""

        var response = "Next train from \(board.location.name): \(headcode) to \(destination)"

        if let formattedTime = formatTime(time) {
            response += " at \(formattedTime)"
        }

        if let plat = platform {
            response += ", Platform \(plat)"
        }

        if first.isCancelled {
            response += ". This service is CANCELLED"
            if let reason = first.cancelReason {
                response += " — \(reason)"
            }
        } else if delay > 0 {
            response += ". Running \(delay) minutes late"
        } else {
            response += ". On time"
        }

        if !operatorName.isEmpty {
            response += ". Operated by \(operatorName)"
        }

        return .result(dialog: "\(response)")
    }

    private func formatTime(_ isoString: String) -> String? {
        if let tIndex = isoString.firstIndex(of: "T") {
            let timeStr = isoString[isoString.index(after: tIndex)...]
            if timeStr.count >= 5 {
                return String(timeStr.prefix(5))
            }
        }
        if isoString.count == 5 && isoString.contains(":") {
            return isoString
        }
        return nil
    }
}

// MARK: - Show Departures Intent (opens app)

struct ShowDeparturesIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Departures"
    static var description: IntentDescription = "Open the departure board for a station"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Station")
    var station: StationEntity

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Check Delays Intent

struct CheckDelaysIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Delays"
    static var description: IntentDescription = "Check if there are delays at a station"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Station")
    var station: StationEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let code = station.id
        let client = APIClient()
        let board = try await client.departures(for: code)

        let delayed = board.services.filter { svc in
            let delay = svc.stop.departure?.delayMinutes ?? 0
            return delay > 0 || svc.isCancelled
        }

        let total = board.services.count
        let cancelledCount = board.services.filter(\.isCancelled).count
        let delayedCount = delayed.count - cancelledCount

        if delayed.isEmpty {
            return .result(dialog: "All \(total) services from \(board.location.name) are running on time.")
        }

        var response = "\(board.location.name): "
        var parts: [String] = []
        if cancelledCount > 0 {
            parts.append("\(cancelledCount) cancelled")
        }
        if delayedCount > 0 {
            parts.append("\(delayedCount) delayed")
        }
        response += parts.joined(separator: ", ")
        response += " out of \(total) services"

        if let worstDelay = board.services.compactMap({ $0.stop.departure?.delayMinutes }).max(), worstDelay > 0 {
            response += ". Worst delay: \(worstDelay) minutes"
        }

        if !board.messages.isEmpty {
            response += ". Station message: \(board.messages.first!.text)"
        }

        return .result(dialog: "\(response)")
    }
}

// MARK: - Shortcuts Provider

struct TrackSideShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextDepartureIntent(),
            phrases: [
                "Next train from \(\.$station) in \(.applicationName)",
                "Next departure from \(\.$station) with \(.applicationName)",
                "When is the next train from \(\.$station) in \(.applicationName)"
            ],
            shortTitle: "Next Train",
            systemImageName: "tram.fill"
        )

        AppShortcut(
            intent: CheckDelaysIntent(),
            phrases: [
                "Check delays at \(\.$station) in \(.applicationName)",
                "Are there delays at \(\.$station) with \(.applicationName)",
                "Any disruptions at \(\.$station) in \(.applicationName)"
            ],
            shortTitle: "Check Delays",
            systemImageName: "exclamationmark.triangle"
        )

        AppShortcut(
            intent: ShowDeparturesIntent(),
            phrases: [
                "Show departures from \(\.$station) in \(.applicationName)",
                "Open \(.applicationName) departures for \(\.$station)"
            ],
            shortTitle: "Show Departures",
            systemImageName: "list.bullet"
        )
    }
}
