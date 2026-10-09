import SwiftUI
import Combine

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
                Toggle("Countdown Timer", systemImage: "clock", isOn: $settings.showCountdown)
                Toggle("Next Connection", systemImage: "arrow.triangle.swap", isOn: $settings.showNextConnection)
                Toggle("Progress Bar", systemImage: "chart.bar.fill", isOn: $settings.showProgressBar)
                Toggle("Operator Name", systemImage: "building.2", isOn: $settings.showOperatorName)
                Toggle("Platform Badge", systemImage: "number", isOn: $settings.showPlatformBadge)
                Toggle("Delay Indicator", systemImage: "exclamationmark.triangle", isOn: $settings.showDelayBadge)
                Toggle("Final Arrival Time", systemImage: "flag.checkered", isOn: $settings.showFinalArrival)
            } header: {
                Text("Live Activity Display")
            } footer: {
                Text("Choose what information appears on the lock screen and Dynamic Island when tracking a journey. Changes apply to new tracking sessions.")
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

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .onReceive(NotificationCenter.default.publisher(for: ServerSettings.didChange)) { _ in
            server = ServerSettings.current
        }
        .onChange(of: settings) {
            settings.save()
        }
    }
}
