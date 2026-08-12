import Foundation

#if DEBUG
@inline(__always)
private func exchSecondHalfExecutorLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSecondHalfActionExecutor] \(message())")
}
#else
@inline(__always)
private func exchSecondHalfExecutorLog(_ message: @autoclosure () -> String) {}
#endif

/// Executes the second-half layer's selected next move against the legacy
/// Exchange thread in a conservative, no-auto-send way.
///
/// Important:
/// - This executor does NOT send federation messages.
/// - This executor does NOT queue outbox work.
/// - This executor does NOT approve/accept/decline externally.
/// - Safe autonomous moves may create local drafts only.
/// - Approval-boundary moves may create local pending approvals only.
public struct ExchangeSecondHalfActionExecutor: Sendable {
    public init() {}

    public struct Result: Sendable, Hashable {
        public var command: Command
        public var updatedThread: ExchangeThread?
        public var createdDraft: ExchangeMessageDraft?
        public var createdApproval: ExchangeApproval?
        public var reason: String

        public init(
            command: Command,
            updatedThread: ExchangeThread?,
            createdDraft: ExchangeMessageDraft? = nil,
            createdApproval: ExchangeApproval? = nil,
            reason: String
        ) {
            self.command = command
            self.updatedThread = updatedThread
            self.createdDraft = createdDraft
            self.createdApproval = createdApproval
            self.reason = reason
        }
    }

    public enum Command: String, Sendable, Hashable {
        case noChange
        case updateThreadOnly
        case preparedLocalDraft
        case preparedLocalDraftAwaitingApproval
        case needsUserInput
        case needsApproval
        case decisionReady
        case stalled
        case blocked
    }

    public func apply(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        to thread: ExchangeThread,
        store: any ExchangeStore,
        now: Date = Date()
    ) async throws -> Result {
        let actionRaw = normalizedActionRaw(from: display)
        let action = ExchangeSecondHalfAction(rawValue: actionRaw)

        let command = commandFor(
            display: display,
            action: action,
            actionRaw: actionRaw
        )

        var updated = thread
        var metadata = updated.metadata

        metadata["second_half_state"] = display.status.state
        metadata["second_half_role"] = display.status.role
        metadata["second_half_quality"] = display.status.quality
        metadata["second_half_readiness"] = display.status.readiness
        metadata["second_half_next_action"] = actionRaw
        metadata["second_half_command"] = command.rawValue
        metadata["second_half_needs_human_attention"] = display.needsHumanAttention ? "true" : "false"
        metadata["second_half_can_run_autonomously"] = display.canRunAutonomously ? "true" : "false"
        metadata["second_half_requires_approval"] = commandRequiresApprovalState(command) ? "true" : "false"
        metadata["second_half_boundary_kind"] = display.boundary.kind
        metadata["second_half_boundary_reason"] = display.boundary.reason
        metadata["second_half_updated_at"] = ISO8601DateFormatter().string(from: now)

        if let rationale = display.nextMove?.rationale.nilIfBlank {
            metadata["second_half_next_rationale"] = rationale
        }

        if let escalation = display.escalationReason?.nilIfBlank {
            metadata["second_half_escalation_reason"] = escalation
        }

        let visibleSummary = visibleSummaryFor(
            display: display,
            command: command
        )

        let localDraft = try await prepareLocalDraftIfNeeded(
            display: display,
            action: action,
            thread: updated,
            store: store,
            now: now
        )

        let localApproval = try await prepareLocalApprovalIfNeeded(
            display: display,
            command: command,
            thread: updated,
            draft: localDraft,
            store: store,
            now: now
        )

        if let localDraft {
            metadata["second_half_latest_local_draft"] = localDraft.id.uuidString
        }

        if let localApproval {
            metadata["second_half_latest_local_approval"] = localApproval.id.uuidString
        }

        let didChange =
            updated.metadata != metadata ||
            updated.visibleSummary != visibleSummary

        if didChange {
            updated.metadata = metadata
            updated.visibleSummary = visibleSummary
            updated.updatedAt = now
            try await store.updateThread(updated)
        }

        guard didChange || localDraft != nil || localApproval != nil else {
            return Result(
                command: .noChange,
                updatedThread: nil,
                reason: "Second-half command state was already current."
            )
        }

        return Result(
            command: command,
            updatedThread: didChange ? updated : nil,
            createdDraft: localDraft,
            createdApproval: localApproval,
            reason: reasonFor(
                display: display,
                command: command,
                actionRaw: actionRaw,
                draft: localDraft,
                approval: localApproval
            )
        )
    }
}

