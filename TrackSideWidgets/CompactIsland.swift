import SwiftUI

/// Text for the compact Dynamic Island that never wraps.
///
/// On the iPhone Duo the island runs vertically beside the camera, and each
/// compact side is only about one short word wide, so "11:47" beside an
/// icon broke onto two lines. This tries the icon beside the text, then the
/// text alone, and shrinks the text before it would wrap.
struct CompactIslandLabel: View {
    let text: String
    var systemImage: String?
    var textColor: Color = .primary
    var iconColor: Color = .primary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if let systemImage {
                HStack(spacing: 3) {
                    Image(systemName: systemImage)
                        .foregroundStyle(iconColor)
                    label
                }
                .font(.caption2)
            }
            label
        }
    }

    private var label: some View {
        Text(text)
            .compactIslandText()
            .foregroundStyle(textColor)
    }
}

extension View {
    /// One line, shrinking rather than wrapping, for the compact island.
    func compactIslandText() -> some View {
        font(.caption2)
            .fontWeight(.bold)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
