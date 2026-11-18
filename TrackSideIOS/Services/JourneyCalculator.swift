import Foundation
import Observation

/// A single leg in a calculated journey
struct CalculatedLeg: Identifiable {
    let id = UUID()
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
struct CalculatedJourney: Identifiable {
    let id = UUID()
    let legs: [CalculatedLeg]
    let departureTime: String?
    let arrivalTime: String?
    let requestedTime: Date

    var totalLegs: Int { legs.count }

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

/// Why a journey couldn't be found, worded for the person using the app.
struct JourneyError: Error {
    let message: String
}

/// What one calculation has fetched, so the journeys it finds share boards
/// and trains instead of asking the server again for each one.
///
/// A leg's board covers two hours. The first journey's fetch usually holds
/// the trains for all the later ones too, and each train's details are
/// fetched once, several at a time.
final class JourneyFetcher {
    struct FetchedBoard {
        let from: Date
        let to: Date
        let services: [BoardService]
    }

    static let windowMinutes = 120

    private let apiClient: APIClient
    private var boards: [String: [FetchedBoard]] = [:]
    private var details: [String: Task<ServiceDetail?, Never>] = [:]

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// The board from `origin` to `destination` covering `time`, fetched
    /// only when no earlier fetch covers it.
    func board(from origin: String, to destination: String, covering time: Date) async throws -> FetchedBoard {
        let key = "\(origin)|\(destination)"
        if let board = boards[key]?.first(where: { $0.from <= time && time < $0.to }) {
            return board
        }
        // The server takes whole minutes.
        let from = Self.wholeMinute(time)
        let board = try await apiClient.departures(
            for: origin,
            to: destination,
            at: Self.formatForAPI(from),
            window: Self.windowMinutes
        )
        let fetched = FetchedBoard(
            from: from,
            to: from.addingTimeInterval(TimeInterval(Self.windowMinutes * 60)),
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
        let apiClient = apiClient
        let task = Task {
            try? await apiClient.serviceDetail(uid: service.uid, date: service.runDate)
        }
        details[key] = task
        return task
    }

    private static let apiFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        return formatter
    }()

    /// The start of the minute `date` falls in.
    static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    /// A Date as the API's `at` parameter (UK local time).
    static func formatForAPI(_ date: Date) -> String {
        apiFormatter.string(from: date)
    }
}

/// Calculates journeys for a saved route from a given time
@Observable
final class JourneyCalculator {
    var journey: CalculatedJourney?
    var journeys: [CalculatedJourney] = []
    var isCalculating = false
    var error: String?

    private let apiClient = APIClient()
    private var currentRun: Task<Void, Never>?
    private var lastDepartAt: Date?

    /// Finds up to `count` consecutive journeys. Starting again, say after
    /// the time is changed, abandons the run already going.
    func calculateMultiple(route: SavedRoute, departAt: Date, count: Int = 5) async {
        currentRun?.cancel()
        let run = Task {
            await self.findJourneys(route: route, departAt: departAt, count: count)
        }
        currentRun = run
        await withTaskCancellationHandler {
            await run.value
        } onCancel: {
            run.cancel()
        }
    }

