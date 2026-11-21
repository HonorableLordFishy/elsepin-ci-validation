import XCTest

final class ElsepinBackupUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 900
    }
    override func tearDownWithError() throws {
        if let app, app.state == .runningForeground { capture("backup-final"); app.terminate() }
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    private func visible(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY >= 145 && element.frame.maxY <= app.frame.maxY - 50 { return element }
            let above = element.exists && element.frame.minY < 145
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: above ? 0.35 : 0.77))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: above ? 0.77 : 0.35)))
        }
        XCTFail("Unreachable backup control: \(element)"); return element
    }
    private func localExportFolder() {
        // DocumentManager loads out of process. Wait for its navigation before
        // querying locations; an optional query during loading can hit Back and
        // silently save to On My iPhone instead of this app's Documents folder.
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 25), "Native Files did not finish presenting")
        let title = picker.buttons["Elsepin, Actions Menu"]
        if !title.waitForExistence(timeout: 5) {
            let ownFolder = app.cells["Elsepin, Container"]
            XCTAssertTrue(ownFolder.waitForExistence(timeout: 15), "App folder missing from On My iPhone")
            ownFolder.doubleTap()
        }
        XCTAssertTrue(title.waitForExistence(timeout: 20), "Native Files did not open the app folder")
    }
    private func snapshot() throws -> [String: Any] {
        app.buttons["Read settings and export"].tap()
        let text = app.staticTexts["validation.backupSnapshot"].label
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    private func settings(_ snapshot: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(snapshot["settings"] as? [String: Any])
    }
    private func prepareFilesProvider() {
        // A successful simctl launch does not mean Files' provider has finished
        // its first-run indexing. Verify actual enumeration before opening an
        // export sheet; a blank system sheet is not a backup interaction result.
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launch()
        let browse = files.tabBars["DOC.browsingModeTabBar"].buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 60), "Simulator Files did not become ready")
        browse.tap()
        browse.tap()
        let location = files.staticTexts["On My iPhone"].firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 30))
        let row = files.cells.containing(.staticText, identifier: "On My iPhone").firstMatch
        if row.exists { row.tap() } else { location.tap() }
        XCTAssertTrue(files.cells["Elsepin, Container"].waitForExistence(timeout: 60),
            "Simulator Files could not enumerate the disposable app container")
        app.activate()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
    }
    private func openImport() {
        app.buttons["Import and export"].tap()
        app.buttons["Choose backup file"].tap()
        let browse = app.tabBars["DOC.browsingModeTabBar"].buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 25))
        browse.tap()
        // The first tap selects Browse; tapping its selected tab returns to
        // Locations. Always leave the app container, even if it lists its copy:
        // that provider can enumerate files yet fail to deliver a selection.
        browse.tap()
        let location = app.staticTexts["On My iPhone"].firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        let row = app.cells.containing(.staticText, identifier: "On My iPhone").firstMatch
        if row.exists { row.tap() } else { location.tap() }
        // iOS 26 exposes this title as text; iOS 27 exposes an Actions button.
        let localStorage = app.navigationBars.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'On My iPhone'")).firstMatch
        XCTAssertTrue(localStorage.waitForExistence(timeout: 10), "File import must use general Files storage, not the app-container provider")
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH 'Elsepin-Settings'")).firstMatch
        capture("33b-general-files-storage")
        XCTAssertTrue(file.waitForExistence(timeout: 20), "Exported settings file not listed")
        XCTAssertTrue(file.isEnabled, "Valid settings backup is disabled in Files")
        file.tap()
        if app.navigationBars.buttons["Open"].exists { app.navigationBars.buttons["Open"].tap() }
        XCTAssertTrue(app.navigationBars["Review import"].waitForExistence(timeout: 10))
    }
    private func expandSettings() {
        let group = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Settings ·'")).firstMatch
        visible(group).tap()
    }
    private func applyImport() {
        visible(app.buttons["Import selected changes"]).tap()
        let confirm = app.sheets.buttons["Import selected changes"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Import complete.'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Close backup test"].tap()
    }

    func testSettingsExportFileSelectiveImportAndRelaunch() throws {
        app = XCUIApplication()
        app.launchArguments = ["--elsepin-ui-test"]
        app.launchEnvironment["ELSEPIN_TEST_SCENARIO"] = "backup-settings"
        app.launch()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
        prepareFilesProvider()
        let baseline = try snapshot()
        let original = try settings(baseline)
        app.buttons["Import and export"].tap()
        visible(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Backup contents'")).firstMatch).tap()
        app.buttons["Settings"].tap()
        app.buttons["Export backup"].tap()
        app.buttons["Export settings"].tap()
        capture("32-native-settings-export-picker")
        localExportFolder()
        capture("33-local-export-destination")
        let exportButton = app.navigationBars.buttons["Export"].firstMatch
        if exportButton.exists { exportButton.tap() }
        else { app.navigationBars.buttons["Save"].tap() }
        XCTAssertTrue(app.staticTexts["Backup exported."].waitForExistence(timeout: 10))
        app.buttons["Close backup test"].tap()
        let exported = try snapshot()
        XCTAssertEqual(exported["valid"] as? Bool, true)
        let backup = try XCTUnwrap(exported["export"] as? [String: Any])
        XCTAssertEqual(backup["categories"] as? [String], ["settings"])
        XCTAssertEqual((backup["trips"] as? [Any])?.count, 0)
        XCTAssertEqual((backup["places"] as? [Any])?.count, 0)
        let exportedSettings = try XCTUnwrap(backup["preferences"] as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: exportedSettings))
        var filesReady = false
        for _ in 0..<30 {
            if try snapshot()["filesReady"] as? Bool == true { filesReady = true; break }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(filesReady, "Actual export was not staged in disposable Files storage; see files-staging.log")

        app.buttons["Change disposable settings"].tap()
        let changed = try settings(snapshot())
        XCTAssertFalse(NSDictionary(dictionary: original).isEqual(to: changed))
        openImport()
        XCTAssertFalse(visible(app.buttons["Import selected changes"]).isEnabled, "Settings must start unchecked")
        capture("34-import-starts-unchecked")
        visible(app.buttons["Cancel import"]).tap()
        app.buttons["Close backup test"].tap()
        XCTAssertTrue(NSDictionary(dictionary: try settings(snapshot())).isEqual(to: changed), "Cancel changed settings")

        openImport()
        expandSettings()
        visible(app.buttons["Select all settings"]).tap()
        let drive = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Drive preset'")).firstMatch
        visible(drive).tap()
        XCTAssertEqual(drive.value as? String, "Not selected")
        capture("35-import-leaves-drive-unchecked")
        applyImport()
        let partial = try settings(snapshot())
        var expectedPartial = original
        var speeds = try XCTUnwrap(original["usualSpeeds"] as? [String: Any])
        speeds["drive"] = 1
        expectedPartial["usualSpeeds"] = speeds
        XCTAssertTrue(NSDictionary(dictionary: partial).isEqual(to: expectedPartial), "Selective import changed an unchecked value or missed a selected value")

        openImport()
        expandSettings()
        visible(app.buttons["Select all settings"]).tap()
        applyImport()
        XCTAssertTrue(NSDictionary(dictionary: try settings(snapshot())).isEqual(to: original))
        app.terminate()
        app.launchArguments.append("--preserve-backup-test-data")
        app.launch()
        XCTAssertTrue(app.buttons["Read settings and export"].waitForExistence(timeout: 20))
        let reopened = try snapshot()
        XCTAssertTrue(NSDictionary(dictionary: try settings(reopened)).isEqual(to: original), "Restored settings did not persist through relaunch")
        XCTAssertEqual(reopened["tripCount"] as? Int, baseline["tripCount"] as? Int)
        XCTAssertEqual(reopened["pinCount"] as? Int, baseline["pinCount"] as? Int)
        openImport()
        XCTAssertFalse(visible(app.buttons["Import selected changes"]).isEnabled, "Reimport should have no settings left to change")
        capture("36-reimport-after-relaunch-no-changes")
        visible(app.buttons["Cancel import"]).tap()
        app.buttons["Close backup test"].tap()

        // Keep the existing paste alternative working, using bytes from the
        // real export above rather than constructing an artificial backup.
        app.buttons["Change disposable settings"].tap()
        app.buttons["Copy exported backup text"].tap()
        app.buttons["Import and export"].tap()
        let paste = app.buttons["Paste backup text"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        XCTAssertTrue(paste.isEnabled)
        paste.tap()
        XCTAssertTrue(app.navigationBars["Review import"].waitForExistence(timeout: 10))
        expandSettings()
        visible(app.buttons["Select all settings"]).tap()
        capture("37-paste-import-retained")
        applyImport()
        XCTAssertTrue(NSDictionary(dictionary: try settings(snapshot())).isEqual(to: original))
    }
}
