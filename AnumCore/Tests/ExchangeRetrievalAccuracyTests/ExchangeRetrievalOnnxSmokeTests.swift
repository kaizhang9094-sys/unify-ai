import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeRetrievalOnnxSmoke")
struct ExchangeRetrievalOnnxSmokeTests {
    @Test("opt-in ONNX retrieval smoke with Tier A comparison")
    func onnxRetrievalSmoke() async throws {
        guard ExchangeRetrievalOnnxSmokeGate.isEnabled else {
            print("[ExchangeRetrievalOnnxSmoke] skipped: set ANUM_RETRIEVAL_ONNX_SMOKE=1 to run")
            print("  cd AnumCore && ANUM_RETRIEVAL_ONNX_SMOKE=1 swift test --filter ExchangeRetrievalOnnxSmokeTests")
            return
        }

        let scenarioIDs = ExchangeRetrievalAccuracyScenarios.onnxSmokeScenarioIDs()
        let scenarios = ExchangeRetrievalAccuracyScenarios.scenarios(forIDs: scenarioIDs)
        #expect(!scenarios.isEmpty)

        let tierAHarness = ExchangeRetrievalAccuracyHarness.make()
        let tierBHarness: ExchangeRetrievalAccuracyHarness
        do {
            tierBHarness = try await ExchangeRetrievalAccuracyHarness.makeONNX()
        } catch let skip as ExchangeRetrievalOnnxSmokeSkip {
            Issue.record("[ExchangeRetrievalOnnxSmoke] skipped: \(skip)")
            return
        }

        var tierAExpectations: [ExchangeRetrievalAccuracyScenarioExpectation] = []
        var tierAResults: [ExchangeRetrievalAccuracyScenarioResult] = []
        var tierBResults: [ExchangeRetrievalAccuracyScenarioResult] = []
        var tierARankingTraces: [String: [ExchangeRetrievalDebugTrace.RankingRow]] = [:]
        var tierBRankingTraces: [String: [ExchangeRetrievalDebugTrace.RankingRow]] = [:]
        var comparisonRows: [ExchangeRetrievalAccuracyReport.TierComparisonRow] = []

        for (index, (thread, expectation)) in scenarios.enumerated() {
            let tierAResult = try await tierAHarness.run(thread: thread, expectation: expectation)
            tierAExpectations.append(expectation)
            tierAResults.append(tierAResult)
            tierARankingTraces[expectation.id] = ExchangeRetrievalDebugTrace.capturedRows()

            if index > 0 {
                try await Task.sleep(nanoseconds: 250_000_000)
            }

            let tierBResult = try await tierBHarness.run(thread: thread, expectation: expectation)
            tierBResults.append(tierBResult)
            tierBRankingTraces[expectation.id] = ExchangeRetrievalDebugTrace.capturedRows()

            comparisonRows.append(
                ExchangeRetrievalAccuracyReport.makeTierComparisonRow(
                    expectation: expectation,
                    tierA: tierAResult,
                    tierB: tierBResult,
                    tierARankingTrace: tierARankingTraces[expectation.id] ?? [],
                    tierBRankingTrace: tierBRankingTraces[expectation.id] ?? []
                )
            )
        }

        let tierAStrict = ExchangeRetrievalAccuracyReport.strictAggregate(
            expectations: tierAExpectations,
            results: tierAResults,
            rankingTracesByScenarioID: tierARankingTraces
        )
        let tierBStrict = ExchangeRetrievalAccuracyReport.strictAggregate(
            expectations: tierAExpectations,
            results: tierBResults,
            rankingTracesByScenarioID: tierBRankingTraces
        )
        let tierAObs = ExchangeRetrievalAccuracyReport.aggregate(
            expectations: tierAExpectations,
            results: tierAResults
        )
        let tierBObs = ExchangeRetrievalAccuracyReport.aggregate(
            expectations: tierAExpectations,
            results: tierBResults
        )

        ExchangeRetrievalAccuracyReport.printTierComparisonReport(
            rows: comparisonRows,
            tierAMetrics: tierAStrict,
            tierBMetrics: tierBStrict,
            tierAObservational: tierAObs,
            tierBObservational: tierBObs
        )

        for row in comparisonRows where !row.tierBStrictPassed {
            Issue.record("[\(row.scenarioID)] strict invariant failure: \(row.tierBStrictFailures.joined(separator: "; "))")
        }

        #expect(tierBStrict.forbiddenAttachmentViolations == 0)
        #expect(tierBStrict.objectLaneFalsePositives == 0)
        #expect(tierBStrict.objectLaneFalseNegatives == 0)
        #expect(tierBStrict.strictPassCount == tierBStrict.totalScenarios)
    }
}
