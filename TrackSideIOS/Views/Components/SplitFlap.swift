import SwiftUI
import UIKit

/// Text on split-flap tiles, like a station's departure board: each
/// character on its own dark tile with a hinge across the middle.
///
/// The tiles move like a real board's. When they first appear they spin
/// through a few characters and settle, left to right. When the text
/// changes, a changed tile rolls through the characters in between, as a
/// board's drum does: 17:12 becoming 17:16 clicks through 3, 4 and 5.
/// With Reduce Motion they just change.
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
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                if character == ":" || character == " " {
                    Text(String(character))
                        .font(.system(style, design: .monospaced).weight(weight))
                        .foregroundStyle(.secondary)
                } else {
                    FlapTile(character: character, index: index, style: style, weight: weight, color: color)
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
    /// Near-black on a light page. On a black page a tile that dark would
    /// vanish, so in dark mode it's a lighter charcoal.
    static let tile = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1)
            : UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    })
    static let hinge = Color.black.opacity(0.6)
    /// Light catching the top flap, which tilts towards it; the bottom flap
    /// hangs straight down and stays plain.
    static let sheen = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.13), location: 0),
            .init(color: .white.opacity(0.04), location: 0.5),
            .init(color: .clear, location: 0.5),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
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

    /// How long one flap takes to fall.
    static let flipDuration: TimeInterval = 0.07

    /// The characters on a tile's drum, in the order it turns through them.
    private static let drums: [[Character]] = [
        Array("0123456789"),
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
    ]

    /// The flaps a tile shows going from one character to another: every
    /// character in between on its drum, then the new one. At most ten, so
    /// a long way round stays brisk.
    static func steps(from old: Character, to new: Character) -> [Character] {
        for drum in drums {
            guard let start = drum.firstIndex(of: old), let end = drum.firstIndex(of: new) else { continue }
            var steps: [Character] = []
            var position = start
            repeat {
                position = (position + 1) % drum.count
                steps.append(drum[position])
            } while position != end
            return Array(steps.suffix(10))
        }
        return [new]
    }

    /// The flaps a tile shows as it first appears: a few random characters
    /// from its drum, then its own.
    static func settling(to character: Character, index: Int) -> [Character] {
        guard let drum = drums.first(where: { $0.contains(character) }) else { return [character] }
        let spins = 2 + index % 3
        return (0..<spins).map { _ in drum.randomElement()! } + [character]
    }

    static func gap(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle, .title, .title2: 3
        default: 1.5
        }
    }
}

/// One tile. It has two flaps: the top half and the bottom half. A flip
/// lets the top half of the old character fall forward over the hinge,
/// uncovering the top of the new one; then the bottom half of the new one
/// drops down over the bottom of the old.
private struct FlapTile: View {
    let character: Character
    /// Its place in the text, so tiles settle one after another.
    let index: Int
    let style: Font.TextStyle
    let weight: Font.Weight
    let color: Color

    /// The character showing; mid-flip, the one being flipped away.
    @State private var current: Character = " "
    /// Mid-flip, the character arriving.
    @State private var incoming: Character?
    /// How far through a flip: 0 at rest, 0.5 with the top flap flat,
    /// 1 with the bottom flap down.
    @State private var progress: Double = 0
    @State private var hasSettled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Behind the falling flap: the top of what's arriving.
            face(incoming ?? current)
                .clipShape(TileHalf(top: true))
            // Under the dropping flap: the bottom of what's leaving.
            face(current)
                .clipShape(TileHalf(top: false))
            // The two moving flaps are always there, so a flip animates
            // from rest. At rest the top one lies over its twin and the
            // bottom one is edge-on, unseen.
            face(current)
                .clipShape(TileHalf(top: true))
                .modifier(FlapTurn(progress: progress, top: true))
            face(incoming ?? current)
                .clipShape(TileHalf(top: false))
                .modifier(FlapTurn(progress: progress, top: false))
        }
        .overlay {
            // The hinge between the top and bottom flaps.
            Rectangle()
                .fill(SplitFlap.hinge)
                .frame(height: 1)
        }
        .task(id: character) {
            await flip(to: character)
        }
    }

    private func face(_ character: Character) -> some View {
        Text(String(character))
            .font(.system(style, design: .monospaced).weight(weight))
            .foregroundStyle(color)
            .padding(.horizontal, padding)
            .padding(.vertical, padding / 2)
            .background {
                let shape = RoundedRectangle(cornerRadius: padding)
                shape
                    .fill(SplitFlap.tile)
                    .overlay(SplitFlap.sheen.clipShape(shape))
                    .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 0.5, y: 0.5)
            }
    }

    private var padding: CGFloat {
        switch style {
        case .largeTitle, .title: 5
        case .title2, .title3: 4
        default: 2.5
        }
    }

    private func flip(to target: Character) async {
        // A new character mid-flip: finish where it was going.
        if let arriving = incoming {
            rest(on: arriving)
        }

        let steps: [Character]
        if !hasSettled {
            hasSettled = true
            guard !reduceMotion else { return rest(on: target) }
            steps = SplitFlap.settling(to: target, index: index)
            try? await Task.sleep(for: .milliseconds(40 * index))
        } else {
            guard current != target else { return }
            guard !reduceMotion else { return rest(on: target) }
            steps = SplitFlap.steps(from: current, to: target)
        }

        for step in steps {
            guard !Task.isCancelled else { return }
            incoming = step
            withAnimation(.linear(duration: SplitFlap.flipDuration)) {
                progress = 1
            }
            try? await Task.sleep(for: .seconds(SplitFlap.flipDuration))
            rest(on: step)
        }
        if !Task.isCancelled, current != target {
            rest(on: target)
        }
    }

    /// Shows a character with both flaps at rest, without animating back.
    private func rest(on character: Character) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            current = character
            incoming = nil
            progress = 0
        }
    }
}

/// The top or bottom half of a tile.
private struct TileHalf: Shape {
    let top: Bool

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: top ? rect.minY : rect.midY, width: rect.width, height: rect.height / 2))
    }
}

/// Turns a flap about the hinge. The top flap falls in the first half of
/// a flip, the bottom flap in the second; each darkens as it turns away
/// from the light.
private struct FlapTurn: ViewModifier, Animatable {
    var progress: Double
    let top: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let fall = min(progress * 2, 1)
        let drop = max(progress * 2 - 1, 0)
        let angle = top ? -90 * fall : 90 * (1 - drop)
        content
            .brightness(top ? -0.35 * fall : -0.35 * (1 - drop))
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 1, y: 0, z: 0),
                anchor: top ? .bottom : .top,
                perspective: 0.25
            )
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        SplitFlapText(text: "12:42", style: .title2, weight: .bold)
        SplitFlapText(text: "12:47", color: SplitFlap.late)
        SplitFlapText(text: "2W00", style: .caption)
        FlipDemo()
    }
    .padding()
}

/// Changes the time every couple of seconds, to watch the tiles flip.
private struct FlipDemo: View {
    @State private var minutes = 12 * 60 + 39

    var body: some View {
        SplitFlapText(text: String(format: "%02d:%02d", minutes / 60, minutes % 60), style: .largeTitle, weight: .bold)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    minutes += 3
                }
            }
    }
}
