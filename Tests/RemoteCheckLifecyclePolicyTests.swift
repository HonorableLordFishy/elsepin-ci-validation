import XCTest
@testable import SessionPresentation

final class RemoteCheckLifecyclePolicyTests: XCTestCase {
    func testIdleLifecycleDoesNotNeedTeardown() {
        XCTAssertFalse(RemoteCheckLifecyclePolicy.needsTeardown(monitoring: false, hasTask: false,
            hasResponse: false, hasNetwork: false, checking: false))
        // Repeated refreshLifecycle calls from confirmed location writes remain idle.
        XCTAssertFalse(RemoteCheckLifecyclePolicy.needsTeardown(monitoring: false, hasTask: false,
            hasResponse: false, hasNetwork: false, checking: false))
    }

    func testEveryActiveStateRequiresTeardown() {
        XCTAssertTrue(RemoteCheckLifecyclePolicy.needsTeardown(monitoring: true, hasTask: false,
            hasResponse: false, hasNetwork: false, checking: false))
        XCTAssertTrue(RemoteCheckLifecyclePolicy.needsTeardown(monitoring: false, hasTask: true,
            hasResponse: false, hasNetwork: false, checking: false))
        XCTAssertTrue(RemoteCheckLifecyclePolicy.needsTeardown(monitoring: false, hasTask: false,
            hasResponse: true, hasNetwork: false, checking: false))
        XCTAssertTrue(RemoteCheckLifecyclePolicy.needsTeardown(monitoring: false, hasTask: false,
            hasResponse: false, hasNetwork: true, checking: false))
        XCTAssertTrue(RemoteCheckLifecyclePolicy.needsTeardown(monitoring: false, hasTask: false,
            hasResponse: false, hasNetwork: false, checking: true))
    }
}
