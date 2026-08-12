import Foundation

#if DEBUG
@inline(__always)
private func exComposeLog(_ message: @autoclosure () -> String) {
    print("[ExchangeMessageComposer] \(message())")
}
#else
@inline(__always)
private func exComposeLog(_ message: @autoclosure () -> String) { }
#endif

/// Composes exchange drafts using thread state, counterparty context, and policy.
///
/// This sits above `ExchangeDraftEngine`.
/// - `ExchangeDraftEngine` knows how to build a draft
/// - `ExchangeMessageComposer` decides which kind of draft to build and whether
///   to revise an existing one
public struct ExchangeMessageComposer: Sendable {
    private let draftEngine: ExchangeDraftEngine
    private let policyEngine: ExchangePolicyEngine

    public init(
        draftEngine: ExchangeDraftEngine,
        policyEngine: ExchangePolicyEngine
    ) {
        self.draftEngine = draftEngine
        self.policyEngine = policyEngine
    }

    public func compose(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        existingDrafts: [ExchangeMessageDraft] = [],
        preferredKind: ExchangeMessageDraft.Kind? = nil,
        now: Date = Date()
    ) async -> CompositionResult {
        exComposeLog(
            "compose start " +
            "threadID=\(thread.id.uuidString) " +
            "state=\(thread.state.phaseTitle) " +
            "intent=\(thread.intent.kind.rawValue) " +
            "counterpartyID=\(counterparty.id) " +
            "existingDrafts=\(existingDrafts.count) " +
            "preferredKind=\(preferredKind?.rawValue ?? "nil")"
        )

        let activeDraft = latestReusableDraft(
            from: existingDrafts,
            counterpartyID: counterparty.id
        )

        exComposeLog(
            "compose reusableDraft " +
            "found=\(activeDraft != nil) " +
            "draftID=\(activeDraft?.id.uuidString ?? "nil") " +
            "status=\(activeDraft?.status.rawValue ?? "nil")"
        )

        let kind = preferredKind ?? inferredDraftKind(for: thread)

        exComposeLog(
            "compose resolvedKind " +
            "kind=\(kind.rawValue)"
        )

        let baseDraft = await draftEngine.createDraft(
            thread: thread,
            counterparty: counterparty,
            kind: kind,
            superseding: activeDraft?.id,
            now: now
        )

        exComposeLog(
            "compose baseDraft " +
            "draftID=\(baseDraft.id.uuidString) " +
            "kind=\(baseDraft.kind.rawValue) " +
            "status=\(baseDraft.status.rawValue) " +
            "targetCounterpartyID=\(baseDraft.targetCounterpartyID ?? "nil") " +
            "subjectChars=\(baseDraft.subject?.count ?? 0) " +
            "bodyChars=\(baseDraft.body.count)"
        )

        let policy = policyEngine.evaluate(
            thread: thread,
            selectedCounterparty: counterparty,
            draft: baseDraft
        )

        exComposeLog(
            "compose policy " +
            "approvalRequired=\(policy.approval.required) " +
            "approvalRationale=\(policy.approval.rationale) " +
            "disclosureRationale=\(policy.disclosure.rationale)"
        )

        let finalDraft: ExchangeMessageDraft
        if policy.approval.required {
            finalDraft = baseDraft.markingAwaitingApproval(at: now)
            exComposeLog(
                "compose finalDraft awaitingApproval " +
                "draftID=\(finalDraft.id.uuidString) " +
                "status=\(finalDraft.status.rawValue)"
            )
        } else {
            finalDraft = baseDraft
            exComposeLog(
                "compose finalDraft noApproval " +
                "draftID=\(finalDraft.id.uuidString) " +
                "status=\(finalDraft.status.rawValue)"
            )
        }

        let supersededDrafts: [ExchangeMessageDraft]
        if let activeDraft, shouldSupersede(existing: activeDraft, with: finalDraft) {
            supersededDrafts = [activeDraft.superseding(with: finalDraft.id, at: now)]
            exComposeLog(
                "compose superseded existingDraftID=\(activeDraft.id.uuidString) newDraftID=\(finalDraft.id.uuidString)"
            )
        } else {
            supersededDrafts = []
            exComposeLog("compose superseded none")
        }

        let result = CompositionResult(
            draft: finalDraft,
            supersededDrafts: supersededDrafts,
            approvalRequired: policy.approval.required,
            rationale: compositionRationale(
                thread: thread,
                counterparty: counterparty,
                policy: policy,
                kind: kind,
                reusedExistingContext: activeDraft != nil,
                supersededExistingDraft: !supersededDrafts.isEmpty,
                inboundSummary: nil
            )
        )

        exComposeLog(
            "compose done " +
            "draftID=\(result.draft.id.uuidString) " +
            "draftStatus=\(result.draft.status.rawValue) " +
            "approvalRequired=\(result.approvalRequired) " +
            "supersededCount=\(result.supersededDrafts.count)"
        )

        return result
    }

