import XCTest

@testable import AnumCore

final class ExchangeRetrievalQueryBuilderCanonicalTaskPhraseTests: XCTestCase {

    func testPlumberLeakRepairBroadQueryAndKeywords() throws {
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "plumber",
            transactionIntent: .hire,
            places: [
                .init(normalizedText: "Austin", aliases: [], confidence: 0.9, isHard: true)
            ],
            broadRecallTokens: ["leak repair"],
            semanticConcepts: ["leak repair"],
            extractionSource: .llmFlatSummary
        )
        let query = buildCanonicalQuery(searchIntent: si, queryIntentClass: .offerSearch)

        let queryText = try XCTUnwrap(query.queryText)
        XCTAssertTrue(queryText.lowercased().contains("plumber"), queryText)
        XCTAssertTrue(queryText.lowercased().contains("leak repair"), queryText)
        XCTAssertTrue(
            queryText.lowercased().contains("plumber services for leak repair near austin"),
            "queryText=\(queryText)"
        )

        let semantic = try XCTUnwrap(query.semanticText)
        XCTAssertTrue(semantic.lowercased().contains("leak repair"), semantic)

        XCTAssertTrue(
            query.keywords.contains { $0.lowercased().contains("leak") },
            "keywords=\(query.keywords)"
        )
    }

    func testSpanishTutorConversationalPracticeBroadQuery() throws {
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .professionalService,
            objectType: "Spanish tutor",
            transactionIntent: .hire,
            broadRecallTokens: ["remote"],
            semanticConcepts: ["conversational practice"],
            extractionSource: .llmFlatSummary
        )
        let query = buildCanonicalQuery(searchIntent: si, queryIntentClass: .offerSearch)

        let queryText = try XCTUnwrap(query.queryText)
        XCTAssertTrue(queryText.lowercased().contains("conversational practice"), queryText)

        let semantic = try XCTUnwrap(query.semanticText)
        XCTAssertTrue(semantic.lowercased().contains("conversational practice"), semantic)
    }

    func testDirectoryTagsIncludeSemanticTaskMissingFromBroadRecall() {
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "contractor",
            transactionIntent: .hire,
            places: [
                .init(normalizedText: "Chaoyang", aliases: ["北京"], confidence: 0.9, isHard: false)
            ],
            broadRecallTokens: ["北京"],
            semanticConcepts: ["kitchen remodel"],
            extractionSource: .llmFlatSummary
        )
        let thread = threadWithCanonicalSearchIntent(si, queryIntentClass: .offerSearch)
        let plan = ExchangeDiscoveryEngine.SearchPlan.build(for: thread)

        XCTAssertTrue(plan.usesCanonicalDirectoryRecall)
        XCTAssertTrue(
            plan.canonicalDirectoryRequestTags.contains { $0.lowercased().contains("kitchen remodel") },
            "tags=\(plan.canonicalDirectoryRequestTags)"
        )
    }

    func testNegativeTimePlaceBudgetNotAppendedAsTaskClause() throws {
        let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "plumber",
            transactionIntent: .hire,
            places: [
                .init(normalizedText: "Austin", aliases: [], confidence: 0.9, isHard: true)
            ],
            timeConstraints: [.init(kind: .specific, text: "tomorrow afternoon")],
            commercialConstraints: [
                .init(kind: .budget, key: "budget", value: "under 500 dollars", isHard: false)
            ],
            broadRecallTokens: ["Austin"],
            semanticConcepts: ["tomorrow afternoon", "Austin", "under 500 dollars"],
            extractionSource: .llmFlatSummary
        )
        let query = buildCanonicalQuery(searchIntent: si, queryIntentClass: .offerSearch)
        let queryText = try XCTUnwrap(query.queryText)

        XCTAssertFalse(queryText.lowercased().contains("for tomorrow"), queryText)
        XCTAssertFalse(queryText.lowercased().contains("for austin"), queryText)
        XCTAssertFalse(queryText.lowercased().contains("500 dollars"), queryText)
        XCTAssertTrue(
            queryText.lowercased().contains("plumber services near austin"),
            "queryText=\(queryText)"
        )
    }

    // MARK: - Fixtures

    private func buildCanonicalQuery(
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        queryIntentClass: ExchangeIntent.QueryIntentClass
    ) -> ExchangeRetrievalQuery {
        let thread = threadWithCanonicalSearchIntent(searchIntent, queryIntentClass: queryIntentClass)
        return ExchangeRetrievalQueryBuilder().build(from: thread)
    }

    private func threadWithCanonicalSearchIntent(
        _ searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        queryIntentClass: ExchangeIntent.QueryIntentClass
    ) -> ExchangeThread {
        let facets = ExchangeIntentFacets(
            searchIntent: searchIntent,
            queryIntentClass: queryIntentClass,
            surfacePreference: .offer,
            providerTerms: [searchIntent.objectType].compactMap { $0 },
            regionTerms: searchIntent.places.map(\.normalizedText)
        )
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: queryIntentClass,
            surfacePreference: .offer,
            title: "Find match",
            objective: "Find a provider"
        )
        return ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(privacy: .balanced),
            facets: facets,
            state: .searching(.init())
        )
    }
}
