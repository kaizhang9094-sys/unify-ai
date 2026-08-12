import XCTest
@testable import AnumCore

final class ExchangeDiscoveryH3SpatialBoostTests: XCTestCase {
    private var auroraCenter: ExchangeCoordinate {
        ExchangeCoordinate(latitude: 43.999, longitude: -79.466)
    }

    private var distantCenter: ExchangeCoordinate {
        ExchangeCoordinate(latitude: 49.2827, longitude: -123.1207)
    }

    private func requesterAnchor(at center: ExchangeCoordinate) -> ExchangeRequesterSpatialAnchor {
        let spatial = ExchangeH3CoverageBuilder.buildCoverage(
            center: center,
            radiusMeters: 10_000,
            resolution: 7,
            source: .manualCoordinate
        )
        return ExchangeRequesterSpatialAnchor(
            source: .explicitQuery,
            coordinate: center,
            spatial: spatial
        )
    }

    private func providerArea(at center: ExchangeCoordinate, name: String) -> ExchangeDeclaredServiceArea {
        let spatial = ExchangeProviderServiceCoverageBuilder.buildProviderServiceCoverage(
            center: center,
            radiusMeters: 15_000,
            resolution: 7,
            source: .manualCoordinate
        )
        return ExchangeDeclaredServiceArea(
            displayName: name,
            normalizedName: name.lowercased(),
            aliases: [],
            spatial: spatial
        )
    }

    func testOverlapGivesCappedBoost() {
        let anchor = requesterAnchor(at: auroraCenter)
        let areas = [providerArea(at: auroraCenter, name: "Aurora")]

        let adjustment = ExchangeSpatialOverlapScoring.evaluate(
            requesterAnchor: anchor,
            providerAreas: areas,
            explicitRegionRequired: false,
            textRegionMatchSucceeded: false
        )

        guard case .overlap = adjustment.fit else {
            return XCTFail("expected overlap fit")
        }
        XCTAssertGreaterThanOrEqual(adjustment.boost, ExchangeSpatialOverlapScoring.baseBoost)
        XCTAssertLessThanOrEqual(adjustment.boost, ExchangeSpatialOverlapScoring.maxBoost)
        XCTAssertEqual(adjustment.demotion, 0)
        XCTAssertGreaterThan(adjustment.scoreDelta, 0)
    }

    func testNoProviderH3_givesNoPenalty() {
        let anchor = requesterAnchor(at: auroraCenter)
        let textOnlyArea = ExchangeDeclaredServiceArea(
            displayName: "Aurora",
            normalizedName: "aurora",
            aliases: ["newmarket"],
            spatial: nil
        )

        let adjustment = ExchangeSpatialOverlapScoring.evaluate(
            requesterAnchor: anchor,
            providerAreas: [textOnlyArea],
            explicitRegionRequired: true,
            textRegionMatchSucceeded: false
        )

        XCTAssertEqual(adjustment.fit, .unavailable)
        XCTAssertEqual(adjustment.boost, 0)
        XCTAssertEqual(adjustment.demotion, 0)
        XCTAssertEqual(adjustment.scoreDelta, 0)
    }

    func testRequesterNamedPlaceWithoutH3_usesTextRegionOnly_noH3Boost() {
        let namedOnlyAnchor = ExchangeRequesterSpatialAnchor(
            source: .explicitQuery,
            coordinate: auroraCenter,
            spatial: nil
        )
        let areas = [providerArea(at: auroraCenter, name: "Aurora")]

        let adjustment = ExchangeSpatialOverlapScoring.evaluate(
            requesterAnchor: namedOnlyAnchor,
            providerAreas: areas,
            explicitRegionRequired: false,
            textRegionMatchSucceeded: true
        )

        XCTAssertEqual(adjustment.fit, .unavailable)
        XCTAssertEqual(adjustment.boost, 0)
        XCTAssertEqual(adjustment.demotion, 0)
    }

    func testNoOverlap_doesNotHardFilter_noBoostWithoutTextFailure() {
        let anchor = requesterAnchor(at: auroraCenter)
        let areas = [providerArea(at: distantCenter, name: "Vancouver")]

        let adjustment = ExchangeSpatialOverlapScoring.evaluate(
            requesterAnchor: anchor,
            providerAreas: areas,
            explicitRegionRequired: false,
            textRegionMatchSucceeded: true
        )

        XCTAssertEqual(adjustment.fit, .noOverlap)
        XCTAssertEqual(adjustment.boost, 0)
        XCTAssertEqual(adjustment.demotion, 0)
    }

    func testNoOverlap_mildDemotionOnlyWhenExplicitRegionAndTextFails() {
        let anchor = requesterAnchor(at: auroraCenter)
        let areas = [providerArea(at: distantCenter, name: "Vancouver")]

        let adjustment = ExchangeSpatialOverlapScoring.evaluate(
            requesterAnchor: anchor,
            providerAreas: areas,
            explicitRegionRequired: true,
            textRegionMatchSucceeded: false
        )

        XCTAssertEqual(adjustment.fit, .noOverlap)
        XCTAssertEqual(adjustment.boost, 0)
        XCTAssertEqual(adjustment.demotion, ExchangeSpatialOverlapScoring.mildDemotion)
    }

    func testH3CellsDoNotAppearInRegionTagsKeywordsOrLexicalText() throws {
        let area = providerArea(at: auroraCenter, name: "Aurora")
        let cells = area.spatial?.h3Cells ?? []
        XCTAssertFalse(cells.isEmpty)

        var offer = ExchangeOffer(
            id: "offer-h3-boost",
            nodeID: "node-boost",
            publicProfileID: "profile-boost",
            title: "Roof repair",
            tags: ["roofer"],
            regionTags: ["Aurora"],
            serviceAreas: [area],
            status: .active,
            visibility: .publicDiscoverable
        )
        ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&offer)

        let builder = ExchangeRetrievalDocumentBuilder()
        let documents = builder.buildDocuments(
            profile: ExchangePublicNodeProfile(
                id: "profile-boost",
                nodeID: "node-boost",
                counterpartyID: "node-boost",
                displayName: "Provider",
                visibility: .discoverable,
                reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                    accessMode: .direct,
                    acceptingInbound: true,
                    disclosureCeiling: .balanced
                )
            ),
            offers: [offer],
            counterpartyID: "node-boost",
            sourceKind: .local
        )
        let doc = try XCTUnwrap(documents.first { $0.surfaceType == .offer })
        let joinedTags = (offer.regionTags + offer.tags + doc.regionTags).joined(separator: " ")
        let lexical = doc.lexicalText + doc.semanticText + doc.searchableText

        for cell in cells.prefix(3) {
            XCTAssertFalse(joinedTags.contains(cell), "H3 must not leak into regionTags/tags")
            XCTAssertFalse(lexical.contains(cell), "H3 must not leak into lexical/searchable text")
        }
    }
}