    public func composeInboundReply(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        inbound: ExchangeInboundInterpreter.Result,
        existingDrafts: [ExchangeMessageDraft] = [],
        preferredKind: ExchangeMessageDraft.Kind? = nil,
        now: Date = Date()
    ) async -> CompositionResult {
        exComposeLog(
            "composeInboundReply start " +
            "threadID=\(thread.id.uuidString) " +
            "state=\(thread.state.phaseTitle) " +
            "intent=\(thread.intent.kind.rawValue) " +
            "counterpartyID=\(counterparty.id) " +
            "existingDrafts=\(existingDrafts.count) " +
            "preferredKind=\(preferredKind?.rawValue ?? "nil") " +
            "suggestedDraftKind=\(inbound.suggestedDraftKind?.rawValue ?? "nil") " +
            "inboundDisposition=\(String(describing: inbound.disposition))"
        )

        let activeDraft = latestReusableDraft(
            from: existingDrafts,
            counterpartyID: counterparty.id
        )

        exComposeLog(
            "composeInboundReply reusableDraft " +
            "found=\(activeDraft != nil) " +
            "draftID=\(activeDraft?.id.uuidString ?? "nil") " +
            "status=\(activeDraft?.status.rawValue ?? "nil")"
        )

        let kind = preferredKind
            ?? inbound.suggestedDraftKind
            ?? inferredInboundDraftKind(for: thread, inbound: inbound)

        exComposeLog(
            "composeInboundReply resolvedKind " +
            "kind=\(kind.rawValue)"
        )

        let baseDraft = await draftEngine.createDraft(
            thread: thread,
            counterparty: counterparty,
            kind: kind,
            superseding: activeDraft?.id,
            now: now
        )

        exComposeLog(
            "composeInboundReply baseDraft " +
            "draftID=\(baseDraft.id.uuidString) " +
            "kind=\(baseDraft.kind.rawValue) " +
            "status=\(baseDraft.status.rawValue) " +
            "targetCounterpartyID=\(baseDraft.targetCounterpartyID ?? "nil") " +
            "subjectChars=\(baseDraft.subject?.count ?? 0) " +
            "bodyChars=\(baseDraft.body.count)"
        )

        let policy = policyEngine.evaluate(
            thread: thread,
            selectedCounterparty: counterparty,
            draft: baseDraft
        )

        exComposeLog(
            "composeInboundReply policy " +
            "approvalRequired=\(policy.approval.required) " +
            "approvalRationale=\(policy.approval.rationale) " +
            "disclosureRationale=\(policy.disclosure.rationale)"
        )

        let finalDraft: ExchangeMessageDraft
        if policy.approval.required {
            finalDraft = baseDraft.markingAwaitingApproval(at: now)
            exComposeLog(
                "composeInboundReply finalDraft awaitingApproval " +
                "draftID=\(finalDraft.id.uuidString) " +
                "status=\(finalDraft.status.rawValue)"
            )
        } else {
            finalDraft = baseDraft
            exComposeLog(
                "composeInboundReply finalDraft noApproval " +
                "draftID=\(finalDraft.id.uuidString) " +
                "status=\(finalDraft.status.rawValue)"
            )
        }

        let supersededDrafts: [ExchangeMessageDraft]
        if let activeDraft, shouldSupersede(existing: activeDraft, with: finalDraft) {
            supersededDrafts = [activeDraft.superseding(with: finalDraft.id, at: now)]
            exComposeLog(
                "composeInboundReply superseded existingDraftID=\(activeDraft.id.uuidString) newDraftID=\(finalDraft.id.uuidString)"
            )
        } else {
            supersededDrafts = []
            exComposeLog("composeInboundReply superseded none")
        }

        let result = CompositionResult(
            draft: finalDraft,
            supersededDrafts: supersededDrafts,
            approvalRequired: policy.approval.required,
            rationale: compositionRationale(
                thread: thread,
                counterparty: counterparty,
                policy: policy,
                kind: kind,
                reusedExistingContext: activeDraft != nil,
                supersededExistingDraft: !supersededDrafts.isEmpty,
                inboundSummary: inbound.summary
            )
        )

        exComposeLog(
            "composeInboundReply done " +
            "draftID=\(result.draft.id.uuidString) " +
            "draftStatus=\(result.draft.status.rawValue) " +
            "approvalRequired=\(result.approvalRequired) " +
            "supersededCount=\(result.supersededDrafts.count)"
        )

        return result
    }
}

public extension ExchangeMessageComposer {
    struct CompositionResult: Sendable, Hashable {
        public var draft: ExchangeMessageDraft
        public var supersededDrafts: [ExchangeMessageDraft]
        public var approvalRequired: Bool
        public var rationale: String

