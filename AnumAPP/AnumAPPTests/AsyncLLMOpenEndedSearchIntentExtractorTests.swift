import XCTest
@testable import AnumCore

final class AsyncLLMOpenEndedSearchIntentExtractorTests: XCTestCase {
    func test_asyncLLMSuccess_usesLLMSource() async throws {
        let raw = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."
        let dto = LLMSearchIntentExtractionDTO(
            objectType: "home",
            domainHint: "real estate",
            transactionIntentHint: "for sale",
            places: [.init(text: "GTA", aliases: ["Greater Toronto Area"], confidence: 0.92, isHard: false)],
            attributes: [.init(key: "bedrooms", value: "3 bedroom", numericValue: 3)],
            commercialConstraints: [.init(kind: "financing", key: "sellerFinancing", value: "vendor take-back mortgage", isHard: false)],
            semanticConcepts: ["seller financing", "vendor take-back mortgage"],
            broadRecallTokens: ["home", "gta"],
            confidence: 0.92
        )

        let store = SearchIntentExtractionDiagnosticsStore()
        let provider = AsyncFixedJSONProvider(rawJSON: encode(dto), ready: true)
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: provider,
            timeoutSeconds: 2.0,
            diagnosticsStore: store
        )

        let extracted = await extractor.extract(sourceText: raw, intent: fixtureIntent(raw))
        let out = try XCTUnwrap(extracted)
        XCTAssertTrue(out.commercialConstraints.contains { $0.value.lowercased().contains("vendor take-back") })
        let diag = await store.last
        XCTAssertEqual(diag?.source, .llm)
        XCTAssertNil(diag?.fallbackReason)
    }

    func test_noisyMarkdown_repairSucceeds_sourceRepaired() async throws {
        let raw = "Find me a ski buddy who has time next Saturday to Mount St. Louis."
        let dto = LLMSearchIntentExtractionDTO(
            objectType: "ski buddy",
            places: [.init(text: "Mount St. Louis", aliases: nil, confidence: 0.9, isHard: false)],
            timeConstraints: [.init(kind: "day", text: "next Saturday", isHard: false)],
            semanticConcepts: ["ski buddy"],
            broadRecallTokens: ["ski buddy", "mount st. louis"],
            confidence: 0.84
        )
        let noisy = "noise before ```json\n\(encode(dto))\n``` trailing"
        let store = SearchIntentExtractionDiagnosticsStore()
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: AsyncFixedJSONProvider(rawJSON: noisy, ready: true),
            diagnosticsStore: store
        )

        let extracted = await extractor.extract(sourceText: raw, intent: fixtureIntent(raw))
        let out = try XCTUnwrap(extracted)
        XCTAssertEqual(out.objectType, "ski buddy")
        let diag = await store.last
        XCTAssertEqual(diag?.source, .llmRepairedJSON)
        XCTAssertEqual(diag?.repairAttempted, true)
    }

    func test_invalidJSON_unrecoverable_fallsBack_withReason() async throws {
        let raw = "Looking for a house in GTA with seller financing."
        let store = SearchIntentExtractionDiagnosticsStore()
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: AsyncFixedJSONProvider(rawJSON: "not { json", ready: true),
            diagnosticsStore: store
        )
        let extracted = await extractor.extract(sourceText: raw, intent: fixtureIntent(raw))
        let out = try XCTUnwrap(extracted)
        XCTAssertEqual(out.objectType, "house")
        let diag = await store.last
        XCTAssertEqual(diag?.source, .heuristicFallback)
        XCTAssertTrue(diag?.fallbackReason == .invalidJSON || diag?.fallbackReason == .repairFailed)
    }

    func test_busyProvider_fallback_withoutProviderCall() async throws {
        let raw = "Looking for a house in GTA with seller financing."
        let provider = AsyncRecordingProvider(ready: false, behavior: .returning("{}"))
        let store = SearchIntentExtractionDiagnosticsStore()
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: provider,
            diagnosticsStore: store
        )

        let extracted = await extractor.extract(sourceText: raw, intent: fixtureIntent(raw))
        let out = try XCTUnwrap(extracted)
        XCTAssertEqual(out.objectType, "house")
        let callCount = await provider.callCount
        let diag = await store.last
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(diag?.fallbackReason, .modelBusy)
    }

    func test_timeout_fallback_fast() async throws {
        let raw = "Looking for a house in GTA with seller financing."
        let provider = AsyncRecordingProvider(ready: true, behavior: .sleepThenReturn(seconds: 0.3, json: "{}"))
        let store = SearchIntentExtractionDiagnosticsStore()
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: provider,
            timeoutSeconds: 0.05,
            diagnosticsStore: store
        )
        let start = CFAbsoluteTimeGetCurrent()
        let extracted = await extractor.extract(sourceText: raw, intent: fixtureIntent(raw))
        let out = try XCTUnwrap(extracted)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(out.objectType, "house")
        XCTAssertLessThan(elapsed, 0.25)
        let diag = await store.last
        XCTAssertEqual(diag?.fallbackReason, .timeout)
    }

    func test_throwingProvider_fallback_withThrownErrorReason() async throws {
        let raw = "Looking for a house in GTA with seller financing."
        let provider = AsyncRecordingProvider(ready: true, behavior: .throwing(TestErr.boom))
        let store = SearchIntentExtractionDiagnosticsStore()
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: provider,
            diagnosticsStore: store
        )

        let extracted = await extractor.extract(sourceText: raw, intent: fixtureIntent(raw))
        let out = try XCTUnwrap(extracted)
        XCTAssertEqual(out.objectType, "house")
        let diag = await store.last
        XCTAssertEqual(diag?.fallbackReason, .thrownError)
    }

    func test_cancellation_recordsCancelled() async {
        let raw = "Looking for a house in GTA with seller financing."
        let provider = AsyncRecordingProvider(ready: true, behavior: .sleepThenReturn(seconds: 0.25, json: "{}"))
        let store = SearchIntentExtractionDiagnosticsStore()
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: provider,
            timeoutSeconds: 1.0,
            diagnosticsStore: store
        )

        let task = Task {
            await extractor.extract(sourceText: raw, intent: fixtureIntent(raw))
        }
        task.cancel()
        _ = await task.value
        let diag = await store.last
        XCTAssertEqual(diag?.fallbackReason, .cancelled)
    }

    func test_lowConfidenceMapping_keepsGeneral_butUsesLLMResult() async throws {
        let raw = "Find me a ski buddy"
        let dto = LLMSearchIntentExtractionDTO(
            domainHint: "activity partner",
            semanticConcepts: ["ski buddy", "activity partner"],
            broadRecallTokens: ["ski buddy"],
            confidence: 0.40
        )
        let store = SearchIntentExtractionDiagnosticsStore()
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: AsyncFixedJSONProvider(rawJSON: encode(dto), ready: true),
            diagnosticsStore: store
        )

        let extracted = await extractor.extract(sourceText: raw, intent: fixtureIntent(raw))
        let out = try XCTUnwrap(extracted)
        XCTAssertEqual(out.domainCategory, .general)
        XCTAssertTrue(out.semanticConcepts.contains { $0.lowercased().contains("ski buddy") })
        let diag = await store.last
        XCTAssertEqual(diag?.source, .llm)
    }

    func test_nonActionableDTO_fallsBack() async throws {
        let raw = "help me find something"
        let dto = LLMSearchIntentExtractionDTO(confidence: 0.30)
        let store = SearchIntentExtractionDiagnosticsStore()
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: AsyncFixedJSONProvider(rawJSON: encode(dto), ready: true),
            diagnosticsStore: store
        )
        let extracted = await extractor.extract(sourceText: raw, intent: fixtureIntent(raw))
        let out = try XCTUnwrap(extracted)
        XCTAssertEqual(out.objectType, nil)
        let diag = await store.last
        XCTAssertTrue(
            diag?.fallbackReason == .nonActionableDTO || diag?.fallbackReason == .emptyDTO,
            "Expected non-actionable/empty fallback reason, got \(String(describing: diag?.fallbackReason))"
        )
    }

    func test_interpreterIntegration_asyncLLMExtractor_usedForCanonicalIntent() async throws {
        let raw = "Help me find a 3 bedroom home for sale in GTA, and seller offers vendor take back mortgage."
        let dto = LLMSearchIntentExtractionDTO(
            objectType: "home",
            domainHint: "real estate",
            transactionIntentHint: "for sale",
            places: [.init(text: "GTA", aliases: nil, confidence: 0.92, isHard: false)],
            attributes: [.init(key: "bedrooms", value: "3 bedroom", numericValue: 3)],
            commercialConstraints: [.init(kind: "financing", key: "sellerFinancing", value: "vendor take-back mortgage", isHard: false)],
            semanticConcepts: ["vendor take-back mortgage"],
            broadRecallTokens: ["home", "gta"],
            confidence: 0.92
        )
        let store = SearchIntentExtractionDiagnosticsStore()
        let asyncExtractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: AsyncFixedJSONProvider(rawJSON: encode(dto), ready: true),
            diagnosticsStore: store
        )
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: ExchangeFallbackIntelligenceProvider(),
            searchIntentExtractor: CanonicalSearchIntentHeuristicExtractor(),
            asyncSearchIntentExtractor: asyncExtractor
        )

        let result = await interpreter.interpret(userText: raw, threadContext: nil)
        guard case .interpreted(let req) = result else {
            XCTFail("Expected interpreted result")
            return
        }
        let si = try XCTUnwrap(req.facets.searchIntent)
        XCTAssertTrue(si.commercialConstraints.contains { $0.value.lowercased().contains("vendor take-back") })
        XCTAssertFalse(req.discoveryKeywords.contains { $0.lowercased().contains(", and ") })
        let diag = await store.last
        XCTAssertEqual(diag?.source, .llm)
    }

    func test_interpreterIntegration_busyFallsBack_withoutProviderCall() async throws {
        let raw = "Looking for a house in GTA with seller financing."
        let provider = AsyncRecordingProvider(ready: false, behavior: .returning("{}"))
        let store = SearchIntentExtractionDiagnosticsStore()
        let asyncExtractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: provider,
            diagnosticsStore: store
        )
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: ExchangeFallbackIntelligenceProvider(),
            searchIntentExtractor: CanonicalSearchIntentHeuristicExtractor(),
            asyncSearchIntentExtractor: asyncExtractor
        )

        let result = await interpreter.interpret(userText: raw, threadContext: nil)
        guard case .interpreted(let req) = result else {
            XCTFail("Expected interpreted result")
            return
        }
        XCTAssertEqual(req.facets.searchIntent?.objectType, "house")
        let callCount = await provider.callCount
        let diag = await store.last
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(diag?.fallbackReason, .modelBusy)
    }
}

