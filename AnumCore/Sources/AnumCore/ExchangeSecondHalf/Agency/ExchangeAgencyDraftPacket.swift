import Foundation

public enum ExchangeAgencyDraftRequiredIntent: String, Codable, Sendable, Hashable {
    case requesterClarificationOnly
    case requesterRecommendNextMoveHuman
    case requesterFrameDecisionHuman
    case providerGroundedAnswerOnly
    case providerPartialAnswerOrEscalation
}

/// Requester autonomous outbound compose mode (Pass-2 agency packets).
public enum RequesterAutonomousOutboundComposeMode: String, Codable, Sendable, Hashable {
    case askClarification
    case recommendNextMove
    case frameDecision
}

/// Optional composer enrichment contract (separate from compare-required provider questions).
public struct RequesterOutboundComposeContract: Codable, Sendable, Hashable {
    public var routingSurface: String?
    public var requiredProviderQuestionLines: [String]
    public var allowedEnrichmentDimensions: [RequesterOutboundEnrichmentDimension]
    public var allowedEnrichmentHints: [String]
    public var maxOptionalEnrichmentCount: Int

    public init(
        routingSurface: String? = nil,
        requiredProviderQuestionLines: [String] = [],
        allowedEnrichmentDimensions: [RequesterOutboundEnrichmentDimension] = [],
        allowedEnrichmentHints: [String] = [],
        maxOptionalEnrichmentCount: Int = 1
    ) {
        self.routingSurface = routingSurface
        self.requiredProviderQuestionLines = requiredProviderQuestionLines
        self.allowedEnrichmentDimensions = allowedEnrichmentDimensions
        self.allowedEnrichmentHints = allowedEnrichmentHints
        self.maxOptionalEnrichmentCount = max(0, maxOptionalEnrichmentCount)
    }
}

public struct RequesterClarificationDraftPacket: Codable, Sendable, Hashable {
    public var threadID: ExchangeThread.ID?
    public var selectedOfferID: ExchangeOffer.ID?
    public var selectedPublicProfileID: ExchangePublicNodeProfile.ID?
    public var selectedCounterpartyID: ExchangeCounterparty.ID?
    public var originalUserRequest: String
    public var selectedProfileSummary: String?
    public var selectedOfferSummary: String?
    public var knownFacts: [String]
    public var missingFacts: [String]
    public var recommendedQuestions: [String]
    public var alreadyAsked: [String]
    public var alreadyAnswered: [String]
    public var styleProfile: ExchangeSecretaryStyleProfile
    public var forbiddenClaims: [String]
    public var forbiddenActions: [String]
    public var maxLength: Int
    public var requiredIntent: ExchangeAgencyDraftRequiredIntent
    /// When set, autonomous LLM compose uses this mode for prompts and validation.
    public var autonomousComposeMode: RequesterAutonomousOutboundComposeMode?
    /// Up to three compact lines for top-ranked matches (score, headline, fit) — not full candidate dumps.
    public var topRankedCandidateSummaries: [String]?
    /// Buyer-directed questions to preserve in autonomous compose (from second-half unresolved issues / probe).
    public var providerDirectedQuestionLines: [String]?

    /// Human-facing opportunity label grounded in surfaced offer/profile (never generic workspace titles).
    public var groundedOpportunityLabelForPrompt: String?

    /// When true, grounded requester-match compare succeeded; autonomous compose must not backfill gap templates.
    public var pass2LLMCompareSucceeded: Bool

    /// Optional enrichment allowed for composer (not compare gaps).
    public var outboundComposeContract: RequesterOutboundComposeContract?

    public init(
        threadID: ExchangeThread.ID?,
        selectedOfferID: ExchangeOffer.ID?,
        selectedPublicProfileID: ExchangePublicNodeProfile.ID?,
        selectedCounterpartyID: ExchangeCounterparty.ID?,
        originalUserRequest: String,
        selectedProfileSummary: String?,
        selectedOfferSummary: String?,
        knownFacts: [String],
        missingFacts: [String],
        recommendedQuestions: [String],
        alreadyAsked: [String],
        alreadyAnswered: [String],
        styleProfile: ExchangeSecretaryStyleProfile,
        forbiddenClaims: [String],
        forbiddenActions: [String],
        maxLength: Int,
        requiredIntent: ExchangeAgencyDraftRequiredIntent = .requesterClarificationOnly,
        autonomousComposeMode: RequesterAutonomousOutboundComposeMode? = nil,
        topRankedCandidateSummaries: [String]? = nil,
        providerDirectedQuestionLines: [String]? = nil,
        groundedOpportunityLabelForPrompt: String? = nil,
        pass2LLMCompareSucceeded: Bool = false,
        outboundComposeContract: RequesterOutboundComposeContract? = nil
    ) {
        self.threadID = threadID
        self.selectedOfferID = selectedOfferID
        self.selectedPublicProfileID = selectedPublicProfileID
        self.selectedCounterpartyID = selectedCounterpartyID
        self.originalUserRequest = originalUserRequest
        self.selectedProfileSummary = selectedProfileSummary
        self.selectedOfferSummary = selectedOfferSummary
        self.knownFacts = knownFacts
        self.missingFacts = missingFacts
        self.recommendedQuestions = recommendedQuestions
        self.alreadyAsked = alreadyAsked
        self.alreadyAnswered = alreadyAnswered
        self.styleProfile = styleProfile
        self.forbiddenClaims = forbiddenClaims
        self.forbiddenActions = forbiddenActions
        self.maxLength = maxLength
        self.requiredIntent = requiredIntent
        self.autonomousComposeMode = autonomousComposeMode
        self.topRankedCandidateSummaries = topRankedCandidateSummaries
        self.providerDirectedQuestionLines = providerDirectedQuestionLines
        self.groundedOpportunityLabelForPrompt = groundedOpportunityLabelForPrompt
        self.pass2LLMCompareSucceeded = pass2LLMCompareSucceeded
        self.outboundComposeContract = outboundComposeContract
    }

