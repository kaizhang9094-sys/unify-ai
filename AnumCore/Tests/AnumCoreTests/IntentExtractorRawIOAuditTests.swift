import Foundation
import XCTest

@testable import AnumCore

/// Writes full input/output JSON for manual audit: ``Tests/Artifacts/intent_extractor_raw_io_audit.jsonl``.
final class IntentExtractorRawIOAuditTests: XCTestCase {

    func testIntentExtractorRawIOAuditArtifact() async throws {
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: ExchangeFallbackIntelligenceProvider(),
            searchIntentExtractor: CanonicalSearchIntentHeuristicExtractor(),
            asyncSearchIntentExtractor: nil
        )
        let heuristicExtractor = CanonicalSearchIntentHeuristicExtractor()

        var lines: [Data] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        for fixture in IntentExtractorGoldenFixtures.all {
            let row = await buildRawIORow(
                fixture: fixture,
                interpreter: interpreter,
                heuristicExtractor: heuristicExtractor
            )
            lines.append(try encoder.encode(row))
        }

        let url = Self.rawIOAuditArtifactURL
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
    }

    private static var rawIOAuditArtifactURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("intent_extractor_raw_io_audit.jsonl", isDirectory: false)
    }

    private func buildRawIORow(
        fixture: IntentExtractorGoldenFixture,
        interpreter: ExchangeInterpreter,
        heuristicExtractor: CanonicalSearchIntentHeuristicExtractor
    ) async -> IntentExtractorRawIOAuditRow {
        let interpretation = await interpreter.interpret(
            userText: fixture.inputText,
            threadContext: nil
        )
        let (intent, facets) = IntentExtractorGoldenEvaluation.extractIntentFacets(from: interpretation)
        let seed = intent ?? IntentExtractorGoldenEvaluation.defaultSeedIntent(for: fixture.inputText)

        let promptSent = ExchangeOpenEndedSearchIntentPromptBuilder.buildPrompt(
            sourceText: fixture.inputText,
            intent: seed
        )

        var rawLLM: String?
        var rawExtractor: String?
        var mapperCanonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
        var notesParts: [String] = []

        let heuristicCanonical = heuristicExtractor.extract(
            sourceText: fixture.inputText,
            intent: seed
        )

        if let goldenJSON = fixture.llmFlatSummaryJSON {
            rawLLM = goldenJSON
            notesParts.append(
                "rawLLMOutputExact is golden flat-summary JSON replayed through LLMOpenEndedSearchIntentExtractor.JSONProvider; no on-device model run in this test target."
            )
            let provider = RawIOGoldenConstantJSONProvider(json: goldenJSON)
            let llmExtractor = LLMOpenEndedSearchIntentExtractor(jsonProvider: provider)
            mapperCanonical = llmExtractor.extract(sourceText: fixture.inputText, intent: seed)
            if let mapped = mapperCanonical {
                rawExtractor = Self.encodeJSONString(mapped)
                notesParts.append("rawExtractorOutputExact is mapper canonical JSON (extractionSource typically llmFlatSummary).")
            } else {
                notesParts.append("LLM mapper returned nil; see heuristic fallback below if present.")
            }
        } else {
            rawLLM = nil
            notesParts.append(
                "rawLLMOutputExact is null: harness uses ExchangeFallbackIntelligenceProvider + CanonicalSearchIntentHeuristicExtractor with asyncSearchIntentExtractor=nil; no live ExchangeIntelligenceModelRunner call."
            )
            if let heuristicCanonical {
                rawExtractor = Self.encodeJSONString(heuristicCanonical)
                notesParts.append("rawExtractorOutputExact is direct CanonicalSearchIntentHeuristicExtractor output JSON.")
            } else {
                rawExtractor = nil
                notesParts.append("rawExtractorOutputExact is null: heuristic extract returned nil for this input.")
            }
        }

        if let heuristicCanonical, fixture.llmFlatSummaryJSON != nil {
            notesParts.append(
                "Heuristic-only canonical also available (not used as rawExtractorOutputExact when LLM replay fixture is set): "
                + (Self.encodeJSONString(heuristicCanonical) ?? "encode_failed")
            )
        }

        let flexibleFailures = IntentExtractorGoldenEvaluation.evaluateFlexible(
            fixture: fixture,
            intent: intent,
            facets: facets
        )
        let strictFailures = IntentExtractorGoldenEvaluation.evaluateStrict(
            fixture: fixture,
            intent: intent,
            facets: facets
        )

        return IntentExtractorRawIOAuditRow(
            fixtureId: fixture.id,
            language: IntentExtractorGoldenEvaluation.mapAuditLanguage(fixture.language),
            category: fixture.category,
            inputTextExact: fixture.inputText,
            promptSentToLLMExact: promptSent,
            rawLLMOutputExact: rawLLM,
            rawExtractorOutputExact: rawExtractor,
            parsedIntentFull: intent,
            parsedFacetsFull: facets,
            parsedCanonicalSearchIntentFull: facets?.searchIntent,
            parsedMapperCanonicalFull: mapperCanonical,
            expectedFull: IntentExtractorGoldenEvaluation.expectedFull(from: fixture),
            oldPassed: flexibleFailures.isEmpty,
            strictPass: strictFailures.isEmpty,
            failedFields: flexibleFailures,
            notes: notesParts.joined(separator: " ")
        )
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct IntentExtractorRawIOAuditRow: Codable, Sendable {
    var fixtureId: String
    var language: String
    var category: String
    var inputTextExact: String
    var promptSentToLLMExact: String
    var rawLLMOutputExact: String?
    var rawExtractorOutputExact: String?
    var parsedIntentFull: ExchangeIntent?
    var parsedFacetsFull: ExchangeIntentFacets?
    var parsedCanonicalSearchIntentFull: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    var parsedMapperCanonicalFull: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    var expectedFull: IntentExtractorExpectedFull
    var oldPassed: Bool
    var strictPass: Bool
    var failedFields: [String]
    var notes: String
}

private struct RawIOGoldenConstantJSONProvider: LLMOpenEndedSearchIntentExtractor.JSONProvider {
    let json: String

    func extractSearchIntentJSON(
        prompt: String,
        sourceText: String,
        intent: ExchangeIntent
    ) throws -> String {
        json
    }
}
