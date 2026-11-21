import XCTest
@testable import SessionPresentation

final class MapPinHitAreaTests: XCTestCase {
    private let anchor = CGPoint(x: 100, y: 150)

    func testCenteredSavedSymbolIncludesItsLowerEdge() {
        let bounds = MapPinHitArea.bounds(anchor: anchor, savedSymbolSize: 32)
        XCTAssertTrue(bounds.contains(CGPoint(x: 100, y: 171)))
        XCTAssertEqual(bounds.midY, anchor.y)
        XCTAssertEqual(bounds.height, MapPinHitArea.savedIconSide(symbolSize: 32))
    }

    func testLargeSavedSymbolIncludesBothSides() {
        let bounds = MapPinHitArea.bounds(anchor: anchor, savedSymbolSize: 60)
        XCTAssertTrue(bounds.contains(CGPoint(x: 68, y: 150)))
        XCTAssertTrue(bounds.contains(CGPoint(x: 132, y: 150)))
        XCTAssertTrue(bounds.contains(CGPoint(x: 100, y: 182)))
    }

    func testSavedSymbolDoesNotClaimEmptyMapAboveIt() {
        let bounds = MapPinHitArea.bounds(anchor: anchor, savedSymbolSize: 32)
        XCTAssertFalse(bounds.contains(CGPoint(x: 100, y: 100)))
        XCTAssertFalse(bounds.contains(CGPoint(x: 130, y: 150)))
    }

    func testNativePointedMarkerKeepsItsExistingTouchArea() {
        XCTAssertEqual(MapPinHitArea.bounds(anchor: anchor, savedSymbolSize: nil),
                       CGRect(x: 72, y: 86, width: 56, height: 80))
    }
}
