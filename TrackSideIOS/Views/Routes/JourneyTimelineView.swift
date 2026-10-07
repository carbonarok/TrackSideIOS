import SwiftUI

/// Navigation target for service detail
private struct ServiceNavTarget: Hashable {
    let uid: String
    let runDate: String
}

struct JourneyTimelineView: View {
    let journey: CalculatedJourney
    let liveClient: LiveClient
    var tracker: JourneyTracker?
    var onTrackJourney: (() -> Void)?
    var onStopTracking: (() -> Void)?

    @State private var selectedService: ServiceNavTarget?

    /// Use tracked legs if available, otherwise fall back to calculated journey legs
    private var displayLegs: [CalculatedLeg] {
        tracker?.updatedLegs ?? journey.legs
    }

    private var currentLegIndex: Int? {
        tracker?.isTracking == true ? tracker?.currentLegIndex : nil
    }

    var body: some View {
        List {
            // Tracking controls
            Section {
                trackingControls
            }

            // Journey summary header
            Section {
                journeySummary
            }

            // Timeline
            ForEach(displayLegs) { leg in
                // Connection wait (between legs)
                if let connectionMins = leg.connectionMinutes {
                    Section {
                        connectionRow(minutes: connectionMins, stationName: leg.originName, legIndex: leg.legIndex)
                    }
                }

                // Leg section
                Section {
                    legRow(leg)
                } header: {
                    HStack {
                        Text("Leg \(leg.legIndex + 1)")
                        if let current = currentLegIndex, leg.legIndex == current {
                            Text("CURRENT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(item: $selectedService) { target in
            ServiceDetailView(
                uid: target.uid,
                runDate: target.runDate,
                liveClient: liveClient
            )
        }
    }

    // MARK: - Tracking Controls

    @ViewBuilder
    private var trackingControls: some View {
        if tracker?.isTracking == true {
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
                    if let tracker, tracker.updatedLegs.contains(where: { $0.isCancelled }) {
                        Text("A train on this journey has been cancelled")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                Button("Stop") {
                    onStopTracking?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
            .padding(.vertical, 4)
        } else if onTrackJourney != nil {
            Button {
                onTrackJourney?()
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Track Journey")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var journeySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Origin → Destination
            HStack {
                if let first = journey.legs.first, let last = journey.legs.last {
                    Text(first.originName)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(last.destinationName)
                        .fontWeight(.semibold)
                }
            }

            // Times
            HStack(spacing: 16) {
                if let dep = journey.departureTime {
                    VStack(alignment: .leading) {
                        Text("Depart")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatTimeShort(dep))
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                }
                if let arr = journey.arrivalTime {
                    VStack(alignment: .leading) {
                        Text("Arrive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatTimeShort(arr))
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                }
                Spacer()
                if let totalMins = journey.totalMinutes {
                    VStack(alignment: .trailing) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatDuration(totalMins))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Stats
            HStack(spacing: 12) {
                Label("\(journey.totalLegs) train\(journey.totalLegs == 1 ? "" : "s")", systemImage: "tram.fill")
                if journey.legs.count > 1 {
                    Label("\(journey.legs.count - 1) change\(journey.legs.count - 1 == 1 ? "" : "s")", systemImage: "arrow.triangle.swap")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if journey.hasIssues {
                Label("Some trains on this journey are cancelled", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Connection Row

    @ViewBuilder
    private func connectionRow(minutes: Int, stationName: String, legIndex: Int = 0) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(connectionRiskColor(minutes))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Change at \(stationName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(minutes) min connection")
                        .font(.caption)
                        .foregroundStyle(connectionRiskColor(minutes))
                }

                Spacer()

                if let current = currentLegIndex, legIndex == current {
                    Text("NOW")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    connectionRiskBadge(minutes)
                }
            }

            // Risk meter bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.1))
                        .frame(height: 4)
                    Capsule()
                        .fill(connectionRiskColor(minutes))
                        .frame(width: max(4, geo.size.width * (1.0 - min(Double(minutes), 15) / 15.0)), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
    }

    private func connectionRiskBadge(_ minutes: Int) -> some View {
        let (label, icon) = connectionRiskInfo(minutes)
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(connectionRiskColor(minutes))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(connectionRiskColor(minutes).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func connectionRiskInfo(_ minutes: Int) -> (String, String) {
        if minutes < 3 {
            return ("Very tight", "exclamationmark.triangle.fill")
        } else if minutes < 5 {
            return ("Tight", "exclamationmark.triangle")
        } else if minutes < 8 {
            return ("OK", "checkmark.circle")
        } else {
            return ("Comfortable", "checkmark.circle.fill")
        }
    }

    private func connectionRiskColor(_ minutes: Int) -> Color {
        if minutes < 3 { return .red }
        if minutes < 5 { return .orange }
        if minutes < 8 { return .yellow }
        return .green
    }

    // MARK: - Leg Row

    @ViewBuilder
    private func legRow(_ leg: CalculatedLeg) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Departure
            HStack(alignment: .top, spacing: 12) {
                // Timeline dot
                VStack(spacing: 0) {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 2, height: 40)
                }
                .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(leg.originName)
                            .font(.body)
                            .fontWeight(.semibold)
                        Spacer()
                        if let time = leg.departureTime {
                            Text(formatTimeShort(time))
                                .font(.body)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                    }

                    HStack(spacing: 8) {
                        if let plat = leg.departurePlatform {
                            platformChip(plat)
                        }
                        if let delay = leg.departureDelay, delay > 0 {
                            Text("+\(delay) min")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(delay >= 10 ? .red.opacity(0.15) : .orange.opacity(0.15))
                                .foregroundStyle(delay >= 10 ? .red : .orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }

            // Train info
            HStack(alignment: .center, spacing: 12) {
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 9)

                HStack(spacing: 8) {
                    if let headcode = leg.service.headcode {
                        Text(headcode)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
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
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    // Live position indicator
                    if let detail = tracker?.legDetails[leg.legIndex] {
                        if let liveStop = detail.stops.last(where: { $0.atPlatform == true }) {
                            Text("At \(liveStop.name)")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .fontWeight(.semibold)
                        } else if let liveStop = detail.stops.last(where: { $0.approaching == true }) {
                            Text("Approaching \(liveStop.name)")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding(.vertical, 8)

                Spacer()

                Button {
                    selectedService = ServiceNavTarget(
                        uid: leg.service.uid,
                        runDate: leg.service.runDate
                    )
                } label: {
                    Text("Details")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .frame(minHeight: 36)

            // Arrival
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                    .padding(.leading, 4)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(leg.destinationName)
                            .font(.body)
                            .fontWeight(.semibold)
                        Spacer()
                        if let time = leg.arrivalTime {
                            Text(formatTimeShort(time))
                                .font(.body)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        } else {
                            Text("--:--")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        if let plat = leg.arrivalPlatform {
                            platformChip(plat)
                        }
                        if let delay = leg.arrivalDelay, delay > 0 {
                            Text("+\(delay) min")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(delay >= 10 ? .red.opacity(0.15) : .orange.opacity(0.15))
                                .foregroundStyle(delay >= 10 ? .red : .orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(leg.isCancelled ? 0.5 : 1.0)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func platformChip(_ platform: String) -> some View {
        HStack(spacing: 2) {
            Text("Plat")
                .font(.caption2)
            Text(platform)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.blue.opacity(0.1))
        .foregroundStyle(.blue)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func formatTimeShort(_ timeString: String) -> String {
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
