import XCTest
@testable import SessionPresentation

final class IncomingRouteSectionTests: XCTestCase {
    private var sections: [RouteTravelSection] {
        [.init(id: UUID(), startMetres: 0, endMetres: 500, mode: .walk, speedMPH: 3),
         .init(id: UUID(), startMetres: 500, endMetres: 1000, mode: .run, speedMPH: 7),
         .init(id: UUID(), startMetres: 1000, endMetres: 1500, mode: .drive, speedMPH: 25)]
    }

    func testSplitLegUsesTrailingFragment() {
        let incoming = RouteTravelSection.incoming(in: sections, endingAt: 1000)
        XCTAssertEqual(incoming?.mode, .run)
        XCTAssertEqual(incoming?.speedMPH, 7)
    }

    func testExactBoundaryDoesNotUsePlaybackForwardEpsilon() {
        let sections = sections
        XCTAssertEqual(RouteTravelSection.incoming(in: sections, endingAt: 500)?.mode, .walk)
        XCTAssertEqual(RouteTravelSection.current(in: sections, at: 500)?.mode, .run)
        XCTAssertEqual(RouteTravelSection.incoming(in: sections, endingAt: 499.9999)?.mode, .walk)
    }

    func testMissingOrInvalidEndpointHasNoIncomingSection() {
        XCTAssertNil(RouteTravelSection.incoming(in: [], endingAt: 1000))
        for metres in [0, -1, Double.nan, .infinity] {
            XCTAssertNil(RouteTravelSection.incoming(in: sections, endingAt: metres))
        }
    }
}
