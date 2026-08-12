import XCTest
@testable import AnumCore

final class ProviderClaimLedgerBuilderTests: XCTestCase {

    private func sampleOffer() -> ExchangeOffer {
        let commercial = ExchangeOffer.CommercialFacts(
            priceDisplay: "Service call $89; typical leak repair $150–$280",
            packages: [
                ExchangeOffer.PackageOption(title: "Standard Leak Repair", summary: "Diagnosis + repair")
            ],
            serviceAreaNote: "Austin metro only",
            availabilityNote: "Weekends by appointment",
            warrantyPolicy: "90-day workmanship warranty",
            faqs: [
                ExchangeOffer.FAQ(
                    question: "Do you offer a discount?",
                    answer: "We sometimes run 10% off promotions."
                )
            ],
            autoAnswerPolicy: ExchangeOffer.AutoAnswerPolicy(
                canAnswerPricing: true,
                canAnswerAvailability: true,
                canAnswerPolicies: true,
                canAnswerServiceArea: true,
                requiresApprovalForCustomQuote: true
            )
        )
        return ExchangeOffer(
            id: "offer-ledger-test",
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Residential plumbing",
            summary: "Emergency and routine repairs.",
            fulfillment: ExchangeOffer.Fulfillment(leadTimeNote: "Usually 24–48 hours"),
            commercialFacts: commercial,
        )
    }

    private func sampleProfile() -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            displayName: "Riverbend Plumbing",
            headline: "Austin-area plumbing professional",
            summary: "Licensed-looking headline only — not a structured credential field.",
            regionTags: ["Austin"]
        )
    }

    func testBuild_fullCommercialSurface_presentAndAbsentClaims() {
        let ledger = ProviderClaimLedgerBuilder.build(
            profile: sampleProfile(),
            offer: sampleOffer()
        )

        XCTAssertEqual(ledger.entries.count, ProviderClaimType.allCases.count)
        XCTAssertEqual(ledger.offerID, "offer-ledger-test")
        XCTAssertEqual(ledger.profileID, "profile-1")

        XCTAssertEqual(ledger.entry(for: .pricing)?.status, .present)
        XCTAssertEqual(ledger.entry(for: .serviceArea)?.status, .present)
        XCTAssertEqual(ledger.entry(for: .availability)?.status, .present)
        XCTAssertEqual(ledger.entry(for: .leadTime)?.status, .present)
        XCTAssertEqual(ledger.entry(for: .packageAvailability)?.status, .present)
        XCTAssertEqual(ledger.entry(for: .warrantyOrGuarantee)?.status, .present)

        XCTAssertEqual(ledger.entry(for: .licensed)?.status, .absent)
        XCTAssertEqual(ledger.entry(for: .insured)?.status, .absent)
        XCTAssertEqual(ledger.entry(for: .certified)?.status, .absent)
        XCTAssertEqual(ledger.entry(for: .discountOffered)?.status, .absent)
        XCTAssertEqual(ledger.entry(for: .customDiscount)?.status, .absent)
        XCTAssertEqual(ledger.entry(for: .exactAvailabilitySlot)?.status, .absent)
        XCTAssertEqual(ledger.entry(for: .bookingConfirmation)?.status, .absent)

        XCTAssertEqual(ledger.entry(for: .responseTime)?.status, .unknown)

        XCTAssertFalse(ledger.entry(for: .licensed)?.mayAutoAnswer ?? true)
        XCTAssertTrue(ledger.entry(for: .licensed)?.requiresProviderConfirmation ?? false)
        XCTAssertEqual(ledger.entry(for: .bookingConfirmation)?.riskTier, .commitment)
    }

    func testBuild_discountFAQDoesNotMarkDiscountPresent() {
        let ledger = ProviderClaimLedgerBuilder.build(profile: nil, offer: sampleOffer())
        XCTAssertEqual(ledger.entry(for: .discountOffered)?.status, .absent)
        XCTAssertNil(ledger.entry(for: .discountOffered)?.sourceValuePreview)
    }

    func testBuild_profileHeadlineDoesNotMarkLicensedPresent() {
        let ledger = ProviderClaimLedgerBuilder.build(profile: sampleProfile(), offer: sampleOffer())
        XCTAssertEqual(ledger.entry(for: .licensed)?.status, .absent)
        XCTAssertEqual(ledger.entry(for: .insured)?.status, .absent)
    }

    func testBuild_pricingFromMinMaxOnly() {
        let offer = ExchangeOffer(
            id: "offer-price-range",
            nodeID: "node-1",
            title: "Consulting",
            commercialFacts: ExchangeOffer.CommercialFacts(priceMin: 100, priceMax: 250)
        )
        let ledger = ProviderClaimLedgerBuilder.build(profile: nil, offer: offer)
        XCTAssertEqual(ledger.entry(for: .pricing)?.status, .present)
        XCTAssertEqual(ledger.entry(for: .pricing)?.sourceField, "offer.commercial.priceMinMax")
    }

    func testBuild_nilOffer_credentialsAbsentServiceAreaFromProfile() {
        let ledger = ProviderClaimLedgerBuilder.build(profile: sampleProfile(), offer: nil)
        XCTAssertEqual(ledger.entry(for: .pricing)?.status, .absent)
        XCTAssertEqual(ledger.entry(for: .serviceArea)?.status, .present)
        XCTAssertEqual(ledger.entry(for: .serviceArea)?.sourceField, "profile.regionTags")
    }

    func testBuild_customQuoteRequiresConfirmation() {
        let ledger = ProviderClaimLedgerBuilder.build(profile: nil, offer: sampleOffer())
        XCTAssertEqual(ledger.entry(for: .customQuote)?.status, .absent)
        XCTAssertTrue(ledger.entry(for: .customQuote)?.requiresProviderConfirmation ?? false)
        XCTAssertEqual(ledger.entry(for: .customQuote)?.riskTier, .commitment)
    }

    #if DEBUG
    func testDebugSummary_nonEmpty() {
        let ledger = ProviderClaimLedgerBuilder.build(profile: sampleProfile(), offer: sampleOffer())
        XCTAssertTrue(ledger.debugSummary.contains("ProviderClaimLedger"))
        XCTAssertTrue(ledger.debugSummary.contains("pricing: present"))
        XCTAssertTrue(ledger.debugSummary.contains("licensed: absent"))
    }
    #endif
}
