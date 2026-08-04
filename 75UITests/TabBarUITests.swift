import XCTest

/// The system tab bar (Liquid Glass on iOS 26): switching tabs works and
/// the dashboard's last row stays reachable above the bar.
final class TabBarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemo"]
        app.launch()
        return app
    }

    /// The dashboard's last row must clear the tab bar: after scrolling to
    /// the end, Open Today has to be hittable AND actually receive its tap.
    func testDashboardBottomClearsBar() throws {
        let app = launch()
        app.swipeUp(velocity: .fast)
        app.swipeUp(velocity: .fast)

        let openToday = app.buttons["Open Today"]
        XCTAssertTrue(openToday.waitForExistence(timeout: 5), "dashboard didn't load")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "dashboard-bottom"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(openToday.isHittable, "Open Today sits under the tab bar")
        openToday.tap()
        // Tapping must push the day screen (its Add Food row carries a
        // combined label, so match by prefix).
        let addFood = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Add Food'")).firstMatch
        XCTAssertTrue(addFood.waitForExistence(timeout: 4),
                      "Open Today tap was swallowed — bar is covering it")
    }

    /// Tapping the Stats tab lands on Stats and stays there.
    func testTabSwitchSticks() throws {
        let app = launch()

        let statsTab = app.tabBars.buttons["Stats"]
        XCTAssertTrue(statsTab.waitForExistence(timeout: 5), "tab bar didn't load")
        statsTab.tap()

        // The Stats screen's scope picker is its landmark.
        let statsPicker = app.buttons["Body"]
        let hittable = NSPredicate(format: "isHittable == true")
        expectation(for: hittable, evaluatedWith: statsPicker)
        waitForExpectations(timeout: 4)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "stats-tab"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
