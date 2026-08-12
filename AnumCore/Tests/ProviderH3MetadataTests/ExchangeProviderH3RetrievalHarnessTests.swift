import XCTest
@testable import AnumCore

final class ExchangeProviderH3RetrievalHarnessTests: XCTestCase {
    private var auroraCenter: ExchangeCoordinate {
        ExchangeCoordinate(latitude: 43.999, longitude: -79.466)
    }

    private func auroraServiceArea() -> ExchangeDeclaredServiceArea {
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

    func testDirectoryMatchIngest_preservesServiceAreasOnRetrievalDocument() async {
        let spatial = auroraServiceArea().spatial
        let sampleCell = spatial?.h3Cells.first ?? ""
        XCTAssertFalse(sampleCell.isEmpty)

        let remoteDoc = ExchangeRetrievalDocument(
            id: "offer::offer-harness-aurora",
            counterpartyID: "node-harness-aurora",
            nodeID: "node-harness-aurora",
            publicProfileID: "profile-harness-aurora",
            offerID: "offer-harness-aurora",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            title: "Roof inspection / roof repair",
            tags: ["roofer", "roofing", "roof repair"],
            regionTags: ["aurora", "newmarket", "richmond hill"],
            serviceAreas: [auroraServiceArea()],
            lexicalText: "roofer roofing roof repair aurora",
            semanticText: "roof inspection"
        )

        let offer = ExchangeOffer(
            id: "offer-harness-aurora",
            nodeID: "node-harness-aurora",
            publicProfileID: "profile-harness-aurora",
            title: "Roof inspection / roof repair",
            tags: ["roofer", "roofing", "roof repair"],
            regionTags: ["Aurora", "Newmarket", "Richmond Hill"],
            serviceAreas: [auroraServiceArea()],
            status: .active,
            visibility: .publicDiscoverable
        )

        let profile = ExchangePublicNodeProfile(
            id: "profile-harness-aurora",
            nodeID: "node-harness-aurora",
            counterpartyID: "node-harness-aurora",
            displayName: "Aurora Roofing Test Provider",
            visibility: .discoverable,
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            )
        )

        let match = ExchangeDirectoryMatch(
            counterparty: ExchangeCounterparty(
                id: "node-harness-aurora",
                kind: .business,
                displayName: "Aurora Roofing Test Provider",
                source: .relayNetwork,
                publicProfile: profile
            ),
            publicProfile: profile,
            offers: [offer],
            retrievalDocuments: [remoteDoc],
            reachability: .init(
                isDiscoverable: true,
                isRouteableInPrinciple: true,
                allowsDirectContactInPrinciple: true,
                requiresIntroductionInPrinciple: false,
                hasRouteHint: true
            ),
            matchReason: "harness",
            matchedTerms: ["roofer", "aurora"]
        )

        let store = ExchangeRetrievalStore()
        let ingestor = ExchangeRetrievalIngestor(
            store: store,
            embeddingProvider: NoOpMemoryEmbeddingProvider(),
            embedRemoteDirectoryMatches: false
        )
        await ingestor.ingestDirectoryMatches([match], sourceKind: .remote)

        let docs = await store.listDocuments()
        guard let doc = docs.first(where: { $0.id == remoteDoc.id }) else { return XCTFail("missing doc"); }
        XCTAssertTrue(doc.serviceAreas.contains(where: { $0.spatial?.hasResolvedCells == true }))
        XCTAssertFalse(doc.lexicalText.contains(sampleCell))
        XCTAssertFalse(doc.regionTags.contains(where: { $0.contains(sampleCell) }))
    }

    func testSpatialOverlap_requesterNearAurora_overlapsProviderCoverage() {
        let providerSpatial = ExchangeProviderServiceCoverageBuilder.buildProviderServiceCoverage(
            center: auroraCenter,
            radiusMeters: 15_000,
            resolution: 7,
            source: .manualCoordinate
        )
        let requesterSpatial = ExchangeProviderServiceCoverageBuilder.buildProviderServiceCoverage(
            center: ExchangeCoordinate(latitude: 43.998, longitude: -79.465),
            radiusMeters: 10_000,
            resolution: 7,
            source: .manualCoordinate
        )
        let fit = ExchangeSpatialOverlap.spatialOverlap(
            requester: requesterSpatial,
            providerAreas: [ExchangeDeclaredServiceArea(displayName: "Aurora", spatial: providerSpatial)]
        )
        if case .overlap(let count) = fit {
            XCTAssertGreaterThan(count, 0)
        } else {
            XCTFail("Expected overlap near Aurora, got \(fit)")
        }
    }
}

private struct NoOpMemoryEmbeddingProvider: MemoryEmbeddingProvider {
    func embed(_ text: String) -> [Float]? { nil }
    }
