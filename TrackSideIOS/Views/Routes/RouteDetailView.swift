import SwiftUI
import SwiftData

struct RouteDetailView: View {
    let route: SavedRoute
    let liveClient: LiveClient

    @Environment(ActiveJourneyManager.self) private var journeyManager
    @State private var calculator = JourneyCalculator()
    @State private var departureTime = Date()
    /// Which journey is open, by its trains rather than its id: refreshing
    /// (or saved journeys giving way to fresh ones) makes new ids for the
    /// same journeys, and the open one shouldn't snap shut.
    @State private var expandedJourneyKey: String?
    @State private var trackingError: String?
    /// Grows with the text size, so times don't get cut off.
    @ScaledMetric(relativeTo: .title3) private var journeyTimeWidth: CGFloat = 104

    /// The active tracker for this route (nil if not tracking this route)
    private var activeTracker: JourneyTracker? {
        journeyManager.tracker(for: route.persistentModelID)
    }

    @Environment(\.spanningFold) private var spanningFold

    var body: some View {
        Group {
            if let fold = spanningFold {
                // Both halves of an unfolded iPhone Duo: the journeys on one
                // side of the fold, the chosen one's trains on the other.
                HStack(spacing: 0) {
                    journeysColumn
                        .clearOfFold(.trailing)
                        .frame(width: fold)
                    chosenJourneyPane
                        .clearOfFold(.leading)
                }
            } else {
                journeysColumn
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await calculator.calculateMultiple(route: route, departAt: departureTime)
        }
        .sensoryFeedback(trigger: activeTracker?.isTracking == true) { _, tracking in
            tracking ? .success : .impact(weight: .light)
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

    private var journeysColumn: some View {
        VStack(spacing: 0) {
            // Journey planner controls
            journeyControls

            // Content
            // While refreshing, keep showing the journeys already found.
            if !calculator.journeys.isEmpty {
                journeyList
            } else if let error = calculator.error, !calculator.isCalculating {
                ProblemView(title: "No Journeys Found", message: error, systemImage: "calendar.badge.exclamationmark") {
                    Task { await recalculate() }
                }
                .frame(maxHeight: .infinity)
            } else {
                LoadingRows(kind: .journeys, count: 5)
            }
        }
    }

    /// The journey open beside the list: the one chosen, or the first.
    private var chosenJourney: CalculatedJourney? {
        calculator.journeys.first { $0.trainsKey == expandedJourneyKey } ?? calculator.journeys.first
    }

    @ViewBuilder
    private var chosenJourneyPane: some View {
        if let journey = chosenJourney {
            List {
                Section {
                    journeyDetails(journey)
                } header: {
                    Text("\(formatTimeShort(journey.departureTime)) to \(formatTimeShort(journey.arrivalTime))")
                }
            }
            .listStyle(.plain)
        } else {
            ContentUnavailableView(
                "No Journey Chosen",
                systemImage: "arrow.triangle.swap",
                description: Text("Choose a journey to see its trains and connections.")
            )
        }
    }

    // MARK: - Journey Controls

    /// When to leave: a date picker, and a way back to now.
    private var journeyControls: some View {
        HStack(spacing: 12) {
            DatePicker(selection: $departureTime, displayedComponents: [.date, .hourAndMinute]) {
                Label("Leaving", systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            }
            .datePickerStyle(.compact)

            Button("Now") {
                departureTime = Date()
            }
            .buttonStyle(.bordered)
            .disabled(abs(departureTime.timeIntervalSinceNow) < 60)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .onChange(of: departureTime) {
            Task { await recalculate() }
        }
        .sensoryFeedback(.selection, trigger: departureTime)
    }

    private func recalculate() async {
        await calculator.calculateMultiple(route: route, departAt: departureTime)
    }

    /// Earlier and later journeys than the ones listed, as on a journey
    /// planner.
    private var earlierAndLater: some View {
        HStack(spacing: 12) {
            Button {
                departureTime = departureTime.addingTimeInterval(-60 * 60)
            } label: {
                Label("Earlier", systemImage: "chevron.up")
                    .frame(maxWidth: .infinity)
            }
            Button {
                let last = calculator.journeys.last?.departureTime.flatMap(parseTime)
                departureTime = (last ?? departureTime.addingTimeInterval(60 * 60)).addingTimeInterval(60)
            } label: {
                Label("Later", systemImage: "chevron.down")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .listRowSeparator(.hidden)
        .padding(.vertical, 6)
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
                            HStack(spacing: 8) {
                                LiveDot()
                                Text("Tracking live")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            if tracker.updatedLegs.contains(where: { $0.isCancelled }) {
                                Text("A train on this journey has been cancelled")
                                    .font(.caption)
                                    .foregroundStyle(Color.delaySevere)
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

            // Journeys saved from an earlier visit, on screen until fresh ones arrive.
            if let savedAt = calculator.showingSavedFrom {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color.delayModerate)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Saved journeys from \(savedAt, format: .dateTime.hour().minute())")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(calculator.updateFailure.map { "Couldn't update: \($0)" } ?? "Times may have changed since")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if calculator.isCalculating {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            ForEach(calculator.journeys, id: \.id) { journey in
                Section {
                    journeyCard(journey)
                }
            }

            Section {
                earlierAndLater
            }
        }
        .listStyle(.plain)
        .refreshable {
            await recalculate()
        }
    }

    // MARK: - Journey Card

    @ViewBuilder
    private func journeyCard(_ journey: CalculatedJourney) -> some View {
        let isExpanded = expandedJourneyKey == journey.trainsKey
        // Beside the fold the details open in the other half, so the card
        // is chosen rather than expanded.
        let isChosen = spanningFold != nil && chosenJourney?.trainsKey == journey.trainsKey

        // Compact header — always visible
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                // Beside the fold, choosing again keeps it chosen.
                expandedJourneyKey = isExpanded && spanningFold == nil ? nil : journey.trainsKey
            }
        } label: {
            HStack(spacing: 8) {
                // A bar per train: faint while all's well, coloured for a
                // late or cancelled one.
                HStack(spacing: 2) {
                    ForEach(journey.legs) { leg in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(legColor(leg))
                            .frame(width: 4, height: 44)
                    }
                }
                .accessibilityHidden(true)

                HStack(spacing: 0) {
                // Departure time
                VStack(alignment: .leading, spacing: 2) {
                    SplitFlapText(text: formatTimeShort(journey.departureTime), style: .title3, weight: .bold)
                    Text(journey.legs.first?.originName ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: journeyTimeWidth, alignment: .leading)

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
                    SplitFlapText(text: formatTimeShort(journey.arrivalTime), style: .title3, weight: .bold)
                    Text(journey.legs.last?.destinationName ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: journeyTimeWidth, alignment: .trailing)

                Spacer().frame(width: 8)

                // Delay indicator + chevron
                VStack(spacing: 4) {
                    let maxDelay = journey.legs.compactMap { $0.departureDelay ?? $0.arrivalDelay }.max() ?? 0
                    if journey.hasIssues {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.delaySevere)
                    } else if maxDelay > 0 {
                        Text("+\(maxDelay)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.delay(minutes: maxDelay))
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(width: 30)
            }
            } // inner HStack
            // A plain button only answers taps on what it draws; the gaps
            // between the times and around the thin arrow didn't open it.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journeyCard")
        .listRowBackground(isChosen ? Color.accentColor.opacity(0.15) : nil)
        .accessibilityAddTraits(isChosen ? .isSelected : [])

        // Expanded content — full journey details
        if isExpanded && spanningFold == nil {
            journeyDetails(journey)
        }
    }

    /// A journey's trains, the connections between them, and tracking.
    @ViewBuilder
    private func journeyDetails(_ journey: CalculatedJourney) -> some View {
        // Platform & headcode info for each leg
        ForEach(journey.legs) { leg in
            if let connectionMins = leg.connectionMinutes {
                connectionSummary(minutes: connectionMins, stationName: leg.originName)
            }

            NavigationLink(value: AppDestination.service(ServiceRoute(uid: leg.service.uid, runDate: leg.service.runDate))) {
                legSummaryRow(leg)
            }
            .accessibilityIdentifier("journeyLeg")

        }

        // Track button
        if activeTracker == nil || activeTracker?.isTracking != true {
            TrackButton(title: "Track This Journey", isTracking: false) {
                startTracking(journey: journey)
            } stop: {}
        }
    }

    private func legColor(_ leg: CalculatedLeg) -> Color {
        if leg.isCancelled { return .delaySevere }
        if let delay = leg.departureDelay ?? leg.arrivalDelay, delay > 0 { return .delay(minutes: delay) }
        return .secondary.opacity(0.12)
    }

    private func legSummaryRow(_ leg: CalculatedLeg) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Timeline dot
            Circle()
                .fill(leg.isCancelled ? Color.delaySevere : .accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let headcode = leg.service.headcode {
                        Text(headcode)
                            .font(.caption.monospaced())
                            .fontWeight(.semibold)
                    }
                    if let op = leg.service.operator {
                        Text(op.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if leg.isCancelled {
                        Text("CANCELLED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.delaySevere)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                legStop(time: leg.departureTime, name: leg.originName, platform: leg.departurePlatform)
                legStop(time: leg.arrivalTime, name: leg.destinationName, platform: leg.arrivalPlatform)
            }

            Spacer(minLength: 0)

            // Delay badge
            if let delay = leg.departureDelay ?? leg.arrivalDelay, delay > 0 {
                Text("+\(delay)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.delay(minutes: delay).opacity(0.15))
                    .foregroundStyle(Color.delay(minutes: delay))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .opacity(leg.isCancelled ? 0.5 : 1.0)
    }

    /// One end of a train: time, station, platform.
    private func legStop(time: String?, name: String, platform: String?) -> some View {
        HStack(spacing: 6) {
            Text(time.map { formatTimeShort($0) } ?? "--:--")
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
            PlatformBadge(number: platform, compact: true)
        }
    }

    @ViewBuilder
    private func connectionSummary(minutes: Int, stationName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.caption2)
                .foregroundStyle(minutes < 5 ? Color.delayModerate : Color.onTime)
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
                trackingError = "Couldn't start tracking: \(error.friendlyDescription)"
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
}
