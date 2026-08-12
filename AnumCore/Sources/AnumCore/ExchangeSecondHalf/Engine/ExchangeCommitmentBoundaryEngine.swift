import Foundation

/// Determines whether a move is safe or requires escalation/approval.
///
/// This is the second-half trust boundary engine.
public struct ExchangeCommitmentBoundaryEngine: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var action: ExchangeSecondHalfAction
        public var isCustomPricing: Bool
        public var includesSensitiveDisclosure: Bool
        public var includesScheduleCommitment: Bool
        public var includesLegalCommercialCommitment: Bool
        public var isPolicyException: Bool
        public var rationale: String?

        public init(
            action: ExchangeSecondHalfAction,
            isCustomPricing: Bool = false,
            includesSensitiveDisclosure: Bool = false,
            includesScheduleCommitment: Bool = false,
            includesLegalCommercialCommitment: Bool = false,
            isPolicyException: Bool = false,
            rationale: String? = nil
        ) {
            self.action = action
            self.isCustomPricing = isCustomPricing
            self.includesSensitiveDisclosure = includesSensitiveDisclosure
            self.includesScheduleCommitment = includesScheduleCommitment
            self.includesLegalCommercialCommitment = includesLegalCommercialCommitment
            self.isPolicyException = isPolicyException
            self.rationale = rationale
        }
    }

    public func classify(
        input: Input
    ) -> ExchangeCommitmentBoundary {
        if input.includesLegalCommercialCommitment {
            return .legalCommercialCommitment(
                reason: input.rationale ?? "The move carries legal or commercial commitment."
            )
        }

        if input.includesScheduleCommitment {
            return .scheduleCommitment(
                reason: input.rationale ?? "The move commits schedule, timing, or delivery expectations."
            )
        }

        if input.isCustomPricing {
            return .customPricing(
                reason: input.rationale ?? "The move involves custom pricing outside routine structured facts."
            )
        }

        if input.isPolicyException {
            return .policyException(
                reason: input.rationale ?? "The move would go outside standard operating policy."
            )
        }

        if input.includesSensitiveDisclosure {
            return .sensitiveDisclosure(
                reason: input.rationale ?? "The move includes sensitive or higher-risk disclosure."
            )
        }

        switch input.action {
        case .qualifyMatch,
             .askClarification,
             .answerClarification,
             .autoRespond,
             .requestUserInput,
             .frameDecision,
             .recommendNextMove,
             .compareOptions:
            return .safe

        case .escalateForApproval,
             .pause,
             .markBlocked,
             .markStalled,
             .complete:
            return ExchangeCommitmentBoundary(
                kind: .obligationBearing,
                reason: input.rationale ?? "The move changes thread obligations or requires human intervention.",
                requiresHumanApproval: true,
                allowsAutonomousDrafting: false,
                allowsAutonomousSending: false
            )

        case .proposeTerms,
             .reviseTerms:
            return .commitmentBearing(
                reason: input.rationale ?? "The move proposes or revises terms that may be interpreted as commitment-bearing."
            )

        case .accept,
             .decline:
            return .commitmentBearing(
                reason: input.rationale ?? "The move expresses final commitment or refusal."
            )
        }
    }
}
