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
                Text(platformText)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
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
            return .orange
        }
        if platform?.confirmed == true {
            return .blue
        }
        return .primary
    }
}
