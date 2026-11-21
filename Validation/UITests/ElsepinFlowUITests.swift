import XCTest

final class ElsepinFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private var restoreAccessibility = false
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if let app, app.state == .runningForeground {
            capture("final-" + name)
            app.terminate()
        }
        // XCTest can abort through Objective-C when continueAfterFailure is false;
        // a Swift defer in the test method is not a reliable cleanup boundary.
        if restoreAccessibility {
            configureAccessibility(false)
            restoreAccessibility = false
        }
    }
    private func launch(_ scenario: String, large: Bool = false, dark: Bool = false, fallback: Bool = false, narrow: Bool = true) {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test"]
        if narrow { app.launchArguments.append("--narrow") }
        if large { app.launchArguments.append("--large-text") }
        if dark { app.launchArguments.append("--dark") }
        if fallback { app.launchArguments.append("--accessibility-fallback") }
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.staticTexts["validation.banner"].waitForExistence(timeout: 20))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow", "Keep Only While Using", "Change to Always Allow"] {
            let button = springboard.buttons[label]
            if button.exists { button.tap() }
        }
        if ["moving", "paused", "connecting", "failed", "map-pins"].contains(scenario) {
            let start = app.buttons["validation.start"]
            if !start.isEnabled, springboard.buttons["Allow"].waitForExistence(timeout: 5) {
                springboard.buttons["Allow"].tap()
            }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            start.tap()
        }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    private func launchRoutes() {
        launch("route-editing", narrow: false)
        let report = app.staticTexts["validation.routeRules"]
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Passed'"), object: report)
        XCTAssertEqual(XCTWaiter.wait(for: [passed], timeout: 20), .completed, report.label)
    }

    private func routeControl(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<9 {
            var bottom = app.frame.maxY - 60
            for label in ["Show route", "Save route & preview"] {
                let action = app.buttons[label]
                if action.exists && action.isHittable { bottom = min(bottom, action.frame.minY - 24) }
            }
            let top = app.frame.minY + 150
            // XCTest can call a partially covered row hittable even though
            // its center lies beneath the sticky Show route button.
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return element }
            let isAbove = element.exists && element.frame.minY < top
            // Start on the list below the map, not inside the pannable preview.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: isAbove ? 0.35 : 0.77))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: isAbove ? 0.77 : 0.35)))
        }
        XCTAssertTrue(element.exists && element.isHittable, "Unreachable route control: \(element)")
        return element
    }

    private func savedSnapshot() throws -> [String: Any] {
        app.buttons["Read saved data"].tap()
        let text = app.staticTexts["validation.savedSnapshot"].label
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(value["loadError"] as? String, "")
        return value
    }

    private func savedTrip() throws -> [String: Any] {
        try XCTUnwrap(savedSnapshot()["saved"] as? [String: Any])
    }

    private func closeRoute() {
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Read saved data"].waitForExistence(timeout: 5))
    }

    private func saveRouteChanges() {
        routeControl(app.buttons["Save changes"]).tap()
        XCTAssertTrue(app.alerts["Save trip"].waitForExistence(timeout: 5))
        app.alerts["Save trip"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Trip saved with its place names and stops."].waitForExistence(timeout: 5))
    }

    @discardableResult private func setVisibleSpeed(_ mode: String, position: CGFloat) throws -> Double {
        let slider = routeControl(app.sliders["\(mode) speed in miles per hour"])
        slider.adjust(toNormalizedSliderPosition: position)
        let text = try XCTUnwrap(slider.value as? String)
        return try XCTUnwrap(Double(text.components(separatedBy: " ")[0]))
    }

    func testUsualSpeedsApplyToNewRoutesAndPersist() throws {
        launchRoutes()
        app.buttons["Usual speeds"].tap()
        // XCUITest's normalized slider drag stops short of the track ends, so this
        // check uses a mid-range usual speed; RouteInteractionTests covers the bounds.
        let walk = try setVisibleSpeed("Walk", position: 0.9)
        XCTAssertGreaterThan(walk, 1)
        XCTAssertLessThan(walk, 6)
        capture("24-settings-walk-usual-speed")
        app.buttons["Done"].tap()
        XCTAssertEqual(try XCTUnwrap(savedSnapshot()["usualWalk"] as? Double), walk, accuracy: 0.05)
        for action in ["New drawn route", "New planned route"] {
            app.buttons[action].tap()
            let save = app.buttons["Save route & preview"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
            capture("25-" + action)
            save.tap()
            XCTAssertTrue(app.buttons["Read saved data"].waitForExistence(timeout: 5))
            let saved = try savedTrip()
            XCTAssertEqual(try XCTUnwrap(saved["speedMPH"] as? Double), walk, accuracy: 0.05)
            XCTAssertEqual(saved["mode"] as? String, "walk")
            app.buttons["Reopen last saved route"].tap()
            closeRoute()
            XCTAssertEqual(try XCTUnwrap(savedSnapshot()["draftSpeed"] as? Double), walk, accuracy: 0.05)
        }
        // A previously saved route must keep its assigned speed, not take 6.
        app.buttons["Open saved route"].tap()
        routeControl(app.buttons["Movement to Test cafe"]).tap()
        XCTAssertTrue(app.staticTexts["1.4 mph"].exists)
        capture("26-existing-speed-preserved")
    }

    func testSavedLegModeAndCustomSpeedsSurviveReopening() throws {
        launchRoutes()
        let before = try savedTrip()
        app.buttons["Open saved route"].tap()
        routeControl(app.buttons["Movement to Test cafe"]).tap()
        app.buttons["Drive"].tap()
        XCTAssertTrue(app.staticTexts["85.0 mph"].exists)
        let drive = try setVisibleSpeed("Drive", position: 0.5)
        XCTAssertGreaterThan(drive, 1); XCTAssertLessThan(drive, 85)
        capture("27-custom-drive-leg")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Recalculate directions"].waitForExistence(timeout: 5))
        app.buttons["Keep current path"].tap()
        capture("27b-kept-path-before-second-leg")
        routeControl(app.buttons["Movement to Test pond"]).tap()
        app.buttons["E-bike"].tap()
        XCTAssertTrue(app.staticTexts["31.0 mph"].exists)
        let bike = try setVisibleSpeed("E-bike", position: 0.35)
        app.buttons["Done"].tap()
        if app.buttons["Keep current path"].waitForExistence(timeout: 2) { app.buttons["Keep current path"].tap() }
        saveRouteChanges()
        closeRoute()
        let saved = try savedTrip()
        XCTAssertEqual(saved["id"] as? String, before["id"] as? String)
        let sections = try XCTUnwrap(saved["travelSections"] as? [[String: Any]])
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0]["mode"] as? String, "drive")
        XCTAssertEqual(try XCTUnwrap(sections[0]["speedMPH"] as? Double), drive, accuracy: 0.11)
        XCTAssertEqual(sections[1]["mode"] as? String, "eBike")
        XCTAssertEqual(try XCTUnwrap(sections[1]["speedMPH"] as? Double), bike, accuracy: 0.11)
        app.buttons["Reopen last saved route"].tap()
        routeControl(app.buttons["Movement to Test cafe"]).tap()
        XCTAssertEqual(try XCTUnwrap(Double((app.sliders.firstMatch.value as? String ?? "").components(separatedBy: " ")[0])), drive, accuracy: 0.11)
        capture("28-reopened-custom-drive-speed")
        app.buttons["Done"].tap()
        routeControl(app.buttons["Movement to Test pond"]).tap()
        XCTAssertEqual(try XCTUnwrap(Double((app.sliders.firstMatch.value as? String ?? "").components(separatedBy: " ")[0])), bike, accuracy: 0.11)
        capture("29-reopened-custom-ebike-speed")
    }

    func testRecalculateSavedRouteRetainsStopsAndSavesNewSpeed() throws {
        launchRoutes()
        let countBefore = try XCTUnwrap(savedSnapshot()["count"] as? Int)
        let before = try savedTrip()
        app.buttons["Open saved route"].tap()
        routeControl(app.buttons["Stop and route options"]).tap()
        app.buttons["Recalculate with another mode"].tap()
        app.buttons["E-bike"].tap()
        XCTAssertEqual(app.sliders["E-bike speed in miles per hour"].value as? String, "31.0 mph")
        let speed = try setVisibleSpeed("E-bike", position: 0.65)
        capture("30-recalculate-same-stops")
        routeControl(app.buttons["route.recalculate.confirm"]).tap()
        XCTAssertTrue(app.buttons["Movement to Test cafe"].waitForExistence(timeout: 5))
        saveRouteChanges()
        closeRoute()
        let saved = try savedTrip()
        XCTAssertEqual(try savedSnapshot()["count"] as? Int, countBefore,
                       "Save changes must update the existing route instead of creating a duplicate")
        for key in ["id", "name", "originName", "destinationName"] {
            XCTAssertEqual(saved[key] as? String, before[key] as? String, key)
        }
        XCTAssertEqual(saved["mode"] as? String, "eBike")
        XCTAssertEqual(try XCTUnwrap(saved["speedMPH"] as? Double), speed, accuracy: 0.11)
        XCTAssertEqual(saved["smoothMovement"] as? Bool, true)
        XCTAssertEqual(saved["arrival"] as? String, before["arrival"] as? String)
        let stops = try XCTUnwrap(saved["stops"] as? [[String: Any]])
        let originalStops = try XCTUnwrap(before["stops"] as? [[String: Any]])
        XCTAssertEqual(stops.count, 2)
        for index in stops.indices {
            for key in ["id", "name"] { XCTAssertEqual(stops[index][key] as? String, originalStops[index][key] as? String) }
            XCTAssertEqual(stops[index]["waitSeconds"] as? Double, originalStops[index]["waitSeconds"] as? Double)
        }
        let points = try XCTUnwrap(saved["points"] as? [[String: Any]])
        let oldPoints = try XCTUnwrap(before["points"] as? [[String: Any]])
        XCTAssertTrue(NSDictionary(dictionary: points.first!).isEqual(to: oldPoints.first!))
        XCTAssertTrue(NSDictionary(dictionary: points.last!).isEqual(to: oldPoints.last!))
        let sections = try XCTUnwrap(saved["travelSections"] as? [[String: Any]])
        XCTAssertEqual(sections.count, 3)
        for section in sections {
            XCTAssertEqual(section["mode"] as? String, "eBike")
            XCTAssertEqual(try XCTUnwrap(section["speedMPH"] as? Double), speed, accuracy: 0.11)
        }
        app.buttons["Reopen last saved route"].tap()
        routeControl(app.buttons["Movement to Test cafe"]).tap()
        XCTAssertEqual(try XCTUnwrap(Double((app.sliders.firstMatch.value as? String ?? "").components(separatedBy: " ")[0])), speed, accuracy: 0.11)
        capture("31-reopened-recalculated-route")
    }

    func testSavedPinsCrossCutoffDuringPinchAndStayVisibleWhenRotated() {
        launch("map-pins", narrow: false)
        reachable("session.pause"); reachable("session.stop")
        app.buttons["Collapse route details"].tap()
        XCTAssertTrue(app.buttons["validation.pin.near"].isHittable)
        app.buttons["validation.pin.near"].tap()
        let count = app.staticTexts["validation.pinCount"]
        func expectPins(_ shown: Bool) {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let number = Int(count.label) else { return false }
                return shown ? number > 0 : number == 0
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
        }
        func value(_ id: String) -> Int { Int(app.staticTexts[id].label) ?? -1 }
        expectPins(true)
        capture("18-pins-near-active-route")
        let pinchArea = app.otherElements["validation.pinchSurface"]
        XCTAssertLessThan(pinchArea.frame.maxY, app.buttons["Expand route details"].frame.minY - 16,
                          "Both pinch fingers must stay above the route tray")
        let hides = value("validation.pinLiveHides")
        pinchArea.pinch(withScale: 0.2, velocity: -0.5)
        expectPins(false)
        XCTAssertGreaterThan(Double(app.staticTexts["validation.pinWidth"].label) ?? 0, 1)
        XCTAssertGreaterThan(value("validation.pinLiveHides"), hides, "Pins must hide in a continuous callback, before camera settles")
        capture("19-pins-hidden-after-live-crossing")
        let shows = value("validation.pinLiveShows")
        pinchArea.pinch(withScale: 5, velocity: 0.5)
        expectPins(true)
        XCTAssertLessThan(Double(app.staticTexts["validation.pinWidth"].label) ?? 2, 1)
        XCTAssertGreaterThan(value("validation.pinLiveShows"), shows, "Pins must reappear in a continuous callback, before camera settles")
        app.buttons["validation.pin.edge"].tap()
        expectPins(true)
        // Wait for this camera's settled sample before comparing its heading.
        let width = app.staticTexts["validation.pinWidth"]
        let edge = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let miles = Double(width.label) ?? 0
            return miles > 0.85 && miles < 0.95
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [edge], timeout: 8), .completed)
        let before = Double(width.label)!
        let settled = value("validation.pinSettled")
        app.buttons["validation.pin.rotate"].tap()
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            value("validation.pinSettled") > settled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
        expectPins(true)
        XCTAssertEqual(Double(width.label) ?? 0, before, accuracy: 0.03, "Rotation alone must not change visible-up-to width")
        reachable("session.pause"); reachable("session.stop")
        capture("20-pins-rotated-at-same-ground-scale")
    }
    private func reachable(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 12), id)
        XCTAssertTrue(button.isHittable, id)
        XCTAssertGreaterThanOrEqual(button.frame.height, 43, id)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame), id)
        let solidNavigation = app.buttons["navigation.library"]
        if solidNavigation.exists && solidNavigation.isHittable {
            XCTAssertLessThanOrEqual(button.frame.maxY, solidNavigation.frame.minY - 8,
                                    "\(id) must clear the solid navigation bar")
        }
    }
    func testDeletedSelectionAfterLongListScroll() {
        launch("deleted-selection", narrow: false)
        app.buttons["Select"].tap()
        for _ in 0..<3 { app.swipeUp(velocity: .fast) }
        app.swipeDown(velocity: .slow)
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Test deleted pin' AND label CONTAINS ', expires '"))
            .allElementsBoundByIndex.filter {
                $0.value != nil && $0.isHittable && $0.frame.minY > 160 && $0.frame.maxY < app.frame.maxY - 150
            }.sorted { $0.frame.minY < $1.frame.minY }
        guard rows.count >= 3 else { XCTFail("Expected three visible selection rows"); return }
        let first = rows[0], third = rows[2]
        first.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 42, dy: 0))
            .press(forDuration: 0.1, thenDragTo: third.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 42, dy: 0)))
        XCTAssertTrue(app.buttons["Delete (3)"].waitForExistence(timeout: 5))
        for row in rows.prefix(3) { XCTAssertTrue((row.value as? String ?? "").contains("Selected")) }
        capture("31-deleted-selection-after-scroll")
        app.buttons["Delete (3)"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["Cancel"].tap()
        XCTAssertTrue(first.exists)
    }
    func testSavedPinLowerEdgeHoldOnlyMovesPreview() {
        launch("pin-adjustment", narrow: false)
        let pin = app.buttons["Test botanical garden walking route beside the riverside observatory and community orchard"]
        XCTAssertTrue(pin.waitForExistence(timeout: 12))
        XCTAssertTrue(pin.isHittable)
        let coordinate = app.staticTexts["validation.adjustedPin"]
        let before = coordinate.label
        let bottom = pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        // A cold simulator can drop the first synthetic long press before the
        // pin's gesture recognizer attaches. Hold the same lower edge again
        // instead of loosening what this check is about.
        var adjusted = false
        for _ in 0..<3 where !adjusted {
            bottom.press(forDuration: 0.35, thenDragTo: bottom.withOffset(CGVector(dx: 65, dy: -35)))
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in coordinate.label != before }, object: nil)
            adjusted = XCTWaiter.wait(for: [moved], timeout: 6) == .completed
        }
        XCTAssertTrue(adjusted, "Holding the pin's lower edge must move only the preview")
        XCTAssertEqual(app.staticTexts["validation.pinCommand"].label, "No location sent")
        capture("32-pin-lower-edge-adjustment")
    }
    func testIdleTraySitsAboveSolidNavigation() {
        checkIdleTray(solid: true)
    }
    func testIdleTraySitsAboveGlassNavigation() {
        checkIdleTray(solid: false)
    }
    private func checkIdleTray(solid: Bool) {
        launch(solid ? "home-solid" : "home-glass", narrow: false)
        XCTAssertTrue(app.staticTexts["Where to next?"].waitForExistence(timeout: 10))
        let saved = app.buttons["Saved"]
        XCTAssertTrue(saved.isHittable)
        let navigation = solid ? app.buttons["navigation.library"] : app.tabBars.firstMatch
        XCTAssertTrue(navigation.exists)
        let gap = navigation.frame.minY - saved.frame.maxY
        XCTAssertGreaterThanOrEqual(gap, 12, "Tray actions must clear navigation")
        XCTAssertLessThanOrEqual(gap, 60, "The compact idle tray must not float above navigation")
        capture(solid ? "16-idle-solid-tray-spacing" : "17-idle-glass-tray-spacing")
    }
    func testMovingPauseResumeAndStop() {
        launch("moving")
        reachable("session.pause"); reachable("session.stop")
        reachable("map.routeSearch"); reachable("map.follow")
        reachable("Route details")
        XCTAssertGreaterThanOrEqual(app.buttons["map.follow"].frame.minY,
                                    app.buttons["Route details"].frame.maxY)
        capture("01-moving-narrow-light")
        app.buttons["session.pause"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'session.pause' AND label CONTAINS 'Resume'")).firstMatch.waitForExistence(timeout: 10))
        capture("02-paused-narrow-light")
        app.buttons["session.pause"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'session.pause' AND label CONTAINS 'Pause'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["session.stop"].tap()
        XCTAssertTrue(app.staticTexts["Where do you want to go?"].waitForExistence(timeout: 10))
        capture("03-cleared-test-session")
    }
    func testLargestTextLongRouteAndWrappedControls() {
        launch("moving", large: true)
        reachable("session.pause"); reachable("session.stop")
        reachable("map.routeSearch"); reachable("map.follow")
        capture("04-largest-text-long-route")
        let details = app.scrollViews["route.detailsScroll"]
        XCTAssertTrue(details.exists)
        XCTAssertGreaterThanOrEqual(details.frame.height, 44, "Route details need a usable scrolling viewport")
        details.swipeUp()
        reachable("session.pause"); reachable("session.stop")
        capture("04b-largest-text-details-scrolled")
        app.buttons["session.pause"].tap()
        reachable("session.stop")
        capture("05-largest-text-paused")
    }
    func testDarkAccessibilityFallbackPaused() {
        restoreAccessibility = true
        configureAccessibility(true)
        launch("paused", large: true, dark: true, fallback: true)
        reachable("session.stop"); reachable("session.pause")
        XCTAssertFalse(app.tabBars.buttons["Library"].isHittable, "Only the solid fallback navigation should be visible")
        XCTAssertLessThan(app.buttons["session.pause"].frame.height, 85, "Resume should fit on one line")
        capture("06-dark-reduced-motion-transparency-contrast")
    }
    private func configureAccessibility(_ enabled: Bool) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        func backButton() -> XCUIElement {
            let explicit = settings.buttons["BackButton"]
            return explicit.exists ? explicit : settings.navigationBars.buttons.firstMatch
        }
        for _ in 0..<6 {
            if settings.navigationBars["Settings"].exists { break }
            let back = backButton()
            if back.exists { back.tap() } else { break }
        }
        func open(_ label: String) {
            let text = settings.staticTexts.matching(identifier: label).firstMatch
            for _ in 0..<7 {
                if text.exists && text.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(text.waitForExistence(timeout: 5), "Settings: \(label)")
            text.tap()
        }
        func toggle(_ label: String) {
            let control = settings.switches.matching(identifier: label).firstMatch
            for _ in 0..<4 {
                if control.exists && control.isHittable { break }
                settings.swipeUp()
            }
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Settings: \(label)")
            let expected = enabled ? "1" : "0"
            if control.value as? String != expected {
                // Settings exposes the entire row as a switch on some runtimes.
                // Hit the visible trailing toggle, then wait for its async update.
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: control)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, label)
        }
        open("Accessibility"); open("Display & Text Size")
        toggle("Reduce Transparency"); toggle("Increase Contrast")
        backButton().tap()
        open("Motion"); toggle("Reduce Motion")
        let shot = XCTAttachment(screenshot: settings.screenshot())
        shot.name = enabled ? "accessibility-settings-enabled" : "accessibility-settings-reset"
        shot.lifetime = .keepAlways; add(shot)
        settings.terminate()
    }
    func testConnectingIsNotPresentedAsMoving() {
        launch("connecting")
        XCTAssertTrue(app.staticTexts["Starting route…"].waitForExistence(timeout: 10))
        capture("07-connecting-test-only")
        reachable("session.stop")
    }
    func testFailedStateOffersRecovery() {
        launch("failed")
        if app.alerts.firstMatch.waitForExistence(timeout: 5) { app.alerts.buttons["OK"].tap() }
        XCTAssertTrue(app.buttons["Retry connection"].waitForExistence(timeout: 10))
        reachable("session.stop")
        capture("08-failed-test-only")
    }
    func testSearchSubmitFailureAndRetry() {
        launch("search")
        let field = app.textFields["route.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("retry\n")
        XCTAssertTrue(app.staticTexts["You're offline. Reconnect and try again; saved pins still work."].waitForExistence(timeout: 10))
        capture("09-search-failed")
        app.buttons["Search for “retry”"].tap()
        XCTAssertTrue(app.staticTexts["Test cafe result for retry"].waitForExistence(timeout: 10))
        capture("10-search-retried")
    }
    func testSearchCancellationRejectsLateResults() {
        launch("search")
        let field = app.textFields["route.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("slow\n")
        XCTAssertTrue(app.buttons["Cancel search"].waitForExistence(timeout: 5))
        app.buttons["Cancel search"].tap()
        app.buttons["Clear search"].tap(); field.tap(); field.typeText("cafe\n")
        XCTAssertTrue(app.staticTexts["Test cafe result for cafe"].waitForExistence(timeout: 10))
        let obsolete = app.staticTexts["OBSOLETE TEST RESULT"]
        XCTAssertFalse(obsolete.waitForExistence(timeout: 4))
        capture("11-search-cancelled-late-response-discarded")
    }
    func testSearchDismissalAndForegroundInterruption() {
        launch("search")
        let field = app.textFields["route.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("slow\n")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(field.exists)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["validation.banner"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["OBSOLETE TEST RESULT"].waitForExistence(timeout: 4))
        capture("12-search-dismissed-and-resumed")
    }
    func testSearchInterruptedWhilePendingThenReplaced() {
        launch("search")
        let field = app.textFields["route.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("slow\n")
        XCTAssertTrue(app.buttons["Cancel search"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.buttons["Clear search"].tap(); field.tap(); field.typeText("cafe\n")
        XCTAssertTrue(app.staticTexts["Test cafe result for cafe"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["OBSOLETE TEST RESULT"].waitForExistence(timeout: 4))
        capture("15-search-background-interruption-replaced")
    }
    func testLibraryEmptyState() {
        launch("empty")
        openLibrary()
        XCTAssertTrue(app.staticTexts["Star a pin to find it here."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Star a saved route to find it here."].exists)
        capture("13-library-empty")
    }
    func testLibraryLongNamesLargeDark() {
        launch("idle", large: true, dark: true, fallback: true)
        openLibrary()
        let longItem = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Test botanical garden'")).firstMatch
        XCTAssertTrue(longItem.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(longItem.frame.width, 180)
        capture("14-library-long-names-largest-text")
        app.descendants(matching: .any).matching(identifier: "library.category").firstMatch.tap()
        app.buttons["Routes"].tap()
        XCTAssertTrue(longItem.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(longItem.frame.width, 180)
        // The Create route row can fill the initial viewport at maximum text.
        // Bring the saved route itself into view before accepting its screenshot.
        for _ in 0..<4 {
            if longItem.isHittable && longItem.frame.minY < 300 { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(longItem.isHittable)
        capture("14b-library-long-route-largest-text")
    }
    private func openLibrary() {
        let solid = app.buttons["navigation.library"]
        if solid.exists && solid.isHittable { solid.tap() }
        else { app.tabBars.buttons["Library"].tap() }
    }
}
