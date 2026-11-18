import SwiftUI

/// Text on split-flap tiles, like a station's departure board: each
/// character on its own dark tile with a hinge across the middle. When the
/// text changes, the characters that changed flip over to the new ones.
///
/// Colons and spaces sit between the tiles, as on a real board, so a time
/// takes four tiles rather than five.
struct SplitFlapText: View {
    let text: String
    var style: Font.TextStyle = .body
    var weight: Font.Weight = .semibold
    /// The characters' colour; the tiles stay dark in light and dark mode,
    /// so this should be a light colour.
    var color: Color = SplitFlap.ink

    var body: some View {
        HStack(spacing: SplitFlap.gap(for: style)) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                if character == ":" || character == " " {
                    Text(String(character))
                        .font(.system(style, design: .monospaced).weight(weight))
                        .foregroundStyle(.secondary)
                } else {
                    FlapTile(character: character, style: style, weight: weight, color: color)
                }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// The board's colours: dark tiles whatever the appearance, and light ink.
enum SplitFlap {
    static let tile = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let hinge = Color.black.opacity(0.55)
    static let ink = Color(white: 0.95)
    /// Delay colours that read on a dark tile. The app's light-mode delay
    /// colours are dark, for white backgrounds, so tiles use these.
    static let late = Color(red: 1.0, green: 0.78, blue: 0.2)
    static let veryLate = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let cancelled = Color(red: 1.0, green: 0.42, blue: 0.38)

    /// The ink for a delay of this many minutes.
    static func ink(delayMinutes: Int?) -> Color {
        guard let delay = delayMinutes, delay > 0 else { return ink }
        return delay >= 10 ? cancelled : delay >= 5 ? veryLate : late
    }

    static func gap(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle, .title, .title2: 3
        default: 1.5
        }
    }
}

private struct FlapTile: View {
    let character: Character
    let style: Font.TextStyle
    let weight: Font.Weight
    let color: Color

    @State private var shown: Character?
    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(String(shown ?? character))
            .font(.system(style, design: .monospaced).weight(weight))
            .foregroundStyle(color)
            .padding(.horizontal, padding)
            .padding(.vertical, padding / 2)
            .background(SplitFlap.tile, in: RoundedRectangle(cornerRadius: padding))
            .overlay {
                // The hinge between the top and bottom flaps.
                Rectangle()
                    .fill(SplitFlap.hinge)
                    .frame(height: 1)
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .onAppear { shown = character }
            .onChange(of: character) { _, new in
                flip(to: new)
            }
    }

    private var padding: CGFloat {
        switch style {
        case .largeTitle, .title: 5
        case .title2, .title3: 4
        default: 2.5
        }
    }

    /// Top flap falls away, then the new character's bottom flap drops in.
    private func flip(to new: Character) {
        guard !reduceMotion else {
            shown = new
            return
        }
        withAnimation(.easeIn(duration: 0.1)) {
            angle = 90
        } completion: {
            shown = new
            angle = -90
            withAnimation(.easeOut(duration: 0.12)) {
                angle = 0
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        SplitFlapText(text: "12:42", style: .title2, weight: .bold)
        SplitFlapText(text: "12:47", color: SplitFlap.late)
        SplitFlapText(text: "2W00", style: .caption)
    }
    .padding()
}
