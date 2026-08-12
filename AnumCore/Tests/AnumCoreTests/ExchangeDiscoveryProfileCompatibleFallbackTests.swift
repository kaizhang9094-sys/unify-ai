import Foundation
import XCTest

@testable import AnumCore

final class ExchangeDiscoveryProfileCompatibleFallbackTests: XCTestCase {

    private let engine = ExchangeDiscoveryEngine()
    private let projector = ExchangeRetrievalCandidateProjector()

    // MARK: - Fixtures

    private func coderProfile(
        profileID: String = "profile-coder-01",
        counterpartyID: String = "cp-coder-01",
        nodeID: String = "node-coder-01"
    ) -> (ExchangePublicNodeProfile, ExchangeCounterparty) {
        let publicProfile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            counterpartyID: counterpartyID,
            displayName: "Kai",
            headline: "Like coding",
            summary: "Vibe coder",
            visibility: .discoverable,
            offers: ["coder"],
            semantic: ExchangePublicNodeProfile.SemanticSurface(
                domains: ["coder"],
                intentKinds: ["coding"]
            ),
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            )
        )

        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            kind: .person,
            displayName: "Kai",
            source: .relayNetwork,
            publicProfile: publicProfile
        )

        return (publicProfile, counterparty)
    }

    private func unrelatedCatOffer(
        profileID: String,
        nodeID: String
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: "offer-cat-noise",
            nodeID: nodeID,
            publicProfileID: profileID,
            title: "Cat",
            tags: ["cat"],
            regionTags: [],
            status: .active,
            visibility: .publicDiscoverable
        )
    }

    private func capabilityDocument(
        profileID: String,
        counterpartyID: String
    ) -> ExchangeRetrievalDocument {
        ExchangeRetrievalDocument(
            id: "profile-capability::\(profileID)",
            counterpartyID: counterpartyID,
            publicProfileID: profileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileCapability,
            sourceKind: .remote,
            title: "Kai",
            summary: "Vibe coder",
            tags: ["coder"],
            regionTags: [],
            lexicalText: "coder coding vibe coder",
            semanticText: "coder coding",
            providerTerms: ["coder"],
            capabilityTerms: ["coder", "coding"]
        )
    }

    private func makeProviderSearchThread(
        objective: String = "Find a coder near me",
        providerTerms: [String] = ["coder"],
        targetKind: ExchangeIntentFacets.TargetKind = .provider
    ) -> ExchangeThread {
        let facets = ExchangeIntentFacets(
            targetKind: targetKind,
            fulfillmentMode: .localPreferred,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            providerTerms: providerTerms,
            regionTerms: []
        )

        return ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .providerSearch,
                surfacePreference: .offer,
                title: "Find coder",
                objective: objective,
                targetDescription: "coder"
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )
    }

    private func projectAndRerank(
        thread: ExchangeThread,
        match: ExchangeDirectoryMatch,
        document: ExchangeRetrievalDocument,
        fusedScore: Double = 0.742
    ) -> [ExchangeDiscoveryEngine.DiscoveryCandidate] {
        let retrievalCandidate = ExchangeRetrievalEngine.Candidate(
            document: document,
            fusedScore: fusedScore,
            contributingSources: ["lexical", "vector"],
            bestRankBySource: ["lexical": 1, "vector": 1]
        )

        let projected = projector.project(
            [retrievalCandidate],
            knownMatches: [match],
            thread: thread
        )

        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)
        return engine.rerankProjectedCandidatesForTests(
            projected,
            thread: thread,
            plan: plan,
            shortlistLimit: 12
        )
    }

    // MARK: - Tests

    func testProviderSearchCapabilityProfileSurvivesRerankWithoutMatchingOffer() throws {
        let (publicProfile, counterparty) = coderProfile()
        let catOffer = unrelatedCatOffer(profileID: publicProfile.id, nodeID: publicProfile.nodeID)
        let match = ExchangeDirectoryMatch.fromCounterparty(
            counterparty,
            offers: [catOffer]
        )
        let document = capabilityDocument(
            profileID: publicProfile.id,
            counterpartyID: counterparty.id
        )
        let thread = makeProviderSearchThread()

        let reranked = projectAndRerank(
            thread: thread,
            match: match,
            document: document
        )

        XCTAssertEqual(reranked.count, 1)
        let row = reranked[0]
        XCTAssertTrue(row.matchedOffers.isEmpty)
        XCTAssertTrue(row.coarse.kindCompatible)
        XCTAssertTrue(row.coarse.isRetrievable)
        XCTAssertEqual(row.dominantSurface, .capability)
        XCTAssertGreaterThan(row.coarse.capabilityOverlap, 0)
    }

    func testOfferSearchAllowsCapabilityFallbackWhenOfferOverlapZero() throws {
        let (publicProfile, counterparty) = coderProfile()
        let catOffer = unrelatedCatOffer(profileID: publicProfile.id, nodeID: publicProfile.nodeID)
        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [catOffer])
        let document = capabilityDocument(profileID: publicProfile.id, counterpartyID: counterparty.id)

        let facets = ExchangeIntentFacets(
            targetKind: .provider,
            fulfillmentMode: .localPreferred,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            providerTerms: ["coder"]
        )
        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer,
                title: "Find offer",
                objective: "Find a coding service package",
                targetDescription: "coder"
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )

        let reranked = projectAndRerank(thread: thread, match: match, document: document)

        XCTAssertEqual(reranked.count, 1)
        let row = reranked[0]
        XCTAssertTrue(row.matchedOffers.isEmpty)
        XCTAssertEqual(row.coarse.offerOverlap, 0)
        XCTAssertGreaterThan(row.coarse.capabilityOverlap, 0)
        XCTAssertTrue(row.coarse.kindCompatible)
        XCTAssertTrue(row.coarse.isRetrievable)
        XCTAssertEqual(row.dominantSurface, .capability)
    }

    func testSocialAffinitySearchAllowsAffinityOverlapForPersonTarget() throws {
        let profileID = "profile-swim-01"
        let counterpartyID = "cp-swim-01"

        let publicProfile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: "node-swim-01",
            counterpartyID: counterpartyID,
            displayName: "Alex",
            summary: "Swimming enthusiast",
            visibility: .discoverable,
            interests: ["swimming"],
            activityTags: ["swimming"],
            semantic: ExchangePublicNodeProfile.SemanticSurface(
                domains: ["swimming"]
            ),
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            )
        )

        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            kind: .person,
            displayName: "Alex",
            source: .relayNetwork,
            publicProfile: publicProfile
        )

        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [])

        let affinityDoc = ExchangeRetrievalDocument(
            id: "profile-affinity::\(profileID)",
            counterpartyID: counterpartyID,
            publicProfileID: profileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileAffinity,
            sourceKind: .remote,
            title: "Alex",
            tags: ["swimming"],
            lexicalText: "swimming enthusiast pool laps",
            semanticText: "swimming",
            affinityTerms: ["swimming"]
        )

        let facets = ExchangeIntentFacets(
            targetKind: .person,
            fulfillmentMode: .localPreferred,
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            affinityTerms: ["swimming"],
            explicitAffinityNeed: true
        )

        let thread = ExchangeThread(
            mode: .cooperative,
            intent: ExchangeIntent(
                kind: .find,
                mode: .cooperative,
                queryIntentClass: .socialAffinitySearch,
                surfacePreference: .affinity,
                title: "Find swimmer",
                objective: "Find a swimming enthusiast nearby",
                targetDescription: "swimming enthusiast"
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )

        let reranked = projectAndRerank(thread: thread, match: match, document: affinityDoc)

        XCTAssertEqual(reranked.count, 1)
        let row = reranked[0]
        XCTAssertGreaterThan(row.coarse.affinityOverlap, 0)
        XCTAssertTrue(row.coarse.kindCompatible)
        XCTAssertTrue(row.coarse.isRetrievable)
        XCTAssertTrue(row.dominantSurface == .affinity || row.dominantSurface == .capability)
    }

    func testProfileFallbackRejectedWithoutSemanticOverlap() throws {
        let profileID = "profile-pottery-01"
        let counterpartyID = "cp-pottery-01"

        let publicProfile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: "node-pottery-01",
            counterpartyID: counterpartyID,
            displayName: "Sam",
            headline: "Pottery studio",
            summary: "Handmade ceramics",
            visibility: .discoverable,
            offers: ["pottery"],
            semantic: ExchangePublicNodeProfile.SemanticSurface(domains: ["pottery"]),
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            )
        )

        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            kind: .person,
            displayName: "Sam",
            source: .relayNetwork,
            publicProfile: publicProfile
        )

        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [])
        let document = ExchangeRetrievalDocument(
            id: "profile-capability::\(profileID)",
            counterpartyID: counterpartyID,
            publicProfileID: profileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileCapability,
            sourceKind: .remote,
            title: "Sam",
            tags: ["pottery"],
            lexicalText: "pottery ceramics handmade",
            semanticText: "pottery",
            capabilityTerms: ["pottery"]
        )

        let thread = makeProviderSearchThread(objective: "Find a coder near me", providerTerms: ["coder"])
        let reranked = projectAndRerank(thread: thread, match: match, document: document)

        XCTAssertTrue(reranked.isEmpty)
    }

    func testUnrelatedOfferNotAttachedToCapabilityHit() throws {
        let (publicProfile, counterparty) = coderProfile()
        let catOffer = unrelatedCatOffer(profileID: publicProfile.id, nodeID: publicProfile.nodeID)
        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [catOffer])
        let document = capabilityDocument(
            profileID: publicProfile.id,
            counterpartyID: counterparty.id
        )
        let thread = makeProviderSearchThread()

        let retrievalCandidate = ExchangeRetrievalEngine.Candidate(
            document: document,
            fusedScore: 0.742,
            contributingSources: ["lexical"],
            bestRankBySource: ["lexical": 1]
        )

        let projected = projector.project(
            [retrievalCandidate],
            knownMatches: [match],
            thread: thread
        )

        XCTAssertEqual(projected.count, 1)
        XCTAssertTrue(projected[0].matchedOffers.isEmpty)
        XCTAssertFalse(projected[0].coarse.hasOffers)
    }

    func testEvaluateTargetKindCompatibilityUsesProfileFallback() {
        let (_, counterparty) = coderProfile()
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: makeProviderSearchThread())

        let compatible = engine.evaluateTargetKindCompatibilityForTests(
            counterparty: counterparty,
            matchedOffers: [],
            plan: plan,
            offerOverlap: 0,
            capabilityOverlap: 1,
            affinityOverlap: 0,
            queryTokenOverlap: 1
        )

        XCTAssertTrue(compatible)
    }
}
