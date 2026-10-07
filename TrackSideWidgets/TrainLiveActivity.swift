import ActivityKit
import SwiftUI
import WidgetKit

struct TrainLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrainActivityAttributes.self) { context in
            // Lock screen / banner UI
            TrainLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.headcode)
                            .font(.caption)
                            .fontWeight(.bold)
                        Text(context.attributes.operatorName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let platform = context.state.platformAtDestination {
                            HStack(spacing: 2) {
                                Text("Plat")
                                    .font(.caption2)
                                Text(platform)
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                            .foregroundStyle(context.state.platformChanged ? .red : .blue)
                        }
                        Text(context.state.status)
                            .font(.caption2)
                            .foregroundStyle(statusColor(context.state))
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.attributes.originName) → \(context.attributes.destinationName)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.atPlatform || context.state.approaching {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(context.state.atPlatform ? .green : .blue)
                                    .frame(width: 6, height: 6)
                                Text(context.state.atPlatform ? "At \(context.state.currentStopName)" : "Approaching \(context.state.currentStopName)")
                                    .font(.caption)
                            }
                        }
                        Spacer()
                        if let scheduled = context.state.scheduledArrival {
                            HStack(spacing: 4) {
                                Text("Arr")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let expected = context.state.expectedArrival, expected != scheduled {
                                    Text(formatShort(scheduled))
                                        .font(.caption)
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                    Text(formatShort(expected))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(formatShort(scheduled))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                }
                            }
                        }
                    }
                }
            } compactLeading: {
                Text(context.attributes.headcode)
                    .font(.caption2)
                    .fontWeight(.bold)
            } compactTrailing: {
                if let arrival = context.state.expectedArrival ?? context.state.scheduledArrival {
                    Text(formatShort(arrival))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(context.state.delayMinutes > 0 ? .orange : .primary)
                } else {
                    Text(context.state.status)
                        .font(.caption2)
                }
            } minimal: {
                Image(systemName: "tram.fill")
                    .font(.caption2)
                    .foregroundStyle(context.state.delayMinutes > 0 ? .orange : .green)
            }
        }
    }

    private func statusColor(_ state: TrainActivityAttributes.ContentState) -> Color {
        if state.status == "Cancelled" { return .red }
        if state.delayMinutes > 0 { return .orange }
        return .green
    }

    private func formatShort(_ timeString: String) -> String {
        if timeString.count > 10, let tIndex = timeString.firstIndex(of: "T") {
            let afterT = timeString[timeString.index(after: tIndex)...]
            return String(afterT.prefix(5))
        }
        return String(timeString.prefix(5))
    }
}

// MARK: - Lock Screen View

private struct TrainLockScreenView: View {
    let context: ActivityViewContext<TrainActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text(context.attributes.headcode)
                    .font(.headline)
                    .fontWeight(.bold)
                Text(context.attributes.operatorName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                statusPill(context.state.status, delay: context.state.delayMinutes)
            }

            // Route
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.originName)
                        .font(.subheadline)
                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(context.attributes.destinationName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()

                // Platform + arrival
                VStack(alignment: .trailing, spacing: 6) {
                    if let platform = context.state.platformAtDestination {
                        VStack(spacing: 1) {
                            Text("PLAT")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(platform)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(context.state.platformChanged ? .red : .primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(context.state.platformChanged ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
                        )
                    }

                    if let scheduled = context.state.scheduledArrival {
                        arrivalTime(scheduled: scheduled, expected: context.state.expectedArrival)
                    }
                }
            }

            // Live position
            if context.state.atPlatform || context.state.approaching {
                HStack(spacing: 6) {
                    Circle()
                        .fill(context.state.atPlatform ? .green : .blue)
                        .frame(width: 8, height: 8)
                    Text(context.state.atPlatform ? "At \(context.state.currentStopName)" : "Approaching \(context.state.currentStopName)")
                        .font(.caption)
                    if let next = context.state.nextStopName {
                        Spacer()
                        Text("Next: \(next)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.7))
    }

    @ViewBuilder
    private func statusPill(_ status: String, delay: Int) -> some View {
        Text(status)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(pillColor(status, delay: delay).opacity(0.2))
            )
            .foregroundStyle(pillColor(status, delay: delay))
    }

    private func pillColor(_ status: String, delay: Int) -> Color {
        if status == "Cancelled" { return .red }
        if delay > 0 { return .orange }
        return .green
    }

    @ViewBuilder
    private func arrivalTime(scheduled: String, expected: String?) -> some View {
        HStack(spacing: 4) {
            Text("Arr")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let expected, expected != scheduled {
                Text(formatShort(scheduled))
                    .font(.caption)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Text(formatShort(expected))
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
            } else {
                Text(formatShort(scheduled))
                    .font(.callout)
                    .fontWeight(.bold)
            }
        }
    }

    private func formatShort(_ timeString: String) -> String {
        if timeString.count > 10, let tIndex = timeString.firstIndex(of: "T") {
            let afterT = timeString[timeString.index(after: tIndex)...]
            return String(afterT.prefix(5))
        }
        return String(timeString.prefix(5))
    }
}
