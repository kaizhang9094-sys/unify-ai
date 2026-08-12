import XCTest
@testable import AnumCore

final class ProviderInboundIntentExtractionTests: XCTestCase {

    private func decode(_ json: String, raw: String = "inbound") throws -> ProviderInboundIntentExtraction {
        try ProviderInboundIntentExtractor.decode(cleanedJSON: json, rawRequesterAsk: raw)
    }

    func testDecodeValidJSON() throws {
        let json = """
        {"normalizedRequesterQuestion":"Are you open?","askSummary":"Openness ask","inquiryKind":"availabilityOrOpenness","requestedFactSurfaces":["publicProfile","reachability","availability","offer"],"requestedClaims":["openTo","availability"],"commercialIntent":true,"asksForCommitment":false,"asksForSensitiveInfo":false,"needsProviderInputLikely":false,"needsCompareLLM":true,"confidence":0.82,"rationaleShort":"founder outreach"}
        """
        let e = try decode(json, raw: "Are you open to hearing from early-stage founders?")
        XCTAssertEqual(e.inquiryKind, .availabilityOrOpenness)
        XCTAssertTrue(e.commercialIntent)
        XCTAssertEqual(e.rawRequesterAsk, "Are you open to hearing from early-stage founders?")
        XCTAssertTrue(e.requestedFactSurfaces.contains(.publicProfile))
        XCTAssertFalse(e.requestedFactSurfaces.isEmpty)
    }

    func testUnknownEnumValuesDropped() throws {
        let json = """
        {"normalizedRequesterQuestion":"q","askSummary":"s","inquiryKind":"notARealKind","requestedFactSurfaces":["publicProfile","fakeSurface"],"requestedClaims":["openTo","bogusClaim"],"commercialIntent":false,"asksForCommitment":false,"asksForSensitiveInfo":false,"needsProviderInputLikely":false,"needsCompareLLM":true,"confidence":0.7,"rationaleShort":"x"}
        """
        let e = try decode(json)
        XCTAssertEqual(e.inquiryKind, .unclear)
        XCTAssertEqual(e.requestedFactSurfaces, [.publicProfile])
        XCTAssertEqual(e.requestedClaims, [.openTo])
    }

    func testLowConfidenceMapsToConservativeSurfaces() {
        let e = ProviderInboundIntentExtraction(
            rawRequesterAsk: "hi",
            normalizedRequesterQuestion: "hi",
            askSummary: "hi",
            inquiryKind: .pricingOrQuote,
            requestedFactSurfaces: [.offer, .commercialPricing],
            requestedClaims: [.pricePosture],
            commercialIntent: true,
            asksForCommitment: false,
            asksForSensitiveInfo: false,
            needsProviderInputLikely: false,
            needsCompareLLM: true,
            confidence: 0.2,
            rationaleShort: "low"
        )
        let surfaces = ProviderAllowedFactSurfaces.derive(
            from: e,
            hasHydratedOffer: true,
            hasHydratedProfile: true
        )
        XCTAssertFalse(surfaces.includeOffer)
        XCTAssertEqual(surfaces.reason, "low_confidence_provider_inbound_extraction")
    }

    func testFounderOpenness_notSocialAffinity() throws {
        let json = fixtureJSON(
            kind: "availabilityOrOpenness",
            surfaces: ["publicProfile", "reachability", "availability", "offer"],
            claims: ["openTo", "availability"],
            commercial: true
        )
        let e = try decode(json, raw: "Are you currently open to hearing from early-stage founders?")
        XCTAssertEqual(e.inquiryKind, .availabilityOrOpenness)
        XCTAssertNotEqual(e.inquiryKind, .socialOrAffinityOnly)
        let surfaces = ProviderAllowedFactSurfaces.derive(from: e, hasHydratedOffer: true, hasHydratedProfile: true)
        XCTAssertTrue(surfaces.includePublicProfile)
        XCTAssertTrue(surfaces.includeOffer)
        XCTAssertFalse(surfaces.includeCommercialPricingFacts)
    }

    func testVCOffer_capabilityOrServiceFit() throws {
        let json = fixtureJSON(
            kind: "capabilityOrServiceFit",
            surfaces: ["offer", "publicProfile", "commercialNonPricing"],
            claims: ["serviceCapability"],
            commercial: true
        )
        let e = try decode(json, raw: "Do you offer VC support for AI startups?")
        XCTAssertEqual(e.inquiryKind, .capabilityOrServiceFit)
        let surfaces = ProviderAllowedFactSurfaces.derive(from: e, hasHydratedOffer: true, hasHydratedProfile: true)
        XCTAssertTrue(surfaces.includeOffer)
        XCTAssertFalse(surfaces.includeCommercialPricingFacts)
    }

