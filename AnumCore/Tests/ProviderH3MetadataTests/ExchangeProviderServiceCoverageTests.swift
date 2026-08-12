import XCTest
@testable import AnumCore

final class ExchangeProviderServiceCoverageTests: XCTestCase {
    private var auroraCenter: ExchangeCoordinate {
        ExchangeCoordinate(latitude: 43.999, longitude: -79.466)
    }

    private func makeCoverageArea() -> ExchangeDeclaredServiceArea {
        let spatial = ExchangeProviderServiceCoverageBuilder.buildProviderServiceCoverage(
            center: auroraCenter,
            radiusMeters: 15_000,
            resolution: 7,
            source: .manualCoordinate
        )
        return ExchangeDeclaredServiceArea(
            displayName: "Aurora",
            normalizedName: "aurora",
            aliases: ["newmarket", "richmond hill"],
            spatial: spatial
        )
    }

    func testBuildProviderServiceCoverage_resolvedBoundedCells() {
        let coverage = ExchangeProviderServiceCoverageBuilder.buildProviderServiceCoverage(
            center: auroraCenter,
            radiusMeters: 15_000,
            resolution: 7,
            source: .manualCoordinate
        )
        XCTAssertEqual(coverage.status, .resolved)
        XCTAssertTrue(coverage.hasResolvedCells)
        XCTAssertEqual(coverage.h3Resolution, 7)
        XCTAssertGreaterThan(coverage.h3Cells.count, 0)
        XCTAssertLessThanOrEqual(coverage.h3Cells.count, 128)
        XCTAssertEqual(coverage.source, .manualCoordinate)
    }

    func testOfferCodable_roundTripsServiceAreasSpatial() throws {
        var offer = ExchangeOffer(
            id: "offer-h3-aurora",
            nodeID: "node-test",
            publicProfileID: "profile-test",
            title: "Roof inspection",
            regionTags: ["Aurora"],
            serviceAreas: [makeCoverageArea()],
            status: .active,
            visibility: .publicDiscoverable
        )
        ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&offer)

