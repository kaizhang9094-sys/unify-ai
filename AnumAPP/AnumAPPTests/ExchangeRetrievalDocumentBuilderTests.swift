import XCTest
import AnumCore

/// `ExchangeRetrievalDocumentBuilder` surface typing + `ExchangeRetrievalIngestor` upsert behavior.
/// Ensures lane gates (`entityType` / `surfaceType`) align with how profiles and offers are projected.
final class ExchangeRetrievalDocumentBuilderTests: XCTestCase {
    private let fixtureDate = SecretaryProjectionTestSupport.fixtureDate
    private let builder = ExchangeRetrievalDocumentBuilder()
    private let embedder = FixedEmbeddingProvider(dimensions: 16)

    // MARK: - Builder: entity / surface typing

    func test_builder_offerDocument_entityAndSurfaceAreOffer() {
        let profile = makeProfile(
            id: "pp-offer-surface",
            nodeID: "node-offer-surface",
            interests: ["community"],
            headline: "Pro seller"
        )
        let offer = makeOffer(
            id: "offer-surface-1",
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            title: "Widget pack",
            tags: ["bulk"]
        )
        let docs = builder.buildDocuments(
            profile: profile,
            offers: [offer],
            counterpartyID: "cp-offer-surface",
            sourceKind: .local
        )
        let offerDoc = docs.first { $0.id == "offer::\(offer.id)" }
        XCTAssertNotNil(offerDoc)
        XCTAssertEqual(offerDoc?.entityType, ExchangeRetrievalDocument.EntityType.offer)
        XCTAssertEqual(offerDoc?.surfaceType, ExchangeRetrievalDocument.SurfaceType.offer)
        XCTAssertEqual(offerDoc?.offerID, offer.id)
    }

    func test_builder_publicProfileCapability_entityAndSurface() {
        let profile = makeProfile(
            id: "pp-cap-only",
            nodeID: "node-cap-only",
            interests: [],
            headline: "Integration engineer",
            semanticDomains: ["systems integration"],
            offers: ["consulting"]
        )
        let docs = builder.buildDocuments(
            profile: profile,
            offers: [],
            counterpartyID: "cp-cap-only",
            sourceKind: .local
        )
        let cap = docs.first { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.publicProfileCapability }
        XCTAssertNotNil(cap)
        XCTAssertEqual(cap?.entityType, ExchangeRetrievalDocument.EntityType.publicProfile)
        XCTAssertEqual(cap?.surfaceType, ExchangeRetrievalDocument.SurfaceType.publicProfileCapability)
        XCTAssertNil(cap?.offerID)
    }

    func test_builder_publicProfileAffinity_entityAndSurface() {
        let profile = makeProfile(
            id: "pp-aff-only",
            nodeID: "node-aff-only",
            interests: ["bookclub", "hiking"],
            headline: "Friendly node"
        )
        let docs = builder.buildDocuments(
            profile: profile,
            offers: [],
            counterpartyID: "cp-aff-only",
            sourceKind: .local
        )
        let aff = docs.first { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.publicProfileAffinity }
        XCTAssertNotNil(aff)
        XCTAssertEqual(aff?.entityType, ExchangeRetrievalDocument.EntityType.publicProfile)
        XCTAssertEqual(aff?.surfaceType, ExchangeRetrievalDocument.SurfaceType.publicProfileAffinity)
    }

    func test_builder_capabilityOnlyProfile_doesNotEmitOfferSurface() {
        let profile = makeProfile(
            id: "pp-prof-only",
            nodeID: "node-prof-only",
            interests: [],
            headline: "Compliance counsel",
            semanticDomains: ["legal compliance"],
            offers: ["contract review"],
            activityTags: [],
            openTo: []
        )
        let docs = builder.buildDocuments(
            profile: profile,
            offers: [],
            counterpartyID: "cp-prof-only",
            sourceKind: .local
        )
        XCTAssertFalse(docs.contains { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.offer })
        XCTAssertTrue(docs.contains { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.publicProfileCapability })
        XCTAssertNil(docs.first { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.publicProfileAffinity })
    }

    func test_builder_affinityTermsOnAffinitySurface_notOfferSurface() {
        let profile = makeProfile(
            id: "pp-social-only",
            nodeID: "node-social-only",
            interests: ["picnic planning"],
            headline: "Social coordinator",
            semanticDomains: [],
            offers: [],
            activityTags: []
        )
        let docs = builder.buildDocuments(
            profile: profile,
            offers: [],
            counterpartyID: "cp-social-only",
            sourceKind: .local
        )
        XCTAssertFalse(docs.contains { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.offer })
        let affinity = docs.first { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.publicProfileAffinity }
        XCTAssertNotNil(affinity)
        XCTAssertTrue(affinity?.affinityTerms.contains("picnic planning") == true)
        let capability = docs.first { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.publicProfileCapability }
        XCTAssertNotNil(capability)
        XCTAssertTrue(capability?.affinityTerms.isEmpty == true)
    }