private extension ExchangeSecondHalfActionExecutor {
    func normalizedActionRaw(
        from display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> String {
        let canonical = ExchangeSecondHalfUIAdapter.canonicalSecondHalfActionRaw(for: display)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !canonical.isEmpty, ExchangeSecondHalfAction(rawValue: canonical) != nil {
            return canonical
        }
        return firstNonBlank(
            display.actionTitle,
            display.nextMove?.action,
            "none"
        ) ?? "none"
    }

    func commandFor(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        action: ExchangeSecondHalfAction?,
        actionRaw: String
    ) -> Command {
        let hasOutboundArtifact = hasApprovalEligibleOutboundArtifact(display: display)
        let providerNeedsInputNoArtifact =
            providerNeedsManualInputState(display: display, action: action, actionRaw: actionRaw)
            && !hasOutboundArtifact
            && action != .escalateForApproval

        if providerNeedsInputNoArtifact {
            return .needsUserInput
        }

        if display.boundary.requiresHumanApproval {
            if displayDraftHasSendableBody(display.draft) {
                return .preparedLocalDraftAwaitingApproval
            }
            if action == .escalateForApproval || hasOutboundArtifact {
                return .needsApproval
            }
            return .needsUserInput
        }

        if action == .requestUserInput {
            return .needsUserInput
        }

        if display.needsHumanAttention {
            return .needsUserInput
        }

        switch action {
        case .autoRespond,
             .answerClarification,
             .askClarification,
             .proposeTerms,
             .reviseTerms:
            if display.draft != nil {
                return .preparedLocalDraft
            }
            return .updateThreadOnly

        case .escalateForApproval:
            return .needsApproval

        case .requestUserInput:
            return .needsUserInput

        case .frameDecision,
             .recommendNextMove,
             .compareOptions:
            return .decisionReady

        case .markStalled,
             .pause:
            return .stalled

        case .markBlocked:
            return .blocked

        case .qualifyMatch,
             .accept,
             .decline,
             .complete,
             .none:
            return .updateThreadOnly
        }
    }

    func visibleSummaryFor(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        command: Command
    ) -> String? {
        switch command {
        case .preparedLocalDraft:
            return firstNonBlank(
                display.draft?.bodyPreview,
                display.recommendation,
                display.summary
            )

        case .preparedLocalDraftAwaitingApproval:
            return firstNonBlank(
                display.escalationReason,
                display.boundary.reason,
                display.draft?.bodyPreview,
                display.recommendation,
                display.summary
            )

        case .needsApproval:
            return firstNonBlank(
                display.escalationReason,
                display.boundary.reason,
                display.recommendation,
                display.summary
            )

        case .needsUserInput:
            return firstNonBlank(
                display.nextMove?.rationale,
                display.recommendation,
                display.summary
            )

        case .decisionReady:
            return firstNonBlank(
                display.decision?.summary,
                display.recommendation,
                display.summary
            )

        case .stalled:
            return firstNonBlank(
                display.nextMove?.rationale,
                "This thread is stalled until something changes."
            )

        case .blocked:
            return firstNonBlank(
                display.boundary.reason,
                display.escalationReason,
                "This thread is blocked."
            )

        case .updateThreadOnly, .noChange:
            return firstNonBlank(display.summary)
        }
    }

    func prepareLocalDraftIfNeeded(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        action: ExchangeSecondHalfAction?,
        thread: ExchangeThread,
        store: any ExchangeStore,
        now: Date
    ) async throws -> ExchangeMessageDraft? {
        guard let draftDisplay = display.draft else {
            return nil
        }

        if shouldSuppressOutboundDraftAfterSend(
            display: display,
            action: action,
            thread: thread
        ) {
            exchSecondHalfExecutorLog(
                "suppressing post-send requester draft | state=\(display.status.state) action=\(action?.rawValue ?? "none") threadState=\(thread.state.phaseTitle)"
            )
            return nil
        }

        guard shouldCreateLocalDraft(for: action, display: display) else {
            return nil
        }

        guard ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread) else {
            #if DEBUG
            exchSecondHalfExecutorLog(
                "prepareLocalDraft suppressed | no_recipient_anchor thread=\(thread.id.uuidString)"
            )
            #endif
            return nil
        }

        let body = (draftDisplay.outboundBodyFull ?? draftDisplay.bodyPreview)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return nil
        }

