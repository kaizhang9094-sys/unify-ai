import Foundation
import Testing
@testable import AnumCore

#if DEBUG

@Suite("ExchangeRetrievalE2EEvaluation")
struct ExchangeRetrievalE2EEvaluationTests {
    private typealias N = ExchangeRetrievalAccuracyFixtureBuilder.NodeID
    private typealias O = ExchangeRetrievalAccuracyFixtureBuilder.OfferID

    @Test("missing objectType fails object-lane case")
    func missingObjectTypeFails() {
        let scenario = ExchangeRetrievalE2EScenarios.mandatory.first { $0.queryText.contains("car") }!
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            objectType: nil,
            domainCategory: .product,
            transactionIntent: .buy
        )
        let result = ExchangeRetrievalE2EAuditSupport.evaluateForTests(
            scenario: scenario,
            thread: thread,
            searchIntent: thread.facets?.searchIntent,
            sortedMatches: [],
            counterparties: [],
            rankingTrace: [],
            ui: emptyUI(),
            selectedOfferID: nil,
            matchedOffersByNode: [:]
        )
        #expect(!result.passed)
        #expect(result.structuralFailures.contains { $0.contains("objectType expected=car actual=nil") })
    }

    @Test("wrong UI card offerID fails")
    func wrongUICardOfferIDFails() {
        let scenario = ExchangeRetrievalE2EScenarios.mandatory.first { $0.queryText.contains("car") }!
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            objectType: "car",
            domainCategory: .product,
            transactionIntent: .buy
        )
        let match = makeMatch(
            counterpartyID: N.carSeller,
            matchedOfferIDs: [O.toyotaCamry],
            provenObjectOfferIDs: [O.toyotaCamry]
        )
        let ui = AppSearchSmokeUIProjectionSnapshot(
            selectedOfferID: O.toyotaCamry,
            matchedOffersByNode: [N.carSeller: [O.toyotaCamry]],
            preferredMatchCounterpartyID: N.carSeller,
            preferredMatchOfferID: O.toyotaCamry,
            cardOfferID: O.dellLaptop,
            visiblePublicProfileID: nil,
            surfaceLead: "offerLed"
        )
        let result = ExchangeRetrievalE2EAuditSupport.evaluateForTests(
            scenario: scenario,
            thread: thread,
            searchIntent: thread.facets?.searchIntent,
            sortedMatches: [match],
            counterparties: [makeCounterparty(id: N.carSeller)],
            rankingTrace: [],
            ui: ui,
            selectedOfferID: O.toyotaCamry,
            matchedOffersByNode: [N.carSeller: [O.toyotaCamry]]
        )
        #expect(!result.passed)
        #expect(result.uiFailures.contains { $0.contains("uiCardOfferID mismatch expected=\(O.toyotaCamry)") })
    }

    @Test("missing requiredInTopK fails ranking evaluate")
    func missingRequiredInTopKFails() {
        let scenario = ExchangeRetrievalE2EScenarios.mandatory.first { $0.queryText.contains("car") }!
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            objectType: "car",
            domainCategory: .product,
            transactionIntent: .buy
        )
        let match = makeMatch(
            counterpartyID: N.computerSeller,
            matchedOfferIDs: [O.dellLaptop],
            provenObjectOfferIDs: [O.dellLaptop]
        )
        let result = ExchangeRetrievalE2EAuditSupport.evaluateForTests(
            scenario: scenario,
            thread: thread,
            searchIntent: thread.facets?.searchIntent,
            sortedMatches: [match],
            counterparties: [makeCounterparty(id: N.computerSeller)],
            rankingTrace: [],
            ui: emptyUI(),
            selectedOfferID: O.dellLaptop,
            matchedOffersByNode: [N.computerSeller: [O.dellLaptop]]
        )
        #expect(!result.passed)
        #expect(result.fullEvaluateApplied)
        #expect(result.rankingFailures.contains { $0.contains("required node \(N.carSeller) missing") })
    }

    @Test("FAQ detail object proof fails")
    func faqDetailObjectProofFails() {
        let scenario = ExchangeRetrievalE2EScenarios.mandatory.first { $0.queryText.contains("deliver") }!
        let thread = makeThread(
            queryIntentClass: .generalDiscovery,
            objectType: nil,
            domainCategory: .general,
            transactionIntent: .inquire
        )
        let rankingTrace = [
            ExchangeRetrievalDebugTrace.RankingRow(
                documentID: "faq-1",
                docKind: ExchangeRetrievalDocument.DocKind.offerFAQ.rawValue,
                surfaceType: "offer",
                counterpartyID: N.photographer,
                nodeID: N.photographer,
                publicProfileID: nil,
                offerID: O.weddingPhoto,
                bm25Rank: 1,
                vectorRank: 1,
                objectLaneRank: nil,
                bm25Score: 0.8,
                vectorScore: 0.8,
                objectLaneScore: 0.35,
                surfaceBias: 0,
                docKindBias: 0,
                finalScore: 0.8
            )
        ]
        let result = ExchangeRetrievalE2EAuditSupport.evaluateForTests(
            scenario: scenario,
            thread: thread,
            searchIntent: thread.facets?.searchIntent,
            sortedMatches: [],
            counterparties: [],
            rankingTrace: rankingTrace,
            ui: emptyUI(),
            selectedOfferID: nil,
            matchedOffersByNode: [:]
        )
        #expect(!result.passed)
        #expect(
            result.structuralFailures.contains { $0.contains("nonOfferObjectProof docKind=offer_faq offerID=\(O.weddingPhoto)") }
                || result.strictFailures.contains { $0.contains("non-offer_object docKind=offer_faq") }
        )
    }

    @Test("transient non-persistent still fails")
    func transientNonPersistentFails() {
        let evaluation = ExchangeRetrievalE2EEvaluation.buildTransientEvaluation(fallbackReason: "repairFailed")
        #expect(!evaluation.passed)
        #expect(evaluation.structuralFailures.contains("transientNonPersistent"))
        #expect(evaluation.allFailures.contains("fallbackReason=repairFailed"))
    }

    @Test("product plus buy forbidden on service cleaner scenario")
    func productBuyForbiddenOnCleanerScenario() {
        let scenario = ExchangeRetrievalE2EScenarios.mandatory.first { $0.queryText.contains("cleaner") }!
        let thread = makeThread(
            queryIntentClass: .providerSearch,
            objectType: "cleaner",
            domainCategory: .product,
            transactionIntent: .buy
        )
        let result = ExchangeRetrievalE2EAuditSupport.evaluateForTests(
            scenario: scenario,
            thread: thread,
            searchIntent: thread.facets?.searchIntent,
            sortedMatches: [],
            counterparties: [],
            rankingTrace: [],
            ui: emptyUI(),
            selectedOfferID: nil,
            matchedOffersByNode: [:]
        )
        #expect(!result.passed)
        #expect(result.structuralFailures.contains { $0.contains("domainCategory forbidden=product") })
        #expect(result.structuralFailures.contains { $0.contains("transactionIntent forbidden=buy") })
        #expect(result.structuralFailures.contains { $0.contains("product+buy canonical combination forbidden") })
    }
    @Test("duplicate multi-offer node counterparties do not crash ranking evaluate")
    func duplicateMultiOfferNodeCounterpartiesDoNotCrash() {
        let scenario = ExchangeRetrievalE2EScenarios.mandatory.first { $0.queryText.contains("computer") }!
        let thread = makeThread(
            queryIntentClass: .offerSearch,
            objectType: "computer",
            domainCategory: .product,
            transactionIntent: .buy
        )
        let computerMatch = makeMatch(
            counterpartyID: N.multiSeller,
            matchedOfferIDs: [O.multiComputer],
            provenObjectOfferIDs: [O.multiComputer],
            score: 0.95
        )
        let carMatch = makeMatch(
            counterpartyID: N.multiSeller,
            matchedOfferIDs: [O.multiCar],
            provenObjectOfferIDs: [],
            score: 0.70
        )
        let counterparty = makeCounterparty(id: N.multiSeller)
        let matchedOffersByNode = ExchangeDebugProjectionMerge.aggregateProjectedOffersByNode(from: [computerMatch, carMatch])

        let result = ExchangeRetrievalE2EAuditSupport.evaluateForTests(
            scenario: scenario,
            thread: thread,
            searchIntent: thread.facets?.searchIntent,
            sortedMatches: [computerMatch, carMatch],
            counterparties: [counterparty, counterparty],
            rankingTrace: [],
            ui: emptyUI(),
            selectedOfferID: O.multiComputer,
            matchedOffersByNode: matchedOffersByNode
        )

        #expect(result.fullEvaluateApplied)
        #expect(matchedOffersByNode[N.multiSeller] == [O.multiComputer])
        #expect(matchedOffersByNode[N.multiSeller]?.contains(O.multiCar) == false)
    }

}

