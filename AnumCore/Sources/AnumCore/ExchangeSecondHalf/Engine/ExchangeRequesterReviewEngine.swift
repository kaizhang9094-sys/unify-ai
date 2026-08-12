import Foundation

/// Requester-side review behavior after match and after provider answer.
///
/// This keeps requester-side second-half behavior intentional and stateful,
/// rather than treating the requester side as a passive recipient of results.
public struct ExchangeRequesterReviewEngine: Sendable {
    public init() {}

    public enum Decision: String, Codable, CaseIterable, Hashable, Sendable {
        case qualifyFurther
        case surfaceNow
        case compareOptions
        case askAnotherClarification
        case recommendDecline
        case moveTowardDecision
    }

    public struct Result: Hashable, Sendable {
        public var decision: Decision
        public var rationale: String
        public var suggestedAction: ExchangeSecondHalfAction

        public init(
            decision: Decision,
            rationale: String,
            suggestedAction: ExchangeSecondHalfAction
        ) {
            self.decision = decision
            self.rationale = rationale
            self.suggestedAction = suggestedAction
        }
    }

    public struct Input: Sendable {
        public var qualification: ExchangeOpportunityQualification
        public var stance: ExchangeThreadStance
        public var priors: ExchangeThreadPriors
        public var clarificationRounds: Int
        public var hasComparableAlternatives: Bool
        public var hasFreshProviderAnswer: Bool
        public var boundary: ExchangeCommitmentBoundary?

        public init(
            qualification: ExchangeOpportunityQualification,
            stance: ExchangeThreadStance,
            priors: ExchangeThreadPriors,
            clarificationRounds: Int = 0,
            hasComparableAlternatives: Bool = false,
            hasFreshProviderAnswer: Bool = false,
            boundary: ExchangeCommitmentBoundary? = nil
        ) {
            self.qualification = qualification
            self.stance = stance
            self.priors = priors
            self.clarificationRounds = clarificationRounds
            self.hasComparableAlternatives = hasComparableAlternatives
            self.hasFreshProviderAnswer = hasFreshProviderAnswer
            self.boundary = boundary
        }
    }

    public func evaluate(
        input: Input,
        policy: ExchangeSecondHalfPolicy
    ) -> Result {
        if let boundary = input.boundary,
           policy.requiresApproval(for: boundary) {
            return Result(
                decision: .moveTowardDecision,
                rationale: "The thread is approaching a commitment boundary and should be surfaced for user judgment.",
                suggestedAction: .frameDecision
            )
        }

        if input.qualification.isDecisionReady || input.stance.isDecisionOrCommitmentReady {
            return Result(
                decision: .moveTowardDecision,
                rationale: "The opportunity is strong enough to move into decision framing.",
                suggestedAction: .frameDecision
            )
        }

        if input.qualification.isWeak {
            if input.hasComparableAlternatives {
                return Result(
                    decision: .compareOptions,
                    rationale: "The current opportunity is weak and should be viewed against alternatives.",
                    suggestedAction: .compareOptions
                )
            } else {
                return Result(
                    decision: .recommendDecline,
                    rationale: "The current opportunity is weak and does not justify more requester-side energy.",
                    suggestedAction: .decline
                )
            }
        }

        if input.qualification.needsClarification &&
            input.qualification.isOneMoreClarificationWorthwhile &&
            !policy.hasExceededClarificationLimit(input.clarificationRounds) {
            return Result(
                decision: .askAnotherClarification,
                rationale: "One more focused clarification should materially improve the thread.",
                suggestedAction: .askClarification
            )
        }

        if input.qualification.isStrongEnoughToSurface && input.hasFreshProviderAnswer {
            return Result(
                decision: .surfaceNow,
                rationale: "A useful provider-side answer has arrived and the opportunity is strong enough to present cleanly.",
                suggestedAction: .recommendNextMove
            )
        }

        return Result(
            decision: .qualifyFurther,
            rationale: "The opportunity still needs refinement before it becomes decision-ready.",
            suggestedAction: .qualifyMatch
        )
    }
}
