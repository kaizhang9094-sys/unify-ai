import Foundation

/// Canonical builder for user-facing decision packets.
///
/// This sits above the raw engines and produces a stable user-facing frame
/// from the core second-half state.
public struct ExchangeDecisionFrameBuilder: Sendable {
    private let changeSummaryBuilder: ExchangeChangeSummaryBuilder
    private let escalationReasonBuilder: ExchangeEscalationReasonBuilder
    private let recommendationBuilder: ExchangeRecommendationBuilder

    public init(
        changeSummaryBuilder: ExchangeChangeSummaryBuilder = .init(),
        escalationReasonBuilder: ExchangeEscalationReasonBuilder = .init(),
        recommendationBuilder: ExchangeRecommendationBuilder = .init()
    ) {
        self.changeSummaryBuilder = changeSummaryBuilder
        self.escalationReasonBuilder = escalationReasonBuilder
        self.recommendationBuilder = recommendationBuilder
    }

    public struct Input: Sendable {
        public var role: ExchangeSecondHalfRole
        public var state: ExchangeSecondHalfState
        public var qualification: ExchangeOpportunityQualification
        public var stance: ExchangeThreadStance
        public var delta: ExchangeThreadDelta?
        public var plan: ExchangeSecondHalfPlan
        public var boundary: ExchangeCommitmentBoundary?
        public var clarifiedFacts: [String]
        public var unresolvedIssues: [String]
        public var tradeoffs: [String]
        public var inquiry: ExchangeInboundInquiry?

        public init(
            role: ExchangeSecondHalfRole,
            state: ExchangeSecondHalfState,
            qualification: ExchangeOpportunityQualification,
            stance: ExchangeThreadStance,
            delta: ExchangeThreadDelta? = nil,
            plan: ExchangeSecondHalfPlan,
            boundary: ExchangeCommitmentBoundary? = nil,
            clarifiedFacts: [String] = [],
            unresolvedIssues: [String] = [],
            tradeoffs: [String] = [],
            inquiry: ExchangeInboundInquiry? = nil
        ) {
            self.role = role
            self.state = state
            self.qualification = qualification
            self.stance = stance
            self.delta = delta
            self.plan = plan
            self.boundary = boundary
            self.clarifiedFacts = clarifiedFacts
            self.unresolvedIssues = unresolvedIssues
            self.tradeoffs = tradeoffs
            self.inquiry = inquiry
        }
    }

    public func build(
        input: Input,
        policy: ExchangeSecondHalfPolicy
    ) -> ExchangeDecisionFrame {
        let recommendation = recommendationBuilder.build(
            qualification: input.qualification,
            stance: input.stance,
            plan: input.plan,
            boundary: input.boundary,
            role: input.role
        )

        let changed = changeSummaryBuilder.build(from: input.delta)
        let escalationReason = escalationReasonBuilder.build(
            boundary: input.boundary,
            missingFacts: input.qualification.missingFacts,
            inquiry: input.inquiry
        )

        let summary = buildSummary(
            input: input,
            recommendation: recommendation.text,
            escalationReason: escalationReason
        )

        let needsCommitmentApproval = input.boundary.map { policy.requiresApproval(for: $0) } ?? false
        let needsUserJudgment = input.state.isHumanReviewState ||
            input.plan.needsUserInput ||
            input.plan.needsApproval ||
            needsCommitmentApproval

        let allTradeoffs = cleaned(input.tradeoffs + input.qualification.weaknessReasons)

        return ExchangeDecisionFrame(
            summary: summary,
            clarifiedFacts: cleaned(input.clarifiedFacts + input.qualification.strengthReasons),
            whatChanged: changed,
            unresolvedIssues: cleaned(input.unresolvedIssues + input.qualification.missingFacts),
            recommendation: recommendation.text,
            tradeoffs: allTradeoffs,
            nextMove: input.plan.selectedAction,
            needsUserJudgment: needsUserJudgment,
            needsCommitmentApproval: needsCommitmentApproval
        )
    }

    private func buildSummary(
        input: Input,
        recommendation: String,
        escalationReason: String?
    ) -> String {
        var parts: [String] = []

        parts.append("Role: \(input.role.displayTitle).")
        parts.append("State: \(input.state.displayTitle).")
        parts.append("Qualification: \(input.qualification.qualityTier.rawValue).")
        parts.append(input.stance.postureSummary)
        parts.append("Recommendation: \(recommendation)")

        if let escalationReason = nonEmpty(escalationReason) {
            parts.append("Escalation: \(escalationReason)")
        }

        return parts.joined(separator: " ")
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
