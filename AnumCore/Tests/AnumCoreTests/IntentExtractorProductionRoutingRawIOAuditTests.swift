import Foundation
import XCTest

@testable import AnumCore

/// Production-routing raw I/O audit: wires ``AsyncLLMOpenEndedSearchIntentExtractor`` like app bootstrap
/// with a deterministic ``RecordingFixtureAsyncSearchIntentJSONProvider`` (no on-device Llama).
final class IntentExtractorProductionRoutingRawIOAuditTests: XCTestCase {

    func testProductionRoutingRawIOAuditArtifact() async throws {
        let diagnosticsStore = SearchIntentExtractionDiagnosticsStore()
        let fakeProvider = RecordingFixtureAsyncSearchIntentJSONProvider(
            jsonByFixtureID: IntentExtractorProductionRoutingFlatSummary.jsonByFixtureID
        )
        let asyncExtractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: fakeProvider,
            fallbackExtractor: CanonicalSearchIntentHeuristicExtractor(),
            diagnosticsStore: diagnosticsStore
        )
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: ExchangeFallbackIntelligenceProvider(),
            searchIntentExtractor: CanonicalSearchIntentHeuristicExtractor(),
            asyncSearchIntentExtractor: asyncExtractor
        )

        var lines: [Data] = []
        var strictFailureSummaries: [String] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        for fixture in IntentExtractorGoldenFixtures.all {
            await fakeProvider.prepareForFixture(id: fixture.id)
            await diagnosticsStore.reset()

            let interpretation = await interpreter.interpret(
                userText: fixture.inputText,
                threadContext: nil
            )
            let (intent, facets) = IntentExtractorGoldenEvaluation.extractIntentFacets(from: interpretation)
            let extractionDiag = await asyncExtractor.lastExtractionDiagnostics()
            let providerSnapshot = await fakeProvider.snapshot()

            let flexibleFailures = IntentExtractorGoldenEvaluation.evaluateFlexible(
                fixture: fixture,
                intent: intent,
                facets: facets
            )
            let goldenStrictFailures = IntentExtractorGoldenEvaluation.evaluateStrict(
                fixture: fixture,
                intent: intent,
                facets: facets
            )
            let productionStrictFailures = IntentExtractorGoldenEvaluation.evaluateProductionRoutingStrict(
                fixtureID: fixture.id,
                asyncFlatSummaryAttempted: providerSnapshot.wasCalled || (extractionDiag?.attemptedLLM == true),
                rawLLMOutputExact: providerSnapshot.rawLLMOutputExact,
                facets: facets,
                extractionDiagnostics: extractionDiag
            )

            let goldenFailedFields = Array(Set(flexibleFailures + goldenStrictFailures)).sorted()
            let failedFields = productionStrictFailures

            let extractionSource = facets?.searchIntent?.extractionSource?.rawValue
                ?? extractionDiag?.source.rawValue
            let fallbackUsed = extractionSource == SearchIntentExtractionSource.heuristicFallback.rawValue
                || extractionDiag?.source == .heuristicFallback
            let heuristicUsed = fallbackUsed
                || productionStrictFailures.contains(where: { $0.contains("heuristicFallback") })

            var notesParts: [String] = [
                "Harness: ExchangeFallbackIntelligenceProvider + AsyncLLMOpenEndedSearchIntentExtractor(RecordingFixtureAsyncSearchIntentJSONProvider).",
                "asyncFlatSummaryAttempted=\(providerSnapshot.wasCalled || (extractionDiag?.attemptedLLM == true)) providerCallCount=\(providerSnapshot.callCount)."
            ]
            if !providerSnapshot.wasCalled {
                notesParts.append(Self.explainMissingProviderCall(fixture: fixture, intent: intent))
            }
            if let extractionDiag {
                notesParts.append(
                    "diagnostics: attemptedLLM=\(extractionDiag.attemptedLLM) source=\(extractionDiag.source.rawValue) fallbackReason=\(extractionDiag.fallbackReason?.rawValue ?? "nil")."
                )
            }

            let row = IntentExtractorProductionRoutingRawIOAuditRow(
                fixtureId: fixture.id,
                language: IntentExtractorGoldenEvaluation.mapAuditLanguage(fixture.language),
                category: fixture.category,
                inputTextExact: fixture.inputText,
                asyncFlatSummaryAttempted: providerSnapshot.wasCalled || (extractionDiag?.attemptedLLM == true),
                promptSentToLLMExact: providerSnapshot.promptSentToLLMExact,
                rawLLMOutputExact: providerSnapshot.rawLLMOutputExact,
                parsedCanonicalSearchIntentFull: facets?.searchIntent,
                extractionSource: extractionSource,
                fallbackUsed: fallbackUsed,
                heuristicUsed: heuristicUsed,
                oldPassed: flexibleFailures.isEmpty,
                strictPass: productionStrictFailures.isEmpty,
                failedFields: failedFields,
                notes: notesParts.joined(separator: " ") + (goldenFailedFields.isEmpty ? "" : " goldenFailures=\(goldenFailedFields.joined(separator: ",")).")
            )

            if !productionStrictFailures.isEmpty {
                strictFailureSummaries.append("\(fixture.id): \(failedFields.joined(separator: ", "))")
            }
            lines.append(try encoder.encode(row))
        }

        let url = Self.productionRoutingAuditArtifactURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var combined = Data()
        for (idx, chunk) in lines.enumerated() {
            combined.append(chunk)
            if idx < lines.count - 1 { combined.append(Data("\n".utf8)) }
        }
        try combined.write(to: url, options: [.atomic])

        XCTAssertTrue(
            strictFailureSummaries.isEmpty,
            "Production-routing strict failures:\n" + strictFailureSummaries.joined(separator: "\n")
        )
    }

    private static var productionRoutingAuditArtifactURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("intent_extractor_production_routing_raw_io_audit.jsonl", isDirectory: false)
    }

    private static func explainMissingProviderCall(
        fixture: IntentExtractorGoldenFixture,
        intent: ExchangeIntent?
    ) -> String {
        var parts: [String] = ["Fake AsyncSearchIntentJSONProvider was not called."]
        if IntentExtractorProductionRoutingFlatSummary.flatSummaryJSON(for: fixture.id) == nil {
            parts.append("No fixture flat-summary JSON registered for this id.")
        }
        if let intent {
            parts.append("interpreted queryIntentClass=\(intent.queryIntentClass.rawValue) kind=\(intent.kind.rawValue).")
            switch intent.queryIntentClass {
            case .directOutreach, .followUp, .statusCheck:
                parts.append("shouldBuildCanonicalSearchIntent is false for this query class.")
            default:
                parts.append("If LLM-first returned early with actionable canonical, compileCanonicalSearchArtifactsAsync may not run (single provider call expected on LLM-first path only).")
            }
        } else {
            parts.append("interpret returned no draft intent (unexpected).")
        }
        return parts.joined(separator: " ")
    }
}