        let data = try JSONEncoder().encode(offer)
        let decoded = try JSONDecoder().decode(ExchangeOffer.self, from: data)
        XCTAssertEqual(decoded.serviceAreas.count, 1)
        XCTAssertTrue(decoded.serviceAreas[0].spatial?.hasResolvedCells == true)
        XCTAssertEqual(decoded.serviceAreas[0].spatial?.h3Resolution, 7)
        XCTAssertFalse(decoded.regionTags.contains(where: { $0.contains("872") }))
    }

    func testSQLiteOfferRoundTrip_preservesServiceAreasSpatial() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exchange-provider-h3-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let profile = ExchangePublicNodeProfile(
            id: "profile-h3",
            nodeID: "node-h3",
            counterpartyID: "node-h3",
            displayName: "Aurora Roofing Test Provider",
            visibility: .discoverable,
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            )
        )
        let counterparty = ExchangeCounterparty(
            id: "node-h3",
            kind: .business,
            displayName: "Aurora Roofing Test Provider",
            source: .relayNetwork
        )
        try await store.upsertCounterparties([counterparty])
        try await store.savePublicProfile(profile)

        var offer = ExchangeOffer(
            id: "offer-h3-aurora",
            nodeID: "node-h3",
            publicProfileID: profile.id,
            title: "Roof inspection / roof repair",
            tags: ["roofer", "roofing", "roof repair"],
            regionTags: ["Aurora", "Newmarket", "Richmond Hill"],
            serviceAreas: [makeCoverageArea()],
            status: .active,
            visibility: .publicDiscoverable
        )
        ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&offer)
        try await store.saveOffer(offer)

        let listed = try await store.listOffers(filter: .init(publicProfileID: profile.id, limit: 10))
        let reloaded = try XCTUnwrap(listed.first(where: { $0.id == offer.id }))
        XCTAssertTrue(reloaded.serviceAreas.contains(where: { $0.spatial?.hasResolvedCells == true }))
    }

    func testPublishedPayload_includesServiceAreas_notH3InRegionTags() throws {
        let offer = ExchangeOffer(
            id: "offer-pub",
            nodeID: "node-pub",
            publicProfileID: "profile-pub",
            title: "Roof repair",
            regionTags: ["Aurora"],
            serviceAreas: [makeCoverageArea()],
            status: .active,
            visibility: .publicDiscoverable
        )
        let profile = ExchangePublicNodeProfile(
            id: "profile-pub",
            nodeID: "node-pub",
            counterpartyID: "node-pub",
            displayName: "Provider",
            visibility: .discoverable,
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            )
        )
        let service = ExchangeDefaultSellerSurfaceService()
        let payload = service.buildPublishedPayload(
            ownerNodeID: "node-pub",
            ownerDisplayName: "Provider",
            publicProfile: profile,
            offers: [offer],
            publicationState: nil,
            now: Date()
        )
        let published = try XCTUnwrap(payload.offers.first)
        XCTAssertFalse(published.serviceAreas.isEmpty)
        XCTAssertTrue(published.serviceAreas.contains(where: { $0.spatial?.hasResolvedCells == true }))
        for tag in published.regionTags {
            XCTAssertFalse(tag.contains("872"), "regionTags must remain text-only")
        }
    }

    func testRetrievalDocumentBuilder_preservesServiceAreas_notInLexical() throws {
        let offer = ExchangeOffer(
            id: "offer-doc",
            nodeID: "node-doc",
            publicProfileID: "profile-doc",
            title: "Roof repair",
            regionTags: ["Aurora"],
            serviceAreas: [makeCoverageArea()],
            status: .active,
            visibility: .publicDiscoverable
        )
        let builder = ExchangeRetrievalDocumentBuilder()
        let documents = builder.buildDocuments(
            profile: ExchangePublicNodeProfile(
                id: "profile-doc",
                nodeID: "node-doc",
                counterpartyID: "node-doc",
                displayName: "Provider",
                visibility: .discoverable,
                reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                    accessMode: .direct,
                    acceptingInbound: true,
                    disclosureCeiling: .balanced
                )
            ),
            offers: [offer],
            counterpartyID: "node-doc",
            sourceKind: .local
        )
        let document = try XCTUnwrap(documents.first { $0.surfaceType == .offer })
        XCTAssertTrue(document.serviceAreas.contains(where: { $0.spatial?.hasResolvedCells == true }))
        XCTAssertFalse(document.lexicalText.contains("872"))
        XCTAssertFalse(document.regionTags.contains(where: { $0.contains("872") }))
    }

    func testRemoteIngest_preservesServiceAreasOnDocument() {
        let spatial = ExchangeProviderServiceCoverageBuilder.buildProviderServiceCoverage(
            center: auroraCenter,
            radiusMeters: 15_000,
            resolution: 7
        )
        let remoteDoc = ExchangeRetrievalDocument(
            id: "doc-remote",
            counterpartyID: "cp-remote",
            offerID: "offer-remote",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            title: "Roof repair",
            regionTags: ["aurora"],
            serviceAreas: [
                ExchangeDeclaredServiceArea(displayName: "Aurora", spatial: spatial)
            ],
            lexicalText: "roof repair aurora",
            semanticText: ""
        )
        let match = ExchangeDirectoryMatch(
            counterparty: ExchangeCounterparty(
                id: "cp-remote",
                kind: .business,
                displayName: "Remote",
                source: .relayNetwork
            ),
            retrievalDocuments: [remoteDoc],
            reachability: .init(
                isDiscoverable: true,
                isRouteableInPrinciple: true,
                allowsDirectContactInPrinciple: true,
                requiresIntroductionInPrinciple: false,
                hasRouteHint: true
            )
        )
        let built = ExchangeRetrievalDocumentBuilder().buildDocuments(matches: [match], sourceKind: .remote)
        let preserved = built.first(where: { $0.id == "doc-remote" })
        XCTAssertNotNil(preserved)
        XCTAssertTrue(preserved?.serviceAreas.contains(where: { $0.spatial?.hasResolvedCells == true }) == true)
    }

    func testRemoteIngest_withoutServiceAreas_stillDecodes() {
        let remoteDoc = ExchangeRetrievalDocument(
            id: "doc-legacy",
            counterpartyID: "cp-legacy",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            title: "Legacy offer",
            regionTags: ["aurora"],
            lexicalText: "legacy",
            semanticText: ""
        )
        XCTAssertTrue(remoteDoc.serviceAreas.isEmpty)
    }

    func testSpatialOverlap_helper() {
        let requester = ExchangeProviderServiceCoverageBuilder.buildProviderServiceCoverage(
            center: auroraCenter,
            radiusMeters: 10_000,
            resolution: 7
        )
        let providerArea = ExchangeDeclaredServiceArea(
            displayName: "Aurora",
            spatial: requester
        )
        let overlap = ExchangeSpatialOverlap.spatialOverlap(
            requester: requester,
            providerAreas: [providerArea]
        )
        if case .overlap(let count) = overlap {
            XCTAssertGreaterThan(count, 0)
        } else {
            XCTFail("Expected overlap, got \(overlap)")
        }

        let disjointProvider = ExchangeDeclaredServiceArea(
            displayName: "Far",
            spatial: ExchangeProviderServiceCoverageBuilder.buildProviderServiceCoverage(
                center: ExchangeCoordinate(latitude: 49.25, longitude: -123.12),
                radiusMeters: 1_000,
                resolution: 7
            )
        )
        let noOverlap = ExchangeSpatialOverlap.spatialOverlap(
            requester: requester,
            providerAreas: [disjointProvider]
        )
        XCTAssertEqual(noOverlap, .noOverlap)

        let unavailable = ExchangeSpatialOverlap.spatialOverlap(
            requester: requester,
            providerAreas: [ExchangeDeclaredServiceArea(displayName: "Text only")]
        )
        XCTAssertEqual(unavailable, .unavailable)
    }

    func testPrivacy_noH3InUserFacingDisplayStrings() {
        let area = makeCoverageArea()
        let cell = area.spatial?.h3Cells.first ?? ""
        XCTAssertFalse(area.displayName.contains(cell))
        XCTAssertFalse(area.normalizedName.contains(cell))
        let offer = ExchangeOffer(
            id: "offer-ui",
            nodeID: "node-ui",
            publicProfileID: "profile-ui",
            title: "Roof repair",
            regionTags: ["Aurora"],
            serviceAreas: [area],
            status: .active,
            visibility: .publicDiscoverable
        )
        XCTAssertFalse(offer.title.contains(cell))
        for tag in offer.regionTags {
            XCTAssertFalse(tag.contains(cell))
        }
    }
}
