import Foundation
import Testing
@testable import TrackSideIOS

@Suite("Route order")
struct RouteOrderTests {
    @Test("Routes never moved are newest first")
    func newestFirst() {
        let old = route("Old", created: 0)
        let new = route("New", created: 60)

        #expect(names(SavedRoute.ordered([old, new])) == ["New", "Old"])
    }

    @Test("Moved routes keep their places, with new routes above them")
    func movedRoutes() {
        let first = route("First", created: 0, place: 1)
        let second = route("Second", created: 60, place: 0)
        let added = route("Added", created: 120)

        #expect(names(SavedRoute.ordered([first, second, added])) == ["Added", "Second", "First"])
    }

    private func route(_ name: String, created: TimeInterval, place: Int? = nil) -> SavedRoute {
        let route = SavedRoute(name: name)
        route.createdAt = Date(timeIntervalSince1970: created)
        route.sortOrder = place
        return route
    }

    private func names(_ routes: [SavedRoute]) -> [String] {
        routes.map(\.name)
    }
}
