import XCTest
@testable import AnumCore

final class ProviderInboundDimensionDetectorTests: XCTestCase {

    func testMissingDiscount_detectsDiscountAndHighClaim() {
        let d = ProviderInboundDimensionDetector.detect(
            requesterText: "Can you do 20% off if I book today?"
        )
        XCTAssertTrue(d.askedDimensions.contains(.discount))
        XCTAssertGreaterThanOrEqual(d.riskTier, .highClaim)
    }

    func testMissingExactSlot_detectsExactSlotAndMediumScope() {
        let d = ProviderInboundDimensionDetector.detect(
            requesterText: "Can you confirm 2:30–4:00 PM Saturday?"
        )
        XCTAssertTrue(d.askedDimensions.contains(.exactSlot))
        XCTAssertEqual(d.riskTier, .mediumScope)
    }

    func testMissingWarrantyCert_detectsLicenseInsurance() {
        let d = ProviderInboundDimensionDetector.detect(
            requesterText: "Are you licensed and insured for this work?"
        )
        XCTAssertTrue(d.askedDimensions.contains(.licenseInsurance))
        XCTAssertEqual(d.riskTier, .highClaim)
    }

    func testOutsideServiceArea_detectsServiceArea() {
        let d = ProviderInboundDimensionDetector.detect(
            requesterText: "Can you come to Houston same day?"
        )
        XCTAssertTrue(d.askedDimensions.contains(.serviceArea))
    }

    func testCommitmentBooking_detectsBookingFinalQuoteAndCommitmentTier() {
        let d = ProviderInboundDimensionDetector.detect(
            requesterText: "Great — please book me for Saturday and send a final quote of $200."
        )
        XCTAssertTrue(d.askedDimensions.contains(.booking))
        XCTAssertTrue(d.askedDimensions.contains(.finalQuote))
        XCTAssertEqual(d.riskTier, .commitment)
    }
}
