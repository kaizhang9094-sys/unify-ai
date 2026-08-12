import Foundation

public enum ExchangeInterestLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case low
    case medium
    case high
}

public enum ExchangeUrgencyLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case low
    case normal
    case high
    case urgent
}

public enum ExchangeTrustLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case low
    case guarded
    case moderate
    case high
}

public enum ExchangePriceSensitivity: String, Codable, CaseIterable, Hashable, Sendable {
    case low
    case moderate
    case high
}

public enum ExchangeFlexibilityLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case rigid
    case moderate
    case flexible
}

public enum ExchangeReadinessLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case weak
    case incomplete
    case promising
    case decisionReady
    case commitmentReady
}

/// Compact durable stance object for a thread.
///
/// This is intentionally smaller than a transcript or full reasoning record.
/// It exists to keep the secretary stateful in a cheap, durable way.
public struct ExchangeThreadStance: Codable, Hashable, Sendable {
    public var interestLevel: ExchangeInterestLevel
    public var urgencyLevel: ExchangeUrgencyLevel
    public var trustLevel: ExchangeTrustLevel
    public var priceSensitivity: ExchangePriceSensitivity
    public var flexibilityLevel: ExchangeFlexibilityLevel
    public var readinessLevel: ExchangeReadinessLevel

    /// Human-readable stance summary used by UI and framing.
    public var postureSummary: String

    /// The action the system currently thinks is best next.
    public var recommendedNextMove: ExchangeSecondHalfAction?

    /// Small hints for follow-up discipline such as "do not over-message"
    /// or "ask one precise pricing question".
    public var followUpHints: [String]

    public init(
        interestLevel: ExchangeInterestLevel = .medium,
        urgencyLevel: ExchangeUrgencyLevel = .normal,
        trustLevel: ExchangeTrustLevel = .guarded,
        priceSensitivity: ExchangePriceSensitivity = .moderate,
        flexibilityLevel: ExchangeFlexibilityLevel = .moderate,
        readinessLevel: ExchangeReadinessLevel = .incomplete,
        postureSummary: String = "",
        recommendedNextMove: ExchangeSecondHalfAction? = nil,
        followUpHints: [String] = []
    ) {
        self.interestLevel = interestLevel
        self.urgencyLevel = urgencyLevel
        self.trustLevel = trustLevel
        self.priceSensitivity = priceSensitivity
        self.flexibilityLevel = flexibilityLevel
        self.readinessLevel = readinessLevel
        self.postureSummary = postureSummary
        self.recommendedNextMove = recommendedNextMove
        self.followUpHints = followUpHints
    }
}

public extension ExchangeThreadStance {
    static let neutral = ExchangeThreadStance()

    var isDecisionOrCommitmentReady: Bool {
        switch readinessLevel {
        case .decisionReady, .commitmentReady:
            return true
        case .weak, .incomplete, .promising:
            return false
        }
    }

    var isHighUrgency: Bool {
        switch urgencyLevel {
        case .high, .urgent:
            return true
        case .low, .normal:
            return false
        }
    }

    var isLowTrust: Bool {
        switch trustLevel {
        case .low, .guarded:
            return true
        case .moderate, .high:
            return false
        }
    }
}
