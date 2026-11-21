import XCTest

final class ElsepinImportUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 180 }
    override func tearDownWithError() throws {
        if let app {
            let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "import-final"; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }
    private func launch(_ extra: [String] = []) {
        app = XCUIApplication(); app.launchArguments = ["--elsepin-ui-test"] + extra
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = "import-review"
        app.launch()
        XCTAssertTrue(app.buttons["Open GPX"].waitForExistence(timeout:20))
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name=name; shot.lifetime = .keepAlways; add(shot)
    }
    func testImportReviewApplyAndCancelPreserveEditor() {
        launch()
        app.buttons["Open GPX"].tap()
        XCTAssertTrue(app.buttons["gpx.apply"].waitForExistence(timeout:10))
        capture("gpx-review-light")
        app.buttons["gpx.cancel"].tap()
        XCTAssertTrue(app.staticTexts["Existing route preserved"].waitForExistence(timeout:5))
        app.buttons["Open GPX"].tap()
        XCTAssertTrue(app.buttons["gpx.apply"].waitForExistence(timeout:10))
        app.buttons["gpx.apply"].tap()
        XCTAssertTrue(app.staticTexts["Imported 2 points into planner"].waitForExistence(timeout:10))
    }
    func testLargeGPXCanSaveAndReopenWithoutLosingCorners() {
        launch()
        app.buttons["Open large GPX"].tap()
        XCTAssertTrue(app.buttons["gpx.apply"].waitForExistence(timeout:30))
        capture("large-gpx-review")
        app.buttons["gpx.apply"].tap()
        XCTAssertTrue(app.staticTexts["Large GPX saved and reopened; all corners preserved"].waitForExistence(timeout:30))
    }
    func testRecoveryLimitsRetainExportableOriginals() {
        launch()
        app.buttons["Check recovery edge cases"].tap()
        XCTAssertTrue(app.staticTexts["Recovery limits and raw copies preserved"].waitForExistence(timeout:15))
        capture("recovery-edge-results")
    }
    func testRootImportOpensActualPlannerAfterReview() {
        app = XCUIApplication(); app.launchArguments = ["--elsepin-ui-test"]
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = "import-root"
        app.launch()
        XCTAssertTrue(app.buttons["validation.openGPX"].waitForExistence(timeout:20))
        app.buttons["validation.openGPX"].tap()
        XCTAssertTrue(app.buttons["gpx.apply"].waitForExistence(timeout:10))
        app.buttons["gpx.apply"].tap()
        XCTAssertTrue(app.navigationBars["Plan a route"].waitForExistence(timeout:15))
        capture("gpx-root-planner")
    }
    func testFailureRetryAndCancellationNeverReplaceEditor() {
        launch()
        app.buttons["Open broken GPX"].tap()
        XCTAssertTrue(app.staticTexts["gpx.error"].waitForExistence(timeout:10))
        app.buttons["gpx.retry"].tap()
        XCTAssertTrue(app.staticTexts["gpx.error"].waitForExistence(timeout:10))
        capture("gpx-failure-retry")
        app.buttons["gpx.cancel"].tap()
        app.buttons["Open slow GPX"].tap()
        XCTAssertTrue(app.buttons["gpx.cancel"].waitForExistence(timeout:5))
        app.buttons["gpx.cancel"].tap()
        XCTAssertTrue(app.staticTexts["Existing route preserved"].waitForExistence(timeout:5))
        app.buttons["Open GPX"].tap()
        XCTAssertTrue(app.buttons["gpx.apply"].waitForExistence(timeout:10))
        app.buttons["gpx.apply"].tap()
        XCTAssertTrue(app.staticTexts["Imported 2 points into planner"].waitForExistence(timeout:10))
    }
    func testRecoveryDiscardSurvivesReload() {
        launch()
        app.buttons["Recovery copies"].tap()
        XCTAssertTrue(app.buttons["recovery.export"].waitForExistence(timeout:10))
        capture("saved-place-recovery")
        app.buttons["Discard unreadable recovery copy"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.staticTexts["Saved-place recovery copy discarded. Your current library is unchanged."].waitForExistence(timeout:5))
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["Check recovery persisted"].tap()
        XCTAssertTrue(app.staticTexts["Recovery discarded after reload"].waitForExistence(timeout:5))
    }
    func testNarrowLargeTextDarkImportControlsRemainReachable() {
        launch(["--narrow","--large-text","--dark"])
        app.buttons["Open GPX"].tap()
        let apply = app.buttons["gpx.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout:10))
        for _ in 0..<5 where !apply.isHittable { app.swipeUp() }
        XCTAssertTrue(apply.isHittable)
        XCTAssertTrue(app.buttons["gpx.cancel"].isHittable)
        capture("gpx-large-dark")
        apply.tap()
        XCTAssertTrue(app.staticTexts["Imported 2 points into planner"].waitForExistence(timeout:10))
    }
}
