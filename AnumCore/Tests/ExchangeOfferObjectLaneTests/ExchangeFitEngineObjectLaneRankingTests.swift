import Testing

@testable import AnumCore

@Suite("ExchangeFitEngine object-lane offer evidence")
struct ExchangeFitEngineObjectLaneRankingTests {
    private let fitEngine = ExchangeFitEngine()

    @Test("exact proven object offer outscores profile-rich broader seller")
    func exactProvenObjectOfferOutscoresProfileRichBroaderSeller() {
        let thread = makeObjectLaneThread(objectType: "widget")

        let sparseExactOffer = makeOffer(
            id: "offer-exact",
            title: "Item",
            category: "goods",
            tags: []
        )
        let exactCandidate = makeFitDiscoveryCandidate(
            counterpartyID: "seller-exact",
            matchedOffers: [sparseExactOffer],
            provenObjectOfferIDs: ["offer-exact"],
            objectEvidenceScoreByOfferID: ["offer-exact": 0.92],
            publicProfile: nil,
            dominantSurface: .offer,
            retrievalScore: 0.45
        )

        let broadOffer = makeOffer(
            id: "offer-broad",
            title: "Multi-category listing",
            category: "general",
            tags: ["widgets", "marketplace", "dealer", "retail"]
        )
        let broadCandidate = makeFitDiscoveryCandidate(
            counterpartyID: "seller-broad",
            matchedOffers: [broadOffer],
            provenObjectOfferIDs: ["offer-broad"],
            objectEvidenceScoreByOfferID: ["offer-broad": 0.55],
            publicProfile: richWidgetProfile(nodeID: "seller-broad"),
            dominantSurface: .capability,
            retrievalScore: 0.85
        )

        let matches = fitEngine.evaluate(
            thread: thread,
            candidates: [broadCandidate, exactCandidate]
        )

        #expect(matches.count == 2)
        let exactMatch = matches.first(where: { $0.counterpartyID == "seller-exact" })
        let broadMatch = matches.first(where: { $0.counterpartyID == "seller-broad" })
        #expect(exactMatch != nil)
        #expect(broadMatch != nil)
        #expect(exactMatch!.score > broadMatch!.score)
        #expect(exactMatch!.fit.offerFit ?? 0 >= 0.92)
        #expect((exactMatch!.fit.offerFit ?? 0) > (broadMatch!.fit.offerFit ?? 0))
    }

    @Test("broader candidate wins only with higher object evidence")
    func broaderCandidateWinsWithHigherObjectEvidence() {
        let thread = makeObjectLaneThread(objectType: "widget")

        let exactOffer = makeOffer(
            id: "offer-exact",
            title: "Item",
            category: "goods",
            tags: ["widget"]
        )
        let exactCandidate = makeFitDiscoveryCandidate(
            counterpartyID: "seller-exact",
            matchedOffers: [exactOffer],
            provenObjectOfferIDs: ["offer-exact"],
            objectEvidenceScoreByOfferID: ["offer-exact": 0.62],
            publicProfile: nil,
            dominantSurface: .offer,
            retrievalScore: 0.45
        )

        let broadOffer = makeOffer(
            id: "offer-broad",
            title: "General listing",
            category: "general",
            tags: ["widgets", "marketplace"]
        )
        let broadCandidate = makeFitDiscoveryCandidate(
            counterpartyID: "seller-broad",
            matchedOffers: [broadOffer],
            provenObjectOfferIDs: ["offer-broad"],
            objectEvidenceScoreByOfferID: ["offer-broad": 0.96],
            publicProfile: richWidgetProfile(nodeID: "seller-broad"),
            dominantSurface: .capability,
            retrievalScore: 0.85
        )

        let matches = fitEngine.evaluate(
            thread: thread,
            candidates: [exactCandidate, broadCandidate]
        )

        let exactMatch = matches.first(where: { $0.counterpartyID == "seller-exact" })
        let broadMatch = matches.first(where: { $0.counterpartyID == "seller-broad" })
        #expect(exactMatch != nil)
        #expect(broadMatch != nil)
        #expect(broadMatch!.score > exactMatch!.score)
        #expect((broadMatch!.fit.offerFit ?? 0) >= 0.96)
    }

    @Test("profile-only candidate remains weak without object provenance")
    func profileOnlyRemainsWeakWithoutObjectProvenance() {
        let thread = makeObjectLaneThread(objectType: "widget")
        let candidate = makeFitDiscoveryCandidate(
            counterpartyID: "seller-profile",
            matchedOffers: [],
            provenObjectOfferIDs: [],
            objectEvidenceScoreByOfferID: [:],
            publicProfile: richWidgetProfile(nodeID: "seller-profile"),
            dominantSurface: .capability,
            retrievalScore: 0.90
        )

        let matches = fitEngine.evaluate(thread: thread, candidates: [candidate])
        #expect(matches.count == 1)
        #expect(matches[0].strength == .weak)
        let offerFit = matches[0].fit.offerFit
        #expect(offerFit == nil || offerFit! <= 0.10)
    }

    @Test("provider search path does not apply object-lane offer evidence blend")
    func providerSearchPathUnchanged() {
        let thread = makeProviderThread(providerTerm: "installer")
        let offer = makeOffer(
            id: "offer-service",
            title: "Installation service",
            category: "service",
            tags: ["install"]
        )
        let candidate = makeFitDiscoveryCandidate(
            counterpartyID: "seller-service",
            matchedOffers: [offer],
            provenObjectOfferIDs: ["offer-service"],
            objectEvidenceScoreByOfferID: ["offer-service": 0.95],
            publicProfile: nil,
            dominantSurface: .offer,
            retrievalScore: 0.5
        )

        let matches = fitEngine.evaluate(thread: thread, candidates: [candidate])
        #expect(matches.count == 1)
        #expect((matches[0].fit.offerFit ?? 0) < 0.95)
    }
}

private func makeObjectLaneThread(objectType: String) -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .product,
        objectType: objectType,
        transactionIntent: .buy,
        semanticConcepts: [objectType],
        rawUserText: "find \(objectType)"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer
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

private func makeFitDiscoveryCandidate(
    counterpartyID: String,
    matchedOffers: [ExchangeOffer],
    provenObjectOfferIDs: Set<String>,
    objectEvidenceScoreByOfferID: [String: Double],
    publicProfile: ExchangePublicNodeProfile?,
    dominantSurface: ExchangeDiscoveryEngine.DiscoveryCandidate.SurfaceType,
    retrievalScore: Double
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
            queryTokenOverlap: 3,
            explicitTokenOverlap: 2,
            regionOverlap: 0,
            offerOverlap: matchedOffers.isEmpty ? 0 : 1,
            capabilityOverlap: publicProfile == nil ? 0 : 4,
            affinityOverlap: 0,
            hasPublicProfile: publicProfile != nil,
            hasOffers: !matchedOffers.isEmpty,
            kindCompatible: true,
            placeCompatible: true,
            trustHintScore: 0.5,
            retrievalScore: retrievalScore,
            rationale: "test"
        ),
        posture: .init(
            bucket: .contactable,
            preview: "test",
            explicitOpenness: true,
            requiresIntroduction: false
        ),
        dominantSurface: dominantSurface,
        overallScore: retrievalScore,
        provenObjectOfferIDs: provenObjectOfferIDs,
        objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID
    )
}
