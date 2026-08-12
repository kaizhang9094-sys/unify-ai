import XCTest
@testable import AnumCore

final class ProviderInquiryCompareDecodeTests: XCTestCase {

    private let liveFlatJSON = """
    {
      "answerableFromOffer": true,
      "knownAnswers": [
        "We are open to hearing from early-stage founders."
      ],
      "knownFacts": [],
      "missingFacts": [
        "Specific availability for today/tomorrow,",
        "Exact service scope or pricing details"
      ],
      "needsProviderInput": false,
      "draftReply": "We are open to hearing from early-stage founders. However, we would need to confirm your specific availability and the details of what you're looking for before proceeding.",
      "replyToSend": null,
      "reason": "General policy acceptance confirmed; specific scheduling and scope details required from provider.",
      "intentCategory": "inquiry",
      "inquirySummary": "Inquiry about Vc services for early-stage founders.",
      "requesterAsk": "Are you currently open to hearing from early-stage founders?",
      "riskFlags": [],
      "recommendedDisposition": "sendWithinConsent",
      "canSendWithinConsent": true,
      "requiresBoundaryApproval": false,
      "consentBasis": "User explicitly asked about early-stage founders and profile indicates openness.",
      "boundaryCrossingReason": null
    }
    """

    private func opennessIntent() -> ProviderInboundIntentExtraction {
        ProviderInboundIntentExtraction(
            rawRequesterAsk: "Are you currently open to hearing from early-stage founders?",
            normalizedRequesterQuestion: "Are you currently open to hearing from early-stage founders?",
            askSummary: "Openness ask",
            inquiryKind: .availabilityOrOpenness,
            requestedFactSurfaces: [.publicProfile, .reachability, .availability, .offer],
            requestedClaims: [.openTo, .availability],
            commercialIntent: true,
            asksForCommitment: false,
            asksForSensitiveInfo: false,
            needsProviderInputLikely: false,
            needsCompareLLM: true,
            confidence: 0.95,
            rationaleShort: "fixture"
        )
    }

    func testDecodeCanonicalFlatSchemaFromLiveE2EJSON() throws {
        let result = try XCTUnwrap(
            ProviderInquiryCompareJSONCodec.decode(
                raw: liveFlatJSON,
                inboundIntent: opennessIntent(),
                requesterAskFallback: "Are you currently open to hearing from early-stage founders?"
            ).get()
        )
        XCTAssertEqual(result.recommendedDisposition, "sendWithinConsent")
        XCTAssertEqual(result.canSendWithinConsent, true)
        XCTAssertEqual(result.requiresBoundaryApproval, false)
        XCTAssertEqual(result.needsProviderInput, false)
        XCTAssertEqual(result.consentBasis?.isEmpty, false)
    }

    func testSchemaEchoThenValidObject_decodesLastObject() throws {
        let raw = """
        {
          "answerableFromOffer": Bool,
          "knownAnswers": [String]
        }
        \(liveFlatJSON)
        """
        let result = try XCTUnwrap(ProviderInquiryCompareJSONCodec.decode(raw: raw, inboundIntent: opennessIntent()).get())
        XCTAssertEqual(result.recommendedDisposition, "sendWithinConsent")
    }

    func testOpennessNormalization_stripsInventedMissingFacts() throws {
        let result = try XCTUnwrap(
            ProviderInquiryCompareJSONCodec.decode(
                raw: liveFlatJSON,
                inboundIntent: opennessIntent(),
                requesterAskFallback: "Are you currently open to hearing from early-stage founders?"
            ).get()
        )
        XCTAssertTrue(result.missingFacts.isEmpty, "pricing/scheduling scope gaps should not block openness ask")
    }

    func testOpennessFixture_expectSendWithinConsent() {
        let mapped = ProviderInquiryCompareJSONCodec.mapFlatDTO(
            ProviderInquiryCompareJSONCodec.FlatDTO(
                answerableFromOffer: true,
                knownAnswers: ["Open to hearing from early-stage founders, including AI and pharmaceutical startups."],
                knownFacts: [],
                missingFacts: [],
                needsProviderInput: false,
                draftReply: "Yes — Hansen is open to hearing from early-stage founders, especially AI and pharmaceutical startups.",
                replyToSend: nil,
                reason: "Profile open_to",
                intentCategory: "openness",
                inquirySummary: nil,
                requesterAsk: "Are you currently open to hearing from early-stage founders?",
                riskFlags: [],
                recommendedDisposition: "sendWithinConsent",
                recommendedAction: nil,
                consentBasis: nil,
                boundaryCrossingReason: nil,
                canSendWithinConsent: true,
                requiresBoundaryApproval: false
            )
        )
        let normalized = ProviderInquiryCompareJSONCodec.normalizeForInboundIntent(
            mapped,
            inboundIntent: opennessIntent(),
            requesterAskFallback: nil
        )
        XCTAssertEqual(normalized.recommendedDisposition, "sendWithinConsent")
        XCTAssertFalse(normalized.needsProviderInput)
        XCTAssertFalse(normalized.requiresBoundaryApproval == true)
    }