    func test_builder_offerCommercialFacts_tags_andFingerprintInRetrievalText() {
        let profile = makeProfile(
            id: "pp-comm-1",
            nodeID: "node-comm-1",
            interests: ["networking"],
            headline: "Commercial fixture host"
        )
        let commercial = ExchangeOffer.CommercialFacts(
            priceDisplay: "$250 per session",
            faqs: [
                ExchangeOffer.FAQ(question: "Cancellation?", answer: "24h notice.")
            ]
        )
        let offer = makeOffer(
            id: "offer-comm-1",
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            title: "Executive coaching",
            summary: "One on one leadership sessions",
            category: "coaching",
            tags: ["fixturetagcommercial", "leadership"],
            semanticDomains: ["coaching"],
            semanticServiceKinds: ["workshop"],
            commercialFacts: commercial
        )
        let doc = builder.buildDocuments(
            profile: profile,
            offers: [offer],
            counterpartyID: "cp-comm-1",
            sourceKind: .local
        ).first { $0.id == "offer::\(offer.id)" }

        XCTAssertNotNil(doc)
        guard let offerDoc = doc else { return }
        let haystack = [
            offerDoc.lexicalText,
            offerDoc.semanticText,
            offerDoc.primaryText,
            offerDoc.secondaryText,
            offerDoc.searchableText
        ]
            .joined(separator: " ")
            .lowercased()

        XCTAssertTrue(haystack.contains("fixturetagcommercial"), "tags should be searchable")
        XCTAssertTrue(haystack.contains("price:"), "commercial fingerprint should land in lexical/semantic text")
        XCTAssertTrue(haystack.contains("$250"), "price display should be searchable")
        XCTAssertTrue(haystack.contains("faq:"), "FAQ fingerprint should be indexed")
        XCTAssertFalse(offerDoc.capabilityTerms.contains("fixturetagcommercial"))
        XCTAssertTrue(offerDoc.providerTerms.contains("executive coaching") || haystack.contains("executive coaching"))
    }

    // MARK: - Ingestor + store

    func test_ingest_directoryMatch_upsertsProfileAndOfferDocuments() async {
        let store = ExchangeRetrievalStore()
        let ingestor = ExchangeRetrievalIngestor(
            builder: builder,
            store: store,
            embeddingProvider: embedder
        )
        let profile = makeProfile(
            id: "pp-ingest-both",
            nodeID: "node-ingest-both",
            interests: ["meetups"],
            headline: "Host node"
        )
        let offer = makeOffer(
            id: "offer-ingest-both",
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            title: "Catering package"
        )
        let cp = makeCounterparty(id: "cp-ingest-both", profile: profile)
        let match = ExchangeDirectoryMatch.fromCounterparty(cp, offers: [offer])

        await ingestor.ingestDirectoryMatches([match], sourceKind: .local)

        let stored = await store.listDocuments()
        XCTAssertTrue(stored.contains { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.publicProfileCapability })
        XCTAssertTrue(stored.contains { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.publicProfileAffinity })
        XCTAssertTrue(stored.contains {
            $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.offer && $0.offerID == offer.id
        })
    }

    func test_ingest_profileOnlyMatch_doesNotCreateOfferDocuments() async {
        let store = ExchangeRetrievalStore()
        let ingestor = ExchangeRetrievalIngestor(
            builder: builder,
            store: store,
            embeddingProvider: embedder
        )
        let profile = makeProfile(
            id: "pp-ingest-profile-only",
            nodeID: "node-ingest-profile-only",
            interests: ["reading"],
            headline: "Reader"
        )
        let cp = makeCounterparty(id: "cp-ingest-profile-only", profile: profile)
        let match = ExchangeDirectoryMatch.fromCounterparty(cp, offers: [])

        await ingestor.ingestDirectoryMatches([match], sourceKind: .local)

        let stored = await store.listDocuments()
        XCTAssertFalse(stored.contains { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.offer })
    }

