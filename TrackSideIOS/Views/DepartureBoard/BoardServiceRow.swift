import SwiftUI

struct BoardServiceRow: View {
    let service: BoardService

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Operator color stripe
            if let op = service.operator {
                RoundedRectangle(cornerRadius: 2)
                    .fill(op.brandColor)
                    .frame(width: 4, height: 44)
            }

            // Time column
            VStack(alignment: .trailing, spacing: 2) {
                TimeDisplay(service.stop.departure ?? service.stop.arrival, showDelay: false)
                    .font(.title3)
                    .fontWeight(.semibold)

                if let delay = (service.stop.departure ?? service.stop.arrival)?.delayMinutes, delay > 0 {
                    Text("+\(delay) min")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(delay >= 10 ? .red : .orange)
                }
            }
            .frame(width: 65, alignment: .trailing)

            // Platform
            PlatformBadge(platform: service.stop.platform)

            // Destination and operator
            VStack(alignment: .leading, spacing: 3) {
                Text(service.destinationName)
                    .font(.body)
                    .fontWeight(.medium)
                    .strikethrough(service.isCancelled)

                HStack(spacing: 6) {
                    if let headcode = service.headcode {
                        Text(headcode)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    if let op = service.operator {
                        Text(op.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Cancel/late reason
                if let reason = service.cancelReason ?? service.lateReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status indicators
            VStack(alignment: .trailing, spacing: 4) {
                if service.isCancelled {
                    StatusBadge(status: service.status, cancelled: true)
                } else if service.stop.atPlatform == true {
                    Label("At platform", systemImage: "tram.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else if service.stop.approaching == true {
                    Label("Approaching", systemImage: "arrow.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if let delay = (service.stop.departure ?? service.stop.arrival)?.delayMinutes {
                    StatusBadge(status: service.status, delayMinutes: delay)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(service.isCancelled ? 0.6 : 1.0)
    }
}
