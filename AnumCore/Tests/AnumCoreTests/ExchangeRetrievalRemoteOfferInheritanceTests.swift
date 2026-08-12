import Foundation
import XCTest

@testable import AnumCore

/// Ensures capability/profile retrieval rows inherit parent-match offers using generic token/region overlap (no fixture-specific strings).
final class ExchangeRetrievalRemoteOfferInheritanceTests: XCTestCase {

    func testCapabilityHitInheritsOfferWhenProviderTermsOverlapOfferTags() throws {
        let profileID = "profile-generic-01"
        let counterpartyID = "cp-generic-01"

        let publicProfile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: "node-generic-01",
            counterpartyID: counterpartyID,
            displayName: "Generic Fixture Vendor",
            visibility: .discoverable,
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            )
        )

        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            kind: .business,
            displayName: "Generic Fixture Vendor",
            source: .relayNetwork,
            publicProfile: publicProfile
        )

        let matchingOffer = ExchangeOffer(
            id: "offer-matching-generic",
            nodeID: "node-generic-01",
            publicProfileID: profileID,
            title: "On-site calibration",
            summary: nil,
            category: "instrumentation",
            tags: ["widget", "calibration"],
            regionTags: [],
            status: .active,
            visibility: .publicDiscoverable
        )

        let noiseOffer = ExchangeOffer(
            id: "offer-noise-generic",
            nodeID: "node-generic-01",
            publicProfileID: profileID,
            title: "Unrelated catering",
            tags: ["catering"],
            regionTags: [],
            status: .active,
            visibility: .publicDiscoverable
        )

        let match = ExchangeDirectoryMatch.fromCounterparty(
            counterparty,
            offers: [noiseOffer, matchingOffer]
        )

        let capabilityDoc = ExchangeRetrievalDocument(
            id: "doc-cap-generic-01",
            counterpartyID: counterpartyID,
            publicProfileID: profileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileCapability,
            sourceKind: .remote,
            title: "Field widget support",
            summary: "Repairs and calibration for industrial widgets",
            category: "services",
            tags: ["widget", "field"],
            regionTags: [],
            lexicalText: "widget calibration industrial field service",
            semanticText: "",
            providerTerms: ["widget"],
            capabilityTerms: ["calibration"]
        )

        let retrievalCandidate = ExchangeRetrievalEngine.Candidate(
            document: capabilityDoc,
            fusedScore: 0.91,
            contributingSources: ["lexical"],
            bestRankBySource: ["lexical": 1]
        )

        let facets = ExchangeIntentFacets(
            targetKind: .provider,
            fulfillmentMode: .localPreferred,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            providerTerms: ["widget", "calibration"],
            regionTerms: []
        )

        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .providerSearch,
                surfacePreference: .offer,
                title: "Find vendor",
                objective: "Need widget calibration for a production line"
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [retrievalCandidate],
            knownMatches: [match],
            thread: thread
        )

        XCTAssertEqual(projected.count, 1)
        let row = projected[0]
        XCTAssertEqual(row.matchedOffers.count, 1)
        XCTAssertEqual(row.matchedOffers.first?.id, matchingOffer.id)
        XCTAssertTrue(row.coarse.hasOffers)
        XCTAssertTrue(row.coarse.kindCompatible)
    }

    func testCapabilityHitInheritsOfferWhenRegionAliasOverlapsQueryRegion() throws {
        let profileID = "profile-generic-02"
        let counterpartyID = "cp-generic-02"

        let publicProfile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: "node-generic-02",
            counterpartyID: counterpartyID,
            displayName: "Regional Fixture Vendor",
            visibility: .discoverable,
            regionTags: [],
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                disclosureCeiling: .balanced
            )
        )

        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            kind: .business,
            displayName: "Regional Fixture Vendor",
            source: .relayNetwork,
            publicProfile: publicProfile
        )

        let offer = ExchangeOffer(
            id: "offer-region-bridge-generic",
            nodeID: "node-generic-02",
            publicProfileID: profileID,
            title: "Metro north on-site support",
            tags: ["support"],
            regionTags: [],
            regionAliases: ["northridge metro corridor"],
            status: .active,
            visibility: .publicDiscoverable
        )

        let match = ExchangeDirectoryMatch.fromCounterparty(counterparty, offers: [offer])

        let capabilityDoc = ExchangeRetrievalDocument(
            id: "doc-cap-generic-02",
            counterpartyID: counterpartyID,
            publicProfileID: profileID,
            offerID: nil,
            entityType: .publicProfile,
            surfaceType: .publicProfileCapability,
            sourceKind: .remote,
            title: "Regional dispatch",
            tags: ["dispatch"],
            regionTags: ["northridge"],
            lexicalText: "dispatch northridge corridor",
            semanticText: "",
            providerTerms: ["dispatch"],
            capabilityTerms: ["corridor"]
        )

        let facets = ExchangeIntentFacets(
            targetKind: .provider,
            fulfillmentMode: .localOnly,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            providerTerms: ["dispatch"],
            regionTerms: ["Northridge Metro"],
            explicitRegionRequired: true
        )

        let thread = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .providerSearch,
                surfacePreference: .offer,
                title: "Find help",
                objective: "Dispatch support in Northridge Metro"
            ),
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )

        let projected = ExchangeRetrievalCandidateProjector().project(
            [
                ExchangeRetrievalEngine.Candidate(
                    document: capabilityDoc,
                    fusedScore: 0.88,
                    contributingSources: ["lexical"],
                    bestRankBySource: ["lexical": 1]
                )
            ],
            knownMatches: [match],
            thread: thread
        )

        XCTAssertEqual(projected.count, 1)
        let row = projected[0]
        XCTAssertEqual(row.matchedOffers.count, 1)
        XCTAssertEqual(row.matchedOffers.first?.id, offer.id)
        XCTAssertTrue(row.coarse.placeCompatible)
    }
}
