import Foundation
import XCTest

@testable import AnumCore

/// Golden harness + audit artifact for search intent extraction and ``ExchangeInterpreter`` output.
///
/// Production entry points exercised:
/// - ``ExchangeInterpreter/interpret(userText:threadContext:)`` with ``ExchangeFallbackIntelligenceProvider``
///   and ``CanonicalSearchIntentHeuristicExtractor`` (default sync extractor).
/// - Optional golden flat-summary JSON replayed through ``LLMOpenEndedSearchIntentExtractor`` (mapper/parser only; no model).
///
/// Artifact: ``AnumCore/Tests/Artifacts/intent_extractor_audit.jsonl``
final class IntentExtractorGoldenHarnessTests: XCTestCase {

    private actor HarnessState {
        var lines: [Data] = []
        var passCount = 0
        var failCount = 0

        func appendLine(_ data: Data) { lines.append(data) }
        func recordPass() { passCount += 1 }
        func recordFail() { failCount += 1 }
        func snapshot() -> (lines: [Data], pass: Int, fail: Int) { (lines, passCount, failCount) }
    }

    private let harnessState = HarnessState()

    override func tearDown() async throws {
        try await flushAuditArtifact()
    }

    private func flushAuditArtifact() async throws {
        let snap = await harnessState.snapshot()
        guard !snap.lines.isEmpty else { return }

        let url = Self.auditArtifactURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var combined = Data()
        for (idx, chunk) in snap.lines.enumerated() {
            combined.append(chunk)
            if idx < snap.lines.count - 1 { combined.append(Data("\n".utf8)) }
        }
        try combined.write(to: url, options: [.atomic])
    }

