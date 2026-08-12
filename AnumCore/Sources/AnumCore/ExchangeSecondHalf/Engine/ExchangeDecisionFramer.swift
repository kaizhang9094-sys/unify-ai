import Foundation

/// Builds decision-ready user frames from second-half state.
///
/// This turns thread progress into a useful user-facing packet instead of
/// raw messages or internal status fragments.
public struct ExchangeDecisionFramer: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var role: ExchangeSecondHalfRole
        public var state: ExchangeSecondHalfState
        public var qualification: ExchangeOpportunityQualification
        public var delta: ExchangeThreadDelta?
        public var stance: ExchangeThreadStance
        public var clarifiedFacts: [String]
        public var unresolvedIssues: [String]
        public var recommendation: String
        public var tradeoffs: [String]
        public var nextMove: ExchangeSecondHalfAction?
        public var escalationReason: String?

        public init(
            role: ExchangeSecondHalfRole,
            state: ExchangeSecondHalfState,
            qualification: ExchangeOpportunityQualification,
            delta: ExchangeThreadDelta? = nil,
            stance: ExchangeThreadStance,
            clarifiedFacts: [String] = [],
            unresolvedIssues: [String] = [],
            recommendation: String,
            tradeoffs: [String] = [],
            nextMove: ExchangeSecondHalfAction? = nil,
            escalationReason: String? = nil
        ) {
            self.role = role
            self.state = state
            self.qualification = qualification
            self.delta = delta
            self.stance = stance
            self.clarifiedFacts = clarifiedFacts
            self.unresolvedIssues = unresolvedIssues
            self.recommendation = recommendation
            self.tradeoffs = tradeoffs
            self.nextMove = nextMove
            self.escalationReason = escalationReason
        }
    }

    public func buildFrame(
        input: Input,
        boundary: ExchangeCommitmentBoundary? = nil,
        policy: ExchangeSecondHalfPolicy
    ) -> ExchangeDecisionFrame {
        let changed = buildWhatChanged(delta: input.delta)
        let summary = buildSummary(input: input, boundary: boundary)
        let needsCommitmentApproval = boundary.map { policy.requiresApproval(for: $0) } ?? false
        let needsUserJudgment = input.state.isHumanReviewState || needsCommitmentApproval || input.nextMove == .requestUserInput

        return ExchangeDecisionFrame(
            summary: summary,
            clarifiedFacts: cleaned(input.clarifiedFacts),
            whatChanged: changed,
            unresolvedIssues: cleaned(input.unresolvedIssues),
            recommendation: input.recommendation.trimmingCharacters(in: .whitespacesAndNewlines),
            tradeoffs: cleaned(input.tradeoffs),
            nextMove: input.nextMove,
            needsUserJudgment: needsUserJudgment,
            needsCommitmentApproval: needsCommitmentApproval
        )
    }

    private func buildSummary(
        input: Input,
        boundary: ExchangeCommitmentBoundary?
    ) -> String {
        var parts: [String] = []

        parts.append("Role: \(input.role.displayTitle).")
        parts.append("State: \(input.state.displayTitle).")
        parts.append("Qualification: \(input.qualification.qualityTier.rawValue).")
        parts.append(input.stance.postureSummary)

        if let escalationReason = nonEmpty(input.escalationReason) {
            parts.append("Escalation reason: \(escalationReason).")
        }

        if let boundary {
            parts.append("Boundary: \(boundary.kind.rawValue). \(boundary.reason)")
        }

        return parts.joined(separator: " ")
    }

    private func buildWhatChanged(
        delta: ExchangeThreadDelta?
    ) -> [String] {
        guard let delta, delta.hasMeaningfulChange else { return [] }

        var items: [String] = []

        items.append(contentsOf: delta.newFactsLearned)

        switch delta.riskChange {
        case .increased:
            items.append("Risk increased.")
        case .decreased:
            items.append("Risk decreased.")
        case .unchanged:
            break
        }

        switch delta.readinessShift {
        case .increased:
            items.append("The thread moved closer to decision.")
        case .decreased:
            items.append("The thread became less decision-ready.")
        case .unchanged:
            break
        }

        if delta.recommendationChanged {
            items.append("The recommendation changed.")
        }

        if delta.nextStepChanged {
            items.append("The next step changed.")
        }

        if let significance = nonEmpty(delta.significanceExplanation) {
            items.append(significance)
        }

        return cleaned(items)
    }

    private func cleaned(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                output.append(trimmed)
            }
        }

        return output
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
