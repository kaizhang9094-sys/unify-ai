import XCTest
@testable import AnumCore

private struct StubSellerServiceAreaGeocoder: ExchangeSellerServiceAreaGeocoding {
    let coordinatesByQuery: [String: ExchangeCoordinate]

    func geocodeAddressString(_ address: String) async throws -> ExchangeCoordinate? {
        let key = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return coordinatesByQuery[key]
    }
}

final class ExchangeSellerServiceAreaResolverTests: XCTestCase {
    func testResolveSellerInput_gazetteerToronto_producesSpatialH3() async {
        let resolver = ExchangeSellerServiceAreaResolver(geocoder: nil)
        let batch = await resolver.resolveSellerInput("Toronto")
        XCTAssertEqual(batch.areas.count, 1)
        XCTAssertEqual(batch.resolvedSpatialCount, 1)
        XCTAssertEqual(batch.textOnlyCount, 0)
        XCTAssertTrue(batch.areas[0].spatial?.hasResolvedCells == true)
        XCTAssertEqual(batch.areas[0].displayName, "Toronto")
        let tags = ExchangeDeclaredServiceAreaSupport.projectRegionTags(from: batch.areas)
        XCTAssertEqual(tags, ["Toronto"])
        XCTAssertFalse(tags.contains(where: { $0.contains("872") }))
    }

    func testResolveSellerInput_unknownPlace_textOnlyWithoutGeocoder() async {
        let resolver = ExchangeSellerServiceAreaResolver(geocoder: nil)
        let batch = await resolver.resolveSellerInput("Obscureville XYZ")
        XCTAssertEqual(batch.areas.count, 1)
        XCTAssertEqual(batch.resolvedSpatialCount, 0)
        XCTAssertEqual(batch.textOnlyCount, 1)
        XCTAssertNil(batch.areas[0].spatial)
        XCTAssertNotNil(batch.userNotice)
    }

    func testResolveSellerInput_stubGeocoder_resolvesCustomPlace() async {
        let geocoder = StubSellerServiceAreaGeocoder(
            coordinatesByQuery: [
                "obscureville xyz": ExchangeCoordinate(latitude: 45.0, longitude: -75.0)
            ]
        )
        let resolver = ExchangeSellerServiceAreaResolver(geocoder: geocoder)
        let batch = await resolver.resolveSellerInput("Obscureville XYZ")
        XCTAssertEqual(batch.resolvedSpatialCount, 1)
        XCTAssertTrue(batch.areas[0].spatial?.hasResolvedCells == true)
        XCTAssertEqual(batch.areas[0].spatial?.source, .geocoder)
    }

    func testResolveSellerInput_radiusPhrase_usesParsedRadius() async {
        let resolver = ExchangeSellerServiceAreaResolver(geocoder: nil)
        let batch = await resolver.resolveSellerInput("within 20km of Aurora")
        XCTAssertEqual(batch.resolvedSpatialCount, 1)
        let spatial = batch.areas[0].spatial
        XCTAssertEqual(spatial?.radiusMeters ?? 0, 20_000, accuracy: 1)
        XCTAssertTrue(spatial?.hasResolvedCells == true)
    }

    func testOfferCodable_roundTripsResolvedServiceAreas() async throws {
        let resolver = ExchangeSellerServiceAreaResolver(geocoder: nil)
        let batch = await resolver.resolveSellerInput("Markham")
        var offer = ExchangeOffer(
            id: "offer-resolve-markham",
            nodeID: "node-test",
            publicProfileID: "profile-test",
            title: "Test",
            serviceAreas: batch.areas,
            status: .active,
            visibility: .publicDiscoverable
        )
        ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&offer)

        let data = try JSONEncoder().encode(offer)
        let decoded = try JSONDecoder().decode(ExchangeOffer.self, from: data)
        XCTAssertTrue(decoded.serviceAreas[0].spatial?.hasResolvedCells == true)
        XCTAssertFalse(decoded.regionTags.joined(separator: " ").contains("872"))
    }
}
