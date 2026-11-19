import SwiftUI

struct BoardServiceRow: View {
    let service: BoardService
    /// Grows with the text size, so times don't get cut off.
    @ScaledMetric(relativeTo: .body) private var timeColumnWidth: CGFloat = 72

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                rowLayout
            }
        }
        .padding(.vertical, 4)
        .opacity(service.isCancelled ? 0.6 : 1.0)
    }

    /// At the largest text sizes there's no room for columns side by side,
    /// so each part gets the full width.
    private var stackedLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            stripe
            VStack(alignment: .leading, spacing: 6) {
                time
                status
                details
                PlatformBadge(platform: service.stop.platform)
            }
        }
    }

    private var rowLayout: some View {
        HStack(alignment: .center, spacing: 12) {
            stripe

            // The booked time; a late train says so on the right
            time
                .frame(width: timeColumnWidth, alignment: .trailing)

            // Platform; badges keep their natural width
            PlatformBadge(platform: service.stop.platform)
                .fixedSize()

            details
                // The destination is what people scan for; it gets the
                // room before anything else.
                .layoutPriority(1)

            Spacer(minLength: 0)

            status
        }
    }

    private var times: Times? {
        service.stop.departure ?? service.stop.arrival
    }

    /// Only for a train that's late or cancelled, so the eye goes straight
    /// to the trouble. On-time trains keep the space, so rows line up.
    private var stripe: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(stripeColor)
            .frame(width: 4, height: 44)
            .accessibilityHidden(true)
    }

    private var stripeColor: Color {
        if service.isCancelled || times?.cancelled == true { return .delaySevere }
        guard let times, times.isDisrupted else { return .clear }
        return .delay(minutes: max(1, times.delayMinutes ?? 1))
    }

    /// The booked time, as the board shows it; the status says if it's
    /// running late.
    private var time: some View {
        SplitFlapText(
            text: clockTime(times?.public ?? times?.working) ?? "--:--",
            style: .body,
            color: service.isCancelled ? SplitFlap.cancelled : SplitFlap.ink
        )
    }

    private var status: some View {
        TrainStatusText(times: times, cancelled: service.isCancelled)
    }

    /// Where the train is, under its destination where there's room for it.
    @ViewBuilder
    private var progress: some View {
        if service.isCancelled {
            EmptyView()
        } else if service.stop.atPlatform == true {
            Label("At platform", systemImage: "tram.fill")
                .imageScale(.small)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.platformConfirmed)
        } else if service.stop.approaching == true {
            Label("Approaching", systemImage: "arrow.right.circle.fill")
                .imageScale(.small)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.delayModerate)
        }
    }

    private var details: some View {
        // Destination and operator
        VStack(alignment: .leading, spacing: 3) {
            Text(service.destinationName)
                .font(.headline)
                .strikethrough(service.isCancelled)
                .lineLimit(2)

            HStack(spacing: 6) {
                if let headcode = service.headcode {
                    Text(headcode)
                        .font(.caption.monospaced())
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                if let op = service.operator {
                    Text(op.shortName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            progress

            // Cancel/late reason
            if let reason = service.cancelReason ?? service.lateReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(Color.delaySevere)
                    .lineLimit(1)
            }
        }
    }
}
