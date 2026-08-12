import XCTest
@testable import AnumCore

final class ExchangeSemanticEvidenceSanitizerTests: XCTestCase {

    func testStandaloneScaffoldReturnsNil() {
        XCTAssertNil(ExchangeSemanticEvidenceSanitizer.sanitize("Response received"))
        XCTAssertNil(ExchangeSemanticEvidenceSanitizer.sanitize("response received"))
        XCTAssertNil(ExchangeSemanticEvidenceSanitizer.sanitize("Counterparty is asking for additional information."))
        XCTAssertNil(ExchangeSemanticEvidenceSanitizer.sanitize("counterparty is asking for additional information."))
    }

    func testPrefixStripPreservesRemainder() {
        XCTAssertEqual(
            ExchangeSemanticEvidenceSanitizer.sanitize(
                "response - response received - Are you open to early-stage founders?"
            ),
            "Are you open to early-stage founders?"
        )
        XCTAssertEqual(
            ExchangeSemanticEvidenceSanitizer.sanitize(
                "Response received - Are you open to early-stage founders?"
            ),
            "Are you open to early-stage founders?"
        )
    }

    func testNormalContentUnchanged() {
        let hi = "Hi Hansen, I'm looking for a vc..."
        XCTAssertEqual(ExchangeSemanticEvidenceSanitizer.sanitize(hi), hi)

        let yes = "Yes — we're open to hearing from early-stage founders."
        XCTAssertEqual(ExchangeSemanticEvidenceSanitizer.sanitize(yes), yes)

        let question = "What type of startups are you interested in?"
        XCTAssertEqual(ExchangeSemanticEvidenceSanitizer.sanitize(question), question)
    }

    func testEmbeddedPhraseNotDropped() {
        let embedded = "The customer said response received yesterday"
        XCTAssertEqual(ExchangeSemanticEvidenceSanitizer.sanitize(embedded), embedded)
    }

    func testBlankAndNil() {
        XCTAssertNil(ExchangeSemanticEvidenceSanitizer.sanitize(nil))
        XCTAssertNil(ExchangeSemanticEvidenceSanitizer.sanitize(""))
        XCTAssertNil(ExchangeSemanticEvidenceSanitizer.sanitize("   \n  "))
    }

    func testRepeatedWhitespaceCollapses() {
        XCTAssertEqual(
            ExchangeSemanticEvidenceSanitizer.sanitize("  Hi   Hansen,\n\nlooking  "),
            "Hi Hansen, looking"
        )
    }
}
