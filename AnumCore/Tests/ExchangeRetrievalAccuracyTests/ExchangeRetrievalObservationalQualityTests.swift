import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeRetrievalObservationalQuality")
struct ExchangeRetrievalObservationalQualityTests {
    private typealias N = ExchangeRetrievalAccuracyFixtureBuilder.NodeID

    @Test("top1AnyRequiredDoesNotCountAsMiss")
    func top1AnyRequiredDoesNotCountAsMiss() {
        let expectation = ExchangeRetrievalAccuracyScenarioExpectation(
            id: "test.any-required-top1",
            queryLabel: "test",
            expectedSummary: "A primary, B acceptable",
            objectLaneActive: false,
            requiredInTopK: [N.computerSeller, N.multiSeller],
            category: .objectLane,
            primaryExpectedNodeID: N.computerSeller,
            acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller]
        )
        let result = makeResult(topNodes: [N.multiSeller, N.computerSeller])

        let assessment = ExchangeRetrievalAccuracyReport.observationalAssessment(
            expectation: expectation,
            result: result
        )

        #expect(!assessment.top1PrimaryHit)
        #expect(assessment.top1AnyRequiredHit)
        #expect(assessment.missRecords.contains {
            $0.classification == ObservationalMissClassification.validAlternateRequiredNode
        })
        #expect(!assessment.missRecords.contains {
            $0.classification == ObservationalMissClassification.trueTopKMiss
        })
        let issues = ExchangeRetrievalAccuracyReport.observationalIssues(
            expectation: expectation,
            result: result
        )
        #expect(!issues.contains { $0.hasPrefix("top1 miss:") })
    }

    @Test("equivalentSiblingProviderClassification")
    func equivalentSiblingProviderClassification() {
        let expectation = ExchangeRetrievalAccuracyScenarioExpectation(
            id: "test.equivalent-computer-providers",
            queryLabel: "laptop",
            expectedSummary: "computer providers interchangeable at top1",
            objectLaneActive: true,
            requiredInTopK: [N.computerSeller],
            category: .objectLane,
            primaryExpectedNodeID: N.computerSeller,
            acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller],
            equivalentResultGroupName: "valid computer providers"
        )
        let result = makeResult(topNodes: [N.multiSeller, N.computerSeller])

        let assessment = ExchangeRetrievalAccuracyReport.observationalAssessment(
            expectation: expectation,
            result: result
        )

        #expect(assessment.missRecords.contains {
            $0.classification == ObservationalMissClassification.equivalentSiblingProvider
        })
    }

    @Test("strictSafetyUnaffectedByObservationChanges")
    func strictSafetyUnaffectedByObservationChanges() {
        let expectation = ExchangeRetrievalAccuracyScenarioExpectation(
            id: "test.forbidden-attachment",
            queryLabel: "computer",
            expectedSummary: "forbidden attachment still strict fail",
            objectLaneActive: true,
            requiredInTopK: [N.computerSeller, N.multiSeller],
            forbiddenAttachments: [(N.carSeller, ExchangeRetrievalAccuracyFixtureBuilder.OfferID.toyotaCamry)],
            category: .objectLane,
            primaryExpectedNodeID: N.computerSeller,
            acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller],
            equivalentResultGroupName: "valid computer providers"
        )
        let result = makeResult(
            topNodes: [N.computerSeller],
            matchedOffers: [N.computerSeller: [], N.carSeller: [ExchangeRetrievalAccuracyFixtureBuilder.OfferID.toyotaCamry]]
        )

        let strictFailures = ExchangeRetrievalAccuracyReport.strictInvariantFailures(
            expectation: expectation,
            result: result
        )
        let assessment = ExchangeRetrievalAccuracyReport.observationalAssessment(
            expectation: expectation,
            result: result
        )

        #expect(!strictFailures.isEmpty)
        #expect(assessment.missRecords.contains {
            $0.classification == ObservationalMissClassification.safetyViolation
        })
        #expect(assessment.top1AnyRequiredHit)
    }

    @Test("localFederationAggregateUsesAnyRequiredMetric")
    func localFederationAggregateUsesAnyRequiredMetric() {
        let expectation = ExchangeRetrievalAccuracyScenarioExpectation(
            id: "test.aggregate",
            queryLabel: "test",
            expectedSummary: "aggregate separates primary vs acceptable top1",
            objectLaneActive: false,
            requiredInTopK: [N.computerSeller, N.multiSeller],
            category: .objectLane,
            primaryExpectedNodeID: N.computerSeller,
            acceptableTop1NodeIDs: [N.computerSeller, N.multiSeller]
        )

        let primaryHit = makeRun(
            expectation: expectation,
            topNodes: [N.computerSeller, N.multiSeller],
            batchID: 1,
            runID: 1
        )
        let alternateHit = makeRun(
            expectation: expectation,
            topNodes: [N.multiSeller, N.computerSeller],
            batchID: 1,
            runID: 2
        )

        let aggregate = ExchangeRetrievalLocalFederationSmokeReport.makeAggregate(
            runs: [primaryHit, alternateHit],
            expectations: [expectation, expectation],
            publishGenerationID: "test-gen"
        )

        #expect(aggregate.runs == 2)
        #expect(aggregate.top1Primary == 0.5)
        #expect(aggregate.top1AnyRequired == 1.0)
        #expect(aggregate.validAlternateTop1 == 1)
    }

    private func makeResult(
        topNodes: [String],
        matchedOffers: [String: [String]] = [:],
        objectLaneActive: Bool = false,
        selectedOfferID: String? = nil,
        provenObjectOfferIDs: [String] = []
    ) -> ExchangeRetrievalAccuracyScenarioResult {
        let summaries = topNodes.enumerated().map { index, nodeID in
            "#\(index + 1) node=\(nodeID) offers=[] docKind=unknown score=0.500"
        }
        return ExchangeRetrievalAccuracyScenarioResult(
            scenarioID: "synthetic",
            queryLabel: "synthetic",
            passed: true,
            expectedSummary: "synthetic",
            failureReason: nil,
            actualTopSummaries: summaries,
            selectedOfferID: selectedOfferID,
            matchedOffersByNode: matchedOffers,
            objectLaneActive: objectLaneActive,
            provenObjectOfferIDs: provenObjectOfferIDs,
            topDocKinds: [],
            topObjectEvidenceScores: [:],
            queryContext: nil,
            directoryRecall: nil
        )
    }

    private func makeRun(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation,
        topNodes: [String],
        batchID: Int,
        runID: Int
    ) -> LocalFederationSmokeRunResult {
        let result = makeResult(topNodes: topNodes)
        let assessment = ExchangeRetrievalAccuracyReport.observationalAssessment(
            expectation: expectation,
            result: result
        )
        return LocalFederationSmokeRunResult(
            batchID: batchID,
            runID: runID,
            scenarioID: expectation.id,
            repeatIndex: 0,
            strictPassed: true,
            strictFailures: [],
            serverRoundTrip: LocalFederationServerRoundTripAudit(
                responseMode: "clientRerank",
                serverRetrievalDocumentsCount: 1,
                serverRetrievalHitsCount: 1,
                docKindCounts: [:],
                embeddingCountsByDocKind: [:],
                candidateOfferIDsFromDocs: [],
                issues: []
            ),
            accuracyResult: result,
            latencyMs: 10,
            observationalIssues: [],
            observationalAssessment: assessment
        )
    }
}
