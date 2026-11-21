import XCTest
@testable import SessionPresentation

final class RouteFlowPresentationTests: XCTestCase {
    func testFailedDirectionsKeepEndpointsAndOfferRetry() {
        let state = RoutePlanningReadiness.resolve(hasOrigin: true, hasDestination: true,
            hasRoute: false, isLoading: false, hasError: true)
        XCTAssertEqual(state, .failed)
        XCTAssertTrue(state.offersDirections)
        XCTAssertNotEqual(state.guidance(nextRoute: false, cyclingUnavailable: false),
                          "Choose a start and destination.")
    }

    func testRetryProgressCannotOfferAnotherRequest() {
        let state = RoutePlanningReadiness.resolve(hasOrigin: true, hasDestination: true,
            hasRoute: false, isLoading: true, hasError: true)
        XCTAssertEqual(state, .finding)
        XCTAssertFalse(state.offersDirections)
    }

    func testMissingEndpointDoesNotOfferAnImpossibleRetry() {
        for (origin, destination) in [(false, false), (true, false), (false, true)] {
            let state = RoutePlanningReadiness.resolve(hasOrigin: origin, hasDestination: destination,
                hasRoute: false, isLoading: false, hasError: true)
            XCTAssertEqual(state, .choosingPlaces)
            XCTAssertFalse(state.offersDirections)
        }
    }

    func testExistingPreviewWinsOverAnUnrelatedEditorError() {
        let state = RoutePlanningReadiness.resolve(hasOrigin: true, hasDestination: true,
            hasRoute: true, isLoading: false, hasError: true)
        XCTAssertEqual(state, .ready)
        XCTAssertFalse(state.offersDirections)
        XCTAssertEqual(state.guidance(nextRoute: true, cyclingUnavailable: false), "Returns to next-route setup.")
    }

    func testDraftWithoutDirectionsHasARecoveryAction() {
        let state = RoutePlanningReadiness.resolve(hasOrigin: true, hasDestination: true,
            hasRoute: false, isLoading: false, hasError: false)
        XCTAssertEqual(state, .needsDirections)
        XCTAssertTrue(state.offersDirections)
    }

    func testStartingRouteDoesNotClaimMovementBeforeConfirmation() {
        XCTAssertEqual(RouteJourneyPresentation.subtitle(phase: .connecting, state: .moving,
            restored: false, recovering: false), "Starting route…")
        XCTAssertEqual(RouteJourneyPresentation.subtitle(phase: .active, state: .moving,
            restored: false, recovering: false), JourneyState.moving.title)
    }

    func testUnconfirmedConnectionDoesNotClaimArrivalOrMovement() {
        for state in [JourneyState.moving, .arrived, .waiting] {
            for phase in [SessionPhase.reconnecting, .unverified, .disconnected, .idle] {
                XCTAssertNotEqual(RouteJourneyPresentation.subtitle(phase: phase, state: state,
                    restored: false, recovering: false), state.title)
            }
        }
    }

    func testConfirmedPauseAndArrivalRetainTheirMeaning() {
        for state in [JourneyState.pausing, .paused, .waiting, .arrived, .seeking, .interrupted] {
            XCTAssertEqual(RouteJourneyPresentation.subtitle(phase: .active, state: state,
                restored: false, recovering: false), state.title)
        }
    }

    func testStopAndRecoveryTakePrecedenceOverWorkerState() {
        XCTAssertEqual(RouteJourneyPresentation.subtitle(phase: .stopping, state: .moving,
            restored: true, recovering: true), SessionPhase.stopping.title)
        XCTAssertEqual(RouteJourneyPresentation.subtitle(phase: .unverified, state: .moving,
            restored: true, recovering: false), "Saved route position")
        XCTAssertEqual(RouteJourneyPresentation.subtitle(phase: .connecting, state: .moving,
            restored: false, recovering: true), "Reconnecting route…")
    }
}
