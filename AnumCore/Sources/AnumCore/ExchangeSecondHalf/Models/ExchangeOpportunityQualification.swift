import Foundation

public enum ExchangeOpportunityQualityTier: String, Codable, CaseIterable, Hashable, Sendable {
    case weak
    case promising
    case strong
    case decisionReady
}

public enum ExchangeQualificationStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case incomplete
    case qualified
    case needsClarification
    case surfaced
    case downgraded
    case decisionReady
}

/// Current quality assessment of the opportunity.
///
/// This lets the system explicitly track whether the thread is still weak,
/// still incomplete, worth one more clarification, or ready for decision.
public struct ExchangeOpportunityQualification: Codable, Hashable, Sendable {
    public var qualityTier: ExchangeOpportunityQualityTier
    public var missingFacts: [String]
    public var strengthReasons: [String]
    public var weaknessReasons: [String]
    public var qualificationStatus: ExchangeQualificationStatus
    public var isOneMoreClarificationWorthwhile: Bool

    public init(
        qualityTier: ExchangeOpportunityQualityTier = .weak,
        missingFacts: [String] = [],
        strengthReasons: [String] = [],
        weaknessReasons: [String] = [],
        qualificationStatus: ExchangeQualificationStatus = .incomplete,
        isOneMoreClarificationWorthwhile: Bool = false
    ) {
        self.qualityTier = qualityTier
        self.missingFacts = missingFacts
        self.strengthReasons = strengthReasons
        self.weaknessReasons = weaknessReasons
        self.qualificationStatus = qualificationStatus
        self.isOneMoreClarificationWorthwhile = isOneMoreClarificationWorthwhile
    }
}

public extension ExchangeOpportunityQualification {
    static let empty = ExchangeOpportunityQualification()

    var isDecisionReady: Bool {
        qualityTier == .decisionReady || qualificationStatus == .decisionReady
    }

    var isStrongEnoughToSurface: Bool {
        switch qualityTier {
        case .promising, .strong, .decisionReady:
            return true
        case .weak:
            return false
        }
    }

    var isWeak: Bool {
        qualityTier == .weak
    }

    var needsClarification: Bool {
        qualificationStatus == .needsClarification || !missingFacts.isEmpty
    }
}
