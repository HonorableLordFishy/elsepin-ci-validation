import XCTest
@testable import SessionPresentation

final class DiagnosticMonitorPolicyTests: XCTestCase {
    func testMonitorsRunOnlyWhileRecordingIncludingBackground() {
        XCTAssertFalse(DiagnosticMonitorPolicy.observesNetwork(loggingEnabled: false, appActive: false))
        XCTAssertFalse(DiagnosticMonitorPolicy.observesNetwork(loggingEnabled: false, appActive: true))
        XCTAssertTrue(DiagnosticMonitorPolicy.observesNetwork(loggingEnabled: true, appActive: false))
        XCTAssertTrue(DiagnosticMonitorPolicy.observesNetwork(loggingEnabled: true, appActive: true))
    }
}
