import SwiftUI

/// A train as a station's departure board shows it: amber on black, big
/// enough to read from across a table. Shown in the top half of an iPhone
/// Duo half-folded like a laptop, the "tabletop" posture, while the rest of
/// the train page sits in the bottom half.
struct PlatformDisplay: View {
    let detail: ServiceDetail

    private static let amber = Color(red: 1.0, green: 0.72, blue: 0.0)

    var body: some View {
        let remaining = remainingStops
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(detail.headcode ?? detail.uid)
                Spacer()
                Text(detail.operator?.shortName ?? "")
            }
            .font(.system(.subheadline, design: .monospaced))
            .foregroundStyle(Self.amber.opacity(0.7))

            if let next = remaining.first {
                // The station gets the line to itself, so it's never cut short.
                HStack(alignment: .center, spacing: 16) {
                    SplitFlapText(text: time(next), style: .largeTitle, weight: .bold, color: Self.amber)
                    Text(next.name)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))

                HStack(alignment: .firstTextBaseline) {
                    if let platform = next.platform?.displayPlatform {
                        Text("Platform")
                            .fontWeight(.bold)
                        SplitFlapText(text: platform, style: .title2, weight: .bold, color: Self.amber)
                    }
                    Spacer()
                    Text(status(next))
                }
                .font(.system(.title2, design: .monospaced))

                if remaining.count > 1 {
                    Text("Then " + remaining.dropFirst().map(\.name).joined(separator: ", "))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Self.amber.opacity(0.8))
                        .lineLimit(2)
                }
            } else {
                Text("Arrived")
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Self.amber)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("platformDisplay")
    }

    /// Calling points the train hasn't left yet, next first.
    private var remainingStops: [Stop] {
        detail.stops.filter { stop in
            guard stop.kind != .pass else { return false }
            let left = stop.kind == .destination || stop.terminatesHere == true
                ? stop.arrival?.actual != nil
                : stop.departure?.actual != nil
            return !left
        }
    }

    private func times(_ stop: Stop) -> Times? {
        stop.kind == .origin ? stop.departure : (stop.arrival ?? stop.departure)
    }

    private func time(_ stop: Stop) -> String {
        let value = times(stop).flatMap { $0.estimated ?? $0.`public` } ?? ""
        guard let date = parseTime(value) else { return "--:--" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_GB")))
    }

    private func status(_ stop: Stop) -> String {
        if detail.isCancelled || stop.cancelled { return "Cancelled" }
        if stop.atPlatform == true { return "At platform" }
        if stop.approaching == true { return "Approaching" }
        if let delay = times(stop)?.delayMinutes, delay > 0 { return "\(delay) min late" }
        return "On time"
    }
}