    func testGovernorBlocksAutoSendWhenCompareRequiresProviderInput() {
        let compare = ExchangeProviderInquiryCompareResult(
            answerableFromOffer: false,
            knownAnswers: [],
            missingFacts: ["License not confirmed"],
            needsProviderInput: true,
            draftReply: "We'd need to confirm license first.",
            reason: "gap",
            recommendedDisposition: "askProviderInput",
            canSendWithinConsent: false,
            requiresBoundaryApproval: false
        )
        let outcome = ProviderInquiryCompareGovernor().evaluate(
            compare: compare,
            permissionPolicy: nil,
            boundaryHints: .init()
        )
        XCTAssertEqual(outcome.normalizedAction, .askProviderInput)
    }

    func testTruncatedJSONRepair_closesObject() {
        let truncated = """
        {"answerableFromOffer":true,"knownAnswers":["open"],"knownFacts":[],"missingFacts":[],"needsProviderInput":false,"draftReply":"Yes","replyToSend":null,"reason":"ok","intentCategory":"openness","riskFlags":[],"recommendedDisposition":"sendWithinConsent","canSendWithinConsent":true,"requiresBoundaryApproval":false
        """
        let result = ProviderInquiryCompareJSONCodec.decode(raw: truncated, inboundIntent: opennessIntent())
        switch result {
        case .success(let mapped):
            XCTAssertEqual(mapped.recommendedDisposition, "sendWithinConsent")
        case .failure(let err):
            XCTFail("expected repair decode, got \(err.logTag)")
        }
    }

    private let livePythonNoneTailJSON = """
    {
    "answerableFromOffer":true,
    "knownAnswers":["Open to hearing from early-stage founders."],
    "knownFacts":[],
    "missingFacts":[],
    "needsProviderInput":false,
    "draftReply":"Yes — we're open to hearing from early-stage founders, especially AI and pharmaceutical startups.",
    "replyToSend":null,
    "reason":"Profile open_to answers the outreach question.",
    "intentCategory":"openness",
    "inquirySummary":"Inbound inquiry about provider openness to early-stage founders.",
    "requesterAsk":"Are you currently open to hearing from early-stage founders?",
    "riskFlags":[],
    "recommendedDisposition":"sendWithinConsent",
    "canSendWithinConsent":true,
    "requiresBoundaryApproval":false,
    "consentBasis":"Profile open_to field explicitly states openness to early-stage founders.",
    "boundaryCrossingReason":None"
    }
    """

    func testLivePythonNoneTail_decodesAfterLiteralNormalization() throws {
        let repaired = ProviderInquiryCompareJSONCodec.normalizeInvalidJSONLiterals(livePythonNoneTailJSON)
        XCTAssertTrue(
            repaired.contains("\"boundaryCrossingReason\":null")
                || repaired.contains("\"boundaryCrossingReason\": null")
        )
        XCTAssertFalse(repaired.contains(":None"))

        let result = try XCTUnwrap(
            ProviderInquiryCompareJSONCodec.decode(
                raw: livePythonNoneTailJSON,
                inboundIntent: opennessIntent(),
                requesterAskFallback: "Are you currently open to hearing from early-stage founders?"
            ).get()
        )
        XCTAssertEqual(result.recommendedDisposition, "sendWithinConsent")
        XCTAssertEqual(result.needsProviderInput, false)
        XCTAssertEqual(result.canSendWithinConsent, true)
        XCTAssertEqual(result.requiresBoundaryApproval, false)
        XCTAssertTrue(result.missingFacts.isEmpty)
        XCTAssertNil(result.boundaryCrossingReason)
    }

    func testQuotedStringNone_boundaryCrossingReasonDecodesNil() throws {
        let raw = """
        {"answerableFromOffer":true,"knownAnswers":["open"],"knownFacts":[],"missingFacts":[],"needsProviderInput":false,"draftReply":"Yes","replyToSend":null,"reason":"ok","intentCategory":"openness","riskFlags":[],"recommendedDisposition":"sendWithinConsent","canSendWithinConsent":true,"requiresBoundaryApproval":false,"boundaryCrossingReason":"None"}
        """
        let result = try XCTUnwrap(ProviderInquiryCompareJSONCodec.decode(raw: raw).get())
        XCTAssertNil(result.boundaryCrossingReason)
    }

