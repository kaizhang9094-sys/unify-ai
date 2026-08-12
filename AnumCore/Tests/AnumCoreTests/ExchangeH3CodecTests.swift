import SwiftyH3
import XCTest
@testable import AnumCore

final class ExchangeH3CodecTests: XCTestCase {
    func testGoldenVector_latLngToCell_matchesCrossPlatformReference() throws {
        let latlng = H3LatLng(
            latitudeDegs: ExchangeH3GoldenVectors.latitudeDegrees,
            longitudeDegs: ExchangeH3GoldenVectors.longitudeDegrees
        )
        let cell = try latlng.cell(at: H3Cell.Resolution(rawValue: Int32(ExchangeH3GoldenVectors.resolution))!)
        XCTAssertEqual(cell.description.lowercased(), ExchangeH3GoldenVectors.expectedCell)
    }

    func testNormalizeCellString_lowercasesUppercaseHex() {
        let upper = ExchangeH3GoldenVectors.expectedCell.uppercased()
        XCTAssertEqual(
            ExchangeH3Codec.normalizeCellString(upper),
            ExchangeH3GoldenVectors.expectedCell
        )
    }

    func testValidateCellString_acceptsGoldenCell() {
        XCTAssertTrue(ExchangeH3Codec.validateCellString(ExchangeH3GoldenVectors.expectedCell))
    }

    func testValidateCells_requiresMatchingResolution() {
        XCTAssertTrue(
            ExchangeH3Codec.validateCells(
                [ExchangeH3GoldenVectors.expectedCell],
                resolution: ExchangeH3GoldenVectors.resolution
            )
        )
        XCTAssertFalse(
            ExchangeH3Codec.validateCells(
                [ExchangeH3GoldenVectors.expectedCell],
                resolution: ExchangeH3GoldenVectors.resolution + 1
            )
        )
    }

    func testCellResolution_readsGoldenCell() {
        XCTAssertEqual(
            ExchangeH3Codec.cellResolution(ExchangeH3GoldenVectors.expectedCell),
            ExchangeH3GoldenVectors.resolution
        )
    }
}
