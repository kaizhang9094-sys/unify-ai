import Foundation

/// Structured output from the on-device LLM comparing the requester's ask to a matched offer/profile.
public struct ExchangeRequesterMatchCompareResult: Codable, Sendable, Hashable {
    public var missingFacts: [String]
    public var providerQuestions: [String]
    public var shouldAskProvider: Bool
    public var reason: String

    public init(
        missingFacts: [String] = [],
        providerQuestions: [String] = [],
        shouldAskProvider: Bool = false,
        reason: String = ""
    ) {
        self.missingFacts = missingFacts
        self.providerQuestions = providerQuestions
        self.shouldAskProvider = shouldAskProvider
        self.reason = reason
    }
}

/// Optional structured fact line from provider inquiry compare (additive schema).
public struct ExchangeProviderInquiryCompareKnownFact: Codable, Sendable, Hashable {
    public var fact: String
    public var source: String?
    public var confidence: Double?

    public init(fact: String, source: String? = nil, confidence: Double? = nil) {
        self.fact = fact
        self.source = source
        self.confidence = confidence
    }
}

/// Structured output from the on-device LLM comparing an inbound inquiry to seller surface facts.
public struct ExchangeProviderInquiryCompareResult: Codable, Sendable, Hashable {
    public var answerableFromOffer: Bool
    public var knownAnswers: [String]
    /// Additive richer grounding lines (optional; may be empty on older decodes).
    public var knownFacts: [ExchangeProviderInquiryCompareKnownFact]
    public var missingFacts: [String]
    public var needsProviderInput: Bool
    public var draftReply: String?
    public var reason: String

    // MARK: - Extended (additive) interpreter fields

    public var intentCategory: String?
    public var inquirySummary: String?
    public var requesterAsk: String?
    public var riskFlags: [String]
    /// Raw model recommendation, e.g. `sendWithinConsent`, `holdForBoundaryApproval`.
    public var recommendedDisposition: String?
    /// Explicit model consent signals (optional; when absent, governor derives from disposition + policy).
    public var canSendWithinConsent: Bool?
    public var requiresBoundaryApproval: Bool?
    public var consentBasis: String?
    public var boundaryCrossingReason: String?

    public init(
        answerableFromOffer: Bool = false,
        knownAnswers: [String] = [],
        knownFacts: [ExchangeProviderInquiryCompareKnownFact] = [],
        missingFacts: [String] = [],
        needsProviderInput: Bool = true,
        draftReply: String? = nil,
        reason: String = "",
        intentCategory: String? = nil,
        inquirySummary: String? = nil,
        requesterAsk: String? = nil,
        riskFlags: [String] = [],
        recommendedDisposition: String? = nil,
        canSendWithinConsent: Bool? = nil,
        requiresBoundaryApproval: Bool? = nil,
        consentBasis: String? = nil,
        boundaryCrossingReason: String? = nil
    ) {
        self.answerableFromOffer = answerableFromOffer
        self.knownAnswers = knownAnswers
        self.knownFacts = knownFacts
        self.missingFacts = missingFacts
        self.needsProviderInput = needsProviderInput
        self.draftReply = draftReply
        self.reason = reason
        self.intentCategory = intentCategory
        self.inquirySummary = inquirySummary
        self.requesterAsk = requesterAsk
        self.riskFlags = riskFlags
        self.recommendedDisposition = recommendedDisposition
        self.canSendWithinConsent = canSendWithinConsent
        self.requiresBoundaryApproval = requiresBoundaryApproval
        self.consentBasis = consentBasis
        self.boundaryCrossingReason = boundaryCrossingReason
    }

    enum CodingKeys: String, CodingKey {
        case answerableFromOffer
        case knownAnswers
        case knownFacts
        case missingFacts
        case needsProviderInput
        case draftReply
        case reason
        case intentCategory
        case inquirySummary
        case requesterAsk
        case riskFlags
        case recommendedDisposition
        case canSendWithinConsent
        case requiresBoundaryApproval
        case consentBasis
        case boundaryCrossingReason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answerableFromOffer = try c.decodeIfPresent(Bool.self, forKey: .answerableFromOffer) ?? false
        knownAnswers = try c.decodeIfPresent([String].self, forKey: .knownAnswers) ?? []
        knownFacts = try c.decodeIfPresent([ExchangeProviderInquiryCompareKnownFact].self, forKey: .knownFacts) ?? []
        missingFacts = try c.decodeIfPresent([String].self, forKey: .missingFacts) ?? []
        needsProviderInput = try c.decodeIfPresent(Bool.self, forKey: .needsProviderInput) ?? true
        draftReply = try c.decodeIfPresent(String.self, forKey: .draftReply)
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        intentCategory = try c.decodeIfPresent(String.self, forKey: .intentCategory)
        inquirySummary = try c.decodeIfPresent(String.self, forKey: .inquirySummary)
        requesterAsk = try c.decodeIfPresent(String.self, forKey: .requesterAsk)
        riskFlags = try c.decodeIfPresent([String].self, forKey: .riskFlags) ?? []
        recommendedDisposition = try c.decodeIfPresent(String.self, forKey: .recommendedDisposition)
        canSendWithinConsent = try c.decodeIfPresent(Bool.self, forKey: .canSendWithinConsent)
        requiresBoundaryApproval = try c.decodeIfPresent(Bool.self, forKey: .requiresBoundaryApproval)
        consentBasis = try c.decodeIfPresent(String.self, forKey: .consentBasis)
        boundaryCrossingReason = try c.decodeIfPresent(String.self, forKey: .boundaryCrossingReason)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(answerableFromOffer, forKey: .answerableFromOffer)
        try c.encode(knownAnswers, forKey: .knownAnswers)
        try c.encode(knownFacts, forKey: .knownFacts)
        try c.encode(missingFacts, forKey: .missingFacts)
        try c.encode(needsProviderInput, forKey: .needsProviderInput)
        try c.encodeIfPresent(draftReply, forKey: .draftReply)
        try c.encode(reason, forKey: .reason)
        try c.encodeIfPresent(intentCategory, forKey: .intentCategory)
        try c.encodeIfPresent(inquirySummary, forKey: .inquirySummary)
        try c.encodeIfPresent(requesterAsk, forKey: .requesterAsk)
        try c.encode(riskFlags, forKey: .riskFlags)
        try c.encodeIfPresent(recommendedDisposition, forKey: .recommendedDisposition)
        try c.encodeIfPresent(canSendWithinConsent, forKey: .canSendWithinConsent)
        try c.encodeIfPresent(requiresBoundaryApproval, forKey: .requiresBoundaryApproval)
        try c.encodeIfPresent(consentBasis, forKey: .consentBasis)
        try c.encodeIfPresent(boundaryCrossingReason, forKey: .boundaryCrossingReason)
    }
}
