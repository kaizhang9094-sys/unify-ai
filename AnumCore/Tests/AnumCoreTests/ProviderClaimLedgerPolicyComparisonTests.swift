#if DEBUG
import XCTest
@testable import AnumCore

/// Haystack vs ledger policy comparison for ledger disagreement smoke fixtures (no LLM).
final class ProviderClaimLedgerPolicyComparisonTests: XCTestCase {

    private func comparison(forFixtureID id: String) -> ProviderClaimLedgerPolicyComparison {
        guard let fixture = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.first(where: { $0.id == id }) else {
            XCTFail("Missing fixture \(id)")
            return ProviderClaimLedgerPolicyComparison(
                detectedDimensions: [],
                oldAllowed: "",
                newAllowed: "",
                oldMissing: "",
                newMissing: "",
                fallbackHaystackUsed: [],
                disagreement: false
            )
        }
        let profile = ProviderInquiryAnswerOnDeviceSmokeAuditSupport.buildProfile(from: fixture)!
        let offer = ProviderInquiryAnswerOnDeviceSmokeAuditSupport.buildOffer(from: fixture)!
        let memory = ExchangeStructuredOperatingMemory()
        let allowedSurfaces = ProviderAllowedFactSurfaces(
            includePublicProfile: true,
            includeOffer: true,
            includeCommercialOffer: true,
            includeContactReachability: false,
            includeOperatingMemoryDelta: false,
            reason: "smoke_audit_ledger_probe",
            includeCommercialPricingFacts: true,
            includeCommercialNonPricingFacts: true
        )
        let sellerControlledFacts = ProviderInquiryCompareSmokeInputAssembly.sellerControlledFactsBlock(
            profile: profile,
            offer: offer,
            operatingMemory: memory,
            allowedSurfaces: allowedSurfaces
        )
        let detection = ProviderInboundDimensionDetector.detect(requesterText: fixture.requesterQuestion)
        let input = ProviderInboundClaimPolicyInput(
            requesterText: fixture.requesterQuestion,
            detection: detection,
            allowedSurfaces: allowedSurfaces,
            applyFactSurfaceGating: true,
            offer: offer,
            profile: profile,
            sellerControlledFacts: sellerControlledFacts
        )
        let ledger = ProviderClaimLedgerBuilder.build(profile: profile, offer: offer)
        return ProviderInboundClaimPolicyEngine.compareHaystackWithLedger(input, ledger: ledger).comparison
    }

    func testDiscountNegativeFAQ_disagreesHaystackVsLedger() {
        let c = comparison(forFixtureID: "ledger.discount_negative_faq")
        XCTAssertTrue(c.detectedDimensions.contains("discount"))
        XCTAssertTrue(c.disagreement, "FAQ discount mention should make haystack differ from ledger absent discount")
        XCTAssertTrue(c.newMissing.contains("discount"))
    }

    func testCredentialMarketingLanguage_disagreesWhenHaystackMatchesMarketingCopy() {
        let c = comparison(forFixtureID: "ledger.credential_marketing_language")
        XCTAssertTrue(
            c.detectedDimensions.contains("licenseInsurance")
                || c.detectedDimensions.contains("certification")
        )
        XCTAssertTrue(c.disagreement, "Marketing copy in offer_details should not count as structured credentials for ledger")
        XCTAssertTrue(c.newMissing.contains("licenseInsurance") || c.newMissing.contains("certification"))
    }

    func testExactSlotGeneralAvailability_ledgerMarksExactSlotAbsent() {
        let c = comparison(forFixtureID: "ledger.exact_slot_general_availability")
        XCTAssertTrue(c.detectedDimensions.contains("exactSlot"))
        XCTAssertTrue(c.newMissing.contains("exactSlot"))
    }

    func testWarrantyPresentLicenseAbsent_mixedMissingAndAllowed() {
        let c = comparison(forFixtureID: "ledger.warranty_present_license_absent")
        XCTAssertTrue(c.detectedDimensions.contains("warranty"))
        XCTAssertTrue(c.detectedDimensions.contains("licenseInsurance"))
        XCTAssertTrue(c.newAllowed.contains("warranty") || c.newAllowed.contains("warrantyPolicy"))
        XCTAssertTrue(c.newMissing.contains("licenseInsurance"))
    }

    func testCustomQuotePressure_commitmentRisk() {
        let c = comparison(forFixtureID: "ledger.custom_quote_pressure")
        XCTAssertTrue(
            c.detectedDimensions.contains("finalQuote") || c.detectedDimensions.contains("price")
        )
        XCTAssertTrue(c.newMissing.contains("booking") || c.newMissing.contains("finalQuote"))
    }

    func testLedgerDisagreementProbeCatalog() {
        for id in ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.ledgerDisagreementProbeIDs {
            XCTAssertNotNil(
                ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all.first(where: { $0.id == id }),
                "Probe fixture missing: \(id)"
            )
        }
        XCTAssertEqual(ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.ledgerDisagreementProbeIDs.count, 5)
    }
}
#endif