        let existingDrafts = try await store.listDrafts(threadID: thread.id)
        if let existing = existingSecondHalfDraft(
            in: existingDrafts,
            subject: draftDisplay.subject,
            body: body,
            action: action
        ) {
            return existing
        }

        let status: ExchangeMessageDraft.Status

        if display.boundary.requiresHumanApproval {
            status = .awaitingApproval
        } else if action == .autoRespond {
            // "Auto respond" means the secretary is allowed to prepare an approved
            // local response artifact. It still does not queue or send externally here.
            status = .approved
        } else {
            status = .draft
        }

        var draftMetadata: [String: String] = [
            "second_half_generated": "true",
            "second_half_action": action?.rawValue ?? "none",
            "second_half_role": display.status.role,
            "second_half_state": display.status.state,
            "second_half_no_auto_send": "true",
            "second_half_autorespond_prepared": action == .autoRespond ? "true" : "false"
        ]
        if draftDisplay.agencyComposePolicy == .skipFullComposeCompareFirstGrounded {
            draftMetadata["agency_body_source"] = "providerInquiryCompare.draftReply"
            draftMetadata["agency_body_grounding"] = "published_facts"
            draftMetadata["agency_compose_policy"] =
                ExchangeDraftAgencyComposePolicy.skipFullComposeCompareFirstGrounded.rawValue
            draftMetadata["provider_compare_first_eligible"] = "true"
        }

        let draft = ExchangeMessageDraft(
            threadID: thread.id,
            createdAt: now,
            updatedAt: now,
            status: status,
            kind: draftKind(for: action),
            audience: .externalCounterparty,
            subject: draftDisplay.subject,
            body: body,
            strategyNote: firstNonBlank(
                display.nextMove?.rationale,
                display.recommendation,
                display.summary
            ),
            posture: thread.posture,
            targetCounterpartyID: thread.selectedCounterpartyID,
            metadata: draftMetadata
        )

