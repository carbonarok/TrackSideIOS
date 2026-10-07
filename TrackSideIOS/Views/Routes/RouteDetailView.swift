import SwiftUI
import SwiftData

struct RouteDetailView: View {
    let route: SavedRoute
    let liveClient: LiveClient

    @Environment(ActiveJourneyManager.self) private var journeyManager
    @State private var calculator = JourneyCalculator()
    @State private var departureTime = Date()
    @State private var showTimePicker = false
    @State private var selectedTab = 0
    @State private var trackingError: String?

    // For the "all departures" fallback view
    @State private var legBoards: [String: Board] = [:]
    @State private var isLoadingBoards = false

    private let apiClient = APIClient()

    /// The active tracker for this route (nil if not tracking this route)
    private var activeTracker: JourneyTracker? {
        journeyManager.tracker(for: route.persistentModelID)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Journey planner controls
            journeyControls

            // Content
            if calculator.isCalculating {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Calculating journey...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let journey = calculator.journey {
                JourneyTimelineView(
                    journey: journey,
                    liveClient: liveClient,
                    tracker: activeTracker,
                    onTrackJourney: {
                        startTracking(journey: journey)
                    },
                    onStopTracking: {
                        journeyManager.stopTracking()
                    }
                )
            } else if let error = calculator.error {
                Spacer()
                ContentUnavailableView {
                    Label("No Journey Found", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") {
                        Task { await calculator.calculate(route: route, departAt: departureTime) }
                    }
                }
                Spacer()
            } else {
                // Initial state — show all departures
                allDeparturesView
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Auto-calculate for "now" on load
            await calculator.calculate(route: route, departAt: departureTime)
        }
        .alert("Tracking Error", isPresented: .init(
            get: { trackingError != nil },
            set: { if !$0 { trackingError = nil } }
        )) {
            Button("OK") { trackingError = nil }
        } message: {
            Text(trackingError ?? "")
        }
    }

    // MARK: - Journey Controls

    @ViewBuilder
    private var journeyControls: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.blue)

                if showTimePicker {
                    DatePicker("Depart at", selection: $departureTime, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                } else {
                    Button {
                        showTimePicker = true
                    } label: {
                        HStack {
                            Text("Depart at")
                                .foregroundStyle(.secondary)
                            Text(formatDepartureTime(departureTime))
                                .fontWeight(.semibold)
                        }
                    }
                    .tint(.primary)
                }

                Spacer()

                Button {
                    departureTime = Date()
                    Task { await calculator.calculate(route: route, departAt: departureTime) }
                    showTimePicker = false
                } label: {
                    Text("Now")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await calculator.calculate(route: route, departAt: departureTime) }
                    showTimePicker = false
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Quick time adjustments
            if calculator.journey != nil {
                HStack(spacing: 8) {
                    ForEach([-30, -15, 15, 30, 60], id: \.self) { offset in
                        Button {
                            departureTime = departureTime.addingTimeInterval(TimeInterval(offset * 60))
                            Task { await calculator.calculate(route: route, departAt: departureTime) }
                        } label: {
                            Text(offset > 0 ? "+\(offset)m" : "\(offset)m")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - All Departures (fallback)

    @ViewBuilder
    private var allDeparturesView: some View {
        if isLoadingBoards && legBoards.isEmpty {
            Spacer()
            ProgressView("Loading departures...")
            Spacer()
        } else {
            List {
                ForEach(route.sortedLegs) { leg in
                    legSection(leg)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func legSection(_ leg: SavedLeg) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(leg.originName)
                        .font(.headline)
                    if let destName = leg.destinationName {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.caption)
                            Text(destName)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let board = legBoards[leg.originCode] {
                let matching = filterServices(board.services, for: leg)
                if matching.isEmpty {
                    Text("No matching departures")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matching.prefix(5)) { service in
                        NavigationLink {
                            ServiceDetailView(uid: service.uid, runDate: service.runDate, liveClient: liveClient)
                        } label: {
                            BoardServiceRow(service: service)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("Leg \(leg.order + 1)")
        }
    }

    // MARK: - Tracking

    private func startTracking(journey: CalculatedJourney) {
        Task {
            do {
                try await journeyManager.startTracking(
                    journey: journey,
                    routeID: route.persistentModelID
                )
            } catch {
                trackingError = "Could not start tracking: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    private func filterServices(_ services: [BoardService], for leg: SavedLeg) -> [BoardService] {
        let depPlatforms = parsePlatforms(leg.preferredDeparturePlatform)
        return services.filter { service in
            if let destCode = leg.destinationCode {
                let matchesDest = service.destination.contains { $0.crs == destCode || $0.tiploc == destCode }
                if !matchesDest { return false }
            }
            if !depPlatforms.isEmpty {
                let currentPlatform = service.stop.platform?.displayPlatform ?? ""
                if !currentPlatform.isEmpty && !depPlatforms.contains(currentPlatform) { return false }
            }
            return true
        }
    }

    private func parsePlatforms(_ value: String?) -> Set<String> {
        guard let value, !value.isEmpty else { return [] }
        return Set(value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private func formatDepartureTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        return formatter.string(from: date)
    }

    private func loadAllLegs() async {
        isLoadingBoards = true
        await withTaskGroup(of: (String, Board?).self) { group in
            for leg in route.sortedLegs {
                group.addTask {
                    let board = try? await apiClient.departures(for: leg.originCode, to: leg.destinationCode)
                    return (leg.originCode, board)
                }
            }
            for await (code, board) in group {
                if let board { legBoards[code] = board }
            }
        }
        isLoadingBoards = false
    }
}
