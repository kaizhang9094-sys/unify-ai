import Foundation
import XCTest
@testable import AnumCore

final class ExchangeFederationUserVisibleSanitizerTests: XCTestCase {
    func test_outboundBodySanitizer_removesInternalScaffold() {
        let polluted = """
        Draft grounded on published facts: Thanks for your interest - this listing is a house for sale in the GTA area with 4 bedrooms and 4 bathrooms. Happy to share more about availability or next steps.
        ---
        Hi node-12c41, response-response-inbound message from node-22
        """
        let cleaned = ExchangeUserFacingCopySanitizer.cleanFederationUserVisibleBody(polluted)
        XCTAssertTrue(cleaned.removedInternalScaffold)
        XCTAssertFalse(cleaned.cleaned.lowercased().contains("draft grounded on published facts"))
        XCTAssertFalse(cleaned.cleaned.lowercased().contains("response-response-inbound"))
        XCTAssertFalse(cleaned.cleaned.lowercased().contains("hi node-"))
        XCTAssertTrue(cleaned.cleaned.hasPrefix("Thanks for your interest"))
    }

    func test_receivedBodySanitizer_removesInternalScaffold() {
        let polluted = """
        Response — Inbound message from node-12c41
        Draft grounded on published facts: Thanks for your interest in the listing.
        """
        let cleaned = ExchangeUserFacingCopySanitizer.cleanReceivedFederationBody(polluted)
        XCTAssertTrue(cleaned.removedInternalScaffold)
        XCTAssertFalse(cleaned.cleaned.lowercased().contains("inbound message from node-"))
        XCTAssertFalse(cleaned.cleaned.lowercased().contains("draft grounded on published facts"))
        XCTAssertEqual(cleaned.forbiddenTermsFound.count, 0)
    }

    func test_titleSanitizer_removesInboundNodeScaffold() {
        let raw = "Response — Inbound message from node-12c41..."
        let cleaned = ExchangeUserFacingCopySanitizer.sanitize(raw, field: .title) ?? ""
        XCTAssertFalse(cleaned.lowercased().contains("inbound message from node"))
        XCTAssertFalse(cleaned.lowercased().contains("node-12c41"))
    }

    func test_correlatedReplyProjection_keepsExistingThreadTitle() {
        let existingTitle = "Help me find a house for sale in gta"
        let pick = ExchangeThreadCardTitleProjection.inboundProviderInquiryTitlePick(
            hydratedOpportunityTitle: "House for sale",
            inboundSenderDisplay: "node-12c41",
            threadStoredTitle: existingTitle,
            threadID: UUID(),
            surface: "threads"
        )
        XCTAssertEqual(pick.title, existingTitle)
        XCTAssertNotEqual(pick.title, "New inquiry about House for sale")
    }
}
