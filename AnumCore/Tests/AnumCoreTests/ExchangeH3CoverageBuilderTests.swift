import XCTest
@testable import AnumCore

final class ExchangeH3CoverageBuilderTests: XCTestCase {
    private var goldenCenter: ExchangeCoordinate {
        ExchangeCoordinate(
            latitude: ExchangeH3GoldenVectors.latitudeDegrees,
            longitude: ExchangeH3GoldenVectors.longitudeDegrees
        )
    }

    func testBuildCoverage_goldenCenter_includesExpectedCell() {
        let coverage = ExchangeH3CoverageBuilder.buildCoverage(
            center: goldenCenter,
            radiusMeters: ExchangeH3CoverageBuilder.defaultRequesterRadiusMeters,
            resolution: ExchangeH3GoldenVectors.resolution,
            source: .manualCoordinate
        )
        XCTAssertEqual(coverage.status, .resolved)
        XCTAssertTrue(coverage.hasResolvedCells)
        XCTAssertEqual(coverage.h3Resolution, ExchangeH3GoldenVectors.resolution)
        XCTAssertTrue(coverage.h3Cells.contains(ExchangeH3GoldenVectors.expectedCell))
        XCTAssertEqual(coverage.h3Cells, coverage.h3Cells.map { $0.lowercased() })
        XCTAssertEqual(coverage.centerLatitude, goldenCenter.latitude)
        XCTAssertEqual(coverage.centerLongitude, goldenCenter.longitude)
        XCTAssertEqual(coverage.source, .manualCoordinate)
    }

    func testBuildCoverage_zeroRadius_centerCellOnly() {
        let coverage = ExchangeH3CoverageBuilder.buildCoverage(
            center: goldenCenter,
            radiusMeters: 0,
            resolution: 7,
            source: .manualCoordinate
        )
        XCTAssertEqual(coverage.status, .resolved)
        XCTAssertEqual(coverage.h3Cells, [ExchangeH3GoldenVectors.expectedCell])
        XCTAssertNil(coverage.radiusMeters)
    }

    func testBuildCoverage_invalidCoordinate_failed() {
        let bad = ExchangeCoordinate(latitude: 999, longitude: 0)
        XCTAssertFalse(bad.isValid)
        let coverage = ExchangeH3CoverageBuilder.buildCoverage(
            center: bad,
            radiusMeters: 5_000,
            source: .manualCoordinate
        )
        XCTAssertEqual(coverage.status, .failed)
        XCTAssertTrue(coverage.h3Cells.isEmpty)
    }

    func testBuildCoverage_respectsMaxCellsCap() {
        let coverage = ExchangeH3CoverageBuilder.buildCoverage(
            center: goldenCenter,
            radiusMeters: 50_000,
            resolution: 7,
            maxCells: 8,
            source: .imported
        )
        XCTAssertLessThanOrEqual(coverage.h3Cells.count, 8)
        XCTAssertGreaterThan(coverage.h3Cells.count, 1)
    }

    func testGridDiskDistance_zeroRadius() {
        guard let res = H3Cell.Resolution(rawValue: 7) else {
            XCTFail("missing res 7")
            return
        }
        XCTAssertEqual(
            ExchangeH3CoverageBuilder.gridDiskDistance(
                radiusMeters: 0,
                resolution: res,
                maxCells: 128
            ),
            0
        )
    }
}
