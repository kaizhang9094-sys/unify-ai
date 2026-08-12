import Foundation

#if DEBUG
/// Compact, grep-friendly DEBUG traces for autonomous requester send ↔ provider auto-reply E2E verification.
/// Logs IDs, roles, lengths, and reasons only — never full message bodies.
public enum ExchangeBilateralConversationDebugTrace {
    private static let flushPassIDLock = NSLock()
    nonisolated(unsafe) private static var storedFlushPassID: String?

    public static var activeFlushPassID: String? {
        get {
            flushPassIDLock.lock()
            defer { flushPassIDLock.unlock() }
            return storedFlushPassID
        }
        set {
            flushPassIDLock.lock()
            defer { flushPassIDLock.unlock() }
            storedFlushPassID = newValue
        }
    }

    private static func opt(_ value: UUID?) -> String { value?.uuidString ?? "nil" }
    private static func opt(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "nil" : trimmed
    }

    private static func log(_ tag: String, _ fields: [String: String]) {
        let body = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\( $0.value)" }
            .joined(separator: " ")
        Swift.print("[\(tag)] \(body)")
    }

    public static func logAutoSendQuery(
        thread: ExchangeThread,
        draftID: UUID?,
        outboxID: UUID? = nil,
        envelopeID: String? = nil,
        allowed: Bool,
        blockReason: String? = nil,
        autonomyAuthority: ExchangeAutonomousUserAuthority
    ) {
        log("AutoSendQuery", [
            "threadID": thread.id.uuidString,
            "threadRole": thread.threadRole.rawValue,
            "parentThreadID": opt(thread.parentThreadID),
            "rootThreadID": opt(thread.rootThreadID),
            "draftID": opt(draftID),
            "outboxID": opt(outboxID),
            "envelopeID": opt(envelopeID),
            "allowed": allowed ? "true" : "false",
            "blockReason": opt(blockReason),
            "autonomyAuthority": autonomyAuthority.rawValue,
            "selectedOfferID": opt(thread.selectedOfferID),
            "selectedPublicProfileID": opt(thread.selectedPublicProfileID),
            "sourceMatchID": opt(thread.sourceMatchID)
        ])
    }

    public static func logFederationSend(
        envelopeID: String,
        outboxID: UUID?,
        sourceThreadID: UUID,
        routeKey: String,
        targetNodeID: String,
        parentEnvelopeID: String?,
        conversationID: String?,
        rootEnvelopeID: String?,
        originalRequesterEnvelopeID: String?,
        conversationSurface: String?,
        sendResult: String?,
        error: String? = nil
    ) {
        var fields: [String: String] = [
            "envelopeID": opt(envelopeID),
            "outboxID": opt(outboxID),
            "sourceThreadID": sourceThreadID.uuidString,
            "routeKey": opt(routeKey),
            "targetNodeID": opt(targetNodeID),
            "parentEnvelopeID": opt(parentEnvelopeID),
            "conversationID": opt(conversationID),
            "rootEnvelopeID": opt(rootEnvelopeID),
            "originalRequesterEnvelopeID": opt(originalRequesterEnvelopeID),
            "conversationSurface": opt(conversationSurface)
        ]
        if let error, !error.isEmpty {
            fields["sendResult"] = "error"
            fields["error"] = error
        } else {
            fields["sendResult"] = opt(sendResult)
        }
        log("FederationSend", fields)
    }

    public static func logInboxReceive(
        item: ExchangeInboxItem,
        resolvedThread: ExchangeThread?,
        createdThreadID: UUID?,
        existingThreadID: UUID?,
        matchReason: String,
        deferredReason: String? = nil,
        destinationNodeID: String? = nil
    ) {
        let tag = inboxReceiveTag(for: resolvedThread)
        var fields: [String: String] = [
            "envelopeID": opt(item.envelopeID),
            "sourceNodeID": opt(item.senderNodeID),
            "destinationNodeID": opt(destinationNodeID ?? item.metadata["recipient_node_id"]),
            "parentEnvelopeID": opt(item.ordering.parentEnvelopeID ?? item.metadata["parent_envelope_id"]),
            "conversationID": opt(item.metadata["conversation_id"]),
            "conversationSurface": opt(item.metadata["conversation_surface"]),
            "resolvedThreadID": opt(resolvedThread?.id),
            "createdThreadID": opt(createdThreadID),
            "existingThreadID": opt(existingThreadID),
            "matchReason": matchReason
        ]
        if tag == "QueryInboxReceive" {
            fields["sourceThreadIDFromEnvelope"] = opt(item.metadata["source_thread_id"])
            fields["matchedThreadID"] = opt(resolvedThread?.id ?? existingThreadID ?? createdThreadID)
            fields["matchedThreadRole"] = resolvedThread?.threadRole.rawValue ?? "nil"
            if let deferredReason { fields["suppressedReason"] = deferredReason }
        } else if let deferredReason {
            fields["deferredReason"] = deferredReason
        }
        log(tag, fields)
    }

    public static func logInboundTurnPersisted(
        thread: ExchangeThread,
        envelopeID: String,
        turnID: UUID?,
        turnKind: String?,
        bodyLength: Int?,
        suppressedReason: String?
    ) {
        log("InboundTurnPersisted", [
            "threadID": thread.id.uuidString,
            "threadRole": thread.threadRole.rawValue,
            "envelopeID": opt(envelopeID),
            "turnID": opt(turnID),
            "turnKind": opt(turnKind),
            "bodyLength": bodyLength.map(String.init) ?? "nil",
            "suppressedReason": opt(suppressedReason),
            "source": "federation_reconcile_inbound"
        ])
    }

