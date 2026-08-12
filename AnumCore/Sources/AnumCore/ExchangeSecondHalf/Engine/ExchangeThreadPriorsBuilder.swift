import Foundation

/// Central builder for compact thread priors.
///
/// This avoids inconsistent state packing and helps keep second-half reasoning
/// compact and stable instead of replaying large raw history.
public struct ExchangeThreadPriorsBuilder: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var role: ExchangeSecondHalfRole
        public var priorQuestionsAsked: [String]
        public var priorAnswersReceived: [String]
        public var currentConstraints: [String]
        public var priorNonCommitments: [String]
        public var lastDecisionFrame: ExchangeDecisionFrame?
        public var lastApprovedPosition: String?
        public var latestDelta: ExchangeThreadDelta?
        public var lastKnownStance: ExchangeThreadStance?

        public init(
            role: ExchangeSecondHalfRole,
            priorQuestionsAsked: [String] = [],
            priorAnswersReceived: [String] = [],
            currentConstraints: [String] = [],
            priorNonCommitments: [String] = [],
            lastDecisionFrame: ExchangeDecisionFrame? = nil,
            lastApprovedPosition: String? = nil,
            latestDelta: ExchangeThreadDelta? = nil,
            lastKnownStance: ExchangeThreadStance? = nil
        ) {
            self.role = role
            self.priorQuestionsAsked = priorQuestionsAsked
            self.priorAnswersReceived = priorAnswersReceived
            self.currentConstraints = currentConstraints
            self.priorNonCommitments = priorNonCommitments
            self.lastDecisionFrame = lastDecisionFrame
            self.lastApprovedPosition = lastApprovedPosition
            self.latestDelta = latestDelta
            self.lastKnownStance = lastKnownStance
        }
    }

    public func build(
        from input: Input
    ) -> ExchangeThreadPriors {
        let recommendation = resolvedRecommendation(
            lastDecisionFrame: input.lastDecisionFrame,
            lastApprovedPosition: input.lastApprovedPosition
        )

        return ExchangeThreadPriors(
            priorQuestionsAsked: dedupePreservingOrder(input.priorQuestionsAsked),
            priorAnswersReceived: dedupePreservingOrder(input.priorAnswersReceived),
            currentConstraints: dedupePreservingOrder(input.currentConstraints),
            priorNonCommitments: dedupePreservingOrder(input.priorNonCommitments),
            lastKnownRecommendation: recommendation,
            latestDelta: input.latestDelta,
            threadStanceSnapshot: input.lastKnownStance
        )
    }

    private func resolvedRecommendation(
        lastDecisionFrame: ExchangeDecisionFrame?,
        lastApprovedPosition: String?
    ) -> String? {
        if let approved = normalizedNonEmpty(lastApprovedPosition) {
            return approved
        }

        if let frameRecommendation = normalizedNonEmpty(lastDecisionFrame?.recommendation) {
            return frameRecommendation
        }

        return nil
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func dedupePreservingOrder(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in items {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }

        return result
    }
}
