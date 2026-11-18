import ActivityKit
import SwiftUI
import WidgetKit

struct LegLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LegActivityAttributes.self) { context in
            LegLockScreenView(context: context)
                .widgetURL(URL(string: "trackside://service?uid=\(context.attributes.uid)&date=\(context.attributes.runDate)"))
        } dynamicIsland: { context in
            let state = context.state
            let attrs = context.attributes

            return DynamicIsland {
                // MARK: - Expanded

                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attrs.headcode)
                            .font(.caption)
                            .fontWeight(.bold)

                        if attrs.totalLegs > 1 {
                            Text("Leg \(attrs.legIndex + 1)/\(attrs.totalLegs)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        delayBadge(state)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 6) {
                        if let p = state.departurePlatform {
                            compactPlatform("D", p, state.departurePlatformChanged)
                        }
                        if let p = state.arrivalPlatform {
                            compactPlatform("A", p, state.arrivalPlatformChanged)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 4) {
                        Text(attrs.originName)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(attrs.destinationName)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if state.isCancelled {
                            Text("CANCELLED")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.red)
                        } else if state.phase == "boarding", let depDate = state.departureDate, depDate > state.lastUpdated {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                Text(depDate, style: .relative)
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .foregroundStyle(.blue)
                        } else if state.phase == "boarding" {
                            Text("Departing")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        } else if state.phase == "onTrain", let arrDate = state.arrivalDate, arrDate > state.lastUpdated {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                Text("Arr")
                                    .font(.caption2)
                                Text(arrDate, style: .relative)
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            .foregroundStyle(.green)
                        } else if state.phase == "onTrain" {
                            Text("Arriving")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        } else if state.phase == "arrived" {
                            Text("Arrived")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        } else if state.phase == "upcoming", let conn = state.connectionMinutes {
                            Text("\(conn) min connection")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        if let scheduled = state.scheduledArrival {
                            HStack(spacing: 2) {
                                Text("Arr")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let expected = state.expectedArrival {
                                    Text(scheduled)
                                        .font(.caption)
                                        .monospacedDigit()
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                    Text(expected)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(scheduled)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }

            } compactLeading: {
                let arriving = state.phase == "onTrain" || state.phase == "arrived"
                let expected = arriving ? state.expectedArrival : state.expectedDeparture
                let scheduled = arriving ? state.scheduledArrival : state.scheduledDeparture
                CompactIslandLabel(
                    text: expected ?? scheduled ?? attrs.headcode,
                    systemImage: phaseIcon(state.phase),
                    textColor: expected != nil ? .orange : .primary,
                    iconColor: phaseColor(state)
                )
            } compactTrailing: {
                if state.isCancelled {
                    Text("CANC")
                        .compactIslandText()
                        .foregroundStyle(.red)
                } else if state.phase == "arrived" {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if state.phase == "boarding", let depDate = state.departureDate, depDate > state.lastUpdated {
                    Text(depDate, style: .timer)
                        .compactIslandText()
                        .frame(maxWidth: 56)
                } else if let maxDelay = [state.departureDelayMinutes, state.arrivalDelayMinutes].max(), maxDelay > 0 {
                    Text("+\(maxDelay)m")
                        .compactIslandText()
                        .foregroundStyle(.orange)
                } else if let p = state.phase == "boarding" ? state.departurePlatform : state.arrivalPlatform {
                    Text("P\(p)")
                        .compactIslandText()
                } else {
                    Image(systemName: "tram.fill")
                        .font(.caption2)
                }
            } minimal: {
                Image(systemName: phaseIcon(state.phase))
                    .font(.caption2)
                    .foregroundStyle(phaseColor(state))
            }
        }
        .supplementalActivityFamilies([.small])
    }

    // MARK: - Helpers

    @ViewBuilder
    private func delayBadge(_ state: LegActivityAttributes.ContentState) -> some View {
        let delay = max(state.departureDelayMinutes, state.arrivalDelayMinutes)
        if state.isCancelled {
            Text("CANC")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.red)
        } else if delay > 0 {
            Text("+\(delay)m")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(delay >= 10 ? .red : .orange)
        }
    }

    private func compactPlatform(_ label: String, _ platform: String, _ changed: Bool) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(changed ? .red : .secondary)
            Text(platform)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(changed ? .red : .primary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(changed ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
        )
    }

    private func phaseIcon(_ phase: String) -> String {
        switch phase {
        case "upcoming": return "clock"
        case "boarding": return "figure.stand"
        case "onTrain": return "tram.fill"
        case "arrived": return "checkmark.circle.fill"
        default: return "tram.fill"
        }
    }

    private func phaseColor(_ state: LegActivityAttributes.ContentState) -> Color {
        if state.isCancelled { return .red }
        switch state.phase {
        case "upcoming": return .secondary
        case "boarding": return .blue
        case "onTrain": return .green
        case "arrived": return .green
        default: return .primary
        }
    }
}

// MARK: - Lock Screen View

private struct LegLockScreenView: View {
    let context: ActivityViewContext<LegActivityAttributes>
    @Environment(\.activityFamily) var activityFamily

    private var state: LegActivityAttributes.ContentState { context.state }
    private var attrs: LegActivityAttributes { context.attributes }

    var body: some View {
        switch activityFamily {
        case .small:
            watchLayout
        default:
            // The unfolded iPhone Duo's lock screen is about twice as wide;
            // there the leg reads across, from departure to arrival.
            ViewThatFits(in: .horizontal) {
                wideLayout
                phoneLayout
            }
        }
    }

    // MARK: - Watch Layout (Smart Stack)

    @ViewBuilder
    private var watchLayout: some View {
        HStack(spacing: 8) {
            // Left: headcode + status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(attrs.headcode)
                        .font(.headline)
                        .fontWeight(.bold)

                    let delay = max(state.departureDelayMinutes, state.arrivalDelayMinutes)
                    if state.isCancelled {
                        Text("CANC")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    } else if delay > 0 {
                        Text("+\(delay)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(delay >= 10 ? .red : .orange)
                    }
                }

                // Countdown or status
                if state.phase == "boarding", let depDate = state.departureDate, depDate > state.lastUpdated {
                    Text(depDate, style: .relative)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                } else if state.phase == "boarding" {
                    Text("Departing")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else if state.phase == "onTrain", let arrDate = state.arrivalDate, arrDate > state.lastUpdated {
                    HStack(spacing: 2) {
                        Text("Arr")
                            .font(.system(size: 9))
                        Text(arrDate, style: .relative)
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.green)
                } else if state.phase == "onTrain" {
                    Text("Arriving")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if state.phase == "upcoming" {
                    Text("Upcoming")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if state.phase == "arrived" {
                    Text("Arrived")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            Spacer(minLength: 0)

            // Right: platforms
            HStack(spacing: 4) {
                if let p = state.departurePlatform {
                    VStack(spacing: 0) {
                        Text("D")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(state.departurePlatformChanged ? .red : .secondary)
                        Text(p)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundStyle(state.departurePlatformChanged ? .red : .primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(state.departurePlatformChanged ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
                    )
                }
                if let p = state.arrivalPlatform {
                    VStack(spacing: 0) {
                        Text("A")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(state.arrivalPlatformChanged ? .red : .secondary)
                        Text(p)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundStyle(state.arrivalPlatformChanged ? .red : .primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(state.arrivalPlatformChanged ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Phone Layout (Lock Screen)

    // MARK: - Wide Layout (unfolded iPhone Duo)

    private var wideLayout: some View {
        HStack(alignment: .center, spacing: 24) {
            endpoint(
                label: "Departs",
                station: attrs.originName,
                scheduled: state.scheduledDeparture,
                expected: state.expectedDeparture,
                platform: state.departurePlatform,
                platformChanged: state.departurePlatformChanged,
                alignment: .leading
            )

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(attrs.headcode)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(attrs.operatorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Rectangle().fill(.secondary.opacity(0.4)).frame(height: 1)
                    Image(systemName: phaseIcon)
                        .foregroundStyle(phaseColor)
                    Rectangle().fill(.secondary.opacity(0.4)).frame(height: 1)
                }
                wideStatus
                if attrs.totalLegs > 1 {
                    Text("Leg \(attrs.legIndex + 1) of \(attrs.totalLegs)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 200)

            endpoint(
                label: "Arrives",
                station: attrs.destinationName,
                scheduled: state.scheduledArrival,
                expected: state.expectedArrival,
                platform: state.arrivalPlatform,
                platformChanged: state.arrivalPlatformChanged,
                alignment: .trailing
            )
        }
        .padding(16)
        // Only where it has this much room; otherwise the phone layout.
        .frame(minWidth: 560)
    }

    @ViewBuilder
    private var wideStatus: some View {
        if state.isCancelled {
            Text("Cancelled")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
        } else if state.phase == "boarding", let depDate = state.departureDate, depDate > state.lastUpdated {
            Text("Leaves \(depDate, style: .relative)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.blue)
        } else if state.phase == "onTrain", let arrDate = state.arrivalDate, arrDate > state.lastUpdated {
            Text("Arrives \(arrDate, style: .relative)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.green)
        } else if state.phase == "arrived" {
            Text("Arrived")
                .font(.subheadline)
                .foregroundStyle(.green)
        } else if let delay = [state.departureDelayMinutes, state.arrivalDelayMinutes].max(), delay > 0 {
            Text("\(delay) min late")
                .font(.subheadline)
                .foregroundStyle(.orange)
        } else {
            Text("On time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func endpoint(
        label: String,
        station: String,
        scheduled: String?,
        expected: String?,
        platform: String?,
        platformChanged: Bool,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(station)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
            HStack(spacing: 6) {
                if let expected, expected != scheduled {
                    Text(scheduled ?? "")
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Text(expected)
                        .foregroundStyle(.orange)
                } else {
                    Text(scheduled ?? "--:--")
                }
            }
            .font(.title2)
            .fontWeight(.bold)
            .monospacedDigit()
            if let platform {
                Text("Platform \(platform)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(platformChanged ? .orange : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    @ViewBuilder
    private var phoneLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerRow
                .padding(.bottom, 6)

            // Main content
            HStack(alignment: .top, spacing: 12) {
                leftSection
                Spacer(minLength: 0)
                platformSection
            }
            .padding(.bottom, 4)

            // Bottom: arrival time
            bottomRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(white: 0.08))
    }

    // MARK: - Header

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 6) {
            // Phase indicator
            Image(systemName: phaseIcon)
                .font(.caption)
                .foregroundStyle(phaseColor)

            Text(attrs.originName)
                .fontWeight(.semibold)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            Text(attrs.destinationName)
                .fontWeight(.semibold)

            Spacer()

            // Headcode + leg badge
            HStack(spacing: 4) {
                Text(attrs.headcode)
                    .fontWeight(.bold)

                if attrs.totalLegs > 1 {
                    Text("\(attrs.legIndex + 1)/\(attrs.totalLegs)")
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                        )
                }
            }
        }
        .font(.caption)
    }

    // MARK: - Left Section

    @ViewBuilder
    private var leftSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Phase-based headline
            Text(headline)
                .font(.headline)
                .lineLimit(2)

            // Countdown — only show timer when the target date is still in the future
            if state.phase == "boarding", let depDate = state.departureDate, depDate > state.lastUpdated {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("Departs in")
                        .font(.subheadline)
                    Text(depDate, style: .relative)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .foregroundStyle(.blue)
            } else if state.phase == "boarding" {
                HStack(spacing: 4) {
                    Image(systemName: "train.side.front.car")
                        .font(.caption)
                    Text("Departing now")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.blue)
            } else if state.phase == "onTrain", let arrDate = state.arrivalDate, arrDate > state.lastUpdated {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("Arrives in")
                        .font(.subheadline)
                    Text(arrDate, style: .relative)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .foregroundStyle(.green)
            } else if state.phase == "onTrain" {
                HStack(spacing: 4) {
                    Image(systemName: "train.side.front.car")
                        .font(.caption)
                    Text("Arriving now")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.green)
            } else if state.phase == "upcoming", let conn = state.connectionMinutes {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.caption)
                    Text("\(conn) min connection")
                        .font(.subheadline)
                }
                .foregroundStyle(.orange)
            }

            // Delay badge
            let delay = max(state.departureDelayMinutes, state.arrivalDelayMinutes)
            if state.isCancelled {
                cancelledBadge
            } else if delay > 0 {
                Text("+\(delay) min late")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(delay >= 10 ? Color.red.opacity(0.3) : Color.orange.opacity(0.3))
                    )
                    .foregroundStyle(delay >= 10 ? .red : .orange)
            }
        }
    }

    private var headline: String {
        switch state.phase {
        case "upcoming":
            return "Next: \(attrs.headcode)"
        case "boarding":
            if let p = state.departurePlatform {
                return "Board at Platform \(p)"
            }
            return "Board \(attrs.headcode)"
        case "onTrain":
            return "On train to \(attrs.destinationName)"
        case "arrived":
            return "Arrived at \(attrs.destinationName)"
        default:
            return attrs.headcode
        }
    }

    @ViewBuilder
    private var cancelledBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CANCELLED")
                .font(.caption)
                .fontWeight(.bold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.3))
                )
                .foregroundStyle(.red)

            if let reason = state.cancelReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Platforms

    @ViewBuilder
    private var platformSection: some View {
        HStack(spacing: 6) {
            if let depPlat = state.departurePlatform {
                PlatformCard(
                    label: "DEP",
                    platform: depPlat,
                    changed: state.departurePlatformChanged
                )
            }
            if let arrPlat = state.arrivalPlatform {
                PlatformCard(
                    label: "ARR",
                    platform: arrPlat,
                    changed: state.arrivalPlatformChanged
                )
            }
        }
    }

    // MARK: - Bottom Row

    @ViewBuilder
    private var bottomRow: some View {
        HStack {
            // Operator
            if !attrs.operatorName.isEmpty {
                Text(attrs.operatorName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Times — show scheduled struck through + expected when delayed
            HStack(spacing: 8) {
                if let scheduled = state.scheduledDeparture {
                    HStack(spacing: 2) {
                        Text("Dep")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let expected = state.expectedDeparture {
                            Text(scheduled)
                                .font(.caption)
                                .monospacedDigit()
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Text(expected)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        } else {
                            Text(scheduled)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
                if let scheduled = state.scheduledArrival {
                    HStack(spacing: 2) {
                        Text("Arr")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let expected = state.expectedArrival {
                            Text(scheduled)
                                .font(.caption)
                                .monospacedDigit()
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Text(expected)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        } else {
                            Text(scheduled)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Phase helpers

    private var phaseIcon: String {
        switch state.phase {
        case "upcoming": return "clock"
        case "boarding": return "figure.stand"
        case "onTrain": return "tram.fill"
        case "arrived": return "checkmark.circle.fill"
        default: return "tram.fill"
        }
    }

    private var phaseColor: Color {
        if state.isCancelled { return .red }
        switch state.phase {
        case "upcoming": return .secondary
        case "boarding": return .blue
        case "onTrain": return .green
        case "arrived": return .green
        default: return .primary
        }
    }
}

// MARK: - Platform Card

private struct PlatformCard: View {
    let label: String
    let platform: String
    let changed: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(changed ? .red : .secondary)
            Text(platform)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(changed ? .red : .primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(changed ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
        )
    }
}
