import SwiftUI
import SwiftData

/// Lightweight identifier for navigating to a service detail view
struct ServiceRoute: Hashable, Identifiable {
    let uid: String
    let runDate: String
    var id: String { "\(uid)|\(runDate)" }
}

struct ContentView: View {
    let liveClient: LiveClient
    /// There's no default server, so the first launch asks for one.
    @State private var needsServer = ServerSettings.current == nil
    @State private var selectedTab = "departures"
    @State private var departuresPath = NavigationPath()
    @State private var routesPath = NavigationPath()

    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveJourneyManager.self) private var journeyManager
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var routes: [SavedRoute]

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Departures", systemImage: "clock", value: "departures") {
                NavigationStack(path: $departuresPath) {
                    DepartureBoardView(liveClient: liveClient)
                        .navigationDestination(for: ServiceRoute.self) { service in
                            ServiceDetailView(
                                uid: service.uid,
                                runDate: service.runDate,
                                liveClient: liveClient
                            )
                        }
                }
            }

            Tab("Routes", systemImage: "arrow.triangle.swap", value: "routes") {
                NavigationStack(path: $routesPath) {
                    RoutesListView(liveClient: liveClient)
                        .navigationDestination(for: SavedRoute.self) { route in
                            RouteDetailView(route: route, liveClient: liveClient)
                        }
                        .navigationDestination(for: ServiceRoute.self) { service in
                            ServiceDetailView(
                                uid: service.uid,
                                runDate: service.runDate,
                                liveClient: liveClient
                            )
                        }
                }
            }

            Tab("History", systemImage: "clock.arrow.circlepath", value: "history") {
                NavigationStack {
                    JourneyHistoryView()
                }
            }

            Tab("Settings", systemImage: "gear", value: "settings") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .fullScreenCover(isPresented: $needsServer) {
            NavigationStack {
                ServerSettingsView {
                    needsServer = false
                }
            }
            .interactiveDismissDisabled()
        }
        .task {
            journeyManager.onJourneyComplete = { [modelContext] record in
                modelContext.insert(record)
                try? modelContext.save()
                print("[ContentView] Saved journey record: \(record.routeName)")
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "trackside" else { return }

        switch url.host {
        case "service":
            // Open service detail from Live Activity tap — navigate in Departures tab
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let uid = components?.queryItems?.first(where: { $0.name == "uid" })?.value,
               let date = components?.queryItems?.first(where: { $0.name == "date" })?.value {
                selectedTab = "departures"
                departuresPath = NavigationPath()
                departuresPath.append(ServiceRoute(uid: uid, runDate: date))
            }
        case "journey":
            // Navigate to the tracked route
            selectedTab = "routes"
            routesPath = NavigationPath()
            if let trackedID = journeyManager.trackedRouteID,
               let route = routes.first(where: { $0.persistentModelID == trackedID }) {
                routesPath.append(route)
            }
        default:
            break
        }
    }
}