    public static func logProviderAutoReplyDecision(
        thread: ExchangeThread,
        inboundEnvelopeID: String?,
        inboundTurnID: String?,
        allowed: Bool,
        reason: String,
        intakeAction: String,
        draftID: UUID? = nil,
        outboxID: UUID? = nil,
        autonomyAuthority: ExchangeAutonomousUserAuthority,
        commitmentBoundaryHit: Bool,
        requiresHumanApproval: Bool
    ) {
        log("ProviderAutoReplyDecision", [
            "threadID": thread.id.uuidString,
            "threadRole": thread.threadRole.rawValue,
            "inboundEnvelopeID": opt(inboundEnvelopeID),
            "inboundTurnID": opt(inboundTurnID),
            "allowed": allowed ? "true" : "false",
            "reason": reason,
            "intakeAction": intakeAction,
            "draftID": opt(draftID),
            "outboxID": opt(outboxID),
            "autonomyAuthority": autonomyAuthority.rawValue,
            "commitmentBoundaryHit": commitmentBoundaryHit ? "true" : "false",
            "requiresHumanApproval": requiresHumanApproval ? "true" : "false"
        ])
    }

    public static func logProviderAutoReplySend(
        threadID: UUID,
        draftID: UUID?,
        outboxID: UUID?,
        envelopeID: String?,
        parentEnvelopeID: String?,
        conversationID: String?,
        routeKey: String?,
        queued: Bool,
        flushedInline: Bool,
        flushPassID: String? = nil
    ) {
        var fields: [String: String] = [
            "threadID": threadID.uuidString,
            "draftID": opt(draftID),
            "outboxID": opt(outboxID),
            "envelopeID": opt(envelopeID),
            "parentEnvelopeID": opt(parentEnvelopeID),
            "conversationID": opt(conversationID),
            "routeKey": opt(routeKey),
            "queued": queued ? "true" : "false",
            "flushedInline": flushedInline ? "true" : "false"
        ]
        if let flushPassID { fields["flushPassID"] = flushPassID }
        log("ProviderAutoReplySend", fields)
    }

    public static func logConversationCardLoad(
        detail: ExchangeModels.ThreadDetail,
        secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel?,
        rows: [ExchangeModels.ThreadTranscriptEntry]
    ) {
        let thread = detail.thread
        let replyReceivedTurns = detail.turns.filter { $0.kind == .replyReceived && $0.actor == .counterparty }
        let includedDraftIDs = rows.compactMap { row -> String? in
            if row.id.hasPrefix("draft-sent-") { return String(row.id.dropFirst("draft-sent-".count)) }
            if row.id.hasPrefix("draft-open-") { return String(row.id.dropFirst("draft-open-".count)) }
            if row.id.hasPrefix("draft-sending-") { return String(row.id.dropFirst("draft-sending-".count)) }
            if row.id.hasPrefix("draft-send-failed-") { return String(row.id.dropFirst("draft-send-failed-".count)) }
            return nil
        }
        let includedTurnIDs = rows.compactMap { row -> String? in
            guard row.id.hasPrefix("turn-reply-") else { return nil }
            return String(row.id.dropFirst("turn-reply-".count))
        }
        let includedTurnIDSet = Set(includedTurnIDs)
        let excludedTurnKinds = detail.turns
            .filter { !includedTurnIDSet.contains($0.id.uuidString) }
            .map(\.kind.rawValue)
        let uniqueExcluded = Array(Set(excludedTurnKinds)).sorted().joined(separator: ",")
        let latestRowSource: String = {
            guard let first = rows.first else { return "none" }
            if first.id.hasPrefix("turn-reply-") { return "replyReceivedTurn" }
            if first.id.hasPrefix("draft-") { return "draft" }
            if first.id.hasPrefix("inbox-fallback-") { return "inboxFallback" }
            return first.id
        }()

        log("ConversationCardLoad", [
            "threadID": thread.id.uuidString,
            "threadRole": thread.threadRole.rawValue,
            "draftCount": String(detail.drafts.count),
            "outboxCount": String(detail.outboxItems.count),
            "replyReceivedTurnCount": String(replyReceivedTurns.count),
            "transcriptRowCount": String(rows.count),
            "includedDraftIDs": includedDraftIDs.isEmpty ? "none" : includedDraftIDs.joined(separator: ","),
            "includedTurnIDs": includedTurnIDs.isEmpty ? "none" : includedTurnIDs.joined(separator: ","),
            "excludedTurnKinds": uniqueExcluded.isEmpty ? "none" : uniqueExcluded,
            "hasSecondHalfDisplay": secondHalfDisplay != nil ? "true" : "false",
            "latestRowSource": latestRowSource
        ])
    }

    private static func inboxReceiveTag(for thread: ExchangeThread?) -> String {
        guard let thread else { return "ProviderInboxReceive" }
        if thread.threadRole == .candidateCoordination { return "QueryInboxReceive" }
        if thread.metadata["inbound_thread"] == "true" { return "ProviderInboxReceive" }
        if thread.threadRole == .standalone || thread.threadRole == .umbrellaSearch {
            return "QueryInboxReceive"
        }
        return "ProviderInboxReceive"
    }
}
#endif
