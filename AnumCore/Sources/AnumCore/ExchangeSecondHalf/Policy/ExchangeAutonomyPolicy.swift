import Foundation

/// Defines what the secretary may do without asking.
///
/// This is the core safe-autonomy rule set for the second half.
/// It should stay simple, legible, and easy to audit.
public struct ExchangeAutonomyPolicy: Codable, Hashable, Sendable {
    public var allowAutonomousQualification: Bool
    public var allowAutonomousClarificationAsking: Bool
    public var allowAutonomousClarificationAnswering: Bool
    public var allowAutonomousRoutineSurfaceResponses: Bool
    public var allowAutonomousDecisionFraming: Bool
    public var allowAutonomousRecommendation: Bool
    public var allowAutonomousDraftPreparation: Bool
    public var allowAutonomousSendingWhenBoundaryIsSafe: Bool

    public init(
        allowAutonomousQualification: Bool = true,
        allowAutonomousClarificationAsking: Bool = true,
        allowAutonomousClarificationAnswering: Bool = true,
        allowAutonomousRoutineSurfaceResponses: Bool = true,
        allowAutonomousDecisionFraming: Bool = true,
        allowAutonomousRecommendation: Bool = true,
        allowAutonomousDraftPreparation: Bool = true,
        allowAutonomousSendingWhenBoundaryIsSafe: Bool = true
    ) {
        self.allowAutonomousQualification = allowAutonomousQualification
        self.allowAutonomousClarificationAsking = allowAutonomousClarificationAsking
        self.allowAutonomousClarificationAnswering = allowAutonomousClarificationAnswering
        self.allowAutonomousRoutineSurfaceResponses = allowAutonomousRoutineSurfaceResponses
        self.allowAutonomousDecisionFraming = allowAutonomousDecisionFraming
        self.allowAutonomousRecommendation = allowAutonomousRecommendation
        self.allowAutonomousDraftPreparation = allowAutonomousDraftPreparation
        self.allowAutonomousSendingWhenBoundaryIsSafe = allowAutonomousSendingWhenBoundaryIsSafe
    }
}

public extension ExchangeAutonomyPolicy {
    static let `default` = ExchangeAutonomyPolicy()

    static let conservative = ExchangeAutonomyPolicy(
        allowAutonomousQualification: true,
        allowAutonomousClarificationAsking: true,
        allowAutonomousClarificationAnswering: false,
        allowAutonomousRoutineSurfaceResponses: false,
        allowAutonomousDecisionFraming: true,
        allowAutonomousRecommendation: true,
        allowAutonomousDraftPreparation: true,
        allowAutonomousSendingWhenBoundaryIsSafe: false
    )

    func permits(_ action: ExchangeSecondHalfAction, boundary: ExchangeCommitmentBoundary? = nil) -> Bool {
        switch action {
        case .qualifyMatch:
            return allowAutonomousQualification

        case .askClarification:
            return allowAutonomousClarificationAsking

        case .answerClarification:
            return allowAutonomousClarificationAnswering

        case .autoRespond:
            if let boundary {
                return allowAutonomousRoutineSurfaceResponses &&
                    boundary.kind == .safe &&
                    boundary.allowsAutonomousSending
            }
            return allowAutonomousRoutineSurfaceResponses

        case .frameDecision:
            return allowAutonomousDecisionFraming

        case .recommendNextMove, .compareOptions:
            return allowAutonomousRecommendation

        case .proposeTerms, .reviseTerms:
            if let boundary {
                return allowAutonomousDraftPreparation &&
                    boundary.allowsAutonomousDrafting &&
                    (!boundary.requiresHumanApproval || allowAutonomousSendingWhenBoundaryIsSafe)
            }
            return allowAutonomousDraftPreparation

        case .requestUserInput, .escalateForApproval, .accept, .decline:
            return false

        case .pause, .markBlocked, .markStalled, .complete:
            return false
        }
    }

    func permitsAutonomousSending(for boundary: ExchangeCommitmentBoundary) -> Bool {
        allowAutonomousSendingWhenBoundaryIsSafe &&
        boundary.kind == .safe &&
        boundary.allowsAutonomousSending &&
        !boundary.requiresHumanApproval
    }
}
