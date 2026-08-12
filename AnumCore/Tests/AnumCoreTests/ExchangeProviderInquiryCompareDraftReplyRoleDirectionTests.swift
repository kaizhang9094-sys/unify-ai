import XCTest
@testable import AnumCore

final class ExchangeProviderInquiryCompareDraftReplyRoleDirectionTests: XCTestCase {

    func testRoleReversal_blocksRequesterCredentialConfirmation() {
        let body = "I need to verify your credentials and schedule availability with you directly."
        let outcome = ExchangeProviderInquiryCompareDraftReplyValidator.validate(rawDraft: body, compare: nil)
        XCTAssertFalse(outcome.allowsCompareFirstDirectSend)
        XCTAssertTrue(outcome.violations.contains("role_reversal_verify_your_credentials"))
    }

    func testRoleReversal_blocksDiscountApprovalFromYourProvider() {
        let body = "I would need to confirm that you have received explicit approval for this discount from your provider."
        let outcome = ExchangeProviderInquiryCompareDraftReplyValidator.validate(rawDraft: body, compare: nil)
        XCTAssertTrue(outcome.violations.contains("role_reversal_requester_discount_approval"))
    }

    func testRoleReversal_allowsProviderSideFraming() {
        let body = "License and insurance details are not published in the offer, so the provider would need to confirm them."
        let outcome = ExchangeProviderInquiryCompareDraftReplyValidator.validate(rawDraft: body, compare: nil)
        XCTAssertFalse(outcome.violations.contains(where: { $0.hasPrefix("role_reversal_") }))
    }
}
