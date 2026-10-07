import SwiftUI

/// Displays scheduled and live times with delay highlighting.
/// Uses a vertical layout to avoid wrapping in narrow columns.
struct TimeDisplay: View {
    let times: Times?
    let showDelay: Bool

    init(_ times: Times?, showDelay: Bool = true) {
        self.times = times
        self.showDelay = showDelay
    }

    var body: some View {
        if let times {
            let scheduled = formatTime(times.`public` ?? times.working ?? "")
            let live = (times.actual ?? times.estimated).map { formatTime($0) }
            let isChanged = live != nil && live != scheduled
            let isCancelled = times.cancelled ?? false

            if isCancelled {
                // Cancelled: struck-through in red
                Text(scheduled)
                    .strikethrough()
                    .foregroundStyle(.red)
            } else if isChanged {
                // Delayed/changed: scheduled struck-through above, live time below
                VStack(alignment: .trailing, spacing: 1) {
                    Text(scheduled)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                        .font(.caption2)

                    HStack(spacing: 3) {
                        Text(live!)
                            .foregroundStyle(delayColor)
                            .fontWeight(.semibold)

                        if showDelay, let delay = times.delayMinutes, delay > 0 {
                            Text("+\(delay)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(delayColor)
                        }
                    }
                }
            } else {
                // On time: clean single time
                HStack(spacing: 3) {
                    Text(scheduled)

                    if times.delayed == true, times.delayMinutes == nil {
                        Text("Late")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var delayColor: Color {
        guard let delay = times?.delayMinutes else { return .orange }
        if delay >= 10 { return .red }
        if delay >= 5 { return .orange }
        return .yellow
    }

    /// Extract HH:MM from an ISO 8601 timestamp or short time string
    private func formatTime(_ timeString: String) -> String {
        // Handle ISO 8601 format: 2026-10-06T14:32:00+01:00
        if timeString.count > 10, let tIndex = timeString.firstIndex(of: "T") {
            let afterT = timeString[timeString.index(after: tIndex)...]
            return String(afterT.prefix(5))
        }
        // Already short format
        return String(timeString.prefix(5))
    }
}