private extension AsyncLLMOpenEndedSearchIntentExtractorTests {
    enum TestErr: Error { case boom }

    actor AsyncRecordingProvider: AsyncSearchIntentJSONProvider {
        enum Behavior {
            case returning(String)
            case sleepThenReturn(seconds: Double, json: String)
            case throwing(Error)
        }
        private(set) var callCount: Int = 0
        let ready: Bool
        let behavior: Behavior

        init(ready: Bool, behavior: Behavior) {
            self.ready = ready
            self.behavior = behavior
        }

        func isReadyForImmediateExtraction() async -> Bool { ready }

        func extractSearchIntentJSON(prompt: String) async throws -> String {
            callCount += 1
            switch behavior {
            case .returning(let json):
                return json
            case .sleepThenReturn(let seconds, let json):
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return json
            case .throwing(let error):
                throw error
            }
        }
    }

    struct AsyncFixedJSONProvider: AsyncSearchIntentJSONProvider {
        let rawJSON: String
        let ready: Bool
        func isReadyForImmediateExtraction() async -> Bool { ready }
        func extractSearchIntentJSON(prompt: String) async throws -> String { rawJSON }
    }

    func encode(_ dto: LLMSearchIntentExtractionDTO) -> String {
        let data = try! JSONEncoder().encode(dto)
        return String(data: data, encoding: .utf8)!
    }

    func fixtureIntent(_ raw: String) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "fixture",
            objective: raw
        )
    }
}