private func makeThread(
    queryIntentClass: ExchangeIntent.QueryIntentClass,
    objectType: String?,
    domainCategory: ExchangeIntentFacets.DomainCategory,
    transactionIntent: ExchangeIntentFacets.TransactionIntent
) -> ExchangeThread {
    var canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        domainCategory: domainCategory,
        objectType: objectType,
        transactionIntent: transactionIntent,
        rawUserText: "test",
        canonicalEnglishSearchText: "test"
    )
    var facets = ExchangeIntentFacets(
        queryIntentClass: queryIntentClass,
        surfacePreference: .offer
    )
    facets.searchIntent = canonical
    return ExchangeThread(
        id: UUID(),
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: queryIntentClass,
            surfacePreference: .offer,
            title: "test",
            objective: "test"
        ),
        posture: .cautious,
        facets: facets,
        state: .searching(.init())
    )
}

private func makeMatch(
    counterpartyID: String,
    matchedOfferIDs: [String],
    provenObjectOfferIDs: [String],
    score: Double = 0.9
) -> ExchangeMatch {
    ExchangeMatch(
        id: UUID(),
        threadID: UUID(),
        counterpartyID: counterpartyID,
        matchedOfferIDs: matchedOfferIDs,
        provenObjectOfferIDs: provenObjectOfferIDs,
        objectEvidenceScoreByOfferID: Dictionary(
            uniqueKeysWithValues: provenObjectOfferIDs.map { ($0, 0.9) }
        ),
        status: .candidate,
        strength: .strong,
        score: score
    )
}

private func makeCounterparty(id: String) -> ExchangeCounterparty {
    ExchangeCounterparty(
        id: id,
        kind: .organization,
        displayName: id,
        source: .localDirectory
    )
}

private func emptyUI() -> AppSearchSmokeUIProjectionSnapshot {
    AppSearchSmokeUIProjectionSnapshot(
        selectedOfferID: nil,
        matchedOffersByNode: [:],
        preferredMatchCounterpartyID: nil,
        preferredMatchOfferID: nil,
        cardOfferID: nil,
        visiblePublicProfileID: nil,
        surfaceLead: "none"
    )
}

#endif
