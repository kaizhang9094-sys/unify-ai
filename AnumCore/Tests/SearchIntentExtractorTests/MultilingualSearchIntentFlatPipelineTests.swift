import XCTest
@testable import AnumCore

final class MultilingualSearchIntentFlatPipelineTests: XCTestCase {
    private let chineseRooferQuery =
        "帮我找一个明天下午2点能来Aurora估价、预算200以内的屋顶工"

    private let chineseRooferJSON = """
    {"raw":"帮我找一个明天下午2点能来Aurora估价、预算200以内的屋顶工","englishSearch":"Find a roofer in Aurora for a roof estimate tomorrow at 2pm under $200.","object":"roofer","need":"roof estimate","place":"Aurora","time":"tomorrow at 2pm","budget":"under 200","commercial":null,"mods":[],"hard":["Aurora","tomorrow at 2pm","under 200"],"soft":[],"gaps":[],"confidence":0.9,"routeClass":"providerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.92,"routeRationale":"hire roofer for scheduled estimate"}
    """

    func testChineseRooferFlatPipelinePreservesCanonicalFields() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let canonical = extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: chineseRooferJSON,
            userText: chineseRooferQuery,
            intent: seedIntent(objective: chineseRooferQuery)
        )

        XCTAssertNotNil(canonical)
        XCTAssertEqual(canonical?.objectType, "roofer")
        XCTAssertEqual(canonical?.places.first?.normalizedText, "aurora")
        XCTAssertEqual(canonical?.timeConstraints.first?.text, "tomorrow at 2pm")
        XCTAssertEqual(canonical?.commercialConstraints.first?.value, "under 200")
        XCTAssertEqual(canonical?.extractedRoute?.routeClassRaw, "providerSearch")
        XCTAssertEqual(canonical?.extractedRoute?.targetKindRaw, "provider")
        XCTAssertEqual(canonical?.extractedRoute?.surfacePreferenceRaw, "offer")
        XCTAssertEqual(
            canonical?.canonicalEnglishSearchText,
            "Find a roofer in Aurora for a roof estimate tomorrow at 2pm under $200."
        )
        XCTAssertTrue(
            canonical?.semanticConcepts.contains(where: { $0.lowercased().contains("roof") }) == true
        )
    }

    func testChineseRooferCanonicalEnglishSurvivesFacetsSanitization() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let canonical = extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: chineseRooferJSON,
            userText: chineseRooferQuery,
            intent: seedIntent(objective: chineseRooferQuery)
        )
        XCTAssertNotNil(canonical)

        let facets = ExchangeIntentFacets(
            searchIntent: canonical,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer
        )

        XCTAssertEqual(
            facets.searchIntent?.canonicalEnglishSearchText,
            "Find a roofer in Aurora for a roof estimate tomorrow at 2pm under $200."
        )
        XCTAssertEqual(facets.searchIntent?.objectType, "roofer")
        XCTAssertEqual(facets.searchIntent?.places.first?.normalizedText, "aurora")
        XCTAssertEqual(facets.searchIntent?.timeConstraints.first?.text, "tomorrow at 2pm")
        XCTAssertEqual(facets.searchIntent?.commercialConstraints.first?.value, "under 200")
    }

    func testTranslatedHardTextsAreNotDroppedWhenStructuredFieldsPresent() {
        let extractor = LLMOpenEndedSearchIntentExtractor()
        let compact = try! JSONDecoder().decode(
            SecretaryCompactSearchSummaryDTO.self,
            from: Data(chineseRooferJSON.utf8)
        )
        let expanded = extractor.expandCompactSearchSummaryToFull(
            compact,
            userText: chineseRooferQuery,
            intent: seedIntent(objective: chineseRooferQuery)
        )
        let validated = extractor.validateFlatSummary(expanded, userText: chineseRooferQuery)

        XCTAssertNotNil(validated)
        XCTAssertEqual(validated?.placeText, "Aurora")
        XCTAssertEqual(validated?.timeText, "tomorrow at 2pm")
        XCTAssertEqual(validated?.budgetText, "under 200")
        XCTAssertEqual(validated?.hardTexts, ["Aurora", "tomorrow at 2pm", "under 200"])
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
}
