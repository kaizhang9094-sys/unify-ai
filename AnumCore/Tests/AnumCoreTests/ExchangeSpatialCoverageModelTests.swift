import XCTest
@testable import AnumCore

final class ExchangeSpatialCoverageModelTests: XCTestCase {
    func testSpatialCoverage_roundtrip_lowercaseCells() throws {
        let spatial = ExchangeSpatialCoverage(
            status: .resolved,
            source: .manualCoordinate,
            h3Resolution: ExchangeH3GoldenVectors.resolution,
            h3Cells: [ExchangeH3GoldenVectors.expectedCell.uppercased()],
            centerLatitude: 37.3615593,
            centerLongitude: -122.0553238,
            radiusMeters: 5_000
        )
        XCTAssertTrue(spatial.hasResolvedCells)
        XCTAssertEqual(spatial.h3Cells, [ExchangeH3GoldenVectors.expectedCell])

        let data = try JSONEncoder().encode(spatial)
        let decoded = try JSONDecoder().decode(ExchangeSpatialCoverage.self, from: data)
        XCTAssertEqual(decoded.h3Cells, [ExchangeH3GoldenVectors.expectedCell])
        XCTAssertEqual(decoded.h3Resolution, ExchangeH3GoldenVectors.resolution)
    }

    func testSpatialCoverage_invalidCellsDropped() {
        let spatial = ExchangeSpatialCoverage(
            status: .resolved,
            source: .imported,
            h3Resolution: 7,
            h3Cells: [ExchangeH3GoldenVectors.expectedCell, "not-a-valid-h3-cell"]
        )
        XCTAssertEqual(spatial.h3Cells, [ExchangeH3GoldenVectors.expectedCell])
    }

    func testDeclaredServiceArea_withoutSpatial_decodes() throws {
        let json = """
        {
          "id": "aurora",
          "displayName": "Aurora",
          "normalizedName": "aurora",
          "aliases": [],
          "source": "sellerEntered",
          "acceptsRemote": false
        }
        """
        let area = try JSONDecoder().decode(ExchangeDeclaredServiceArea.self, from: json.data(using: .utf8)!)
        XCTAssertNil(area.spatial)
    }

    func testDeclaredServiceArea_withSpatial_roundtrip() throws {
        let area = ExchangeDeclaredServiceArea(
            displayName: "Aurora",
            spatial: ExchangeSpatialCoverage(
                status: .resolved,
                source: .manualCoordinate,
                h3Resolution: 7,
                h3Cells: [ExchangeH3GoldenVectors.expectedCell]
            )
        )
        XCTAssertNotNil(area.spatial)
        let data = try JSONEncoder().encode(area)
        let decoded = try JSONDecoder().decode(ExchangeDeclaredServiceArea.self, from: data)
        XCTAssertEqual(decoded.displayName, "Aurora")
        XCTAssertEqual(decoded.spatial?.h3Cells, [ExchangeH3GoldenVectors.expectedCell])
    }

    func testLocationRequirement_withSpatial_roundtrip() throws {
        let requirement = ExchangeLocationRequirement(
            displayName: "Aurora",
            normalizedName: "aurora",
            kind: .namedPlace,
            strictness: .preferred,
            spatial: ExchangeSpatialCoverage(
                status: .resolved,
                source: .savedDefault,
                h3Resolution: 7,
                h3Cells: [ExchangeH3GoldenVectors.expectedCell]
            )
        )
        let data = try JSONEncoder().encode(requirement)
        let decoded = try JSONDecoder().decode(ExchangeLocationRequirement.self, from: data)
        XCTAssertEqual(decoded.kind, .namedPlace)
        XCTAssertEqual(decoded.spatial?.h3Cells, [ExchangeH3GoldenVectors.expectedCell])
    }

    func testLocationRequirement_nearMe_defaultsSpatialNil() {
        let requirement = ExchangeLocationRequirement(
            rawText: "near me",
            displayName: "near me",
            kind: .nearMe,
            strictness: .requiresClarification,
            sourcePhrase: "near me"
        )
        XCTAssertNil(requirement.spatial)
        XCTAssertTrue(requirement.needsClarification)
    }

    func testSellerChipParsing_spatialNil() {
        let areas = ExchangeDeclaredServiceAreaSupport.parseSellerInput("Aurora, GTA, Online")
        XCTAssertEqual(areas.count, 3)
        XCTAssertTrue(areas.allSatisfy { $0.spatial == nil })
    }
}
