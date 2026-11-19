import SwiftUI

/// A platform, the same everywhere in the app: a small "PLAT" over the
/// number, on a tinted chip. Amber once it has changed, the accent colour
/// once confirmed, grey while it's only the booked platform. A dashed
/// outline means it's planned but not yet on the station's screens: big
/// stations hold platforms back until shortly before departure.
struct PlatformBadge: View {
    let number: String?
    var changed = false
    var confirmed = false
    var unannounced = false
    /// Smaller, for a line of text such as a journey's legs.
    var compact = false

    init(platform: Platform?, compact: Bool = false) {
        self.number = platform?.displayPlatform
        self.changed = platform?.changed == true
        self.confirmed = platform?.confirmed == true
        self.unannounced = platform?.suppressed == true
        self.compact = compact
    }

    init(number: String?, compact: Bool = false) {
        self.number = number
        self.compact = compact
    }

    var body: some View {
        if let number, !number.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("PLAT")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .opacity(0.75)
                Text(number)
                    .font(.system(compact ? .caption : .subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, compact ? 1 : 3)
            .background(background, in: RoundedRectangle(cornerRadius: compact ? 5 : 7))
            .overlay {
                if unannounced {
                    RoundedRectangle(cornerRadius: compact ? 5 : 7)
                        .strokeBorder(foreground.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(number))
        }
    }

    private var foreground: Color {
        if changed { return .delayModerate }
        if confirmed { return .accentColor }
        return .primary
    }

    private var background: Color {
        if unannounced { return .clear }
        if changed { return Color.delayModerate.opacity(0.14) }
        if confirmed { return Color.accentColor.opacity(0.12) }
        return Color.secondary.opacity(0.12)
    }

    private func accessibilityText(_ number: String) -> String {
        if unannounced && changed { return "Platform \(number), changed, not yet announced" }
        if unannounced { return "Platform \(number), not yet announced" }
        if changed { return "Platform \(number), changed" }
        if confirmed { return "Platform \(number), confirmed" }
        return "Platform \(number)"
    }
}

#Preview {
    VStack(spacing: 12) {
        PlatformBadge(number: "7")
        PlatformBadge(number: "12", compact: true)
    }
    .padding()
}
