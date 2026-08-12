import XCTest
@testable import AnumCore

final class SearchIntentRouteValidatorTests: XCTestCase {
    func testDecodeRouteFieldsFromLLMJSON() throws {
        let canonical = try XCTUnwrap(pipelineCanonical(
            json: SearchIntentRouteTestFixtures.photographyPeopleJSON,
            userText: "Find people interested in photography in Aurora"
        ))
        let route = try XCTUnwrap(canonical.extractedRoute)
        XCTAssertEqual(route.routeClassRaw, "socialAffinitySearch")
        XCTAssertEqual(route.surfacePreferenceRaw, "affinity")
        XCTAssertEqual(route.targetKindRaw, "person")
        XCTAssertEqual(route.modeRaw, "relational")
        XCTAssertEqual(route.routeConfidence ?? 0, 0.91, accuracy: 0.001)
    }

    func testLegacyJSONWithoutRouteFieldsStillDecodes() throws {
        let canonical = try XCTUnwrap(pipelineCanonical(
            json: SearchIntentRouteTestFixtures.legacyPhotographyJSON,
            userText: "Find people interested in photography in Aurora"
        ))
        XCTAssertNil(canonical.extractedRoute)
    }

    func testPhotographyPeopleRoutesSocial() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.photographyPeopleJSON,
            userText: "Find people interested in photography in Aurora",
            expectedQueryClass: .socialAffinitySearch,
            expectedSurface: .affinity,
            expectedTargetKind: .person,
            expectedMode: .relational,
            expectedLane: .socialConnection,
            expectedRouteSource: .llmRoute
        )
    }

    func testPhotographyEnthusiastsRoutesSocial() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.photographyEnthusiastsJSON,
            userText: "Find photography enthusiasts in Aurora",
            expectedQueryClass: .socialAffinitySearch,
            expectedSurface: .affinity,
            expectedTargetKind: .person,
            expectedMode: .relational,
            expectedLane: .socialConnection,
            expectedRouteSource: .llmRoute
        )
    }

    func testProductPhotographerRoutesCommercial() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.productPhotographerJSON,
            userText: "Find a photographer for product photos in Aurora",
            expectedQueryClass: .providerSearch,
            expectedSurface: .offer,
            expectedTargetKind: .provider,
            expectedMode: .transactional,
            expectedLane: .commercialInquiry,
            expectedRouteSource: .llmRoute
        )
    }

    func testRooferAppraisalRoutesCommercial() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.rooferAppraisalJSON,
            userText: "Find a roofer for an appraisal tomorrow at 2pm",
            expectedQueryClass: .providerSearch,
            expectedSurface: .offer,
            expectedTargetKind: .provider,
            expectedMode: .transactional,
            expectedLane: .commercialInquiry,
            expectedRouteSource: .llmRoute
        )
    }

    func testInvalidLowConfidenceRouteFallsBack() throws {
        let canonical = try XCTUnwrap(pipelineCanonical(
            json: SearchIntentRouteTestFixtures.invalidSocialLowConfidenceJSON,
            userText: "Find people interested in photography in Aurora"
        ))
        let legacy = legacyRouting(from: canonical)
        let resolved = SearchIntentRouteValidator.resolvedRouting(from: canonical, legacy: legacy)
        XCTAssertEqual(resolved.source, SearchIntentRouteValidator.ResolutionSource.legacy)
        XCTAssertEqual(resolved.queryClass, legacy.queryClass)
    }

    func testSocialRouteInterpretationUsesAffinityTerms() async throws {
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: ExchangeFallbackIntelligenceProvider(),
            searchIntentExtractor: CanonicalSearchIntentHeuristicExtractor(),
            asyncSearchIntentExtractor: RouteFixtureAsyncExtractor(
                json: SearchIntentRouteTestFixtures.photographyPeopleJSON
            )
        )

        let result = await interpreter.interpret(
            userText: "Find people interested in photography in Aurora",
            threadContext: nil
        )

        guard case .interpreted(let request) = result else {
            return XCTFail("expected interpreted result")
        }

        XCTAssertEqual(request.intent.queryIntentClass, .socialAffinitySearch)
        XCTAssertEqual(request.intent.mode, .relational)
        XCTAssertEqual(ExchangeThreadLaneResolver.lane(for: request.intent), .socialConnection)
        XCTAssertTrue(request.facets.affinityTerms.contains(where: { $0.lowercased().contains("photography") }))
        XCTAssertTrue(request.facets.providerTerms.isEmpty)
    }

    // MARK: - Helpers

    private func pipelineCanonical(
        json: String,
        userText: String
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        let extractor = LLMOpenEndedSearchIntentExtractor(jsonProvider: nil)
        return extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: json,
            userText: userText,
            intent: seedIntent()
        )
    }

    private func assertRouting(
        json: String,
        userText: String,
        expectedQueryClass: ExchangeIntent.QueryIntentClass,
        expectedSurface: ExchangeIntent.SurfacePreference,
        expectedTargetKind: ExchangeIntentFacets.TargetKind,
        expectedMode: ExchangeMode,
        expectedLane: ExchangeThreadLane,
        expectedRouteSource: SearchIntentRouteValidator.ResolutionSource,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let canonical = try XCTUnwrap(pipelineCanonical(json: json, userText: userText), file: file, line: line)
        let legacy = legacyRouting(from: canonical)
        let resolved = SearchIntentRouteValidator.resolvedRouting(from: canonical, legacy: legacy)

        XCTAssertEqual(resolved.queryClass, expectedQueryClass, file: file, line: line)
        XCTAssertEqual(resolved.surface, expectedSurface, file: file, line: line)
        XCTAssertEqual(resolved.targetKind, expectedTargetKind, file: file, line: line)
        XCTAssertEqual(resolved.modeOverride ?? inferExpectedMode(for: expectedQueryClass), expectedMode, file: file, line: line)
        XCTAssertEqual(resolved.source, expectedRouteSource, file: file, line: line)

        let intent = ExchangeIntent(
            kind: .find,
            mode: resolved.modeOverride ?? expectedMode,
            queryIntentClass: resolved.queryClass,
            surfacePreference: resolved.surface,
            title: "Test",
            objective: "Test objective"
        )
        XCTAssertEqual(ExchangeThreadLaneResolver.lane(for: intent), expectedLane, file: file, line: line)
    }

    private func legacyRouting(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> (
        queryClass: ExchangeIntent.QueryIntentClass,
        surface: ExchangeIntent.SurfacePreference,
        targetKind: ExchangeIntentFacets.TargetKind
    ) {
        switch canonical.domainCategory {
        case .homeService, .professionalService:
            return (.providerSearch, .offer, .provider)
        case .realEstate, .product:
            return (.offerSearch, .offer, .business)
        case .general:
            if let tx = canonical.transactionIntent {
                switch tx {
                case .hire, .book, .inquire:
                    return (.providerSearch, .offer, .provider)
                case .buy, .forSale, .rent:
                    return (.offerSearch, .offer, .provider)
                }
            }
            let trimmedObject = canonical.objectType?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedObject, !trimmedObject.isEmpty {
                return (.generalDiscovery, .mixed, .unknown)
            }
            return (.generalDiscovery, .mixed, .unknown)
        }
    }

    private func inferExpectedMode(for queryClass: ExchangeIntent.QueryIntentClass) -> ExchangeMode {
        switch queryClass {
        case .socialAffinitySearch, .relationshipSearch:
            return .relational
        default:
            return .transactional
        }
    }

    private func seedIntent() -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            title: "Test",
            objective: "Test objective"
        )
    }


    func testCampingFriendNextMonthRoutesSocialDespiteFindMeAndSchedule() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.campingFriendNextMonthJSON,
            userText: "Find me a camping friend who wants to go on a camping trip next month",
            expectedQueryClass: .socialAffinitySearch,
            expectedSurface: .affinity,
            expectedTargetKind: .person,
            expectedMode: .relational,
            expectedLane: .socialConnection,
            expectedRouteSource: .llmRoute
        )
    }

    func testRentCampingGearFromRoutesCommercialProvider() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.rentCampingGearFromJSON,
            userText: "Find someone to rent camping gear from next month",
            expectedQueryClass: .providerSearch,
            expectedSurface: .offer,
            expectedTargetKind: .provider,
            expectedMode: .transactional,
            expectedLane: .commercialInquiry,
            expectedRouteSource: .llmRoute
        )
    }

    func testBookCampingGuideNextMonthRoutesCommercialProvider() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.bookCampingGuideNextMonthJSON,
            userText: "Find a camping guide I can book next month",
            expectedQueryClass: .providerSearch,
            expectedSurface: .offer,
            expectedTargetKind: .provider,
            expectedMode: .transactional,
            expectedLane: .commercialInquiry,
            expectedRouteSource: .llmRoute
        )
    }

    func testCampingFriendNextMonthInterpretationUsesSocialAffinityRails() async throws {
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: ExchangeFallbackIntelligenceProvider(),
            searchIntentExtractor: CanonicalSearchIntentHeuristicExtractor(),
            asyncSearchIntentExtractor: RouteFixtureAsyncExtractor(
                json: SearchIntentRouteTestFixtures.campingFriendNextMonthJSON
            )
        )

        let result = await interpreter.interpret(
            userText: "Find me a camping friend who wants to go on a camping trip next month",
            threadContext: nil
        )

        guard case .interpreted(let request) = result else {
            return XCTFail("expected interpreted result")
        }

        XCTAssertEqual(request.intent.queryIntentClass, .socialAffinitySearch)
        XCTAssertEqual(request.intent.mode, .relational)
        XCTAssertEqual(request.intent.surfacePreference, .affinity)
        XCTAssertEqual(request.facets.targetKind, .person)
        XCTAssertNotEqual(request.intent.title, "Find Provider")
        XCTAssertTrue(request.facets.providerTerms.isEmpty)
        XCTAssertTrue(request.facets.affinityTerms.contains(where: { $0.lowercased().contains("camping") }))
        XCTAssertEqual(ExchangeThreadLaneResolver.lane(for: request.intent), .socialConnection)
    }
    func testCampingFriendRoutesSocialDespiteSchedule() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.campingFriendJSON,
            userText: "Find a friend for a camping trip this weekend",
            expectedQueryClass: .socialAffinitySearch,
            expectedSurface: .affinity,
            expectedTargetKind: .person,
            expectedMode: .relational,
            expectedLane: .socialConnection,
            expectedRouteSource: .llmRoute
        )
    }

    func testCampingGearRentalRoutesCommercialProvider() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.campingGearRentalProviderJSON,
            userText: "Find camping gear rental in Aurora",
            expectedQueryClass: .providerSearch,
            expectedSurface: .offer,
            expectedTargetKind: .provider,
            expectedMode: .transactional,
            expectedLane: .commercialInquiry,
            expectedRouteSource: .llmRoute
        )
    }

    func testCampingGearRentalWrongSocialRouteRejectedByCommercialGuardrail() throws {
        let canonical = try XCTUnwrap(pipelineCanonical(
            json: SearchIntentRouteTestFixtures.campingGearRentalWrongSocialJSON,
            userText: "Find camping gear rental in Aurora"
        ))
        let legacy = legacyRouting(from: canonical)
        XCTAssertEqual(legacy.queryClass, .providerSearch)
        let resolved = SearchIntentRouteValidator.resolve(from: canonical, legacy: legacy)
        XCTAssertEqual(resolved.rejectionReason, .hardCommercialContradiction)
        XCTAssertEqual(resolved.routing.source, .legacy)
        XCTAssertEqual(resolved.routing.queryClass, .providerSearch)
    }

    func testBookCampingGuideRoutesCommercialProvider() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.bookCampingGuideJSON,
            userText: "Book a camping guide for a guided camping trip in Colorado",
            expectedQueryClass: .providerSearch,
            expectedSurface: .offer,
            expectedTargetKind: .provider,
            expectedMode: .transactional,
            expectedLane: .commercialInquiry,
            expectedRouteSource: .llmRoute
        )
    }

    func testSocialRouteAcceptedDespiteLegacyProviderSearchInference() throws {
        let canonical = try XCTUnwrap(pipelineCanonical(
            json: SearchIntentRouteTestFixtures.movieAuroraSocialJSON,
            userText: "Find someone who wants to watch a movie tomorrow in Aurora"
        ))
        let legacy = legacyRouting(from: canonical)
        XCTAssertEqual(legacy.queryClass, .providerSearch)
        let resolved = SearchIntentRouteValidator.resolvedRouting(from: canonical, legacy: legacy)
        XCTAssertEqual(resolved.source, .llmRoute)
        XCTAssertEqual(resolved.queryClass, .socialAffinitySearch)
        XCTAssertEqual(resolved.targetKind, .person)
        XCTAssertFalse(SearchIntentRouteValidator.canonicalHasHardCommercialContradiction(canonical))
    }

    func testRentCampingGearWrongSocialRouteRejectedByStructuredNeedLexicon() throws {
        let canonical = try XCTUnwrap(pipelineCanonical(
            json: SearchIntentRouteTestFixtures.rentCampingGearWrongSocialJSON,
            userText: "Find someone to rent camping gear from next month"
        ))
        let legacy = legacyRouting(from: canonical)
        let resolved = SearchIntentRouteValidator.resolve(from: canonical, legacy: legacy)
        XCTAssertEqual(resolved.rejectionReason, .hardCommercialContradiction)
        XCTAssertEqual(resolved.routing.source, .legacy)
        XCTAssertEqual(resolved.routing.queryClass, .providerSearch)
    }

    func testMovieTomorrowAuroraValidatesSocialRouteDespiteTimeAndPlace() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.movieAuroraSocialJSON,
            userText: "Find someone who wants to watch a movie tomorrow in Aurora",
            expectedQueryClass: .socialAffinitySearch,
            expectedSurface: .affinity,
            expectedTargetKind: .person,
            expectedMode: .relational,
            expectedLane: .socialConnection,
            expectedRouteSource: .llmRoute
        )
    }

    func testRooferTomorrowAuroraValidatesCommercialRouteWithTime() throws {
        try assertRouting(
            json: SearchIntentRouteTestFixtures.rooferAuroraTomorrowJSON,
            userText: "Find a roofer in Aurora tomorrow at 2pm for an appraisal",
            expectedQueryClass: .providerSearch,
            expectedSurface: .offer,
            expectedTargetKind: .provider,
            expectedMode: .transactional,
            expectedLane: .commercialInquiry,
            expectedRouteSource: .llmRoute
        )
    }

    func testSocialRouteRejectedForCommercialCanonicalDespiteHighRouteConfidence() throws {
        let canonical = try XCTUnwrap(pipelineCanonical(
            json: SearchIntentRouteTestFixtures.movieAuroraSocialJSON,
            userText: "Find someone who wants to watch a movie tomorrow in Aurora"
        ))
        var commercialCanonical = canonical
        commercialCanonical.domainCategory = .homeService

        let legacy = legacyRouting(from: commercialCanonical)
        let resolved = SearchIntentRouteValidator.resolve(from: commercialCanonical, legacy: legacy)
        XCTAssertEqual(resolved.rejectionReason, .hardCommercialContradiction)
        XCTAssertEqual(resolved.routing.source, .legacy)
    }

}

private struct RouteFixtureAsyncExtractor: AsyncOpenEndedSearchIntentExtractor {
    let json: String

    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        let extractor = LLMOpenEndedSearchIntentExtractor(
            jsonProvider: RouteFixtureJSONProvider(json: json)
        )
        return extractor.extract(sourceText: sourceText, intent: intent)
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
