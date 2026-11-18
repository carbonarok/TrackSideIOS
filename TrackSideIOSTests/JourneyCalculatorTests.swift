import Foundation
import Testing
@testable import TrackSideIOS

/// How the calculator chooses trains, against a made-up timetable. Times
/// are in November, when UK time is UTC.
@Suite("Journey calculator")
struct JourneyCalculatorTests {
    @Test("Takes the train that arrives first, not the one that leaves first")
    func fastestTrain() async throws {
        let timetable = FakeTimetable()
        timetable.add(Train("SLOW", "WAT", "08:00", "WOK", "09:00"))
        timetable.add(Train("FAST", "WAT", "08:10", "WOK", "08:40"))

        let journeys = await find(timetable, legs: [leg("WAT", "WOK")], at: "07:55", count: 1)

        #expect(journeys.first?.legs.first?.service.uid == "FAST")
    }

    @Test("Lists consecutive journeys in order")
    func consecutiveJourneys() async throws {
        let timetable = FakeTimetable()
        timetable.add(Train("A", "WAT", "08:00", "WOK", "08:30"))
        timetable.add(Train("B", "WAT", "08:15", "WOK", "08:45"))
        timetable.add(Train("C", "WAT", "08:30", "WOK", "09:00"))

        let journeys = await find(timetable, legs: [leg("WAT", "WOK")], at: "07:55", count: 3)

        #expect(journeys.map { $0.legs[0].service.uid } == ["A", "B", "C"])
    }

    @Test("Finds the first train tomorrow when none is left today")
    func pastMidnight() async throws {
        let timetable = FakeTimetable()
        timetable.add(Train("LATE", "WAT", "06:00", "WOK", "06:30", day: 19))

        let journeys = await find(timetable, legs: [leg("WAT", "WOK")], at: "23:30", count: 1)

        #expect(journeys.first?.legs.first?.service.uid == "LATE")
    }

    @Test("Fetches each board and train once for all the journeys")
    func sharesFetches() async throws {
        let timetable = FakeTimetable()
        for (index, minute) in [0, 15, 30, 45, 55].enumerated() {
            timetable.add(Train("T\(index)", "WAT", String(format: "08:%02d", minute), "WOK", String(format: "09:%02d", minute)))
        }

        let journeys = await find(timetable, legs: [leg("WAT", "WOK")], at: "07:55", count: 5)

        #expect(journeys.count == 5)
        #expect(timetable.boardRequests == 1)
        #expect(timetable.detailRequests.count == 5)
        #expect(Set(timetable.detailRequests).count == 5)
    }

    @Test("Leaves time to change trains")
    func connectionBuffer() async throws {
        let timetable = FakeTimetable()
        timetable.add(Train("FIRST", "WAT", "08:00", "CLJ", "08:30"))
        timetable.add(Train("TIGHT", "CLJ", "08:33", "WOK", "09:00"))
        timetable.add(Train("OK", "CLJ", "08:40", "WOK", "09:10"))

        let journeys = await find(
            timetable,
            legs: [leg("WAT", "CLJ"), leg("CLJ", "WOK")],
            at: "07:55",
            count: 1,
            connectionMinutes: 5
        )

        let legs = try #require(journeys.first?.legs)
        #expect(legs.map(\.service.uid) == ["FIRST", "OK"])
        #expect(legs[1].connectionMinutes == 10)
    }

    @Test("Prefers a train arriving at a preferred platform")
    func arrivalPlatform() async throws {
        let timetable = FakeTimetable()
        timetable.add(Train("P1", "WAT", "08:00", "WOK", "08:30", arrivalPlatform: "1"))
        timetable.add(Train("P2", "WAT", "08:05", "WOK", "08:35", arrivalPlatform: "2"))

        let journeys = await find(timetable, legs: [leg("WAT", "WOK", arrivalPlatforms: ["2"])], at: "07:55", count: 1)

        #expect(journeys.first?.legs.first?.service.uid == "P2")
    }

    @Test("Skips cancelled trains")
    func cancelled() async throws {
        let timetable = FakeTimetable()
        timetable.add(Train("GONE", "WAT", "08:00", "WOK", "08:30", cancelled: true))
        timetable.add(Train("RUNS", "WAT", "08:20", "WOK", "08:50"))

        let journeys = await find(timetable, legs: [leg("WAT", "WOK")], at: "07:55", count: 1)

        #expect(journeys.first?.legs.first?.service.uid == "RUNS")
    }

