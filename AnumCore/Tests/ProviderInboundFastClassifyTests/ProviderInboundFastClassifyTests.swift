import XCTest
@testable import AnumCore

final class ProviderInboundFastClassifyTests: XCTestCase {

    private func adjusted(
        userText: String,
        decodedLane: ExchangeIntent.QueryIntentClass = .socialAffinitySearch,
        decodedSurface: ExchangeIntent.SurfacePreference = .affinity,
        needsFull: Bool = false
    ) -> ProviderInboundFastClassificationRoutingRules.Adjustment {
        ProviderInboundFastClassificationRoutingRules.adjustedRouting(
            decodedQueryIntentClass: decodedLane,
            decodedSurfacePreference: decodedSurface,
            userText: userText,
            needsFullLLMInterpretation: needsFull
        )
    }

    private func assertNotSocialAffinity(
        _ adjustment: ProviderInboundFastClassificationRoutingRules.Adjustment,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotEqual(
            adjustment.queryIntentClass,
            .socialAffinitySearch,
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            adjustment.queryIntentClass,
            .relationshipSearch,
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            adjustment.surfacePreference,
            .affinity,
            file: file,
            line: line
        )
    }

    func testVCFounderOutreach_notSocialAffinity() {
        let text = """
        Hi Hansen,
        I'm looking for a vc and came across your profile Are you currently open to hearing from early-stage founders?
        Thank you,
        """
        let result = adjusted(userText: text)
        assertNotSocialAffinity(result)
        XCTAssertTrue(
            result.queryIntentClass == .directOutreach
                || result.queryIntentClass == .providerSearch
                || result.queryIntentClass == .offerSearch
        )
    }

    func testVCFounderOutreach_shortAsk_notSocialAffinity() {
        let result = adjusted(userText: "Are you currently open to hearing from early-stage founders?")
        assertNotSocialAffinity(result)
    }

    func testServiceAvailability_takingClients_notSocialAffinity() {
        let result = adjusted(userText: "Are you taking new clients for bookkeeping?")
        assertNotSocialAffinity(result)
        XCTAssertTrue(
            result.queryIntentClass == .directOutreach || result.queryIntentClass == .providerSearch
        )
    }

    func testOfferCapability_doYouOffer_notSocialAffinity() {
        let result = adjusted(userText: "Do you offer VC support for AI startups?")
        assertNotSocialAffinity(result)
        XCTAssertEqual(result.queryIntentClass, .providerSearch)
        XCTAssertEqual(result.surfacePreference, .offer)
    }

    func testTrueAffinity_swimming_staysSocialAffinity() {
        let result = adjusted(
            userText: "I'm looking for someone who likes swimming.",
            decodedLane: .socialAffinitySearch,
            decodedSurface: .affinity
        )
        XCTAssertEqual(result.queryIntentClass, .socialAffinitySearch)
        XCTAssertEqual(result.surfacePreference, .affinity)
    }

    func testAmbiguousOpenToChat_notConfidentSocialAffinity() {
        let result = adjusted(
            userText: "Would you be open to chat sometime next week?",
            decodedLane: .socialAffinitySearch,
            decodedSurface: .affinity,
            needsFull: false
        )
        assertNotSocialAffinity(result)
        XCTAssertEqual(result.queryIntentClass, .directOutreach)
        XCTAssertEqual(result.surfacePreference, .mixed)
        XCTAssertTrue(result.needsFullLLMInterpretation)
    }
}
