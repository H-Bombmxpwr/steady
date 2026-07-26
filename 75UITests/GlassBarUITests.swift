import XCTest

/// Device-reported glass-bar regressions, reproduced mechanically:
/// bottom-of-page content hiding under the floating bar, and one-tab bead
/// slides snapping back to the tab they started on.
final class GlassBarUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemo"]
        app.launch()
        return app
    }

    /// The dashboard's last row must clear the floating bar: after
    /// scrolling to the end, Open Today has to be hittable AND actually
    /// receive its tap (a covered button hit-tests to the bar instead).
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

        XCTAssertTrue(openToday.isHittable, "Open Today sits under the glass bar")
        openToday.tap()
        // Tapping must push the day screen (its Add Food row carries a
        // combined label, so match by prefix).
        let addFood = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Add Food'")).firstMatch
        XCTAssertTrue(addFood.waitForExistence(timeout: 4),
                      "Open Today tap was swallowed — bar is covering it")
    }

    /// Slide the bead exactly one tab-width (Dashboard → Stats), slowly and
    /// with a hold before release so there's no flick momentum. It must
    /// land on Stats and stay there.
    func testBeadOneTabSlideSticks() throws {
        let app = launch()
        let window = app.windows.firstMatch
        let f = window.frame

        // Bar geometry mirrors GlassTabBar: 14pt outer padding, 5pt inner
        // inset, 56pt tall, 2pt above the bottom safe area (~34pt).
        let innerWidth = f.width - 28 - 10
        let tabWidth = innerWidth / 5
        let barY = f.maxY - 34 - 2 - 28
        func tabCenter(_ i: CGFloat) -> XCUICoordinate {
            window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 14 + 5 + (i + 0.5) * tabWidth, dy: barY))
        }

        tabCenter(0).press(forDuration: 0.2, thenDragTo: tabCenter(1),
                           withVelocity: 200, thenHoldForDuration: 0.3)

        // The pager keeps every page in the hierarchy, so `exists` is
        // meaningless — hittable (on screen) is the real check. Wait for
        // it: an instant check races the settle spring.
        let statsPicker = app.buttons["Body"]
        let hittable = NSPredicate(format: "isHittable == true")
        expectation(for: hittable, evaluatedWith: statsPicker)
        waitForExpectations(timeout: 4)

        // Give a wrong settle time to happen, then re-check it stuck.
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertTrue(statsPicker.isHittable, "bead snapped back after release")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "after-one-tab-slide"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
