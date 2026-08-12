import XCTest
@testable import AnumCore

final class ProviderAllowedFactSurfacesTests: XCTestCase {
    func testDeriveOfferSearchOfferSurface() {
        let latest = ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            mode: .transactional,
            kind: .find,
            readiness: .ready,
            confidence: 0.9,
            needsFullLLMInterpretation: false
        )
        let s = ProviderAllowedFactSurfaces.derive(latestInbound: latest)
        XCTAssertFalse(s.includePublicProfile)
        XCTAssertTrue(s.includeOffer)
        XCTAssertTrue(s.includeCommercialOffer)
        XCTAssertFalse(s.includeContactReachability)
        XCTAssertTrue(s.includeOperatingMemoryDelta)
    }

    func testDeriveAffinitySurface() {
        let latest = ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            mode: .relational,
            kind: .find,
            readiness: .ready,
            confidence: 0.88,
            needsFullLLMInterpretation: false
        )
        let s = ProviderAllowedFactSurfaces.derive(latestInbound: latest)
        XCTAssertTrue(s.includePublicProfile)
        XCTAssertFalse(s.includeOffer)
        XCTAssertFalse(s.includeCommercialOffer)
        XCTAssertTrue(s.includeContactReachability)
    }

    func testDeriveLowConfidenceConservative() {
        let latest = ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            mode: .transactional,
            kind: .find,
            readiness: .ready,
            confidence: 0.2,
            needsFullLLMInterpretation: false
        )
        let s = ProviderAllowedFactSurfaces.derive(latestInbound: latest)
        XCTAssertEqual(s.reason, "low_confidence_inbound_classification")
        XCTAssertFalse(s.includeOffer)
    }

    func testDeriveNeedsFullMixedUsesOfferGeographyWithoutPricing() {
        let latest = ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            mode: .transactional,
            kind: .find,
            readiness: .ready,
            confidence: 0.9,
            needsFullLLMInterpretation: true
        )
        let s = ProviderAllowedFactSurfaces.derive(latestInbound: latest)
        XCTAssertEqual(s.reason, "needs_full_mixed_offer_geography_without_pricing")
        XCTAssertTrue(s.includeOffer)
        XCTAssertTrue(s.includeCommercialOffer)
        XCTAssertTrue(s.includeCommercialNonPricingFacts)
        XCTAssertFalse(s.includeCommercialPricingFacts)
        XCTAssertFalse(s.includePublicProfile)
        XCTAssertFalse(s.includeContactReachability)
    }

    func testClassificationDecodeFailedIsMinimal() {
        let s = ProviderAllowedFactSurfaces.classificationDecodeFailed
        XCTAssertEqual(s.reason, "classification_decode_failed_conservative_unknown")
        XCTAssertFalse(s.includeOffer)
        XCTAssertFalse(s.includeOperatingMemoryDelta)
        XCTAssertFalse(s.includeCommercialPricingFacts)
        XCTAssertFalse(s.includeCommercialNonPricingFacts)
    }
}
