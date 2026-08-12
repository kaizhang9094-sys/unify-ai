import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeCanonicalSelectionResolution")
struct ExchangeCanonicalSelectionResolutionTests {
    private typealias N = ExchangeRetrievalAccuracyFixtureBuilder.NodeID
    private typealias O = ExchangeRetrievalAccuracyFixtureBuilder.OfferID

    @Test("canonical best match beats raw object-lane top offer")
    func canonicalBeatsObjectLaneTop() {
        let thread = makeObjectLaneThread(canonicalOfferID: O.toyotaCamry)
        let rawObjectLaneTop = makeMatch(
            offerID: O.multiCar,
            provenObjectOfferIDs: [O.multiCar],
            objectEvidence: [O.multiCar: 0.95]
        )
        let canonicalMatch = makeMatch(
            offerID: O.toyotaCamry,
            provenObjectOfferIDs: [O.toyotaCamry],
            objectEvidence: [O.toyotaCamry: 0.72]
        )

        let resolved = ExchangeCanonicalSelectionResolution.resolve(
            anchors: ExchangeCanonicalSelectionResolution.anchors(from: thread, allowChildCoordinationAnchor: false),
            thread: thread,
            matches: [rawObjectLaneTop, canonicalMatch],
            location: "test.canonicalBeatsObjectLaneTop",
            logResolution: false
        )

        #expect(resolved.source == .canonicalBestMatch)
        #expect(resolved.selectedOfferID == O.toyotaCamry)
    }

    @Test("Retrieval E2E resolver uses canonical discovery selection on umbrella response")
    func retrievalE2EResolverUsesCanonical() {
        let thread = makeObjectLaneThread(selectedOfferID: nil)
        let response = makeResponse(
            thread: thread,
            canonicalOfferID: O.toyotaCamry,
            matches: [
                makeMatch(
                    offerID: O.multiCar,
                    provenObjectOfferIDs: [O.multiCar],
                    objectEvidence: [O.multiCar: 0.99]
                )
            ]
        )

        let resolved = ExchangeCanonicalSelectionResolution.resolve(
            anchors: ExchangeCanonicalSelectionResolution.anchors(from: response),
            thread: thread,
            matches: response.matches,
            location: "test.retrievalE2E",
            logResolution: false
        )

        #expect(resolved.source == .canonicalBestMatch)
        #expect(resolved.selectedOfferID == O.toyotaCamry)
    }

    @Test("UI card resolver uses canonical selected offer from thread detail")
    func uiCardResolverUsesCanonical() {
        let thread = makeObjectLaneThread(selectedOfferID: nil, canonicalOfferID: O.toyotaCamry)
        let detail = makeDetail(
            thread: thread,
            matches: [
                makeMatch(
                    offerID: O.multiCar,
                    provenObjectOfferIDs: [O.multiCar],
                    objectEvidence: [O.multiCar: 0.99]
                )
            ]
        )

        let resolved = ExchangeCanonicalSelectionResolution.resolve(
            anchors: ExchangeCanonicalSelectionResolution.anchors(from: detail, allowChildCoordinationAnchor: true),
            thread: detail.thread,
            matches: detail.matches,
            location: "test.uiCard",
            logResolution: false
        )

        #expect(resolved.source == .canonicalBestMatch)
        #expect(resolved.selectedOfferID == O.toyotaCamry)
    }

    @Test("legacy object-lane fallback only when canonical anchor is absent")
    func legacyObjectLaneOnlyWithoutCanonical() {
        let thread = makeObjectLaneThread(selectedOfferID: nil, canonicalOfferID: nil)
        let rawTop = makeMatch(
            offerID: O.multiCar,
            provenObjectOfferIDs: [O.multiCar],
            objectEvidence: [O.multiCar: 0.88]
        )

        let resolved = ExchangeCanonicalSelectionResolution.resolve(
            anchors: ExchangeCanonicalSelectionResolution.anchors(from: thread, allowChildCoordinationAnchor: false),
            thread: thread,
            matches: [rawTop],
            location: "test.legacyObjectLane",
            logResolution: false
        )

        #expect(resolved.source == .legacyObjectLane)
        #expect(resolved.selectedOfferID == O.multiCar)
    }