    func testPricing_pricingOrQuote() throws {
        let json = fixtureJSON(
            kind: "pricingOrQuote",
            surfaces: ["offer", "commercialPricing"],
            claims: ["pricePosture", "quoteRequired"],
            commercial: true
        )
        let e = try decode(json, raw: "What is your pricing?")
        XCTAssertEqual(e.inquiryKind, .pricingOrQuote)
        let surfaces = ProviderAllowedFactSurfaces.derive(from: e, hasHydratedOffer: true, hasHydratedProfile: false)
        XCTAssertTrue(surfaces.includeCommercialPricingFacts)
    }

    func testCommitmentCall_asksForCommitment() throws {
        let json = """
        {"normalizedRequesterQuestion":"Can you commit to a call tomorrow?","askSummary":"Schedule commitment","inquiryKind":"schedulingOrTiming","requestedFactSurfaces":["offer","availability"],"requestedClaims":["commitment","availability"],"commercialIntent":true,"asksForCommitment":true,"asksForSensitiveInfo":false,"needsProviderInputLikely":true,"needsCompareLLM":true,"confidence":0.75,"rationaleShort":"scheduling commitment"}
        """
        let e = try decode(json)
        XCTAssertEqual(e.inquiryKind, .schedulingOrTiming)
        XCTAssertTrue(e.asksForCommitment)
    }

    func testIntroduceInvestors_sensitiveOrInput() throws {
        let json = """
        {"normalizedRequesterQuestion":"Can you introduce me to your investors?","askSummary":"Intro request","inquiryKind":"introductionOrContact","requestedFactSurfaces":["publicProfile","reachability"],"requestedClaims":["contactPreference"],"commercialIntent":false,"asksForCommitment":true,"asksForSensitiveInfo":true,"needsProviderInputLikely":true,"needsCompareLLM":true,"confidence":0.7,"rationaleShort":"intro"}
        """
        let e = try decode(json)
        XCTAssertEqual(e.inquiryKind, .introductionOrContact)
        XCTAssertTrue(e.asksForSensitiveInfo || e.asksForCommitment)
        XCTAssertTrue(e.needsProviderInputLikely)
    }

    func testSwimming_socialOrAffinityOnly() throws {
        let json = fixtureJSON(
            kind: "socialOrAffinityOnly",
            surfaces: ["publicProfile"],
            claims: [],
            commercial: false
        )
        let e = try decode(json, raw: "I'm looking for someone who likes swimming.")
        XCTAssertEqual(e.inquiryKind, .socialOrAffinityOnly)
        let surfaces = ProviderAllowedFactSurfaces.derive(from: e, hasHydratedOffer: true, hasHydratedProfile: true)
        XCTAssertTrue(surfaces.includePublicProfile)
        XCTAssertFalse(surfaces.includeOffer)
    }

    func testAutoSendBlockedWhenCompareRequiresProviderInput() {
        let compare = ExchangeProviderInquiryCompareResult(
            answerableFromOffer: false,
            knownAnswers: [],
            knownFacts: [],
            missingFacts: ["Binding quote"],
            needsProviderInput: true,
            draftReply: nil,
            reason: "needs provider",
            recommendedDisposition: "askProviderInput",
            canSendWithinConsent: false,
            requiresBoundaryApproval: false
        )
        let governed = ProviderInquiryCompareGovernor().evaluate(compare: compare, permissionPolicy: nil, boundaryHints: .init())
        XCTAssertEqual(governed.normalizedAction, .askProviderInput)

        let answerability = ExchangeProviderAnswerability(
            answerability: .answerableFromPublicFacts,
            knownFactsUsed: [],
            missingFacts: [],
            proposedAnswer: "We can help.",
            requiresHumanApproval: false,
            allowsAutonomousDrafting: true,
            allowsAutonomousSending: true,
            boundaryReason: "extractor said likely ok"
        )
        let decision = ExchangeAutonomousSendPolicy.evaluateProviderAutoResponse(
            .init(
                userAuthority: .fullWithinBoundaries,
                actionRaw: "autoRespond",
                canRunAutonomously: true,
                needsHumanAttention: false,
                boundaryRequiresApproval: false,
                pass3GateAllowed: true,
                hasVerifiedContextHold: false,
                hasCounterparty: true,
                hasDraft: true,
                isDuplicate: false,
                hasSelectedOfferAnchor: true,
                hasSelectedPublicProfileAnchor: true,
                providerAnswerability: answerability,
                canonicalCompareFirstDirectGroundedSend: false,
                compareFirstDirectClaimBoundaryBlocked: false
            )
        )
        XCTAssertFalse(decision.allowed)
    }

    private func fixtureJSON(
        kind: String,
        surfaces: [String],
        claims: [String],
        commercial: Bool
    ) -> String {
        let s = surfaces.map { "\"\($0)\"" }.joined(separator: ",")
        let c = claims.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"normalizedRequesterQuestion":"q","askSummary":"s","inquiryKind":"\(kind)","requestedFactSurfaces":[\(s)],"requestedClaims":[\(c)],"commercialIntent":\(commercial),"asksForCommitment":false,"asksForSensitiveInfo":false,"needsProviderInputLikely":false,"needsCompareLLM":true,"confidence":0.85,"rationaleShort":"fixture"}
        """
    }
}
