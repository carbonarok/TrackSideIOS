import SwiftUI

/// One search for stations and trains. Station names never have digits
/// and headcodes always do (2W00, 1A23), so a query with a digit in it also
/// looks for trains.
struct StationSearchView: View {
    let onSelect: (Location) -> Void
    var onSelectService: ((ServiceRoute) -> Void)?

    @State private var searchService = LocationSearchService()
    @State private var query = ""
    @State private var trains: [ServiceSummary] = []
    @State private var isSearchingTrains = false
    /// Opening search is for typing, so the keyboard comes straight up.
    @FocusState private var searchFocused: Bool

    @Environment(\.dismiss) private var dismiss

    private let apiClient = APIClient()

    private var looksLikeHeadcode: Bool {
        onSelectService != nil && query.count >= 3 && query.contains(where: \.isNumber)
    }

    var body: some View {
        NavigationStack {
            List {
                if searchService.isSearching || isSearchingTrains {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                }

                if !trains.isEmpty {
                    Section("Trains") {
                        ForEach(trains, id: \.id) { train in
                            Button {
                                dismiss()
                                onSelectService?(ServiceRoute(uid: train.uid, runDate: train.runDate))
                            } label: {
                                trainRow(train)
                            }
                            .tint(.primary)
                        }
                    }
                }

                if !searchService.results.isEmpty {
                    Section {
                        ForEach(searchService.results) { location in
                            Button {
                                onSelect(location)
                                dismiss()
                            } label: {
                                stationRow(location)
                            }
                            .tint(.primary)
                        }
                    } header: {
                        if !trains.isEmpty { Text("Stations") }
                    }
                }

                if query.count >= 2 && searchService.results.isEmpty && trains.isEmpty
                    && !searchService.isSearching && !isSearchingTrains {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: onSelectService == nil ? "Station name or code" : "Station, or a train's headcode"
            )
            .searchFocused($searchFocused)
            .onAppear { searchFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                searchService.search(query: newValue)
            }
            .task(id: query) {
                await searchTrains()
            }
        }
    }

    private func searchTrains() async {
        guard looksLikeHeadcode else {
            trains = []
            return
        }
        // Wait for a pause in typing.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearchingTrains = true
        defer { isSearchingTrains = false }
        let found = (try? await apiClient.searchServices(query: query.trimmingCharacters(in: .whitespaces).uppercased())) ?? []
        guard !Task.isCancelled else { return }
        trains = found
    }

    private func stationRow(_ location: Location) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                if let crs = location.crs {
                    Text(crs)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func trainRow(_ train: ServiceSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "train.side.front.car")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let headcode = train.headcode {
                        Text(headcode)
                            .font(.body.monospaced())
                            .fontWeight(.semibold)
                    }
                    if train.isCancelled {
                        StatusBadge(status: train.status, cancelled: true)
                    }
                }
                Text("\(train.originName) → \(train.destinationName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let op = train.operator {
                    Text(op.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
