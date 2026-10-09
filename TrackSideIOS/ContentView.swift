import SwiftUI

struct ContentView: View {
    let liveClient: LiveClient
    /// There's no default server, so the first launch asks for one.
    @State private var needsServer = ServerSettings.current == nil

    var body: some View {
        TabView {
            Tab("Departures", systemImage: "clock") {
                NavigationStack {
                    DepartureBoardView(liveClient: liveClient)
                }
            }

            Tab("Routes", systemImage: "arrow.triangle.swap") {
                NavigationStack {
                    RoutesListView(liveClient: liveClient)
                }
            }

            Tab("History", systemImage: "clock.arrow.circlepath") {
                NavigationStack {
                    JourneyHistoryView()
                }
            }

            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .fullScreenCover(isPresented: $needsServer) {
            NavigationStack {
                ServerSettingsView {
                    needsServer = false
                }
            }
            .interactiveDismissDisabled()
        }
    }
}
