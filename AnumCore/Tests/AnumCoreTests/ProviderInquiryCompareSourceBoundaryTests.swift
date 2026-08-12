import XCTest
@testable import AnumCore

final class ProviderInquiryCompareSourceBoundaryTests: XCTestCase {

    private let commercialOnly = ProviderAllowedFactSurfaces(
        includePublicProfile: false,
        includeOffer: true,
        includeCommercialOffer: true,
        includeContactReachability: false,
        includeOperatingMemoryDelta: true,
        reason: "transactional_offer_surface"
    )

    private func offerOnlyFactsBlock() -> String {
        """
        === OFFER_FACTS ===
        offer_title: Residential plumbing service in Austin
        price_display: Service call $89
        === END OFFER_FACTS ===
        """
    }

    func testCommercialOnlyPayloadExcludesProfileSources() {
        let context = ProviderInquiryCompareSourceBoundary.Context.make(
            allowedSurfaces: commercialOnly,
            profileSummary: nil,
            offerSummary: "Service call $89",
            sellerControlledFacts: offerOnlyFactsBlock(),
            selectedProfileID: nil
        )
        let audit = ProviderInquiryCompareSourceBoundary.auditPayload(context)
        XCTAssertFalse(audit.profileSummaryPresent)
        XCTAssertFalse(audit.profileFactsPresent)
        XCTAssertFalse(audit.profileDerivedHintsPresent)
        XCTAssertTrue(audit.violations.isEmpty)
    }

    func testCommercialOnlyPayloadFlagsProfileLeak() {
        let context = ProviderInquiryCompareSourceBoundary.Context.make(
            allowedSurfaces: commercialOnly,
            profileSummary: "Austin-area plumbing professional",
            offerSummary: "Service call $89",
            sellerControlledFacts: """
            === PROFILE_FACTS ===
            profile_headline: plumber
            === END PROFILE_FACTS ===
            \(offerOnlyFactsBlock())
            """,
            selectedProfileID: "profile-1"
        )
        let audit = ProviderInquiryCompareSourceBoundary.auditPayload(context)
        XCTAssertTrue(audit.profileSummaryPresent)
        XCTAssertTrue(audit.profileFactsPresent)
        XCTAssertTrue(audit.profileDerivedHintsPresent)
        XCTAssertFalse(audit.violations.isEmpty)
    }

    func testCommercialOnlyKnownAnswersCannotUseProfileSource() {
        let context = ProviderInquiryCompareSourceBoundary.Context.make(
            allowedSurfaces: commercialOnly,
            profileSummary: nil,
            offerSummary: "Service call $89",
            sellerControlledFacts: offerOnlyFactsBlock(),
            selectedProfileID: nil
        )
        let raw = ExchangeProviderInquiryCompareResult(
            answerableFromOffer: false,
            knownAnswers: [
                "The seller's profile indicates they are a plumber offering residential plumbing service in Austin."
            ],
            knownFacts: [],
            missingFacts: [],
            needsProviderInput: true,
            draftReply: nil,
            reason: "test"
        )
        let filtered = ProviderInquiryCompareSourceBoundary.applyToCompareResult(raw, context: context)
        XCTAssertTrue(filtered.knownAnswers.isEmpty)
    }

    func testCommercialOnlyKeepsOfferGroundedKnownAnswers() {
        let context = ProviderInquiryCompareSourceBoundary.Context.make(
            allowedSurfaces: commercialOnly,
            profileSummary: nil,
            offerSummary: "Service call $89",
            sellerControlledFacts: offerOnlyFactsBlock(),
            selectedProfileID: nil
        )
        let raw = ExchangeProviderInquiryCompareResult(
            answerableFromOffer: true,
            knownAnswers: ["Published service call price is $89."],
            knownFacts: [],
            missingFacts: [],
            needsProviderInput: false,
            draftReply: "Service call $89.",
            reason: "test"
        )
        let filtered = ProviderInquiryCompareSourceBoundary.applyToCompareResult(raw, context: context)
        XCTAssertEqual(filtered.knownAnswers.count, 1)
    }

    func testSourceBoundaryLogShowsNoProfileLeak_fixture13Style() {
        let context = ProviderInquiryCompareSourceBoundary.Context.make(
            allowedSurfaces: commercialOnly,
            profileSummary: nil,
            offerSummary: "Residential plumbing service in Austin · Emergency repairs",
            sellerControlledFacts: offerOnlyFactsBlock(),
            selectedProfileID: nil
        )
        let audit = ProviderInquiryCompareSourceBoundary.auditPayload(context)
        XCTAssertEqual(audit.boundaryLabel, "commercialOnly")
        XCTAssertFalse(audit.profileSummaryPresent)
        XCTAssertFalse(audit.profileFactsPresent)
        XCTAssertFalse(audit.profileDerivedHintsPresent)
    }

    func testMaskedSelectedProfileID_nilWhenExcluded() {
        XCTAssertNil(
            ProviderInquiryCompareSourceBoundary.maskedSelectedProfileID(
                selectedProfileID: "abc",
                includePublicProfile: false
            )
        )
    }
}
