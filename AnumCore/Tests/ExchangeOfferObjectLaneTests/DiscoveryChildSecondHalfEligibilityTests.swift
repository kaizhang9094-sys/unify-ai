import Foundation
import Testing

@testable import AnumCore

@Suite("DiscoveryChildSecondHalfEligibility")
struct DiscoveryChildSecondHalfEligibilityTests {
    @Test("rank 1 strong primary child is eligible")
    func rankOneStrongEligible() {
        let umbrella = makeUmbrellaThread()
        let primary = makeMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            counterpartyID: "seller-primary",
            offerID: "offer-primary",
            strength: .strong,
            score: 0.82
        )
        let child = makeChildThread(sourceRank: 1, sourceMatchID: primary.id, counterpartyID: "seller-primary")

        let eligibility = DiscoveryChildSecondHalfEligibility.evaluate(
            childThread: child,
            childMatch: primary,
            umbrellaThread: umbrella,
            umbrellaMatches: [primary, secondaryMatch()],
            trigger: .discoveryAuto
        )

        #expect(eligibility.shouldRunSecondHalf)
        #expect(eligibility.decision == .eligible)
        #expect(eligibility.reason == "primary_strong_candidate")
    }

    @Test("rank 2 moderate child is shortlist only on discovery auto")
    func rankTwoModerateShortlistOnly() {
        let umbrella = makeUmbrellaThread()
        let primary = makeMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            counterpartyID: "seller-primary",
            offerID: "offer-primary",
            strength: .strong,
            score: 0.90
        )
        let noisy = makeMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            counterpartyID: "seller-noisy",
            offerID: "offer-minor",
            strength: .moderate,
            score: 0.72
        )
        let child = makeChildThread(sourceRank: 2, sourceMatchID: noisy.id, counterpartyID: "seller-noisy")

        let eligibility = DiscoveryChildSecondHalfEligibility.evaluate(
            childThread: child,
            childMatch: noisy,
            umbrellaThread: umbrella,
            umbrellaMatches: [primary, noisy],
            trigger: .discoveryAuto
        )

        #expect(!eligibility.shouldRunSecondHalf)
        #expect(eligibility.decision == .shortlistOnly)
        #expect(eligibility.reason == "non_primary_shortlist_candidate")
    }

    @Test("rank 1 moderate below fit floor is shortlist only")
    func rankOneModerateBelowFitFloor() {
        let umbrella = makeUmbrellaThread()
        let moderate = makeMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            counterpartyID: "seller-moderate",
            offerID: "offer-moderate",
            strength: .moderate,
            score: 0.55
        )
        let child = makeChildThread(sourceRank: 1, sourceMatchID: moderate.id, counterpartyID: "seller-moderate")

        let eligibility = DiscoveryChildSecondHalfEligibility.evaluate(
            childThread: child,
            childMatch: moderate,
            umbrellaThread: umbrella,
            umbrellaMatches: [moderate],
            trigger: .discoveryAuto
        )

        #expect(!eligibility.shouldRunSecondHalf)
        #expect(eligibility.reason == "primary_moderate_below_fit_floor")
    }

    @Test("object lane child without object evidence is shortlist only")
    func objectLaneWithoutEvidenceShortlistOnly() {
        let umbrella = makeObjectLaneUmbrellaThread()
        let proven = makeMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            counterpartyID: "seller-proven",
            offerID: "offer-proven",
            strength: .strong,
            score: 0.88,
            provenObjectOfferIDs: ["offer-proven"],
            objectEvidenceScoreByOfferID: ["offer-proven": 0.92]
        )
        let unproven = makeMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            counterpartyID: "seller-profile",
            offerID: "offer-generic",
            strength: .strong,
            score: 0.95,
            provenObjectOfferIDs: [],
            objectEvidenceScoreByOfferID: [:]
        )
        let child = makeChildThread(sourceRank: 1, sourceMatchID: unproven.id, counterpartyID: "seller-profile")

        let eligibility = DiscoveryChildSecondHalfEligibility.evaluate(
            childThread: child,
            childMatch: unproven,
            umbrellaThread: umbrella,
            umbrellaMatches: [proven, unproven],
            trigger: .discoveryAuto
        )

        #expect(!eligibility.shouldRunSecondHalf)
        #expect(eligibility.reason == "insufficient_object_evidence")
    }

    @Test("user explicit trigger allows non-primary child")
    func userExplicitAllowsNonPrimary() {
        let umbrella = makeUmbrellaThread()
        let primary = makeMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            counterpartyID: "seller-primary",
            offerID: "offer-primary",
            strength: .strong,
            score: 0.90
        )
        let secondary = secondaryMatch()
        let child = makeChildThread(sourceRank: 2, sourceMatchID: secondary.id, counterpartyID: secondary.counterpartyID)

        let eligibility = DiscoveryChildSecondHalfEligibility.evaluate(
            childThread: child,
            childMatch: secondary,
            umbrellaThread: umbrella,
            umbrellaMatches: [primary, secondary],
            trigger: .userExplicit
        )

        #expect(eligibility.shouldRunSecondHalf)
        #expect(eligibility.reason == "user_explicit_second_half")
    }
}