    private static var auditArtifactURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("intent_extractor_audit.jsonl", isDirectory: false)
    }

    func testIntentExtractorGoldenHarnessAudit() async throws {
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: ExchangeFallbackIntelligenceProvider(),
            searchIntentExtractor: CanonicalSearchIntentHeuristicExtractor(),
            asyncSearchIntentExtractor: nil
        )

        for fixture in IntentExtractorGoldenFixtures.all {
            let row = await runFixture(fixture, interpreter: interpreter)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(row)
            await harnessState.appendLine(data)

            if row.passed { await harnessState.recordPass() } else { await harnessState.recordFail() }

            if !row.passed, fixture.validationMode == .strict {
                XCTFail(Self.xctFailureMessage(from: row))
            }
        }
    }

    private func runFixture(
        _ fixture: IntentExtractorGoldenFixture,
        interpreter: ExchangeInterpreter
    ) async -> IntentExtractorAuditRow {
        let interpretation = await interpreter.interpret(
            userText: fixture.inputText,
            threadContext: nil
        )

        let (intent, facets) = Self.extractIntentFacets(from: interpretation)
        let intentSummary = Self.summarizeIntent(intent)
        let facetsSummary = Self.summarizeFacets(facets)
        let canonicalSummary = facets?.searchIntent.map { Self.summarizeCanonical($0) }

        var rawLLM: String?
        var rawExtractor: String?
        var mapperCanonicalSummary: String?

        if let goldenJSON = fixture.llmFlatSummaryJSON {
            rawLLM = goldenJSON
            let provider = GoldenConstantJSONProvider(json: goldenJSON)
            let llmExtractor = LLMOpenEndedSearchIntentExtractor(jsonProvider: provider)
            let seed = intent ?? Self.defaultSeedIntent(for: fixture.inputText)
            if let mapped = llmExtractor.extract(sourceText: fixture.inputText, intent: seed) {
                mapperCanonicalSummary = Self.summarizeCanonical(mapped)
                rawExtractor = (try? Self.encodeCanonicalJSON(mapped)) ?? rawExtractor
            }
        }

        if rawExtractor == nil, let canonical = facets?.searchIntent {
            rawExtractor = (try? Self.encodeCanonicalJSON(canonical)) ?? "canonical:encoding_failed"
        } else if rawExtractor == nil {
            rawExtractor = "interpreter:no_searchIntent"
        }

        let failures = Self.evaluateExpectations(fixture: fixture, intent: intent, facets: facets)
        let passed = failures.isEmpty

        return IntentExtractorAuditRow(
            fixtureId: fixture.id,
            language: fixture.language,
            category: fixture.category,
            inputText: fixture.inputText,
            rawLLMOutput: rawLLM,
            rawExtractorOutput: rawExtractor,
            parsedIntentSummary: intentSummary,
            parsedFacetsSummary: facetsSummary,
            parsedMapperCanonicalSummary: mapperCanonicalSummary,
            parsedCanonicalSummary: canonicalSummary,
            expectedSummary: fixture.expectedSummaryLine,
            passed: passed,
            failedFields: failures
        )
    }

    private static func xctFailureMessage(from row: IntentExtractorAuditRow) -> String {
        var parts: [String] = []
        parts.append("fixtureId=\(row.fixtureId)")
        parts.append("inputText=\(row.inputText)")
        if let raw = row.rawLLMOutput { parts.append("rawLLMOutput=\(raw)") }
        if let rawEx = row.rawExtractorOutput { parts.append("rawExtractorOutput=\(rawEx)") }
        parts.append("parsedIntentSummary=\(row.parsedIntentSummary)")
        parts.append("parsedFacetsSummary=\(row.parsedFacetsSummary)")
        if let c = row.parsedCanonicalSummary { parts.append("parsedCanonicalSummary=\(c)") }
        parts.append("failedFields=\(row.failedFields.joined(separator: " | "))")
        return parts.joined(separator: "\n")
    }

    private static func extractIntentFacets(
        from result: ExchangeInterpreter.InterpretationResult
    ) -> (ExchangeIntent?, ExchangeIntentFacets?) {
        switch result {
        case .interpreted(let req):
            return (req.intent, req.facets)
        case .needsClarification(_, let draftIntent, _, let draftFacets):
            return (draftIntent, draftFacets)
        }
    }

    private static func defaultSeedIntent(for text: String) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "seed",
            objective: text
        )
    }

    private static func summarizeIntent(_ intent: ExchangeIntent?) -> String {
        guard let intent else { return "nil" }
        return [
            "kind=\(intent.kind.rawValue)",
            "mode=\(intent.mode.rawValue)",
            "queryIntentClass=\(intent.queryIntentClass.rawValue)",
            "surfacePreference=\(intent.surfacePreference.rawValue)",
            "readiness=\(intent.readiness.rawValue)",
            "title=\(intent.title)",
            "objective=\(intent.objective)",
            "targetDescription=\(intent.targetDescription ?? "nil")",
            "confidence=\(String(format: "%.3f", intent.interpretationConfidence))"
        ].joined(separator: " | ")
    }

    private static func summarizeFacets(_ facets: ExchangeIntentFacets?) -> String {
        guard let facets else { return "nil" }
        return [
            "targetKind=\(facets.targetKind.rawValue)",
            "marketType=\(facets.marketType.rawValue)",
            "fulfillmentMode=\(facets.fulfillmentMode.rawValue)",
            "queryIntentClass=\(facets.queryIntentClass.rawValue)",
            "surfacePreference=\(facets.surfacePreference.rawValue)",
            "prefersLocalFirst=\(facets.prefersLocalFirst)",
            "allowsRemoteOrShipped=\(facets.allowsRemoteOrShipped)",
            "providerTerms=[\(facets.providerTerms.joined(separator: ","))]",
            "capabilityTerms=[\(facets.capabilityTerms.joined(separator: ","))]",
            "affinityTerms=[\(facets.affinityTerms.joined(separator: ","))]",
            "regionTerms=[\(facets.regionTerms.joined(separator: ","))]",
            "primaryKeywords=[\(facets.primaryKeywords.joined(separator: ","))]",
            "hasSearchIntent=\(facets.searchIntent != nil)"
        ].joined(separator: " | ")
    }

    private static func summarizeCanonical(_ c: ExchangeIntentFacets.ExchangeCanonicalSearchIntent) -> String {
        [
            "domain=\(c.domainCategory.rawValue)",
            "objectType=\(c.objectType ?? "nil")",
            "transaction=\(c.transactionIntent?.rawValue ?? "nil")",
            "places=\(c.places.map(\.normalizedText).joined(separator: "|"))",
            "time=\(c.timeConstraints.map(\.text).joined(separator: "|"))",
            "semantic=\(c.semanticConcepts.joined(separator: ","))",
            "broadRecall=\(c.broadRecallTokens.joined(separator: ","))",
            "clarificationGaps=\(c.clarificationGaps.joined(separator: ","))",
            "extractionSource=\(c.extractionSource?.rawValue ?? "nil")",
            "confidence=\(c.extractionConfidence.map { String(format: "%.3f", $0) } ?? "nil")"
        ].joined(separator: " | ")
    }

    private static func encodeCanonicalJSON(
        _ c: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) throws -> String {
        let data = try JSONEncoder().encode(c)
        return String(decoding: data, as: UTF8.self)
    }

    private static func buildHaystack(intent: ExchangeIntent?, facets: ExchangeIntentFacets?) -> String {
        var parts: [String] = []
        if let intent {
            parts.append(contentsOf: [
                intent.title,
                intent.objective,
                intent.targetDescription ?? "",
                intent.interpretationNotes ?? ""
            ])
            for c in intent.constraints {
                parts.append(c.key)
                parts.append(c.value)
            }
        }
        if let facets {
            parts.append(facets.targetRole ?? "")
            parts.append(facets.activity ?? "")
            parts.append(facets.serviceCategory ?? "")
            parts.append(facets.productCategory ?? "")
            parts.append(facets.locationText ?? "")
            parts.append(facets.placeName ?? "")
            parts.append(facets.timeText ?? "")
            parts.append(contentsOf: facets.providerTerms)
            parts.append(contentsOf: facets.capabilityTerms)
            parts.append(contentsOf: facets.affinityTerms)
            parts.append(contentsOf: facets.regionTerms)
            parts.append(contentsOf: facets.primaryKeywords)
            parts.append(contentsOf: facets.secondaryKeywords)
            if let si = facets.searchIntent {
                parts.append(si.rawUserText)
                parts.append(contentsOf: si.semanticConcepts)
                parts.append(contentsOf: si.broadRecallTokens)
                for p in si.places { parts.append(p.normalizedText) }
                for t in si.timeConstraints { parts.append(t.text) }
                for h in si.hardConstraints { parts.append(h.value) }
                for s in si.softPreferences { parts.append(s.value) }
            }
        }
        return parts.joined(separator: " ")
    }

    private static func evaluateExpectations(
        fixture: IntentExtractorGoldenFixture,
        intent: ExchangeIntent?,
        facets: ExchangeIntentFacets?
    ) -> [String] {
        var failures: [String] = []

        guard let intent, let facets else {
            failures.append("missingIntentOrFacets")
            return failures
        }

        let hay = buildHaystack(intent: intent, facets: facets).lowercased()

        if !fixture.expectedAnyIntentKinds.isEmpty {
            let ok = fixture.expectedAnyIntentKinds.contains(intent.kind.rawValue)
            if !ok {
                failures.append(
                    "intentKind: wanted one of [\(fixture.expectedAnyIntentKinds.joined(separator: ","))] got \(intent.kind.rawValue)"
                )
            }
        }

        if !fixture.expectedAnyQueryIntentClasses.isEmpty {
            let ok = fixture.expectedAnyQueryIntentClasses.contains(intent.queryIntentClass.rawValue)
            if !ok {
                failures.append(
                    "queryIntentClass: wanted one of [\(fixture.expectedAnyQueryIntentClasses.joined(separator: ","))] got \(intent.queryIntentClass.rawValue)"
                )
            }
        }

        if !fixture.expectedAnySurfacePreferences.isEmpty {
            let ok = fixture.expectedAnySurfacePreferences.contains(intent.surfacePreference.rawValue)
            if !ok {
                failures.append(
                    "surfacePreference: wanted one of [\(fixture.expectedAnySurfacePreferences.joined(separator: ","))] got \(intent.surfacePreference.rawValue)"
                )
            }
        }

        if !fixture.expectedReadiness.isEmpty {
            let ok = fixture.expectedReadiness.contains(intent.readiness.rawValue)
            if !ok {
                failures.append(
                    "readiness: wanted one of [\(fixture.expectedReadiness.joined(separator: ","))] got \(intent.readiness.rawValue)"
                )
            }
        }

        if !fixture.expectedDomainCategories.isEmpty,
           let domain = facets.searchIntent?.domainCategory.rawValue {
            let ok = fixture.expectedDomainCategories.contains(domain)
            if !ok {
                failures.append(
                    "domainCategory: wanted one of [\(fixture.expectedDomainCategories.joined(separator: ","))] got \(domain)"
                )
            }
        }

        for term in fixture.expectedHaystackSubstrings {
            let needle = term.lowercased()
            if !hay.contains(needle) {
                failures.append("haystackMissing:\(term)")
            }
        }

        return failures
    }
}

