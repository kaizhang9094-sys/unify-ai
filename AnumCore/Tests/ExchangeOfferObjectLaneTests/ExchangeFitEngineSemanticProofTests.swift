import Testing

@testable import AnumCore

@Suite("ExchangeFitEngine semantic proof shaping")
struct ExchangeFitEngineSemanticProofTests {
    private let fitEngine = ExchangeFitEngine()

    @Test("unsatisfied semantic proof cannot become strong")
    func unsatisfiedSemanticProofCannotBecomeStrong() {
        let thread = makeProviderProofThread(need: "vehicle")

        let candidate = makeProofDiscoveryCandidate(
            counterpartyID: "seller-generic",
            matchedOffers: [
                makeOffer(
                    id: "offer-generic",
                    title: "General marketplace listing",
                    category: "general",
                    tags: ["marketplace", "dealer", "retail"]
                )
            ],
            retrievalScore: 0.88,
            proof: makeSemanticProof(
                offerID: "offer-generic",
                reason: .profileInheritedOffer,
                strength: .weakRecall,
                targetOverlap: 0,
                genericOverlap: 2,
                satisfiesMinimumProof: false,
                summarySatisfies: false
            )
        )

        let matches = fitEngine.evaluate(thread: thread, candidates: [candidate])
        #expect(matches.count == 1)
        #expect(matches[0].strength == .weak)
        #expect((matches[0].fit.offerFit ?? 1.0) <= 0.12)
    }

    @Test("satisfied semantic proof remains eligible")
    func satisfiedSemanticProofRemainsEligible() {
        let thread = makeProviderProofThread(need: "vehicle")

        let candidate = makeProofDiscoveryCandidate(
            counterpartyID: "seller-specific",
            matchedOffers: [
                makeOffer(
                    id: "offer-specific",
                    title: "Compact vehicle listing",
                    category: "vehicle",
                    tags: ["vehicle"]
                )
            ],
            retrievalScore: 0.72,
            proof: makeSemanticProof(
                offerID: "offer-specific",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true
            )
        )

        let matches = fitEngine.evaluate(thread: thread, candidates: [candidate])
        #expect(matches.count == 1)
        #expect(matches[0].strength != .weak)
        #expect((matches[0].fit.offerFit ?? 0) >= 0.68)
        #expect(matches[0].semanticProof?.summary.satisfiesMinimumProof == true)
    }

    @Test("proof-valid specificity tie-break prefers clearer concrete offer over broader multi-offer seller")
    func proofValidSpecificityPrefersClearerConcreteOffer() {
        let thread = makeConcreteObjectThread(objectType: "vehicle")

        let specificOffer = makeOffer(
            id: "offer-specific",
            title: "Compact vehicle",
            category: "vehicle",
            tags: ["vehicle"]
        )
        let specificCandidate = makeProofDiscoveryCandidate(
            counterpartyID: "seller-specific",
            matchedOffers: [specificOffer],
            retrievalScore: 0.68,
            proof: makeSemanticProof(
                offerID: "offer-specific",
                reason: .objectEmbeddingProven,
                strength: .exact,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                objectEvidenceScore: 0.84
            ),
            provenObjectOfferIDs: ["offer-specific"],
            objectEvidenceScoreByOfferID: ["offer-specific": 0.84]
        )

        let broadOffers = [
            makeOffer(id: "offer-a", title: "Inventory slot A", category: "general", tags: ["marketplace"]),
            makeOffer(id: "offer-b", title: "Inventory slot B", category: "general", tags: ["dealer"]),
            makeOffer(id: "offer-c", title: "Inventory slot C", category: "general", tags: ["retail"]),
        ]
        let broadCandidate = makeProofDiscoveryCandidate(
            counterpartyID: "seller-broad",
            matchedOffers: broadOffers,
            retrievalScore: 0.88,
            proof: makeSemanticProof(
                offerID: "offer-a",
                reason: .objectEmbeddingProven,
                strength: .concrete,
                targetOverlap: 1,
                genericOverlap: 2,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                objectEvidenceScore: 0.93
            ),
            provenObjectOfferIDs: ["offer-a"],
            objectEvidenceScoreByOfferID: ["offer-a": 0.93]
        )

        let matches = fitEngine.evaluate(
            thread: thread,
            candidates: [broadCandidate, specificCandidate]
        )

        let specificMatch = matches.first(where: { $0.counterpartyID == "seller-specific" })
        let broadMatch = matches.first(where: { $0.counterpartyID == "seller-broad" })
        #expect(specificMatch != nil)
        #expect(broadMatch != nil)
        #expect(specificMatch!.score > broadMatch!.score)
        #expect((specificMatch!.fit.offerFit ?? 0) > (broadMatch!.fit.offerFit ?? 0))
    }
}

