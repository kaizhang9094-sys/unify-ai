import XCTest
@testable import AnumCore

final class ExchangeProviderDetailsPresentationContextTests: XCTestCase {

    // MARK: - Thread derivation

    func testHansenCommercialProviderBothAnchorsOfferLed() {
        let context = ExchangeProviderDetailsPresentationContextResolver.derive(
            lane: .commercialInquiry,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            surfaceLead: .offerLed,
            hasOfferAnchor: true,
            hasProfileAnchor: true
        )
        XCTAssertEqual(context, .commercialOpportunity)
    }

    func testSocialLaneBothAnchorsReturnsSocialProfile() {
        let context = ExchangeProviderDetailsPresentationContextResolver.derive(
            lane: .socialConnection,
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            surfaceLead: .offerLed,
            hasOfferAnchor: true,
            hasProfileAnchor: true
        )
        XCTAssertEqual(context, .socialProfile)
    }

    func testUnknownLaneGeneralDiscoveryBothAnchorsAmbiguous() {
        let context = ExchangeProviderDetailsPresentationContextResolver.derive(
            lane: .unknown,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            surfaceLead: .ambiguous,
            hasOfferAnchor: true,
            hasProfileAnchor: true
        )
        XCTAssertEqual(context, .mixedHydrated)
    }

    func testCommercialInquiryProfileLedProviderSearch() {
        let context = ExchangeProviderDetailsPresentationContextResolver.derive(
            lane: .commercialInquiry,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            surfaceLead: .profileLed,
            hasOfferAnchor: false,
            hasProfileAnchor: true
        )
        XCTAssertEqual(context, .opportunityProfile)
    }

    func testCommercialInquiryCapabilitySearchOfferLedBothAnchors() {
        let context = ExchangeProviderDetailsPresentationContextResolver.derive(
            lane: .commercialInquiry,
            queryIntentClass: .capabilitySearch,
            surfacePreference: .capability,
            surfaceLead: .offerLed,
            hasOfferAnchor: true,
            hasProfileAnchor: true
        )
        XCTAssertEqual(context, .commercialOpportunity)
    }

    // MARK: - For You candidate derivation

    func testForYouOfferLedWithProfileAndOffer() {
        let context = ExchangeProviderDetailsPresentationContextResolver.deriveForCandidate(
            surfaceLead: .offerLed,
            hasProfile: true,
            hasOffer: true
        )
        XCTAssertEqual(context, .commercialOpportunity)
    }

    func testForYouProfileLedWithProfileAndOffer() {
        let context = ExchangeProviderDetailsPresentationContextResolver.deriveForCandidate(
            surfaceLead: .profileLed,
            hasProfile: true,
            hasOffer: true
        )
        XCTAssertEqual(context, .opportunityProfile)
    }

    func testForYouAmbiguousBothHydrated() {
        let context = ExchangeProviderDetailsPresentationContextResolver.deriveForCandidate(
            surfaceLead: .ambiguous,
            hasProfile: true,
            hasOffer: true
        )
        XCTAssertEqual(context, .mixedHydrated)
    }
}
