import Foundation

/// Selects the best next move from current thread conditions.
///
/// The goal is to make the secretary feel intentional rather than passive.
public struct ExchangeNextMoveEngine: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var role: ExchangeSecondHalfRole
        public var state: ExchangeSecondHalfState
        public var qualification: ExchangeOpportunityQualification
        public var stance: ExchangeThreadStance
        public var priors: ExchangeThreadPriors
        public var clarificationRounds: Int
        public var followUpAttempts: Int
        public var canAnswerStructurally: Bool
        public var boundary: ExchangeCommitmentBoundary?
        /// True when unresolved issues include user-facing outbound material follow-ups (e.g. confirm price with provider).
        public var hasOutboundProviderMaterialFollowUpIssues: Bool

        public init(
            role: ExchangeSecondHalfRole,
            state: ExchangeSecondHalfState,
            qualification: ExchangeOpportunityQualification,
            stance: ExchangeThreadStance,
            priors: ExchangeThreadPriors,
            clarificationRounds: Int = 0,
            followUpAttempts: Int = 0,
            canAnswerStructurally: Bool = false,
            boundary: ExchangeCommitmentBoundary? = nil,
            hasOutboundProviderMaterialFollowUpIssues: Bool = false
        ) {
            self.role = role
            self.state = state
            self.qualification = qualification
            self.stance = stance
            self.priors = priors
            self.clarificationRounds = clarificationRounds
            self.followUpAttempts = followUpAttempts
            self.canAnswerStructurally = canAnswerStructurally
            self.boundary = boundary
            self.hasOutboundProviderMaterialFollowUpIssues = hasOutboundProviderMaterialFollowUpIssues
        }
    }

    public func select(
        input: Input,
        policy: ExchangeSecondHalfPolicy
    ) -> ExchangeSecondHalfPlan {
        if let boundary = input.boundary, policy.requiresApproval(for: boundary) {
            return .escalate(
                role: input.role,
                rationale: "The next move crosses a commitment or approval boundary."
            )
        }

        if input.state == .blocked {
            return .requestInput(
                role: input.role,
                rationale: "The thread is blocked and needs user intervention.",
                requiredInputs: ["Clarify how to proceed"]
            )
        }

        if input.role == .requester,
           input.hasOutboundProviderMaterialFollowUpIssues,
           let boundary = input.boundary,
           !boundary.requiresHumanApproval,
           !policy.hasExceededClarificationLimit(input.clarificationRounds) {
            return ExchangeSecondHalfPlan(
                selectedAction: .askClarification,
                role: input.role,
                rationale:
                    "You asked the secretary to confirm specific details with the provider; send a focused outbound clarification first.",
                requiredInputs: [],
                needsGeneration: true,
                needsUserInput: false,
                needsApproval: false
            )
        }

        if input.qualification.isDecisionReady || input.stance.isDecisionOrCommitmentReady {
            return ExchangeSecondHalfPlan(
                selectedAction: .frameDecision,
                role: input.role,
                rationale: "The thread is strong enough to frame a decision for the user.",
                requiredInputs: [],
                needsGeneration: true,
                needsUserInput: false,
                needsApproval: false
            )
        }

        if input.canAnswerStructurally && input.state.isAwaitingClarification {
            return ExchangeSecondHalfPlan(
                selectedAction: .autoRespond,
                role: input.role,
                rationale: "The question can be answered from structured facts.",
                requiredInputs: [],
                needsGeneration: true,
                needsUserInput: false,
                needsApproval: false
            )
        }

        if input.qualification.needsClarification &&
            input.qualification.isOneMoreClarificationWorthwhile &&
            !policy.hasExceededClarificationLimit(input.clarificationRounds) {
            return ExchangeSecondHalfPlan(
                selectedAction: .askClarification,
                role: input.role,
                rationale: "One more focused clarification is worthwhile before surfacing or deciding.",
                requiredInputs: [],
                needsGeneration: true,
                needsUserInput: false,
                needsApproval: false
            )
        }

        if input.qualification.isStrongEnoughToSurface {
            return ExchangeSecondHalfPlan(
                selectedAction: .recommendNextMove,
                role: input.role,
                rationale: "The opportunity is strong enough to surface with a recommendation.",
                requiredInputs: [],
                needsGeneration: true,
                needsUserInput: false,
                needsApproval: false
            )
        }

        if input.followUpAttempts >= policy.followUpLimit {
            return ExchangeSecondHalfPlan(
                selectedAction: .markStalled,
                role: input.role,
                rationale: "Follow-up budget has been exhausted.",
                requiredInputs: [],
                needsGeneration: false,
                needsUserInput: false,
                needsApproval: false
            )
        }

        if input.qualification.isWeak && input.role == .requester {
            return ExchangeSecondHalfPlan(
                selectedAction: .compareOptions,
                role: input.role,
                rationale: "The current option is weak; comparison or continued search is more appropriate.",
                requiredInputs: [],
                needsGeneration: false,
                needsUserInput: false,
                needsApproval: false
            )
        }

        return .requestInput(
            role: input.role,
            rationale: "The thread needs user input to progress safely.",
            requiredInputs: ["Missing context or preference"]
        )
    }
}
