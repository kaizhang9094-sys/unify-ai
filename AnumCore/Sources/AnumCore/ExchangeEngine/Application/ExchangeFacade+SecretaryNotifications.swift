import Foundation

extension ExchangeFacade {
    /// Posted after second-half evaluation completes so open threads/lists pick up cached snapshots without waiting on sync.
    func emitDeskRefreshAfterSecondHalfCompleted(threadID: ExchangeThread.ID) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("secretaryWorkspaceShouldRefresh"),
                object: nil,
                userInfo: ["threadID": threadID.uuidString, "reason": "secondHalfCompleted"]
            )
        }
        await postSecretaryNotificationsDidChange()
    }
}

public extension Notification.Name {
    /// Posted when SQLite-backed Secretary notifications change (count or rows).
    static let secretaryNotificationsDidChange = Notification.Name("secretaryNotificationsDidChange")
}

extension ExchangeFacade {
    fileprivate enum SecretaryInboundAttentionSurface {
        static let metadataKey = "inbound_attention_surface"
        static let exchangeThread = "exchange_thread"
        static let directMessage = "direct_message"
    }

    public func registerSecretarySQLiteHooksIfNeeded() async {
        guard let sqlite = store as? ExchangeSQLiteStore else { return }

        let facade = self
        await sqlite.configureSecretarySQLiteHooks(
            ExchangeSecretarySQLiteHooks(
                onApprovalSaved: { approval in
                    await facade.secretarySQLiteHookApprovalSaved(approval)
                },
                onTurnAppended: { turn in
                    await facade.secretarySQLiteHookTurnAppended(turn)
                },
                onOutboxItemSaved: { item in
                    await facade.secretarySQLiteHookOutboxSaved(item)
                },
                onFailurePersisted: { threadID, failure in
                    await facade.secretarySQLiteHookFailurePersisted(threadID: threadID, failure: failure)
                }
            )
        )
    }

    // MARK: - Public queries / mutations

    public func listSecretaryNotifications(
        filter: ExchangeSecretaryNotificationFilter = .init()
    ) async throws -> [SecretaryNotification] {
        try await store.listSecretaryNotifications(filter: filter)
    }

    public func countUnreadSecretaryNotifications(
        excludingPriorityLow: Bool = true,
        excludedKinds: Set<SecretaryNotificationKind>? = nil
    ) async throws -> Int {
        try await store.countUnreadSecretaryNotifications(
            excludingPriorityLow: excludingPriorityLow,
            excludedKinds: excludedKinds
        )
    }