    @Test("A later journey with the same arrival replaces the earlier one")
    func sameArrival() async throws {
        let timetable = FakeTimetable()
        timetable.add(Train("EARLY", "WAT", "08:00", "CLJ", "08:20"))
        timetable.add(Train("LATER", "WAT", "08:10", "CLJ", "08:30"))
        timetable.add(Train("ONWARD", "CLJ", "09:00", "WOK", "09:30"))

        let journeys = await find(timetable, legs: [leg("WAT", "CLJ"), leg("CLJ", "WOK")], at: "07:55", count: 3)

        // Both catch the 09:00 onward; leaving at 08:10 is the better choice.
        #expect(journeys.count == 1)
        #expect(journeys.first?.legs.map(\.service.uid) == ["LATER", "ONWARD"])
    }

    @Test("Says when there's no train")
    func noTrain() async throws {
        let timetable = FakeTimetable()
        let calculator = JourneyCalculator(dataSource: timetable, usesStore: false)

        await calculator.calculateMultiple(legs: [leg("WAT", "WOK")], connectionBuffer: 0, departAt: time("07:55"), count: 1)

        #expect(calculator.journeys.isEmpty)
        #expect(calculator.error?.contains("No suitable train") == true)
        // Longer boards after empty ones: a day in a handful of requests.
        #expect(timetable.boardRequests <= 6)
    }

    // MARK: - Helpers

    private func find(
        _ timetable: FakeTimetable,
        legs: [RouteLegPlan],
        at departAt: String,
        count: Int,
        connectionMinutes: Int = 0
    ) async -> [CalculatedJourney] {
        let calculator = JourneyCalculator(dataSource: timetable, usesStore: false)
        await calculator.calculateMultiple(
            legs: legs,
            connectionBuffer: TimeInterval(connectionMinutes * 60),
            departAt: time(departAt),
            count: count
        )
        return calculator.journeys
    }

    private func leg(_ origin: String, _ destination: String, arrivalPlatforms: Set<String> = []) -> RouteLegPlan {
        RouteLegPlan(
            originCode: origin,
            originName: origin,
            destinationCode: destination,
            destinationName: destination,
            arrivalPlatforms: arrivalPlatforms
        )
    }
}

@Suite("Parsing times")
struct ParseTimeTests {
    @Test("Reads the server's ISO 8601 times")
    func iso() {
        #expect(parseTime("2026-11-18T08:00:00Z") == time("08:00"))
        #expect(parseTime("2026-06-18T09:00:00+01:00") == ISO8601DateFormatter().date(from: "2026-06-18T08:00:00Z"))
        #expect(parseTime("2026-11-18T08:00:00.000Z") == time("08:00"))
    }

    @Test("Rejects what isn't a time")
    func invalid() {
        #expect(parseTime("soon") == nil)
        #expect(parseTime("") == nil)
    }
}

@Suite("Retrying requests")
struct RetryTests {
    @Test("Retries errors that pass", arguments: [
        URLError(.timedOut), URLError(.networkConnectionLost), URLError(.notConnectedToInternet),
    ])
    func transient(error: URLError) {
        #expect(APIClient.isTransient(error))
    }

    @Test("Retries a gateway error while the server restarts")
    func gateway() {
        #expect(APIClient.isTransient(APIError.httpError(statusCode: 503, message: "")))
        #expect(!APIClient.isTransient(APIError.httpError(statusCode: 404, message: "")))
    }

    @Test("Doesn't retry what won't change")
    func permanent() {
        #expect(!APIClient.isTransient(URLError(.badURL)))
        #expect(!APIClient.isTransient(APIError.decodingError("")))
    }
}

@Suite("Saved journeys")
struct JourneyStoreTests {
    @Test("Edited routes don't share saved journeys")
    func keys() {
        let plain = [RouteLegPlan(originCode: "WAT", originName: "", destinationCode: "WOK", destinationName: "")]
        let withPlatform = [RouteLegPlan(originCode: "WAT", originName: "", destinationCode: "WOK", destinationName: "", arrivalPlatforms: ["2"])]
        #expect(JourneyStore.key(for: plain) == JourneyStore.key(for: plain))
        #expect(JourneyStore.key(for: plain) != JourneyStore.key(for: withPlatform))
    }

    @Test("Only journeys that haven't left are shown again")
    func usable() async {
        let timetable = FakeTimetable()
        timetable.add(Train("A", "WAT", "08:00", "WOK", "08:30"))
        timetable.add(Train("B", "WAT", "09:00", "WOK", "09:30"))
        let calculator = JourneyCalculator(dataSource: timetable, usesStore: false)
        await calculator.calculateMultiple(
            legs: [RouteLegPlan(originCode: "WAT", originName: "", destinationCode: "WOK", destinationName: "")],
            connectionBuffer: 0,
            departAt: time("07:55"),
            count: 2
        )
        let saved = JourneyStore.Saved(savedAt: time("07:55"), departAt: time("07:55"), journeys: calculator.journeys)

        #expect(JourneyStore.usable(saved, for: time("08:30")).map { $0.legs[0].service.uid } == ["B"])
        #expect(JourneyStore.usable(saved, for: time("12:00")).isEmpty)
    }
}