private struct IntentExtractorAuditRow: Codable, Sendable {
    var fixtureId: String
    var language: String
    var category: String
    var inputText: String
    var rawLLMOutput: String?
    var rawExtractorOutput: String?
    var parsedIntentSummary: String
    var parsedFacetsSummary: String
    var parsedMapperCanonicalSummary: String?
    var parsedCanonicalSummary: String?
    var expectedSummary: String
    var passed: Bool
    var failedFields: [String]
}

enum FixtureValidationMode: String, Codable, Sendable { case auditOnly, strict }

struct IntentExtractorGoldenFixture: Sendable {
    var id: String
    var language: String
    var category: String
    var inputText: String
    var llmFlatSummaryJSON: String?
    var expectedAnyIntentKinds: [String]
    var expectedAnyQueryIntentClasses: [String]
    var expectedAnySurfacePreferences: [String]
    var expectedReadiness: [String]
    var expectedDomainCategories: [String]
    var expectedHaystackSubstrings: [String]
    var expectedSummaryLine: String
    var validationMode: FixtureValidationMode
}

private struct GoldenConstantJSONProvider: LLMOpenEndedSearchIntentExtractor.JSONProvider {
    let json: String

    func extractSearchIntentJSON(
        prompt: String,
        sourceText: String,
        intent: ExchangeIntent
    ) throws -> String { json }
}
