import Foundation

// MARK: - Models

public struct DirectMessageTranscriptBubble: Identifiable, Sendable, Equatable {
    public let id: String
    public let body: String
    public let attachments: [DirectMessageAttachmentDescriptor]
    public let timestamp: Date
    public let isOutgoing: Bool
    public let source: String

    public init(
        id: String,
        body: String,
        attachments: [DirectMessageAttachmentDescriptor],
        timestamp: Date,
        isOutgoing: Bool,
        source: String
    ) {
        self.id = id
        self.body = body
        self.attachments = attachments
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
        self.source = source
    }
}

public struct DirectMessageTranscriptRenderResult: Sendable, Equatable {
    public let rows: [DirectMessageTranscriptBubble]
    public let localCount: Int
    public let remoteCount: Int
    public let skippedSystemRows: Int
    public let skippedAgencyRows: Int
    public let skippedContactRequestRows: Int
    public let usedInboxFallbackCount: Int
    public let dedupedRows: Int

    public init(
        rows: [DirectMessageTranscriptBubble],
        localCount: Int,
        remoteCount: Int,
        skippedSystemRows: Int,
        skippedAgencyRows: Int,
        skippedContactRequestRows: Int,
        usedInboxFallbackCount: Int,
        dedupedRows: Int
    ) {
        self.rows = rows
        self.localCount = localCount
        self.remoteCount = remoteCount
        self.skippedSystemRows = skippedSystemRows
        self.skippedAgencyRows = skippedAgencyRows
        self.skippedContactRequestRows = skippedContactRequestRows
        self.usedInboxFallbackCount = usedInboxFallbackCount
        self.dedupedRows = dedupedRows
    }
}

public struct DirectMessageInboundPreviewResolution: Sendable, Equatable {
    public let rowID: String
    public let linkedThreadID: ExchangeThread.ID?
    public let canonicalDMThreadID: ExchangeThread.ID?
    public let chosenThreadID: ExchangeThread.ID?
    public let reason: String

    public init(
        rowID: String,
        linkedThreadID: ExchangeThread.ID?,
        canonicalDMThreadID: ExchangeThread.ID?,
        chosenThreadID: ExchangeThread.ID?,
        reason: String
    ) {
        self.rowID = rowID
        self.linkedThreadID = linkedThreadID
        self.canonicalDMThreadID = canonicalDMThreadID
        self.chosenThreadID = chosenThreadID
        self.reason = reason
    }
}

// MARK: - Projection

/// Shared direct-message transcript rendering for DM screen and Inbound conversation previews.
public enum DirectMessageTranscriptProjection: Sendable {

    /// Inbound / Chats row subtitle when the visible DM transcript is empty (including after clear watermark).
    public static let inboundEmptyPreviewLabel = "No messages yet."

    public enum InboundPreviewSource: String, Sendable {
        case canonicalDM
        case emptyAfterClear
        case noDMThread
        case rawInboxFallback
    }

