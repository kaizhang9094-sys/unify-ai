import Foundation

/// Provider-side front desk behavior.
///
/// This decides whether an inbound inquiry should be answered automatically,
/// escalated to the provider user, declined, or surfaced as promising.
public struct ExchangeProviderIntakeEngine: Sendable {
    public init() {}

    public enum Decision: String, Codable, CaseIterable, Hashable, Sendable {
        case answerAutomatically
        case askProviderUser
        case declinePolitely
        case markWeakLead
        case surfaceStrongLead
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

    public func evaluate(
        inquiry: ExchangeInboundInquiry,
        qualification: ExchangeOpportunityQualification,
        boundary: ExchangeCommitmentBoundary,
        autonomousRoundsSoFar: Int,
        policy: ExchangeSecondHalfPolicy
    ) -> Result {
        if policy.providerIntake.mayAutoDecline(inquiry: inquiry) {
            return Result(
                decision: .declinePolitely,
                rationale: "The inquiry is clearly out of scope and may be declined automatically.",
                suggestedAction: .decline
            )
        }

        if policy.providerIntake.mayAutoAnswer(
            inquiry: inquiry,
            boundary: boundary,
            autonomousRoundsSoFar: autonomousRoundsSoFar
        ) {
            return Result(
                decision: .answerAutomatically,
                rationale: "The inquiry is routine and answerable from known structured facts.",
                suggestedAction: .autoRespond
            )
        }

        if policy.providerIntake.shouldEscalate(
            inquiry: inquiry,
            boundary: boundary
        ) {
            return Result(
                decision: .askProviderUser,
                rationale: "The inquiry needs provider-side user input or crosses a higher-risk boundary.",
                suggestedAction: .requestUserInput
            )
        }

        if qualification.isWeak {
            return Result(
                decision: .markWeakLead,
                rationale: "The inquiry is not strong enough to interrupt the provider user yet.",
                suggestedAction: .markStalled
            )
        }

        return Result(
            decision: .surfaceStrongLead,
            rationale: "The inquiry appears promising enough to surface as a real opportunity.",
            suggestedAction: .recommendNextMove
        )
    }
}
