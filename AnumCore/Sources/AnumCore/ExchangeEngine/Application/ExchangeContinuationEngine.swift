import Foundation

/// Decides the next bounded secretary action after an inbound event.
///
/// This engine stays conservative:
/// - stop when ambiguity is high
/// - stop when the user must decide
/// - stop before commitment / disclosure expansion
/// - allow at most one autonomous clarification turn when explicitly allowed
/// - otherwise only continue within the bounded reply budget
public struct ExchangeContinuationEngine: Sendable {
    public init() {}

    public func decideNextAction(
        thread: ExchangeThread,
        expectation: ExchangeExpectation,
        inbound: ExchangeInboundInterpreter.Result
    ) -> ExchangeContinuationDecision {
        if inbound.detectedSignals.contains(where: expectation.completionSignals.contains) {
            let signal =
                inbound.detectedSignals.first(where: expectation.completionSignals.contains)
                ?? .answerReceived

            return .resolved(
                inbound.summary,
                completionSignal: signal,
                rationale: inbound.rationale
            )
        }

        switch inbound.disposition {
        case .completed:
            let signal = inbound.detectedSignals.first ?? .answerReceived
            return .resolved(
                inbound.summary,
                completionSignal: signal,
                rationale: inbound.rationale
            )

        case .declined:
            return .resolved(
                inbound.summary,
                completionSignal: .explicitDecline,
                rationale: inbound.rationale
            )

        case .needsApproval:
            return .requestApprovalForReply(
                inbound.summary,
                draftKind: .negotiation,
                trigger: .approveCommitment,
                rationale: inbound.rationale,
                stopCondition: .approvalRequired
            )

        case .needsUserInput:
            if canAutonomouslyClarify(thread: thread, expectation: expectation, inbound: inbound) {
                return .continueWithDraft(
                    clarificationSummary(from: inbound),
                    draftKind: inbound.suggestedDraftKind ?? fallbackDraftKind(for: thread),
                    rationale: clarificationRationale(from: inbound),
                    incrementBudget: true
                )
            }

            return .needsUserInput(
                inbound.summary,
                trigger: userDecisionTrigger(for: thread, expectation: expectation),
                rationale: inbound.extractedQuestion ?? inbound.rationale,
                stopCondition: .userInputRequired
            )

        case .ambiguous:
            if canAutonomouslyClarify(thread: thread, expectation: expectation, inbound: inbound) {
                return .continueWithDraft(
                    clarificationSummary(from: inbound),
                    draftKind: inbound.suggestedDraftKind ?? fallbackDraftKind(for: thread),
                    rationale: clarificationRationale(from: inbound),
                    incrementBudget: true
                )
            }

            return .needsClarification(
                inbound.summary,
                trigger: .resolveAmbiguity,
                rationale: inbound.rationale,
                stopCondition: .ambiguityTooHigh
            )

        case .progressed:
            guard inbound.requiresReply else {
                return .wait(
                    inbound.summary,
                    rationale: inbound.rationale
                )
            }

            if canAutonomouslyClarify(thread: thread, expectation: expectation, inbound: inbound) {
                return .continueWithDraft(
                    clarificationSummary(from: inbound),
                    draftKind: inbound.suggestedDraftKind ?? fallbackDraftKind(for: thread),
                    rationale: clarificationRationale(from: inbound),
                    incrementBudget: true
                )
            }

            guard expectation.canAutoReply else {
                return .needsUserInput(
                    "The thread progressed, but the bounded auto-reply budget is exhausted.",
                    trigger: .approveOutbound,
                    rationale: "Stop condition reached: \(ExchangeExpectation.StopCondition.autoReplyBudgetExhausted.rawValue).",
                    stopCondition: .autoReplyBudgetExhausted
                )
            }

            let draftKind = inbound.suggestedDraftKind ?? fallbackDraftKind(for: thread)

            if shouldRequireApprovalForReply(thread: thread, draftKind: draftKind) {
                return .requestApprovalForReply(
                    inbound.summary,
                    draftKind: draftKind,
                    trigger: .approveOutbound,
                    rationale: inbound.rationale,
                    stopCondition: .approvalRequired
                )
            }

            return .continueWithDraft(
                inbound.summary,
                draftKind: draftKind,
                rationale: inbound.rationale,
                incrementBudget: true
            )
        }
    }
}

private extension ExchangeContinuationEngine {
    func canAutonomouslyClarify(
        thread: ExchangeThread,
        expectation: ExchangeExpectation,
        inbound: ExchangeInboundInterpreter.Result
    ) -> Bool {
        guard inbound.requiresReply else { return false }
        guard inbound.extractedQuestion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }
        guard expectation.allowsAutonomousClarification else { return false }
        guard thread.facets?.allowsAutonomousClarification == true else { return false }
        guard thread.canUseAutonomousClarification else { return false }
        guard expectation.canAutoReply else { return false }
        return true
    }

    func clarificationSummary(
        from inbound: ExchangeInboundInterpreter.Result
    ) -> String {
        let question = inbound.extractedQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let question, !question.isEmpty {
            return question
        }

        return inbound.summary
    }

    func clarificationRationale(
        from inbound: ExchangeInboundInterpreter.Result
    ) -> String? {
        let question = inbound.extractedQuestion?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let question, !question.isEmpty {
            if let rationale = inbound.rationale?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rationale.isEmpty {
                return "\(rationale) Autonomous clarification is still allowed for this thread."
            }
            return "Autonomous clarification is still allowed for this thread."
        }

        return inbound.rationale
    }

    func fallbackDraftKind(for thread: ExchangeThread) -> ExchangeMessageDraft.Kind {
        switch thread.intent.kind {
        case .arrangeCall, .arrangeMeeting, .invite:
            return .scheduling
        case .followUp, .checkStatus:
            return .followUp
        case .requestQuote:
            return .quoteRequest
        case .introduce:
            return .introduction
        case .negotiate:
            return .negotiation
        case .message, .find, .source, .coordinate, .plan, .other:
            return .inquiry
        }
    }

    func shouldRequireApprovalForReply(
        thread: ExchangeThread,
        draftKind: ExchangeMessageDraft.Kind
    ) -> Bool {
        if thread.posture.privacy == .guarded {
            return true
        }

        switch draftKind {
        case .negotiation, .closure:
            return true
        case .quoteRequest, .introduction, .followUp, .scheduling, .inquiry, .other:
            return false
        }
    }

    func userDecisionTrigger(
        for thread: ExchangeThread,
        expectation: ExchangeExpectation
    ) -> ExchangeExpectation.UserDecisionTrigger {
        if expectation.requiresUserDecisionOn.contains(.answerMissingInfo) {
            return .answerMissingInfo
        }

        switch thread.intent.kind {
        case .requestQuote:
            return .answerMissingInfo
        case .arrangeCall, .arrangeMeeting:
            return .confirmSchedulingChoice
        case .negotiate:
            return .reviewCounteroffer
        case .find, .source:
            return .chooseBetweenOptions
        case .introduce, .message, .followUp, .checkStatus, .invite, .coordinate, .plan, .other:
            return .resolveAmbiguity
        }
    }
}
