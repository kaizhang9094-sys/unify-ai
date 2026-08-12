import XCTest
@testable import AnumCore

final class DirectChatReplySuggestionPolicyTests: XCTestCase {
    func testFallbackVariantStableForSelectionKey() {
        let key = "node-a|did you get a chance to send the deck?"
        let first = DirectChatReplySuggestionPolicy.fallbackReplyText(
            latestInboundMessage: "Did you get a chance to send the deck?",
            relationshipType: .colleague,
            selectionKey: key
        )
        let second = DirectChatReplySuggestionPolicy.fallbackReplyText(
            latestInboundMessage: "Did you get a chance to send the deck?",
            relationshipType: .colleague,
            selectionKey: key
        )
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testDeckFallbackMatchesSmokeSelectionKey() {
        let key = "smoke-direct-reply-node|Did you get a chance to send the deck?"
        let reply = DirectChatReplySuggestionPolicy.fallbackReplyText(
            latestInboundMessage: "Did you get a chance to send the deck?",
            relationshipType: .colleague,
            selectionKey: key
        )
        let variants = [
            "Not yet — I'm working on it and will send it over when it's ready.",
            "Still putting it together — I'll send it your way soon.",
            "Not quite ready yet, but I'll share it shortly."
        ]
        XCTAssertTrue(variants.contains(reply))
    }

    func testParserAcceptsMinimalJSON() {
        let output = DirectChatReplySuggestionParser.parse(raw: #"{"reply":"hi"}"#)
        XCTAssertEqual(output?.reply, "hi")
        XCTAssertEqual(output?.requiresApproval, true)
    }
}
