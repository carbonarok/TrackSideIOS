import ActivityKit
import SwiftUI
import WidgetKit

struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            JourneyLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded Dynamic Island

                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Headcode
                        Text(context.state.headcode)
                            .font(.caption)
                            .fontWeight(.bold)

                        // Leg indicator
                        if context.attributes.totalLegs > 1 {
                            Text("Leg \(context.state.currentLegIndex + 1)/\(context.attributes.totalLegs)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        // Delay badge
                        if context.state.overallDelayMinutes > 0 {
                            Text("+\(context.state.overallDelayMinutes)m")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(context.state.overallDelayMinutes >= 10 ? .red : .orange)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 8) {
                        // Departure platform
                        if let depPlat = context.state.departurePlatform {
                            PlatformPill(
                                label: "DEP",
                                platform: depPlat,
                                changed: context.state.departurePlatformChanged,
                                compact: true
                            )
                        }
                        // Arrival platform
                        if let arrPlat = context.state.arrivalPlatform {
                            PlatformPill(
                                label: "ARR",
                                platform: arrPlat,
                                changed: context.state.arrivalPlatformChanged,
                                compact: true
                            )
                        }
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.statusHeadline)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        // Progress dots
                        if context.attributes.showProgressBar, context.attributes.totalLegs > 1 {
                            ProgressDotsView(
                                totalLegs: context.attributes.totalLegs,
                                currentLeg: context.state.currentLegIndex,
                                completionStatus: context.state.legCompletionStatus
                            )
                        }

                        HStack {
                            // Countdown or detail
                            if context.state.phase == "boarding", let depDate = context.state.departureDate {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption2)
                                    Text(depDate, style: .relative)
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                                .foregroundStyle(.blue)
                            } else if context.state.phase == "onTrain", let arrDate = context.state.arrivalDate {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption2)
                                    Text("Arr in")
                                        .font(.caption2)
                                    Text(arrDate, style: .relative)
                                        .font(.caption)
                                        .monospacedDigit()
                                }
                                .foregroundStyle(.green)
                            } else if let detail = context.state.statusDetail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let next = context.state.nextAction {
                                Text(next)
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } compactLeading: {
                // Phase icon + delay
                HStack(spacing: 3) {
                    Image(systemName: phaseIcon(context.state.phase))
                        .font(.caption2)
                        .foregroundStyle(phaseColor(context.state))
                    if context.state.overallDelayMinutes > 0 {
                        Text("+\(context.state.overallDelayMinutes)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                }
            } compactTrailing: {
                // Platform or countdown
                if context.state.phase == "boarding", let depDate = context.state.departureDate {
                    Text(depDate, style: .timer)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .frame(maxWidth: 56)
                } else if let plat = context.state.phase == "boarding"
                    ? context.state.departurePlatform
                    : context.state.arrivalPlatform {
                    Text("P\(plat)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                } else {
                    Image(systemName: "tram.fill")
                        .font(.caption2)
                }
            } minimal: {
                Image(systemName: phaseIcon(context.state.phase))
                    .font(.caption2)
                    .foregroundStyle(phaseColor(context.state))
            }
        }
    }

    private func phaseIcon(_ phase: String) -> String {
        switch phase {
        case "boarding": return "figure.stand"
        case "onTrain": return "tram.fill"
        case "connection": return "figure.walk"
        case "arrived": return "checkmark.circle.fill"
        default: return "tram.fill"
        }
    }

    private func phaseColor(_ state: JourneyActivityAttributes.ContentState) -> Color {
        if state.hasIssues { return .red }
        switch state.phase {
        case "boarding": return .blue
        case "onTrain": return .green
        case "connection": return .orange
        case "arrived": return .green
        default: return .primary
        }
    }
}

// MARK: - Platform Pill

private struct PlatformPill: View {
    let label: String
    let platform: String
    let changed: Bool
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: compact ? 7 : 8, weight: .medium))
                .foregroundStyle(changed ? .red : .secondary)
            Text(platform)
                .font(compact ? .caption : .title3)
                .fontWeight(.bold)
                .foregroundStyle(changed ? .red : .primary)
        }
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 2 : 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(changed ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
        )
    }
}

// MARK: - Progress Dots

