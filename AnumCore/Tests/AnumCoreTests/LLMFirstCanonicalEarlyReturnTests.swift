import XCTest
@testable import AnumCore

final class LLMFirstCanonicalEarlyReturnTests: XCTestCase {
    func testSocialPaintingValidatedRouteEarlyReturnWithoutEscalation() async {
        let tracker = IntelligenceCallTracker()
        let extractCounter = ExtractCallCounter()
        let interpreter = makeInterpreter(
            json: SearchIntentRouteTestFixtures.paintingPeopleJSON,
            extractCounter: extractCounter,
            intelligenceTracker: tracker,
            blockEscalation: true
        )

        let result = await interpreter.interpret(
            userText: "Find people interested in painting.",
            threadContext: nil
        )

        guard case .interpreted(let request) = result else {
            return XCTFail("expected interpreted early return")
        }

        XCTAssertEqual(request.intent.queryIntentClass, .socialAffinitySearch)
        XCTAssertEqual(request.intent.mode, .relational)
        XCTAssertEqual(request.intent.surfacePreference, .affinity)
        XCTAssertEqual(request.facets.targetKind, .person)
        XCTAssertTrue(request.shouldDiscover)

        let calls = await tracker.snapshot()
        XCTAssertEqual(calls.fastClassification, 0)
        XCTAssertEqual(calls.interpret, 0)
        let extractCalls = await extractCounter.value()
        XCTAssertEqual(extractCalls, 1)
    }

    func testCommercialValidatedRouteEarlyReturnWithoutEscalation() async {
        let tracker = IntelligenceCallTracker()
        let extractCounter = ExtractCallCounter()
        let interpreter = makeInterpreter(
            json: SearchIntentRouteTestFixtures.productPhotographerJSON,
            extractCounter: extractCounter,
            intelligenceTracker: tracker,
            blockEscalation: true
        )

        let result = await interpreter.interpret(
            userText: "Find a photographer for product photos in Aurora",
            threadContext: nil
        )

        guard case .interpreted(let request) = result else {
            return XCTFail("expected interpreted early return")
        }

        XCTAssertEqual(request.intent.queryIntentClass, .providerSearch)
        XCTAssertEqual(request.intent.mode, .transactional)

        let calls = await tracker.snapshot()
        XCTAssertEqual(calls.fastClassification, 0)
        XCTAssertEqual(calls.interpret, 0)
        let extractCalls = await extractCounter.value()
        XCTAssertEqual(extractCalls, 1)
    }

    func testLowConfidenceRouteAllowsFallbackEscalation() async {
        let tracker = IntelligenceCallTracker()
        let extractCounter = ExtractCallCounter()
        let interpreter = makeInterpreter(
            json: SearchIntentRouteTestFixtures.invalidSocialLowConfidenceJSON,
            extractCounter: extractCounter,
            intelligenceTracker: tracker,
            blockEscalation: false
        )

        _ = await interpreter.interpret(
            userText: "Find people interested in photography in Aurora",
            threadContext: nil
        )

        let calls = await tracker.snapshot()
        XCTAssertGreaterThan(calls.fastClassification, 0)
    }

    func testLegacyJSONWithoutRouteAllowsFallbackEscalation() async {
        let tracker = IntelligenceCallTracker()
        let extractCounter = ExtractCallCounter()
        let interpreter = makeInterpreter(
            json: SearchIntentRouteTestFixtures.legacyPaintingJSON,
            extractCounter: extractCounter,
            intelligenceTracker: tracker,
            blockEscalation: false
        )

        _ = await interpreter.interpret(
            userText: "Find people interested in painting.",
            threadContext: nil
        )

        let calls = await tracker.snapshot()
        XCTAssertGreaterThan(calls.fastClassification, 0)
    }

