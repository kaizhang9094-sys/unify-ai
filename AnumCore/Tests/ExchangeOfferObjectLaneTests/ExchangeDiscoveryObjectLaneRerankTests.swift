import Testing

@testable import AnumCore

@Suite("ExchangeDiscoveryEngine object-lane rerank")
struct ExchangeDiscoveryObjectLaneRerankTests {
    private let engine = ExchangeDiscoveryEngine()

    @Test("proven object-offer candidate ranks above profile-rich unproven candidate")
    func provenObjectOfferRanksAboveProfileRichUnproven() {
        let thread = makeObjectLaneThread(objectType: "widget")
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)

        let provenOffer = makeOffer(
            id: "offer-exact",
            title: "Item",
            category: "goods",
            tags: ["widget"]
        )
        let provenCandidate = makeProjectedDiscoveryCandidate(
            counterpartyID: "seller-exact",
            matchedOffers: [provenOffer],
            publicProfile: nil,
            provenObjectOfferIDs: ["offer-exact"],
            objectEvidenceScoreByOfferID: ["offer-exact": 0.92],
            projectedRetrievalScore: 0.55,
            dominantSurface: .offer
        )

        let profileCandidate = makeProjectedDiscoveryCandidate(
            counterpartyID: "seller-profile",
            matchedOffers: [],
            publicProfile: richWidgetProfile(nodeID: "seller-profile"),
            provenObjectOfferIDs: [],
            objectEvidenceScoreByOfferID: [:],
            projectedRetrievalScore: 1.35,
            dominantSurface: .capability
        )

        let reranked = engine.rerankProjectedCandidatesForTests(
            [profileCandidate, provenCandidate],
            thread: thread,
            plan: plan,
            shortlistLimit: 12
        )

        #expect(reranked.count == 2)
        #expect(reranked[0].counterparty.id == "seller-exact")
        #expect(!reranked[0].provenObjectOfferIDs.isEmpty)
        #expect(reranked[1].provenObjectOfferIDs.isEmpty)
    }

    @Test("higher object evidence ranks above lower among proven candidates")
    func higherObjectEvidenceRanksFirstAmongProven() {
        let thread = makeObjectLaneThread(objectType: "widget")
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)

        let lowerOffer = makeOffer(id: "offer-low", title: "Item", category: "goods", tags: ["widget"])
        let higherOffer = makeOffer(id: "offer-high", title: "Item", category: "goods", tags: ["widget"])

        let lowerCandidate = makeProjectedDiscoveryCandidate(
            counterpartyID: "seller-low",
            matchedOffers: [lowerOffer],
            publicProfile: nil,
            provenObjectOfferIDs: ["offer-low"],
            objectEvidenceScoreByOfferID: ["offer-low": 0.62],
            projectedRetrievalScore: 0.90,
            dominantSurface: .offer
        )
        let higherCandidate = makeProjectedDiscoveryCandidate(
            counterpartyID: "seller-high",
            matchedOffers: [higherOffer],
            publicProfile: nil,
            provenObjectOfferIDs: ["offer-high"],
            objectEvidenceScoreByOfferID: ["offer-high": 0.96],
            projectedRetrievalScore: 0.50,
            dominantSurface: .offer
        )

        let reranked = engine.rerankProjectedCandidatesForTests(
            [lowerCandidate, higherCandidate],
            thread: thread,
            plan: plan,
            shortlistLimit: 12
        )

        #expect(reranked.first?.counterparty.id == "seller-high")
    }

    @Test("provider search rerank does not apply object-lane proven tier")
    func providerSearchRerankUnchangedByObjectLaneTier() {
        let thread = makeProviderThread(providerTerm: "installer")
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)

        let provenOffer = makeOffer(
            id: "offer-service",
            title: "Install",
            category: "service",
            tags: ["installer"]
        )
        let provenCandidate = makeProjectedDiscoveryCandidate(
            counterpartyID: "seller-proven",
            matchedOffers: [provenOffer],
            publicProfile: nil,
            provenObjectOfferIDs: ["offer-service"],
            objectEvidenceScoreByOfferID: ["offer-service": 0.95],
            projectedRetrievalScore: 0.40,
            dominantSurface: .offer
        )
        let profileCandidate = makeProjectedDiscoveryCandidate(
            counterpartyID: "seller-profile",
            matchedOffers: [],
            publicProfile: richInstallerProfile(nodeID: "seller-profile"),
            provenObjectOfferIDs: [],
            objectEvidenceScoreByOfferID: [:],
            projectedRetrievalScore: 1.20,
            dominantSurface: .capability
        )

        let reranked = engine.rerankProjectedCandidatesForTests(
            [provenCandidate, profileCandidate],
            thread: thread,
            plan: plan,
            shortlistLimit: 12
        )

        #expect(reranked.count == 2)
        #expect(reranked[0].counterparty.id == "seller-profile")
    }
}

