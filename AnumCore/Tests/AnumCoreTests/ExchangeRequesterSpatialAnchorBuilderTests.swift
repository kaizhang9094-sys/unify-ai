import XCTest
@testable import AnumCore

final class ExchangeRequesterSpatialAnchorBuilderTests: XCTestCase {
    private var goldenCoordinate: ExchangeCoordinate {
        ExchangeCoordinate(
            latitude: ExchangeH3GoldenVectors.latitudeDegrees,
            longitude: ExchangeH3GoldenVectors.longitudeDegrees
        )
    }

    func testCurrentDeviceCoordinateCreatesResolvedSpatialCoverage() {
        let coordinate = goldenCoordinate
        let anchor = ExchangeRequesterSpatialAnchorBuilder.makeCurrentDeviceAnchor(coordinate: coordinate)

        XCTAssertEqual(anchor.source, .currentDevice)
        XCTAssertEqual(anchor.coordinate, coordinate)
        XCTAssertEqual(anchor.radiusMeters, ExchangeH3CoverageBuilder.defaultRequesterRadiusMeters)
        XCTAssertTrue(anchor.hasResolvedSpatial)
        XCTAssertEqual(anchor.spatial?.status, .resolved)
        XCTAssertEqual(anchor.spatial?.source, .currentDevice)
        XCTAssertFalse(anchor.spatial?.h3Cells.isEmpty ?? true)
        for cell in anchor.spatial?.h3Cells ?? [] {
            XCTAssertTrue(ExchangeH3Codec.validateCellString(cell))
            XCTAssertEqual(cell, cell.lowercased())
        }
    }

    func testExplicitQueryAnchorCanExistWithoutCurrentDevice() {
        let anchor = ExchangeRequesterSpatialAnchorBuilder.makeExplicitQueryAnchor(
            coordinate: nil,
            spatial: nil,
            radiusMeters: nil
        )

        XCTAssertEqual(anchor.source, .explicitQuery)
        XCTAssertNil(anchor.coordinate)
        XCTAssertFalse(anchor.hasResolvedSpatial)
    }

    func testInvalidCoordinateProducesNoneAnchor() {
        let invalid = ExchangeCoordinate(latitude: 999, longitude: 0)
        let anchor = ExchangeRequesterSpatialAnchorBuilder.makeCurrentDeviceAnchor(coordinate: invalid)

        XCTAssertEqual(anchor.source, .none)
        XCTAssertFalse(anchor.hasResolvedSpatial)
    }

    func testGoldenVectorCellIsLowercaseValid() {
        let anchor = ExchangeRequesterSpatialAnchorBuilder.makeCurrentDeviceAnchor(coordinate: goldenCoordinate)
        let cells = anchor.spatial?.h3Cells ?? []
        XCTAssertTrue(cells.contains(ExchangeH3GoldenVectors.expectedCell))
    }
}
