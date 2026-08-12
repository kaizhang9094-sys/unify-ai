import Foundation

/// Pass 2: compact agency outputs merged into second-half projection (read-only, no transport).
public struct ExchangeAgencyAssessment: Codable, Hashable, Sendable {
    public var requesterDecisionNeeds: ExchangeRequesterDecisionNeeds?
    public var providerAnswerability: ExchangeProviderAnswerability?
    public var groundedFactLines: [String]
    public var suggestedQuestionLines: [String]
    public var answerabilityLine: String?

    /// Pass 3: deterministic planner suggestions — never authoritative for sends; gated paths remain canonical.
    public var agencySuggestions: [ExchangeAgencySuggestion]
    public var agencyDecision: ExchangeAgencyDecision

    public init(
        requesterDecisionNeeds: ExchangeRequesterDecisionNeeds? = nil,
        providerAnswerability: ExchangeProviderAnswerability? = nil,
        groundedFactLines: [String] = [],
        suggestedQuestionLines: [String] = [],
        answerabilityLine: String? = nil,
        agencySuggestions: [ExchangeAgencySuggestion] = [],
        agencyDecision: ExchangeAgencyDecision = .conservativeDefault
    ) {
        self.requesterDecisionNeeds = requesterDecisionNeeds
        self.providerAnswerability = providerAnswerability
        self.groundedFactLines = groundedFactLines
        self.suggestedQuestionLines = suggestedQuestionLines
        self.answerabilityLine = answerabilityLine
        self.agencySuggestions = agencySuggestions
        self.agencyDecision = agencyDecision
    }

    enum CodingKeys: String, CodingKey {
        case requesterDecisionNeeds
        case providerAnswerability
        case groundedFactLines
        case suggestedQuestionLines
        case answerabilityLine
        case agencySuggestions
        case agencyDecision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requesterDecisionNeeds = try container.decodeIfPresent(
            ExchangeRequesterDecisionNeeds.self,
            forKey: .requesterDecisionNeeds
        )
        providerAnswerability = try container.decodeIfPresent(
            ExchangeProviderAnswerability.self,
            forKey: .providerAnswerability
        )
        groundedFactLines = try container.decodeIfPresent([String].self, forKey: .groundedFactLines) ?? []
        suggestedQuestionLines = try container.decodeIfPresent([String].self, forKey: .suggestedQuestionLines) ?? []
        answerabilityLine = try container.decodeIfPresent(String.self, forKey: .answerabilityLine)
        agencySuggestions = try container.decodeIfPresent([ExchangeAgencySuggestion].self, forKey: .agencySuggestions) ?? []
        agencyDecision = try container.decodeIfPresent(
            ExchangeAgencyDecision.self,
            forKey: .agencyDecision
        ) ?? .conservativeDefault
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(requesterDecisionNeeds, forKey: .requesterDecisionNeeds)
        try container.encodeIfPresent(providerAnswerability, forKey: .providerAnswerability)
        try container.encode(groundedFactLines, forKey: .groundedFactLines)
        try container.encode(suggestedQuestionLines, forKey: .suggestedQuestionLines)
        try container.encodeIfPresent(answerabilityLine, forKey: .answerabilityLine)
        try container.encode(agencySuggestions, forKey: .agencySuggestions)
        try container.encode(agencyDecision, forKey: .agencyDecision)
    }
}
