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

        tab("Routes", in: app).tap()
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

        tab("Departures", in: app).tap()
        let row = app.staticTexts["Woking"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "The board never showed a train")
        row.tap()

        XCTAssertTrue(app.staticTexts["Calling Points"].firstMatch.waitForExistence(timeout: 15), "Tapping a board row didn't open the train")
        attach(app, name: "train from board")
    }

    /// Starts tracking a journey and leaves its Live Activity on screen,
    /// to look at the Dynamic Island (on the iPhone Duo it runs vertically
    /// beside the camera). The screenshot is the thing to check.
    @MainActor
    func testTrackingShowsALiveActivity() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedRoute"]
        app.launch()

        tab("Routes", in: app).tap()
        app.staticTexts["UI Test Route"].firstMatch.tap()
        let card = app.buttons["journeyCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "No journeys were found")
        card.tap()

        let track = app.buttons["Track This Journey"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5), "No Track button")
        track.tap()
        // The system may ask to allow Live Activities.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        sleep(3)

        // The board leads with the train being tracked.
        if app.buttons["Show the List"].firstMatch.exists { app.buttons["Show the List"].firstMatch.tap() }
        tab("Departures", in: app).tap()
        XCTAssertTrue(app.staticTexts["Tracking"].firstMatch.waitForExistence(timeout: 10),
                      "No tracking banner on the board")

        XCUIDevice.shared.press(.home)
        sleep(3)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "live activity"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// On an unfolded iPhone Duo, an open route or train can take both
    /// halves, splitting itself at the fold. Skipped elsewhere: the button
    /// only appears beside a fold.
    @MainActor
    func testUsingBothHalves() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedRoute", "-lastStationCode", "CLJ", "-lastStationName", "Clapham Junction"]
        app.launch()

        tab("Routes", in: app).tap()
        app.staticTexts["UI Test Route"].firstMatch.tap()
        let bothHalves = app.buttons["Use Both Halves"].firstMatch
        guard bothHalves.waitForExistence(timeout: 10) else {
            throw XCTSkip("No fold here, so no two-half layout")
        }
        bothHalves.tap()
        XCTAssertTrue(app.buttons["journeyLeg"].firstMatch.waitForExistence(timeout: 30),
                      "The chosen journey's trains should show beside the journeys, without expanding a card")
        attach(app, name: "route on both halves")
        holdForScreenshot("route on both halves")
        app.buttons["Show the List"].firstMatch.tap()

        tab("Departures", in: app).tap()
        let row = app.staticTexts["Woking"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.buttons["Use Both Halves"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Use Both Halves"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Calling Points"].firstMatch.waitForExistence(timeout: 15))
        attach(app, name: "train on both halves")
        for button in app.buttons.allElementsBoundByIndex.prefix(30) {
            print("BUTTON \(button.label) \(button.frame)")
        }
        XCTAssertTrue(app.buttons["Show the List"].firstMatch.exists, "No way back to the board")
        holdForScreenshot("train on both halves")
    }

    /// Half-folded like a laptop, with the fold across the screen, an open
    /// train shows a platform display in the top half. The simulator lies
    /// flat and won't turn sideways, so -UITestTabletop pretends there's a
    /// bent fold halfway down.
    @MainActor
    func testTabletopShowsAPlatformDisplay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestTabletop", "-lastStationCode", "CLJ", "-lastStationName", "Clapham Junction"]
        app.launch()

        tab("Departures", in: app).tap()
        let row = app.staticTexts["Woking"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["platformDisplay"].firstMatch.waitForExistence(timeout: 15),
                      "No platform display in the top half")
        holdForScreenshot("tabletop")
    }

    /// XCTest's own screenshots of an iPhone Duo's inner screen come out
    /// black, so with HOLD_FOR_SCREENSHOTS set (TEST_RUNNER_HOLD_FOR_SCREENSHOTS
    /// to xcodebuild) the test waits, for `simctl io screenshot` instead.
    private func holdForScreenshot(_ name: String) {
        guard ProcessInfo.processInfo.environment["HOLD_FOR_SCREENSHOTS"] != nil else { return }
        print("HOLD \(name) \(Date().timeIntervalSince1970)")
        sleep(12)
    }

    /// A tab's button. It's found by name anywhere, not only in a tab bar:
    /// on the iPhone Duo the tabs are a vertical strip beside the content.
    private func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No \(name) tab")
        return button
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
