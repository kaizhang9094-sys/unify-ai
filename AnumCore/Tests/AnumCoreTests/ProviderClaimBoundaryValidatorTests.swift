import XCTest
@testable import AnumCore

final class ProviderClaimBoundaryValidatorTests: XCTestCase {

    private func packet(
        dimensions: [ProviderInboundDimension],
        answerability: ProviderPolicyAnswerability,
        riskTier: ProviderInboundRiskTier = .highClaim,
        responseMode: ProviderResponseMode = .askProviderInput,
        allowed: [ProviderAllowedClaim] = [],
        missing: [ProviderMissingClaim] = [],
        caveats: [String] = [],
        forbidden: [String] = [],
        untrusted: [String] = [],
        commitmentBoundary: ExchangeCommitmentBoundary? = nil
    ) -> ProviderClaimBoundaryPacket {
        ProviderClaimBoundaryPacket(
            responseMode: responseMode,
            riskTier: riskTier,
            askedDimensions: dimensions,
            allowedClaims: allowed,
            missingClaims: missing,
            requiredCaveats: caveats,
            forbiddenClaims: forbidden,
            requesterClaimsUntrusted: untrusted,
            answerabilityStatus: answerability,
            commitmentBoundary: commitmentBoundary
        )
    }

    func testMissingDiscount_affirmativeFails() {
        let pkt = packet(
            dimensions: [.discount],
            answerability: .needsProviderConfirmation,
            missing: [ProviderMissingClaim(dimension: .discount, reason: "not published")]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "Yes, we can offer a discount on service calls.",
            packet: pkt,
            requesterText: "Can you do 20% off if I book today?"
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.reasons.contains { $0.code.contains("discount") })
    }

