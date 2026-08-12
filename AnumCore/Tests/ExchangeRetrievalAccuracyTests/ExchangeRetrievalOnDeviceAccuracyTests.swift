import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeRetrievalAccuracy")
struct ExchangeRetrievalAccuracyTests {
    @Test("scenario catalog has 20 entries")
    func scenarioCount() {
        #expect(ExchangeRetrievalAccuracyScenarios.all.count == 20)
    }

    @Test("aggregate accuracy report")
    func aggregateAccuracyReport() async throws {
        let harness = ExchangeRetrievalAccuracyHarness.make()
        var results: [ExchangeRetrievalAccuracyScenarioResult] = []
        var expectations: [ExchangeRetrievalAccuracyScenarioExpectation] = []

        for (thread, expectation) in ExchangeRetrievalAccuracyScenarios.all {
            let result = try await harness.run(thread: thread, expectation: expectation)
            results.append(result)
            expectations.append(expectation)
            if !result.passed {
                Issue.record("[\(expectation.id)] \(result.failureReason ?? "unknown failure")")
            }
        }

        let metrics = ExchangeRetrievalAccuracyReport.aggregate(expectations: expectations, results: results)
        ExchangeRetrievalAccuracyReport.printReport(results: results, metrics: metrics)

        #expect(metrics.forbiddenAttachmentViolations == 0)

        for result in results where !result.passed {
            Issue.record("Scenario \(result.scenarioID) failed: \(result.failureReason ?? "")")
        }
    }

    @Test("object lane computer query")
    func objectLaneComputer() async throws {
        let harness = ExchangeRetrievalAccuracyHarness.make()
        let (thread, expectation) = ExchangeRetrievalAccuracyScenarios.all[0]
        let result = try await harness.run(thread: thread, expectation: expectation)
        #expect(result.objectLaneActive)
        #expect(result.passed || result.failureReason?.contains("selectedOfferID") == true)
    }

    @Test("capability profile slices never prove object evidence")
    func profileSlicesNeverProveObject() {
        let catalog = ExchangeRetrievalAccuracyFixtureBuilder.buildCatalog()
        for match in catalog {
            for doc in match.retrievalDocuments where doc.docKind?.isProfileKind == true {
                #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(doc))
            }
        }
    }

    @Test("non-object offer slices never prove object evidence")
    func nonObjectOfferSlicesNeverProveObject() {
        let forbidden: Set<ExchangeRetrievalDocument.DocKind> = [.offerDetail, .offerFAQ, .offerPackage]
        let catalog = ExchangeRetrievalAccuracyFixtureBuilder.buildCatalog()
        for match in catalog {
            for doc in match.retrievalDocuments {
                if let kind = doc.docKind, forbidden.contains(kind) {
                    #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(doc))
                }
            }
        }
    }

    @Test("scenario 10 capability outranks about on coder node")
    func capabilityOutranksAboutOnCoder() async throws {
        let harness = ExchangeRetrievalAccuracyHarness.make()
        let (thread, expectation) = ExchangeRetrievalAccuracyScenarios.all[9]
        let result = try await harness.run(thread: thread, expectation: expectation)
        #expect(result.passed)
        let trace = ExchangeRetrievalDebugTrace.capturedRows().filter { $0.counterpartyID == ExchangeRetrievalAccuracyFixtureBuilder.NodeID.coder }
        let capScore = trace.first { $0.docKind == ExchangeRetrievalDocument.DocKind.profileCapability.rawValue }?.finalScore
        let aboutScore = trace.first { $0.docKind == ExchangeRetrievalDocument.DocKind.profileAbout.rawValue }?.finalScore
        if let capScore, let aboutScore, capScore < aboutScore {
            let assessment = ExchangeRetrievalAccuracyReport.observationalAssessment(
                expectation: expectation,
                result: result,
                rankingTrace: trace
            )
            #expect(assessment.missRecords.contains {
                $0.classification == ObservationalMissClassification.docKindOrderingIssue
            })
        }
    }
}

private extension ExchangeRetrievalDocument.DocKind {
    var isProfileKind: Bool {
        switch self {
        case .profileIntro, .profileAbout, .profileCapability, .profileSeeking, .profileAffinity: return true
        default: return false
        }
    }
}
