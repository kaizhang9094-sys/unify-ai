import XCTest
@testable import AnumCore

final class SearchIntentSentinelFilterTests: XCTestCase {
    func testIsSentinelRecognizesPlaceholderTokens() {
        for token in ["none", "null", "nil", "n/a", "na", "unknown", "", "  NONE  ", "\"none\""] {
            XCTAssertTrue(SearchIntentSentinelFilter.isSentinel(token), "expected sentinel for \(token)")
        }
    }

    func testNilIfSentinelStripsNeedNone() {
        XCTAssertNil(SearchIntentSentinelFilter.nilIfSentinel("none"))
        XCTAssertEqual(SearchIntentSentinelFilter.nilIfSentinel("photography"), "photography")
    }

    func testNeedNoneDoesNotEnterCanonicalSemanticConcepts() {
        let extractor = LLMOpenEndedSearchIntentExtractor(jsonProvider: nil)
        let userText = "Find people interested in photography in Aurora"
        let canonical = extractor.processSearchIntentFlatPipelineCanonical(
            cleaned: SearchIntentRouteTestFixtures.needNoneJSON,
            userText: userText,
            intent: seedIntent()
        )
        XCTAssertNotNil(canonical)

        let joined = (
            canonical!.semanticConcepts
            + canonical!.broadRecallTokens
            + [canonical!.objectType]
        ).compactMap { $0 }.joined(separator: " ").lowercased()

        XCTAssertFalse(joined.contains("none"))
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
}