// MARK: - Fake timetable

/// 18 November 2026 at `hhmm`, UTC (which is UK time in November).
func time(_ hhmm: String, day: Int = 18) -> Date {
    ISO8601DateFormatter().date(from: String(format: "2026-11-%02dT%@:00Z", day, hhmm))!
}

struct Train {
    let uid: String
    let origin: String
    let departure: Date
    let destination: String
    let arrival: Date
    let arrivalPlatform: String?
    let cancelled: Bool

    init(
        _ uid: String,
        _ origin: String,
        _ departure: String,
        _ destination: String,
        _ arrival: String,
        day: Int = 18,
        arrivalPlatform: String? = nil,
        cancelled: Bool = false
    ) {
        self.uid = uid
        self.origin = origin
        self.departure = time(departure, day: day)
        self.destination = destination
        self.arrival = time(arrival, day: day)
        self.arrivalPlatform = arrivalPlatform
        self.cancelled = cancelled
    }

    var runDate: String { String(ISO8601DateFormatter().string(from: departure).prefix(10)) }

    func stop(_ code: String, kind: StopKind, arrival: Date? = nil, departure: Date? = nil, platform: String? = nil) -> Stop {
        Stop(
            tiploc: code,
            crs: code,
            name: code,
            kind: kind,
            arrival: arrival.map(Self.times),
            departure: departure.map(Self.times),
            pass: nil,
            platform: platform.map { Platform(planned: $0, actual: nil, changed: false, confirmed: false, suppressed: nil) },
            cancelled: cancelled,
            startsHere: nil,
            atPlatform: nil,
            approaching: nil,
            terminatesHere: nil,
            line: nil,
            path: nil
        )
    }

    nonisolated static func times(_ date: Date) -> Times {
        Times(
            public: ISO8601DateFormatter().string(from: date),
            working: nil,
            actual: nil,
            estimated: nil,
            delayMinutes: nil,
            delayed: nil,
            cancelled: nil
        )
    }

    var boardService: BoardService {
        BoardService(
            uid: uid,
            runDate: runDate,
            headcode: nil,
            operator: nil,
            isPassenger: true,
            status: cancelled ? .cancelled : .scheduled,
            origin: [],
            destination: [],
            cancelReasonCode: nil,
            cancelReasonCodeDescription: nil,
            cancelReason: nil,
            lateReason: nil,
            plannedCancel: false,
            stop: stop(origin, kind: .origin, departure: departure)
        )
    }

    var detail: ServiceDetail {
        ServiceDetail(
            uid: uid,
            runDate: runDate,
            headcode: nil,
            operator: nil,
            isPassenger: true,
            status: cancelled ? .cancelled : .scheduled,
            origin: [],
            destination: [],
            cancelReasonCode: nil,
            cancelReasonCodeDescription: nil,
            cancelReason: nil,
            lateReason: nil,
            plannedCancel: false,
            trainClass: nil,
            powerType: nil,
            category: nil,
            source: "test",
            position: nil,
            associations: nil,
            stops: [
                stop(origin, kind: .origin, departure: departure),
                stop(destination, kind: .destination, arrival: arrival, platform: arrivalPlatform),
            ]
        )
    }
}

/// Answers like the server: a board holds the trains from its origin to its
/// destination booked to leave within its window.
final class FakeTimetable: JourneyDataSource {
    private var trains: [Train] = []
    private(set) var boardRequests = 0
    private(set) var detailRequests: [String] = []

    func add(_ train: Train) {
        trains.append(train)
    }

    func departures(for code: String, to: String?, at: String?, window: Int?) async throws -> Board {
        boardRequests += 1
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        let from = try #require(at.flatMap(formatter.date(from:)))
        let end = from.addingTimeInterval(TimeInterval((window ?? 120) * 60))
        let services = trains
            .filter { $0.origin == code && (to == nil || $0.destination == to) }
            .filter { $0.departure >= from && $0.departure < end }
            .sorted { $0.departure < $1.departure }
            .map(\.boardService)
        return Board(
            location: Location(tiploc: code, crs: code, name: code),
            from: at ?? "",
            to: "",
            messages: [],
            services: services
        )
    }

    func serviceDetail(uid: String, date: String) async throws -> ServiceDetail {
        detailRequests.append(uid)
        guard let train = trains.first(where: { $0.uid == uid }) else { throw URLError(.fileDoesNotExist) }
        return train.detail
    }
}
