import SwiftUI

/// Displays platform information with visual indicators for changes/confirmation
struct PlatformBadge: View {
    let platform: Platform?

    var body: some View {
        if let platformText = platform?.displayPlatform {
            HStack(spacing: 2) {
                Text("Plat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                SplitFlapText(text: platformText, style: .caption, color: tileInk)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// The platform number's colour on its dark tile: amber when it has
    /// changed, blue once confirmed.
    private var tileInk: Color {
        if platform?.changed == true { return SplitFlap.late }
        if platform?.confirmed == true { return Color(red: 0.55, green: 0.8, blue: 1.0) }
        return SplitFlap.ink
    }

    private var backgroundColor: Color {
        if platform?.changed == true {
            return .orange.opacity(0.15)
        }
        if platform?.confirmed == true {
            return .blue.opacity(0.1)
        }
        return .secondary.opacity(0.1)
    }

    private var foregroundColor: Color {
        if platform?.changed == true {
            return .delayModerate
        }
        if platform?.confirmed == true {
            return .platformConfirmed
        }
        return .primary
    }
}