private func makeConcreteObjectThread(objectType: String) -> ExchangeThread {
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

private func makeProviderProofThread(need: String) -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .homeService,
        objectType: need,
        transactionIntent: .hire,
        semanticConcepts: [need],
        rawUserText: "find \(need)"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .providerSearch,
        surfacePreference: .offer,
        capabilityTerms: [need]
    )
    return ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "test",
            objective: "find \(need)"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
}

private func makeSemanticProof(
    offerID: String,
    reason: ExchangeCandidateSemanticProof.AttachmentReason,
    strength: ExchangeSemanticProofStrength,
    targetOverlap: Int,
    genericOverlap: Int,
    satisfiesMinimumProof: Bool,
    summarySatisfies: Bool,
    objectEvidenceScore: Double? = nil
) -> ExchangeCandidateSemanticProof {
    ExchangeCandidateSemanticProof(
        offerAttachments: [
            .init(
                offerID: offerID,
                reason: reason,
                proofStrength: strength,
                objectEvidenceScore: objectEvidenceScore ?? (strength == .exact ? 0.82 : 0.55),
                lexicalOverlap: targetOverlap + genericOverlap,
                targetOverlap: targetOverlap,
                genericOverlap: genericOverlap,
                satisfiesMinimumProof: satisfiesMinimumProof
            )
        ],
        summary: .init(
            primaryOfferID: offerID,
            maxProofStrength: strength,
            satisfiesMinimumProof: summarySatisfies,
            hasWeakRecallOnly: strength == .weakRecall
        )
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

private func makeProofDiscoveryCandidate(
    counterpartyID: String,
    matchedOffers: [ExchangeOffer],
    retrievalScore: Double,
    proof: ExchangeCandidateSemanticProof,
    provenObjectOfferIDs: Set<String> = [],
    objectEvidenceScoreByOfferID: [String: Double] = [:]
) -> ExchangeDiscoveryEngine.DiscoveryCandidate {
    let counterparty = ExchangeCounterparty(
        id: counterpartyID,
        kind: .secretaryNode,
        displayName: "Seller",
        source: .relayNetwork,
        identity: .init(nodeID: counterpartyID, publicKeyID: nil, verification: .unverified),
        publicProfile: nil,
        tags: [],
        semantic: .init(),
        contactRoutes: [],
        status: .active
    )

    return ExchangeDiscoveryEngine.DiscoveryCandidate(
        publicProfile: nil,
        counterparty: counterparty,
        matchedOffers: matchedOffers,
        coarse: .init(
            queryTokenOverlap: 3,
            explicitTokenOverlap: 2,
            regionOverlap: 0,
            offerOverlap: matchedOffers.isEmpty ? 0 : 2,
            capabilityOverlap: 0,
            affinityOverlap: 0,
            hasPublicProfile: false,
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
        dominantSurface: .offer,
        overallScore: retrievalScore,
        provenObjectOfferIDs: provenObjectOfferIDs,
        objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID,
        semanticProof: proof
    )
}