// MARK: - Helpers


private func makeEligibilitySafeProof(offerID: String) -> ExchangeCandidateSemanticProof {
    ExchangeCandidateSemanticProof(
        offerAttachments: [
            .init(
                offerID: offerID,
                reason: .directOfferDocumentHit,
                proofStrength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true
            )
        ],
        summary: .init(
            primaryOfferID: offerID,
            maxProofStrength: .concrete,
            satisfiesMinimumProof: true,
            hasWeakRecallOnly: false
        )
    )
}

private func secondaryMatch() -> ExchangeMatch {
    makeMatch(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
        counterpartyID: "seller-secondary",
        offerID: "offer-secondary",
        strength: .moderate,
        score: 0.70
    )
}

private func makeUmbrellaThread() -> ExchangeThread {
    ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "test",
            objective: "find cleaner"
        ),
        posture: ExchangePosture(),
        facets: ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            providerTerms: ["cleaner"]
        ),
        state: .searching(.init())
    )
}

private func makeObjectLaneUmbrellaThread() -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .product,
        objectType: "widget",
        transactionIntent: .buy,
        broadRecallTokens: ["widget"],
        semanticConcepts: ["widget"],
        rawUserText: "find widget"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer,
        primaryKeywords: ["widget"]
    )
    return ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            title: "test",
            objective: "find widget"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
}

private func makeChildThread(
    sourceRank: Int,
    sourceMatchID: UUID,
    counterpartyID: String
) -> ExchangeThread {
    var thread = ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "child",
            objective: "find cleaner"
        ),
        posture: ExchangePosture(),
        facets: ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            providerTerms: ["cleaner"]
        ),
        state: .searching(.init())
    )
    ExchangeThreadRoleResolver.applyCandidateCoordinationHierarchy(
        parentThreadID: UUID(),
        rootThreadID: UUID(),
        sourceMatchID: sourceMatchID,
        sourceRank: sourceRank,
        to: &thread.metadata
    )
    thread.selectedCounterpartyID = counterpartyID
    return thread
}

private func makeMatch(
    id: UUID,
    counterpartyID: String,
    offerID: String,
    strength: ExchangeMatch.Strength,
    score: Double,
    provenObjectOfferIDs: [String] = [],
    objectEvidenceScoreByOfferID: [String: Double] = [:],
    semanticProof: ExchangeCandidateSemanticProof? = nil
) -> ExchangeMatch {
    ExchangeMatch(
        id: id,
        threadID: UUID(),
        counterpartyID: counterpartyID,
        scope: .offer,
        offerID: offerID,
        matchedOfferIDs: [offerID],
        provenObjectOfferIDs: provenObjectOfferIDs,
        objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID,
        status: .selected,
        strength: strength,
        score: score,
        semanticProof: semanticProof ?? makeEligibilitySafeProof(offerID: offerID)
    )
}
