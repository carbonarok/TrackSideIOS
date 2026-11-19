import SwiftUI

/// The shape of what's coming while it loads: grey blocks where the rows
/// will be, gently pulsing. Screens keep their layout instead of jumping
/// from a spinner to a list.
struct LoadingRows: View {
    enum Kind {
        /// Departure board rows: a time, a platform, a destination.
        case board
        /// Route journeys: a departure and arrival time either side.
        case journeys
        /// A train: a header card, then its stops.
        case train
    }

    let kind: Kind
    var count = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            if kind == .train {
                trainHeader
                    .listRowSeparator(.hidden)
            }
            ForEach(0..<count, id: \.self) { index in
                row(index)
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { content, opacity in
            content.opacity(opacity)
        } animation: { _ in
            .easeInOut(duration: 0.9)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    @ViewBuilder
    private func row(_ index: Int) -> some View {
        // Varying widths, so it reads as text rather than a grid.
        let width: CGFloat = [150, 110, 170, 130, 95, 160][index % 6]
        switch kind {
        case .board:
            HStack(spacing: 12) {
                block(width: 70, height: 26)
                block(width: 46, height: 22)
                VStack(alignment: .leading, spacing: 6) {
                    block(width: width, height: 15)
                    block(width: 70, height: 11)
                }
                Spacer()
                block(width: 54, height: 14)
            }
            .padding(.vertical, 8)
        case .journeys:
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    block(width: 84, height: 28)
                    block(width: 100, height: 10)
                }
                Spacer()
                block(width: 40, height: 10)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    block(width: 84, height: 28)
                    block(width: 70, height: 10)
                }
            }
            .padding(.vertical, 8)
        case .train:
            HStack(spacing: 12) {
                Circle().fill(.quaternary).frame(width: 10, height: 10)
                block(width: width, height: 14)
                Spacer()
                block(width: 44, height: 14)
            }
            .padding(.vertical, 6)
        }
    }

    private var trainHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            block(width: 90, height: 30)
            block(width: 220, height: 14)
            block(width: nil, height: 64)
        }
        .padding(.vertical, 8)
    }

    private func block(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(6, height / 2))
            .fill(.quaternary)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

/// Something couldn't load: what, why in plain words, and a way to try
/// again.
struct ProblemView: View {
    let title: String
    let message: String
    var systemImage = "wifi.exclamationmark"
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview("Board") { LoadingRows(kind: .board) }
#Preview("Train") { LoadingRows(kind: .train) }
