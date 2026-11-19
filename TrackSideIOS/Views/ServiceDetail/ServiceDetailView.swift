import SwiftUI

struct ServiceDetailView: View {
    let uid: String
    let runDate: String
    let liveClient: LiveClient

    @Environment(ActiveJourneyManager.self) private var journeyManager
    @State private var service: ServiceDetailService
    @State private var trackingError: String?

    init(uid: String, runDate: String, liveClient: LiveClient) {
        self.uid = uid
        self.runDate = runDate
        self.liveClient = liveClient
        self._service = State(initialValue: ServiceDetailService(liveClient: liveClient))
    }

    var body: some View {
        Group {
            if let detail = service.detail {
                serviceContent(detail)
            } else if let error = service.error {
                ProblemView(title: "Can't Load This Train", message: error) {
                    Task { await service.loadService(uid: uid, date: runDate) }
                }
            } else {
                // Shown from the start, before loading begins as well as
                // during it. With nothing to show, the group is empty and
                // `.task` never runs, so the page stays blank.
                LoadingRows(kind: .train)
            }
        }
        .task {
            await service.loadService(uid: uid, date: runDate)
        }
        .onDisappear {
            service.stopLive()
        }
        .sensoryFeedback(trigger: journeyManager.isTracking) { _, tracking in
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

    // MARK: - Main Content

    @Environment(\.spanningFold) private var spanningFold
    /// How far down the fold runs, when the phone is half-folded with the
    /// fold across the screen (tabletop): the top half becomes a platform
    /// display.
    @State private var tabletopFold: CGFloat?

    /// The train on one list, or, with both halves of an unfolded iPhone
    /// Duo, on two: about the train on one side of the fold, its stops on
    /// the other.
    private func serviceContent(_ detail: ServiceDetail) -> some View {
        VStack(spacing: 0) {
            if let fold = tabletopFold {
                PlatformDisplay(detail: detail)
                    .frame(height: max(0, fold - 20))
                // The crease itself, and its margins either side.
                Color.clear.frame(height: 40)
            }
            serviceLists(detail)
        }
        .onGeometryChange(for: CGFloat?.self) { proxy in
            Self.tabletopFold(in: proxy)
        } action: { fold in
            tabletopFold = fold
        }
    }

    /// Where a fold across the screen starts, if the phone is bent at it.
    private static func tabletopFold(in proxy: GeometryProxy) -> CGFloat? {
        #if DEBUG
        // The simulator lies flat and won't turn its inner screen sideways,
        // so UI tests pretend: a fold halfway down, bent.
        if ProcessInfo.processInfo.arguments.contains("-UITestTabletop") {
            return proxy.size.height / 2
        }
        #endif
        guard #available(iOS 27.1, *) else { return nil }
        guard let fold = proxy.reservedRegions(kind: .division).first(where: \.isActive),
              fold.frame.width > fold.frame.height,
              fold.frame.minY >= 200,
              fold.frame.minY <= proxy.size.height - 200
        else { return nil }
        return fold.frame.minY
    }

    @ViewBuilder
    private func serviceLists(_ detail: ServiceDetail) -> some View {
        Group {
            if let fold = spanningFold {
                HStack(spacing: 0) {
                    List {
                        summarySections(detail)
                    }
                    .listStyle(.plain)
                    .clearOfFold(.trailing)
                    .frame(width: fold)

                    List {
                        stopSections(detail)
                    }
                    .listStyle(.plain)
                    .clearOfFold(.leading)
                }
            } else {
                List {
                    summarySections(detail)
                    stopSections(detail)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(detail.headcode ?? detail.uid)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await service.loadService(uid: uid, date: runDate)
        }
    }

    /// About the train: where it is, how it's running, why, and what it
    /// joins or becomes.
    @ViewBuilder
    private func summarySections(_ detail: ServiceDetail) -> some View {
        // Header + Progress
        Section {
            headerView(detail)
        }

        // Quick stats
        Section {
            statsGrid(detail)
        }

        // Track button
        Section {
            trackButton(detail)
        }

        // Associations (joins, divides, next trains)
        if let associations = detail.associations, !associations.isEmpty {
            Section {
                ForEach(associations, id: \.service.id) { assoc in
                    associationRow(assoc)
                }
            } header: {
                Text("Connections")
            }
        }

        // Cancel/late reason detail
        if detail.cancelReason != nil || detail.lateReason != nil {
            Section {
                disruptionInfo(detail)
            } header: {
                Text("Disruption")
            }
        }
    }

    /// Where the train stops, and where it passes.
    @ViewBuilder
    private func stopSections(_ detail: ServiceDetail) -> some View {
        // Calling points
        Section {
            let callingStops = callingPointStops(detail)
            ForEach(Array(callingStops.enumerated()), id: \.element.stop.id) { index, entry in
                StopRow(
                    stop: entry.stop,
                    isCurrentPosition: entry.isCurrent,
                    isFirst: index == 0,
                    isLast: index == callingStops.count - 1,
                    isPassed: entry.isPassed
                )
            }
        } header: {
            HStack {
                Text("Calling Points")
                Spacer()
                let stats = stopStats(detail)
                if stats.remaining > 0 && stats.remaining < stats.total {
                    Text("\(stats.remaining) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        // Pass stops (collapsed)
        let passes = detail.stops.filter { $0.kind == .pass }
        if !passes.isEmpty {
            Section {
                DisclosureGroup("Passing Points (\(passes.count))") {
                    ForEach(passes) { stop in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text(stop.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let passTime = stop.pass {
                                TimeDisplay(passTime, showDelay: false, style: .caption)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerView(_ detail: ServiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Headcode, status, operator
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let headcode = detail.headcode {
                            Text(headcode)
                                .font(.title.monospaced())
                                .fontWeight(.bold)
                        }
                        Text(detail.uid)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    // Origin → Destination
                    HStack(spacing: 6) {
                        Text(detail.originName)
                            .fontWeight(.medium)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(detail.destinationName)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }

                Spacer()

                StatusBadge(
                    status: detail.status,
                    delayMinutes: currentDelay(detail),
                    cancelled: detail.isCancelled,
                    lateReason: detail.lateReason
                )
            }

            // Destination ETA card
            destinationETA(detail)

            // Operator and metadata chips
            HStack(spacing: 8) {
                if let op = detail.operator {
                    Label(op.name, systemImage: "building.2")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let powerType = detail.powerType {
                    Label(formatPowerType(powerType), systemImage: "bolt.fill")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if let category = detail.category {
                    Text(category)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Progress bar
            if detail.status == .running || detail.status == .activated {
                trainProgressBar(detail)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Destination ETA

    @ViewBuilder
    private func destinationETA(_ detail: ServiceDetail) -> some View {
        let destStop = detail.stops.last(where: { $0.kind == .destination || $0.terminatesHere == true })
            ?? detail.stops.last

        if let destStop, let arrival = destStop.arrival {
            let scheduled = formatTimeForETA(arrival.`public` ?? arrival.working ?? "")
            let live = (arrival.actual ?? arrival.estimated).map { formatTimeForETA($0) }
            let delay = arrival.delayMinutes ?? 0
            let hasArrived = arrival.actual != nil

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasArrived ? "Arrived" : "Expected arrival")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if let live, live != scheduled && !hasArrived {
                            Text(scheduled)
                                .font(.title3)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            SplitFlapText(text: live, style: .title3, weight: .bold,
                                          color: SplitFlap.ink(delayMinutes: delay))
                        } else {
                            SplitFlapText(text: hasArrived ? (live ?? scheduled) : scheduled,
                                          style: .title3, weight: .bold,
                                          color: hasArrived ? Color(red: 0.45, green: 0.9, blue: 0.5) : SplitFlap.ink)
                        }
                    }
                    .monospacedDigit()
                }

                Spacer()

                if delay > 0 && !hasArrived {
                    Text("+\(delay) min")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.delay(minutes: delay).opacity(0.15))
                        .foregroundStyle(Color.delay(minutes: delay))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if hasArrived {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.onTime)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func formatTimeForETA(_ timeString: String) -> String {
        if timeString.count > 10, let tIndex = timeString.firstIndex(of: "T") {
            let afterT = timeString[timeString.index(after: tIndex)...]
            return String(afterT.prefix(5))
        }
        return String(timeString.prefix(5))
    }

    // MARK: - Progress Bar

    @ViewBuilder
    private func trainProgressBar(_ detail: ServiceDetail) -> some View {
        let stats = stopStats(detail)
        let progress = stats.total > 0 ? Double(stats.passed) / Double(stats.total) : 0

        VStack(spacing: 6) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(.secondary.opacity(0.15))
                        .frame(height: 6)

                    // Fill
                    Capsule()
                        .fill(progressColor(delay: currentDelay(detail)))
                        .frame(width: max(6, geo.size.width * progress), height: 6)
                }
            }
            .frame(height: 6)

            // Position label
            HStack {
                if let currentStop = detail.stops.last(where: { $0.atPlatform == true }) {
                    Label("At \(currentStop.name)", systemImage: "tram.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                } else if let approaching = detail.stops.last(where: { $0.approaching == true }) {
                    Label("Approaching \(approaching.name)", systemImage: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.delayModerate)
                } else if stats.passed > 0 {
                    Text("\(stats.passed) of \(stats.total) stops completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if stats.remaining > 0 {
                    Text("\(stats.remaining) stops to go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if detail.status == .terminated {
                    Text("Journey complete")
                        .font(.caption)
                        .foregroundStyle(Color.onTime)
                }
            }
        }
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private func statsGrid(_ detail: ServiceDetail) -> some View {
        let stats = stopStats(detail)
        let duration = journeyDuration(detail)
        let delay = currentDelay(detail) ?? 0

        HStack(spacing: 0) {
            // Duration
            statCell(
                value: duration.map { formatDuration($0) } ?? "--",
                label: "Duration",
                icon: "clock",
                color: .accentColor
            )

            Divider()
                .frame(height: 40)

            // Calling stops
            statCell(
                value: "\(stats.total)",
                label: stats.total == 1 ? "Stop" : "Stops",
                icon: "mappin.circle",
                color: .accentColor
            )

            Divider()
                .frame(height: 40)

            // Delay
            statCell(
                value: delay > 0 ? "+\(delay)m" : "On time",
                label: delay > 0 ? "Late" : "Status",
                icon: delay > 0 ? "clock.badge.exclamationmark" : "checkmark.circle",
                color: delay > 0 ? .delay(minutes: delay) : .onTime
            )
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Track Button

    private func trackButton(_ detail: ServiceDetail) -> some View {
        TrackButton(title: "Track This Train", isTracking: journeyManager.isTracking) {
            Task {
                do {
                    try await journeyManager.startTracking(journey: buildJourney(from: detail))
                } catch {
                    trackingError = "Couldn't start tracking: \(error.friendlyDescription)"
                }
            }
        } stop: {
            journeyManager.stopTracking()
        }
    }

    /// Build a single-leg CalculatedJourney from a ServiceDetail for ad-hoc tracking
    private func buildJourney(from detail: ServiceDetail) -> CalculatedJourney {
        let originStop = detail.stops.first(where: { $0.kind == .origin || $0.startsHere == true }) ?? detail.stops.first
        let destStop = detail.stops.last(where: { $0.kind == .destination || $0.terminatesHere == true }) ?? detail.stops.last

        let boardService = BoardService(
            uid: detail.uid,
            runDate: detail.runDate,
            headcode: detail.headcode,
            operator: detail.operator,
            isPassenger: detail.isPassenger,
            status: detail.status,
            origin: detail.origin,
            destination: detail.destination,
            cancelReasonCode: detail.cancelReasonCode,
            cancelReasonCodeDescription: detail.cancelReasonCodeDescription,
            cancelReason: detail.cancelReason,
            lateReason: detail.lateReason,
            plannedCancel: detail.plannedCancel,
            stop: originStop ?? detail.stops[0]
        )

        let leg = CalculatedLeg(
            legIndex: 0,
            service: boardService,
            serviceDetail: detail,
            originName: originStop?.name ?? detail.originName,
            destinationName: destStop?.name ?? detail.destinationName,
            destinationCode: destStop?.crs ?? destStop?.tiploc ?? detail.destination.first?.tiploc ?? "",
            departureTime: originStop?.departure?.bestTime ?? originStop?.departure?.`public`,
            arrivalTime: destStop?.arrival?.bestTime ?? destStop?.arrival?.`public`,
            departurePlatform: originStop?.platform?.displayPlatform,
            arrivalPlatform: destStop?.platform?.displayPlatform,
            departureDelay: originStop?.departure?.delayMinutes,
            arrivalDelay: destStop?.arrival?.delayMinutes,
            isCancelled: detail.isCancelled,
            connectionMinutes: nil
        )

        return CalculatedJourney(
            legs: [leg],
            departureTime: leg.departureTime,
            arrivalTime: leg.arrivalTime,
            requestedTime: Date()
        )
    }

    // MARK: - Association Row

    @ViewBuilder
    private func associationRow(_ assoc: Association) -> some View {
        NavigationLink {
            ServiceDetailView(
                uid: assoc.service.uid,
                runDate: assoc.service.runDate,
                liveClient: liveClient
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: associationIcon(assoc.type))
                    .foregroundStyle(assoc.cancelled ? Color.delaySevere : .accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(associationLabel(assoc))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 6) {
                        if let headcode = assoc.service.headcode {
                            Text(headcode)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(assoc.service.destinationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if assoc.cancelled {
                        Text("Cancelled")
                            .font(.caption2)
                            .foregroundStyle(Color.delaySevere)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .opacity(assoc.cancelled ? 0.6 : 1.0)
        }
    }

    // MARK: - Disruption Info

    @ViewBuilder
    private func disruptionInfo(_ detail: ServiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cancelReason = detail.cancelReason {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.delaySevere)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cancellation Reason")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(cancelReason)
                            .font(.subheadline)
                    }
                }
            }
            if let lateReason = detail.lateReason {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(Color.delayModerate)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delay Reason")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(lateReason)
                            .font(.subheadline)
                    }
                }
            }
            if let code = detail.cancelReasonCode {
                Text("Code: \(code)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private struct StopEntry {
        let stop: Stop
        let isPassed: Bool
        let isCurrent: Bool
    }

    private func callingPointStops(_ detail: ServiceDetail) -> [StopEntry] {
        let callingStops = detail.stops.filter { $0.kind != .pass }
        return callingStops.map { stop in
            let isPassed: Bool = {
                if stop.kind == .destination || stop.terminatesHere == true {
                    return stop.arrival?.actual != nil
                }
                return stop.departure?.actual != nil
            }()
            let isCurrent = stop.atPlatform == true || stop.approaching == true
            return StopEntry(stop: stop, isPassed: isPassed, isCurrent: isCurrent)
        }
    }

    private struct StopStats {
        let total: Int
        let passed: Int
        let remaining: Int
    }

    private func stopStats(_ detail: ServiceDetail) -> StopStats {
        let callingStops = detail.stops.filter { $0.kind != .pass }
        let passed = callingStops.filter { stop in
            if stop.kind == .destination || stop.terminatesHere == true {
                return stop.arrival?.actual != nil
            }
            return stop.departure?.actual != nil
        }.count
        return StopStats(total: callingStops.count, passed: passed, remaining: callingStops.count - passed)
    }

    private func currentDelay(_ detail: ServiceDetail) -> Int? {
        for stop in detail.stops.reversed() {
            if let dep = stop.departure, dep.actual != nil, let delay = dep.delayMinutes {
                return delay
            }
            if let arr = stop.arrival, arr.actual != nil, let delay = arr.delayMinutes {
                return delay
            }
        }
        return nil
    }

    private func journeyDuration(_ detail: ServiceDetail) -> Int? {
        guard let originDep = detail.stops.first?.departure?.`public` ?? detail.stops.first?.departure?.working,
              let destArr = detail.stops.last?.arrival?.`public` ?? detail.stops.last?.arrival?.working,
              let start = parseTime(originDep),
              let end = parseTime(destArr) else { return nil }
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 { return "\(hours)h\(mins > 0 ? " \(mins)m" : "")" }
        return "\(mins)m"
    }

    private func progressColor(delay: Int?) -> Color {
        guard let delay, delay > 0 else { return .signalGreen }
        if delay >= 10 { return .delaySevere }
        if delay >= 5 { return .delayModerate }
        return .yellow
    }

    private func formatPowerType(_ powerType: String) -> String {
        switch powerType.uppercased() {
        case "EMU": return "Electric"
        case "DMU": return "Diesel"
        case "HST": return "High Speed"
        case "D": return "Diesel Loco"
        case "E": return "Electric Loco"
        case "ED": return "Electro-Diesel"
        default: return powerType
        }
    }

    private func associationIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "join": return "arrow.triangle.merge"
        case "divide", "split": return "arrow.triangle.branch"
        case "next": return "arrow.right.circle"
        default: return "link"
        }
    }

    private func associationLabel(_ assoc: Association) -> String {
        let verb: String
        switch assoc.type.lowercased() {
        case "join": verb = "Joins with"
        case "divide", "split": verb = "Divides at"
        case "next": verb = "Continues as"
        default: verb = assoc.type.capitalized
        }
        return "\(verb) \(assoc.location.name)"
    }
}
