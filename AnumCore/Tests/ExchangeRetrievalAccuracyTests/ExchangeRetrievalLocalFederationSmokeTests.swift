import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeRetrievalLocalFederationSmoke")
struct ExchangeRetrievalLocalFederationSmokeTests {
    @Test("export ONNX fixture catalog when ANUM_EXPORT_RETRIEVAL_ACCURACY_CATALOG=1")
    func exportCatalogWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["ANUM_EXPORT_RETRIEVAL_ACCURACY_CATALOG"] == "1" else {
            print("[LocalFederationExport] skipped: set ANUM_EXPORT_RETRIEVAL_ACCURACY_CATALOG=1")
            return
        }

        let catalogPath = ProcessInfo.processInfo.environment["ANUM_CATALOG_EXPORT_PATH"]
            ?? "/tmp/anum-retrieval-accuracy-catalog.json"
        let manifestPath = ProcessInfo.processInfo.environment["ANUM_LOCAL_FED_SMOKE_GENERATION_FILE"]
            ?? "/tmp/anum-local-fed-smoke-generation.json"

        let manifest = try await ExchangeRetrievalAccuracyFederationCatalogExport.exportCatalogAndManifest(
            catalogURL: URL(fileURLWithPath: catalogPath),
            manifestURL: URL(fileURLWithPath: manifestPath)
        )
        print("[LocalFederationExport] wrote catalog nodes=\(manifest.expectedNodeIDs.count) docs=\(manifest.expectedDocIDs.count)")
        print("[LocalFederationExport] publishGenerationID=\(manifest.publishGenerationID)")
        #expect(!manifest.expectedNodeIDs.isEmpty)
        #expect(!manifest.expectedDocIDs.isEmpty)
    }

    @Test("opt-in local federation retrieval smoke audit")
    func localFederationRetrievalSmoke() async throws {
        guard ExchangeRetrievalLocalFederationSmokeGate.isEnabled else {
            print("[LocalFederationSmoke] skipped: set ANUM_RETRIEVAL_LOCAL_FEDERATION_SMOKE=1")
            print("  ./AnumCore/scripts/run-retrieval-local-federation-smoke.sh")
            return
        }

        let batchEntries = ExchangeRetrievalLocalFederationSmokeBatchPlan.activeEntries
        #expect(!batchEntries.isEmpty)

        let harness: ExchangeRetrievalLocalFederationHarness
        do {
            harness = try await ExchangeRetrievalLocalFederationHarness.make()
        } catch let skip as LocalFederationSmokeSkip {
            Issue.record("[LocalFederationSmoke] skipped: \(skip)")
            return
        }

        var expectations: [ExchangeRetrievalAccuracyScenarioExpectation] = []
        var runResults: [LocalFederationSmokeRunResult] = []

        for (index, entry) in batchEntries.enumerated() {
            guard let scenario = ExchangeRetrievalAccuracyScenarios.scenario(forID: entry.scenarioID) else {
                Issue.record("[LocalFederationSmoke] missing scenario \(entry.scenarioID)")
                continue
            }
            let (thread, expectation) = scenario
            expectations.append(expectation)

            if index > 0 {
                try await Task.sleep(nanoseconds: 250_000_000)
            }

            let runResult = try await harness.run(
                batchEntry: entry,
                thread: thread,
                expectation: expectation
            )
            runResults.append(runResult)

            ExchangeRetrievalLocalFederationSmokeReport.printRunReport(
                run: runResult,
                serverBaseURL: harness.baseURL.absoluteString,
                publishGenerationID: harness.manifest.publishGenerationID
            )
        }

        let aggregate = ExchangeRetrievalLocalFederationSmokeReport.makeAggregate(
            runs: runResults,
            expectations: expectations,
            publishGenerationID: harness.manifest.publishGenerationID
        )
        ExchangeRetrievalLocalFederationSmokeReport.printAggregateReport(aggregate: aggregate)

        for run in runResults where !run.strictPassed {
            Issue.record("[\(run.scenarioID)] strict failure: \(run.strictFailures.joined(separator: "; "))")
        }

        #expect(aggregate.strictPass == aggregate.runs)
        #expect(aggregate.forbiddenAttachmentViolations == 0)
        #expect(aggregate.objectLaneFP == 0)
        #expect(aggregate.objectLaneFN == 0)
        #expect(aggregate.embeddingMissing == 0)
        #expect(aggregate.serverResponseModeMismatch == 0)
    }
}
