import Foundation

/// Stage 1 seam for requester-side provider response assessment.
///
/// This protocol is intentionally synchronous right now to avoid broad async
/// blast radius across `ExchangeSecondHalfCoordinator.evaluate`.
/// A future LLM-backed implementation can introduce an async variant.
public protocol ExchangeProviderResponseAssessmentEngine: Sendable {
    func assessProviderResponse(
        context: ExchangeSecondHalfExecutionContext,
        priorAssessment: ExchangeProviderResponseAssessment?
    ) -> ExchangeProviderResponseAssessment?
}

public struct ExchangeHeuristicProviderResponseAssessmentEngine: ExchangeProviderResponseAssessmentEngine, Sendable {
    public init() {}

    public func assessProviderResponse(
        context: ExchangeSecondHalfExecutionContext,
        priorAssessment: ExchangeProviderResponseAssessment?
    ) -> ExchangeProviderResponseAssessment? {
        var conditions: [ConditionAssessment] = []

        for issue in context.unresolvedIssues {
            let text = issue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            conditions.append(
                ConditionAssessment(
                    conditionText: text,
                    source: inferSource(for: text),
                    status: .notAnswered
                )
            )
        }

        for fact in context.clarifiedFacts {
            let text = fact.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            conditions.append(
                ConditionAssessment(
                    conditionText: text,
                    source: inferSource(for: text),
                    status: .partiallySatisfied
                )
            )
        }

        if let reply = context.latestCounterpartyReplyText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reply.isEmpty {
            conditions.append(
                ConditionAssessment(
                    conditionText: "Latest provider reply received",
                    source: .providerReply,
                    status: .partiallySatisfied,
                    evidence: [reply]
                )
            )
        }

        guard !conditions.isEmpty else { return priorAssessment }

        let hasContradiction = conditions.contains(where: { $0.status == .contradicted })
        let hasUnanswered = conditions.contains(where: { $0.status == .notAnswered || $0.status == .needsFollowUp })
        let hasProgress = conditions.contains(where: {
            $0.status == .satisfied || $0.status == .partiallySatisfied || $0.status == .impliedFlexible
        })

        let readiness: DecisionReadiness = {
            if hasContradiction { return .blockedByContradiction }
            if hasUnanswered { return .needsFollowUp }
            return .readyForDecisionFrame
        }()

        let nextMove: NextMoveRecommendation? = {
            if hasContradiction { return .requestUserInput }
            if hasUnanswered { return .askClarification }
            if hasProgress { return .frameDecision }
            return nil
        }()

        return ExchangeProviderResponseAssessment(
            conditionAssessments: conditions,
            confidenceDelta: hasProgress ? .positive : .stable,
            shortlistRecommendation: hasProgress ? .promote : .noChange,
            decisionReadiness: readiness,
            nextMoveRecommendation: nextMove,
            requiresHumanJudgment: hasContradiction,
            safeForAutonomousFollowup: hasUnanswered && !hasContradiction,
            assessedAt: Date(),
            summary: "Heuristic assessment based on clarified facts, unresolved issues, and latest provider reply."
        )
    }

    private func inferSource(for text: String) -> ConditionSource {
        let lower = text.lowercased()
        if lower.contains("price") || lower.contains("budget") || lower.contains("financing") || lower.contains("terms") {
            return .commercialConstraint
        }
        if lower.contains("time") || lower.contains("tomorrow") || lower.contains("saturday") || lower.contains("availability") {
            return .timingConstraint
        }
        if lower.contains("preference") || lower.contains("likes") || lower.contains("style") {
            return .userPreference
        }
        if lower.contains("confirm") || lower.contains("clarify") || lower.contains("question") {
            return .gapFill
        }
        return .unknown
    }
}
