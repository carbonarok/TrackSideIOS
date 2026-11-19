import SwiftUI

/// The main thing to do with a train or journey: a full-width, filled
/// button to start tracking it, which becomes "Tracking live" with a Stop
/// once it's going.
struct TrackButton: View {
    let title: String
    let isTracking: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        Group {
            if isTracking {
                HStack(spacing: 10) {
                    LiveDot()
                    Text("Tracking live")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Stop", role: .destructive, action: stop)
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            } else {
                Button(action: start) {
                    Label(title, systemImage: "location.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .listRowSeparator(.hidden)
        .padding(.vertical, 4)
    }
}

/// A small green dot that pulses, for something updating live.
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Color.signalGreen)
            .frame(width: 8, height: 8)
            .background {
                if !reduceMotion {
                    Circle()
                        .fill(Color.signalGreen.opacity(0.4))
                        .phaseAnimator([0.8, 2.2]) { content, scale in
                            content.scaleEffect(scale).opacity(2.4 - scale)
                        } animation: { _ in .easeOut(duration: 1.4) }
                }
            }
            .accessibilityHidden(true)
    }
}
