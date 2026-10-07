import SwiftUI

struct StationSearchView: View {
    @State private var searchService = LocationSearchService()
    @State private var query = ""
    let onSelect: (Location) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                        dismiss()
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                searchService.search(query: newValue)
            }
        }
    }
}
