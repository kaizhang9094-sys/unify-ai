import Foundation

public enum ExchangeRecommendationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case qualifyFurther
    case askClarification
    case answerAutomatically
    case requestUserInput
    case surfaceNow
    case compareOptions
    case decline
    case moveTowardDecision
    case escalateForApproval
    case wait
}

/// Builds recommendation text / recommendation kind.
///
/// This keeps recommendation construction separate from the raw state and
/// avoids coordinator drift.
public struct ExchangeRecommendationBuilder: Sendable {
    public init() {}

    public struct Result: Hashable, Sendable {
        public var kind: ExchangeRecommendationKind
        public var text: String

        public init(
            kind: ExchangeRecommendationKind,
            text: String
        ) {
            self.kind = kind
            self.text = text
        }
    }

    public func build(
        qualification: ExchangeOpportunityQualification,
        stance: ExchangeThreadStance,
        plan: ExchangeSecondHalfPlan,
        boundary: ExchangeCommitmentBoundary? = nil,
        role: ExchangeSecondHalfRole
    ) -> Result {
        if let boundary, boundary.requiresHumanApproval {
            return Result(
                kind: .escalateForApproval,
                text: "The thread is approaching a commitment boundary and should be reviewed before proceeding."
            )
        }

        switch plan.selectedAction {
        case .qualifyMatch:
            return Result(
                kind: .qualifyFurther,
                text: "The opportunity should be qualified further before it is surfaced."
            )

        case .askClarification:
            return Result(
                kind: .askClarification,
                text: "One focused clarification should improve the thread meaningfully."
            )

        case .answerClarification, .autoRespond:
            return Result(
                kind: .answerAutomatically,
                text: "This can be answered from the current known facts."
            )

        case .requestUserInput:
            return Result(
                kind: .requestUserInput,
                text: "User input is needed to move the thread forward safely."
            )

        case .frameDecision, .recommendNextMove:
            if qualification.isDecisionReady || stance.isDecisionOrCommitmentReady {
                return Result(
                    kind: .moveTowardDecision,
                    text: "The opportunity is ready to be framed for a decision."
                )
            } else {
                return Result(
                    kind: .surfaceNow,
                    text: role == .requester
                        ? "This opportunity is strong enough to surface now."
                        : "This inbound opportunity is strong enough to surface now."
                )
            }

        case .compareOptions:
            return Result(
                kind: .compareOptions,
                text: "It is better to compare options before committing further attention."
            )

        case .proposeTerms, .reviseTerms, .escalateForApproval:
            return Result(
                kind: .escalateForApproval,
                text: "The next move affects terms and should be reviewed before being treated as final."
            )

        case .decline:
            return Result(
                kind: .decline,
                text: "This thread is not strong enough to justify more effort."
            )

        case .pause, .markStalled:
            return Result(
                kind: .wait,
                text: "The thread should pause for now rather than forcing more movement."
            )

        case .markBlocked:
            return Result(
                kind: .requestUserInput,
                text: "The thread is blocked and needs user direction."
            )

        case .accept, .complete:
            return Result(
                kind: .moveTowardDecision,
                text: "The thread is ready to move to a final outcome."
            )
        }
    }
}
