import Foundation
import AnumCore

/// Shared approve / queue path for secretary outbound drafts (approval sheet + ThreadView inline button).
enum SecretaryOutboundApproveSend {
    /// Mirrors ``SecretaryWorkspaceView.approveFromDisplay`` queue semantics without duplicating eligibility logic.
    @MainActor
    static func perform(
        display: SecretaryApprovalPanelDisplay,
        exchangeFacade: ExchangeFacade,
        permit: ExchangeFacade.OutboundQueuePermit = .userApproved(source: "SecretaryOutboundApproveSend")
    ) async throws -> Bool {
        guard let threadID = display.threadID else {
            #if DEBUG
            reviewApproveEligibilityLog(
                display: display,
                threadID: nil,
                resolvedApprovalID: nil,
                action: "abort",
                result: "false",
                reason: "missingThreadID"
            )
            #endif
            return false
        }

        let approvalID: ExchangeApproval.ID?
        if let existing = display.approvalID {
            approvalID = existing
        } else {
            let detail = try await exchangeFacade.getThread(threadID: threadID)
            approvalID = SecretaryProjectionEngine.latestPendingApproval(for: detail)?.id
        }

        if let approvalID {
            _ = try await exchangeFacade.approveAndQueue(
                threadID: threadID,
                approvalID: approvalID,
                permit: permit
            )
            #if DEBUG
            reviewApproveEligibilityLog(
                display: display,
                threadID: threadID,
                resolvedApprovalID: approvalID,
                action: "approveAndQueue",
                result: "true",
                reason: "queue_attempt_completed"
            )
            #endif
            return true
        }

        if display.prefersSecondHalfPreparedSend {
            let outcome = try await exchangeFacade.queuePreparedSecondHalfOutboundSend(
                threadID: threadID,
                draftID: nil,
                userInitiatedOverride: display.requiresHumanApproval,
                now: Date()
            )
            let ok = outcome == .queued
            #if DEBUG
            reviewApproveEligibilityLog(
                display: display,
                threadID: threadID,
                resolvedApprovalID: nil,
                action: "queuePreparedSecondHalfOutboundSend",
                result: ok ? "true" : "false",
                reason: ok ? "queued" : "preparedSendNotQueued outcome=\(String(describing: outcome))"
            )
            #endif
            return ok
        }

        #if DEBUG
        do {
            let detail = try await exchangeFacade.getThread(threadID: threadID)
            let pick = SecretaryProjectionEngine.latestPersistedActionableExternalOutboundDraft(for: detail)
            reviewApproveEligibilityLog(
                display: display,
                threadID: threadID,
                resolvedApprovalID: nil,
                action: "noop",
                result: "false",
                reason: "noApprovalAndNoPreparedSend actionableDraft=\(pick != nil) draftID=\(pick?.id.uuidString ?? "nil")"
            )
        } catch {
            reviewApproveEligibilityLog(
                display: display,
                threadID: threadID,
                resolvedApprovalID: nil,
                action: "noop",
                result: "false",
                reason: "inspect_detail_failed error=\(error.localizedDescription)"
            )
        }
        #endif

        return false
    }

    #if DEBUG
    private static func reviewApproveEligibilityLog(
        display: SecretaryApprovalPanelDisplay,
        threadID: ExchangeThread.ID?,
        resolvedApprovalID: ExchangeApproval.ID?,
        action: String,
        result: String,
        reason: String
    ) {
        let tid = threadID?.uuidString ?? "nil"
        let aid = resolvedApprovalID?.uuidString ?? "nil"
        let displayAid = display.approvalID?.uuidString ?? "nil"
        let hasDraftBody = display.draftBody != nil
        Swift.print(
            "[ReviewApproveTrace] action=\(action) result=\(result) reason=\(reason) " +
                "thread=\(tid) resolvedApproval=\(aid) displayApprovalID=\(displayAid) " +
                "prefersPreparedSend=\(display.prefersSecondHalfPreparedSend) requiresHumanApproval=\(display.requiresHumanApproval) " +
                "canRunPrimary=\(display.canRunPrimaryAction) primaryTitle=\(display.primaryTitle) resolvedTitle=\(display.resolvedPrimaryActionTitle) " +
                "hasDraftBody=\(hasDraftBody)"
        )
    }
    #endif
}