    func testMissingDiscount_caveatPasses() {
        let pkt = packet(
            dimensions: [.discount],
            answerability: .needsProviderConfirmation,
            caveats: ["Discount policy is not specified; provider needs to confirm."]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "Discount policy is not specified; provider needs to confirm before we could discuss any special rate.",
            packet: pkt,
            requesterText: "Can you do 20% off if I book today?"
        )
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.severity, .pass)
    }

    func testMissingWarrantyCert_licensedInsuredFails() {
        let pkt = packet(
            dimensions: [.licenseInsurance],
            answerability: .notInOffer,
            missing: [ProviderMissingClaim(dimension: .licenseInsurance, reason: "not in offer")]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "We are licensed and insured for this work.",
            packet: pkt,
            requesterText: "Are you licensed and insured for this work?"
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.reasons.contains { $0.code.contains("credential") })
    }

    func testMissingWarrantyCert_caveatPasses() {
        let pkt = packet(
            dimensions: [.licenseInsurance],
            answerability: .notInOffer
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "License and insurance are not specified in the listing; provider would need to confirm.",
            packet: pkt,
            requesterText: "Are you licensed and insured for this work?"
        )
        XCTAssertTrue(result.isValid)
    }

    func testCommitmentBooking_affirmativeFails() {
        let pkt = packet(
            dimensions: [.booking, .finalQuote],
            answerability: .refuseCommitment,
            riskTier: .commitment,
            responseMode: .decline,
            commitmentBoundary: .commitmentBearing(reason: "booking")
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "Saturday is booked and the final quote is $200.",
            packet: pkt,
            requesterText: "Great — please book me for Saturday and send a final quote of $200."
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.reasons.contains { $0.code.contains("booking") || $0.code.contains("final_quote") })
    }

    func testCommitmentBooking_caveatPasses() {
        let pkt = packet(
            dimensions: [.booking, .finalQuote],
            answerability: .refuseCommitment,
            riskTier: .commitment,
            responseMode: .decline
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "We cannot confirm booking or send a final quote of $200 without provider confirmation.",
            packet: pkt,
            requesterText: "Great — please book me for Saturday and send a final quote of $200."
        )
        XCTAssertTrue(result.isValid)
    }

    func testOutsideServiceArea_serveHoustonFails() {
        let pkt = packet(
            dimensions: [.serviceArea],
            answerability: .notInOffer,
            allowed: [
                ProviderAllowedClaim(
                    factID: "offer.commercial.serviceAreaNote",
                    text: "Austin metro only",
                    source: .offer
                )
            ],
            missing: [ProviderMissingClaim(dimension: .serviceArea, reason: "outside area")]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "We serve Houston with same-day availability.",
            packet: pkt,
            requesterText: "Can you come to Houston same day?"
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.reasons.contains { $0.code.contains("service_area") })
    }

    func testOutsideServiceArea_denialPasses() {
        let pkt = packet(
            dimensions: [.serviceArea],
            answerability: .notInOffer,
            allowed: [
                ProviderAllowedClaim(
                    factID: "offer.commercial.serviceAreaNote",
                    text: "Austin metro only",
                    source: .offer
                )
            ]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "We cannot confirm service in Houston; the published service area is Austin metro only.",
            packet: pkt,
            requesterText: "Can you come to Houston same day?"
        )
        XCTAssertTrue(result.isValid)
    }

    func testExactSlot_confirmedFails() {
        let pkt = packet(
            dimensions: [.exactSlot],
            answerability: .answerWithCaveat,
            riskTier: .mediumScope,
            responseMode: .partialAnswer,
            allowed: [
                ProviderAllowedClaim(
                    factID: "offer.commercial.availabilityNote",
                    text: "Weekends by appointment",
                    source: .offer
                )
            ],
            missing: [ProviderMissingClaim(dimension: .exactSlot, reason: "precision gap")]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "2:30 PM Saturday is confirmed for your visit.",
            packet: pkt,
            requesterText: "Can you confirm 2:30–4:00 PM Saturday?"
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.reasons.contains { $0.code == "exact_slot_confirmed" })
    }

    func testPublishedPriceRange_passesWhenAllowed() {
        let pkt = packet(
            dimensions: [.price],
            answerability: .answerDirectly,
            riskTier: .lowFact,
            responseMode: .groundedAnswer,
            allowed: [
                ProviderAllowedClaim(
                    factID: "offer.commercial.priceDisplay",
                    text: "Service call $89; typical leak repair $150–$280",
                    source: .offer
                )
            ]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "Published pricing is a $89 service call and typical leak repairs run $150–$280.",
            packet: pkt,
            requesterText: "What do you charge for a leak repair?"
        )
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.suggestedAction, .allow)
    }


    func testDiscount_hasNotBeenConfirmed_passes() {
        let pkt = packet(
            dimensions: [.discount, .price],
            answerability: .needsProviderConfirmation,
            missing: [ProviderMissingClaim(dimension: .discount, reason: "not published")],
            forbidden: ["20% off", "discount approved", "special rate confirmed", "today-only deal"]
        )
        let body = """
        Published pricing is a service call of $89 and typical leak repairs range from $150 to $280.         A discount offer for today's booking has not been confirmed in the listing details;         that would require provider confirmation.
        """
        let result = ProviderClaimBoundaryValidator.validate(
            body: body,
            packet: pkt,
            requesterText: "Can you do 20% off if I book today?"
        )
        XCTAssertTrue(result.isValid, "reasons: \(result.reasons.map { $0.code })")
    }

    func testDiscount_wouldRequireProviderConfirmation_passes() {
        let pkt = packet(
            dimensions: [.discount],
            answerability: .needsProviderConfirmation,
            forbidden: ["discount approved"]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "A discount has not been confirmed and would require provider confirmation.",
            packet: pkt,
            requesterText: "Can you offer a discount?"
        )
        XCTAssertTrue(result.isValid, "reasons: \(result.reasons.map { $0.code })")
    }

    func testLicenseInsurance_doesNotExplicitlyState_passes() {
        let pkt = packet(
            dimensions: [.licenseInsurance],
            answerability: .notInOffer,
            missing: [ProviderMissingClaim(dimension: .licenseInsurance, reason: "not in offer")],
            forbidden: ["licensed", "insured", "bonded", "liability insurance"]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "The seller's profile does not explicitly state that they hold a professional license or carry liability insurance.",
            packet: pkt,
            requesterText: "Are you licensed and insured?"
        )
        XCTAssertTrue(result.isValid, "reasons: \(result.reasons.map { $0.code })")
    }

    func testLicenseInsurance_affirmativeStillFails() {
        let pkt = packet(
            dimensions: [.licenseInsurance],
            answerability: .notInOffer,
            missing: [ProviderMissingClaim(dimension: .licenseInsurance, reason: "not in offer")],
            forbidden: ["licensed", "insured"]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "Yes, we are licensed and insured.",
            packet: pkt,
            requesterText: "Are you licensed and insured?"
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.reasons.contains { $0.code.contains("credential") || $0.code == "forbidden_claim_echo" })
    }

    func testDiscount_affirmativeStillFails() {
        let pkt = packet(
            dimensions: [.discount],
            answerability: .needsProviderConfirmation,
            forbidden: ["discount approved"]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "We can offer a discount.",
            packet: pkt,
            requesterText: "Can you offer a discount?"
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.reasons.contains { $0.code.contains("discount") })
    }

    func testPublishedOfferDoesNotSpecify_licenseInsurance_passes() {
        let pkt = packet(
            dimensions: [.licenseInsurance],
            answerability: .notInOffer,
            forbidden: ["licensed", "insured"]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "The published offer does not specify license or insurance details.",
            packet: pkt,
            requesterText: "Are you licensed and insured?"
        )
        XCTAssertTrue(result.isValid, "reasons: \(result.reasons.map { $0.code })")
    }

    func testLicenseInsurance_haveNotBeenConfirmedInListing_passes() {
        let pkt = packet(
            dimensions: [.licenseInsurance],
            answerability: .notInOffer,
            forbidden: ["licensed", "insured"]
        )
        let result = ProviderClaimBoundaryValidator.validate(
            body: "License and insurance have not been confirmed in the listing.",
            packet: pkt,
            requesterText: "Are you licensed and insured?"
        )
        XCTAssertTrue(result.isValid, "reasons: \(result.reasons.map { $0.code })")
    }

}
