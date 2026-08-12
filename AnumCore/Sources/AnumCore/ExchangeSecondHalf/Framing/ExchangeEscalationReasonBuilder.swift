import Foundation

/// Builds human-readable escalation reasons.
///
/// This is important for trust: users should understand why the secretary is
/// interrupting them or refusing to proceed autonomously.
public struct ExchangeEscalationReasonBuilder: Sendable {
    public init() {}

    public func build(
        boundary: ExchangeCommitmentBoundary?,
        missingFacts: [String] = [],
        inquiry: ExchangeInboundInquiry? = nil
    ) -> String? {
        if let boundary {
            switch boundary.kind {
            case .safe:
                break
            case .customPricing:
                return "Custom pricing needs your approval."
            case .policyException:
                return "This would go outside your normal policy."
            case .scheduleCommitment:
                return "This would commit timing or schedule."
            case .legalCommercialCommitment:
                return "This carries legal or commercial commitment."
            case .commitmentBearing:
                return "This move would create a real commitment."
            case .obligationBearing:
                return "This move would create an obligation that should be reviewed."
            case .sensitiveDisclosure:
                return "This requires disclosure that should be reviewed first."
            }
        }

        let cleanedMissingFacts = cleaned(missingFacts)
        if !cleanedMissingFacts.isEmpty {
            return "More input is needed before the thread can progress safely."
        }

        if let inquiry {
            switch inquiry.answerabilityStatus {
            case .requiresUserInput:
                return "The incoming inquiry needs your input."
            case .insufficientContext:
                return "There is not enough context to answer confidently."
            case .outOfScope:
                return "This appears to be outside your current scope."
            case .answerableFromKnownFacts:
                break
            }
        }

        return nil
    }

    private func cleaned(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