        try await store.saveDraft(draft)
        return draft
    }

    func prepareLocalApprovalIfNeeded(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        command: Command,
        thread: ExchangeThread,
        draft: ExchangeMessageDraft?,
        store: any ExchangeStore,
        now: Date
    ) async throws -> ExchangeApproval? {
        guard command == .preparedLocalDraftAwaitingApproval || command == .needsApproval else {
            return nil
        }

        guard display.boundary.requiresHumanApproval else {
            return nil
        }

        guard shouldPersistPendingApproval(
            display: display,
            command: command,
            draft: draft
        ) else {
            return nil
        }

        if let existing = try await store.fetchLatestApproval(threadID: thread.id),
           existing.status == .pending {
            return existing
        }

        let approval = ExchangeApproval(
            threadID: thread.id,
            createdAt: now,
            updatedAt: now,
            status: .pending,
            kind: approvalKind(for: display, draft: draft),
            requestedAction: requestedApprovalAction(for: display, draft: draft),
            draftID: draft?.id,
            summary: approvalSummary(for: display, draft: draft),
            rationale: firstNonBlank(
                display.boundary.reason,
                display.escalationReason,
                display.nextMove?.rationale,
                "Second-half determined this move needs explicit approval."
            ),
            expiresAt: nil,
            metadata: [
                "second_half_generated": "true",
                "second_half_no_auto_send": "true",
                "second_half_boundary_kind": display.boundary.kind
            ]
        )

        try await store.saveApproval(approval)
        return approval
    }

    func shouldCreateLocalDraft(
        for action: ExchangeSecondHalfAction?,
        display: ExchangeSecondHalfUIAdapter.DisplayModel
    ) -> Bool {
        guard display.draft != nil else {
            return false
        }

        switch action {
        case .autoRespond,
             .answerClarification,
             .askClarification,
             .proposeTerms,
             .reviseTerms,
             .recommendNextMove,
             .frameDecision:
            return true

        case .decline:
            return true

        case .qualifyMatch,
             .requestUserInput,
             .compareOptions,
             .escalateForApproval,
             .accept,
             .pause,
             .markBlocked,
             .markStalled,
             .complete,
             .none:
            return display.boundary.requiresHumanApproval
        }
    }

    func shouldSuppressOutboundDraftAfterSend(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        action: ExchangeSecondHalfAction?,
        thread: ExchangeThread
    ) -> Bool {
        let requesterTitle = ExchangeSecondHalfRole.requester.displayTitle
        guard display.status.role == requesterTitle else {
            return false
        }

        let suppressibleActions: Set<ExchangeSecondHalfAction> = [
            .frameDecision,
            .recommendNextMove,
            .compareOptions,
            .askClarification
        ]

        guard let action, suppressibleActions.contains(action) else {
            return false
        }

        let stateLower = display.status.state.lowercased()

        let awaitingByDisplay =
            stateLower.contains("awaiting provider") ||
            stateLower.contains("awaiting response") ||
            stateLower.contains("waiting for counterparty")

        let awaitingByThread: Bool
        if case .awaitingResponse = thread.state {
            awaitingByThread = true
        } else {
            awaitingByThread = false
        }

        let agencyDecisionIsWait =
            display.agencyAssessment?.agencyDecision.autonomyDisposition == .wait

        return awaitingByDisplay || awaitingByThread || agencyDecisionIsWait
    }

    func existingSecondHalfDraft(
        in drafts: [ExchangeMessageDraft],
        subject: String?,
        body: String,
        action: ExchangeSecondHalfAction?
    ) -> ExchangeMessageDraft? {
        drafts
            .filter { $0.metadata["second_half_generated"] == "true" }
            .filter { $0.metadata["second_half_action"] == (action?.rawValue ?? "none") }
            .first { existing in
                existing.subject == subject &&
                existing.body.trimmingCharacters(in: .whitespacesAndNewlines) == body &&
                existing.isActionable
            }
    }

    func draftKind(
        for action: ExchangeSecondHalfAction?
    ) -> ExchangeMessageDraft.Kind {
        switch action {
        case .askClarification,
             .answerClarification,
             .autoRespond:
            return .inquiry

        case .proposeTerms,
             .reviseTerms:
            return .negotiation

        case .decline,
             .complete:
            return .closure

        case .recommendNextMove,
             .frameDecision,
             .compareOptions:
            return .other

        case .qualifyMatch,
             .requestUserInput,
             .escalateForApproval,
             .accept,
             .pause,
             .markBlocked,
             .markStalled,
             .none:
            return .other
        }
    }

    func approvalKind(
        for display: ExchangeSecondHalfUIAdapter.DisplayModel,
        draft: ExchangeMessageDraft?
    ) -> ExchangeApproval.Kind {
        if draft?.kind == .negotiation {
            return .negotiationStep
        }

        if display.boundary.kind.localizedCaseInsensitiveContains("disclosure") {
            return .discloseMoreContext
        }

        return .outboundSend
    }

    func requestedApprovalAction(
        for display: ExchangeSecondHalfUIAdapter.DisplayModel,
        draft: ExchangeMessageDraft?
    ) -> ExchangeApproval.RequestedAction {
        if draft?.kind == .negotiation {
            return .negotiate(
                summary: firstNonBlank(
                    draft?.strategyNote,
                    display.nextMove?.rationale,
                    "Approve the negotiation move."
                ) ?? "Approve the negotiation move."
            )
        }

        if display.boundary.kind.localizedCaseInsensitiveContains("disclosure") {
            return .discloseContext(fields: ["response details"])
        }

        return .sendMessage
    }

    func approvalSummary(
        for display: ExchangeSecondHalfUIAdapter.DisplayModel,
        draft: ExchangeMessageDraft?
    ) -> String {
        if let preview = draft?.previewText.nilIfBlank {
            return "Approve this second-half draft: \(preview)"
        }

        return firstNonBlank(
            display.escalationReason,
            display.boundary.reason,
            display.recommendation,
            "Approve the second-half recommended move."
        ) ?? "Approve the second-half recommended move."
    }

    func reasonFor(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        command: Command,
        actionRaw: String,
        draft: ExchangeMessageDraft?,
        approval: ExchangeApproval?
    ) -> String {
        switch command {
        case .noChange:
            return "No second-half command update was needed."

        case .updateThreadOnly:
            return "Second-half evaluated the thread and recorded the next action: \(actionRaw)."

        case .preparedLocalDraft:
            if draft != nil {
                return "Second-half prepared a local draft for \(actionRaw). Nothing was sent."
            }
            return "Second-half wanted a local draft for \(actionRaw), but no usable draft body was available."

        case .preparedLocalDraftAwaitingApproval:
            if draft != nil && approval != nil {
                return "Second-half prepared a local draft and pending approval. Nothing was sent."
            }
            if approval != nil {
                return "Second-half created a pending approval. Nothing was sent."
            }
            return "Second-half identified an approval boundary. Nothing was sent."

        case .needsUserInput:
            return firstNonBlank(
                display.nextMove?.rationale,
                "Second-half determined that user input is needed before the thread should move further."
            ) ?? "Second-half determined that user input is needed before the thread should move further."

        case .needsApproval:
            return firstNonBlank(
                display.boundary.reason,
                display.escalationReason,
                "Second-half determined that approval is needed before any commitment-bearing move."
            ) ?? "Second-half determined that approval is needed before any commitment-bearing move."

        case .decisionReady:
            return firstNonBlank(
                display.decision?.summary,
                display.recommendation,
                "Second-half determined that this thread is ready to be framed for decision."
            ) ?? "Second-half determined that this thread is ready to be framed for decision."

        case .stalled:
            return "Second-half determined that the thread should pause or be treated as stalled."

        case .blocked:
            return firstNonBlank(
                display.boundary.reason,
                "Second-half determined that the thread is blocked."
            ) ?? "Second-half determined that the thread is blocked."
        }
    }

    func commandRequiresApprovalState(_ command: Command) -> Bool {
        switch command {
        case .preparedLocalDraftAwaitingApproval, .needsApproval:
            return true
        case .noChange,
             .updateThreadOnly,
             .preparedLocalDraft,
             .needsUserInput,
             .decisionReady,
             .stalled,
             .blocked:
            return false
        }
    }

    func displayDraftHasSendableBody(_ draft: ExchangeSecondHalfUIAdapter.DraftSection?) -> Bool {
        guard let draft else { return false }
        let text = (draft.outboundBodyFull ?? draft.bodyPreview)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty
    }

    func hasApprovalEligibleOutboundArtifact(display: ExchangeSecondHalfUIAdapter.DisplayModel) -> Bool {
        if displayDraftHasSendableBody(display.draft) { return true }
        if display.hasDecisionPacket { return true }
        return false
    }

    func providerNeedsManualInputState(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        action: ExchangeSecondHalfAction?,
        actionRaw: String
    ) -> Bool {
        if action == .requestUserInput { return true }
        if display.nextMove?.needsUserInput == true { return true }
        if display.nextMove?.actionRaw == ExchangeSecondHalfAction.requestUserInput.rawValue { return true }

        let rawTokens = [
            actionRaw,
            display.nextMove?.actionRaw ?? "",
            display.status.state
        ]
        .joined(separator: " ")
        .lowercased()

        if rawTokens.contains("requestuserinput") { return true }
        if rawTokens.contains("askprovideruser") { return true }
        if rawTokens.contains("needsproviderinput") { return true }
        return false
    }

    func shouldPersistPendingApproval(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        command: Command,
        draft: ExchangeMessageDraft?
    ) -> Bool {
        let hasDraftArtifact = draft?.isActionable == true
        let hasDecisionArtifact = command == .needsApproval && display.hasDecisionPacket
        return hasDraftArtifact || hasDecisionArtifact
    }

    func firstNonBlank(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
