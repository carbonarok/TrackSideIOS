import SwiftUI
import SwiftData

struct RoutesListView: View {
    let liveClient: LiveClient

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var routes: [SavedRoute]
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
                    ForEach(routes) { route in
                        NavigationLink(value: route) {
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
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Routes")
        .toolbar {
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
        .navigationDestination(for: SavedRoute.self) { route in
            RouteDetailView(route: route, liveClient: liveClient)
        }
    }

    @ViewBuilder
    private func routeRow(_ route: SavedRoute) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(route.name)
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(Array(route.sortedLegs.enumerated()), id: \.element.id) { index, leg in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(leg.originCode)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                if let lastLeg = route.sortedLegs.last, let dest = lastLeg.destinationCode {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(dest)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(.secondary)

            Text("\(route.sortedLegs.count) leg\(route.sortedLegs.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func reverseRoute(_ route: SavedRoute) {
        let reversed = route.reversed()
        modelContext.insert(reversed)
    }
}
