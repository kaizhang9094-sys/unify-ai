import Foundation
import Testing
@testable import AnumCore

@Suite("SecondHalfProofGate")
struct SecondHalfProofGateTests {

    @Test("empty proof with concrete policy blocks automatic discovery second-half")
    func emptyProofWithConcretePolicyBlocks() {
        let policyThread = makeProviderProofPolicyThread()
        let match = makeProofMatch(
            strength: .strong,
            score: 0.82,
            proof: .empty
        )

        let safety = SecondHalfProofGate.evaluateSemanticMatchProofSafety(
            match: match,
            policyThread: policyThread,
            requireConcreteProof: true
        )

        #expect(!safety.isSafe)
        #expect(safety.reason == "missing_semantic_proof")
    }

    @Test("insufficient semantic proof blocks")
    func insufficientSemanticProofBlocks() {
        let policyThread = makeProviderProofPolicyThread()
        let match = makeProofMatch(
            strength: .strong,
            score: 0.82,
            proof: makeGateSemanticProof(
                offerID: "offer-generic",
                reason: .profileInheritedOffer,
                strength: .weakRecall,
                satisfiesMinimumProof: false,
                summarySatisfies: false,
                hasWeakRecallOnly: true
            )
        )

        let safety = SecondHalfProofGate.evaluateSemanticMatchProofSafety(
            match: match,
            policyThread: policyThread,
            requireConcreteProof: true
        )

        #expect(!safety.isSafe)
        #expect(safety.reason == "insufficient_semantic_proof")
    }

    @Test("weak recall only proof blocks")
    func weakRecallOnlyProofBlocks() {
        let policyThread = makeProviderProofPolicyThread()
        let match = makeProofMatch(
            strength: .strong,
            score: 0.82,
            proof: makeGateSemanticProof(
                offerID: "offer-generic",
                reason: .profileInheritedOffer,
                strength: .weakRecall,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: true
            )
        )

        let safety = SecondHalfProofGate.evaluateSemanticMatchProofSafety(
            match: match,
            policyThread: policyThread,
            requireConcreteProof: true
        )

        #expect(!safety.isSafe)
        #expect(safety.reason == "weak_recall_only_proof")
    }

    @Test("weak match strength blocks")
    func weakMatchStrengthBlocks() {
        let policyThread = makeProviderProofPolicyThread()
        let match = makeProofMatch(
            strength: .weak,
            score: 0.20,
            proof: makeGateSemanticProof(
                offerID: "offer-safe",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )

        let safety = SecondHalfProofGate.evaluateSemanticMatchProofSafety(
            match: match,
            policyThread: policyThread,
            requireConcreteProof: true
        )

        #expect(!safety.isSafe)
        #expect(safety.isWeakMatch)
        #expect(safety.reason == "weak_match_strength")
    }

    @Test("strong concrete proof allows")
    func strongConcreteProofAllows() {
        let policyThread = makeProviderProofPolicyThread()
        let match = makeProofMatch(
            strength: .strong,
            score: 0.88,
            proof: makeGateSemanticProof(
                offerID: "offer-safe",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )

        let safety = SecondHalfProofGate.evaluateSemanticMatchProofSafety(
            match: match,
            policyThread: policyThread,
            requireConcreteProof: true
        )

        #expect(safety.isSafe)
        #expect(safety.reason == "proof_safe")

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit.childCoordination",
                trigger: .automaticSecondHalf,
                thread: policyThread,
                policyThread: policyThread,
                selectedMatch: match
            )
        )
        #expect(decision.applies)
        #expect(decision.shouldRun)
    }

