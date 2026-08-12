import Foundation
import XCTest

@testable import AnumCore

final class ExchangeOfferObjectEvidenceGateTests: XCTestCase {

    private let gate = ExchangeOfferObjectEvidenceGate.self
    private let projector = ExchangeRetrievalCandidateProjector()
    private let engine = ExchangeDiscoveryEngine()
    private let fitEngine = ExchangeFitEngine()
    private lazy var discoveryService = ExchangeDiscoveryService(
        discoveryEngine: engine,
        fitEngine: fitEngine
    )

    private func carOffer(
        id: String = "offer-car-01",
        nodeID: String = "node-seller-01",
        profileID: String = "profile-seller-01"
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: id,
            nodeID: nodeID,
            publicProfileID: profileID,
            title: "Selling my car",
            summary: "Available now in Aurora",
            category: "vehicle",
            tags: ["car", "selling", "available"],
            regionTags: ["aurora"],
            status: .active,
            visibility: .publicDiscoverable
        )
    }

    private func computerOffer(
        id: String = "offer-computer-01",
        nodeID: String = "node-seller-01",
        profileID: String = "profile-seller-01"
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: id,
            nodeID: nodeID,
            publicProfileID: profileID,
            title: "Refurbished laptop computer",
            summary: "Electronics deal",
            category: "electronics",
            tags: ["computer", "laptop", "electronics"],
            regionTags: ["aurora"],
            status: .active,
            visibility: .publicDiscoverable
        )
    }

    private func purchaseThread(
        objectType: String,
        objective: String,
        transactionIntent: ExchangeIntentFacets.TransactionIntent = .buy,
        queryIntentClass: ExchangeIntent.QueryIntentClass = .offerSearch,
        domainCategory: ExchangeIntentFacets.DomainCategory = .product,
        providerTerms: [String]? = nil,
        regionTerms: [String] = []
    ) -> ExchangeThread {
        let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: domainCategory,
            objectType: objectType,
            transactionIntent: transactionIntent,
            semanticConcepts: [objectType],
            rawUserText: objective
        )

        let facets = ExchangeIntentFacets(
            searchIntent: searchIntent,
            targetKind: .provider,
            fulfillmentMode: .localPreferred,
            queryIntentClass: queryIntentClass,
            surfacePreference: .offer,
            providerTerms: providerTerms ?? [objectType],
            regionTerms: regionTerms
        )

        return ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: queryIntentClass,
                surfacePreference: .offer,
                title: "Purchase request",
                objective: objective,
                targetDescription: objectType
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )
    }

    private func coderProfileThread() -> ExchangeThread {
        let facets = ExchangeIntentFacets(
            targetKind: .provider,
            fulfillmentMode: .localPreferred,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            providerTerms: ["coder"],
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
                objective: "Find a coder near me",
                targetDescription: "coder"
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )
    }

    private func coderProfile() -> (ExchangePublicNodeProfile, ExchangeCounterparty) {
        let profileID = "profile-coder-01"
        let counterpartyID = "cp-coder-01"
        let publicProfile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: "node-coder-01",
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
            lexicalText: "coder coding vibe coder",
            semanticText: "coder coding",
            providerTerms: ["coder"],
            capabilityTerms: ["coder", "coding"]
        )
    }

    private func projectAndRerank(
        thread: ExchangeThread,
        match: ExchangeDirectoryMatch,
        document: ExchangeRetrievalDocument
    ) -> [ExchangeDiscoveryEngine.DiscoveryCandidate] {
        let retrievalCandidate = ExchangeRetrievalEngine.Candidate(
            document: document,
            fusedScore: 0.742,
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

    func testComputerQueryRejectsCarOffer() {
        let thread = purchaseThread(objectType: "computer", objective: "I want to buy a computer")
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)
        XCTAssertTrue(gate.requiresOfferObjectEvidence(thread: thread, plan: plan))

        let queryPhrases = gate.queryObjectPhrases(thread: thread, plan: plan)
        XCTAssertTrue(queryPhrases.map { $0.lowercased() }.contains("computer"))

        if case .reject(let reason, _) = gate.evaluate(queryPhrases: queryPhrases, offer: carOffer()) {
            XCTAssertEqual(reason, "missing_offer_owned_object_evidence")
        } else {
            XCTFail("Expected car offer rejection for computer query")
        }
    }

    func testCarQueryAcceptsCarOffer() {
        let thread = purchaseThread(objectType: "car", objective: "I want to buy a car")
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)
        let queryPhrases = gate.queryObjectPhrases(thread: thread, plan: plan)

        if case .keep = gate.evaluate(queryPhrases: queryPhrases, offer: carOffer()) {
        } else {
            XCTFail("Expected car offer to match car query")
        }
    }

    func testLaptopQueryAcceptsComputerOffer() {
        let thread = purchaseThread(objectType: "laptop", objective: "I want to buy a laptop")
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)
        let queryPhrases = gate.queryObjectPhrases(thread: thread, plan: plan)

        if case .keep = gate.evaluate(queryPhrases: queryPhrases, offer: computerOffer()) {
        } else {
            XCTFail("Expected computer/electronics offer to match laptop query")
        }
    }

    func testBroadCommercialOverlapOnlyIsRejected() {
        let thread = purchaseThread(
            objectType: "computer",
            objective: "I want to buy a computer",
            regionTerms: ["aurora"]
        )
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)
        let queryPhrases = gate.queryObjectPhrases(thread: thread, plan: plan)

        let noisyOffer = ExchangeOffer(
            id: "offer-noise",
            nodeID: "node-noise",
            title: "Selling available offer",
            summary: "Near me in Aurora",
            tags: ["selling", "available"],
            regionTags: ["aurora"],
            status: .active,
            visibility: .publicDiscoverable
        )

        if case .reject = gate.evaluate(queryPhrases: queryPhrases, offer: noisyOffer) {
        } else {
            XCTFail("Expected rejection when only broad commercial/region overlap exists")
        }
    }

    func testComputerQueryDoesNotAttachCarOfferFromOfferSurface() {
        let thread = purchaseThread(objectType: "computer", objective: "I want to buy a computer")
        let car = carOffer()
        let counterparty = ExchangeCounterparty(
            id: "cp-seller-01",
            kind: .provider,
            displayName: "Seller",
            source: .relayNetwork
        )
        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [car])
        let document = ExchangeRetrievalDocument(
            id: "offer::\(car.id)",
            counterpartyID: counterparty.id,
            publicProfileID: car.publicProfileID,
            offerID: car.id,
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            title: car.title,
            summary: car.summary,
            tags: car.tags,
            regionTags: car.regionTags,
            lexicalText: "Selling my car available aurora",
            semanticText: "car vehicle selling"
        )

        let projected = projector.project(
            [
                ExchangeRetrievalEngine.Candidate(
                    document: document,
                    fusedScore: 0.81,
                    contributingSources: ["lexical"],
                    bestRankBySource: ["lexical": 1]
                )
            ],
            knownMatches: [match],
            thread: thread
        )

        XCTAssertEqual(projected.count, 1)
        XCTAssertTrue(projected[0].matchedOffers.isEmpty)
    }

    private func auroraSellerProfile() -> (ExchangePublicNodeProfile, ExchangeCounterparty) {
        let profileID = "profile-seller-01"
        let counterpartyID = "cp-seller-01"
        let publicProfile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: "node-seller-01",
            counterpartyID: counterpartyID,
            displayName: "Aurora Seller",
            headline: "Local seller",
            summary: "Serving Aurora buyers",
            visibility: .discoverable,
            regionTags: ["aurora"],
            semantic: ExchangePublicNodeProfile.SemanticSurface(domains: ["retail"]),
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            )
        )

        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            kind: .provider,
            displayName: "Aurora Seller",
            source: .relayNetwork,
            publicProfile: publicProfile
        )

        return (publicProfile, counterparty)
    }

    func testRegionOnlyInheritanceDoesNotAttachUnrelatedOffer() {
        let thread = purchaseThread(
            objectType: "computer",
            objective: "I want to buy a computer",
            regionTerms: ["aurora"]
        )
        let (publicProfile, counterparty) = auroraSellerProfile()
        let car = carOffer(nodeID: publicProfile.nodeID, profileID: publicProfile.id)
        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [car])
        let document = ExchangeRetrievalDocument(
            id: "profile-capability::\(publicProfile.id)",
            counterpartyID: counterparty.id,
            publicProfileID: publicProfile.id,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfile,
            sourceKind: .remote,
            title: publicProfile.displayName ?? "Aurora Seller",
            summary: publicProfile.summary,
            tags: publicProfile.regionTags,
            regionTags: ["aurora"],
            lexicalText: "Aurora seller local retail",
            semanticText: "aurora seller"
        )

        let retrievalCandidate = ExchangeRetrievalEngine.Candidate(
            document: document,
            fusedScore: 0.71,
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
    }

    func testCoderProfileFallbackKeepsCapabilityWithoutOffer() {
        let thread = coderProfileThread()
        let (publicProfile, counterparty) = coderProfile()
        let car = carOffer(nodeID: publicProfile.nodeID, profileID: publicProfile.id)
        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [car])
        let document = capabilityDocument(
            profileID: publicProfile.id,
            counterpartyID: counterparty.id
        )

        let reranked = projectAndRerank(thread: thread, match: match, document: document)
        XCTAssertEqual(reranked.count, 1)
        let row = reranked[0]
        XCTAssertTrue(row.matchedOffers.isEmpty)
        XCTAssertTrue(row.coarse.kindCompatible)
        XCTAssertTrue(row.coarse.isRetrievable)
        XCTAssertGreaterThan(row.coarse.capabilityOverlap, 0)
    }

    func testIncompatibleOfferForcesWeakAndBlocksAdvance() {
        let thread = purchaseThread(objectType: "computer", objective: "I want to buy a computer")
        let car = carOffer()
        let counterparty = ExchangeCounterparty(
            id: "cp-seller-01",
            kind: .provider,
            displayName: "Seller",
            source: .relayNetwork
        )

        let candidate = ExchangeDiscoveryEngine.DiscoveryCandidate(
            publicProfile: nil,
            counterparty: counterparty,
            matchedOffers: [car],
            coarse: ExchangeDiscoveryEngine.CoarseSignal(
                queryTokenOverlap: 1,
                explicitTokenOverlap: 0,
                regionOverlap: 1,
                offerOverlap: 0,
                capabilityOverlap: 0,
                affinityOverlap: 0,
                hasPublicProfile: false,
                hasOffers: true,
                kindCompatible: true,
                placeCompatible: true,
                trustHintScore: 0.4,
                retrievalScore: 0.5,
                rationale: "test"
            ),
            posture: ExchangeDiscoveryEngine.ContactPosture(
                bucket: .contactable,
                preview: "direct",
                explicitOpenness: true,
                requiresIntroduction: false
            ),
            dominantSurface: .offer,
            overallScore: 0.62,
            provenance: .retrievalProjected,
            directoryEvidence: nil
        )

        let matches = fitEngine.evaluate(thread: thread, candidates: [candidate])
        XCTAssertEqual(matches.count, 1)
        let match = matches[0]
        XCTAssertEqual(match.strength, .weak)
        XCTAssertTrue(
            match.cautions.contains(where: {
                $0.kind == .offerMismatch &&
                $0.summary.contains("does not match the requested product")
            })
        )

        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)
        XCTAssertFalse(
            discoveryService.evaluateAdvanceabilityForTests(
                candidate: candidate,
                match: match,
                thread: thread,
                searchPlan: plan
            )
        )
    }

    func testCarQueryCanSelectCarOfferInProjection() {
        let thread = purchaseThread(objectType: "car", objective: "I want to buy a car")
        let car = carOffer()
        let counterparty = ExchangeCounterparty(
            id: "cp-seller-01",
            kind: .provider,
            displayName: "Seller",
            source: .relayNetwork
        )
        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [car])
        let document = ExchangeRetrievalDocument(
            id: "offer::\(car.id)",
            counterpartyID: counterparty.id,
            offerID: car.id,
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            title: car.title,
            tags: car.tags,
            lexicalText: "Selling my car",
            semanticText: "car vehicle"
        )

        let projected = projector.project(
            [
                ExchangeRetrievalEngine.Candidate(
                    document: document,
                    fusedScore: 0.81,
                    contributingSources: ["lexical"],
                    bestRankBySource: ["lexical": 1]
                )
            ],
            knownMatches: [match],
            thread: thread
        )

        XCTAssertEqual(projected.first?.matchedOffers.first?.id, car.id)
    }

    func testLaptopQuerySelectsComputerOffer() {
        let thread = purchaseThread(objectType: "laptop", objective: "I want to buy a laptop")
        let computer = computerOffer()
        let counterparty = ExchangeCounterparty(
            id: "cp-seller-01",
            kind: .provider,
            displayName: "Seller",
            source: .relayNetwork
        )
        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [computer])
        let document = ExchangeRetrievalDocument(
            id: "offer::\(computer.id)",
            counterpartyID: counterparty.id,
            offerID: computer.id,
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            title: computer.title,
            category: computer.category,
            tags: computer.tags,
            lexicalText: "Refurbished laptop computer electronics",
            semanticText: "computer laptop electronics"
        )

        let projected = projector.project(
            [
                ExchangeRetrievalEngine.Candidate(
                    document: document,
                    fusedScore: 0.79,
                    contributingSources: ["lexical"],
                    bestRankBySource: ["lexical": 1]
                )
            ],
            knownMatches: [match],
            thread: thread
        )

        XCTAssertEqual(projected.first?.matchedOffers.first?.id, computer.id)
    }

    func testMultiOfferSellerAttachesOnlyMatchingOffer() {
        let thread = purchaseThread(objectType: "computer", objective: "I want to buy a computer")
        let car = carOffer()
        let computer = computerOffer()
        let counterparty = ExchangeCounterparty(
            id: "cp-seller-01",
            kind: .provider,
            displayName: "Seller",
            source: .relayNetwork
        )
        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [car, computer])
        let document = ExchangeRetrievalDocument(
            id: "offer::\(computer.id)",
            counterpartyID: counterparty.id,
            offerID: computer.id,
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .remote,
            title: computer.title,
            category: computer.category,
            tags: computer.tags,
            lexicalText: "Refurbished laptop computer electronics",
            semanticText: "computer laptop electronics"
        )

        let projected = projector.project(
            [
                ExchangeRetrievalEngine.Candidate(
                    document: document,
                    fusedScore: 0.79,
                    contributingSources: ["lexical"],
                    bestRankBySource: ["lexical": 1]
                )
            ],
            knownMatches: [match],
            thread: thread
        )

        XCTAssertEqual(projected.first?.matchedOffers.count, 1)
        XCTAssertEqual(projected.first?.matchedOffers.first?.id, computer.id)
        XCTAssertFalse(projected.first?.matchedOffers.contains(where: { $0.id == car.id }) ?? true)
    }

}
