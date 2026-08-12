import Foundation

public struct ExchangeProviderResponseAssessment: Codable, Sendable, Hashable {
    public var conditionAssessments: [ConditionAssessment]
    public var providerFitSummary: String?
    public var confidenceDelta: ConfidenceDelta
    public var shortlistRecommendation: ShortlistRecommendation
    public var decisionReadiness: DecisionReadiness
    public var nextMoveRecommendation: NextMoveRecommendation?
    public var missingInfo: [String]
    public var suggestedFollowUp: String?
    public var requesterFacingExplanation: String?
    public var requiresHumanJudgment: Bool
    public var safeForAutonomousFollowup: Bool
    public var assessedAt: Date
    public var summary: String?

    public init(
        conditionAssessments: [ConditionAssessment] = [],
        providerFitSummary: String? = nil,
        confidenceDelta: ConfidenceDelta = .stable,
        shortlistRecommendation: ShortlistRecommendation = .noChange,
        decisionReadiness: DecisionReadiness = .notReady,
        nextMoveRecommendation: NextMoveRecommendation? = nil,
        missingInfo: [String] = [],
        suggestedFollowUp: String? = nil,
        requesterFacingExplanation: String? = nil,
        requiresHumanJudgment: Bool = false,
        safeForAutonomousFollowup: Bool = false,
        assessedAt: Date = Date(),
        summary: String? = nil
    ) {
        self.conditionAssessments = conditionAssessments
        self.providerFitSummary = providerFitSummary
        self.confidenceDelta = confidenceDelta
        self.shortlistRecommendation = shortlistRecommendation
        self.decisionReadiness = decisionReadiness
        self.nextMoveRecommendation = nextMoveRecommendation
        self.missingInfo = missingInfo
        self.suggestedFollowUp = suggestedFollowUp
        self.requesterFacingExplanation = requesterFacingExplanation
        self.requiresHumanJudgment = requiresHumanJudgment
        self.safeForAutonomousFollowup = safeForAutonomousFollowup
        self.assessedAt = assessedAt
        self.summary = summary
    }
}

public struct ConditionAssessment: Codable, Sendable, Hashable {
    public var conditionText: String
    public var source: ConditionSource
    public var status: ConditionStatus
    public var confidence: Double?
    public var evidence: [String]
    public var missingInfo: [String]
    public var suggestedFollowUp: String?

    public init(
        conditionText: String,
        source: ConditionSource,
        status: ConditionStatus,
        confidence: Double? = nil,
        evidence: [String] = [],
        missingInfo: [String] = [],
        suggestedFollowUp: String? = nil
    ) {
        self.conditionText = conditionText
        self.source = source
        self.status = status
        self.confidence = confidence
        self.evidence = evidence
        self.missingInfo = missingInfo
        self.suggestedFollowUp = suggestedFollowUp
    }
}

public enum ConditionSource: String, Codable, Sendable, Hashable, CaseIterable {
    case canonicalIntent
    case gapFill
    case userPreference
    case commercialConstraint
    case timingConstraint
    case providerReply
    case operatingMemory
    case unknown
}

public enum ConditionStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case satisfied
    case partiallySatisfied
    case impliedFlexible
    case notAnswered
    case contradicted
    case needsFollowUp
    case unknown
}

public enum ConfidenceDelta: String, Codable, Sendable, Hashable, CaseIterable {
    case stronglyNegative
    case negative
    case stable
    case positive
    case stronglyPositive
}

public enum ShortlistRecommendation: String, Codable, Sendable, Hashable, CaseIterable {
    case noChange
    case promote
    case demote
    case remove
    case compareWithAlternatives
}

public enum DecisionReadiness: String, Codable, Sendable, Hashable, CaseIterable {
    case notReady
    case needsFollowUp
    case readyForDecisionFrame
    case blockedByContradiction
}

public enum NextMoveRecommendation: String, Codable, Sendable, Hashable, CaseIterable {
    case askClarification
    case frameDecision
    case recommendNextMove
    case compareOptions
    case requestUserInput
    case escalateForApproval
    case pause
}
