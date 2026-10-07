import SwiftUI
import SwiftData

struct RouteEditorView: View {
    let liveClient: LiveClient
    var existingRoute: SavedRoute?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var routeName = ""
    @State private var legs: [LegData] = [LegData()]
    @State private var searchContext: SearchContext?

    struct LegData: Identifiable {
        let id = UUID()
        var originCode = ""
        var originName = ""
        var destinationCode = ""
        var destinationName = ""
        var departurePlatforms = ""
        var arrivalPlatforms = ""
    }

    /// Tracks which leg field we're searching for
    struct SearchContext: Identifiable {
        let id = UUID()
        let legIndex: Int
        let field: Field

        enum Field {
            case origin, destination
        }
    }

    init(liveClient: LiveClient, existingRoute: SavedRoute? = nil) {
        self.liveClient = liveClient
        self.existingRoute = existingRoute
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route Name") {
                    TextField("e.g. Morning Commute", text: $routeName)
                }

                ForEach(Array(legs.enumerated()), id: \.element.id) { index, _ in
                    legSection(index: index)
                }

                Section {
                    Button {
                        var newLeg = LegData()
                        if let lastLeg = legs.last, !lastLeg.destinationCode.isEmpty {
                            newLeg.originCode = lastLeg.destinationCode
                            newLeg.originName = lastLeg.destinationName
                        }
                        legs.append(newLeg)
                    } label: {
                        Label("Add Leg", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(existingRoute == nil ? "New Route" : "Edit Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .navigationDestination(item: $searchContext) { context in
                StationSearchInlineView { location in
                    applySelection(location, to: context)
                    searchContext = nil
                }
            }
            .onAppear {
                if let route = existingRoute {
                    routeName = route.name
                    legs = route.sortedLegs.map { leg in
                        LegData(
                            originCode: leg.originCode,
                            originName: leg.originName,
                            destinationCode: leg.destinationCode ?? "",
                            destinationName: leg.destinationName ?? "",
                            departurePlatforms: leg.preferredDeparturePlatform ?? "",
                            arrivalPlatforms: leg.preferredArrivalPlatform ?? ""
                        )
                    }
                    if legs.isEmpty { legs = [LegData()] }
                }
            }
        }
    }

    @ViewBuilder
    private func legSection(index: Int) -> some View {
        Section {
            LegEditorView(
                originCode: $legs[index].originCode,
                originName: $legs[index].originName,
                destinationCode: $legs[index].destinationCode,
                destinationName: $legs[index].destinationName,
                departurePlatforms: $legs[index].departurePlatforms,
                arrivalPlatforms: $legs[index].arrivalPlatforms,
                onSearchOrigin: {
                    searchContext = SearchContext(legIndex: index, field: .origin)
                },
                onSearchDestination: {
                    searchContext = SearchContext(legIndex: index, field: .destination)
                }
            )
        } header: {
            HStack {
                Text("Leg \(index + 1)")
                Spacer()
                if legs.count > 1 {
                    Button("Remove") {
                        legs.remove(at: index)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    private func applySelection(_ location: Location, to context: SearchContext) {
        guard context.legIndex < legs.count else { return }
        switch context.field {
        case .origin:
            legs[context.legIndex].originCode = location.displayCode
            legs[context.legIndex].originName = location.name
        case .destination:
            legs[context.legIndex].destinationCode = location.displayCode
            legs[context.legIndex].destinationName = location.name
        }
    }

    private var isValid: Bool {
        !routeName.trimmingCharacters(in: .whitespaces).isEmpty &&
        legs.allSatisfy { !$0.originCode.isEmpty }
    }

    private func save() {
        if let route = existingRoute {
            route.name = routeName
            for leg in route.legs {
                modelContext.delete(leg)
            }
            route.legs = legs.enumerated().map { index, data in
                SavedLeg(
                    order: index,
                    originCode: data.originCode,
                    originName: data.originName,
                    destinationCode: data.destinationCode.isEmpty ? nil : data.destinationCode,
                    destinationName: data.destinationName.isEmpty ? nil : data.destinationName,
                    preferredDeparturePlatform: data.departurePlatforms.isEmpty ? nil : data.departurePlatforms,
                    preferredArrivalPlatform: data.arrivalPlatforms.isEmpty ? nil : data.arrivalPlatforms
                )
            }
        } else {
            let savedLegs = legs.enumerated().map { index, data in
                SavedLeg(
                    order: index,
                    originCode: data.originCode,
                    originName: data.originName,
                    destinationCode: data.destinationCode.isEmpty ? nil : data.destinationCode,
                    destinationName: data.destinationName.isEmpty ? nil : data.destinationName,
                    preferredDeparturePlatform: data.departurePlatforms.isEmpty ? nil : data.departurePlatforms,
                    preferredArrivalPlatform: data.arrivalPlatforms.isEmpty ? nil : data.arrivalPlatforms
                )
            }
            let route = SavedRoute(name: routeName, legs: savedLegs)
            modelContext.insert(route)
        }
        dismiss()
    }
}

// MARK: - Hashable conformance for navigation

extension RouteEditorView.SearchContext: Hashable {
    static func == (lhs: RouteEditorView.SearchContext, rhs: RouteEditorView.SearchContext) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Inline station search (pushed via navigation, not a sheet)

struct StationSearchInlineView: View {
    @State private var searchService = LocationSearchService()
    @State private var query = ""
    let onSelect: (Location) -> Void

    var body: some View {
        List {
            if searchService.isSearching {
                HStack {
                    ProgressView()
                    Text("Searching...")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(searchService.results) { location in
                Button {
                    onSelect(location)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name)
                                .font(.body)
                            if let crs = location.crs {
                                Text(crs)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            }

            if !query.isEmpty && query.count >= 2 && searchService.results.isEmpty && !searchService.isSearching {
                ContentUnavailableView(
                    "No stations found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term")
                )
            }
        }
        .navigationTitle("Find Station")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Station name or code")
        .onChange(of: query) { _, newValue in
            searchService.search(query: newValue)
        }
    }
}