private struct ProgressDotsView: View {
    let totalLegs: Int
    let currentLeg: Int
    let completionStatus: [Bool]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalLegs, id: \.self) { index in
                if index > 0 {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index <= currentLeg ? Color.green : Color.white.opacity(0.2))
                        .frame(height: 2)
                }
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: 8, height: 8)
                    .overlay {
                        if completionStatus.indices.contains(index) && completionStatus[index] {
                            Image(systemName: "checkmark")
                                .font(.system(size: 5, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dotColor(for index: Int) -> Color {
        if completionStatus.indices.contains(index) && completionStatus[index] {
            return .green
        }
        if index == currentLeg { return .blue }
        if index < currentLeg { return .green.opacity(0.6) }
        return .white.opacity(0.3)
    }
}

// MARK: - Lock Screen View

private struct JourneyLockScreenView: View {
    let context: ActivityViewContext<JourneyActivityAttributes>

    private var state: JourneyActivityAttributes.ContentState { context.state }
    private var attrs: JourneyActivityAttributes { context.attributes }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            headerSection
                .padding(.bottom, 6)

            // Progress dots (multi-leg only)
            if attrs.showProgressBar, attrs.totalLegs > 1 {
                ProgressDotsView(
                    totalLegs: attrs.totalLegs,
                    currentLeg: state.currentLegIndex,
                    completionStatus: state.legCompletionStatus
                )
                .padding(.bottom, 8)
            }

            // Main content: left info + right platforms
            HStack(alignment: .top, spacing: 12) {
                leftSection
                Spacer(minLength: 0)
                platformSection
            }
            .padding(.bottom, 6)

            // Bottom bar
            bottomBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color(white: 0.08))
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "tram.fill")
                .font(.caption)
                .foregroundStyle(.blue)

            Text(attrs.originName)
                .fontWeight(.semibold)

            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            Text(attrs.finalDestinationName)
                .fontWeight(.semibold)

            Spacer()

            if attrs.totalLegs > 1 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(phaseColor)
                        .frame(width: 6, height: 6)
                    Text("Leg \(state.currentLegIndex + 1)/\(attrs.totalLegs)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    // MARK: - Left Section (headline, countdown, delay)

    @ViewBuilder
    private var leftSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status headline
            Text(state.statusHeadline)
                .font(.headline)
                .lineLimit(2)

            // Countdown or status detail
            if state.phase == "boarding", let depDate = state.departureDate {
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
            } else if state.phase == "onTrain", let arrDate = state.arrivalDate {
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
            } else if let detail = state.statusDetail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Delay badge — always prominent
            if state.overallDelayMinutes > 0 {
                Text("+\(state.overallDelayMinutes) min late")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(state.overallDelayMinutes >= 10 ? Color.red.opacity(0.3) : Color.orange.opacity(0.3))
                    )
                    .foregroundStyle(state.overallDelayMinutes >= 10 ? .red : .orange)
            }
        }
    }

    // MARK: - Platform Section (DEP + ARR side by side)

    @ViewBuilder
    private var platformSection: some View {
        HStack(spacing: 6) {
            if let depPlat = state.departurePlatform {
                PlatformPill(
                    label: "DEP",
                    platform: depPlat,
                    changed: state.departurePlatformChanged
                )
            }
            if let arrPlat = state.arrivalPlatform {
                PlatformPill(
                    label: "ARR",
                    platform: arrPlat,
                    changed: state.arrivalPlatformChanged
                )
            }
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 0) {
            if let info = state.nextConnectionInfo {
                Text(info)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            } else if let next = state.nextAction {
                Label(next, systemImage: "arrow.right.circle")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            Spacer(minLength: 8)

            // Arrival time for current leg
            if let arrTime = state.currentLegArrivalTime {
                HStack(spacing: 2) {
                    Text("Arr")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(arrTime)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(state.arrivalDelayMinutes > 0 ? .orange : .primary)
                }
            }

            // Issues warning
            if state.hasIssues {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("Issues")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.red)
                .padding(.leading, 6)
            }
        }
    }

    private var phaseColor: Color {
        if state.hasIssues { return .red }
        switch state.phase {
        case "boarding": return .blue
        case "onTrain": return .green
        case "connection": return .orange
        case "arrived": return .green
        default: return .primary
        }
    }
}