// MARK: - Helpers

private func makeObjectLaneThread(objectType: String) -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .product,
        objectType: objectType,
        transactionIntent: .buy,
        broadRecallTokens: [objectType],
        semanticConcepts: [objectType],
        rawUserText: "find \(objectType)"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer,
        primaryKeywords: [objectType]
    )
    return ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            title: "test",
            objective: "find \(objectType)"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
}

private func makeProviderThread(providerTerm: String) -> ExchangeThread {
    let facets = ExchangeIntentFacets(
        queryIntentClass: .providerSearch,
        surfacePreference: .offer,
        providerTerms: [providerTerm]
    )
    return ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "test",
            objective: "find \(providerTerm)"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
}

private func richWidgetProfile(nodeID: String) -> ExchangePublicNodeProfile {
    ExchangePublicNodeProfile(
        id: "profile-\(nodeID)",
        nodeID: nodeID,
        displayName: "Broad Seller",
        headline: "Premier widget marketplace dealer",
        summary: "We sell widgets accessories parts supplies electronics and more",
        interests: ["widgets", "marketplace", "retail"],
        offers: ["widgets", "accessories", "parts", "supplies"],
        openTo: ["buyers", "local pickup"],
        activityTags: ["widget", "dealer", "retail", "marketplace"],
        regionTags: ["local"]
    )
}

private func richInstallerProfile(nodeID: String) -> ExchangePublicNodeProfile {
    ExchangePublicNodeProfile(
        id: "profile-\(nodeID)",
        nodeID: nodeID,
        displayName: "Installer Pro",
        headline: "Premier installer marketplace",
        summary: "We install fixtures appliances and more",
        interests: ["installer", "marketplace", "service"],
        offers: ["installer", "installation", "repair"],
        openTo: ["buyers"],
        activityTags: ["installer", "dealer", "service", "marketplace"],
        regionTags: ["local"]
    )
}

private func makeOffer(
    id: String,
    title: String,
    category: String,
    tags: [String] = []
) -> ExchangeOffer {
    ExchangeOffer(
        id: id,
        nodeID: "seller-1",
        title: title,
        category: category,
        tags: tags,
        status: .active,
        visibility: .publicDiscoverable
    )
}

private func makeProjectedDiscoveryCandidate(
    counterpartyID: String,
    matchedOffers: [ExchangeOffer],
    publicProfile: ExchangePublicNodeProfile?,
    provenObjectOfferIDs: Set<String>,
    objectEvidenceScoreByOfferID: [String: Double],
    projectedRetrievalScore: Double,
    dominantSurface: ExchangeDiscoveryEngine.DiscoveryCandidate.SurfaceType
) -> ExchangeDiscoveryEngine.DiscoveryCandidate {
    let counterparty = ExchangeCounterparty(
        id: counterpartyID,
        kind: .secretaryNode,
        displayName: "Seller",
        source: .relayNetwork,
        identity: .init(nodeID: counterpartyID, publicKeyID: nil, verification: .unverified),
        publicProfile: publicProfile,
        tags: [],
        semantic: .init(),
        contactRoutes: [],
        status: .active
    )
    return ExchangeDiscoveryEngine.DiscoveryCandidate(
        publicProfile: publicProfile,
        counterparty: counterparty,
        matchedOffers: matchedOffers,
        coarse: .init(
            queryTokenOverlap: 1,
            explicitTokenOverlap: 1,
            regionOverlap: 0,
            offerOverlap: matchedOffers.isEmpty ? 0 : 1,
            capabilityOverlap: publicProfile == nil ? 0 : 4,
            affinityOverlap: 0,
            hasPublicProfile: publicProfile != nil,
            hasOffers: !matchedOffers.isEmpty,
            kindCompatible: true,
            placeCompatible: true,
            trustHintScore: 0.5,
            retrievalScore: projectedRetrievalScore,
            rationale: "test-projection"
        ),
        posture: .init(
            bucket: .contactable,
            preview: "test",
            explicitOpenness: true,
            requiresIntroduction: false
        ),
        dominantSurface: dominantSurface,
        overallScore: projectedRetrievalScore,
        provenance: .retrievalProjected,
        provenObjectOfferIDs: provenObjectOfferIDs,
        objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID
    )
}
