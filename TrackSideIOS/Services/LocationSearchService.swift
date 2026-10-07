import Foundation
import Observation

@Observable
final class LocationSearchService {
    var results: [Location] = []
    var isSearching = false

    private let apiClient = APIClient()
    private var searchTask: Task<Void, Never>?

    func search(query: String) {
        searchTask?.cancel()

        guard query.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            // Debounce 300ms
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            do {
                let locations = try await apiClient.searchLocations(query: query)
                if !Task.isCancelled {
                    results = locations
                    isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    results = []
                    isSearching = false
                }
            }
        }
    }

    func clear() {
        searchTask?.cancel()
        results = []
        isSearching = false
    }
}
