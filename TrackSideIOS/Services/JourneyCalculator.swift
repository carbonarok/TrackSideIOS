import Foundation
import os
import Observation
import os
import CryptoKit

/// A single leg in a calculated journey
nonisolated struct CalculatedLeg: Identifiable, Codable, Sendable {
    var id = UUID()
    let legIndex: Int
    let service: BoardService
    let serviceDetail: ServiceDetail?
    let originName: String
    let destinationName: String
    /// Where this leg is left: the saved leg's station (CRS or TIPLOC). It
    /// can be before the train's terminus, so never use the service's
    /// destination for it.
    let destinationCode: String
    let departureTime: String?
    let arrivalTime: String?
    let departurePlatform: String?
    let arrivalPlatform: String?
    let departureDelay: Int?
    let arrivalDelay: Int?
    let isCancelled: Bool
    /// Minutes waiting at this station before this leg departs (nil for first leg)
    let connectionMinutes: Int?

    /// Find the stop at the destination within the service detail
    static func arrivalStop(in detail: ServiceDetail, destinationCode: String) -> Stop? {
        detail.stops.last { stop in
            stop.crs == destinationCode || stop.tiploc == destinationCode
        }
    }
}

/// A fully calculated journey across all legs of a route
nonisolated struct CalculatedJourney: Identifiable, Codable, Sendable {
    var id = UUID()
    let legs: [CalculatedLeg]
    let departureTime: String?
    let arrivalTime: String?
    let requestedTime: Date

    var totalLegs: Int { legs.count }

    /// The same for the same trains, however many times it's calculated.
    var trainsKey: String {
        legs.map { "\($0.service.uid)|\($0.service.runDate)" }.joined(separator: ">")
    }

    var hasIssues: Bool {
        legs.contains { $0.isCancelled } || legs.isEmpty
    }

    /// Try to compute total journey minutes from first departure to last arrival
    var totalMinutes: Int? {
        guard let first = legs.first?.departureTime,
              let last = legs.last?.arrivalTime else { return nil }
        guard let firstDate = parseTime(first),
              let lastDate = parseTime(last) else { return nil }
        let interval = lastDate.timeIntervalSince(firstDate)
        return max(0, Int(interval / 60))
    }
}

