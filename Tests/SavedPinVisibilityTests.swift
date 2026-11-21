import XCTest
@testable import SessionPresentation

final class SavedPinVisibilityTests: XCTestCase {
    func testDefaultKeepsWiderNeighborhoodOverviewsVisible() {
        // A quarter-mile scale division represents only part of the map.
        // Even a several-mile viewport should keep its saved pins by default.
        for miles in [0.25, 0.75, 2.5, 5] {
            XCTAssertTrue(SavedPinVisibility.isVisible(mapWidthMeters: miles * SavedPinVisibility.metersPerMile,
                maximumMiles: SavedPinVisibility.defaultMiles))
        }
    }

    func testSliderThresholdUsesGroundMilesAndKeepsDistantOverviewsClear() {
        let width = 8 * SavedPinVisibility.metersPerMile
        XCTAssertFalse(SavedPinVisibility.isVisible(mapWidthMeters: width, maximumMiles: 5))
        XCTAssertTrue(SavedPinVisibility.isVisible(mapWidthMeters: width, maximumMiles: 8))
        XCTAssertFalse(SavedPinVisibility.isVisible(mapWidthMeters: width + 1, maximumMiles: 8))
        XCTAssertFalse(SavedPinVisibility.isVisible(mapWidthMeters: 5_000_000, maximumMiles: 20))
    }

    func testPinsHiddenUntilMapSpanIsKnownAndValid() {
        let distances: [Double?] = [nil, .nan, .infinity, -.infinity, 0, -600]
        for distance in distances {
            XCTAssertFalse(SavedPinVisibility.isVisible(mapWidthMeters: distance, maximumMiles: 5))
        }
    }

    func testMapSpanUsesLocalGroundScaleAndRejectsInvalidGeometry() {
        XCTAssertEqual(SavedPinVisibility.mapWidthMeters(sampleMeters: 320, samplePoints: 32, viewportPoints: 400), 4_000)
        XCTAssertEqual(SavedPinVisibility.mapWidthMeters(sampleMeters: 160, samplePoints: 32, viewportPoints: 400), 2_000)
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertNil(SavedPinVisibility.mapWidthMeters(sampleMeters: invalid, samplePoints: 32, viewportPoints: 400))
            XCTAssertNil(SavedPinVisibility.mapWidthMeters(sampleMeters: 32, samplePoints: invalid, viewportPoints: 400))
            XCTAssertNil(SavedPinVisibility.mapWidthMeters(sampleMeters: 32, samplePoints: 32, viewportPoints: invalid))
        }
        XCTAssertNil(SavedPinVisibility.mapWidthMeters(sampleMeters: 32, samplePoints: 32, viewportPoints: 16))
        XCTAssertNil(SavedPinVisibility.mapWidthMeters(sampleMeters: .greatestFiniteMagnitude, samplePoints: 1, viewportPoints: 2))
    }

    func testWidthTracksScreenSizeInsteadOfBoundingRectangleHeight() {
        XCTAssertEqual(SavedPinVisibility.mapWidthMeters(sampleMeters: 32, samplePoints: 32, viewportPoints: 320), 320)
        XCTAssertEqual(SavedPinVisibility.mapWidthMeters(sampleMeters: 32, samplePoints: 32, viewportPoints: 640), 640)
        // A different sample length at the same ground scale gives the same width.
        XCTAssertEqual(SavedPinVisibility.mapWidthMeters(sampleMeters: 16, samplePoints: 16, viewportPoints: 320), 320)
    }

    func testCutoffCrossingsBypassThrottleInBothDirections() {
        var cadence = SavedPinRefreshCadence()
        for (index, miles) in [0.99, 1.01, 0.99, 1.01, 1.0].enumerated() {
            let visible = SavedPinVisibility.isVisible(mapWidthMeters: miles * SavedPinVisibility.metersPerMile, maximumMiles: 1)
            XCTAssertTrue(cadence.shouldRefresh(visible: visible, now: Double(index) * 0.001))
        }
    }

    func testPanningScansAtMostTenTimesPerSecondButAlwaysSettles() {
        var cadence = SavedPinRefreshCadence()
        XCTAssertTrue(cadence.shouldRefresh(visible: true, now: 0))
        for step in 1..<10 {
            XCTAssertFalse(cadence.shouldRefresh(visible: true, now: Double(step) / 100))
        }
        XCTAssertTrue(cadence.shouldRefresh(visible: true, now: 0.1))
        XCTAssertTrue(cadence.shouldRefresh(visible: true, now: 0.101, force: true))
    }

    func testHiddenPinsDoNotContinuouslyRescanLibrary() {
        var cadence = SavedPinRefreshCadence()
        XCTAssertTrue(cadence.shouldRefresh(visible: false, now: 0))
        XCTAssertFalse(cadence.shouldRefresh(visible: false, now: 1))
        XCTAssertFalse(cadence.shouldRefresh(visible: false, now: 60))
        XCTAssertTrue(cadence.shouldRefresh(visible: false, now: 61, force: true))
    }

    func testPreferenceChangeDoesNotWaitForAnotherCameraGesture() {
        var cadence = SavedPinRefreshCadence()
        let width = 3 * SavedPinVisibility.metersPerMile
        XCTAssertTrue(cadence.shouldRefresh(visible: SavedPinVisibility.isVisible(mapWidthMeters: width, maximumMiles: 1), now: 0))
        XCTAssertTrue(cadence.shouldRefresh(visible: SavedPinVisibility.isVisible(mapWidthMeters: width, maximumMiles: 5), now: 0.01))
    }

    func testWorldScaleStaysHiddenInsteadOfWrappingToASmallWidth() {
        let width = SavedPinVisibility.mapWidthMeters(sampleMeters: 3_200_000, samplePoints: 32, viewportPoints: 400)
        XCTAssertEqual(width, 40_000_000)
        XCTAssertFalse(SavedPinVisibility.isVisible(mapWidthMeters: width, maximumMiles: 20))
    }

    func testPreferenceBoundsRecoverFromInvalidStoredValues() {
        XCTAssertEqual(SavedPinVisibility.boundedMiles(.nan), 5)
        XCTAssertEqual(SavedPinVisibility.boundedMiles(.infinity), 5)
        XCTAssertEqual(SavedPinVisibility.boundedMiles(-1), 0.5)
        XCTAssertEqual(SavedPinVisibility.boundedMiles(500), 20)
        XCTAssertEqual(SavedPinVisibility.boundedMiles(8.5), 8.5)
    }
}
