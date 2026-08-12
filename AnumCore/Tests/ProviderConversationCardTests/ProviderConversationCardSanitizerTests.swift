import XCTest
@testable import AnumCore

final class ProviderConversationCardSanitizerTests: XCTestCase {

    func testStripsResponseReceivedPrefixBeforeUserText() {
        let cleaned = ExchangeUserFacingCopySanitizer.sanitizeProviderConversationCardPreview(
            "response - response received - Hello",
            surface: "test"
        )
        XCTAssertEqual(cleaned, "Hello")
    }

    func testStripsTitleCaseResponseReceivedPrefixBeforeUserText() {
        let cleaned = ExchangeUserFacingCopySanitizer.sanitizeProviderConversationCardPreview(
            "Response received - Hello",
            surface: "test"
        )
        XCTAssertEqual(cleaned, "Hello")
    }

    func testStandaloneCounterpartyScaffoldBecomesNeutralFallback() {
        let cleaned = ExchangeUserFacingCopySanitizer.sanitizeProviderConversationCardPreview(
            "Counterparty is asking for additional information.",
            surface: "test"
        )
        XCTAssertEqual(cleaned, "New inquiry received")
    }

    func testLegitimateUserMessageUnchanged() {
        let message = "Yes — we're open to hearing from early-stage founders."
        let cleaned = ExchangeUserFacingCopySanitizer.sanitizeProviderConversationCardPreview(
            message,
            surface: "test"
        )
        XCTAssertEqual(cleaned, message)
    }

    func testUsesCleanInboundFallbackWhenScaffoldOnly() {
        let cleaned = ExchangeUserFacingCopySanitizer.sanitizeProviderConversationCardPreview(
            "Response received",
            cleanInboundFallback: "Are you currently open to early-stage founders?",
            surface: "test"
        )
        XCTAssertEqual(cleaned, "Are you currently open to early-stage founders?")
    }

    func testRequesterSanitizePathUnchanged() {
        let requesterLine = "Looking for a pediatric dentist near downtown."
        let cleaned = ExchangeUserFacingCopySanitizer.sanitize(
            requesterLine,
            field: .subtitle
        )
        XCTAssertEqual(cleaned, requesterLine)
    }
}