    @Test("user explicit bypasses proof gate")
    func userExplicitBypassesProofGate() {
        let policyThread = makeProviderProofPolicyThread()
        let match = makeProofMatch(
            strength: .weak,
            score: 0.20,
            proof: .empty
        )

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit.user_let_secretary_handle",
                trigger: .userExplicit,
                thread: policyThread,
                policyThread: policyThread,
                selectedMatch: match
            )
        )

        #expect(!decision.applies)
        #expect(decision.shouldRun)
        #expect(decision.reason == "out_of_scope")
    }

    @Test("manualOnly autonomy blocks before proof gate applies")
    func manualOnlyAutonomyBlocksBeforeProofGate() {
        let entryGate = SecondHalfAutomaticEntryGate.evaluate(source: "submit.childCoordination")
        #expect(!entryGate.shouldRun)
        #expect(entryGate.reason == "disabledByUserSetting")
    }

    @Test("non-child automatic submit fallback is gated")
    func nonChildAutomaticSubmitFallbackIsGated() {
        let policyThread = makeProviderProofPolicyThread()
        let match = makeProofMatch(
            strength: .strong,
            score: 0.82,
            proof: .empty
        )

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit",
                trigger: .automaticSecondHalf,
                thread: policyThread,
                policyThread: policyThread,
                selectedMatch: match
            )
        )

        #expect(decision.applies)
        #expect(!decision.shouldRun)
        #expect(decision.reason == "missing_semantic_proof")
    }

    @Test("reconcile inbox source is out of scope for proof gate")
    func reconcileInboxSourceIsOutOfScope() {
        let policyThread = makeProviderProofPolicyThread()
        let match = makeProofMatch(
            strength: .weak,
            score: 0.20,
            proof: .empty
        )

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "reconcileInbox",
                trigger: .automaticSecondHalf,
                thread: policyThread,
                policyThread: policyThread,
                selectedMatch: match
            )
        )

        #expect(!decision.applies)
        #expect(decision.shouldRun)
    }

    @Test("discovery child eligibility delegates empty proof hole to shared gate")
    func discoveryChildEligibilityDelegatesEmptyProofHole() {
        let umbrella = makeProviderProofPolicyThread()
        let primary = makeProofMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            strength: .strong,
            score: 0.82,
            proof: .empty
        )
        let child = makeChildCoordinationThread(
            sourceRank: 1,
            sourceMatchID: primary.id,
            counterpartyID: "seller-primary"
        )

        let eligibility = DiscoveryChildSecondHalfEligibility.evaluate(
            childThread: child,
            childMatch: primary,
            umbrellaThread: umbrella,
            umbrellaMatches: [primary],
            trigger: .discoveryAuto
        )

        #expect(!eligibility.shouldRunSecondHalf)
        #expect(eligibility.decision == .shortlistOnly)
        #expect(eligibility.reason == "missing_semantic_proof")
    }

    @Test("repair laptop with repair-only proof blocks automatic second-half")
    func repairLaptopRepairOnlyProofBlocks() {
        let policyThread = makeRepairLaptopPolicyThread()
        let match = makeProofMatch(
            strength: .strong,
            score: 0.82,
            offerID: "offer-appraisal-repair",
            proof: makeGateSemanticProof(
                offerID: "offer-appraisal-repair",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                targetOverlap: 1,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )
        let offerSurface = SecondHalfProofTargetCoverage.offerSurfaceTokens(
            from: makeRepairOffer(
                id: "offer-appraisal-repair",
                title: "Appraisal Repair Service",
                tags: ["repair", "plumber"]
            )
        )

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit",
                trigger: .automaticSecondHalf,
                thread: policyThread,
                policyThread: policyThread,
                selectedMatch: match,
                offerSurfaceTokens: offerSurface
            )
        )

        #expect(decision.applies)
        #expect(!decision.shouldRun)
        #expect(decision.reason == "target_concept_not_covered")
    }

    @Test("repair laptop with laptop repair proof allows automatic second-half")
    func repairLaptopLaptopRepairProofAllows() {
        let policyThread = makeRepairLaptopPolicyThread()
        let match = makeProofMatch(
            strength: .strong,
            score: 0.88,
            offerID: "offer-dell-laptop",
            proof: makeGateSemanticProof(
                offerID: "offer-dell-laptop",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )
        let offerSurface = SecondHalfProofTargetCoverage.offerSurfaceTokens(
            from: makeRepairOffer(
                id: "offer-dell-laptop",
                title: "Dell Laptop Repair",
                tags: ["laptop", "computer", "electronics", "repair"]
            )
        )

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit",
                trigger: .automaticSecondHalf,
                thread: policyThread,
                policyThread: policyThread,
                selectedMatch: match,
                offerSurfaceTokens: offerSurface
            )
        )

        #expect(decision.applies)
        #expect(decision.shouldRun)
        #expect(decision.reason == "proof_safe_full_target")
    }

    @Test("inherited profile-only proof blocks offer automation automatic second-half")
    func inheritedProfileOnlyProofBlocksOfferAutomation() {
        let policyThread = makeProviderProofPolicyThread()
        let match = makeProofMatch(
            strength: .strong,
            score: 0.82,
            proof: makeGateSemanticProof(
                offerID: "offer-inherited",
                reason: .profileInheritedOffer,
                strength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit",
                trigger: .automaticSecondHalf,
                thread: policyThread,
                policyThread: policyThread,
                selectedMatch: match
            )
        )

        #expect(decision.applies)
        #expect(!decision.shouldRun)
        #expect(decision.reason == "inherited_profile_only_proof")
    }

    @Test("missing selected match blocks automatic second-half")
    func missingSelectedMatchBlocks() {
        let policyThread = makeProviderProofPolicyThread()

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit",
                trigger: .automaticSecondHalf,
                thread: policyThread,
                policyThread: policyThread,
                selectedMatch: nil
            )
        )

        #expect(decision.applies)
        #expect(!decision.shouldRun)
        #expect(decision.reason == "missing_selected_match")
    }

    @Test("childCoordination allows shown non-canonical top candidate when proof-safe")
    func childCoordinationAllowsShownNonCanonicalChild() {
        var umbrella = makeCarSearchPolicyThread()
        ExchangeThreadCanonicalDiscoverySelectionMetadata.apply(
            ExchangeCanonicalDiscoverySelectionSnapshot(
                offerID: "offer-toyota-camry",
                source: "discovery"
            ),
            to: &umbrella.metadata
        )

        let canonicalMatch = makeProofMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            strength: .strong,
            score: 0.90,
            offerID: "offer-toyota-camry",
            proof: makeGateSemanticProof(
                offerID: "offer-toyota-camry",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )
        let multiCarMatch = makeProofMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            strength: .strong,
            score: 0.85,
            offerID: "offer-multi-car",
            proof: makeGateSemanticProof(
                offerID: "offer-multi-car",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )

        var multiCarChild = makeChildCoordinationThread(
            sourceRank: 2,
            sourceMatchID: multiCarMatch.id,
            counterpartyID: "seller-multi"
        )
        multiCarChild.selectedOfferID = "offer-multi-car"
        var canonicalChild = makeChildCoordinationThread(
            sourceRank: 1,
            sourceMatchID: canonicalMatch.id,
            counterpartyID: "seller-toyota"
        )
        canonicalChild.selectedOfferID = "offer-toyota-camry"

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit.childCoordination",
                trigger: .automaticSecondHalf,
                thread: multiCarChild,
                policyThread: umbrella,
                selectedMatch: multiCarMatch,
                umbrellaMatches: [canonicalMatch, multiCarMatch],
                activatedChildThreads: [canonicalChild, multiCarChild]
            )
        )

        #expect(decision.applies)
        #expect(decision.shouldRun)
        #expect(decision.reason == "proof_safe_shown_candidate")
    }

    @Test("childCoordination blocks hidden background candidate not in activated set")
    func childCoordinationBlocksHiddenBackgroundCandidate() {
        var umbrella = makeCarSearchPolicyThread()
        ExchangeThreadCanonicalDiscoverySelectionMetadata.apply(
            ExchangeCanonicalDiscoverySelectionSnapshot(
                offerID: "offer-toyota-camry",
                source: "discovery"
            ),
            to: &umbrella.metadata
        )

        let canonicalMatch = makeProofMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            strength: .strong,
            score: 0.90,
            offerID: "offer-toyota-camry",
            proof: makeGateSemanticProof(
                offerID: "offer-toyota-camry",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )
        let hiddenMatch = makeProofMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            strength: .strong,
            score: 0.80,
            offerID: "offer-background-noise",
            proof: makeGateSemanticProof(
                offerID: "offer-background-noise",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )

        var hiddenChild = makeChildCoordinationThread(
            sourceRank: 3,
            sourceMatchID: hiddenMatch.id,
            counterpartyID: "seller-hidden"
        )
        hiddenChild.selectedOfferID = "offer-background-noise"
        var canonicalChild = makeChildCoordinationThread(
            sourceRank: 1,
            sourceMatchID: canonicalMatch.id,
            counterpartyID: "seller-toyota"
        )
        canonicalChild.selectedOfferID = "offer-toyota-camry"

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit.childCoordination",
                trigger: .automaticSecondHalf,
                thread: hiddenChild,
                policyThread: umbrella,
                selectedMatch: hiddenMatch,
                umbrellaMatches: [canonicalMatch, hiddenMatch],
                activatedChildThreads: [canonicalChild]
            )
        )

        #expect(decision.applies)
        #expect(!decision.shouldRun)
        #expect(decision.reason == "not_shown_candidate")
    }

    @Test("childCoordination allows canonical selected child")
    func childCoordinationAllowsCanonicalChild() {
        var umbrella = makeCarSearchPolicyThread()
        ExchangeThreadCanonicalDiscoverySelectionMetadata.apply(
            ExchangeCanonicalDiscoverySelectionSnapshot(
                offerID: "offer-toyota-camry",
                source: "discovery"
            ),
            to: &umbrella.metadata
        )

        let canonicalMatch = makeProofMatch(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            strength: .strong,
            score: 0.90,
            offerID: "offer-toyota-camry",
            proof: makeGateSemanticProof(
                offerID: "offer-toyota-camry",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )

        let child = makeChildCoordinationThread(
            sourceRank: 1,
            sourceMatchID: canonicalMatch.id,
            counterpartyID: "seller-toyota"
        )

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit.childCoordination",
                trigger: .automaticSecondHalf,
                thread: child,
                policyThread: umbrella,
                selectedMatch: canonicalMatch,
                umbrellaMatches: [canonicalMatch]
            )
        )

        #expect(decision.applies)
        #expect(decision.shouldRun)
        #expect(decision.reason == "proof_safe_canonical_candidate")
    }

    @Test("cleaner query with cleaning offer allows through token equivalence")
    func cleanerQueryWithCleaningOfferAllows() {
        let policyThread = makeCleanerPolicyThread()
        let match = makeProofMatch(
            strength: .strong,
            score: 0.88,
            offerID: "offer-moveout-cleaning",
            proof: makeGateSemanticProof(
                offerID: "offer-moveout-cleaning",
                reason: .directOfferDocumentHit,
                strength: .concrete,
                targetOverlap: 2,
                genericOverlap: 0,
                satisfiesMinimumProof: true,
                summarySatisfies: true,
                hasWeakRecallOnly: false
            )
        )
        let offerSurface = SecondHalfProofTargetCoverage.offerSurfaceTokens(
            from: makeRepairOffer(
                id: "offer-moveout-cleaning",
                title: "Move Out Cleaning Service",
                tags: ["cleaning", "move", "out"]
            )
        )

        let decision = SecondHalfProofGate.evaluate(
            SecondHalfProofGate.Input(
                source: "submit",
                trigger: .automaticSecondHalf,
                thread: policyThread,
                policyThread: policyThread,
                selectedMatch: match,
                offerSurfaceTokens: offerSurface
            )
        )

        #expect(decision.applies)
        #expect(decision.shouldRun)
        #expect(decision.reason == "proof_safe_full_target")
    }
}

