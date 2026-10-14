import SwiftUI
import SwiftData

struct RouteDetailView: View {
    let route: SavedRoute
    let liveClient: LiveClient

    @Environment(ActiveJourneyManager.self) private var journeyManager
    @State private var calculator = JourneyCalculator()
    @State private var departureTime = Date()
    @State private var showTimePicker = false
    @State private var expandedJourneyID: UUID?
    @State private var trackingError: String?

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
                    Text("Finding journeys...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if !calculator.journeys.isEmpty {
                journeyList
            } else if let error = calculator.error {
                Spacer()
                ContentUnavailableView {
                    Label("No Journeys Found", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") {
                        Task { await calculator.calculateMultiple(route: route, departAt: departureTime) }
                    }
                }
                Spacer()
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await calculator.calculateMultiple(route: route, departAt: departureTime)
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
                    Task { await calculator.calculateMultiple(route: route, departAt: departureTime) }
                    showTimePicker = false
                } label: {
                    Text("Now")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await calculator.calculateMultiple(route: route, departAt: departureTime) }
                    showTimePicker = false
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Quick time adjustments
            if !calculator.journeys.isEmpty {
                HStack(spacing: 8) {
                    ForEach([-30, -15, 15, 30, 60], id: \.self) { offset in
                        Button {
                            departureTime = departureTime.addingTimeInterval(TimeInterval(offset * 60))
                            Task { await calculator.calculateMultiple(route: route, departAt: departureTime) }
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

    // MARK: - Journey List

    @ViewBuilder
    private var journeyList: some View {
        List {
            // Active tracking banner (if tracking this route)
            if let tracker = activeTracker, tracker.isTracking {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Live Tracking")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            if tracker.updatedLegs.contains(where: { $0.isCancelled }) {
                                Text("A train on this journey has been cancelled")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        Button("Stop") {
                            journeyManager.stopTracking()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(calculator.journeys, id: \.id) { journey in
                Section {
                    journeyCard(journey)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await calculator.calculateMultiple(route: route, departAt: departureTime)
        }
    }

    // MARK: - Journey Card

    @ViewBuilder
    private func journeyCard(_ journey: CalculatedJourney) -> some View {
        let isExpanded = expandedJourneyID == journey.id

        // Compact header — always visible
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedJourneyID = isExpanded ? nil : journey.id
            }
        } label: {
            HStack(spacing: 8) {
                // Operator colour bars
                HStack(spacing: 2) {
                    ForEach(journey.legs) { leg in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(leg.service.operator?.brandColor ?? .secondary)
                            .frame(width: 4, height: 44)
                    }
                }

                HStack(spacing: 0) {
                // Departure time
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTimeShort(journey.departureTime))
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(journey.legs.first?.originName ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 80, alignment: .leading)

                // Arrow + duration
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.secondary.opacity(0.3))
                            .frame(height: 1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(.secondary.opacity(0.3))
                            .frame(height: 1)
                    }
                    if let mins = journey.totalMinutes {
                        Text(formatDuration(mins))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if journey.legs.count > 1 {
                        Text("\(journey.legs.count - 1) change\(journey.legs.count > 2 ? "s" : "")")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                // Arrival time
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatTimeShort(journey.arrivalTime))
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(journey.legs.last?.destinationName ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 80, alignment: .trailing)

                Spacer().frame(width: 8)

                // Delay indicator + chevron
                VStack(spacing: 4) {
                    let maxDelay = journey.legs.compactMap { $0.departureDelay ?? $0.arrivalDelay }.max() ?? 0
                    if journey.hasIssues {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if maxDelay > 0 {
                        Text("+\(maxDelay)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(width: 30)
            }
            } // inner HStack
        }
        .buttonStyle(.plain)

        // Expanded content — full journey details
        if isExpanded {
            // Platform & headcode info for each leg
            ForEach(journey.legs) { leg in
                if let connectionMins = leg.connectionMinutes {
                    connectionSummary(minutes: connectionMins, stationName: leg.originName)
                }

                NavigationLink(value: ServiceRoute(uid: leg.service.uid, runDate: leg.service.runDate)) {
                    legSummaryRow(leg)
                }

            }

            // Track button
            if activeTracker == nil || activeTracker?.isTracking != true {
                Button {
                    startTracking(journey: journey)
                } label: {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Track This Journey")
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func legSummaryRow(_ leg: CalculatedLeg) -> some View {
        HStack(spacing: 10) {
            // Timeline dot
            Circle()
                .fill(leg.isCancelled ? .red : .blue)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let headcode = leg.service.headcode {
                        Text(headcode)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if let op = leg.service.operator {
                        Text(op.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if leg.isCancelled {
                        Text("CANCELLED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 12) {
                    // Departure
                    HStack(spacing: 3) {
                        Text(leg.originName)
                            .font(.caption)
                        if let time = leg.departureTime {
                            Text(formatTimeShort(time))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        if let p = leg.departurePlatform {
                            Text("P\(p)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)

                    // Arrival
                    HStack(spacing: 3) {
                        Text(leg.destinationName)
                            .font(.caption)
                        if let time = leg.arrivalTime {
                            Text(formatTimeShort(time))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        if let p = leg.arrivalPlatform {
                            Text("P\(p)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            Spacer()

            // Delay badge
            if let delay = leg.departureDelay ?? leg.arrivalDelay, delay > 0 {
                Text("+\(delay)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(delay >= 10 ? .red.opacity(0.15) : .orange.opacity(0.15))
                    .foregroundStyle(delay >= 10 ? .red : .orange)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .opacity(leg.isCancelled ? 0.5 : 1.0)
    }

    @ViewBuilder
    private func connectionSummary(minutes: Int, stationName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.caption2)
                .foregroundStyle(minutes < 5 ? .orange : .green)
            Text("Change at \(stationName) · \(minutes) min")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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

    private func formatTimeShort(_ timeString: String?) -> String {
        guard let timeString else { return "--:--" }
        if timeString.count > 10, let tIndex = timeString.firstIndex(of: "T") {
            let afterT = timeString[timeString.index(after: tIndex)...]
            return String(afterT.prefix(5))
        }
        return String(timeString.prefix(5))
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func formatDepartureTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM, HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        return formatter.string(from: date)
    }
}
