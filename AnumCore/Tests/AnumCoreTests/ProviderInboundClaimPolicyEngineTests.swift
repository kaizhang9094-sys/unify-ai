import XCTest
@testable import AnumCore

final class ProviderInboundClaimPolicyEngineTests: XCTestCase {

    private let permissive = ExchangeOffer.AutoAnswerPolicy(
        canAnswerPricing: true,
        canAnswerAvailability: true,
        canAnswerPolicies: true,
        canAnswerServiceArea: true,
        canAnswerFAQs: true,
        requiresApprovalForCustomQuote: false
    )

    private func surfacesOfferSearch() -> ProviderAllowedFactSurfaces {
        ProviderAllowedFactSurfaces(
            includePublicProfile: false,
            includeOffer: true,
            includeCommercialOffer: true,
            includeContactReachability: false,
            includeOperatingMemoryDelta: true,
            reason: "transactional_offer_surface"
        )
    }

    private func sellerFactsBlock(offer: ExchangeOffer) -> String {
        let cf = offer.commercialFacts
        var lines = ["=== OFFER_FACTS ===", "offer_title: \(offer.title)"]
        if let pd = cf.priceDisplay { lines.append("price_display: \(pd)") }
        if let area = cf.serviceAreaNote { lines.append("service_area_note: \(area)") }
        if let avail = cf.availabilityNote { lines.append("availability_note: \(avail)") }
        lines.append("=== END OFFER_FACTS ===")
        return lines.joined(separator: "\n")
    }

    private func evaluate(
        question: String,
        commercial: ExchangeOffer.CommercialFacts
    ) -> ProviderClaimBoundaryPacket {
        let cf = commercial
        let offer = ExchangeOffer(
            id: "test-offer",
            nodeID: "node-1",
            title: "Residential plumbing",
            commercialFacts: cf
        )
        let profile = ExchangePublicNodeProfile(
            id: "test-profile",
            nodeID: "node-1",
            displayName: "Riverbend Plumbing",
            headline: "Austin-area plumbing professional"
        )
        let allowed = surfacesOfferSearch()
        let detection = ProviderInboundDimensionDetector.detect(requesterText: question)
        return ProviderInboundClaimPolicyEngine.evaluateLogOnly(
            ProviderInboundClaimPolicyInput(
                requesterText: question,
                detection: detection,
                allowedSurfaces: allowed,
                applyFactSurfaceGating: true,
                offer: offer,
                profile: profile,
                sellerControlledFacts: sellerFactsBlock(offer: offer)
            )
        )
    }

    func testMissingDiscount_needsProviderConfirmation() {
        let packet = evaluate(
            question: "Can you do 20% off if I book today?",
            commercial: ExchangeOffer.CommercialFacts(
                priceDisplay: "Service call $89",
                autoAnswerPolicy: permissive
            )
        )
        XCTAssertEqual(packet.answerabilityStatus, ProviderPolicyAnswerability.needsProviderConfirmation)
        XCTAssertTrue(packet.missingClaims.contains { $0.dimension == .discount })
        XCTAssertTrue(packet.forbiddenClaims.contains("20% off"))
    }

    func testMissingWarrantyCert_notInOffer() {
        let packet = evaluate(
            question: "Are you licensed and insured for this work?",
            commercial: ExchangeOffer.CommercialFacts(autoAnswerPolicy: permissive)
        )
        XCTAssertEqual(packet.answerabilityStatus, ProviderPolicyAnswerability.notInOffer)
        XCTAssertTrue(packet.missingClaims.contains { $0.dimension == .licenseInsurance })
        XCTAssertTrue(packet.forbiddenClaims.contains("licensed"))
    }

    func testMissingExactSlot_answerWithCaveat() {
        let packet = evaluate(
            question: "Can you confirm 2:30–4:00 PM Saturday?",
            commercial: ExchangeOffer.CommercialFacts(
                availabilityNote: "Weekends by appointment; Saturday PM often available",
                autoAnswerPolicy: permissive
            )
        )
        XCTAssertEqual(packet.answerabilityStatus, ProviderPolicyAnswerability.answerWithCaveat)
        XCTAssertTrue(packet.missingClaims.contains { $0.dimension == .exactSlot })
        XCTAssertFalse(packet.requiredCaveats.isEmpty)
    }

    func testOutsideServiceArea_notInOffer() {
        var commercial = ExchangeOffer.CommercialFacts(autoAnswerPolicy: permissive)
        commercial.serviceAreaNote = "Austin metro only"
        let packet = evaluate(
            question: "Can you come to Houston same day?",
            commercial: commercial
        )
        XCTAssertEqual(packet.answerabilityStatus, ProviderPolicyAnswerability.notInOffer)
        XCTAssertTrue(packet.allowedClaims.contains { $0.factID == "offer.commercial.serviceAreaNote" })
        XCTAssertTrue(packet.missingClaims.contains { $0.dimension == .serviceArea })
    }

    func testCommitmentBooking_refuseCommitment() {
        let packet = evaluate(
            question: "Great — please book me for Saturday and send a final quote of $200.",
            commercial: ExchangeOffer.CommercialFacts(
                priceDisplay: "Service call $89; typical leak repair $150–$280",
                autoAnswerPolicy: permissive
            )
        )
        XCTAssertEqual(packet.answerabilityStatus, ProviderPolicyAnswerability.refuseCommitment)
        XCTAssertEqual(packet.riskTier, ProviderInboundRiskTier.commitment)
        XCTAssertNotNil(packet.commitmentBoundary)
        XCTAssertTrue(packet.forbiddenClaims.contains("final quote"))
    }

    func testProfileSummaryGating_nilWhenPublicProfileExcluded() {
        let profile = ExchangePublicNodeProfile(
            id: "p1",
            nodeID: "node-1",
            displayName: "Riverbend Plumbing",
            headline: "Austin-area plumbing professional"
        )
        let surfaces = surfacesOfferSearch()
        XCTAssertFalse(surfaces.includePublicProfile)
        let summary = ProviderInquiryCompareProfileSummaryGate.compactProfileSummary(
            profile: profile,
            allowedSurfaces: surfaces,
            applyFactSurfaceGating: true
        )
        XCTAssertNil(summary)
    }
}