    private func findJourneys(route: SavedRoute, departAt: Date, count: Int) async {
        // Refreshing keeps the journeys on screen until new ones arrive; a
        // different time shouldn't show the old time's journeys meanwhile.
        if departAt != lastDepartAt {
            journeys = []
            journey = nil
        }
        lastDepartAt = departAt
        isCalculating = true
        error = nil

        let fetcher = JourneyFetcher(apiClient: apiClient)
        defer { fetcher.cancel() }

        var results: [CalculatedJourney] = []
        var failure: String?
        var nextDeparture = departAt

        for _ in 0..<count {
            do {
                let found = try await findJourney(route: route, departAt: nextDeparture, using: fetcher)
                results.append(found)
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

        journeys = results
        journey = results.first
        error = results.isEmpty ? (failure ?? "No journeys found") : nil
        isCalculating = false
    }

    /// The first journey on the route leaving at or after `departAt`.
    private func findJourney(route: SavedRoute, departAt: Date, using fetcher: JourneyFetcher) async throws -> CalculatedJourney {
        let connectionBuffer = TimeInterval(LiveActivitySettings.load().minimumConnectionMinutes * 60)

        let sortedLegs = route.sortedLegs
        guard !sortedLegs.isEmpty else {
            throw JourneyError(message: "Route has no legs")
        }

        var calculatedLegs: [CalculatedLeg] = []
        var nextEarliestDeparture = departAt

        for (index, leg) in sortedLegs.enumerated() {
            guard let destCode = leg.destinationCode, !destCode.isEmpty else {
                throw JourneyError(message: "Leg \(index + 1) has no destination set")
            }

            // Search for departures, a board at a time, until we find a
            // suitable service or reach end of day.
            let depPlatforms = parsePlatforms(leg.preferredDeparturePlatform)
            var searchFrom = nextEarliestDeparture
            let endOfDay = endOfCurrentDay(from: nextEarliestDeparture)
            var matchingServices: [BoardService] = []

            while searchFrom < endOfDay {
                let board: JourneyFetcher.FetchedBoard
                do {
                    board = try await fetcher.board(from: leg.originCode, to: destCode, covering: searchFrom)
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    throw JourneyError(message: "Failed to load departures for \(leg.originName): \(error.localizedDescription)")
                }

                let earliest = JourneyFetcher.wholeMinute(searchFrom)
                matchingServices = board.services.filter { service in
                    // A board fetched for an earlier journey starts earlier.
                    if let booked = service.stop.departure?.`public`,
                       let bookedDate = parseTime(booked),
                       bookedDate < earliest {
                        return false
                    }
                    // Skip cancelled services
                    if service.isCancelled { return false }
                    // Platform filter (if the user set preferred platforms)
                    if !depPlatforms.isEmpty {
                        let currentPlatform = service.stop.platform?.displayPlatform ?? ""
                        if !currentPlatform.isEmpty && !depPlatforms.contains(currentPlatform) {
                            return false
                        }
                    }
                    return true
                }

                if !matchingServices.isEmpty { break }

                // No suitable services on this board — try the next one
                searchFrom = board.to
            }

            guard let firstService = matchingServices.first else {
                throw JourneyError(message: "No suitable train found from \(leg.originName) to \(leg.destinationName ?? destCode) today")
            }

            // The next few journeys usually take the next few trains, so
            // fetch their details together now. With a preferred arrival
            // platform, later trains may be needed sooner.
            let arrPlatforms = parsePlatforms(leg.preferredArrivalPlatform)
            fetcher.prefetchDetails(matchingServices.prefix(arrPlatforms.isEmpty ? 5 : 10))

            // Fetch service detail to get arrival time at destination
            var bestService = firstService
            var serviceDetail = await fetcher.detail(firstService)
            var arrStop = serviceDetail.flatMap { CalculatedLeg.arrivalStop(in: $0, destinationCode: destCode) }

            // Check arrival platform filter — if the user specified preferred arrival
            // platforms and the service arrives at a different one, use the
            // first later one that arrives at a preferred platform, if any.
            if !arrPlatforms.isEmpty, let actualArrPlatform = arrStop?.platform?.displayPlatform,
               !actualArrPlatform.isEmpty, !arrPlatforms.contains(actualArrPlatform) {
                for altService in matchingServices.dropFirst() {
                    if let altDetail = await fetcher.detail(altService),
                       let altArrStop = CalculatedLeg.arrivalStop(in: altDetail, destinationCode: destCode),
                       let altArrPlatform = altArrStop.platform?.displayPlatform,
                       arrPlatforms.contains(altArrPlatform) {
                        bestService = altService
                        serviceDetail = altDetail
                        arrStop = altArrStop
                        break
                    }
                }
                // No alternative found — use the original service anyway
            }
            try Task.checkCancellation()

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
                serviceDetail: serviceDetail,
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

    // MARK: - Helpers

    private func parsePlatforms(_ value: String?) -> Set<String> {
        guard let value, !value.isEmpty else { return [] }
        return Set(value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private func formatDisplayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        return formatter.string(from: date)
    }

    /// End of the current day (midnight) in UK timezone
    private func endOfCurrentDay(from date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar.startOfDay(for: date).addingTimeInterval(24 * 60 * 60)
    }
}

// MARK: - Time parsing helpers (module-level)

private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private let isoFractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let hhmmFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.locale = Locale(identifier: "en_GB_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/London")
    return formatter
}()

/// Parse an ISO 8601 or HH:MM time string into a Date (today, UK timezone).
/// Formatters are slow to make, and this runs for every train on a board,
/// so they're made once.
func parseTime(_ timeString: String) -> Date? {
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
