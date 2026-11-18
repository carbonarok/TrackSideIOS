import SwiftUI

/// The train you're tracking, at the top of the board: the first thing on
/// screen when you open the app, which on a folded iPhone Duo's outer
/// screen is usually all you want. Tapping it opens the journey.
struct TrackedJourneyBanner: View {
    @Environment(ActiveJourneyManager.self) private var journeyManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let tracker = journeyManager.tracker, tracker.isTracking,
           tracker.updatedLegs.indices.contains(tracker.currentLegIndex) {
            let leg = tracker.updatedLegs[tracker.currentLegIndex]
            let delay = max(leg.departureDelay ?? 0, leg.arrivalDelay ?? 0)
            Button {
                openURL(URL(string: "trackside://journey")!)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tracker.updatedLegs.count > 1
                             ? "Tracking · train \(tracker.currentLegIndex + 1) of \(tracker.updatedLegs.count)"
                             : "Tracking")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(time(leg.departureTime)) to \(leg.destinationName)")
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            if let platform = leg.departurePlatform {
                                Text("Platform \(platform)")
                            }
                            if leg.isCancelled {
                                Text("Cancelled").foregroundStyle(Color.delaySevere)
                            } else if delay > 0 {
                                Text("\(delay) min late").foregroundStyle(Color.delay(minutes: delay))
                            } else {
                                Text("Arrives \(time(leg.arrivalTime))")
                            }
                        }
                        .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .accessibilityHint("Opens the journey")
        }
    }

    private func time(_ value: String?) -> String {
        guard let value, let date = parseTime(value) else { return "--:--" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_GB")))
    }
}
