import SwiftUI
import SwiftData

struct RoutesListView: View {
    let liveClient: LiveClient

    @Environment(\.modelContext) private var modelContext
    @Query private var routes: [SavedRoute]
    @State private var showingEditor = false
    @State private var routeToEdit: SavedRoute?

    var body: some View {
        Group {
            if routes.isEmpty {
                ContentUnavailableView {
                    Label("No Routes", systemImage: "arrow.triangle.swap")
                } description: {
                    Text("Create a route to track your regular journeys with multiple trains")
                } actions: {
                    Button("Create Route") {
                        showingEditor = true
                    }
                }
            } else {
                List {
                    ForEach(orderedRoutes) { route in
                        DestinationLink(.route(route)) {
                            routeRow(route)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(route)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                routeToEdit = route
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                reverseRoute(route)
                            } label: {
                                Label("Reverse", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.orange)
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                }
                .sensoryFeedback(.selection, trigger: routes.map(\.sortOrder))
                .listStyle(.plain)
            }
        }
        .navigationTitle("Routes")
        .toolbar {
            if routes.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Add Route", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            RouteEditorView(liveClient: liveClient)
        }
        .sheet(item: $routeToEdit) { route in
            RouteEditorView(liveClient: liveClient, existingRoute: route)
        }
    }

    private func routeRow(_ route: SavedRoute) -> some View {
        let legs = route.sortedLegs
        let from = legs.first?.originName ?? ""
        let to = legs.last.map { $0.destinationName ?? $0.destinationCode ?? "" } ?? ""
        let changes = legs.dropFirst().map(\.originName)

        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.headline)
                Text("\(from) → \(to)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !changes.isEmpty {
                    Text("Change at \(changes.formatted(.list(type: .and)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            NextJourneyLine(route: route)
        }
        .padding(.vertical, 6)
    }

    private var orderedRoutes: [SavedRoute] {
        SavedRoute.ordered(routes)
    }

    /// Drag a route to a new place. Every route gets a place, so the order
    /// holds from then on; routes added later go on top.
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = orderedRoutes
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, route) in reordered.enumerated() {
            route.sortOrder = index
        }
    }

    private func delete(at offsets: IndexSet) {
        let shown = orderedRoutes
        for index in offsets {
            modelContext.delete(shown[index])
        }
    }

    private func reverseRoute(_ route: SavedRoute) {
        let reversed = route.reversed()
        modelContext.insert(reversed)
    }
}

/// A route's next journey, at a glance: when it leaves and arrives, from
/// which platform, and whether it's on time. Shows the journey saved last
/// time straight away, then checks with the server, and again each minute.
private struct NextJourneyLine: View {
    let route: SavedRoute

    /// Its own calculator, not saving: the route page saves its full list
    /// of journeys, which one journey shouldn't replace.
    @State private var calculator = JourneyCalculator(usesStore: false)
    @State private var saved: CalculatedJourney?

    var body: some View {
        Group {
            if let journey = calculator.journeys.first ?? saved {
                line(journey)
            } else if calculator.error != nil {
                Text("No trains soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Finding the next train…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: route.persistentModelID) {
            let legs = route.sortedLegs.map(RouteLegPlan.init)
            if let stored = await JourneyStore.load(key: JourneyStore.key(for: legs)) {
                saved = JourneyStore.usable(stored, for: .now).first
            }
            while !Task.isCancelled {
                await calculator.calculateMultiple(route: route, departAt: .now, count: 1)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func line(_ journey: CalculatedJourney) -> some View {
        HStack(spacing: 6) {
            Text("NEXT")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
            SplitFlapText(text: clockTime(journey.departureTime) ?? "--:--", style: .subheadline)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            SplitFlapText(text: clockTime(journey.arrivalTime) ?? "--:--", style: .subheadline)
            PlatformBadge(number: journey.legs.first?.departurePlatform, compact: true)
            Spacer(minLength: 4)
            status(journey)
        }
        .accessibilityElement(children: .combine)
    }

    private func status(_ journey: CalculatedJourney) -> some View {
        let delay = journey.legs.compactMap { $0.departureDelay ?? $0.arrivalDelay }.max() ?? 0
        let (text, color): (String, Color) = journey.hasIssues
            ? ("Disrupted", .delaySevere)
            : delay > 0 ? ("+\(delay) min", .delay(minutes: delay)) : ("On time", .onTime)
        return Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .fixedSize()
    }
}
