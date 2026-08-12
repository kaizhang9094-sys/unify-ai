import XCTest
@testable import AnumCore

// MARK: - Test doubles

private final class SpyExchangeIntelligenceProvider: ExchangeIntelligenceProvider, @unchecked Sendable {
    private(set) var interpretCallCount = 0
    private(set) var fastClassifyCallCount = 0

    func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse {
        fastClassifyCallCount += 1
        return ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            mode: .transactional,
            kind: .find,
            readiness: .ready,
            confidence: 0.8,
            needsFullLLMInterpretation: true
        )
    }

    func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        interpretCallCount += 1
        return ExchangeIntelligenceInterpretationResponse(
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            mode: .transactional,
            kind: .find,
            title: String(request.userText.prefix(40)),
            objective: request.userText,
            constraints: [],
            desiredOutcomes: [.shortlist],
            readiness: .ready,
            confidence: 0.8,
            needsClarification: false,
            shouldDiscover: true,
            shouldDraft: false
        )
    }

    func modelPosture(
        _ request: ExchangeIntelligencePostureRequest
    ) async throws -> ExchangeIntelligencePostureResponse {
        ExchangeIntelligencePostureResponse(
            urgency: .normal,
            warmth: .neutral,
            directness: .balanced,
            openness: .open,
            commitment: .exploring,
            privacy: .balanced,
            priceSensitivity: .moderate,
            flexibility: .flexible,
            confidence: 0.5
        )
    }

    func composeDraft(
        _ request: ExchangeIntelligenceDraftRequest
    ) async throws -> ExchangeIntelligenceDraftResponse {
        ExchangeIntelligenceDraftResponse(body: "stub", confidence: 0.5)
    }

    func classifyInboundInquiry(
        _ request: ExchangeIntelligenceInboundInquiryRequest
    ) async throws -> ExchangeIntelligenceInboundInquiryResponse {
        ExchangeIntelligenceInboundInquiryResponse(
            inquirySummary: "stub",
            requesterAsk: request.requesterAsk,
            answerabilityStatus: .insufficientContext,
            classification: .routine,
            confidence: 0.5
        )
    }
}

private final class CountingAsyncSearchIntentExtractor: AsyncOpenEndedSearchIntentExtractor, @unchecked Sendable {
    private(set) var extractCallCount = 0
    var canonicalResult: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?

    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        extractCallCount += 1
        return canonicalResult
    }
}


private final class DiagnosticsFallbackAsyncSearchIntentExtractor: AsyncOpenEndedSearchIntentExtractor, @unchecked Sendable {
    private(set) var extractCallCount = 0
    var fallbackReason: SearchIntentExtractionFailureReason = .nonActionableDTO

    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        extractCallCount += 1
        return nil
    }

    func lastExtractionDiagnostics() async -> SearchIntentExtractionDiagnostics? {
        SearchIntentExtractionDiagnostics(
            attemptedLLM: true,
            source: .heuristicFallback,
            fallbackReason: fallbackReason
        )
    }
}

// MARK: - Tests

