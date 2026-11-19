import SwiftUI

/// What a tracked journey looks like on the lock screen, with the parts
/// switched on in Settings. A made-up journey, so the toggles below it show
/// what each one does.
struct LiveActivityPreview: View {
    let settings: LiveActivitySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "train.side.front.car")
                    .foregroundStyle(Color.signalGreen)
                Text("2W00")
                    .font(.subheadline.monospaced())
                    .fontWeight(.semibold)
                if settings.showOperatorName {
                    Text("South Western Railway")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if settings.showDelayBadge {
                    Text("+2 min")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(SplitFlap.late)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(SplitFlap.late.opacity(0.18), in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    SplitFlapText(text: "16:40", style: .title3, weight: .bold, color: SplitFlap.late)
                    Text("Clapham Junction")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    SplitFlapText(text: "17:05", style: .title3, weight: .bold)
                    Text("Woking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.showPlatformBadge || settings.showCountdown {
                HStack {
                    if settings.showPlatformBadge {
                        PlatformBadge(number: "7")
                    }
                    Spacer()
                    if settings.showCountdown {
                        Text("Leaves in 12 min")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }

            if settings.showProgressBar {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(Color.signalGreen).frame(width: geo.size.width * 0.35)
                    }
                }
                .frame(height: 5)
            }

            if settings.showNextConnection || settings.showFinalArrival {
                VStack(alignment: .leading, spacing: 4) {
                    if settings.showNextConnection {
                        Label("Then 17:15 to Guildford, Plat 4", systemImage: "arrow.triangle.swap")
                    }
                    if settings.showFinalArrival {
                        Label("Arrive Guildford 17:32", systemImage: "flag.checkered")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 24))
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .animation(.snappy, value: settings)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of a tracked journey on the lock screen")
    }
}

#Preview {
    LiveActivityPreview(settings: LiveActivitySettings())
        .padding()
}
