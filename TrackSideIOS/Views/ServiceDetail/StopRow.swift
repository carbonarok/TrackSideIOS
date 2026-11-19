import SwiftUI

struct StopRow: View {
    /// Grows with the text size, so times don't get cut off.
    @ScaledMetric(relativeTo: .subheadline) private var timeColumnWidth: CGFloat = 80
    let stop: Stop
    let isCurrentPosition: Bool
    let isFirst: Bool
    let isLast: Bool
    let isPassed: Bool

    init(stop: Stop, isCurrentPosition: Bool = false, isFirst: Bool = false, isLast: Bool = false, isPassed: Bool = false) {
        self.stop = stop
        self.isCurrentPosition = isCurrentPosition
        self.isFirst = isFirst
        self.isLast = isLast
        self.isPassed = isPassed
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Timeline indicator with connecting lines
            timelineIndicator

            if dynamicTypeSize.isAccessibilitySize {
                // No room for columns at the largest sizes: time above the
                // station, each the full width.
                VStack(alignment: .leading, spacing: 4) {
                    timeColumn
                        .font(.subheadline)
                        .monospacedDigit()
                    stationInfo
                    trailingIndicator
                }
                Spacer(minLength: 0)
            } else {
                // Times column — single relevant time per stop
                timeColumn
                    .font(.subheadline)
                    .monospacedDigit()
                    .frame(width: timeColumnWidth, alignment: .trailing)

                // Station info
                stationInfo

                Spacer(minLength: 0)

                // Status indicator on the right
                trailingIndicator
            }
        }
        .padding(.vertical, 4)
        .opacity(stop.cancelled ? 0.5 : 1.0)
        .listRowSeparator(.hidden)
    }

    // MARK: - Timeline

    private var timelineIndicator: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? .clear : lineColorAbove)
                .frame(width: 2, height: 14)

            ZStack {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: indicatorSize, height: indicatorSize)

                if isCurrentPosition || stop.atPlatform == true {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: indicatorSize + 6, height: indicatorSize + 6)
                }
            }
            .frame(width: 20, height: 20)

            Rectangle()
                .fill(isLast ? .clear : lineColorBelow)
                .frame(width: 2, height: 14)
        }
        .frame(width: 20)
    }

    // MARK: - Time Column

    @ViewBuilder
    private var timeColumn: some View {
        if stop.kind == .pass {
            // Pass: show pass time subtly
            TimeDisplay(stop.pass, showDelay: false, style: .caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if stop.kind == .origin || stop.startsHere == true {
            // Origin: departure time
            TimeDisplay(stop.departure, style: .subheadline)
        } else if stop.kind == .destination || stop.terminatesHere == true {
            // Destination: arrival time
            TimeDisplay(stop.arrival, style: .subheadline)
        } else {
            // Intermediate stops: departure time only (what passengers need)
            TimeDisplay(stop.departure, style: .subheadline)
        }
    }

    // MARK: - Station Info

    private var stationInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(stop.name)
                    .font(.body)
                    .fontWeight(isKeyStop ? .semibold : .regular)
                    .strikethrough(stop.cancelled)
                    .foregroundStyle(stop.cancelled ? .red : isPassed ? .secondary : .primary)

                if stop.kind == .pass {
                    Text("pass")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                PlatformBadge(platform: stop.platform)

                if stop.atPlatform == true {
                    Label("At platform", systemImage: "tram.fill")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                } else if stop.approaching == true {
                    Label("Approaching", systemImage: "arrow.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.delayModerate)
                }

                if stop.startsHere == true {
                    Text("Starts here")
                        .font(.caption2)
                        .foregroundStyle(Color.onTime)
                }

                if stop.terminatesHere == true {
                    Text("Terminates here")
                        .font(.caption2)
                        .foregroundStyle(Color.delaySevere)
                }
            }
        }
    }

    // MARK: - Trailing Indicator

    @ViewBuilder
    private var trailingIndicator: some View {
        if isPassed && !isKeyStop {
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundStyle(Color.signalGreen.opacity(0.6))
        }
    }

    // MARK: - Computed Properties

    private var isKeyStop: Bool {
        stop.kind == .origin || stop.kind == .destination || stop.startsHere == true || stop.terminatesHere == true
    }

    private var indicatorColor: Color {
        if stop.cancelled { return .delaySevere }
        if stop.atPlatform == true { return .accentColor }
        if stop.approaching == true { return .delayModerate }
        if isCurrentPosition { return .accentColor }
        if stop.kind == .origin || stop.startsHere == true { return .signalGreen }
        if stop.kind == .destination || stop.terminatesHere == true { return .accentColor }
        if stop.kind == .pass { return .secondary.opacity(0.3) }
        if isPassed { return Color.signalGreen.opacity(0.6) }
        return .secondary.opacity(0.5)
    }

    private var indicatorSize: CGFloat {
        if isKeyStop || stop.atPlatform == true { return 12 }
        if stop.kind == .pass { return 6 }
        return 10
    }

    private var lineColorAbove: Color {
        if isPassed || isCurrentPosition { return Color.signalGreen.opacity(0.5) }
        return .secondary.opacity(0.2)
    }

    private var lineColorBelow: Color {
        if isPassed && !isCurrentPosition { return Color.signalGreen.opacity(0.5) }
        return .secondary.opacity(0.2)
    }
}
