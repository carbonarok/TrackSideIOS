import SwiftUI

struct BoardServiceRow: View {
    let service: BoardService
    /// Grows with the text size, so times don't get cut off.
    @ScaledMetric(relativeTo: .body) private var timeColumnWidth: CGFloat = 86

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

            // Time column — shows scheduled time, or strikethrough + live time when delayed
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

            // Only what's unusual: on-time trains have no badge, and a
            // delay already shows in the time.
            if service.isCancelled {
                StatusBadge(status: service.status, cancelled: true)
                    .fixedSize()
            }
        }
    }

    // Operator color stripe
    @ViewBuilder
    private var stripe: some View {
        if let op = service.operator {
            RoundedRectangle(cornerRadius: 2)
                .fill(op.brandColor)
                .frame(width: 4, height: 44)
        }
    }

    private var time: some View {
        TimeDisplay(service.stop.departure ?? service.stop.arrival, style: .body)
            .font(.body)
            .fontWeight(.semibold)
    }

    @ViewBuilder
    private var status: some View {
        if service.isCancelled {
            StatusBadge(status: service.status, cancelled: true)
        }
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
                .font(.body)
                .fontWeight(.medium)
                .strikethrough(service.isCancelled)
                .lineLimit(2)

            HStack(spacing: 6) {
                if let headcode = service.headcode {
                    SplitFlapText(text: headcode, style: .caption2, weight: .medium)
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
