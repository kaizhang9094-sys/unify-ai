import Foundation

/// Quarantines **exchange outbox** rows that belong to the pre-``DirectMessageSendService`` manual DM path
/// on `direct_message_thread` containers, so `flushOutbox` does not call `grantApproval` / relay retry.
public enum DirectMessageLegacyExchangeOutbox: Sendable {
    /// Whether this outbox row should be terminally cleared instead of going through ``sendOutboxItem``.
    public static func shouldQuarantineExchangeOutboxForDmRelayOwnedSend(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft?,
        item: ExchangeOutboxItem
    ) -> Bool {
        guard isDirectMessageThread(thread) else { return false }

        if let draft, isTruthy(draft.metadata["dm_manual_v2"]) {
            return true
        }
        if isTruthy(item.metadata["dm_manual_v2"]) {
            return true
        }

        if let draft, isTruthy(draft.metadata["trusted_node_manual_message"]) {
            return true
        }
        if isTruthy(item.metadata["trusted_node_manual_message"]) {
            return true
        }

        let payloadDraft = draft?.metadata["payload_kind"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let payloadOutbox = item.metadata["payload_kind"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if payloadDraft.contains("direct_message") || payloadOutbox.contains("direct_message") {
            return true
        }

        let surfDraft = draft?.metadata["conversation_surface"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let surfOutbox = item.metadata["conversation_surface"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if surfDraft == "direct_message" || surfOutbox == "direct_message" {
            return true
        }

        return false
    }

    /// After a successful DirectMessageSendV2 relay send, clears any leftover exchange-queue rows for this thread.
    public static func quarantineStaleItemsAfterDirectMessageSendV2Succeeded(
        store: any ExchangeStore,
        threadID: ExchangeThread.ID,
        now: Date
    ) async throws {
        let thread = try await store.requireThread(id: threadID)
        let items = try await store.listOutboxItems(
            filter: ExchangeOutboxFilter(threadID: threadID, activeOnly: true, limit: 64)
        )
        for item in items {
            let draft = try await store.fetchDraft(id: item.draftID)
            guard shouldQuarantineExchangeOutboxForDmRelayOwnedSend(thread: thread, draft: draft, item: item) else {
                continue
            }
            let failed = item.failingTerminally(
                errorCode: "dm_manual_v2_superseded",
                note: "Superseded by DirectMessageSendV2 relay-direct send; exchange outbox must not retry.",
                externalEffect: .none,
                at: now
            )
            let audit = ExchangeAuditRecord.failed(
                direction: .outbound,
                threadID: item.threadID,
                envelopeID: item.envelopeID,
                outboxItemID: item.id,
                summary: "Direct-message relay-direct send superseded exchange outbox work.",
                detail: "This row belonged to the legacy manual-DM exchange queue path and was quarantined after a successful DirectMessageSendV2 relay send.",
                externalEffect: .none,
                relatedNodeID: item.targetNodeID,
                relatedDisplayName: nil,
                createdAt: now
            )
            try await store.performTransaction {
                try await store.saveOutboxItem(failed)
                try await store.appendAuditRecord(audit)
            }
            #if DEBUG
            Swift.print(
                "[DMOutboxCleanup][superseded] threadID=\(threadID.uuidString) outboxID=\(item.id.uuidString)"
            )
            #endif
        }
    }

    private static func isDirectMessageThread(_ thread: ExchangeThread) -> Bool {
        thread.metadata["direct_message_thread"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "true"
    }

    private static func isTruthy(_ raw: String?) -> Bool {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }
}