/// One leg of a route, as the calculator needs it. Kept apart from the
/// SwiftData model so the calculator can be tested without a database.
nonisolated struct RouteLegPlan: Sendable, Hashable {
    let originCode: String
    let originName: String
    let destinationCode: String?
    let destinationName: String?
    let departurePlatforms: Set<String>
    let arrivalPlatforms: Set<String>

    init(
        originCode: String,
        originName: String,
        destinationCode: String?,
        destinationName: String?,
        departurePlatforms: Set<String> = [],
        arrivalPlatforms: Set<String> = []
    ) {
        self.originCode = originCode
        self.originName = originName
        self.destinationCode = destinationCode
        self.destinationName = destinationName
        self.departurePlatforms = departurePlatforms
        self.arrivalPlatforms = arrivalPlatforms
    }

    /// "1, 2,3" → ["1", "2", "3"]
    static func platforms(_ value: String?) -> Set<String> {
        guard let value, !value.isEmpty else { return [] }
        return Set(value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}

extension RouteLegPlan {
    @MainActor
    init(_ leg: SavedLeg) {
        self.init(
            originCode: leg.originCode,
            originName: leg.originName,
            destinationCode: leg.destinationCode,
            destinationName: leg.destinationName,
            departurePlatforms: Self.platforms(leg.preferredDeparturePlatform),
            arrivalPlatforms: Self.platforms(leg.preferredArrivalPlatform)
        )
    }
}

/// Why a journey couldn't be found, worded for the person using the app.
nonisolated struct JourneyError: Error {
    let message: String
}

/// Where the calculator gets boards and trains: the server, or a fake in tests.
protocol JourneyDataSource {
    func departures(for code: String, to: String?, at: String?, window: Int?) async throws -> Board
    func serviceDetail(uid: String, date: String) async throws -> ServiceDetail
}

extension APIClient: JourneyDataSource {}

/// What one calculation has fetched, so the journeys it finds share boards
/// and trains instead of asking the server again for each one.
///
/// The first journey's board for a leg usually holds the trains for all the
/// later ones too, and each train's details are fetched once, several at a
/// time.
final class JourneyFetcher {
    struct FetchedBoard {
        let from: Date
        let to: Date
        let services: [BoardService]
    }

    nonisolated static let initialWindowMinutes = 120
    /// Empty boards are followed by longer ones, up to this, so a quiet
    /// night costs a few requests rather than one per two hours.
    nonisolated static let maxWindowMinutes = 720

    private let dataSource: JourneyDataSource
    private var boards: [String: [FetchedBoard]] = [:]
    private var details: [String: Task<ServiceDetail?, Never>] = [:]

    init(dataSource: JourneyDataSource) {
        self.dataSource = dataSource
    }

    /// The board from `origin` to `destination` covering `time`, fetched
    /// only when no earlier fetch covers it.
    func board(
        from origin: String,
        to destination: String,
        covering time: Date,
        windowMinutes: Int = initialWindowMinutes
    ) async throws -> FetchedBoard {
        let key = "\(origin)|\(destination)"
        if let board = boards[key]?.first(where: { $0.from <= time && time < $0.to }) {
            return board
        }
        // The server takes whole minutes.
        let from = Self.wholeMinute(time)
        let board = try await dataSource.departures(
            for: origin,
            to: destination,
            at: Self.formatForAPI(from),
            window: windowMinutes
        )
        let fetched = FetchedBoard(
            from: from,
            to: from.addingTimeInterval(TimeInterval(windowMinutes * 60)),
            services: board.services
        )
        boards[key, default: []].append(fetched)
        return fetched
    }

    /// Starts fetching these trains' details, all at once.
    func prefetchDetails(_ services: some Sequence<BoardService>) {
        for service in services {
            _ = detailTask(service)
        }
    }

    /// A train's details, or nil if they couldn't be fetched.
    func detail(_ service: BoardService) async -> ServiceDetail? {
        await detailTask(service).value
    }

    /// Stops fetches nobody is waiting for any more.
    func cancel() {
        for task in details.values {
            task.cancel()
        }
    }

    private func detailTask(_ service: BoardService) -> Task<ServiceDetail?, Never> {
        let key = "\(service.uid)|\(service.runDate)"
        if let task = details[key] { return task }
        let dataSource = dataSource
        let task = Task {
            try? await dataSource.serviceDetail(uid: service.uid, date: service.runDate)
        }
        details[key] = task
        return task
    }

    /// The start of the minute `date` falls in.
    nonisolated static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    private nonisolated static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        return formatter
    }()

    /// A Date as the API's `at` parameter (UK local time).
    nonisolated static func formatForAPI(_ date: Date) -> String {
        apiFormatter.string(from: date)
    }
}

/// The last journeys found for each route, so a route opens with something
/// on screen straight away, and still shows its journeys with no signal.
nonisolated enum JourneyStore {
    struct Saved: Codable, Sendable {
        let savedAt: Date
        let departAt: Date
        let journeys: [CalculatedJourney]
    }

    /// Saved journeys are only offered for a requested time this close to
    /// the one they were found for.
    static let maxTimeDifference: TimeInterval = 3 * 60 * 60

    private static let directory: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Journeys", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Named after what the route asks for, so identical routes share one
    /// file and an edited route doesn't get the old route's journeys.
    static func key(for legs: [RouteLegPlan]) -> String {
        let description = legs.map { leg in
            [
                leg.originCode,
                leg.destinationCode ?? "",
                leg.departurePlatforms.sorted().joined(separator: ","),
                leg.arrivalPlatforms.sorted().joined(separator: ","),
            ].joined(separator: ">")
        }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(description.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    @concurrent
    static func load(key: String) async -> Saved? {
        let url = directory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    @concurrent
    static func save(_ saved: Saved, key: String) async {
        let url = directory.appendingPathComponent("\(key).json")
        do {
            try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        } catch {
            Log.journeys.error("Couldn't save journeys: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The saved journeys still worth showing for a request at `departAt`:
    /// ones that haven't left yet.
    static func usable(_ saved: Saved, for departAt: Date) -> [CalculatedJourney] {
        guard abs(saved.departAt.timeIntervalSince(departAt)) <= maxTimeDifference else { return [] }
        let earliest = JourneyFetcher.wholeMinute(departAt)
        return saved.journeys.filter { journey in
            guard let departure = journey.departureTime.flatMap(parseTime) else { return false }
            return departure >= earliest
        }
    }
}

/// Calculates journeys for a saved route from a given time
@Observable
final class JourneyCalculator {
    var journey: CalculatedJourney?
    var journeys: [CalculatedJourney] = []
    var isCalculating = false
    var error: String?
    /// The journeys on screen were saved earlier, and haven't been updated
    /// from the server yet. When set, this is when they were found.
    var showingSavedFrom: Date?
    /// Why saved journeys are still on screen, when updating them failed.
    var updateFailure: String?

    /// The next few journeys usually take the next few trains.
    static let candidateTrains = 8
    /// A train leaving more than this after the first suitable one is not
    /// worth checking for a faster arrival.
    static let candidateMinutes: TimeInterval = 60 * 60
    /// How far ahead to look for a train before giving up.
    static let searchHorizon: TimeInterval = 24 * 60 * 60

    private let dataSource: JourneyDataSource
    private let usesStore: Bool
    private var currentRun: Task<Void, Never>?
    private var lastDepartAt: Date?

    /// - Parameter usesStore: whether journeys are saved to and shown from
    ///   disk. Off in tests.
    init(dataSource: JourneyDataSource = APIClient(), usesStore: Bool = true) {
        self.dataSource = dataSource
        self.usesStore = usesStore
    }

    /// Finds up to `count` consecutive journeys. Starting again, say after
    /// the time is changed, abandons the run already going.
    func calculateMultiple(route: SavedRoute, departAt: Date, count: Int = 5) async {
        await calculateMultiple(
            legs: route.sortedLegs.map(RouteLegPlan.init),
            connectionBuffer: TimeInterval(LiveActivitySettings.load().minimumConnectionMinutes * 60),
            departAt: departAt,
            count: count
        )
    }

    func calculateMultiple(legs: [RouteLegPlan], connectionBuffer: TimeInterval, departAt: Date, count: Int = 5) async {
        currentRun?.cancel()
        let run = Task {
            await self.findJourneys(legs: legs, connectionBuffer: connectionBuffer, departAt: departAt, count: count)
        }
        currentRun = run
        await withTaskCancellationHandler {
            await run.value
        } onCancel: {
            run.cancel()
        }
    }

    private func findJourneys(legs: [RouteLegPlan], connectionBuffer: TimeInterval, departAt: Date, count: Int) async {
        let storeKey = JourneyStore.key(for: legs)

        // Refreshing keeps the journeys on screen until new ones arrive; a
        // different time shouldn't show the old time's journeys meanwhile.
        if departAt != lastDepartAt {
            journeys = []
            journey = nil
            showingSavedFrom = nil
        }
        lastDepartAt = departAt
        isCalculating = true
        error = nil
        updateFailure = nil

        if usesStore, journeys.isEmpty, let saved = await JourneyStore.load(key: storeKey) {
            let usable = JourneyStore.usable(saved, for: departAt)
            if !usable.isEmpty, !Task.isCancelled {
                journeys = usable
                journey = usable.first
                showingSavedFrom = saved.savedAt
            }
        }

        let fetcher = JourneyFetcher(dataSource: dataSource)
        defer { fetcher.cancel() }

        var results: [CalculatedJourney] = []
        var failure: String?
        var nextDeparture = departAt
        // A journey can turn out to arrive no sooner than the one before it
        // (both catch the same last train), which replaces that one; a few
        // spare attempts make up for it.
        var attempts = 0

        while results.count < count && attempts < count + 3 {
            attempts += 1
            do {
                let found = try await findJourney(legs: legs, connectionBuffer: connectionBuffer, departAt: nextDeparture, using: fetcher)
                if let previous = results.last, !Self.arrivesLater(found, than: previous) {
                    // Leaving later for the same arrival is the better journey.
                    results[results.count - 1] = found
                } else {
                    results.append(found)
                }
                // Next search starts 1 minute after this journey's first departure
                guard let depTime = found.departureTime, let depDate = parseTime(depTime) else { break }
                nextDeparture = depDate.addingTimeInterval(60)
            } catch let journeyError as JourneyError {
                failure = journeyError.message
                break
            } catch {
                failure = error.localizedDescription
                break
            }
            if Task.isCancelled { break }
        }

        // A newer run owns what's on screen now.
        guard !Task.isCancelled else { return }
        isCalculating = false

        if results.isEmpty && showingSavedFrom != nil {
            // Keep the saved journeys rather than swap them for an error.
            updateFailure = failure ?? "No journeys found"
            return
        }

        journeys = results
        journey = results.first
        showingSavedFrom = nil
        error = results.isEmpty ? (failure ?? "No journeys found") : nil

        if usesStore, !results.isEmpty {
            let saved = JourneyStore.Saved(savedAt: Date(), departAt: departAt, journeys: results)
            Task { await JourneyStore.save(saved, key: storeKey) }
        }
    }

    /// Whether `journey` gets in after `other`. An unknown arrival counts as
    /// later, so a journey isn't dropped for missing data.
    private static func arrivesLater(_ journey: CalculatedJourney, than other: CalculatedJourney) -> Bool {
        guard let arrival = journey.arrivalTime.flatMap(parseTime),
              let otherArrival = other.arrivalTime.flatMap(parseTime) else { return true }
        return arrival > otherArrival
    }

    /// One train a leg could take, with what's known about its arrival.
    private struct Option {
        let index: Int
        let service: BoardService
        let detail: ServiceDetail?
        let arrivalStop: Stop?

        var arrival: Date? {
            (arrivalStop?.arrival?.bestTime ?? arrivalStop?.arrival?.`public`).flatMap(parseTime)
        }

        var arrivalPlatform: String? {
            arrivalStop?.platform?.displayPlatform
        }
    }

    /// The journey on the route that leaves at or after `departAt` and gets
    /// in soonest. On each leg that's the train that arrives first, among
    /// those leaving within the hour, so a fast train leaving a few minutes
    /// later beats a slow one leaving now.
    private func findJourney(legs: [RouteLegPlan], connectionBuffer: TimeInterval, departAt: Date, using fetcher: JourneyFetcher) async throws -> CalculatedJourney {
        guard !legs.isEmpty else {
            throw JourneyError(message: "Route has no legs")
        }

        var calculatedLegs: [CalculatedLeg] = []
        var nextEarliestDeparture = departAt

        for (index, leg) in legs.enumerated() {
            guard let destCode = leg.destinationCode, !destCode.isEmpty else {
                throw JourneyError(message: "Leg \(index + 1) has no destination set")
            }

            let matchingServices = try await departures(for: leg, to: destCode, from: nextEarliestDeparture, using: fetcher)
            guard let firstService = matchingServices.first else {
                throw JourneyError(message: "No suitable train found from \(leg.originName) to \(leg.destinationName ?? destCode) in the next 24 hours")
            }

            // Trains worth comparing: the next few, within the hour.
            let firstDeparture = Self.bookedDeparture(firstService)
            var candidates: [BoardService] = []
            for service in matchingServices.prefix(Self.candidateTrains) {
                if let firstDeparture, let departure = Self.bookedDeparture(service),
                   departure.timeIntervalSince(firstDeparture) > Self.candidateMinutes {
                    break
                }
                candidates.append(service)
            }
            fetcher.prefetchDetails(candidates)

            var options: [Option] = []
            for (candidateIndex, service) in candidates.enumerated() {
                options.append(await option(candidateIndex, service, to: destCode, using: fetcher))
            }

            // Prefer trains arriving at a preferred platform. An unknown
            // platform doesn't rule a train out.
            let arrPlatforms = leg.arrivalPlatforms
            var pool = options.filter { option in
                guard !arrPlatforms.isEmpty, let platform = option.arrivalPlatform, !platform.isEmpty else { return true }
                return arrPlatforms.contains(platform)
            }
            if pool.isEmpty {
                // None of them; look further along the board for one that does.
                let later = matchingServices.dropFirst(candidates.count)
                fetcher.prefetchDetails(later.prefix(10))
                for (offset, service) in later.enumerated() {
                    let option = await option(candidates.count + offset, service, to: destCode, using: fetcher)
                    if let platform = option.arrivalPlatform, arrPlatforms.contains(platform) {
                        pool = [option]
                        break
                    }
                }
            }
            if pool.isEmpty {
                // Nothing arrives at a preferred platform; take the best anyway.
                pool = options
            }
            try Task.checkCancellation()

            // Soonest arrival; among equals, or with nothing known, the first to leave.
            let best = pool.min { a, b in
                (a.arrival ?? .distantFuture, a.index) < (b.arrival ?? .distantFuture, b.index)
            }!
            let bestService = best.service
            let arrStop = best.arrivalStop

            let arrivalTime = arrStop?.arrival?.bestTime ?? arrStop?.arrival?.`public`
            let departureTime = bestService.stop.departure?.bestTime ?? bestService.stop.departure?.`public`

            // Calculate connection time from previous leg
            let connectionMinutes: Int?
            if index > 0, let prevArrival = calculatedLegs.last?.arrivalTime,
               let prevDate = parseTime(prevArrival),
               let departureTime,
               let depDate = parseTime(departureTime) {
                connectionMinutes = max(0, Int(depDate.timeIntervalSince(prevDate) / 60))
            } else {
                connectionMinutes = nil
            }

            calculatedLegs.append(CalculatedLeg(
                legIndex: index,
                service: bestService,
                serviceDetail: best.detail,
                originName: leg.originName,
                destinationName: leg.destinationName ?? destCode,
                destinationCode: destCode,
                departureTime: departureTime,
                arrivalTime: arrivalTime,
                departurePlatform: bestService.stop.platform?.displayPlatform,
                arrivalPlatform: arrStop?.platform?.displayPlatform,
                departureDelay: bestService.stop.departure?.delayMinutes,
                arrivalDelay: arrStop?.arrival?.delayMinutes,
                isCancelled: bestService.isCancelled,
                connectionMinutes: connectionMinutes
            ))

            // Set next earliest departure: arrival time + connection buffer
            if let arrivalTime, let arrDate = parseTime(arrivalTime) {
                nextEarliestDeparture = arrDate.addingTimeInterval(connectionBuffer)
            } else if let depTime = bestService.stop.departure?.bestTime,
                      let depDate = parseTime(depTime) {
                // Fallback: estimate 30 min travel, then connect
                nextEarliestDeparture = depDate.addingTimeInterval(30 * 60)
            }
        }

        return CalculatedJourney(
            legs: calculatedLegs,
            departureTime: calculatedLegs.first?.departureTime,
            arrivalTime: calculatedLegs.last?.arrivalTime,
            requestedTime: departAt
        )
    }

    /// Trains on the leg leaving at or after `start` that the leg's
    /// preferences allow, from the first board that has any. Looks up to a
    /// day ahead, past midnight, with longer boards after empty ones.
    private func departures(for leg: RouteLegPlan, to destCode: String, from start: Date, using fetcher: JourneyFetcher) async throws -> [BoardService] {
        let horizon = start.addingTimeInterval(Self.searchHorizon)
        var searchFrom = start
        var window = JourneyFetcher.initialWindowMinutes

        while searchFrom < horizon {
            let board: JourneyFetcher.FetchedBoard
            do {
                board = try await fetcher.board(from: leg.originCode, to: destCode, covering: searchFrom, windowMinutes: window)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw JourneyError(message: "Failed to load departures for \(leg.originName): \(error.localizedDescription)")
            }

            let earliest = JourneyFetcher.wholeMinute(searchFrom)
            let matching = board.services.filter { service in
                // A board fetched for an earlier journey starts earlier.
                if let booked = Self.bookedDeparture(service), booked < earliest { return false }
                if service.isCancelled { return false }
                if !leg.departurePlatforms.isEmpty {
                    let platform = service.stop.platform?.displayPlatform ?? ""
                    if !platform.isEmpty && !leg.departurePlatforms.contains(platform) { return false }
                }
                return true
            }
            if !matching.isEmpty { return matching }

            searchFrom = board.to
            window = min(window * 2, JourneyFetcher.maxWindowMinutes)
        }
        return []
    }

    private func option(_ index: Int, _ service: BoardService, to destCode: String, using fetcher: JourneyFetcher) async -> Option {
        let detail = await fetcher.detail(service)
        return Option(
            index: index,
            service: service,
            detail: detail,
            arrivalStop: detail.flatMap { CalculatedLeg.arrivalStop(in: $0, destinationCode: destCode) }
        )
    }

    private static func bookedDeparture(_ service: BoardService) -> Date? {
        (service.stop.departure?.`public` ?? service.stop.departure?.bestTime).flatMap(parseTime)
    }
}

// MARK: - Time parsing helpers (module-level)

private nonisolated(unsafe) let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private nonisolated(unsafe) let isoFractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private nonisolated let hhmmFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.locale = Locale(identifier: "en_GB_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/London")
    return formatter
}()

/// Parse an ISO 8601 or HH:MM time string into a Date (today, UK timezone).
/// Formatters are slow to make, and this runs for every train on a board,
/// so they're made once.
nonisolated func parseTime(_ timeString: String) -> Date? {
    // Try ISO 8601 first: 2026-10-06T14:32:00+01:00
    if let date = isoFormatter.date(from: timeString) {
        return date
    }

    // Try with fractional seconds
    if let date = isoFractionalFormatter.date(from: timeString) {
        return date
    }

    // Try HH:MM format (assume today, UK timezone)
    if timeString.count == 5, let time = hhmmFormatter.date(from: timeString) {
        // Combine with today's date
        let timeZone = hhmmFormatter.timeZone!
        let calendar = Calendar.current
        var components = calendar.dateComponents(in: timeZone, from: Date())
        let timeComponents = calendar.dateComponents(in: timeZone, from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components)
    }

    return nil
}
