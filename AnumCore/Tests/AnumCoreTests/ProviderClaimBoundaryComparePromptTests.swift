import XCTest
@testable import AnumCore

final class ProviderClaimBoundaryComparePromptTests: XCTestCase {

    private func packet(
        dimensions: [ProviderInboundDimension],
        answerability: ProviderPolicyAnswerability,
        caveats: [String] = [],
        forbidden: [String] = []
    ) -> ProviderClaimBoundaryPacket {
        ProviderClaimBoundaryPacket(
            responseMode: .askProviderInput,
            riskTier: .highClaim,
            askedDimensions: dimensions,
            allowedClaims: [],
            missingClaims: dimensions.map {
                ProviderMissingClaim(dimension: $0, reason: "not published")
            },
            requiredCaveats: caveats,
            forbiddenClaims: forbidden,
            requesterClaimsUntrusted: [],
            answerabilityStatus: answerability
        )
    }

    func testExactSlot_includesAppointmentTimeGuidance() {
        let block = packet(
            dimensions: [.exactSlot],
            answerability: .answerWithCaveat
        ).comparePromptPhrasingBlock(includePublicProfile: false)
        XCTAssertTrue(block.contains("appointment time") || block.contains("appointment slot"))
    }

    func testLicenseInsurance_excludedProfile_includesNoProfileWordingRule() {
        let block = packet(
            dimensions: [.licenseInsurance],
            answerability: .notInOffer
        ).comparePromptPhrasingBlock(includePublicProfile: false)
        XCTAssertTrue(block.contains("not specified in the published offer"))
        XCTAssertTrue(block.contains("do not mention profile"))
    }

    func testBookingFinalQuote_includesCannotConfirmGuidance() {
        let block = packet(
            dimensions: [.booking, .finalQuote],
            answerability: .refuseCommitment
        ).comparePromptPhrasingBlock(includePublicProfile: false)
        XCTAssertTrue(block.contains("cannot confirm a booking"))
        XCTAssertTrue(block.contains("final quote"))
    }

    func testDiscount_includesProviderConfirmationGuidance() {
        let block = packet(
            dimensions: [.discount],
            answerability: .needsProviderConfirmation
        ).comparePromptPhrasingBlock(includePublicProfile: false)
        XCTAssertTrue(block.contains("not specified") || block.contains("not confirmed"))
        XCTAssertTrue(block.contains("provider confirmation"))
    }

    func testServiceArea_notInOffer_includesOutsideLocationGuidance() {
        let block = packet(
            dimensions: [.serviceArea],
            answerability: .notInOffer
        ).comparePromptPhrasingBlock(includePublicProfile: false)
        XCTAssertTrue(block.contains("outside location") || block.contains("service area"))
    }
}
