import XCTest
@testable import AnumCore

final class SearchIntentFlatPipelineTests: XCTestCase {
    private let dogSellerJSON = """
    {"raw":"Find me dog seller.","object":"dog seller","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.9,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"search vendor for dog seller"}
    """

    func testDogSellerCompactJsonReturnsProviderSearchCanonical() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let intent = seedIntent(objective: "Find me dog seller.")
        let canonical = extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: dogSellerJSON,
            userText: "Find me dog seller.",
            intent: intent
        )
        XCTAssertNotNil(canonical)
        XCTAssertEqual(canonical?.objectType, "dog seller")
        XCTAssertEqual(canonical?.extractedRoute?.routeClassRaw, "providerSearch")
    }

    func testSanitizeObjectPreservesSingleWordQuery() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let fingerprint = extractor.compactSentenceFingerprint("computer")
        let sanitized = extractor.sanitizeText(
            "computer",
            role: .objectText,
            sentenceFingerprint: fingerprint
        )
        XCTAssertEqual(sanitized, "computer")
    }

    func testSanitizeObjectPreservesShortPhrase() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let query = "macbook pro"
        let fingerprint = extractor.compactSentenceFingerprint(query)
        let sanitized = extractor.sanitizeText(
            "macbook pro",
            role: .objectText,
            sentenceFingerprint: fingerprint
        )
        XCTAssertEqual(sanitized, "macbook pro")
    }

    func testGenericNeedTextStillStripsFullQueryEcho() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let query = "find me a coder"
        let fingerprint = extractor.compactSentenceFingerprint(query)
        let sanitized = extractor.sanitizeText(
            query,
            role: .needText,
            sentenceFingerprint: fingerprint
        )
        XCTAssertNil(sanitized)
    }

    func testCompactComputerDoesNotRepairFail() {
        assertOfferObjectCompactMaps(query: "computer", object: "computer")
    }

    func testCompactCarDoesNotRepairFail() {
        assertOfferObjectCompactMaps(query: "car", object: "car")
    }

    func testCompactLaptopDoesNotRepairFail() {
        assertOfferObjectCompactMaps(query: "laptop", object: "laptop")
    }


    func testComputerBudgetTimeHireNormalizesToBuy() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let query = "find me a computer under 500 tomorrow"
        let json = """
        {"raw":"\(query)","object":"computer","need":null,"place":null,"time":"tomorrow","budget":"under 500","commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking computer with budget and time","transactionIntent":"hire"}
        """
        let canonical = extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: json,
            userText: query,
            intent: seedIntent(objective: query)
        )
        XCTAssertNotNil(canonical)
        XCTAssertEqual(canonical?.transactionIntent, .buy)
        let normalized = ExchangeOfferObjectLane.normalizeProductObjectTransactionForLiveInterpretation(
            canonical!,
            source: "unitTest"
        )
        XCTAssertEqual(normalized.transactionIntent, .buy)
        let thread = threadFromCanonical(normalized, query: query)
        XCTAssertTrue(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }

    func testComputerBudgetTimeObjectLaneFields() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let query = "computer under 500 tomorrow"
        let json = """
        {"raw":"\(query)","object":"computer","need":null,"place":null,"time":"tomorrow","budget":"under 500","commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking computer with budget and time"}
        """
        let canonical = extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: json,
            userText: query,
            intent: seedIntent(objective: query)
        )
        XCTAssertNotNil(canonical)
        XCTAssertEqual(canonical?.objectType, "computer")
        XCTAssertEqual(canonical?.domainCategory, .product)
        XCTAssertEqual(canonical?.transactionIntent, .buy)
        XCTAssertFalse(canonical?.commercialConstraints.isEmpty ?? true)
        XCTAssertFalse(canonical?.timeConstraints.isEmpty ?? true)

        let thread = threadFromCanonical(canonical!, query: query)
        XCTAssertTrue(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }

    func testFacetsIntentSync() async {
        let query = "computer"
        let json = """
        {"raw":"\(query)","object":"computer","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking computer offer"}
        """
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: FixtureJSONProvider(json: json)
        )
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: NoOpIntelligenceProvider(),
            asyncSearchIntentExtractor: extractor
        )
        let result = await interpreter.interpret(
            userText: query,
            threadContext: nil,
            entrySurface: .searchComposer
        )
        guard case .interpreted(let request) = result else {
            XCTFail("expected interpreted result")
            return
        }
        XCTAssertEqual(request.intent.queryIntentClass, request.facets.queryIntentClass)
        XCTAssertEqual(request.intent.queryIntentClass, .offerSearch)
        XCTAssertEqual(request.facets.searchIntent?.objectType, "computer")
    }



    func testFindMeACarFacetsIntentSync() async {
        let query = "find me a car"
        let json = """
        {"raw":"find me a car","object":"car","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking car offer"}
        """
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: FixtureJSONProvider(json: json)
        )
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: NoOpIntelligenceProvider(),
            asyncSearchIntentExtractor: extractor
        )
        let result = await interpreter.interpret(
            userText: query,
            threadContext: nil,
            entrySurface: .searchComposer
        )
        guard case .interpreted(let request) = result else {
            XCTFail("expected interpreted result")
            return
        }
        XCTAssertEqual(request.intent.queryIntentClass, .offerSearch)
        XCTAssertEqual(request.facets.searchIntent?.objectType, "car")
        XCTAssertEqual(request.facets.searchIntent?.domainCategory, .product)
        XCTAssertEqual(request.facets.searchIntent?.transactionIntent, .buy)
    }

    func testFindMeACarCompactObjectMapsToCanonical() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let query = "find me a car"
        let json = """
        {"raw":"find me a car","object":"car","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking car offer"}
        """
        let canonical = extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: json,
            userText: query,
            intent: seedIntent(objective: query)
        )
        XCTAssertNotNil(canonical)
        XCTAssertEqual(canonical?.objectType, "car")
        XCTAssertEqual(canonical?.domainCategory, .product)
        XCTAssertEqual(canonical?.transactionIntent, .buy)
        XCTAssertEqual(canonical?.extractedRoute?.routeClassRaw, "offerSearch")
        XCTAssertEqual(canonical?.extractedRoute?.surfacePreferenceRaw, "offer")

        let thread = threadFromCanonical(canonical!, query: query)
        XCTAssertTrue(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
        XCTAssertEqual(ExchangeOfferObjectLane.queryObjectText(thread: thread), "car")
    }

    func testAtomicObjectNotFingerprintStrippedWhenQueryMatchesObject() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let fingerprint = extractor.compactSentenceFingerprint("car")
        let preserved = extractor.preservedFlatObjectText("car")
        XCTAssertEqual(preserved, "car")
        let resolved = extractor.resolvedFlatObjectType(rawObjectText: "car", sentenceFingerprint: fingerprint)
        XCTAssertEqual(resolved, "car")
    }

    func testCleanerQueryDoesNotCoerceToProductBuy() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let query = "find me a cleaner tomorrow at 2 under 200"
        let json = """
        {"raw":"\(query)","object":"cleaner","need":null,"place":null,"time":"tomorrow at 2","budget":"under 200","commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking cleaner service","transactionIntent":"hire"}
        """
        let canonical = extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: json,
            userText: query,
            intent: seedIntent(objective: query)
        )
        XCTAssertNotNil(canonical)
        XCTAssertNotEqual(canonical?.domainCategory, .product)
        XCTAssertEqual(canonical?.transactionIntent, .hire)
        let thread = threadFromCanonicalProvider(canonical!, query: query)
        XCTAssertFalse(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }

    func testCleanerHireRouteUnchanged() throws {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let query = "find me a cleaner tomorrow at 2 under 200"
        let json = """
        {"raw":"\(query)","object":"cleaner","need":null,"place":null,"time":"tomorrow at 2","budget":"under 200","commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking cleaner service","transactionIntent":"hire"}
        """
        let canonical = try XCTUnwrap(
            extractor.processSearchIntentFlatPipelineCanonical(
                cleaned: json,
                userText: query,
                intent: seedIntent(objective: query)
            )
        )
        XCTAssertEqual(canonical.transactionIntent, .hire)
        let thread = threadFromCanonicalProvider(canonical, query: query)
        XCTAssertFalse(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))

        let legacy = SearchIntentRouteValidator.legacyQuerySurfaceTargetRouting(from: canonical)
        let resolved = SearchIntentRouteValidator.resolvedRouting(from: canonical, legacy: legacy)
        XCTAssertEqual(resolved.queryClass, .providerSearch)
        XCTAssertEqual(resolved.surface, .offer)
    }

    func testDeliveryProviderSearchRouteDoesNotTransientAbort() throws {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let query = "who can deliver this?"
        let json = """
        {"raw":"\(query)","object":"this","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.85,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.88,"routeRationale":"delivery provider lookup"}
        """
        let canonical = try XCTUnwrap(
            extractor.processSearchIntentFlatPipelineCanonical(
                cleaned: json,
                userText: query,
                intent: seedIntent(objective: query)
            )
        )
        XCTAssertEqual(canonical.extractedRoute?.routeClassRaw, "providerSearch")
        XCTAssertEqual(canonical.extractedRoute?.surfacePreferenceRaw, "offer")
        XCTAssertTrue(extractor.isMateriallyActionable(canonical))

        let legacy = SearchIntentRouteValidator.legacyQuerySurfaceTargetRouting(from: canonical)
        let resolved = SearchIntentRouteValidator.resolvedRouting(from: canonical, legacy: legacy)
        XCTAssertEqual(resolved.queryClass, .providerSearch)
        XCTAssertEqual(resolved.surface, .offer)
        XCTAssertEqual(resolved.source, .llmRoute)

        let thread = threadFromCanonicalProvider(canonical, query: query)
        XCTAssertFalse(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }


    func testHireNeedVetoesSocialAffinityRoute() {
        let canonical = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: "person",
            transactionIntent: .hire,
            broadRecallTokens: ["repair laptop", "person"],
            semanticConcepts: ["repair laptop"],
            rawUserText: "find me someone who repairs laptops",
            extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute(
                routeClassRaw: "socialAffinitySearch",
                surfacePreferenceRaw: "affinity",
                targetKindRaw: "person",
                modeRaw: "relational",
                routeConfidence: 0.92
            )
        )
        let legacy = SearchIntentRouteValidator.legacyQuerySurfaceTargetRouting(from: canonical)
        let resolved = SearchIntentRouteValidator.resolve(from: canonical, legacy: legacy)
        XCTAssertEqual(resolved.rejectionReason, .hardCommercialContradiction)
        XCTAssertEqual(resolved.routing.source, .legacy)
        XCTAssertEqual(resolved.routing.queryClass, .providerSearch)
        XCTAssertEqual(resolved.routing.surface, .offer)
        XCTAssertNotEqual(resolved.routing.surface, .affinity)
    }


    func testFindMeACarGeneralDiscoveryCompactRouteRepairPreservesObjectForOfferSearch() async throws {
        let query = "find me a car"
        let provider = SpyIntelligenceProvider(shouldFailIfCalled: true)
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: provider,
            asyncSearchIntentExtractor: RejectedCompactCarAsyncExtractor()
        )
        let result = await interpreter.interpret(
            userText: query,
            threadContext: nil,
            entrySurface: .searchComposer
        )
        guard case .interpreted(let request) = result else {
            XCTFail("expected interpreted canonical-first route repair result")
            return
        }
        XCTAssertEqual(provider.classifyIntentFastCallCount, 0)
        XCTAssertEqual(provider.interpretCallCount, 0)
        XCTAssertEqual(request.intent.queryIntentClass, .offerSearch)
        XCTAssertEqual(request.intent.surfacePreference, .offer)
        XCTAssertEqual(request.facets.searchIntent?.objectType, "car")
        XCTAssertEqual(request.facets.searchIntent?.domainCategory, .product)
        XCTAssertEqual(request.facets.searchIntent?.transactionIntent, .buy)
        XCTAssertEqual(ExchangeOfferObjectLane.queryObjectText(from: request.facets.searchIntent!), "car")
        let thread = threadFromCanonical(request.facets.searchIntent!, query: query)
        XCTAssertTrue(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }

    func testFindMeACarRealCompactMalformedRouteRepairWithoutProviderFallback() async throws {
        let query = "find me a car"
        let json = """
        {"raw":"find me a car","object":"car","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.9,"routeClass":"generalDiscovery","surfacePreference":"mixed","targetKind":"unknown","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking car"}
        """
        let provider = SpyIntelligenceProvider(shouldFailIfCalled: true)
        let extractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: FixtureJSONProvider(json: json)
        )
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: provider,
            asyncSearchIntentExtractor: extractor
        )
        let result = await interpreter.interpret(
            userText: query,
            threadContext: nil,
            entrySurface: .searchComposer
        )
        guard case .interpreted(let request) = result else {
            XCTFail("expected interpreted canonical-first route repair result")
            return
        }
        XCTAssertEqual(provider.classifyIntentFastCallCount, 0)
        XCTAssertEqual(request.intent.queryIntentClass, .offerSearch)
        XCTAssertEqual(request.intent.surfacePreference, .offer)
        XCTAssertEqual(request.facets.searchIntent?.objectType, "car")
        XCTAssertEqual(request.facets.searchIntent?.domainCategory, .product)
        XCTAssertEqual(request.facets.searchIntent?.transactionIntent, .buy)
        let thread = threadFromCanonical(request.facets.searchIntent!, query: query)
        XCTAssertTrue(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
        let retrievalQuery = ExchangeRetrievalQueryBuilder().build(from: thread)
        XCTAssertEqual(retrievalQuery.queryObjectText, "car")
    }

    func testCleanerGeneralDiscoveryRouteRepairPreservesHireNotBuy() async throws {
        let query = "find me a cleaner tomorrow at 2 under 200"
        let provider = SpyIntelligenceProvider(shouldFailIfCalled: true)
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: provider,
            asyncSearchIntentExtractor: RejectedCompactCleanerAsyncExtractor()
        )
        let result = await interpreter.interpret(
            userText: query,
            threadContext: nil,
            entrySurface: .searchComposer
        )
        guard case .interpreted(let request) = result else {
            XCTFail("expected interpreted canonical-first route repair result")
            return
        }
        XCTAssertEqual(provider.classifyIntentFastCallCount, 0)
        XCTAssertEqual(request.intent.queryIntentClass, .providerSearch)
        XCTAssertEqual(request.intent.surfacePreference, .offer)
        XCTAssertEqual(request.facets.searchIntent?.objectType, "cleaner")
        XCTAssertEqual(request.facets.searchIntent?.transactionIntent, .hire)
        XCTAssertNotEqual(request.facets.searchIntent?.domainCategory, .product)
        let thread = threadFromCanonicalProvider(request.facets.searchIntent!, query: query)
        XCTAssertFalse(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread))
    }

    func testSocialMalformedRouteDoesNotRepairToOfferSearch() async {
        let query = "find friends nearby"
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: NoOpIntelligenceProvider(),
            asyncSearchIntentExtractor: RejectedCompactSocialAsyncExtractor()
        )
        let result = await interpreter.interpret(
            userText: query,
            threadContext: nil,
            entrySurface: .searchComposer
        )
        guard case .interpreted(let request) = result else {
            XCTFail("expected interpreted fallback result")
            return
        }
        XCTAssertNotEqual(request.intent.queryIntentClass, .offerSearch)
    }

    func testMalformedRouteWithoutObjectAllowsProviderFallback() async {
        let provider = SpyIntelligenceProvider(shouldFailIfCalled: false)
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: provider,
            asyncSearchIntentExtractor: RejectedCompactNoObjectAsyncExtractor()
        )
        _ = await interpreter.interpret(
            userText: "find something nearby",
            threadContext: nil,
            entrySurface: .searchComposer
        )
        XCTAssertGreaterThanOrEqual(provider.classifyIntentFastCallCount, 0)
    }

    func testRouteRepairedCarFacetsPersistForRetrievalHandoff() async {
        let query = "find me a car"
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: SpyIntelligenceProvider(shouldFailIfCalled: true),
            asyncSearchIntentExtractor: RejectedCompactCarAsyncExtractor()
        )
        let result = await interpreter.interpret(
            userText: query,
            threadContext: nil,
            entrySurface: .searchComposer
        )
        guard case .interpreted(let request) = result else {
            XCTFail("expected interpreted result")
            return
        }
        XCTAssertEqual(request.facets.searchIntent?.objectType, "car")
        let thread = ExchangeThread(
            id: UUID(),
            mode: .transactional,
            intent: request.intent,
            posture: .cautious,
            facets: request.facets,
            state: .searching(.init())
        )
        let retrievalQuery = ExchangeRetrievalQueryBuilder().build(from: thread)
        XCTAssertEqual(retrievalQuery.queryObjectText, "car")
        XCTAssertEqual(retrievalQuery.queryIntentClass, .offerSearch)
    }

        func testProductBuyLaneUnchanged() throws {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        for (query, object) in [("find me a car", "car"), ("computer under 500 tomorrow", "computer")] {
            let json = """
            {"raw":"\(query)","object":"\(object)","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking \(object) offer"}
            """
            let canonical = try XCTUnwrap(
                extractor.processSearchIntentFlatPipelineCanonical(
                    cleaned: json,
                    userText: query,
                    intent: seedIntent(objective: query)
                )
            )
            XCTAssertEqual(canonical.transactionIntent, .buy, "expected buy for \(query)")
            let thread = threadFromCanonical(canonical, query: query)
            XCTAssertTrue(ExchangeOfferObjectLane.isObjectLaneActive(thread: thread), "expected object lane for \(query)")
        }
    }

    private func assertOfferObjectCompactMaps(query: String, object: String) {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let json = """
        {"raw":"\(query)","object":"\(object)","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking \(object) offer"}
        """
        let canonical = extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: json,
            userText: query,
            intent: seedIntent(objective: query)
        )
        XCTAssertNotNil(canonical, "expected compact mapping for \(query)")
        XCTAssertEqual(canonical?.objectType, object)
        XCTAssertEqual(canonical?.domainCategory, .product)
        XCTAssertEqual(canonical?.transactionIntent, .buy)
    }


    private func threadFromCanonicalProvider(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        query: String
    ) -> ExchangeThread {
        var facets = ExchangeIntentFacets(
            queryIntentClass: .providerSearch,
            surfacePreference: .offer
        )
        facets.searchIntent = canonical
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: query,
            objective: query
        )
        return ExchangeThread(
            id: UUID(),
            mode: .transactional,
            intent: intent,
            posture: .cautious,
            facets: facets,
            state: .searching(.init())
        )
    }

    private func seedIntent(objective: String) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "test",
            objective: objective
        )
    }

    private func threadFromCanonical(
        _ canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        query: String
    ) -> ExchangeThread {
        var facets = ExchangeIntentFacets(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer
        )
        facets.searchIntent = canonical
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            title: query,
            objective: query
        )
        return ExchangeThread(
            id: UUID(),
            mode: .transactional,
            intent: intent,
            posture: .cautious,
            facets: facets,
            state: .searching(.init())
        )
    }
}