private func makeProviderProofPolicyThread() -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .homeService,
        objectType: "vehicle",
        transactionIntent: .hire,
        semanticConcepts: ["vehicle"],
        rawUserText: "find vehicle"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .providerSearch,
        surfacePreference: .offer,
        capabilityTerms: ["vehicle"]
    )
    return ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "test",
            objective: "find vehicle"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
}

private func makeGateSemanticProof(
    offerID: String,
    reason: ExchangeCandidateSemanticProof.AttachmentReason,
    strength: ExchangeSemanticProofStrength,
    targetOverlap: Int = 2,
    genericOverlap: Int = 0,
    satisfiesMinimumProof: Bool,
    summarySatisfies: Bool,
    hasWeakRecallOnly: Bool
) -> ExchangeCandidateSemanticProof {
    ExchangeCandidateSemanticProof(
        offerAttachments: [
            .init(
                offerID: offerID,
                reason: reason,
                proofStrength: strength,
                targetOverlap: targetOverlap,
                genericOverlap: genericOverlap,
                satisfiesMinimumProof: satisfiesMinimumProof
            )
        ],
        summary: .init(
            primaryOfferID: offerID,
            maxProofStrength: strength,
            satisfiesMinimumProof: summarySatisfies,
            hasWeakRecallOnly: hasWeakRecallOnly
        )
    )
}

