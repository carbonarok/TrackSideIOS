import XCTest

/// Walks the route screens like a person would. Needs the simulator set up
/// with a reachable server (Settings → Server), as the journeys are live.
final class RouteNavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testOpeningALegShowsTheTrain() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedRoute"]
        app.launch()

        app.tabBars.buttons["Routes"].firstMatch.tap()
        app.staticTexts["UI Test Route"].firstMatch.tap()

        let card = app.buttons["journeyCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "No journeys were found")
        card.tap()

        let leg = app.buttons["journeyLeg"].firstMatch
        XCTAssertTrue(leg.waitForExistence(timeout: 5), "Expanding the journey showed no legs")
        leg.tap()

        // The train page shows its stops, or at least that it's loading;
        // a blank page shows neither.
        let loaded = app.staticTexts["Loading service..."].firstMatch
        let stops = app.collectionViews.firstMatch
        let shown = loaded.waitForExistence(timeout: 3) || stops.waitForExistence(timeout: 10)
        attach(app, name: "after tapping a leg")
        XCTAssertTrue(shown, "Tapping a leg showed a blank page")
        XCTAssertTrue(app.staticTexts["Woking"].firstMatch.waitForExistence(timeout: 15), "The train's stops never appeared")
        attach(app, name: "train page")
    }

    /// Board rows have no chevron; the whole row must still open the train.
    @MainActor
    func testTappingABoardRowShowsTheTrain() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lastStationCode", "CLJ", "-lastStationName", "Clapham Junction"]
        app.launch()

        app.tabBars.buttons["Departures"].firstMatch.tap()
        let row = app.staticTexts["Woking"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The board never showed a train")
        row.tap()

        XCTAssertTrue(app.staticTexts["Calling Points"].firstMatch.waitForExistence(timeout: 15), "Tapping a board row didn't open the train")
        attach(app, name: "train from board")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
