import SwiftUI
import os
import SwiftData
import os

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
    @State private var departuresPath: [AppDestination] = []
    @State private var routesPath: [AppDestination] = []

    @Environment(\.modelContext) private var modelContext
    @Environment(ActiveJourneyManager.self) private var journeyManager
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var routes: [SavedRoute]

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Departures", systemImage: "clock", value: "departures") {
                AdaptiveNavigation(path: $departuresPath) {
                    DepartureBoardView(liveClient: liveClient)
                } destination: { destination in
                    destinationView(destination)
                } placeholder: {
                    ContentUnavailableView(
                        "No Train Selected",
                        systemImage: "train.side.front.car",
                        description: Text("Choose a train from the board to see its stops and where it is.")
                    )
                }
            }

            Tab("Routes", systemImage: "arrow.triangle.swap", value: "routes") {
                AdaptiveNavigation(path: $routesPath) {
                    RoutesListView(liveClient: liveClient)
                } destination: { destination in
                    destinationView(destination)
                } placeholder: {
                    ContentUnavailableView(
                        "No Route Selected",
                        systemImage: "arrow.triangle.swap",
                        description: Text("Choose a route to see its next journeys.")
                    )
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
        .onChange(of: routes) { _, routes in
            // Side by side, a route can be deleted from the list while it's
            // open next to it. Close it rather than show a deleted route.
            if case .route(let open) = routesPath.first, !routes.contains(open) {
                routesPath = []
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
        .task {
            #if DEBUG
            seedRouteForUITests()
            #endif
            journeyManager.onJourneyComplete = { [modelContext] record in
                modelContext.insert(record)
                try? modelContext.save()
                Log.app.info("Saved journey record: \(String(describing: record.routeName), privacy: .public)")
            }
        }
    }

    #if DEBUG
    /// UI tests launch with `-UITestSeedRoute` to start with one route, so
    /// they can test the route screens without typing one in.
    private func seedRouteForUITests() {
        guard ProcessInfo.processInfo.arguments.contains("-UITestSeedRoute"), routes.isEmpty else { return }
        let leg = SavedLeg(order: 0, originCode: "CLJ", originName: "Clapham Junction", destinationCode: "WOK", destinationName: "Woking")
        modelContext.insert(SavedRoute(name: "UI Test Route", legs: [leg]))
        try? modelContext.save()
    }
    #endif

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .service(let service):
            ServiceDetailView(uid: service.uid, runDate: service.runDate, liveClient: liveClient)
        case .route(let route):
            RouteDetailView(route: route, liveClient: liveClient)
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
                departuresPath = [.service(ServiceRoute(uid: uid, runDate: date))]
            }
        case "journey":
            // Navigate to the tracked route
            selectedTab = "routes"
            routesPath = []
            if let trackedID = journeyManager.trackedRouteID,
               let route = routes.first(where: { $0.persistentModelID == trackedID }) {
                routesPath = [.route(route)]
            }
        default:
            break
        }
    }
}