    enum CodingKeys: String, CodingKey {
        case threadID
        case selectedOfferID
        case selectedPublicProfileID
        case selectedCounterpartyID
        case originalUserRequest
        case selectedProfileSummary
        case selectedOfferSummary
        case knownFacts
        case missingFacts
        case recommendedQuestions
        case alreadyAsked
        case alreadyAnswered
        case styleProfile
        case forbiddenClaims
        case forbiddenActions
        case maxLength
        case requiredIntent
        case autonomousComposeMode
        case topRankedCandidateSummaries
        case providerDirectedQuestionLines
        case groundedOpportunityLabelForPrompt
        case pass2LLMCompareSucceeded
        case outboundComposeContract
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadID = try container.decodeIfPresent(ExchangeThread.ID.self, forKey: .threadID)
        selectedOfferID = try container.decodeIfPresent(ExchangeOffer.ID.self, forKey: .selectedOfferID)
        selectedPublicProfileID = try container.decodeIfPresent(
            ExchangePublicNodeProfile.ID.self,
            forKey: .selectedPublicProfileID
        )
        selectedCounterpartyID = try container.decodeIfPresent(
            ExchangeCounterparty.ID.self,
            forKey: .selectedCounterpartyID
        )
        originalUserRequest = try container.decode(String.self, forKey: .originalUserRequest)
        selectedProfileSummary = try container.decodeIfPresent(String.self, forKey: .selectedProfileSummary)
        selectedOfferSummary = try container.decodeIfPresent(String.self, forKey: .selectedOfferSummary)
        knownFacts = try container.decodeIfPresent([String].self, forKey: .knownFacts) ?? []
        missingFacts = try container.decodeIfPresent([String].self, forKey: .missingFacts) ?? []
        recommendedQuestions = try container.decodeIfPresent([String].self, forKey: .recommendedQuestions) ?? []
        alreadyAsked = try container.decodeIfPresent([String].self, forKey: .alreadyAsked) ?? []
        alreadyAnswered = try container.decodeIfPresent([String].self, forKey: .alreadyAnswered) ?? []
        styleProfile = try container.decode(ExchangeSecretaryStyleProfile.self, forKey: .styleProfile)
        forbiddenClaims = try container.decodeIfPresent([String].self, forKey: .forbiddenClaims) ?? []
        forbiddenActions = try container.decodeIfPresent([String].self, forKey: .forbiddenActions) ?? []
        maxLength = try container.decode(Int.self, forKey: .maxLength)
        requiredIntent = try container.decodeIfPresent(
            ExchangeAgencyDraftRequiredIntent.self,
            forKey: .requiredIntent
        ) ?? .requesterClarificationOnly
        autonomousComposeMode = try container.decodeIfPresent(
            RequesterAutonomousOutboundComposeMode.self,
            forKey: .autonomousComposeMode
        )
        topRankedCandidateSummaries = try container.decodeIfPresent(
            [String].self,
            forKey: .topRankedCandidateSummaries
        )
        providerDirectedQuestionLines = try container.decodeIfPresent(
            [String].self,
            forKey: .providerDirectedQuestionLines
        )
        groundedOpportunityLabelForPrompt = try container.decodeIfPresent(
            String.self,
            forKey: .groundedOpportunityLabelForPrompt
        )
        pass2LLMCompareSucceeded = try container.decodeIfPresent(Bool.self, forKey: .pass2LLMCompareSucceeded) ?? false
        outboundComposeContract = try container.decodeIfPresent(
            RequesterOutboundComposeContract.self,
            forKey: .outboundComposeContract
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(threadID, forKey: .threadID)
        try container.encodeIfPresent(selectedOfferID, forKey: .selectedOfferID)
        try container.encodeIfPresent(selectedPublicProfileID, forKey: .selectedPublicProfileID)
        try container.encodeIfPresent(selectedCounterpartyID, forKey: .selectedCounterpartyID)
        try container.encode(originalUserRequest, forKey: .originalUserRequest)
        try container.encodeIfPresent(selectedProfileSummary, forKey: .selectedProfileSummary)
        try container.encodeIfPresent(selectedOfferSummary, forKey: .selectedOfferSummary)
        try container.encode(knownFacts, forKey: .knownFacts)
        try container.encode(missingFacts, forKey: .missingFacts)
        try container.encode(recommendedQuestions, forKey: .recommendedQuestions)
        try container.encode(alreadyAsked, forKey: .alreadyAsked)
        try container.encode(alreadyAnswered, forKey: .alreadyAnswered)
        try container.encode(styleProfile, forKey: .styleProfile)
        try container.encode(forbiddenClaims, forKey: .forbiddenClaims)
        try container.encode(forbiddenActions, forKey: .forbiddenActions)
        try container.encode(maxLength, forKey: .maxLength)
        try container.encode(requiredIntent, forKey: .requiredIntent)
        try container.encodeIfPresent(autonomousComposeMode, forKey: .autonomousComposeMode)
        try container.encodeIfPresent(topRankedCandidateSummaries, forKey: .topRankedCandidateSummaries)
        try container.encodeIfPresent(providerDirectedQuestionLines, forKey: .providerDirectedQuestionLines)
        try container.encodeIfPresent(groundedOpportunityLabelForPrompt, forKey: .groundedOpportunityLabelForPrompt)
        try container.encode(pass2LLMCompareSucceeded, forKey: .pass2LLMCompareSucceeded)
        try container.encodeIfPresent(outboundComposeContract, forKey: .outboundComposeContract)
    }
}

public enum ProviderResponseMode: String, Codable, Sendable, Hashable {
    case groundedAnswer
    case partialAnswer
    case askProviderInput
    case decline
}

public struct ProviderResponseDraftPacket: Codable, Sendable, Hashable {
    public var threadID: ExchangeThread.ID?
    public var selectedOfferID: ExchangeOffer.ID?
    public var selectedPublicProfileID: ExchangePublicNodeProfile.ID?
    public var selectedCounterpartyID: ExchangeCounterparty.ID?
    public var inboundInquiry: String
    public var requesterDisplayContext: String?
    public var providerPublicProfileSummary: String?
    public var selectedOfferSummary: String?
    public var approvedGroundedFacts: [ExchangeProviderGroundedFact]
    public var contextOnlyFacts: [String]
    public var missingFacts: [String]
    public var answerabilityStatus: ExchangeProviderAnswerability.Answerability
    public var escalationReason: String?
    public var styleProfile: ExchangeSecretaryStyleProfile
    public var responseMode: ProviderResponseMode
    public var forbiddenClaims: [String]
    public var forbiddenActions: [String]
    public var maxLength: Int
    public var requiredIntent: ExchangeAgencyDraftRequiredIntent

