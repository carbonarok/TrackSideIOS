import SwiftUI
import Combine
import ActivityKit

struct SettingsView: View {
    @State private var settings = LiveActivitySettings.load()
    @State private var server = ServerSettings.current

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ServerSettingsView()
                } label: {
                    LabeledContent {
                        Text(server?.displayName ?? "Not set up")
                    } label: {
                        Label("Server", systemImage: "server.rack")
                    }
                }
            }

            Section {
                LiveActivityPreview(settings: settings)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("Live Activity Display")
            }

            Section {
                Toggle("Countdown Timer", systemImage: "clock", isOn: $settings.showCountdown)
                Toggle("Next Connection", systemImage: "arrow.triangle.swap", isOn: $settings.showNextConnection)
                Toggle("Progress Bar", systemImage: "chart.bar.fill", isOn: $settings.showProgressBar)
                Toggle("Operator Name", systemImage: "building.2", isOn: $settings.showOperatorName)
                Toggle("Platform Badge", systemImage: "number", isOn: $settings.showPlatformBadge)
                Toggle("Delay Indicator", systemImage: "exclamationmark.triangle", isOn: $settings.showDelayBadge)
                Toggle("Final Arrival Time", systemImage: "flag.checkered", isOn: $settings.showFinalArrival)
            } footer: {
                Text("Choose what shows on the lock screen and in the Dynamic Island while you track a journey. Changes show straight away, even on a journey you're already tracking.")
            }

            Section {
                Stepper(value: $settings.minimumConnectionMinutes, in: 1...30) {
                    HStack {
                        Label("Connection Time", systemImage: "figure.walk")
                        Spacer()
                        Text("\(settings.minimumConnectionMinutes) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Journey Planning")
            } footer: {
                Text("Minimum time allowed between arriving and the next train departing. Increase this if you need more time to change platforms.")
            }

            Section {
                LabeledContent("Version", value: Self.version)
            } header: {
                Text("About")
            } footer: {
                VStack(spacing: 6) {
                    Image("AppLogo")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    Text("TrackSide")
                        .font(.footnote)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .accessibilityHidden(true)
            }
        }
        .navigationTitle("Settings")
        .onReceive(NotificationCenter.default.publisher(for: ServerSettings.didChange)) { _ in
            server = ServerSettings.current
        }
        .onChange(of: settings) {
            settings.save()
            Task { await Self.redrawLiveActivities() }
        }
        .sensoryFeedback(.selection, trigger: settings)
    }

    /// Live Activities only redraw when updated; updating each running one
    /// with what it already shows redraws it with the new switches.
    private static func redrawLiveActivities() async {
        for activity in Activity<LegActivityAttributes>.activities {
            await activity.update(activity.content)
        }
    }

    /// "1.2 (34)", from the app's Info.plist.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}
