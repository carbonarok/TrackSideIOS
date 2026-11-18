import SwiftUI

/// Displays scheduled and live times with delay highlighting.
/// Uses a vertical layout to avoid wrapping in narrow columns.
struct TimeDisplay: View {
    let times: Times?
    let showDelay: Bool
    /// The size of the split-flap tiles the time is shown on.
    let style: Font.TextStyle

    init(_ times: Times?, showDelay: Bool = true, style: Font.TextStyle = .body) {
        self.times = times
        self.showDelay = showDelay
        self.style = style
    }

    var body: some View {
        if let times {
            let scheduled = formatTime(times.`public` ?? times.working ?? "")
            let live = (times.actual ?? times.estimated).map { formatTime($0) }
            let isChanged = live != nil && live != scheduled
            let isCancelled = times.cancelled ?? false

            if isCancelled {
                // Cancelled: the booked time in red
                SplitFlapText(text: scheduled, style: style, color: SplitFlap.cancelled)
                    .accessibilityLabel("\(scheduled), cancelled")
            } else if isChanged {
                // Delayed/changed: scheduled struck-through above, live time below
                VStack(alignment: .trailing, spacing: 1) {
                    Text(scheduled)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                        .font(.caption2)

                    HStack(spacing: 3) {
                        SplitFlapText(text: live!, style: style, color: SplitFlap.ink(delayMinutes: times.delayMinutes ?? 1))

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
                    SplitFlapText(text: scheduled, style: style)

                    if times.delayed == true, times.delayMinutes == nil {
                        Text("Late")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.delayModerate)
                    }
                }
            }
        }
    }

    private var delayColor: Color {
        guard let delay = times?.delayMinutes else { return .delayModerate }
        return .delay(minutes: delay)
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
