import Foundation
import Testing

@testable import AnumCore

@Suite("ExchangeDiscoveryService object-lane bestMatch selection")
struct ExchangeDiscoveryBestMatchSelectionTests {
    private let service = ExchangeDiscoveryService(
        discoveryEngine: ExchangeDiscoveryEngine(),
        fitEngine: ExchangeFitEngine()
    )

    @Test("object lane selects highest object evidence not first advanceable")
    func objectLaneSelectsHighestObjectEvidence() {
        let thread = makeObjectLaneThread(objectType: "widget")
        let lower = makeRankedCandidate(
            counterpartyID: "seller-low",
            offerID: "offer-low",
            provenObjectOfferIDs: ["offer-low"],
            objectEvidenceScoreByOfferID: ["offer-low": 0.62],
            fitScore: 0.88,
            discoveryScore: 1.30,
            strength: .strong,
            advanceable: true
        )
        let higher = makeRankedCandidate(
            counterpartyID: "seller-high",
            offerID: "offer-high",
            provenObjectOfferIDs: ["offer-high"],
            objectEvidenceScoreByOfferID: ["offer-high": 0.96],
            fitScore: 0.72,
            discoveryScore: 0.95,
            strength: .strong,
            advanceable: true
        )

        let selected = service.selectBestMatchForTests(
            thread: thread,
            hydrated: [lower, higher]
        )

        #expect(selected?.counterpartyID == "seller-high")
        #expect(selected?.offerID == "offer-high")
    }

    @Test("object lane ignores non-proven advanceable profile-only candidate")
    func objectLaneIgnoresNonProvenProfileOnly() {
        let thread = makeObjectLaneThread(objectType: "widget")
        let profileOnly = makeRankedCandidate(
            counterpartyID: "seller-profile",
            offerID: nil,
            provenObjectOfferIDs: [],
            objectEvidenceScoreByOfferID: [:],
            fitScore: 0.95,
            discoveryScore: 1.40,
            strength: .strong,
            advanceable: false,
            dominantSurface: .capability,
            hasPublicProfile: true
        )
        let proven = makeRankedCandidate(
            counterpartyID: "seller-proven",
            offerID: "offer-proven",
            provenObjectOfferIDs: ["offer-proven"],
            objectEvidenceScoreByOfferID: ["offer-proven": 0.91],
            fitScore: 0.70,
            discoveryScore: 0.80,
            strength: .moderate,
            advanceable: true
        )

        let selected = service.selectBestMatchForTests(
            thread: thread,
            hydrated: [profileOnly, proven]
        )

        #expect(selected?.counterpartyID == "seller-proven")
        #expect(selected?.offerID == "offer-proven")
    }

    @Test("provider search keeps first advanceable selection")
    func providerSearchKeepsFirstAdvanceable() {
        let thread = makeProviderThread(providerTerm: "installer")
        let first = makeRankedCandidate(
            counterpartyID: "seller-first",
            offerID: "offer-first",
            provenObjectOfferIDs: ["offer-first"],
            objectEvidenceScoreByOfferID: ["offer-first": 0.55],
            fitScore: 0.60,
            discoveryScore: 1.10,
            strength: .strong,
            advanceable: true
        )
        let second = makeRankedCandidate(
            counterpartyID: "seller-second",
            offerID: "offer-second",
            provenObjectOfferIDs: ["offer-second"],
            objectEvidenceScoreByOfferID: ["offer-second": 0.98],
            fitScore: 0.95,
            discoveryScore: 0.70,
            strength: .strong,
            advanceable: true
        )

        let selected = service.selectBestMatchForTests(
            thread: thread,
            hydrated: [first, second]
        )

        #expect(selected?.counterpartyID == "seller-first")
    }

