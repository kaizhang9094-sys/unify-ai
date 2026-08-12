import Foundation

/// Structured next-step decision for bounded secretary continuation.
///
/// This is intentionally narrow and legible.
/// It should be possible to explain every decision to the user.
public struct ExchangeContinuationDecision: Codable, Sendable, Hashable {
    public var action: Action
    public var summary: String
    public var rationale: String?
    public var requiresApproval: Bool
    public var shouldIncrementAutoReplyBudget: Bool
    public var suggestedDraftKind: ExchangeMessageDraft.Kind?
    public var completionSignal: ExchangeExpectation.CompletionSignal?
    public var userDecisionTrigger: ExchangeExpectation.UserDecisionTrigger?
    public var stopCondition: ExchangeExpectation.StopCondition?

    public init(
        action: Action,
        summary: String,
        rationale: String? = nil,
        requiresApproval: Bool = false,
        shouldIncrementAutoReplyBudget: Bool = false,
        suggestedDraftKind: ExchangeMessageDraft.Kind? = nil,
        completionSignal: ExchangeExpectation.CompletionSignal? = nil,
        userDecisionTrigger: ExchangeExpectation.UserDecisionTrigger? = nil,
        stopCondition: ExchangeExpectation.StopCondition? = nil
    ) {
        self.action = action
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rationale = rationale?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.requiresApproval = requiresApproval
        self.shouldIncrementAutoReplyBudget = shouldIncrementAutoReplyBudget
        self.suggestedDraftKind = suggestedDraftKind
        self.completionSignal = completionSignal
        self.userDecisionTrigger = userDecisionTrigger
        self.stopCondition = stopCondition
    }
}

public extension ExchangeContinuationDecision {
    enum Action: String, Codable, Sendable, CaseIterable, Hashable {
        case wait
        case resolved
        case continueWithDraft
        case requestApprovalForReply
        case needsUserInput
        case needsClarification
        case failedLegibly
    }
}

public extension ExchangeContinuationDecision {
    static func wait(_ summary: String, rationale: String? = nil) -> ExchangeContinuationDecision {
        .init(
            action: .wait,
            summary: summary,
            rationale: rationale
        )
    }

    static func resolved(
        _ summary: String,
        completionSignal: ExchangeExpectation.CompletionSignal,
        rationale: String? = nil
    ) -> ExchangeContinuationDecision {
        .init(
            action: .resolved,
            summary: summary,
            rationale: rationale,
            completionSignal: completionSignal
        )
    }

    static func continueWithDraft(
        _ summary: String,
        draftKind: ExchangeMessageDraft.Kind,
        rationale: String? = nil,
        incrementBudget: Bool = true
    ) -> ExchangeContinuationDecision {
        .init(
            action: .continueWithDraft,
            summary: summary,
            rationale: rationale,
            requiresApproval: false,
            shouldIncrementAutoReplyBudget: incrementBudget,
            suggestedDraftKind: draftKind
        )
    }

    static func requestApprovalForReply(
        _ summary: String,
        draftKind: ExchangeMessageDraft.Kind,
        trigger: ExchangeExpectation.UserDecisionTrigger = .approveOutbound,
        rationale: String? = nil,
        stopCondition: ExchangeExpectation.StopCondition = .approvalRequired
    ) -> ExchangeContinuationDecision {
        .init(
            action: .requestApprovalForReply,
            summary: summary,
            rationale: rationale,
            requiresApproval: true,
            shouldIncrementAutoReplyBudget: false,
            suggestedDraftKind: draftKind,
            userDecisionTrigger: trigger,
            stopCondition: stopCondition
        )
    }

    static func needsUserInput(
        _ summary: String,
        trigger: ExchangeExpectation.UserDecisionTrigger,
        rationale: String? = nil,
        stopCondition: ExchangeExpectation.StopCondition = .userInputRequired
    ) -> ExchangeContinuationDecision {
        .init(
            action: .needsUserInput,
            summary: summary,
            rationale: rationale,
            userDecisionTrigger: trigger,
            stopCondition: stopCondition
        )
    }

    static func needsClarification(
        _ summary: String,
        trigger: ExchangeExpectation.UserDecisionTrigger = .resolveAmbiguity,
        rationale: String? = nil,
        stopCondition: ExchangeExpectation.StopCondition = .ambiguityTooHigh
    ) -> ExchangeContinuationDecision {
        .init(
            action: .needsClarification,
            summary: summary,
            rationale: rationale,
            userDecisionTrigger: trigger,
            stopCondition: stopCondition
        )
    }

    static func failedLegibly(
        _ summary: String,
        rationale: String? = nil,
        stopCondition: ExchangeExpectation.StopCondition? = nil
    ) -> ExchangeContinuationDecision {
        .init(
            action: .failedLegibly,
            summary: summary,
            rationale: rationale,
            stopCondition: stopCondition
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
