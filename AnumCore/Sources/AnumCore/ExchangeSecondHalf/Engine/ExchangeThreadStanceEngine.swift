import Foundation

/// Maintains per-thread stance.
///
/// This keeps the secretary coherent over time by updating thread posture in a
/// compact, durable way instead of reacting randomly each turn.
public struct ExchangeThreadStanceEngine: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var previousStance: ExchangeThreadStance?
        public var qualification: ExchangeOpportunityQualification
        public var priors: ExchangeThreadPriors
        public var role: ExchangeSecondHalfRole
        public var threadState: ExchangeSecondHalfState
        public var isTimeSensitive: Bool
        public var isPriceSensitive: Bool
        public var hasLowTrustSignals: Bool
        public var recommendedNextMove: ExchangeSecondHalfAction?

        public init(
            previousStance: ExchangeThreadStance? = nil,
            qualification: ExchangeOpportunityQualification,
            priors: ExchangeThreadPriors,
            role: ExchangeSecondHalfRole,
            threadState: ExchangeSecondHalfState,
            isTimeSensitive: Bool = false,
            isPriceSensitive: Bool = false,
            hasLowTrustSignals: Bool = false,
            recommendedNextMove: ExchangeSecondHalfAction? = nil
        ) {
            self.previousStance = previousStance
            self.qualification = qualification
            self.priors = priors
            self.role = role
            self.threadState = threadState
            self.isTimeSensitive = isTimeSensitive
            self.isPriceSensitive = isPriceSensitive
            self.hasLowTrustSignals = hasLowTrustSignals
            self.recommendedNextMove = recommendedNextMove
        }
    }

    public func update(
        input: Input
    ) -> ExchangeThreadStance {
        let previous = input.previousStance ?? input.priors.threadStanceSnapshot ?? .neutral

        let interest = updatedInterest(previous: previous, qualification: input.qualification)
        let urgency = updatedUrgency(previous: previous, isTimeSensitive: input.isTimeSensitive)
        let trust = updatedTrust(previous: previous, hasLowTrustSignals: input.hasLowTrustSignals)
        let priceSensitivity = input.isPriceSensitive ? ExchangePriceSensitivity.high : previous.priceSensitivity
        let flexibility = updatedFlexibility(previous: previous, qualification: input.qualification)
        let readiness = updatedReadiness(from: input.qualification, threadState: input.threadState)
        let postureSummary = buildPostureSummary(
            role: input.role,
            readiness: readiness,
            trust: trust,
            urgency: urgency,
            priceSensitivity: priceSensitivity
        )
        let hints = buildFollowUpHints(
            qualification: input.qualification,
            trust: trust,
            urgency: urgency,
            recommendedNextMove: input.recommendedNextMove
        )

        return ExchangeThreadStance(
            interestLevel: interest,
            urgencyLevel: urgency,
            trustLevel: trust,
            priceSensitivity: priceSensitivity,
            flexibilityLevel: flexibility,
            readinessLevel: readiness,
            postureSummary: postureSummary,
            recommendedNextMove: input.recommendedNextMove,
            followUpHints: hints
        )
    }

    private func updatedInterest(
        previous: ExchangeThreadStance,
        qualification: ExchangeOpportunityQualification
    ) -> ExchangeInterestLevel {
        switch qualification.qualityTier {
        case .decisionReady, .strong:
            return .high
        case .promising:
            return max(previous.interestLevel, .medium)
        case .weak:
            return previous.interestLevel == .high ? .medium : .low
        }
    }

    private func updatedUrgency(
        previous: ExchangeThreadStance,
        isTimeSensitive: Bool
    ) -> ExchangeUrgencyLevel {
        if isTimeSensitive {
            return previous.urgencyLevel == .urgent ? .urgent : .high
        }
        return previous.urgencyLevel
    }

    private func updatedTrust(
        previous: ExchangeThreadStance,
        hasLowTrustSignals: Bool
    ) -> ExchangeTrustLevel {
        if hasLowTrustSignals {
            return previous.trustLevel == .low ? .low : .guarded
        }

        switch previous.trustLevel {
        case .low, .guarded:
            return .guarded
        case .moderate, .high:
            return previous.trustLevel
        }
    }

    private func updatedFlexibility(
        previous: ExchangeThreadStance,
        qualification: ExchangeOpportunityQualification
    ) -> ExchangeFlexibilityLevel {
        if qualification.isDecisionReady {
            return .moderate
        }

        if qualification.isOneMoreClarificationWorthwhile {
            return previous.flexibilityLevel == .rigid ? .moderate : previous.flexibilityLevel
        }

        return previous.flexibilityLevel
    }

    private func updatedReadiness(
        from qualification: ExchangeOpportunityQualification,
        threadState: ExchangeSecondHalfState
    ) -> ExchangeReadinessLevel {
        if threadState == .awaitingCommitmentApproval {
            return .commitmentReady
        }

        switch qualification.qualityTier {
        case .weak:
            return .weak
        case .promising:
            return .promising
        case .strong:
            return .decisionReady
        case .decisionReady:
            return .decisionReady
        }
    }

    private func buildPostureSummary(
        role: ExchangeSecondHalfRole,
        readiness: ExchangeReadinessLevel,
        trust: ExchangeTrustLevel,
        urgency: ExchangeUrgencyLevel,
        priceSensitivity: ExchangePriceSensitivity
    ) -> String {
        let roleText = role == .requester ? "Requester" : "Provider"
        let readinessText = readiness.rawValue
        let trustText = trust.rawValue
        let urgencyText = urgency.rawValue
        let priceText = priceSensitivity.rawValue

        return "\(roleText) posture: \(readinessText), trust \(trustText), urgency \(urgencyText), price sensitivity \(priceText)."
    }

    private func buildFollowUpHints(
        qualification: ExchangeOpportunityQualification,
        trust: ExchangeTrustLevel,
        urgency: ExchangeUrgencyLevel,
        recommendedNextMove: ExchangeSecondHalfAction?
    ) -> [String] {
        var hints: [String] = []

        if qualification.isOneMoreClarificationWorthwhile {
            hints.append("Ask only one focused clarification.")
        }

        if trust == .low || trust == .guarded {
            hints.append("Avoid overcommitting while trust is still limited.")
        }

        if urgency == .high || urgency == .urgent {
            hints.append("Prefer a direct next move over broad exploration.")
        }

        if recommendedNextMove == .compareOptions {
            hints.append("Frame tradeoffs clearly before asking for a decision.")
        }

        return hints
    }
}

private extension Comparable {
    static func max(_ lhs: Self, _ rhs: Self) -> Self {
        lhs < rhs ? rhs : lhs
    }
}

extension ExchangeInterestLevel: Comparable {
    public static func < (lhs: ExchangeInterestLevel, rhs: ExchangeInterestLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}