    @Test("handoff selected offer wins over canonical metadata")
    func handoffWinsOverCanonical() {
        let thread = makeObjectLaneThread(selectedOfferID: nil, canonicalOfferID: O.toyotaCamry)
        let response = makeResponse(
            thread: thread,
            handoffOfferID: O.dellLaptop,
            canonicalOfferID: O.toyotaCamry,
            matches: []
        )

        let resolved = ExchangeCanonicalSelectionResolution.resolve(
            anchors: ExchangeCanonicalSelectionResolution.anchors(from: response),
            thread: thread,
            matches: response.matches,
            location: "test.handoffPriority",
            logResolution: false
        )

        #expect(resolved.source == .handoff)
        #expect(resolved.selectedOfferID == O.dellLaptop)
    }

    @Test("thread detail selectedOfferID surfaces canonical when thread anchor is nil")
    func threadDetailSelectedOfferIDIncludesCanonical() {
        let thread = makeObjectLaneThread(selectedOfferID: nil, canonicalOfferID: O.toyotaCamry)
        let detail = makeDetail(thread: thread, matches: [])

        #expect(detail.selectedOfferID == O.toyotaCamry)
        #expect(detail.canonicalDiscoverySelectedOfferID == O.toyotaCamry)
    }

    private func makeObjectLaneThread(
        selectedOfferID: String? = nil,
        canonicalOfferID: String? = nil
    ) -> ExchangeThread {
        var metadata: [String: String] = [:]
        if let canonicalOfferID {
            ExchangeThreadCanonicalDiscoverySelectionMetadata.apply(
                ExchangeCanonicalDiscoverySelectionSnapshot(
                    offerID: canonicalOfferID,
                    source: ExchangeOrchestrator.CanonicalDiscoverySelection.Source.bestMatch.rawValue
                ),
                to: &metadata
            )
        }
        var facets = ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer
        )
        facets.searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .product,
            objectType: "car",
            transactionIntent: .buy,
            rawUserText: "find me a car",
            canonicalEnglishSearchText: "find me a car"
        )
        var thread = ExchangeThread(
            id: UUID(),
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer,
                title: "search",
                objective: "search"
            ),
            posture: .cautious,
            facets: facets,
            state: .searching(.init()),
            metadata: metadata
        )
        thread.selectedOfferID = selectedOfferID
        return thread
    }

    private func makeMatch(
        offerID: String,
        provenObjectOfferIDs: [String] = [],
        objectEvidence: [String: Double] = [:],
        status: ExchangeMatch.Status = .candidate
    ) -> ExchangeMatch {
        ExchangeMatch(
            id: UUID(),
            threadID: UUID(),
            counterpartyID: N.carSeller,
            offerID: offerID,
            matchedOfferIDs: [offerID],
            provenObjectOfferIDs: provenObjectOfferIDs,
            objectEvidenceScoreByOfferID: objectEvidence,
            status: status,
            strength: .strong,
            score: 0.8,
            recommendation: "match"
        )
    }

    private func makeResponse(
        thread: ExchangeThread,
        handoffOfferID: String? = nil,
        canonicalOfferID: String? = nil,
        matches: [ExchangeMatch]
    ) -> ExchangeOrchestrator.Response {
        ExchangeOrchestrator.Response(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: matches,
            counterparties: [],
            artifacts: [],
            summary: "found",
            handoff: .init(selectedOfferID: handoffOfferID),
            canonicalDiscoverySelection: canonicalOfferID.map {
                ExchangeOrchestrator.CanonicalDiscoverySelection(
                    offerID: $0,
                    source: .bestMatch
                )
            }
        )
    }

    private func makeDetail(
        thread: ExchangeThread,
        matches: [ExchangeMatch]
    ) -> ExchangeModels.ThreadDetail {
        ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: matches,
            counterparties: [],
            artifacts: [],
            summary: "found"
        )
    }
}
