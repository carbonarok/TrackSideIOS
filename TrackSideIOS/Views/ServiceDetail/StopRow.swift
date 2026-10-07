import SwiftUI

struct StopRow: View {
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Timeline indicator with connecting lines
            timelineIndicator

            // Times column — single relevant time per stop
            timeColumn
                .font(.subheadline)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)

            // Station info
            stationInfo

            Spacer(minLength: 0)

            // Status indicator on the right
            trailingIndicator
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
                        .stroke(Color.blue, lineWidth: 2)
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
            TimeDisplay(stop.pass, showDelay: false)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if stop.kind == .origin || stop.startsHere == true {
            // Origin: departure time
            TimeDisplay(stop.departure)
        } else if stop.kind == .destination || stop.terminatesHere == true {
            // Destination: arrival time
            TimeDisplay(stop.arrival)
        } else {
            // Intermediate stops: departure time only (what passengers need)
            TimeDisplay(stop.departure)
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
                        .foregroundStyle(.blue)
                } else if stop.approaching == true {
                    Label("Approaching", systemImage: "arrow.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if stop.startsHere == true {
                    Text("Starts here")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                if stop.terminatesHere == true {
                    Text("Terminates here")
                        .font(.caption2)
                        .foregroundStyle(.red)
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
                .foregroundStyle(.green.opacity(0.6))
        }
    }

    // MARK: - Computed Properties

    private var isKeyStop: Bool {
        stop.kind == .origin || stop.kind == .destination || stop.startsHere == true || stop.terminatesHere == true
    }

    private var indicatorColor: Color {
        if stop.cancelled { return .red }
        if stop.atPlatform == true { return .blue }
        if stop.approaching == true { return .orange }
        if isCurrentPosition { return .blue }
        if stop.kind == .origin || stop.startsHere == true { return .green }
        if stop.kind == .destination || stop.terminatesHere == true { return .red }
        if stop.kind == .pass { return .secondary.opacity(0.3) }
        if isPassed { return .green.opacity(0.6) }
        return .secondary.opacity(0.5)
    }

    private var indicatorSize: CGFloat {
        if isKeyStop || stop.atPlatform == true { return 12 }
        if stop.kind == .pass { return 6 }
        return 10
    }

    private var lineColorAbove: Color {
        if isPassed || isCurrentPosition { return .green.opacity(0.5) }
        return .secondary.opacity(0.2)
    }

    private var lineColorBelow: Color {
        if isPassed && !isCurrentPosition { return .green.opacity(0.5) }
        return .secondary.opacity(0.2)
    }
}
