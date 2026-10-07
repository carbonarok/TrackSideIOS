import SwiftUI

struct ServiceDetailView: View {
    let uid: String
    let runDate: String
    let liveClient: LiveClient

    @State private var service: ServiceDetailService
    @State private var liveActivityService: LiveActivityService
    @State private var trackingError: String?

    init(uid: String, runDate: String, liveClient: LiveClient) {
        self.uid = uid
        self.runDate = runDate
        self.liveClient = liveClient
        self._service = State(initialValue: ServiceDetailService(liveClient: liveClient))
        self._liveActivityService = State(initialValue: LiveActivityService(liveClient: liveClient))
    }

    var body: some View {
        Group {
            if let detail = service.detail {
                serviceContent(detail)
            } else if service.isLoading {
                ProgressView("Loading service...")
            } else if let error = service.error {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await service.loadService(uid: uid, date: runDate) }
                    }
                }
            }
        }
        .task {
            await service.loadService(uid: uid, date: runDate)
        }
        .onDisappear {
            service.stopLive()
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

    @ViewBuilder
    private func serviceContent(_ detail: ServiceDetail) -> some View {
        List {
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
                                    TimeDisplay(passTime, showDelay: false)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .font(.subheadline)
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
        .listStyle(.plain)
        .navigationTitle(detail.headcode ?? detail.uid)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await service.loadService(uid: uid, date: runDate)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerView(_ detail: ServiceDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Operator color accent bar
            if let op = detail.operator {
                RoundedRectangle(cornerRadius: 2)
                    .fill(op.brandColor)
                    .frame(height: 4)
            }

            // Headcode, status, operator
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let headcode = detail.headcode {
                            Text(headcode)
                                .font(.title)
                                .fontWeight(.bold)
                                .monospaced()
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
                        .background(op.brandColor.opacity(0.12))
                        .foregroundStyle(op.brandColor)
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
                            Text(live)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(delay >= 10 ? .red : delay >= 5 ? .orange : .yellow)
                        } else {
                            Text(hasArrived ? (live ?? scheduled) : scheduled)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(hasArrived ? .green : .primary)
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
                        .background(delay >= 10 ? .red.opacity(0.15) : delay >= 5 ? .orange.opacity(0.15) : .yellow.opacity(0.15))
                        .foregroundStyle(delay >= 10 ? .red : delay >= 5 ? .orange : .yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if hasArrived {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
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
                        .foregroundStyle(.blue)
                } else if let approaching = detail.stops.last(where: { $0.approaching == true }) {
                    Label("Approaching \(approaching.name)", systemImage: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
                        .foregroundStyle(.green)
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
                color: .blue
            )

            Divider()
                .frame(height: 40)

            // Calling stops
            statCell(
                value: "\(stats.total)",
                label: stats.total == 1 ? "Stop" : "Stops",
                icon: "mappin.circle",
                color: .purple
            )

            Divider()
                .frame(height: 40)

            // Delay
            statCell(
                value: delay > 0 ? "+\(delay)" : "0",
                label: delay > 0 ? "Min Late" : "On Time",
                icon: delay > 0 ? "clock.badge.exclamationmark" : "checkmark.circle",
                color: delay > 0 ? (delay >= 10 ? .red : .orange) : .green
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

    @ViewBuilder
    private func trackButton(_ detail: ServiceDetail) -> some View {
        let serviceKey = detail.id
        let isTracking = liveActivityService.isTracking(serviceKey)

        Button {
            if isTracking {
                liveActivityService.stopTracking(key: serviceKey)
            } else {
                do {
                    let destCRS = detail.destination.first?.crs
                    try liveActivityService.startTracking(service: detail, destinationCRS: destCRS)
                } catch {
                    trackingError = "Could not start tracking: \(error.localizedDescription)"
                }
            }
        } label: {
            HStack {
                Image(systemName: isTracking ? "stop.circle.fill" : "location.fill")
                    .foregroundStyle(isTracking ? .red : .blue)
                Text(isTracking ? "Stop Tracking" : "Track This Train")
                    .fontWeight(.medium)
                Spacer()
                if isTracking {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
        .padding(.vertical, 4)
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
                    .foregroundStyle(assoc.cancelled ? .red : .blue)
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
                            .foregroundStyle(.red)
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
                        .foregroundStyle(.red)
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
                        .foregroundStyle(.orange)
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
        guard let delay, delay > 0 else { return .green }
        if delay >= 10 { return .red }
        if delay >= 5 { return .orange }
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