    func test_ingest_offerOnlyMatch_preservesOfferIDOnOfferDocument() async {
        let store = ExchangeRetrievalStore()
        let ingestor = ExchangeRetrievalIngestor(
            builder: builder,
            store: store,
            embeddingProvider: embedder
        )
        let offerID = "offer-orphan-stable-id"
        let offer = makeOffer(
            id: offerID,
            nodeID: "node-orphan",
            publicProfileID: nil,
            title: "Standalone SKU"
        )
        let cp = ExchangeCounterparty(
            id: "cp-offer-only",
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            kind: .business,
            displayName: "Orphan seller",
            source: .relayNetwork,
            identity: .init(nodeID: "node-orphan", verification: .unverified),
            publicProfile: nil
        )
        let reachability = ExchangeDirectoryMatch.ReachabilityPreview(
            isDiscoverable: true,
            isRouteableInPrinciple: true,
            allowsDirectContactInPrinciple: true,
            requiresIntroductionInPrinciple: false,
            hasRouteHint: false
        )
        let match = ExchangeDirectoryMatch(
            counterparty: cp,
            publicProfile: nil,
            offers: [offer],
            reachability: reachability
        )

        await ingestor.ingestDirectoryMatches([match], sourceKind: .local)

        let stored = await store.listDocuments()
        XCTAssertEqual(stored.filter { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.offer }.count, 1)
        let offerDoc = stored.first { $0.surfaceType == ExchangeRetrievalDocument.SurfaceType.offer }
        XCTAssertEqual(offerDoc?.offerID, offerID)
        XCTAssertEqual(offerDoc?.id, "offer::\(offerID)")
        XCTAssertEqual(offerDoc?.entityType, ExchangeRetrievalDocument.EntityType.offer)
    }

    func test_ingest_repeatedUpsert_sameStableIDs_noDuplicates() async {
        let store = ExchangeRetrievalStore()
        let ingestor = ExchangeRetrievalIngestor(
            builder: builder,
            store: store,
            embeddingProvider: embedder
        )
        let profile = makeProfile(
            id: "pp-upsert-stable",
            nodeID: "node-upsert-stable",
            interests: ["cycling"],
            headline: "First headline"
        )
        let offer = makeOffer(
            id: "offer-upsert-stable",
            nodeID: profile.nodeID,
            publicProfileID: profile.id,
            title: "First title"
        )
        let cp1 = makeCounterparty(id: "cp-upsert-stable", profile: profile)
        let match1 = ExchangeDirectoryMatch.fromCounterparty(cp1, offers: [offer])

        await ingestor.ingestDirectoryMatches([match1], sourceKind: .local)
        let countAfterFirst = await store.documentCount

        var profileV2 = profile
        profileV2.headline = "Updated headline for upsert"
        var offerV2 = offer
        offerV2.title = "Updated offer title"
        offerV2.updatedAt = fixtureDate.addingTimeInterval(3600)

        let cp2 = makeCounterparty(id: "cp-upsert-stable", profile: profileV2)
        let match2 = ExchangeDirectoryMatch.fromCounterparty(cp2, offers: [offerV2])

        await ingestor.ingestDirectoryMatches([match2], sourceKind: .local)
        let countAfterSecond = await store.documentCount

        XCTAssertEqual(countAfterFirst, countAfterSecond)

        let fetchedOffer = await store.fetchDocument(id: "offer::\(offer.id)")
        XCTAssertEqual(fetchedOffer?.title, "Updated offer title")

        let fetchedCap = await store.fetchDocument(id: "profile-capability::\(profile.id)")
        XCTAssertEqual(fetchedCap?.primaryText.lowercased().contains("updated headline"), true)
    }

    // MARK: - Fixtures

    private func makeProfile(
        id: String,
        nodeID: String,
        interests: [String],
        headline: String,
        semanticDomains: [String] = [],
        offers: [String] = [],
        activityTags: [String] = [],
        openTo: [String] = []
    ) -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: id,
            nodeID: nodeID,
            displayName: "Fixture \(id)",
            headline: headline,
            summary: "Fixture summary for \(id)",
            interests: interests,
            offers: offers,
            openTo: openTo,
            activityTags: activityTags,
            semantic: ExchangePublicNodeProfile.SemanticSurface(
                domains: semanticDomains,
                intentKinds: semanticDomains.isEmpty ? [] : ["professional"]
            ),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
    }

    private func makeOffer(
        id: String,
        nodeID: String,
        publicProfileID: String?,
        title: String,
        summary: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        semanticDomains: [String] = [],
        semanticServiceKinds: [String] = [],
        commercialFacts: ExchangeOffer.CommercialFacts = .empty
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: id,
            nodeID: nodeID,
            publicProfileID: publicProfileID,
            title: title,
            summary: summary,
            category: category,
            tags: tags,
            semantic: ExchangeOffer.SemanticSurface(
                domains: semanticDomains,
                serviceKinds: semanticServiceKinds
            ),
            status: .active,
            visibility: .publicDiscoverable,
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            commercialFacts: commercialFacts
        )
    }

    private func makeCounterparty(
        id: String,
        profile: ExchangePublicNodeProfile
    ) -> ExchangeCounterparty {
        ExchangeCounterparty(
            id: id,
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            kind: .secretaryNode,
            displayName: profile.displayName ?? id,
            source: .relayNetwork,
            identity: .init(nodeID: profile.nodeID, verification: .unverified),
            publicProfile: profile
        )
    }
}