private final class SpyIntelligenceProvider: ExchangeIntelligenceProvider, @unchecked Sendable {
    var shouldFailIfCalled: Bool
    private(set) var classifyIntentFastCallCount = 0
    private(set) var interpretCallCount = 0

    init(shouldFailIfCalled: Bool) {
        self.shouldFailIfCalled = shouldFailIfCalled
    }

    func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse {
        classifyIntentFastCallCount += 1
        if shouldFailIfCalled {
            XCTFail("classifyIntentFast should not be called")
        }
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
        if shouldFailIfCalled {
            XCTFail("interpret should not be called")
        }
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

private struct FixtureJSONProvider: AsyncSearchIntentJSONProvider {
    var json: String
    func isReadyForImmediateExtraction() async -> Bool { true }
    func extractSearchIntentJSON(prompt: String) async throws -> String { json }
}

private struct NoOpIntelligenceProvider: ExchangeIntelligenceProvider {
    func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse {
        ExchangeIntelligenceFastClassificationResponse(
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
        ExchangeIntelligenceInterpretationResponse(
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


private final class RejectedCompactCarAsyncExtractor: AsyncOpenEndedSearchIntentExtractor, @unchecked Sendable {
    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: "car",
            broadRecallTokens: ["car"],
            semanticConcepts: ["car"],
            rawUserText: sourceText,
            extractionSource: .llmFlatSummary,
            extractionConfidence: 0.9,
            extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute(
                routeClassRaw: "generalDiscovery",
                surfacePreferenceRaw: "mixed",
                targetKindRaw: nil,
                modeRaw: "transactional",
                routeConfidence: 0.85
            )
        )
    }
}

private final class RejectedCompactCleanerAsyncExtractor: AsyncOpenEndedSearchIntentExtractor, @unchecked Sendable {
    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: "cleaner",
            transactionIntent: .hire,
            timeConstraints: [
                ExchangeIntentFacets.StructuredTimeConstraint(kind: .specific, text: "tomorrow at 2")
            ],
            commercialConstraints: [
                ExchangeIntentFacets.StructuredCommercialConstraint(kind: .budget, key: "budget", value: "under 200")
            ],
            broadRecallTokens: ["cleaner"],
            semanticConcepts: ["cleaner"],
            rawUserText: sourceText,
            extractionSource: .llmFlatSummary,
            extractionConfidence: 0.9,
            extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute(
                routeClassRaw: "generalDiscovery",
                surfacePreferenceRaw: "mixed",
                targetKindRaw: nil,
                modeRaw: "transactional",
                routeConfidence: 0.85
            )
        )
    }
}

private final class RejectedCompactSocialAsyncExtractor: AsyncOpenEndedSearchIntentExtractor, @unchecked Sendable {
    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            objectType: "friends",
            broadRecallTokens: ["friends"],
            semanticConcepts: ["friends"],
            rawUserText: sourceText,
            extractionSource: .llmFlatSummary,
            extractionConfidence: 0.9,
            extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute(
                routeClassRaw: "socialAffinitySearch",
                surfacePreferenceRaw: "affinity",
                targetKindRaw: "person",
                modeRaw: "relational",
                routeConfidence: 0.9
            )
        )
    }
}

