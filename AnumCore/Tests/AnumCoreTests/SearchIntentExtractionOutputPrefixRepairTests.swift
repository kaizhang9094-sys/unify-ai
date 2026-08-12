import XCTest
@testable import AnumCore

final class SearchIntentExtractionOutputPrefixRepairTests: XCTestCase {

    func testReattachesContinuationWithClosingBrace() {
        let input = "\"Find me a roofer in Aurora tomorrow at 2:30pm\"}"
        let (out, did) = SearchIntentExtractionOutputPrefixRepair.reconstructJSONIfNeeded(input)
        XCTAssertTrue(did)
        XCTAssertEqual(out, "{\"raw\":" + input)
    }

    func testFullObjectUnchanged() {
        let full = "{\"raw\":\"already full\"}"
        let (out, did) = SearchIntentExtractionOutputPrefixRepair.reconstructJSONIfNeeded(full)
        XCTAssertFalse(did)
        XCTAssertEqual(out, full)
    }

    func testBareQuotedStringGetsWrapped() {
        let input = "\"only string\""
        let (out, did) = SearchIntentExtractionOutputPrefixRepair.reconstructJSONIfNeeded(input)
        XCTAssertTrue(did)
        XCTAssertEqual(out, "{\"raw\":" + input + "}")
    }


    func testRepairEscapedFlatSummaryKeyValueSeparator() throws {
        let malformed = """
        {"raw":"Find me a plumber in Austin for a leak repair this Saturday afternoon.","object":"plumber","need":"leak repair","place":"Austin","time\\\":\\\"this Saturday afternoon","budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.9}
        """
        let user = "Find me a plumber in Austin for a leak repair this Saturday afternoon."
        let seed = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "t",
            objective: user
        )
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let cleaned = mapper.cleanJSON(malformed)
        XCTAssertTrue(cleaned.contains(#""time":"this Saturday afternoon"#))
        let canonical = try XCTUnwrap(
            mapper.processSearchIntentFlatPipelineCanonical(
                cleaned: cleaned,
                userText: user,
                intent: seed
            )
        )
        XCTAssertEqual(canonical.objectType?.lowercased(), "plumber")
        XCTAssertTrue(
            canonical.semanticConcepts.contains { $0.lowercased().contains("leak") }
        )
        XCTAssertTrue(
            canonical.broadRecallTokens.contains { $0.lowercased().contains("leak") }
        )
        XCTAssertTrue(
            canonical.timeConstraints.contains { $0.text.lowercased().contains("saturday") }
        )
    }

    func testRepairEscapedSeparatorPreservesValidJSON() {
        let valid = """
        {"raw":"Find me a roofer in Aurora for a roof appraisal tomorrow at 2:30pm.","object":"roofer","need":"roof appraisal","place":"Aurora","time":"tomorrow at 2:30pm","budget":null,"commercial":null,"mods":[],"hard":["Aurora","tomorrow at 2:30pm"],"soft":[],"gaps":[],"confidence":0.9}
        """
        let repaired = SearchIntentExtractionFlatSummaryJSONRepair.repairEscapedKeyValueSeparators(valid)
        XCTAssertEqual(repaired, valid)

        let mapper = LLMOpenEndedSearchIntentExtractor()
        let user = "Find me a roofer in Aurora for a roof appraisal tomorrow at 2:30pm."
        let seed = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "t",
            objective: user
        )
        let canonical = mapper.processSearchIntentFlatPipelineCanonical(
            cleaned: mapper.cleanJSON(valid),
            userText: user,
            intent: seed
        )
        XCTAssertNotNil(canonical)
        XCTAssertEqual(canonical?.objectType?.lowercased(), "roofer")
    }

    func testRepairSingleEscapedSeparatorLiteral() {
        let broken = "{\"object\":\"plumber\",\"time\":\"this Saturday afternoon\",\"confidence\":0.9}"
        let expected = "{\"object\":\"plumber\",\"time\":\"this Saturday afternoon\",\"confidence\":0.9}"
        let fixed = SearchIntentExtractionFlatSummaryJSONRepair.repairEscapedKeyValueSeparators(broken)
        XCTAssertEqual(fixed, expected)
    }

}
