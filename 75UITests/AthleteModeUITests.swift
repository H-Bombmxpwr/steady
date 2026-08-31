import XCTest

/// The mode split: an athlete profile must land on the athlete dashboard, a
/// general-health profile on its own, and a weight-loss profile on the
/// original one. These are the three experiences the whole feature rests on,
/// so a regression here is worth catching loudly.
final class AthleteModeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        // These tests share one simulator container, so each run starts from
        // an empty store — otherwise the seeds no-op and a test inherits
        // whichever mode ran before it.
        app.launchArguments = ["-resetStore", seed]
        // Permission alerts (notifications on a fresh install) would otherwise
        // sit over the first screen and fail every assertion below.
        addUIInterruptionMonitor(withDescription: "system alert") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Don't Allow"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
        app.launch()
        // Deliver the interruption monitor without touching the UI: a bare
        // app.tap() lands in the middle of the screen and can open whatever
        // card happens to be there.
        _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)
        app.swipeDown(velocity: .slow)
        return app
    }

    /// Scroll without tapping. A fast swipe over a card full of buttons gets
    /// read as a tap often enough to make the test flaky.
    private func scroll(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Athlete mode opens on training, not on a weight trend.
    func testAthleteDashboardLeadsWithTraining() throws {
        let app = launch("-seedAthlete")

        let training = app.staticTexts["TODAY'S TRAINING"]
        XCTAssertTrue(training.waitForExistence(timeout: 8),
                      "athlete dashboard didn't lead with today's training")
        attach("athlete-dashboard-top")

        // The seeded plan has a hard threshold session today.
        XCTAssertTrue(app.staticTexts["Threshold 3x12"].exists,
                      "today's imported session is missing")
        // Macros are periodized, so carbs must be shown as their own target.
        XCTAssertTrue(app.staticTexts["Carbs"].exists, "carb target is missing")
    }

    /// Scrolling reaches hydration, the week, and the locked cycle card.
    func testAthleteDashboardCards() throws {
        let app = launch("-seedAthlete")
        XCTAssertTrue(app.staticTexts["TODAY'S TRAINING"].waitForExistence(timeout: 8))

        scroll(app)
        XCTAssertTrue(app.staticTexts["HYDRATION"].waitForExistence(timeout: 4),
                      "hydration card is missing")
        attach("athlete-hydration")

        scroll(app)
        // Cycle tracking is on in the seed, and must be locked by default.
        let cycle = app.staticTexts["CYCLE"]
        XCTAssertTrue(cycle.waitForExistence(timeout: 4), "cycle card is missing")
        XCTAssertTrue(app.staticTexts["Locked"].exists,
                      "cycle data must be locked until Face ID or the PIN unlocks it")
        // Nothing about the actual cycle may be visible while locked.
        XCTAssertFalse(app.staticTexts["Menstrual"].exists)
        XCTAssertFalse(app.staticTexts["Luteal"].exists)
        XCTAssertFalse(app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH 'Day '")).firstMatch.exists,
            "the day of the cycle must not be readable through the lock")
        attach("athlete-cycle-locked")

        scroll(app)
        XCTAssertTrue(app.staticTexts["WEEK AHEAD"].waitForExistence(timeout: 4),
                      "week-ahead card is missing")
        attach("athlete-week")
    }

    /// General health opens on the day and its quality metrics — no training
    /// card, and no goal weight anywhere on it.
    func testGeneralHealthDashboard() throws {
        let app = launch("-seedHealth")

        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 8),
                      "general-health dashboard didn't lead with today")
        XCTAssertFalse(app.staticTexts["TODAY'S TRAINING"].exists,
                       "athlete card leaked into general-health mode")
        attach("health-dashboard-top")

        XCTAssertTrue(app.staticTexts["GENERAL HEALTH"].waitForExistence(timeout: 4),
                      "the health metrics are the mode — they must be on the dashboard")

        scroll(app)
        XCTAssertTrue(app.staticTexts["MOVEMENT"].waitForExistence(timeout: 4),
                      "movement card is missing")
        attach("health-movement")

        scroll(app)
        // Cycle tracking is on in this seed too, and locked just the same.
        XCTAssertTrue(app.staticTexts["CYCLE"].waitForExistence(timeout: 4),
                      "cycle card is missing")
        XCTAssertTrue(app.staticTexts["Locked"].exists,
                      "cycle data must be locked until Face ID or the PIN unlocks it")
        attach("health-cycle-locked")

        scroll(app)
        XCTAssertTrue(app.staticTexts["WEIGHT"].waitForExistence(timeout: 4),
                      "weight is still tracked here, just not as the score")
        XCTAssertFalse(app.staticTexts["GOAL"].exists,
                       "general health has no goal weight to chase")
        attach("health-weight-and-streak")
    }

    /// Setup offers all three modes, and picking general health skips the
    /// goal-weight question entirely rather than asking for a number nobody
    /// in this mode has.
    func testSetupOffersGeneralHealthWithoutAGoalWeight() throws {
        let app = launch("-resetStore")

        let option = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'General Health'")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10),
                      "setup didn't offer general health as a mode")
        XCTAssertTrue(app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Athlete'")).firstMatch.exists)
        attach("setup-modes")

        option.tap()
        // The health metrics are the mode, so there's nothing left to opt into.
        XCTAssertFalse(app.switches["Also track general health"].exists,
                       "the add-on toggle belongs to the other two modes")

        app.buttons["Continue"].tap()      // past the mode step
        app.buttons["Continue"].tap()      // past the profile step

        XCTAssertTrue(app.navigationBars["Where You're At"].waitForExistence(timeout: 4),
                      "general health should go straight to the baseline step")
        XCTAssertTrue(app.textFields["Current weight (lb)"].exists)
        XCTAssertFalse(app.textFields["Goal weight (lb)"].exists,
                       "general health has no goal weight")
        attach("setup-baseline")
    }

    /// Weight-loss mode is untouched: it still opens on weight and today.
    func testWeightLossDashboardUnchanged() throws {
        let app = launch("-seedDemo")

        XCTAssertTrue(app.staticTexts["WEIGHT"].waitForExistence(timeout: 8),
                      "weight-loss dashboard didn't lead with weight")
        XCTAssertFalse(app.staticTexts["TODAY'S TRAINING"].exists,
                       "athlete card leaked into weight-loss mode")
        attach("weightloss-dashboard")
    }
}