private final class RejectedCompactNoObjectAsyncExtractor: AsyncOpenEndedSearchIntentExtractor, @unchecked Sendable {
    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .general,
            broadRecallTokens: ["nearby"],
            semanticConcepts: ["nearby"],
            rawUserText: sourceText,
            extractionSource: .llmFlatSummary,
            extractionConfidence: 0.9,
            extractedRoute: ExchangeIntentFacets.ExtractedSearchRoute(
                routeClassRaw: "generalDiscovery",
                surfacePreferenceRaw: "mixed",
                targetKindRaw: nil,
                modeRaw: "transactional",
                routeConfidence: 0.85
            )
        )
    }
}

private struct OfferSearchCarFallbackProvider: ExchangeIntelligenceProvider {
    func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse {
        ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            mode: .transactional,
            kind: .find,
            readiness: .ready,
            confidence: 0.85,
            needsFullLLMInterpretation: true
        )
    }

    func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        ExchangeIntelligenceInterpretationResponse(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            mode: .transactional,
            kind: .find,
            title: "Find car",
            objective: request.userText,
            constraints: [],
            desiredOutcomes: [.shortlist],
            readiness: .ready,
            confidence: 0.85,
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

private struct ProviderSearchCleanerFallbackProvider: ExchangeIntelligenceProvider {
    func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse {
        ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            mode: .transactional,
            kind: .find,
            readiness: .ready,
            confidence: 0.85,
            needsFullLLMInterpretation: true
        )
    }

    func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        ExchangeIntelligenceInterpretationResponse(
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            mode: .transactional,
            kind: .find,
            title: "Find cleaner",
            objective: request.userText,
            constraints: [],
            desiredOutcomes: [.shortlist],
            readiness: .ready,
            confidence: 0.85,
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