    func testMovieTomorrowAuroraSocialEarlyReturnUsesLLMRoute() async {
        let tracker = IntelligenceCallTracker()
        let extractCounter = ExtractCallCounter()
        let interpreter = makeInterpreter(
            json: SearchIntentRouteTestFixtures.movieAuroraSocialJSON,
            extractCounter: extractCounter,
            intelligenceTracker: tracker,
            blockEscalation: true
        )

        let result = await interpreter.interpret(
            userText: "Find someone who wants to watch a movie tomorrow in Aurora",
            threadContext: nil
        )

        guard case .interpreted(let request) = result else {
            return XCTFail("expected interpreted early return")
        }

        XCTAssertEqual(request.intent.queryIntentClass, .socialAffinitySearch)
        XCTAssertEqual(request.intent.mode, .relational)
        XCTAssertEqual(request.intent.surfacePreference, .affinity)
        XCTAssertEqual(request.facets.targetKind, .person)
        XCTAssertNotEqual(request.intent.title, "Find Provider")
        XCTAssertTrue(request.facets.providerTerms.isEmpty)
        XCTAssertTrue(request.facets.affinityTerms.contains(where: { $0.lowercased().contains("movie") }))
        XCTAssertEqual(ExchangeThreadLaneResolver.lane(for: request.intent), .socialConnection)

        let calls = await tracker.snapshot()
        XCTAssertEqual(calls.fastClassification, 0)
        XCTAssertEqual(calls.interpret, 0)
        let extractCalls = await extractCounter.value()
        XCTAssertEqual(extractCalls, 1)
    }

    // MARK: - Helpers

    private func makeInterpreter(
        json: String,
        extractCounter: ExtractCallCounter,
        intelligenceTracker: IntelligenceCallTracker,
        blockEscalation: Bool
    ) -> ExchangeInterpreter {
        ExchangeInterpreter(
            intelligenceProvider: TrackingIntelligenceProvider(
                tracker: intelligenceTracker,
                blockCalls: blockEscalation,
                fallback: ExchangeFallbackIntelligenceProvider()
            ),
            searchIntentExtractor: CanonicalSearchIntentHeuristicExtractor(),
            asyncSearchIntentExtractor: CountingRouteFixtureAsyncExtractor(
                json: json,
                counter: extractCounter
            )
        )
    }
}

private actor ExtractCallCounter {
    private var count = 0

    func increment() { count += 1 }
    func value() -> Int { count }
}

private actor IntelligenceCallTracker {
    private var fastClassificationCalls = 0
    private var interpretCalls = 0

    func recordFastClassification() { fastClassificationCalls += 1 }
    func recordInterpret() { interpretCalls += 1 }

    func snapshot() -> (fastClassification: Int, interpret: Int) {
        (fastClassificationCalls, interpretCalls)
    }
}

private struct CountingRouteFixtureAsyncExtractor: AsyncOpenEndedSearchIntentExtractor {
    let json: String
    let counter: ExtractCallCounter

    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        await counter.increment()
        let extractor = LLMOpenEndedSearchIntentExtractor(
            jsonProvider: RouteFixtureJSONProvider(json: json)
        )
        return extractor.extract(sourceText: sourceText, intent: intent)
    }
}

private struct TrackingIntelligenceProvider: ExchangeIntelligenceProvider {
    let tracker: IntelligenceCallTracker
    let blockCalls: Bool
    let fallback: ExchangeFallbackIntelligenceProvider

    func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse {
        await tracker.recordFastClassification()
        if blockCalls {
            XCTFail("fastClassification should not run for validated-route early return")
        }
        return try await fallback.classifyIntentFast(request)
    }

    func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        await tracker.recordInterpret()
        if blockCalls {
            XCTFail("provider interpret should not run for validated-route early return")
        }
        return try await fallback.interpret(request)
    }

    func modelPosture(
        _ request: ExchangeIntelligencePostureRequest
    ) async throws -> ExchangeIntelligencePostureResponse {
        try await fallback.modelPosture(request)
    }

    func composeDraft(
        _ request: ExchangeIntelligenceDraftRequest
    ) async throws -> ExchangeIntelligenceDraftResponse {
        try await fallback.composeDraft(request)
    }

    func classifyInboundInquiry(
        _ request: ExchangeIntelligenceInboundInquiryRequest
    ) async throws -> ExchangeIntelligenceInboundInquiryResponse {
        try await fallback.classifyInboundInquiry(request)
    }
}


private struct RouteFixtureJSONProvider: LLMOpenEndedSearchIntentExtractor.JSONProvider {
    let json: String

    func extractSearchIntentJSON(
        prompt: String,
        sourceText: String,
        intent: ExchangeIntent
    ) throws -> String {
        json
    }
}
