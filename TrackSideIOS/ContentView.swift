import SwiftUI

struct ContentView: View {
    let liveClient: LiveClient

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
    }
}