    /// Unread count for the global Updates bell — matches in-app `secretaryNotificationUnreadBadge`.
    public func countGlobalSecretaryUnreadBellBadge() async throws -> Int {
        let rows = try await listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                excludingPriorityLow: true,
                limit: 500
            )
        )
        return SecretaryNotification.collapseGlobalUnreadForDistinctAttention(rows).count
    }

    public func markSecretaryNotificationsRead(ids: Set<SecretaryNotification.ID>) async throws {
        try await store.markSecretaryNotificationsRead(ids: ids)
        await postSecretaryNotificationsDidChange()
    }

    public func markSecretaryNotificationsUnread(ids: Set<SecretaryNotification.ID>) async throws {
        try await store.markSecretaryNotificationsUnread(ids: ids)
        await postSecretaryNotificationsDidChange()
    }

    /// Marks unread notifications scoped to dashboard thread attention (excluding approval rows).
    public func markSecretaryThreadPeekNotificationsRead(threadID: ExchangeThread.ID) async throws {
        try await store.markSecretaryNotificationsReadForThread(
            threadID: threadID,
            kinds: Set<SecretaryNotificationKind>([
                .newReply,
                .needsAnswer,
                .matchReady,
                .sendFailed,
                .recoveryNeeded,
                .messageSent
            ])
        )
        await postSecretaryNotificationsDidChange()
    }

    /// Clears inbound messaging attention for one exchange thread only (no counterparty-wide sweep).
    public func markSecretaryExchangeThreadMessagingAttentionReadForOpen(
        threadID: ExchangeThread.ID
    ) async throws {
        try await store.markSecretaryNotificationsReadForThread(
            threadID: threadID,
            kinds: SecretaryNotificationKind.inboundMessagingUnreadSurface
        )
        await postSecretaryNotificationsDidChange()
    }

    /// True when any unread `.newReply` / `.needsAnswer` belongs to a non-DM exchange thread.
    public func hasUnreadExchangeThreadMessagingAttention(
        among prefetched: [SecretaryNotification]? = nil
    ) async throws -> Bool {
        let rows: [SecretaryNotification]
        if let prefetched {
            rows = prefetched
        } else {
            rows = try await listSecretaryNotifications(
                filter: ExchangeSecretaryNotificationFilter(
                    unreadOnly: true,
                    kinds: SecretaryNotificationKind.inboundMessagingUnreadSurface,
                    excludingPriorityLow: true,
                    limit: 500
                )
            )
        }

        for notification in rows where !notification.isRead {
            if await isExchangeThreadInboundMessagingNotification(notification) {
                return true
            }
        }
        return false
    }

    /// True when any unread `.newReply` / `.needsAnswer` belongs to the Chat tab (direct message / inbound lane), not exchange-thread conversation cards.
    public func hasUnreadInboundChatMessagingAttention(
        among prefetched: [SecretaryNotification]? = nil
    ) async throws -> Bool {
        let rows: [SecretaryNotification]
        if let prefetched {
            rows = prefetched
        } else {
            rows = try await listSecretaryNotifications(
                filter: ExchangeSecretaryNotificationFilter(
                    unreadOnly: true,
                    kinds: SecretaryNotificationKind.inboundMessagingUnreadSurface,
                    excludingPriorityLow: true,
                    limit: 500
                )
            )
        }

        for notification in rows where !notification.isRead {
            if await isExchangeThreadInboundMessagingNotification(notification) {
                continue
            }
            return true
        }
        return false
    }

    /// Marks send/recovery secretary notifications after the user opens a recovery sheet or equivalent route for the thread.
    public func markSecretaryRecoveryRouteNotificationsRead(threadID: ExchangeThread.ID) async throws {
        try await store.markSecretaryNotificationsReadForThread(
            threadID: threadID,
            kinds: Set([.sendFailed, .recoveryNeeded])
        )
        await postSecretaryNotificationsDidChange()
    }

    public func markSecretaryNotificationsReadForApproval(
        approvalID: ExchangeApproval.ID
    ) async throws {
        try await store.markSecretaryNotificationsReadWhereApproval(approvalID: approvalID)
        await postSecretaryNotificationsDidChange()
    }

    public func markSecretaryNotificationsReadForFailure(
        failureID: ExchangeFailure.ID
    ) async throws {
        try await store.markSecretaryNotificationsReadWhereFailure(failureID: failureID)
        await postSecretaryNotificationsDidChange()
    }

    public func markSecretaryNotificationsReadForTrustedNode(
        nodeID: String
    ) async throws {
        try await store.markSecretaryNotificationsReadWhereTrustedNode(nodeID: nodeID)
        await postSecretaryNotificationsDidChange()
    }

    /// Marks only non-messaging trusted-surface attention when opening Trusted contact UI (does not clear `.newReply` / `.needsAnswer` / etc.).
    public func markSecretaryTrustedContactSurfaceNotificationsRead(nodeID: String) async throws {
        let trimmed = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let rows = try await store.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                kinds: [.trustedContactAdded],
                excludingPriorityLow: true,
                limit: 200
            )
        )
        let lowered = trimmed.lowercased()
        let ids = Set(
            rows
                .filter {
                    guard let nid = $0.trustedNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !nid.isEmpty else { return false }
                    return nid.lowercased() == lowered
                }
                .map(\.id)
        )
        guard !ids.isEmpty else { return }
        try await store.markSecretaryNotificationsRead(ids: ids)
        await postSecretaryNotificationsDidChange()
    }

    /// Clears inbound messaging attention when opening an Inbound conversation (`.newReply` / `.needsAnswer` only).
    public func markSecretaryInboundMessagingAttentionReadForOpen(
        threadID: ExchangeThread.ID?,
        counterpartyNodeID: String?
    ) async throws {
        let messagingKinds = SecretaryNotificationKind.inboundMessagingUnreadSurface
        let kindsLabel = messagingKinds
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")

        let unreadRows = try await store.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                kinds: messagingKinds,
                excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                excludingPriorityLow: true,
                limit: 500
            )
        )

        let trimmedNode = counterpartyNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var effectiveLoweredNode = trimmedNode.isEmpty ? nil : trimmedNode.lowercased()
        if effectiveLoweredNode == nil, let threadID {
            if let thread = try? await store.fetchThread(id: threadID),
               let sel = thread.selectedCounterpartyID?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                effectiveLoweredNode = sel.lowercased()
            }
        }
        let nodeIDLog: String = {
            if let n = counterpartyNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                return n
            }
            if let el = effectiveLoweredNode { return el }
            return "nil"
        }()

        #if DEBUG
        let beforeKeys = unreadRows.map(\.inboundMessagingAttentionKey).sorted()
        #endif

        var matchedIDs = Set<SecretaryNotification.ID>()
        if let tid = threadID {
            for n in unreadRows where n.threadID == tid {
                matchedIDs.insert(n.id)
            }
        }
        if let loweredNode = effectiveLoweredNode {
            for n in unreadRows {
                guard let nid = n.trustedNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else { continue }
                guard nid.lowercased() == loweredNode else { continue }
                matchedIDs.insert(n.id)
            }
        }
        if let loweredNode = effectiveLoweredNode {
            var threadCache: [ExchangeThread.ID: ExchangeThread] = [:]
            for n in unreadRows {
                guard n.trustedNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank == nil else { continue }
                guard let rowTid = n.threadID else { continue }
                guard !matchedIDs.contains(n.id) else { continue }
                let thread: ExchangeThread?
                if let cached = threadCache[rowTid] {
                    thread = cached
                } else if let fetched = try? await store.fetchThread(id: rowTid) {
                    threadCache[rowTid] = fetched
                    thread = fetched
                } else {
                    thread = nil
                }
                guard let resolvedThread = thread else {
                    #if DEBUG
                    Swift.print(
                        "[InboundBadgeClearFallbackCandidate] notificationID=\(n.id.uuidString) notificationThreadID=\(rowTid.uuidString) effectiveNode=\(loweredNode) matched=false reason=fetchThreadFailed"
                    )
                    #endif
                    continue
                }
                let (matched, reason) = await inboundNotificationThreadMatchesCounterpartyNode(
                    thread: resolvedThread,
                    effectiveLoweredNode: loweredNode
                )
                #if DEBUG
                Swift.print(
                    "[InboundBadgeClearFallbackCandidate] notificationID=\(n.id.uuidString) notificationThreadID=\(rowTid.uuidString) effectiveNode=\(loweredNode) matched=\(matched) reason=\(reason)"
                )
                #endif
                if matched {
                    matchedIDs.insert(n.id)
                }
            }
        }

        #if DEBUG
        let matchedList = matchedIDs.map(\.uuidString).sorted().joined(separator: ",")
        Swift.print(
            "[InboundBadgeClearBasis] threadID=\(threadID?.uuidString ?? "nil") nodeID=\(nodeIDLog) matchedIDs=\(matchedIDs.count) matchedList=\(matchedList) beforeKeys=\(beforeKeys) kinds=\(kindsLabel)"
        )
        #endif

        guard !matchedIDs.isEmpty else {
            #if DEBUG
            Swift.print(
                "[InboundBadgeClearResult] cleared=0 matchedIDs=0 afterKeys=\(beforeKeys)"
            )
            #endif
            return
        }

        try await store.markSecretaryNotificationsRead(ids: matchedIDs)
        await postSecretaryNotificationsDidChange()

        #if DEBUG
        let afterRows = try? await store.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                kinds: messagingKinds,
                excludedKinds: SecretaryNotificationKind.globalBellAndFeedExcludedKinds,
                excludingPriorityLow: true,
                limit: 500
            )
        )
        let afterKeys = (afterRows ?? []).map(\.inboundMessagingAttentionKey).sorted()
        Swift.print(
            "[InboundBadgeClearResult] cleared=\(matchedIDs.count) afterKeys=\(afterKeys)"
        )
        #endif
    }

    /// Unread rows whose `trustedNodeID` is missing still belong to the same counterparty when their
    /// notification `threadID` resolves to a thread whose selected counterparty / identity matches `effectiveLoweredNode`.
    fileprivate func inboundNotificationThreadMatchesCounterpartyNode(
        thread: ExchangeThread,
        effectiveLoweredNode: String
    ) async -> (matched: Bool, reason: String) {
        let node = effectiveLoweredNode

        if let sel = thread.selectedCounterpartyID?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            sel.lowercased() == node {
            return (true, "selectedCounterpartyIDEqualsNode")
        }

        if let sel = thread.selectedCounterpartyID?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            let cp = try? await store.fetchCounterparty(id: sel) {
            if cp.id.lowercased() == node {
                return (true, "counterpartyRecordIDMatches")
            }
            if let nid = cp.identity?.nodeID?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                nid.lowercased() == node {
                return (true, "identityNodeIDMatches")
            }
        }

        for cand in thread.candidateCounterpartyIDs {
            let trimmed = cand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.lowercased() == node {
                return (true, "candidateCounterpartyIDMatches")
            }
            if let cp = try? await store.fetchCounterparty(id: cand) {
                if cp.id.lowercased() == node {
                    return (true, "candidateRecordIDMatches")
                }
                if let nid = cp.identity?.nodeID?
                    .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                    nid.lowercased() == node {
                    return (true, "candidateIdentityNodeIDMatches")
                }
            }
        }

        return (false, "noCounterpartyMatchOnThread")
    }

    #if DEBUG
    fileprivate func unreadInboundMessagingAttentionKeys(
        kinds: Set<SecretaryNotificationKind>
    ) async throws -> [String] {
        let rows = try await store.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(
                unreadOnly: true,
                kinds: kinds,
                excludingPriorityLow: true,
                limit: 500
            )
        )
        return rows.filter { !$0.isRead }.map(\.inboundMessagingAttentionKey).sorted()
    }
    #endif

    /// Inserts or merges a notification row (primarily for tests or future bridges).
    public func upsertSecretaryNotification(_ notification: SecretaryNotification) async throws {
        try await store.upsertSecretaryNotification(notification)
        await postSecretaryNotificationsDidChange()
    }

    // MARK: - reconcile hook

    func emitSecretaryNotificationsForReconciledInbound(
        result: ExchangeFederationReconcileResult,
        now: Date
    ) async {
        _ = now
        let threads = result.reconciledThreadIDs
        let envelopes = result.reconciledEnvelopeIDs
        let count = min(threads.count, envelopes.count)
        guard count > 0 else { return }

        #if DEBUG
        Swift.print(
            "[InboundNotificationReconcileSkip] reason=replyReceived_hook_is_canonical threads=\(threads.count) envelopes=\(envelopes.count) paired=\(count)"
        )
        #endif
    }

    func emitTrustedContactAddedSecretaryNotification(
        canonicalNodeID: String,
        displayLine: String,
        now: Date
    ) async {
        let body = displayLine.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? canonicalNodeID
        await persistSecretaryAttention(
            SecretaryNotification(
                createdAt: now,
                updatedAt: now,
                kind: .trustedContactAdded,
                dedupeKey: SecretaryNotificationDedupeKey.trustedContactAdded(nodeID: canonicalNodeID),
                priority: .normal,
                title: "Trusted contact saved",
                body: body,
                trustedNodeID: canonicalNodeID,
                metadata: [:]
            )
        )
    }

    // MARK: - Persistence + refresh

    fileprivate func persistSecretaryAttention(_ notification: SecretaryNotification) async {
        do {
            try await store.upsertSecretaryNotification(notification)
            #if DEBUG
            Swift.print(
                "[InboundNotificationPersisted] dedupeKey=\(notification.dedupeKey) kind=\(notification.kind.rawValue) isRead=\(notification.isRead) threadID=\(notification.threadID?.uuidString ?? "nil") trustedNodeID=\(notification.trustedNodeID ?? "nil")"
            )
            #endif
            await postSecretaryNotificationsDidChange()
        } catch {
            #if DEBUG
            Swift.print("[ExchangeFacade] secretary notification upsert skipped | \(String(describing: error))")
            #endif
        }
    }

    fileprivate func postSecretaryNotificationsDidChange() async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .secretaryNotificationsDidChange,
                object: nil
            )
            // Desk refresh is coalesced via `AppServices.requestSecretaryRefresh` from UI observers on
            // `secretaryNotificationsDidChange`. Avoid duplicate `secretaryWorkspaceShouldRefresh` bursts here.
        }
    }

    fileprivate func secretarySQLiteHookApprovalSaved(_ approval: ExchangeApproval) async {
        guard approval.status == .pending else { return }

        await persistSecretaryAttention(
            SecretaryNotification(
                kind: .needsApproval,
                dedupeKey: SecretaryNotificationDedupeKey.needsApproval(approvalID: approval.id),
                title: "Decision needed",
                body: sanitizedSecretarySentence(approval.summary),
                threadID: approval.threadID,
                approvalID: approval.id,
                metadata: ["hook": "approval_saved"]
            )
        )
    }

    fileprivate func secretarySQLiteHookTurnAppended(_ turn: ExchangeTurn) async {
        await postDirectMessageTranscriptDidChangeIfNeeded(for: turn)

        switch turn.kind {
        case .replyReceived:
            await secretarySQLiteHookCounterpartyReplyReceivedTurn(turn)

        case .clarificationAsked:
            let clarificationSurface = await inboundAttentionSurface(for: turn.threadID)
            await persistSecretaryAttention(
                SecretaryNotification(
                    kind: .needsAnswer,
                    dedupeKey: SecretaryNotificationDedupeKey.needsAnswer(
                        threadID: turn.threadID,
                        clarificationTurnID: turn.id
                    ),
                    title: "Needs your answer",
                    body: sanitizedSecretarySentence(turn.summary),
                    threadID: turn.threadID,
                    turnID: turn.id,
                    metadata: [
                        "hook": "clarification_asked",
                        SecretaryInboundAttentionSurface.metadataKey: clarificationSurface ?? ""
                    ].filter { !$0.value.isEmpty }
                )
            )

        case .candidateSelected:
            await persistSecretaryAttention(
                SecretaryNotification(
                    kind: .matchReady,
                    dedupeKey: SecretaryNotificationDedupeKey.matchReady(threadID: turn.threadID),
                    title: "Match ready",
                    body: await secretarySafeConversationPeekLine(threadID: turn.threadID),
                    threadID: turn.threadID,
                    turnID: turn.id,
                    metadata: ["hook": "candidate_selected"]
                )
            )

        case .deliveryFailed:
            await persistSecretaryAttention(
                SecretaryNotification(
                    kind: .sendFailed,
                    dedupeKey: SecretaryNotificationDedupeKey.sendFailed(
                        threadID: turn.threadID,
                        outboxItemID: secretarySyntheticOutboxID(from: turn)
                    ),
                    title: "Send didn’t finish",
                    body: await secretarySafeConversationPeekLine(threadID: turn.threadID),
                    threadID: turn.threadID,
                    turnID: turn.id,
                    metadata: ["hook": "delivery_failed_turn"]
                )
            )

        case .sendConfirmed:
            guard Self.secretaryMessageSentHooksEnabled else { return }
            await persistSecretaryAttention(
                SecretaryNotification(
                    kind: .messageSent,
                    dedupeKey: SecretaryNotificationDedupeKey.messageSent(
                        threadID: turn.threadID,
                        turnID: turn.id
                    ),
                    priority: .low,
                    title: "Message sent",
                    body: await secretarySafeConversationPeekLine(threadID: turn.threadID),
                    threadID: turn.threadID,
                    turnID: turn.id,
                    metadata: ["hook": "send_confirmed"]
                )
            )

        default:
            break
        }
    }

    /// Default off — enable only if product wants quiet “message sent” entries.
    fileprivate static var secretaryMessageSentHooksEnabled: Bool { false }

    fileprivate func secretarySQLiteHookCounterpartyReplyReceivedTurn(_ turn: ExchangeTurn) async {
        guard turn.kind == .replyReceived else { return }
        guard turn.actor == .counterparty else { return }
        guard turn.visibility.isVisibleToUserByDefault else { return }
        guard !shouldSuppressInboundMessagingAttentionForCounterpartyTurn(turn) else { return }

        let envelopeHint =
            turn.metadata["source_envelope_id"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? turn.externalReference?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank

        if let env = envelopeHint, !env.isEmpty,
           let thread = try? await store.fetchThread(id: turn.threadID),
           thread.metadata["direct_message_thread"] == "true",
           (try? await store.fetchOutboxItemByEnvelopeID(env)) != nil {
            #if DEBUG
            Swift.print(
                "[InboundNotificationSkip] reason=dm_outbox_echo threadID=\(turn.threadID.uuidString) envelopeID=\(env)"
            )
            #endif
            return
        }

        var counterpartyNodeID =
            turn.metadata["source_sender_node_id"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        if counterpartyNodeID == nil,
           let thread = try? await store.fetchThread(id: turn.threadID) {
            counterpartyNodeID = thread.selectedCounterpartyID?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }

        let previewSource = turn.detail?.nilIfBlank ?? turn.summary
        let bodyPreview = previewSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadKind = turn.metadata["payload_kind"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let attentionTitle = (payloadKind == "inquiry" || payloadKind == "introduction")
            ? "New inquiry"
            : "New message"
        var hookMetadata: [String: String] = [
            "hook": "reply_received_counterparty",
            "turn_id": turn.id.uuidString
        ]
        if !payloadKind.isEmpty {
            hookMetadata["payload_kind"] = payloadKind
        }

        await ensureInboundMessagingNotificationForVisibleInboundMessage(
            threadID: turn.threadID,
            envelopeID: envelopeHint,
            counterpartyNodeID: counterpartyNodeID,
            bodyPreview: bodyPreview.isEmpty ? attentionTitle : bodyPreview,
            receivedAt: turn.createdAt,
            turnID: turn.id,
            source: "sqlite_hook_replyReceived",
            title: attentionTitle,
            extraMetadata: hookMetadata
        )

        await postExchangeThreadWorkspaceRefreshAfterCounterpartyReplyIfNeeded(turn)
    }

    /// Refreshes open exchange-thread UI (e.g. Conversation card) without DM transcript notifications.
    fileprivate func postExchangeThreadWorkspaceRefreshAfterCounterpartyReplyIfNeeded(_ turn: ExchangeTurn) async {
        guard turn.actor == .counterparty else { return }
        guard let thread = try? await store.fetchThread(id: turn.threadID) else { return }
        guard thread.metadata["direct_message_thread"] != "true" else { return }

        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("secretaryWorkspaceShouldRefresh"),
                object: nil,
                userInfo: [
                    "threadID": turn.threadID.uuidString,
                    "reason": "exchangeThreadReplyReceived"
                ]
            )
        }
    }

    /// Ensures SQLite-backed `.newReply` attention exists for a user-visible inbound counterparty message.
    fileprivate func ensureInboundMessagingNotificationForVisibleInboundMessage(
        threadID: ExchangeThread.ID?,
        envelopeID: String?,
        counterpartyNodeID: String?,
        bodyPreview: String,
        receivedAt: Date,
        turnID: ExchangeTurn.ID?,
        source: String,
        title: String = "New message",
        extraMetadata: [String: String] = [:]
    ) async {
        if extraMetadata["local_outbox_echo"] == "true"
            || extraMetadata["outbound_local_echo"] == "true" {
            #if DEBUG
            Swift.print("[InboundNotificationSkip] reason=local_echo_metadata source=\(source)")
            #endif
            return
        }

        let trimmedEnvelope = envelopeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        var trimmedNode = counterpartyNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        if trimmedNode == nil, let tid = threadID, let thread = try? await store.fetchThread(id: tid) {
            trimmedNode = thread.selectedCounterpartyID?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }

        guard threadID != nil || trimmedNode != nil else {
            #if DEBUG
            Swift.print("[InboundNotificationSkip] reason=missing_thread_and_counterparty source=\(source)")
            #endif
            return
        }

        let millis = Int(receivedAt.timeIntervalSince1970 * 1000)

        // Dedupe: envelope id when available, else turn id, else coarse timestamp (per product contract).
        let dedupeKey: String = {
            if let tid = threadID, let ev = trimmedEnvelope, !ev.isEmpty {
                return SecretaryNotificationDedupeKey.newReply(threadID: tid, envelopeID: ev)
            }
            if let tid = threadID, let tID = turnID {
                return SecretaryNotificationDedupeKey.newReplyTurn(threadID: tid, turnID: tID)
            }
            if let tid = threadID {
                return SecretaryNotificationDedupeKey.newReplyTimeFallback(threadID: tid, millis: millis)
            }
            guard let node = trimmedNode else {
                return SecretaryNotificationDedupeKey.newReplyNode(nodeID: "unknown", envelopeIDOrTimeKey: "\(millis)")
            }
            let suffix = trimmedEnvelope ?? "\(millis)"
            return SecretaryNotificationDedupeKey.newReplyNode(nodeID: node, envelopeIDOrTimeKey: suffix)
        }()

        let body = sanitizedSecretarySentence(bodyPreview)
        var md = extraMetadata
        md["inbound_attention_source"] = source
        md["inbound_attention_received_at_ms"] = "\(millis)"
        if let surface = await inboundAttentionSurface(for: threadID) {
            md[SecretaryInboundAttentionSurface.metadataKey] = surface
        }

        let now = Date()

        #if DEBUG
        Swift.print(
            "[InboundNotificationCreated] kind=newReply threadID=\(threadID?.uuidString ?? "nil") nodeID=\(trimmedNode ?? "nil") envelopeID=\(trimmedEnvelope ?? "nil") turnID=\(turnID?.uuidString ?? "nil") dedupeKey=\(dedupeKey) source=\(source) surface=\(md[SecretaryInboundAttentionSurface.metadataKey] ?? "nil")"
        )
        #endif

        await persistSecretaryAttention(
            SecretaryNotification(
                createdAt: now,
                updatedAt: now,
                kind: .newReply,
                dedupeKey: dedupeKey,
                priority: .normal,
                title: title,
                body: body,
                threadID: threadID,
                turnID: turnID,
                trustedNodeID: trimmedNode,
                metadata: md
            )
        )
    }

    fileprivate func shouldSuppressInboundMessagingAttentionForCounterpartyTurn(_ turn: ExchangeTurn) -> Bool {
        if turn.metadata["second_half_generated"] == "true" { return true }
        if turn.metadata["autonomy_source"] == "for_you" { return true }
        if turn.metadata["autonomous_first_contact"] == "true" { return true }
        if turn.metadata["autonomous_first_contact_queued"] == "true" { return true }
        if turn.metadata["autonomous_first_contact_approved"] == "true" { return true }
        if turn.metadata["inbound_attention_suppressed"] == "true" { return true }
        if turn.metadata["local_outbox_echo"] == "true" { return true }
        if turn.metadata["outbound_local_echo"] == "true" { return true }
        return false
    }

    fileprivate func inboundAttentionSurface(for threadID: ExchangeThread.ID?) async -> String? {
        guard let threadID, let thread = try? await store.fetchThread(id: threadID) else { return nil }
        if thread.metadata["direct_message_thread"] == "true" {
            return SecretaryInboundAttentionSurface.directMessage
        }
        return SecretaryInboundAttentionSurface.exchangeThread
    }

    fileprivate func isExchangeThreadInboundMessagingNotification(
        _ notification: SecretaryNotification
    ) async -> Bool {
        if notification.metadata[SecretaryInboundAttentionSurface.metadataKey]
            == SecretaryInboundAttentionSurface.exchangeThread {
            return true
        }
        if notification.metadata[SecretaryInboundAttentionSurface.metadataKey]
            == SecretaryInboundAttentionSurface.directMessage {
            return false
        }
        guard let threadID = notification.threadID,
              let thread = try? await store.fetchThread(id: threadID) else {
            return false
        }
        return thread.metadata["direct_message_thread"] != "true"
    }

    fileprivate func secretarySQLiteHookOutboxSaved(_ item: ExchangeOutboxItem) async {
        guard item.deliveryState.phase == .failed else { return }

        await persistSecretaryAttention(
            SecretaryNotification(
                kind: .sendFailed,
                dedupeKey: SecretaryNotificationDedupeKey.sendFailed(
                    threadID: item.threadID,
                    outboxItemID: item.id
                ),
                title: "Send didn’t finish",
                body: await secretarySafeConversationPeekLine(threadID: item.threadID),
                threadID: item.threadID,
                metadata: [
                    "hook": "outbox_failed",
                    "outbox_item_id": item.id.uuidString
                ]
            )
        )
    }

    fileprivate func secretarySQLiteHookFailurePersisted(
        threadID: ExchangeThread.ID?,
        failure: ExchangeFailure
    ) async {
        guard let threadID else { return }

        await persistSecretaryAttention(
            SecretaryNotification(
                kind: .recoveryNeeded,
                dedupeKey: SecretaryNotificationDedupeKey.recoveryNeeded(
                    threadID: threadID,
                    failureID: failure.id
                ),
                priority: .normal,
                title: "Needs attention",
                body: sanitizedSecretarySentence(failure.summary),
                threadID: threadID,
                failureID: failure.id,
                metadata: ["hook": "failure_saved"]
            )
        )
    }

    fileprivate func secretarySyntheticOutboxID(from turn: ExchangeTurn) -> ExchangeOutboxItem.ID {
        turn.id
    }

    fileprivate func secretarySafeConversationPeekLine(threadID: ExchangeThread.ID) async -> String {
        do {
            if let thread = try await store.fetchThread(id: threadID) {
                let title = sanitizedSecretarySentence(thread.title)
                let trimmed = title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                return trimmed.isEmpty ? "Open this conversation." : trimmed
            }
        } catch {}

        return "Open this conversation."
    }

    fileprivate func sanitizedSecretarySentence(_ raw: String) -> String {
        SecretaryNotificationCopySanitizer.sanitizeSentence(raw)
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