    public init(
        threadID: ExchangeThread.ID?,
        selectedOfferID: ExchangeOffer.ID?,
        selectedPublicProfileID: ExchangePublicNodeProfile.ID?,
        selectedCounterpartyID: ExchangeCounterparty.ID?,
        inboundInquiry: String,
        requesterDisplayContext: String?,
        providerPublicProfileSummary: String?,
        selectedOfferSummary: String?,
        approvedGroundedFacts: [ExchangeProviderGroundedFact],
        contextOnlyFacts: [String],
        missingFacts: [String],
        answerabilityStatus: ExchangeProviderAnswerability.Answerability,
        escalationReason: String?,
        styleProfile: ExchangeSecretaryStyleProfile,
        responseMode: ProviderResponseMode,
        forbiddenClaims: [String],
        forbiddenActions: [String],
        maxLength: Int,
        requiredIntent: ExchangeAgencyDraftRequiredIntent
    ) {
        self.threadID = threadID
        self.selectedOfferID = selectedOfferID
        self.selectedPublicProfileID = selectedPublicProfileID
        self.selectedCounterpartyID = selectedCounterpartyID
        self.inboundInquiry = inboundInquiry
        self.requesterDisplayContext = requesterDisplayContext
        self.providerPublicProfileSummary = providerPublicProfileSummary
        self.selectedOfferSummary = selectedOfferSummary
        self.approvedGroundedFacts = approvedGroundedFacts
        self.contextOnlyFacts = contextOnlyFacts
        self.missingFacts = missingFacts
        self.answerabilityStatus = answerabilityStatus
        self.escalationReason = escalationReason
        self.styleProfile = styleProfile
        self.responseMode = responseMode
        self.forbiddenClaims = forbiddenClaims
        self.forbiddenActions = forbiddenActions
        self.maxLength = maxLength
        self.requiredIntent = requiredIntent
    }
}