final class ExchangeInterpreterCanonicalRoutingTests: XCTestCase {
    private func offerSearchCanonical(
        object: String,
        need: ExchangeIntentFacets.TransactionIntent = .buy,
        rawUserText: String
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: object,
            transactionIntent: need,
            broadRecallTokens: [object, need.rawValue],
            semanticConcepts: [object],
            rawUserText: rawUserText,
            extractionSource: .llmFlatSummary,
            extractionConfidence: 0.9,
            extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute(
                routeClassRaw: "offerSearch",
                surfacePreferenceRaw: "offer",
                targetKindRaw: "provider",
                modeRaw: "transactional",
                routeConfidence: 0.85
            )
        )
    }

    private func makeInterpreter(
        provider: SpyExchangeIntelligenceProvider,
        extractor: CountingAsyncSearchIntentExtractor
    ) -> ExchangeInterpreter {
        ExchangeInterpreter(
            intelligenceProvider: provider,
            asyncSearchIntentExtractor: extractor
        )
    }

    func testBuyDogUsesCanonicalSearchIntentFirstWithoutProvider() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = offerSearchCanonical(
            object: "dog",
            rawUserText: "I want to buy a dog."
        )
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        let result = await interpreter.interpret(userText: "I want to buy a dog.")

        XCTAssertEqual(extractor.extractCallCount, 1)
        XCTAssertEqual(provider.interpretCallCount, 0)
        XCTAssertEqual(provider.fastClassifyCallCount, 0)

        guard case .interpreted(let request) = result else {
            return XCTFail("Expected interpreted result")
        }
        XCTAssertEqual(request.intent.queryIntentClass, .offerSearch)
        XCTAssertEqual(request.intent.surfacePreference, .offer)
        XCTAssertEqual(request.facets.targetKind, .provider)
        XCTAssertFalse(request.needsFullLLMInterpretation)
        XCTAssertEqual(request.facets.searchIntent?.objectType, "dog")
        XCTAssertEqual(request.facets.searchIntent?.transactionIntent, .buy)
    }

    func testSkinCareProductsUsesCanonicalSearchIntentFirstWithoutProvider() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = offerSearchCanonical(
            object: "skin care products",
            rawUserText: "I want to buy skin care products."
        )
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        let result = await interpreter.interpret(userText: "I want to buy skin care products.")

        XCTAssertEqual(extractor.extractCallCount, 1)
        XCTAssertEqual(provider.interpretCallCount, 0)

        guard case .interpreted(let request) = result else {
            return XCTFail("Expected interpreted result")
        }
        XCTAssertEqual(request.intent.queryIntentClass, .offerSearch)
        XCTAssertEqual(request.intent.surfacePreference, .offer)
    }

    func testRooferInAuroraUsesCanonicalSearchIntentFirstWithoutProvider() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "roofer",
            transactionIntent: .hire,
            places: [
                .init(
                    normalizedText: "Aurora",
                    aliases: [],
                    confidence: 0.9
                )
            ],
            timeConstraints: [.init(kind: .day, text: "tomorrow")],
            broadRecallTokens: ["roofer", "aurora", "tomorrow"],
            semanticConcepts: ["roofer"],
            rawUserText: "Find me a roofer in Aurora tomorrow",
            extractionSource: .llmFlatSummary,
            extractionConfidence: 0.88,
            extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute(
                routeClassRaw: "providerSearch",
                surfacePreferenceRaw: "offer",
                targetKindRaw: "provider",
                modeRaw: "transactional",
                routeConfidence: 0.82
            )
        )
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        let result = await interpreter.interpret(userText: "Find me a roofer in Aurora tomorrow")

        XCTAssertEqual(extractor.extractCallCount, 1)
        XCTAssertEqual(provider.interpretCallCount, 0)

        guard case .interpreted(let request) = result else {
            return XCTFail("Expected interpreted result")
        }
        XCTAssertEqual(request.intent.queryIntentClass, .providerSearch)
    }

    func testDraftReplyDoesNotUseCanonicalExtractor() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = offerSearchCanonical(
            object: "ignored",
            rawUserText: "Draft a reply to Wei"
        )
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        _ = await interpreter.interpret(userText: "Draft a reply to Wei")

        XCTAssertEqual(extractor.extractCallCount, 0)
        XCTAssertEqual(provider.interpretCallCount, 1)
    }

    private func providerSearchCanonical(
        object: String,
        rawUserText: String
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: object,
            transactionIntent: .hire,
            broadRecallTokens: [object],
            semanticConcepts: [object],
            rawUserText: rawUserText,
            extractionSource: .llmFlatSummary,
            extractionConfidence: 0.88,
            extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute(
                routeClassRaw: "providerSearch",
                surfacePreferenceRaw: "offer",
                targetKindRaw: "provider",
                modeRaw: "transactional",
                routeConfidence: 0.82
            )
        )
    }

    private func socialAffinityCanonical(
        object: String,
        rawUserText: String
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: object,
            transactionIntent: nil,
            broadRecallTokens: [object],
            semanticConcepts: [object],
            rawUserText: rawUserText,
            extractionSource: .llmFlatSummary,
            extractionConfidence: 0.86,
            extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute(
                routeClassRaw: "socialAffinitySearch",
                surfacePreferenceRaw: "affinity",
                targetKindRaw: "person",
                modeRaw: "relational",
                routeConfidence: 0.8
            )
        )
    }

    func testRooferInAuroraDirectQuerySearchComposerUsesCanonicalFirst() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = providerSearchCanonical(
            object: "roofer",
            rawUserText: "roofer in Aurora tomorrow 2 PM"
        )
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        let result = await interpreter.interpret(
            userText: "roofer in Aurora tomorrow 2 PM",
            entrySurface: .searchComposer
        )

        XCTAssertEqual(extractor.extractCallCount, 1)
        XCTAssertEqual(provider.interpretCallCount, 0)

        guard case .interpreted(let request) = result else {
            return XCTFail("Expected interpreted result")
        }
        XCTAssertEqual(request.intent.queryIntentClass, .providerSearch)
    }

    func testHikingBuddyNearTorontoSearchComposerUsesCanonicalFirst() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = socialAffinityCanonical(
            object: "hiking buddy",
            rawUserText: "hiking buddy near Toronto this weekend"
        )
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        _ = await interpreter.interpret(
            userText: "hiking buddy near Toronto this weekend",
            entrySurface: .searchComposer
        )

        XCTAssertEqual(extractor.extractCallCount, 1)
        XCTAssertEqual(provider.interpretCallCount, 0)
    }

    func testCommercialCleanerInMarkhamSearchComposerUsesCanonicalFirst() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = providerSearchCanonical(
            object: "commercial cleaner",
            rawUserText: "commercial cleaner in Markham"
        )
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        _ = await interpreter.interpret(
            userText: "commercial cleaner in Markham",
            entrySurface: .searchComposer
        )

        XCTAssertEqual(extractor.extractCallCount, 1)
        XCTAssertEqual(provider.interpretCallCount, 0)
    }

    func testPackagingSupplierSearchComposerUsesCanonicalFirst() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = offerSearchCanonical(
            object: "packaging supplier",
            rawUserText: "packaging supplier"
        )
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        _ = await interpreter.interpret(
            userText: "packaging supplier",
            entrySurface: .searchComposer
        )

        XCTAssertEqual(extractor.extractCallCount, 1)
        XCTAssertEqual(provider.interpretCallCount, 0)
    }

    func testDraftReplySearchComposerDoesNotUseCanonicalExtractor() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = offerSearchCanonical(
            object: "ignored",
            rawUserText: "Draft a reply to Wei"
        )
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        _ = await interpreter.interpret(
            userText: "Draft a reply to Wei",
            entrySurface: .searchComposer
        )

        XCTAssertEqual(extractor.extractCallCount, 0)
        XCTAssertEqual(provider.interpretCallCount, 1)
    }

    func testCanonicalExtractorFailureFallsBackToProvider() async {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = CountingAsyncSearchIntentExtractor()
        extractor.canonicalResult = nil
        let interpreter = makeInterpreter(provider: provider, extractor: extractor)

        _ = await interpreter.interpret(userText: "I want to buy a dog.")

        XCTAssertEqual(extractor.extractCallCount, 1)
        XCTAssertEqual(provider.interpretCallCount, 1)
        XCTAssertEqual(provider.fastClassifyCallCount, 0)
    }

    func testDeliveryQueryFallsThroughInsteadOfTransientFailure() async throws {
        let provider = SpyExchangeIntelligenceProvider()
        let extractor = DiagnosticsFallbackAsyncSearchIntentExtractor()
        extractor.fallbackReason = .nonActionableDTO
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: provider,
            asyncSearchIntentExtractor: extractor
        )

        let result = await interpreter.interpret(
            userText: "who can deliver this?",
            threadContext: nil,
            entrySurface: .searchComposer
        )

        if case .needsClarification(let failure, _, _, _) = result {
            XCTAssertNotEqual(
                failure.reasonCode,
                "search_intent_extractor_unavailable",
                "parse/actionability extractor miss must not transient-abort"
            )
        }

        XCTAssertEqual(extractor.extractCallCount, 1)
        XCTAssertEqual(provider.interpretCallCount, 1)

        guard case .interpreted(let request) = result else {
            return XCTFail("expected legacy provider fallthrough")
        }
        XCTAssertTrue(request.shouldDiscover)
    }
}