private struct IntentExtractorProductionRoutingRawIOAuditRow: Codable, Sendable {
    var fixtureId: String
    var language: String
    var category: String
    var inputTextExact: String
    var asyncFlatSummaryAttempted: Bool
    var promptSentToLLMExact: String?
    var rawLLMOutputExact: String?
    var parsedCanonicalSearchIntentFull: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    var extractionSource: String?
    var fallbackUsed: Bool
    var heuristicUsed: Bool
    var oldPassed: Bool
    var strictPass: Bool
    var failedFields: [String]
    var notes: String
}

/// Test double for ``AsyncSearchIntentJSONProvider`` used by production-routing audits.
final class RecordingFixtureAsyncSearchIntentJSONProvider: AsyncSearchIntentJSONProvider, @unchecked Sendable {
    struct Snapshot: Sendable {
        var wasCalled: Bool
        var callCount: Int
        var promptSentToLLMExact: String?
        var rawLLMOutputExact: String?
    }

    private let state: RecordingFixtureAsyncSearchIntentJSONProviderState
    private let jsonByFixtureID: [String: String]

    init(jsonByFixtureID: [String: String]) {
        self.jsonByFixtureID = jsonByFixtureID
        self.state = RecordingFixtureAsyncSearchIntentJSONProviderState()
    }

    func prepareForFixture(id: String) async {
        await state.prepareForFixture(id: id)
    }

    func snapshot() async -> Snapshot {
        await state.snapshot()
    }

    func isReadyForImmediateExtraction() async -> Bool { true }

    func extractSearchIntentJSON(prompt: String) async throws -> String {
        let fixtureID = await state.beginCall(prompt: prompt)
        guard let json = jsonByFixtureID[fixtureID]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty
        else {
            throw RecordingFixtureAsyncSearchIntentJSONProviderError.missingFixtureJSON
        }
        await state.completeCall(raw: json)
        return json
    }
}

private actor RecordingFixtureAsyncSearchIntentJSONProviderState {
    private var currentFixtureID: String?
    private var callCount = 0
    private var lastPrompt: String?
    private var lastRaw: String?

    func prepareForFixture(id: String) {
        currentFixtureID = id
        callCount = 0
        lastPrompt = nil
        lastRaw = nil
    }

    func snapshot() -> RecordingFixtureAsyncSearchIntentJSONProvider.Snapshot {
        RecordingFixtureAsyncSearchIntentJSONProvider.Snapshot(
            wasCalled: callCount > 0,
            callCount: callCount,
            promptSentToLLMExact: lastPrompt,
            rawLLMOutputExact: lastRaw
        )
    }

    func beginCall(prompt: String) -> String {
        callCount += 1
        lastPrompt = prompt
        return currentFixtureID ?? ""
    }

    func completeCall(raw: String) {
        lastRaw = raw
    }
}

private enum RecordingFixtureAsyncSearchIntentJSONProviderError: Error {
    case missingFixtureJSON
}