    func testPythonTrueFalse_normalizedOutsideStrings() {
        let raw = #"{"answerableFromOffer":True,"needsProviderInput":False,"riskFlags":[]}"#
        let normalized = ProviderInquiryCompareJSONCodec.normalizeInvalidJSONLiterals(raw)
        XCTAssertTrue(normalized.contains(":true"))
        XCTAssertTrue(normalized.contains(":false"))
    }

    private let liveMalformedTrailingQuoteCommaJSON = """
    {
    "answerableFromOffer":true,
    "knownAnswers":["Open to hearing from early-stage founders."],
    "knownFacts":[],
    "missingFacts":[],
    "needsProviderInput":false,
    "draftReply":"Yes — we're open to hearing from early-stage founders, especially AI and pharmaceutical startups.","
    "replyToSend":null,
    "reason":"Profile open_to answers the outreach question.","
    "intentCategory":"openness",
    "inquirySummary":"Inbound inquiry about provider openness to early-stage founders.",
    "requesterAsk":"Are you currently open to hearing from early-stage founders?",
    "riskFlags":[],
    "recommendedDisposition":"sendWithinConsent",
    "canSendWithinConsent":true,
    "requiresBoundaryApproval":false,
    "consentBasis":"Profile open_to field explicitly states openness to early-stage founders.",
    "boundaryCrossingReason":null
    }
    """

    func testLiveMalformedTrailingQuoteComma_decodesFlatCompare() throws {
        let prepared = ProviderInquiryCompareJSONCodec.prepareTextForJSONObjectExtraction(
            liveMalformedTrailingQuoteCommaJSON
        )
        let candidates = ProviderInquiryCompareJSONCodec.collectJSONObjectCandidates(
            from: liveMalformedTrailingQuoteCommaJSON
        )
        XCTAssertFalse(
            candidates.isEmpty,
            "no candidates; prepared=\(prepared)"
        )

        let result = try XCTUnwrap(
            ProviderInquiryCompareJSONCodec.decode(
                raw: liveMalformedTrailingQuoteCommaJSON,
                inboundIntent: opennessIntent(),
                requesterAskFallback: "Are you currently open to hearing from early-stage founders?"
            ).get()
        )
        XCTAssertEqual(result.recommendedDisposition, "sendWithinConsent")
        XCTAssertEqual(result.needsProviderInput, false)
        XCTAssertEqual(result.canSendWithinConsent, true)
        XCTAssertEqual(
            result.draftReply,
            "Yes — we're open to hearing from early-stage founders, especially AI and pharmaceutical startups."
        )
    }

    func testCommaQuoteKeySeparatorRepair_draftReplyFragment() {
        let broken = """
        "draftReply":"Yes — we're open to hearing from early-stage founders, especially AI and pharmaceutical startups.","
        "replyToSend":null
        """
        let repaired = ProviderInquiryCompareJSONCodec.repairCommaQuoteKeySeparatorGlitch(broken)
        XCTAssertTrue(repaired.contains(
            """
            "draftReply":"Yes — we're open to hearing from early-stage founders, especially AI and pharmaceutical startups.",
            "replyToSend":null
            """
        ))
        XCTAssertFalse(repaired.contains("startups.\",\""))
    }

    func testCommaQuoteKeySeparatorRepair_reasonFragment() throws {
        let broken = """
        "reason":"Profile open_to answers the outreach question.","
        "intentCategory":"openness"
        """
        let repaired = ProviderInquiryCompareJSONCodec.repairCommaQuoteKeySeparatorGlitch(broken)
        XCTAssertTrue(repaired.contains(
            """
            "reason":"Profile open_to answers the outreach question.",
            "intentCategory":"openness"
            """
        ))

        let wrapped = "{\(repaired)}"
        let result = try XCTUnwrap(ProviderInquiryCompareJSONCodec.decode(raw: wrapped).get())
        XCTAssertEqual(result.reason, "Profile open_to answers the outreach question.")
        XCTAssertEqual(result.intentCategory, "openness")
    }

    func testLiveMalformedTrailingQuoteComma_reasonFieldPreserved() throws {
        let result = try XCTUnwrap(
            ProviderInquiryCompareJSONCodec.decode(
                raw: liveMalformedTrailingQuoteCommaJSON,
                inboundIntent: opennessIntent()
            ).get()
        )
        XCTAssertEqual(result.reason, "Profile open_to answers the outreach question.")
    }
}
