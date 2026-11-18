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
    }

    @ViewBuilder
    private func routeRow(_ route: SavedRoute) -> some View {
        let legs = route.sortedLegs

        VStack(alignment: .leading, spacing: 8) {
            Text(route.name)
                .font(.headline)

            // Visual route line with station names
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(legs.enumerated()), id: \.element.id) { index, leg in
                    if index > 0 {
                        // Connection indicator
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(.secondary.opacity(0.3))
                                .frame(height: 2)
                                .frame(maxWidth: .infinity)
                            Text("change")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 5)
                    }

                    // Station dot + name
                    VStack(spacing: 3) {
                        Circle()
                            .fill(index == 0 ? .green : .blue)
                            .frame(width: 10, height: 10)
                        Text(leg.originName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(minWidth: 44)

                    // Line between origin and destination of this leg
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(.blue.opacity(0.4))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 5)

                    // Final destination (only on last leg)
                    if index == legs.count - 1 {
                        VStack(spacing: 3) {
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                            Text(leg.destinationName ?? leg.destinationCode ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(minWidth: 44)
                    }
                }
            }

            // Stats row
            HStack(spacing: 8) {
                Label("\(legs.count) train\(legs.count == 1 ? "" : "s")", systemImage: "tram.fill")
                if legs.count > 1 {
                    Label("\(legs.count - 1) change\(legs.count > 2 ? "s" : "")", systemImage: "arrow.triangle.swap")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func reverseRoute(_ route: SavedRoute) {
        let reversed = route.reversed()
        modelContext.insert(reversed)
    }
}