        public init(
            draft: ExchangeMessageDraft,
            supersededDrafts: [ExchangeMessageDraft],
            approvalRequired: Bool,
            rationale: String
        ) {
            self.draft = draft
            self.supersededDrafts = supersededDrafts
            self.approvalRequired = approvalRequired
            self.rationale = rationale
        }
    }
}

private extension ExchangeMessageComposer {
    func latestReusableDraft(
        from drafts: [ExchangeMessageDraft],
        counterpartyID: ExchangeCounterparty.ID
    ) -> ExchangeMessageDraft? {
        let filtered = drafts
            .filter {
                $0.targetCounterpartyID == counterpartyID &&
                $0.status != .sent &&
                $0.status != .superseded &&
                $0.status != .abandoned &&
                $0.status != .rejected
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let picked = filtered.first

        exComposeLog(
            "latestReusableDraft " +
            "input=\(drafts.count) " +
            "eligible=\(filtered.count) " +
            "picked=\(picked?.id.uuidString ?? "nil")"
        )

        return picked
    }

    func shouldSupersede(
        existing: ExchangeMessageDraft,
        with newDraft: ExchangeMessageDraft
    ) -> Bool {
        let should =
            existing.subject != newDraft.subject ||
            existing.body != newDraft.body ||
            existing.strategyNote != newDraft.strategyNote ||
            existing.status != newDraft.status

        exComposeLog(
            "shouldSupersede " +
            "existingID=\(existing.id.uuidString) " +
            "newID=\(newDraft.id.uuidString) " +
            "result=\(should)"
        )

        return should
    }

    func inferredDraftKind(for thread: ExchangeThread) -> ExchangeMessageDraft.Kind {
        if let expectation = thread.expectation {
            switch expectation.primaryGoal {
            case .obtainQuote:
                exComposeLog("inferredDraftKind via expectation=obtainQuote -> quoteRequest")
                return .quoteRequest
            case .secureIntroduction:
                exComposeLog("inferredDraftKind via expectation=secureIntroduction -> introduction")
                return .introduction
            case .arrangeCall, .arrangeMeeting:
                exComposeLog("inferredDraftKind via expectation=arrangeCall/arrangeMeeting -> scheduling")
                return .scheduling
            case .advanceNegotiation:
                exComposeLog("inferredDraftKind via expectation=advanceNegotiation -> negotiation")
                return .negotiation
            case .confirmAvailability, .gatherInformation, .confirmFit, .establishContact, .resolveThread, .other:
                break
            }
        }

        let resolved: ExchangeMessageDraft.Kind
        switch thread.intent.kind {
        case .introduce:
            resolved = .introduction
        case .requestQuote:
            resolved = .quoteRequest
        case .followUp, .checkStatus:
            resolved = .followUp
        case .negotiate:
            resolved = .negotiation
        case .arrangeCall, .arrangeMeeting, .invite:
            resolved = .scheduling
        case .message, .find, .source, .coordinate, .plan, .other:
            resolved = .inquiry
        }

        exComposeLog(
            "inferredDraftKind via intent " +
            "intent=\(thread.intent.kind.rawValue) " +
            "resolved=\(resolved.rawValue)"
        )

        return resolved
    }

    func inferredInboundDraftKind(
        for thread: ExchangeThread,
        inbound: ExchangeInboundInterpreter.Result
    ) -> ExchangeMessageDraft.Kind {
        if let suggested = inbound.suggestedDraftKind {
            exComposeLog("inferredInboundDraftKind using inbound suggestion=\(suggested.rawValue)")
            return suggested
        }

        let resolved: ExchangeMessageDraft.Kind
        switch inbound.disposition {
        case .completed, .declined:
            resolved = inferredDraftKind(for: thread)
        case .needsApproval:
            resolved = .negotiation
        case .needsUserInput:
            if thread.intent.kind == .arrangeCall || thread.intent.kind == .arrangeMeeting {
                resolved = .scheduling
            } else {
                resolved = .inquiry
            }
        case .progressed:
            resolved = inferredDraftKind(for: thread)
        case .ambiguous:
            resolved = .inquiry
        }

        exComposeLog(
            "inferredInboundDraftKind disposition=\(String(describing: inbound.disposition)) resolved=\(resolved.rawValue)"
        )

        return resolved
    }

    func compositionRationale(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        policy: ExchangePolicyEngine.DecisionSet,
        kind: ExchangeMessageDraft.Kind,
        reusedExistingContext: Bool,
        supersededExistingDraft: Bool,
        inboundSummary: String?
    ) -> String {
        var parts: [String] = []

        parts.append("Draft kind: \(kind.rawValue).")
        parts.append("Counterparty: \(counterparty.bestDisplayLine).")

        if let inboundSummary = nonBlank(inboundSummary) {
            parts.append("Inbound context: \(inboundSummary).")
        }

        if let expectation = thread.expectation {
            parts.append("Primary goal: \(primaryGoalLabel(expectation.primaryGoal)).")
            parts.append(
                "Preferred outcome: \(outcomeTargetLabel(expectation.preferredOutcome)); acceptable outcome: \(outcomeTargetLabel(expectation.acceptableOutcome))."
            )

            if expectation.maxAutoReplies > 0 {
                parts.append(
                    "Auto-reply budget remaining: \(expectation.autoReplyBudgetRemaining) of \(expectation.maxAutoReplies)."
                )
            } else {
                parts.append("No autonomous reply loop is currently budgeted.")
            }

            if !expectation.requiresUserDecisionOn.isEmpty {
                let triggers = expectation.requiresUserDecisionOn
                    .prefix(3)
                    .map(userDecisionTriggerLabel)
                    .joined(separator: ", ")
                if !triggers.isEmpty {
                    parts.append("User decision triggers: \(triggers).")
                }
            }

            if !expectation.stopConditions.isEmpty {
                let stops = expectation.stopConditions
                    .prefix(3)
                    .map(stopConditionLabel)
                    .joined(separator: ", ")
                if !stops.isEmpty {
                    parts.append("Stop conditions: \(stops).")
                }
            }

            if let notes = nonBlank(expectation.notes) {
                parts.append("Expectation notes: \(notes)")
            }
        }

        parts.append(policy.disclosure.rationale)

        if reusedExistingContext {
            parts.append("An existing draft for this counterparty was considered during composition.")
        } else {
            parts.append("This is a fresh draft for this counterparty.")
        }

        if supersededExistingDraft {
            parts.append("The previous reusable draft was superseded by a new version.")
        }

        if policy.approval.required {
            parts.append(policy.approval.rationale)
        } else {
            parts.append("No extra approval boundary was required at compose time.")
        }

        let rationale = parts.joined(separator: " ")

        exComposeLog(
            "compositionRationale built chars=\(rationale.count)"
        )

        return rationale
    }

    func primaryGoalLabel(_ value: ExchangeExpectation.PrimaryGoal) -> String {
        switch value {
        case .obtainQuote:
            return "obtain a quote"
        case .establishContact:
            return "establish contact"
        case .secureIntroduction:
            return "secure an introduction"
        case .arrangeCall:
            return "arrange a call"
        case .arrangeMeeting:
            return "arrange a meeting"
        case .gatherInformation:
            return "gather information"
        case .confirmAvailability:
            return "confirm availability"
        case .confirmFit:
            return "confirm fit"
        case .advanceNegotiation:
            return "advance negotiation"
        case .resolveThread:
            return "resolve the thread"
        case .other:
            return "move the request forward"
        }
    }

    func outcomeTargetLabel(_ value: ExchangeExpectation.OutcomeTarget) -> String {
        switch value {
        case .completed:
            return "completed"
        case .meaningfulProgress:
            return "meaningful progress"
        case .basicResponse:
            return "a basic response"
        }
    }

    func stopConditionLabel(_ value: ExchangeExpectation.StopCondition) -> String {
        switch value {
        case .autoReplyBudgetExhausted:
            return "auto-reply budget exhausted"
        case .counterpartyRequestsSensitiveInfo:
            return "sensitive info requested"
        case .counterpartyRequestsCommitment:
            return "commitment requested"
        case .counterpartyChangesScopeMaterially:
            return "material scope change"
        case .counterpartyIntroducesPricingNegotiation:
            return "pricing negotiation introduced"
        case .counterpartyIntroducesContractualTerms:
            return "contractual terms introduced"
        case .ambiguityTooHigh:
            return "ambiguity too high"
        case .repeatedLoopDetected:
            return "repeated loop detected"
        case .userInputRequired:
            return "user input required"
        case .approvalRequired:
            return "approval required"
        case .disclosureBoundaryReached:
            return "disclosure boundary reached"
        }
    }

    func userDecisionTriggerLabel(_ value: ExchangeExpectation.UserDecisionTrigger) -> String {
        switch value {
        case .approveOutbound:
            return "approve outbound"
        case .answerMissingInfo:
            return "answer missing info"
        case .chooseBetweenOptions:
            return "choose between options"
        case .reviewQuote:
            return "review quote"
        case .reviewCounteroffer:
            return "review counteroffer"
        case .approveCommitment:
            return "approve commitment"
        case .approveDisclosureExpansion:
            return "approve disclosure expansion"
        case .confirmSchedulingChoice:
            return "confirm scheduling choice"
        case .resolveAmbiguity:
            return "resolve ambiguity"
        }
    }

    func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
