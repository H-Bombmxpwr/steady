import XCTest

/// The Day Plan has to be reachable both ways: as its own tab, and pushed
/// from the Today screen.
///
/// The pushed route is the one worth a test. A screen that supplies its own
/// `NavigationStack` cannot be pushed onto one — SwiftUI navigates to a blank
/// screen rather than failing — so the bug is invisible to the compiler, to
/// unit tests, and to anyone not looking at the actual device.
final class DayPlanUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetStore", "-seedDemo"]
        addUIInterruptionMonitor(withDescription: "system alert") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launch()
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 15)
        app.swipeDown(velocity: .slow)
        return app
    }

    /// Scroll without tapping — a fast swipe over a card of buttons reads as
    /// a tap often enough to make this flaky.
    private func scroll(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    func testDayPlanTabOpens() {
        let app = launch()
        let tab = app.tabBars.buttons["Day Plan"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "the Day Plan tab should exist")
        tab.tap()
        XCTAssertTrue(app.buttons["dayplan.adjust"].waitForExistence(timeout: 10),
                      "the Day Plan tab opened on nothing")
    }

    /// Five tabs, and the last one is Workouts every time — no system "More"
    /// list, and no picker asking which screen you meant.
    func testLastTabIsAlwaysWorkouts() {
        let app = launch()
        XCTAssertFalse(app.tabBars.buttons["More"].exists,
                       "the system More tab should be gone entirely")
        XCTAssertFalse(app.tabBars.buttons["Photos"].exists,
                       "Photos moved to the Calendar — it shouldn't hold a tab")

        let workouts = app.tabBars.buttons["Workouts"]
        XCTAssertTrue(workouts.waitForExistence(timeout: 15))
        workouts.tap()

        // Straight there: no sheet in between.
        XCTAssertFalse(app.buttons["overflow.workouts"].exists,
                       "tapping Workouts should not ask which screen you meant")
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 5),
                      "the Workouts tab opened on nothing")
    }

    /// Photos hangs off the Calendar now, and has to actually arrive — it
    /// owns a NavigationStack of its own, which is the same trap the day plan
    /// fell into.
    func testPhotosPushesFromTheCalendar() {
        let app = launch()
        let calendar = app.tabBars.buttons["Calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 15))
        calendar.tap()

        let photos = app.buttons["calendar.photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5),
                      "the Calendar should offer a way into Progress Photos")
        photos.tap()

        XCTAssertTrue(app.navigationBars["Progress Photos"].waitForExistence(timeout: 10),
                      "Progress Photos went nowhere — the destination is empty")
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).exists,
                      "no back button — the push replaced the stack instead of adding to it")
    }

    /// Settings has one home: the dashboard.
    func testDayPlanHasNoSettingsGear() {
        let app = launch()
        let tab = app.tabBars.buttons["Day Plan"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        XCTAssertTrue(app.buttons["dayplan.adjust"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Settings"].exists,
                       "Settings belongs on the dashboard, not on every tab")
    }

    /// The regression this file exists for.
    func testPlanTheWholeDayPushesSomewhereReal() {
        let app = launch()

        let openToday = app.buttons["Open Today"].firstMatch
        XCTAssertTrue(openToday.waitForExistence(timeout: 15))
        openToday.tap()

        let link = app.buttons["Plan the Whole Day"].firstMatch
        for _ in 0..<6 where !link.exists {
            scroll(app)
        }
        XCTAssertTrue(link.waitForExistence(timeout: 5),
                      "\"Plan the Whole Day\" should be in the Food section of Today")
        link.tap()

        // The Day Plan's own control. If the push landed on a dead end —
        // which is exactly what a nested NavigationStack produces — nothing
        // below exists and the screen is blank.
        XCTAssertTrue(app.buttons["dayplan.adjust"].waitForExistence(timeout: 10),
                      "Plan the Whole Day went nowhere — the destination is empty")

        // And it must still be a pushed screen, not a new root: the way back
        // to Today has to be there.
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).exists,
                      "no back button — the push replaced the stack instead of adding to it")
    }
}
