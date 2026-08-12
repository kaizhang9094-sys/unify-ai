import Foundation

/// Provider-side inbound handling rules.
///
/// This defines what kinds of inbound questions can be answered automatically,
/// what should be escalated, and how strict provider-side intake should be.
public struct ExchangeProviderIntakePolicy: Codable, Hashable, Sendable {
    /// Allow automatic answering of routine questions when structured facts are sufficient.
    public var allowAutoAnswerFromKnownFacts: Bool

    /// Allow automatic answering of routine price-list questions that do not
    /// require custom pricing or exceptions.
    public var allowAutoAnswerStandardPricing: Bool

    /// Allow automatic answering of routine availability / service area / policy questions.
    public var allowAutoAnswerOperationalFacts: Bool

    /// Whether custom pricing requests must always escalate.
    public var requireEscalationForCustomPricing: Bool

    /// Whether out-of-scope requests should be declined automatically when clear.
    public var allowAutoDeclineOutOfScope: Bool

    /// Whether unclear or insufficiently grounded provider responses should escalate
    /// rather than be guessed.
    public var requireEscalationWhenContextIsInsufficient: Bool

    /// Maximum number of autonomous provider-side intake loops before user involvement.
    public var maxAutonomousProviderIntakeRounds: Int

    public init(
        allowAutoAnswerFromKnownFacts: Bool = true,
        allowAutoAnswerStandardPricing: Bool = true,
        allowAutoAnswerOperationalFacts: Bool = true,
        requireEscalationForCustomPricing: Bool = true,
        allowAutoDeclineOutOfScope: Bool = true,
        requireEscalationWhenContextIsInsufficient: Bool = true,
        maxAutonomousProviderIntakeRounds: Int = 1
    ) {
        self.allowAutoAnswerFromKnownFacts = allowAutoAnswerFromKnownFacts
        self.allowAutoAnswerStandardPricing = allowAutoAnswerStandardPricing
        self.allowAutoAnswerOperationalFacts = allowAutoAnswerOperationalFacts
        self.requireEscalationForCustomPricing = requireEscalationForCustomPricing
        self.allowAutoDeclineOutOfScope = allowAutoDeclineOutOfScope
        self.requireEscalationWhenContextIsInsufficient = requireEscalationWhenContextIsInsufficient
        self.maxAutonomousProviderIntakeRounds = max(0, maxAutonomousProviderIntakeRounds)
    }
}

public extension ExchangeProviderIntakePolicy {
    static let `default` = ExchangeProviderIntakePolicy()

    func mayAutoAnswer(
        inquiry: ExchangeInboundInquiry,
        boundary: ExchangeCommitmentBoundary = .safe,
        autonomousRoundsSoFar: Int = 0
    ) -> Bool {
        guard autonomousRoundsSoFar < maxAutonomousProviderIntakeRounds else {
            return false
        }

        guard allowAutoAnswerFromKnownFacts else {
            return false
        }

        guard !boundary.requiresHumanApproval else {
            return false
        }

        switch inquiry.answerabilityStatus {
        case .answerableFromKnownFacts:
            return inquiry.classification == .routine

        case .requiresUserInput, .insufficientContext, .outOfScope:
            return false
        }
    }

    func shouldEscalate(
        inquiry: ExchangeInboundInquiry,
        boundary: ExchangeCommitmentBoundary = .safe
    ) -> Bool {
        if boundary.requiresHumanApproval {
            return true
        }

        switch inquiry.answerabilityStatus {
        case .requiresUserInput:
            return true
        case .insufficientContext:
            return requireEscalationWhenContextIsInsufficient
        case .answerableFromKnownFacts:
            return false
        case .outOfScope:
            return false
        }
    }

    func mayAutoDecline(
        inquiry: ExchangeInboundInquiry
    ) -> Bool {
        allowAutoDeclineOutOfScope && inquiry.answerabilityStatus == .outOfScope
    }
}