private func makeProofMatch(
    id: UUID = UUID(),
    strength: ExchangeMatch.Strength,
    score: Double,
    offerID: String? = nil,
    proof: ExchangeCandidateSemanticProof
) -> ExchangeMatch {
    let resolvedOfferID = offerID ?? proof.summary.primaryOfferID ?? "offer-primary"
    return ExchangeMatch(
        id: id,
        threadID: UUID(),
        counterpartyID: "seller-primary",
        scope: .offer,
        offerID: resolvedOfferID,
        matchedOfferIDs: [resolvedOfferID],
        status: .selected,
        strength: strength,
        score: score,
        semanticProof: proof
    )
}

private func makeChildCoordinationThread(
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
            objective: "find vehicle"
        ),
        posture: ExchangePosture(),
        facets: ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            capabilityTerms: ["vehicle"]
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

private func makeRepairLaptopPolicyThread() -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .homeService,
        objectType: "person",
        transactionIntent: .hire,
        semanticConcepts: ["repair laptop"],
        rawUserText: "find me someone who repairs laptops"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .providerSearch,
        surfacePreference: .offer,
        capabilityTerms: ["repair", "laptop"]
    )
    return ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "test",
            objective: "repair laptop"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
}

private func makeCarSearchPolicyThread() -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .product,
        objectType: "car",
        transactionIntent: .hire,
        semanticConcepts: ["car"],
        rawUserText: "find me a car"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer,
        capabilityTerms: ["car"]
    )
    return ExchangeThread(
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            title: "test",
            objective: "find car"
        ),
        posture: ExchangePosture(),
        facets: facets,
        state: .searching(.init())
    )
}

private func makeCleanerPolicyThread() -> ExchangeThread {
    let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: .homeService,
        objectType: "cleaner",
        transactionIntent: .hire,
        semanticConcepts: ["cleaner"],
        rawUserText: "find me a cleaner tomorrow at 2 under 200"
    )
    let facets = ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .providerSearch,
        surfacePreference: .offer,
        capabilityTerms: ["cleaner", "cleaning"]
    )
    return ExchangeThread(
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
        facets: facets,
        state: .searching(.init())
    )
}

private func makeRepairOffer(
    id: String,
    title: String,
    tags: [String]
) -> ExchangeOffer {
    ExchangeOffer(
        id: id,
        nodeID: "node-test",
        title: title,
        tags: tags,
        regionTags: [],
        serviceAreas: [],
        canonicalRegionIDs: [],
        parentRegionIDs: [],
        regionAliases: [],
        semantic: .init(serviceKinds: tags),
        fulfillment: .init(),
        status: .active,
        visibility: .publicDiscoverable,
        createdAt: Date(),
        updatedAt: Date()
    )
}