    @Test("object lane tie-breaks equal object evidence by fit score")
    func objectLaneTieBreaksByFitScore() {
        let thread = makeObjectLaneThread(objectType: "widget")
        let lowerFit = makeRankedCandidate(
            counterpartyID: "seller-a",
            offerID: "offer-a",
            provenObjectOfferIDs: ["offer-a"],
            objectEvidenceScoreByOfferID: ["offer-a": 0.90],
            fitScore: 0.70,
            discoveryScore: 1.20,
            strength: .strong,
            advanceable: true
        )
        let higherFit = makeRankedCandidate(
            counterpartyID: "seller-b",
            offerID: "offer-b",
            provenObjectOfferIDs: ["offer-b"],
            objectEvidenceScoreByOfferID: ["offer-b": 0.90],
            fitScore: 0.85,
            discoveryScore: 0.90,
            strength: .strong,
            advanceable: true
        )

        let selected = service.selectBestMatchForTests(
            thread: thread,
            hydrated: [lowerFit, higherFit]
        )

        #expect(selected?.counterpartyID == "seller-b")
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

private func makeRankedCandidate(
    counterpartyID: String,
    offerID: String?,
    provenObjectOfferIDs: Set<String>,
    objectEvidenceScoreByOfferID: [String: Double],
    fitScore: Double,
    discoveryScore: Double,
    strength: ExchangeMatch.Strength,
    advanceable: Bool,
    dominantSurface: ExchangeDiscoveryEngine.DiscoveryCandidate.SurfaceType = .offer,
    hasPublicProfile: Bool = false
) -> ExchangeDiscoveryService.RankedCandidate {
    let publicProfile: ExchangePublicNodeProfile? = hasPublicProfile
        ? ExchangePublicNodeProfile(
            id: "profile-\(counterpartyID)",
            nodeID: counterpartyID,
            displayName: "Seller",
            headline: "Seller headline",
            summary: "Seller summary",
            interests: ["widgets"],
            offers: ["widgets"],
            activityTags: ["widget"]
        )
        : nil

    let matchedOffers: [ExchangeOffer]
    if let offerID {
        matchedOffers = [
            ExchangeOffer(
                id: offerID,
                nodeID: counterpartyID,
                title: "Item",
                category: "goods",
                tags: ["widget"],
                status: .active,
                visibility: .publicDiscoverable
            )
        ]
    } else {
        matchedOffers = []
    }

    let candidate = ExchangeDiscoveryEngine.DiscoveryCandidate(
        publicProfile: publicProfile,
        counterparty: ExchangeCounterparty(
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
        ),
        matchedOffers: matchedOffers,
        coarse: .init(
            queryTokenOverlap: 1,
            explicitTokenOverlap: 1,
            regionOverlap: 0,
            offerOverlap: matchedOffers.isEmpty ? 0 : 1,
            capabilityOverlap: hasPublicProfile ? 2 : 0,
            affinityOverlap: 0,
            hasPublicProfile: hasPublicProfile,
            hasOffers: !matchedOffers.isEmpty,
            kindCompatible: true,
            placeCompatible: true,
            trustHintScore: 0.5,
            retrievalScore: discoveryScore,
            rationale: "test"
        ),
        posture: .init(
            bucket: .contactable,
            preview: "test",
            explicitOpenness: true,
            requiresIntroduction: false
        ),
        dominantSurface: dominantSurface,
        overallScore: discoveryScore,
        provenance: .retrievalProjected,
        provenObjectOfferIDs: provenObjectOfferIDs,
        objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID
    )

    let match = ExchangeMatch(
        threadID: UUID(),
        counterpartyID: counterpartyID,
        scope: offerID == nil ? .publicProfile : .offer,
        publicProfileID: publicProfile?.id,
        offerID: offerID,
        matchedOfferIDs: matchedOffers.map(\.id),
        provenObjectOfferIDs: Array(provenObjectOfferIDs).sorted(),
        objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID,
        strength: strength,
        score: fitScore
    )

    return ExchangeDiscoveryService.RankedCandidate(
        candidate: candidate,
        match: match,
        isAdvanceable: advanceable,
        rankSummary: "test"
    )
}