    /// Maps canonical DM preview text to the user-facing Inbound subtitle and preview source.
    public static func inboundLatestPreviewDisplay(
        fromCanonicalPreview raw: String?
    ) -> (text: String, source: InboundPreviewSource) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed != inboundEmptyPreviewLabel else {
            return (inboundEmptyPreviewLabel, .emptyAfterClear)
        }
        if isGenericInboundPlaceholderBody(trimmed) {
            return ("Attachment", .canonicalDM)
        }
        return (String(trimmed.prefix(240)), .canonicalDM)
    }

    /// System fallback copy used when inbound reconcile has no decrypted body/subject/summary.
    public static func isGenericInboundPlaceholderBody(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let withoutPeriod = normalized.hasSuffix(".")
            ? String(normalized.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            : normalized
        return withoutPeriod == "inbound message received"
    }

    // MARK: - Clear watermark (UserDefaults)

    public static func clearWatermarkKey(for counterpartyNodeID: String) -> String {
        let normalized = counterpartyNodeID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "secretary.directMessage.clearWatermark.\(normalized)"
    }

    public static func clearedAt(for counterpartyNodeID: String) -> Date? {
        let key = clearWatermarkKey(for: counterpartyNodeID)
        let seconds = UserDefaults.standard.double(forKey: key)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public static func setClearWatermark(at date: Date, for counterpartyNodeID: String) {
        let key = clearWatermarkKey(for: counterpartyNodeID)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        #if DEBUG
        print("[DirectMessageClearTranscript] nodeID=\(counterpartyNodeID) clearedAt=\(date)")
        #endif
    }

    public static func rowsAfterClearWatermark(
        _ rows: [DirectMessageTranscriptBubble],
        counterpartyNodeID: String
    ) -> [DirectMessageTranscriptBubble] {
        guard let clearedAt = clearedAt(for: counterpartyNodeID) else {
            return rows
        }

        let filtered = rows.filter { $0.timestamp > clearedAt }

        #if DEBUG
        print(
            "[InboundPreviewDMClearApplied] nodeID=\(counterpartyNodeID) clearedAt=\(clearedAt) " +
            "before=\(rows.count) after=\(filtered.count)"
        )
        #endif

        return filtered
    }

    // MARK: - Transcript build

    public static func buildTranscriptRows(
        detail: ExchangeModels.ThreadDetail,
        counterpartyNodeID: String
    ) -> DirectMessageTranscriptRenderResult {
        var rows: [DirectMessageTranscriptBubble] = []
        var localCount = 0
        var remoteCount = 0
        var skippedSystemRows = 0
        var skippedAgencyRows = 0
        var skippedContactRequestRows = 0
        var usedInboxFallbackCount = 0
        var emittedInboundEnvelopeIDs = Set<String>()
        var emittedInboundInboxIDs = Set<String>()
        let restrictToDirectChatSurface = usesFriendStyleDirectTranscript(detail: detail)
        let owningThreadID = detail.thread.id

        for draft in detail.drafts.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            guard isManualDirectDraft(draft) else { continue }

            if restrictToDirectChatSurface, isDiscoveryOrAgencyOutboundDraft(draft) {
                continue
            }

            if isContactRequestMetadata(draft.metadata) {
                skippedContactRequestRows += 1
                continue
            }

            let attachments = DirectMessageAttachmentMetadata.descriptors(from: draft.metadata)
            let body = sanitizedMessageBody(draft.body)
            guard !body.isEmpty || !attachments.isEmpty else { continue }

            rows.append(
                DirectMessageTranscriptBubble(
                    id: "draft-\(draft.id.uuidString)",
                    body: body,
                    attachments: attachments,
                    timestamp: draft.updatedAt,
                    isOutgoing: true,
                    source: "draft"
                )
            )
            localCount += 1
        }

        for turn in detail.turns.sorted(by: { $0.createdAt < $1.createdAt }) {
            if isContactRequestMetadata(turn.metadata) {
                skippedContactRequestRows += 1
                continue
            }

            if turn.kind == .replyReceived, turn.actor == .counterparty {
                if restrictToDirectChatSurface, isExchangeThreadLaneMetadata(turn.metadata) {
                    skippedSystemRows += 1
                    continue
                }

                let turnDetail = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let attachments = DirectMessageAttachmentMetadata.descriptors(from: turn.metadata)
                let bubbleID = stableInboundBubbleID(turn: turn)
                let body = transcriptInboundDisplayBody(
                    rawBody: turnDetail.isEmpty ? turn.summary : turnDetail,
                    attachments: attachments,
                    messageID: bubbleID
                )
                guard !body.isEmpty || !attachments.isEmpty else { continue }

                rows.append(
                    DirectMessageTranscriptBubble(
                        id: bubbleID,
                        body: body,
                        attachments: attachments,
                        timestamp: turn.createdAt,
                        isOutgoing: false,
                        source: "turn_reply"
                    )
                )

                if let env = normalizedInboundSourceID(turn.metadata["source_envelope_id"]) {
                    emittedInboundEnvelopeIDs.insert(env)
                }
                if let inbox = normalizedInboundSourceID(turn.metadata["source_inbox_item_id"]) {
                    emittedInboundInboxIDs.insert(inbox)
                }
                if let ext = normalizedInboundSourceID(turn.externalReference) {
                    emittedInboundEnvelopeIDs.insert(ext)
                }

                remoteCount += 1
                continue
            }

            if turn.actor == .user, isManualDirectTurn(turn) {
                if restrictToDirectChatSurface, isDiscoveryOrAgencyUserTurn(turn) {
                    skippedAgencyRows += 1
                    continue
                }

                let turnDetail = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let attachments = DirectMessageAttachmentMetadata.descriptors(from: turn.metadata)
                let body = sanitizedMessageBody(turnDetail.isEmpty ? turn.summary : turnDetail)
                guard !body.isEmpty || !attachments.isEmpty else { continue }

                rows.append(
                    DirectMessageTranscriptBubble(
                        id: "turn-local-\(turn.id.uuidString)",
                        body: body,
                        attachments: attachments,
                        timestamp: turn.createdAt,
                        isOutgoing: true,
                        source: "turn_local"
                    )
                )
                localCount += 1
                continue
            }

            if turn.actor == .secretary || turn.actor == .system {
                skippedAgencyRows += 1
            } else {
                skippedSystemRows += 1
            }
        }

        for item in detail.inboxItems.sorted(by: { $0.receivedAt < $1.receivedAt }) {
            guard item.processingState != .archived else { continue }

            if restrictToDirectChatSurface,
               !inboxItemBelongsOnThisTranscriptThread(item, owningThreadID: owningThreadID) {
                skippedSystemRows += 1
                continue
            }

            if restrictToDirectChatSurface, isExchangeThreadInboxItem(item) {
                skippedSystemRows += 1
                continue
            }

            if isContactRequestMetadata(item.metadata) {
                skippedContactRequestRows += 1
                continue
            }

            let inboxID = normalizedInboundSourceID(item.id.uuidString)
            let envelopeID = normalizedInboundSourceID(item.envelopeID)

            if let envelopeID, emittedInboundEnvelopeIDs.contains(envelopeID) { continue }
            if let inboxID, emittedInboundInboxIDs.contains(inboxID) { continue }

            let attachments = DirectMessageAttachmentMetadata.descriptors(from: item.metadata)
            let bubbleID = stableInboxFallbackBubbleID(item)
            let preview = transcriptInboundDisplayBody(
                rawBody: inboxBodyPreview(item),
                attachments: attachments,
                messageID: bubbleID
            )
            guard !preview.isEmpty || !attachments.isEmpty else { continue }

            rows.append(
                DirectMessageTranscriptBubble(
                    id: bubbleID,
                    body: preview,
                    attachments: attachments,
                    timestamp: item.receivedAt,
                    isOutgoing: false,
                    source: "inbox_fallback"
                )
            )
            usedInboxFallbackCount += 1
            remoteCount += 1
        }

        rows.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id < $1.id
        }

        let beforeDedup = rows.count
        rows = dedupedRows(rows)
        let deduped = max(0, beforeDedup - rows.count)

        return DirectMessageTranscriptRenderResult(
            rows: rows,
            localCount: localCount,
            remoteCount: remoteCount,
            skippedSystemRows: skippedSystemRows,
            skippedAgencyRows: skippedAgencyRows,
            skippedContactRequestRows: skippedContactRequestRows,
            usedInboxFallbackCount: usedInboxFallbackCount,
            dedupedRows: deduped
        )
    }

    public static func latestVisiblePreview(
        from rows: [DirectMessageTranscriptBubble],
        counterpartyNodeID: String,
        emptyLabel: String = ""
    ) -> String {
        let visible = rowsAfterClearWatermark(rows, counterpartyNodeID: counterpartyNodeID)
        guard let last = visible.last else { return emptyLabel }

        let body = last.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty, !( !last.attachments.isEmpty && isGenericInboundPlaceholderBody(body) ) {
            return String(body.prefix(240))
        }
        if !last.attachments.isEmpty {
            return "Attachment"
        }
        return emptyLabel
    }

    public static func shouldMergeUnfiledInboundForTranscript(detail: ExchangeModels.ThreadDetail) -> Bool {
        let isDM = detail.thread.metadata["direct_message_thread"] == "true"
        let isInboundThread = detail.thread.metadata["inbound_thread"] == "true"
        return isDM || isInboundThread
    }

    public static func detailMergingUnfiledSenderInbox(
        _ detail: ExchangeModels.ThreadDetail,
        counterpartyNodeID: String,
        facade: ExchangeFacade
    ) async -> ExchangeModels.ThreadDetail {
        let trimmed = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return detail }

        let supplemental: [ExchangeInboxItem]
        do {
            supplemental = try await facade.listInboxItems(
                filter: ExchangeInboxFilter(senderNodeID: trimmed, limit: 150)
            )
        } catch {
            return detail
        }

        let existingIDs = Set(detail.inboxItems.map(\.id))
        let extras = supplemental.filter { item in
            guard !existingIDs.contains(item.id) else { return false }
            guard item.threadID == nil else { return false }
            if isExchangeThreadInboxItem(item) {
                #if DEBUG
                logSkippedExchangeThreadInboxForDirectMessageTranscript(
                    item: item,
                    counterpartyNodeID: trimmed
                )
                #endif
                return false
            }
            if isDirectMessageInboxItem(item) {
                return true
            }
            // Legacy unfiled DM rows may lack conversation_surface; keep only when not exchange/inquiry.
            return true
        }

        guard !extras.isEmpty else { return detail }

        var copy = detail
        copy.inboxItems = (detail.inboxItems + extras).sorted {
            if $0.receivedAt != $1.receivedAt { return $0.receivedAt < $1.receivedAt }
            return $0.id.uuidString < $1.id.uuidString
        }

        #if DEBUG
        print(
            "[DirectMessageTranscriptMerge] threadID=\(detail.thread.id.uuidString) counterparty=\(trimmed) " +
            "threadScopedInbox=\(detail.inboxItems.count) supplemental=\(supplemental.count) " +
            "mergedExtras=\(extras.count) mergedTotal=\(copy.inboxItems.count)"
        )
        #endif

        return copy
    }

    // MARK: - Inbound preview

    public static func resolveInboundPreviewThreadID(
        rowID: String,
        counterpartyNodeID: String,
        linkedThreadID: ExchangeThread.ID?,
        facade: ExchangeFacade
    ) async -> DirectMessageInboundPreviewResolution {
        let trimmedNode = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = (try? await facade.resolveExistingDirectMessageThreadIDIfPresent(
            counterpartyNodeID: trimmedNode
        ))

        guard !trimmedNode.isEmpty else {
            return DirectMessageInboundPreviewResolution(
                rowID: rowID,
                linkedThreadID: linkedThreadID,
                canonicalDMThreadID: canonical,
                chosenThreadID: linkedThreadID,
                reason: "noCounterpartyNode"
            )
        }

        if let canonical {
            if let linked = linkedThreadID, linked != canonical {
                if let linkedThread = try? await facade.loadThreadRow(threadID: linked),
                   linkedThread.metadata["direct_message_thread"] != "true" {
                    #if DEBUG
                    print(
                        "[InboundPreviewMismatchGuard] reason=staleLinkedThreadIgnored " +
                        "rowID=\(rowID) linked=\(linked.uuidString) canonical=\(canonical.uuidString)"
                    )
                    #endif
                    return DirectMessageInboundPreviewResolution(
                        rowID: rowID,
                        linkedThreadID: linked,
                        canonicalDMThreadID: canonical,
                        chosenThreadID: canonical,
                        reason: "canonicalDMPreferredOverLinkedExchange"
                    )
                }
            }
            return DirectMessageInboundPreviewResolution(
                rowID: rowID,
                linkedThreadID: linkedThreadID,
                canonicalDMThreadID: canonical,
                chosenThreadID: canonical,
                reason: "canonicalDMThread"
            )
        }

        if let linked = linkedThreadID,
           let linkedThread = try? await facade.loadThreadRow(threadID: linked),
           linkedThread.metadata["direct_message_thread"] == "true" {
            return DirectMessageInboundPreviewResolution(
                rowID: rowID,
                linkedThreadID: linked,
                canonicalDMThreadID: nil,
                chosenThreadID: linked,
                reason: "linkedDMThreadNoCanonical"
            )
        }

        if linkedThreadID != nil {
            #if DEBUG
            print(
                "[InboundPreviewMismatchGuard] reason=exchangeLinkedThreadNoCanonicalDM " +
                "rowID=\(rowID) linked=\(linkedThreadID?.uuidString ?? "nil")"
            )
            #endif
            return DirectMessageInboundPreviewResolution(
                rowID: rowID,
                linkedThreadID: linkedThreadID,
                canonicalDMThreadID: nil,
                chosenThreadID: nil,
                reason: "exchangeLinkedThreadNoCanonicalDM"
            )
        }

        return DirectMessageInboundPreviewResolution(
            rowID: rowID,
            linkedThreadID: nil,
            canonicalDMThreadID: nil,
            chosenThreadID: nil,
            reason: "noDMThread"
        )
    }

    public static func buildInboundLatestPreview(
        rowID: String,
        counterpartyNodeID: String,
        linkedThreadID: ExchangeThread.ID?,
        facade: ExchangeFacade
    ) async -> (preview: String, resolution: DirectMessageInboundPreviewResolution) {
        let resolution = await resolveInboundPreviewThreadID(
            rowID: rowID,
            counterpartyNodeID: counterpartyNodeID,
            linkedThreadID: linkedThreadID,
            facade: facade
        )

        #if DEBUG
        print(
            "[InboundPreviewDMResolution] rowID=\(rowID) " +
            "linkedThreadID=\(resolution.linkedThreadID?.uuidString ?? "nil") " +
            "canonicalDMThreadID=\(resolution.canonicalDMThreadID?.uuidString ?? "nil") " +
            "chosenThreadID=\(resolution.chosenThreadID?.uuidString ?? "nil") reason=\(resolution.reason)"
        )
        #endif

        guard let threadID = resolution.chosenThreadID else {
            #if DEBUG
            print(
                "[InboundPreviewDMProjection] threadID=nil rawRows=0 visibleRows=0 " +
                "clearWatermark=\(clearedAt(for: counterpartyNodeID) != nil) previewSource=none"
            )
            #endif
            return (inboundEmptyPreviewLabel, resolution)
        }

        do {
            var detail = try await facade.getThread(
                threadID: threadID,
                hydrationMode: .directMessage
            )
            let trimmedNode = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            if shouldMergeUnfiledInboundForTranscript(detail: detail), !trimmedNode.isEmpty {
                detail = await detailMergingUnfiledSenderInbox(
                    detail,
                    counterpartyNodeID: trimmedNode,
                    facade: facade
                )
            }

            let rendered = buildTranscriptRows(
                detail: detail,
                counterpartyNodeID: trimmedNode
            )
            let visible = rowsAfterClearWatermark(rendered.rows, counterpartyNodeID: trimmedNode)
            let preview = latestVisiblePreview(
                from: rendered.rows,
                counterpartyNodeID: trimmedNode,
                emptyLabel: inboundEmptyPreviewLabel
            )

            #if DEBUG
            let previewSource = visible.last?.source ?? "none"
            print(
                "[InboundPreviewDMProjection] threadID=\(threadID.uuidString) rawRows=\(rendered.rows.count) " +
                "visibleRows=\(visible.count) clearWatermark=\(clearedAt(for: trimmedNode) != nil) " +
                "previewSource=\(previewSource) previewChars=\(preview.count)"
            )
            #endif

            return (preview, resolution)
        } catch {
            #if DEBUG
            print(
                "[InboundPreviewDMProjection] threadID=\(threadID.uuidString) failed error=\(error.localizedDescription)"
            )
            #endif
            return (inboundEmptyPreviewLabel, resolution)
        }
    }

    /// Builds DM-aligned previews keyed by normalized counterparty node ID (includes trusted-only peers).
    public static func buildInboundPreviewByCounterpartyNodeID(
        nodeIDs: [String],
        linkedThreadIDByNodeID: [String: ExchangeThread.ID] = [:],
        facade: ExchangeFacade
    ) async -> [String: String] {
        let normalizedIDs = Set(
            nodeIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { $0.lowercased() }
        )

        var output: [String: String] = [:]

        await withTaskGroup(of: (String, String).self) { group in
            for normalized in normalizedIDs {
                group.addTask {
                    let counterparty = nodeIDs.first {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased() == normalized
                    } ?? normalized

                    let linked = linkedThreadIDByNodeID[normalized]
                        ?? linkedThreadIDByNodeID[counterparty]
                    let (preview, _) = await buildInboundLatestPreview(
                        rowID: "node:\(normalized)",
                        counterpartyNodeID: counterparty,
                        linkedThreadID: linked,
                        facade: facade
                    )
                    return (normalized, preview)
                }
            }

            for await (normalized, preview) in group {
                output[normalized] = preview
            }
        }

        return output
    }

    /// Builds DM-aligned previews keyed by inbound conversation group key (`node:…`).
    public static func buildInboundPreviewByGroupKey(
        items: [ExchangeInboxItem],
        groupKey: @escaping @Sendable (ExchangeInboxItem) -> String,
        facade: ExchangeFacade
    ) async -> [String: String] {
        let groups = Dictionary(grouping: items, by: groupKey)
        var output: [String: String] = [:]

        await withTaskGroup(of: (String, String).self) { group in
            for (key, groupedItems) in groups {
                group.addTask {
                    let sorted = groupedItems.sorted {
                        if $0.receivedAt != $1.receivedAt { return $0.receivedAt > $1.receivedAt }
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    guard let latest = sorted.first else { return (key, "") }

                    let counterparty = nonBlank(latest.senderNodeID)
                        ?? nonBlankMetadataNodeID(from: sorted)
                    guard let counterparty else { return (key, "") }

                    let linked = sorted.compactMap(\.threadID).first
                    let (preview, _) = await buildInboundLatestPreview(
                        rowID: key,
                        counterpartyNodeID: counterparty,
                        linkedThreadID: linked,
                        facade: facade
                    )
                    return (key, preview)
                }
            }

            for await (key, preview) in group {
                output[key] = preview
            }
        }

        return output
    }

    // MARK: - Helpers (private)

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonBlankMetadataNodeID(from items: [ExchangeInboxItem]) -> String? {
        let keys = [
            "sender_node_id",
            "counterparty_node_id",
            "trusted_node_id",
            "source_sender_node_id",
            "first_inbound_sender_node_id",
            "inbound_sender_node",
            "inbound_thread_sender_node",
        ]
        for item in items {
            for key in keys {
                if let v = nonBlank(item.metadata[key]) { return v }
            }
        }
        return nil
    }

    private static func usesFriendStyleDirectTranscript(detail: ExchangeModels.ThreadDetail) -> Bool {
        detail.thread.metadata["direct_message_thread"] == "true"
            || detail.thread.metadata["inbound_thread"] == "true"
    }

    private static func inboxItemBelongsOnThisTranscriptThread(
        _ item: ExchangeInboxItem,
        owningThreadID: ExchangeThread.ID
    ) -> Bool {
        if let tid = item.threadID, tid != owningThreadID { return false }
        return true
    }

    /// Exchange / inquiry / Conversation-card federation inbox — must not render in DM transcript.
    private static func isExchangeThreadInboxItem(_ item: ExchangeInboxItem) -> Bool {
        isExchangeThreadLaneMetadata(item.metadata)
    }

    /// Explicit direct-message lane inbox metadata (stricter inclusion for unfiled merge).
    private static func isDirectMessageInboxItem(_ item: ExchangeInboxItem) -> Bool {
        isDirectMessageLaneMetadata(item.metadata)
    }

    /// Surface-first: exclude only explicit exchange / Conversation-card markers.
    /// Do not treat `payload_kind=inquiry` alone as exchange — DM drafts also use inquiry kind.
    private static func isExchangeThreadLaneMetadata(_ metadata: [String: String]) -> Bool {
        if isDirectMessageLaneMetadata(metadata) {
            return false
        }
        if normalizedMetadataValue(metadata, key: "conversation_surface") == "exchange_thread" {
            return true
        }
        if normalizedMetadataValue(metadata, key: "conversation_kind") == "exchange_thread" {
            return true
        }
        if metadata["conversation_card_manual_outbound"] == "true" {
            return true
        }
        return false
    }

    private static func isDirectMessageLaneMetadata(_ metadata: [String: String]) -> Bool {
        if normalizedMetadataValue(metadata, key: "conversation_surface") == "direct_message" {
            return true
        }
        if normalizedMetadataValue(metadata, key: "conversation_kind") == "direct_message" {
            return true
        }
        if metadata["trusted_node_manual_message"] == "true" { return true }
        if metadata["dm_manual_v2"] == "true" { return true }
        if metadata["direct_message_thread"] == "true" { return true }
        if let payloadKind = normalizedMetadataValue(metadata, key: "payload_kind"),
           payloadKind.hasPrefix("direct_message") {
            return true
        }
        return false
    }

    private static func normalizedMetadataValue(
        _ metadata: [String: String],
        key: String
    ) -> String? {
        nonBlank(metadata[key])?.lowercased()
    }

    #if DEBUG
    private static func logSkippedExchangeThreadInboxForDirectMessageTranscript(
        item: ExchangeInboxItem,
        counterpartyNodeID: String
    ) {
        let surface = item.metadata["conversation_surface"] ?? "nil"
        let payloadKind = item.metadata["payload_kind"] ?? "nil"
        print(
            "[DirectMessageTranscriptProjection][skipExchangeThreadInbox] " +
            "sender=\(counterpartyNodeID) inboxID=\(item.id.uuidString) " +
            "surface=\(surface) payloadKind=\(payloadKind)"
        )
    }
    #endif

    private static func isDiscoveryOrAgencyOutboundDraft(_ draft: ExchangeMessageDraft) -> Bool {
        if draft.metadata["second_half_generated"] == "true" { return true }
        if draft.metadata["autonomy_source"] == "for_you" { return true }
        if draft.metadata["autonomous_first_contact"] == "true" { return true }
        if draft.metadata["autonomous_first_contact_queued"] == "true" { return true }
        if draft.metadata["autonomous_first_contact_approved"] == "true" { return true }
        return false
    }

    private static func isDiscoveryOrAgencyUserTurn(_ turn: ExchangeTurn) -> Bool {
        if turn.metadata["second_half_generated"] == "true" { return true }
        if turn.metadata["autonomy_source"] == "for_you" { return true }
        if turn.metadata["autonomous_first_contact"] == "true" { return true }
        return false
    }

    private static func isManualDirectDraft(_ draft: ExchangeMessageDraft) -> Bool {
        guard draft.audience == .externalCounterparty else { return false }
        guard draft.status == .approved || draft.status == .sent else { return false }
        if isContactRequestMetadata(draft.metadata) { return false }

        return draft.metadata["trusted_node_manual_message"] == "true"
            || draft.metadata["inbound_provider_manual_reply"] == "true"
    }

    private static func isManualDirectTurn(_ turn: ExchangeTurn) -> Bool {
        if isContactRequestMetadata(turn.metadata) { return false }

        return turn.metadata["trusted_node_manual_message"] == "true"
            || turn.metadata["inbound_provider_manual_reply"] == "true"
    }

    private static func isContactRequestMetadata(_ metadata: [String: String]) -> Bool {
        ExchangeContactSignalClassifier.matchesContactSignalMetadata(metadata)
    }

    private static func sanitizedMessageBody(_ raw: String?) -> String {
        let cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleaned.isEmpty else { return "" }

        let lower = cleaned.lowercased()
        if lower.contains("auto-approved by requester bridge")
            || lower.contains("clarification needed")
            || lower.contains("find match")
            || lower.contains("no response yet after your last message")
            || lower.contains("direct message opened.") {
            return ""
        }

        return String(cleaned.prefix(600))
    }

    private static func transcriptInboundDisplayBody(
        rawBody: String,
        attachments: [DirectMessageAttachmentDescriptor],
        messageID: String
    ) -> String {
        let body = sanitizedMessageBody(rawBody)
        guard !attachments.isEmpty, isGenericInboundPlaceholderBody(body) else { return body }
        print(
            "[DMTranscript][mediaBodySuppressed] messageID=\(messageID) " +
            "attachmentCount=\(attachments.count) reason=genericInboundPlaceholder"
        )
        return ""
    }

    private static func normalizedInboundSourceID(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private static func inboxBodyPreview(_ item: ExchangeInboxItem) -> String {
        let parts = [
            item.metadata["body_preview"],
            item.visibleSummary,
            item.metadata["subject_preview"],
        ]

        for p in parts {
            let t = sanitizedMessageBody(p)
            if !t.isEmpty { return t }
        }

        return ""
    }

    private static func stableInboundBubbleID(
        turn: ExchangeTurn,
        fallbackPrefix: String = "turn-reply"
    ) -> String {
        if let inbox = normalizedInboundSourceID(turn.metadata["source_inbox_item_id"]) {
            return "inbound-\(inbox)"
        }
        if let envelope = normalizedInboundSourceID(turn.metadata["source_envelope_id"]) {
            return "inbound-envelope-\(envelope)"
        }
        if let ext = normalizedInboundSourceID(turn.externalReference) {
            return "inbound-envelope-\(ext)"
        }
        return "\(fallbackPrefix)-\(turn.id.uuidString)"
    }

    private static func stableInboxFallbackBubbleID(_ item: ExchangeInboxItem) -> String {
        if let envelopeID = normalizedInboundSourceID(item.envelopeID) {
            return "inbound-envelope-\(envelopeID)"
        }
        if let inboxID = normalizedInboundSourceID(item.id.uuidString) {
            return "inbound-\(inboxID)"
        }
        return "inbox-fallback-\(item.id.uuidString)"
    }

    private static func dedupedRows(_ rows: [DirectMessageTranscriptBubble]) -> [DirectMessageTranscriptBubble] {
        var seen = Set<String>()
        var output: [DirectMessageTranscriptBubble] = []

        for row in rows {
            let bodyKey = row.body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let attachKey = row.attachments.first.map(\.storageKey) ?? ""
            let timeKey = Int(row.timestamp.timeIntervalSince1970)
            let key = "\(row.isOutgoing ? "out" : "in")|\(timeKey)|\(bodyKey)|\(attachKey)"

            if seen.insert(key).inserted {
                output.append(row)
            }
        }

        return output
    }
}
