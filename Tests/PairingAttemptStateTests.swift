import XCTest
@testable import SessionPresentation

final class PairingAttemptStateTests: XCTestCase {
    func testCancelBeforeListenerArrivesWakesExactlyOnce() {
        var attempt = PairingAttemptState()
        XCTAssertNil(attempt.cancel())
        XCTAssertFalse(attempt.acceptsCallbacks)
        XCTAssertEqual(attempt.listening(on: 1234), 1234)
        XCTAssertNil(attempt.cancel())
        XCTAssertNil(attempt.listening(on: 1234))
    }

    func testCancelAfterListeningWakesNativeAccept() {
        var attempt = PairingAttemptState()
        XCTAssertNil(attempt.listening(on: 1234))
        XCTAssertTrue(attempt.acceptsCallbacks)
        XCTAssertEqual(attempt.cancel(), 1234)
        XCTAssertFalse(attempt.acceptsCallbacks)
    }

    func testFinishedWorkerNeverConnectsToStalePort() {
        var attempt = PairingAttemptState()
        _ = attempt.listening(on: 1234)
        attempt.finish()
        XCTAssertNil(attempt.cancel())
        XCTAssertFalse(attempt.cancelled)
        XCTAssertNil(attempt.listening(on: 5678))
        XCTAssertFalse(attempt.acceptsCallbacks)
    }

    func testCancelledResultCannotReplacePairingFile() {
        var attempt = PairingAttemptState()
        let revision = UUID()
        XCTAssertTrue(attempt.canInstall(startingRevision: revision, currentRevision: revision))
        _ = attempt.cancel()
        XCTAssertFalse(attempt.canInstall(startingRevision: revision, currentRevision: revision))
    }

    func testImportedOrRemovedPairingInvalidatesOlderNativeResult() {
        let attempt = PairingAttemptState(), original = UUID(), imported = UUID()
        XCTAssertFalse(attempt.canInstall(startingRevision: original, currentRevision: imported))
    }

    func testRetryIsIndependentOfOldCallbacksAndCompletion() {
        var old = PairingAttemptState(), retry = PairingAttemptState()
        let revision = UUID()
        _ = old.cancel()
        _ = retry.listening(on: 5678)
        XCTAssertEqual(old.listening(on: 1234), 1234)
        old.finish()
        XCTAssertTrue(retry.canInstall(startingRevision: revision, currentRevision: revision))
        XCTAssertEqual(retry.cancel(), 5678)
    }

    func testZeroPortCannotStartCancellationConnection() {
        var attempt = PairingAttemptState()
        _ = attempt.cancel()
        XCTAssertNil(attempt.listening(on: 0))
        XCTAssertEqual(attempt.listening(on: 1234), 1234)
    }
}
