import Foundation

// MARK: - Thread conversation transcript (local projection only)

public extension ExchangeModels {
    /// A single human-readable row for the Conversation surface (derived from drafts, turns, and thread delivery state).
    struct ThreadTranscriptEntry: Sendable, Hashable, Identifiable {
        public var id: String
        /// Short label such as “You sent” or “They replied”.
        public var title: String
        public var bodyPreview: String
        public var timestamp: Date
        /// Optional compact status (e.g. “Couldn’t send”) — keep empty when redundant with title.
        public var statusChip: String?

        public init(
            id: String,
            title: String,
            bodyPreview: String,
            timestamp: Date,
            statusChip: String? = nil
        ) {
            self.id = id
            self.title = title
            self.bodyPreview = bodyPreview
            self.timestamp = timestamp
            self.statusChip = statusChip
        }
    }

    enum ThreadTranscriptBuilder {
        /// `true` when a prose line (e.g. provider assessment) repeats an inbound body already shown in ``build(from:secondHalfDisplay:)``.
        public static func providerAssessmentLineDuplicatesInboundTranscript(
            _ line: String,
            detail: ExchangeModels.ThreadDetail
        ) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let factKey = normalizedTranscriptBodyMatchKey(trimmed)
            guard factKey.count >= 8 else { return false }
            let inboundKeys = inboundTranscriptBodyMatchKeys(for: detail)
            for inbound in inboundKeys where !inbound.isEmpty {
                if inbound == factKey { return true }
                if inbound.hasPrefix(factKey) || factKey.hasPrefix(inbound) { return true }
            }
            return false
        }

        /// Builds a newest-first conversation transcript from durable thread detail.
        ///
        /// Open-draft (“Draft ready”) rows use ``ExchangeMessageDraft.userFacingRenderableExternalOutboundDraftIDs``
        /// so Conversation matches Draft ready / review gates (stale second-half drafts after newer sends are omitted).
        ///
        /// When `secondHalfDisplay` is provided, suppresses duplicate rows for second-half generated outbound drafts
        /// already surfaced on the main second-half card.
        public static func build(
            from detail: ExchangeModels.ThreadDetail,
            secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel? = nil
        ) -> [ThreadTranscriptEntry] {
            var rows: [ThreadTranscriptEntry] = []
            let thread = detail.thread
            let threadID = thread.id

            let userFacingDraftIDs = ExchangeMessageDraft.userFacingRenderableExternalOutboundDraftIDs(
                in: detail.drafts,
                thread: detail.thread,
                turns: detail.turns
            )

            let approvalsByDraftID: [ExchangeMessageDraft.ID: ExchangeApproval] = {
                var map: [ExchangeMessageDraft.ID: ExchangeApproval] = [:]
                for a in detail.approvals {
                    if let did = a.draftID {
                        if let existing = map[did] {
                            if a.updatedAt >= existing.updatedAt { map[did] = a }
                        } else {
                            map[did] = a
                        }
                    }
                }
                return map
            }()

            var draftIDsWithEmittedFailureRows: Set<ExchangeMessageDraft.ID> = []

            let secondHalfOpenOutboundDraftCount = detail.drafts.filter { d in
                guard userFacingDraftIDs.contains(d.id) else { return false }
                guard d.audience == .externalCounterparty else { return false }
                guard d.metadata["second_half_generated"] == "true" else { return false }
                switch d.status {
                case .draft, .awaitingApproval:
                    return true
                case .approved, .rejected, .sent, .superseded, .abandoned:
                    return false
                }
            }.count

            for draft in detail.drafts where draft.audience == .externalCounterparty {
                switch draft.status {
                case .sent:
                    let title = outboundSentTitle(for: draft, approval: approvalsByDraftID[draft.id])
                    rows.append(
                        ThreadTranscriptEntry(
                            id: "draft-sent-\(draft.id.uuidString)",
                            title: title,
                            bodyPreview: scrubUserFacing(draftPreviewText(draft)),
                            timestamp: draft.updatedAt
                        )
                    )
                case .approved:
                    // Approved drafts are no longer “Draft ready”; only surface outbound pipeline states here.
                    guard !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    guard ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread) else { continue }

                    if let failedItem = prioritizedOutboxItemIndicatingFailure(
                        draftID: draft.id,
                        threadID: threadID,
                        outboxItems: detail.outboxItems
                    ) {
                        let note = failureNote(from: failedItem)
                        draftIDsWithEmittedFailureRows.insert(draft.id)
                        rows.append(
                            ThreadTranscriptEntry(
                                id: "draft-send-failed-\(draft.id.uuidString)",
                                title: transcriptCouldntSendTitle,
                                bodyPreview: scrubUserFacing(note),
                                timestamp: failedItem.updatedAt
                            )
                        )
                    } else if prioritizedOutboxItemIndicatingSending(
                        draftID: draft.id,
                        threadID: threadID,
                        outboxItems: detail.outboxItems
                    ) != nil {
                        rows.append(
                            ThreadTranscriptEntry(
                                id: "draft-sending-\(draft.id.uuidString)",
                                title: transcriptSendingTitle,
                                bodyPreview: scrubUserFacing(draftPreviewText(draft)),
                                timestamp: draft.updatedAt
                            )
                        )
                    } else if isConversationCardManualOutboundDraft(draft) {
                        rows.append(
                            ThreadTranscriptEntry(
                                id: "draft-conversation-outbound-\(draft.id.uuidString)",
                                title: "You sent",
                                bodyPreview: scrubUserFacing(draftPreviewText(draft)),
                                timestamp: draft.updatedAt
                            )
                        )
                    }
                case .draft, .awaitingApproval:
                    guard !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let actionable = draft.isActionable || draft.status == .awaitingApproval
                    guard actionable else { continue }

                    // User-facing “Draft ready” / outbound transcript rows require durable recipient routing on
                    // the owning thread — same invariant as ``ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft``.
                    guard ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread) else {
                        #if DEBUG
                        Swift.print(
                            "[Transcript] orphan_external_draft_suppressed thread=\(threadID.uuidString) draft=\(draft.id.uuidString)"
                        )
                        #endif
                        continue
                    }

                    guard userFacingDraftIDs.contains(draft.id) else {
                        #if DEBUG
                        let ev = ExchangeMessageDraft.latestOutboundSendEvidenceDate(
                            drafts: detail.drafts,
                            turns: detail.turns,
                            thread: detail.thread
                        )
                        Swift.print(
                            "[TranscriptDraftRow] suppressed thread=\(threadID.uuidString) draft=\(draft.id.uuidString) status=\(draft.status.rawValue) updatedAt=\(draft.updatedAt.timeIntervalSince1970) reason=not_user_facing_renderable latestOutboundEvidence=\(ev?.timeIntervalSince1970.description ?? "nil") bodyPrefix=\(transcriptDraftDebugBodyPrefix(draft.body))"
                        )
                        #endif
                        continue
                    }

                    if shouldSuppressSecondHalfDraftTranscriptRow(
                        draft: draft,
                        detail: detail,
                        secondHalfDisplay: secondHalfDisplay,
                        secondHalfOpenOutboundDraftCount: secondHalfOpenOutboundDraftCount
                    ) {
                        continue
                    }

                    if let failedItem = prioritizedOutboxItemIndicatingFailure(
                        draftID: draft.id,
                        threadID: threadID,
                        outboxItems: detail.outboxItems
                    ) {
                        let note = failureNote(from: failedItem)
                        draftIDsWithEmittedFailureRows.insert(draft.id)
                        rows.append(
                            ThreadTranscriptEntry(
                                id: "draft-send-failed-\(draft.id.uuidString)",
                                title: transcriptCouldntSendTitle,
                                bodyPreview: scrubUserFacing(note),
                                timestamp: failedItem.updatedAt
                            )
                        )
                    } else if prioritizedOutboxItemIndicatingSending(
                        draftID: draft.id,
                        threadID: threadID,
                        outboxItems: detail.outboxItems
                    ) != nil {
                        rows.append(
                            ThreadTranscriptEntry(
                                id: "draft-sending-\(draft.id.uuidString)",
                                title: transcriptSendingTitle,
                                bodyPreview: scrubUserFacing(draftPreviewText(draft)),
                                timestamp: draft.updatedAt
                            )
                        )
                    } else {
                        #if DEBUG
                        Swift.print(
                            "[TranscriptDraftRow] included thread=\(threadID.uuidString) draft=\(draft.id.uuidString) status=\(draft.status.rawValue) updatedAt=\(draft.updatedAt.timeIntervalSince1970) reason=user_facing_renderable"
                        )
                        #endif
                        rows.append(
                            ThreadTranscriptEntry(
                                id: "draft-open-\(draft.id.uuidString)",
                                title: transcriptDraftReadyTitle,
                                bodyPreview: scrubUserFacing(draftPreviewText(draft)),
                                timestamp: draft.updatedAt
                            )
                        )
                    }
                case .rejected, .abandoned:
                    continue
                case .superseded:
                    continue
                }
            }

            let replyTurns = detail.turns.filter { $0.kind == .replyReceived && $0.actor == .counterparty }
            let inboxRows = detail.inboxItems
                .filter { item in
                    guard item.threadID == threadID else { return false }
                    switch item.processingState {
                    case .reconciledIntoThread, .received, .deferred:
                        return true
                    default:
                        return false
                    }
                }
                .sorted { $0.receivedAt < $1.receivedAt }

            var emittedInboundBodyKeys: Set<String> = []
            var emittedInboundEnvelopeIDs: Set<String> = []
            var emittedInboundInboxItemIDs: Set<String> = []
            var inboundLatestCandidates: [(Date, String)] = []
            var emittedReplyTurns = 0
            var inboxFallbackCandidates = 0
            var emittedInboxFallbacks = 0
            var skippedFallbackByEnvelope = 0
            var skippedFallbackByInboxID = 0
            var skippedFallbackByBodyOnly = 0

            for turn in replyTurns {
                let raw = (turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(\.nilIfBlank)
                    ?? turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                emittedInboundBodyKeys.insert(normalizedTranscriptBodyMatchKey(raw))
                if let env = normalizedInboundSourceID(turn.metadata["source_envelope_id"]) {
                    emittedInboundEnvelopeIDs.insert(env)
                }
                if let inboxID = normalizedInboundSourceID(turn.metadata["source_inbox_item_id"]) {
                    emittedInboundInboxItemIDs.insert(inboxID)
                }
                if let ext = normalizedInboundSourceID(turn.externalReference) {
                    emittedInboundEnvelopeIDs.insert(ext)
                }
                inboundLatestCandidates.append((turn.createdAt, "reply:\(turn.id.uuidString)"))
            }

            var inboxItemsToEmit: [ExchangeInboxItem] = []
            for item in inboxRows {
                inboxFallbackCandidates += 1
                let inboxID = normalizedInboundSourceID(item.id.uuidString)
                let envelopeID = normalizedInboundSourceID(item.envelopeID)
                if let envelopeID, emittedInboundEnvelopeIDs.contains(envelopeID) {
                    skippedFallbackByEnvelope += 1
                    continue
                }
                if let inboxID, emittedInboundInboxItemIDs.contains(inboxID) {
                    skippedFallbackByInboxID += 1
                    continue
                }

                let preview = inboxBodyPreview(item)
                let key = normalizedTranscriptBodyMatchKey(preview)
                if key.count >= 8,
                   emittedInboundBodyKeys.contains(key),
                   inboxID == nil,
                   envelopeID == nil {
                    skippedFallbackByBodyOnly += 1
                    continue
                }
                if key.count >= 8 {
                    emittedInboundBodyKeys.insert(key)
                }
                inboxItemsToEmit.append(item)
                inboundLatestCandidates.append((item.receivedAt, "inbox:\(item.id.uuidString)"))
            }

            let winningInbound = inboundLatestCandidates.max { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                return lhs.1 < rhs.1
            }

            for turn in replyTurns {
                let raw = (turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(\.nilIfBlank)
                    ?? turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                emittedReplyTurns += 1
                let momentKey = "reply:\(turn.id.uuidString)"
                let title = inboundReceivedRowTitle(
                    turnDate: turn.createdAt,
                    momentKey: momentKey,
                    winning: winningInbound
                )
                rows.append(
                    ThreadTranscriptEntry(
                        id: "turn-reply-\(turn.id.uuidString)",
                        title: title,
                        bodyPreview: scrubUserFacing(String(raw.prefix(400))),
                        timestamp: turn.createdAt,
                        statusChip: nil
                    )
                )
            }

            for turn in detail.turns {
                guard let mapped = userFacingTranscriptEntry(for: turn) else { continue }
                rows.append(mapped)
            }

            for item in inboxItemsToEmit {
                let preview = inboxBodyPreview(item)
                let momentKey = "inbox:\(item.id.uuidString)"
                let title = inboundReceivedRowTitle(
                    turnDate: item.receivedAt,
                    momentKey: momentKey,
                    winning: winningInbound
                )
                rows.append(
                    ThreadTranscriptEntry(
                        id: "inbox-fallback-\(item.id.uuidString)",
                        title: title,
                        bodyPreview: scrubUserFacing(preview),
                        timestamp: item.receivedAt,
                        statusChip: nil
                    )
                )
                emittedInboxFallbacks += 1
            }

            if let failureRow = deliveryFailureRow(
                thread: thread,
                outbox: detail.outboxItems,
                suppressedFailureDraftIDs: draftIDsWithEmittedFailureRows
            ) {
                rows.append(failureRow)
            }

            if waitingForReplyRow(thread: thread, drafts: detail.drafts, turns: detail.turns) {
                rows.append(
                    ThreadTranscriptEntry(
                        id: "waiting-\(threadID.uuidString)",
                        title: "Waiting for reply",
                        bodyPreview: "No response yet after your last message.",
                        timestamp: thread.updatedAt,
                        statusChip: nil
                    )
                )
            }

            if let postApproval = postApprovalOutboundStatusRowIfNeeded(detail: detail) {
                rows.append(postApproval)
            }

            rows.sort { lhs, rhs in
                if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
                return lhs.id < rhs.id
            }
            #if DEBUG
            ThreadTranscriptDebugLog.logRender(
                threadID: threadID,
                turnCount: detail.turns.count,
                replyTurnCount: replyTurns.count,
                inboxItemCount: inboxRows.count,
                emittedReplyTurns: emittedReplyTurns,
                inboxFallbackCandidates: inboxFallbackCandidates,
                emittedInboxFallbacks: emittedInboxFallbacks,
                skippedFallbackByEnvelope: skippedFallbackByEnvelope,
                skippedFallbackByInboxID: skippedFallbackByInboxID,
                skippedFallbackByBodyOnly: skippedFallbackByBodyOnly,
                finalEntryCount: rows.count
            )
            ExchangeBilateralConversationDebugTrace.logConversationCardLoad(
                detail: detail,
                secondHalfDisplay: secondHalfDisplay,
                rows: rows
            )
            #endif
            return rows
        }

        #if DEBUG
        private enum ThreadTranscriptDebugLog {
            private static let lock = NSLock()
            nonisolated(unsafe) private static var suppressedManualApprovalKeys = Set<String>()
            nonisolated(unsafe) private static var renderSignatures = Set<String>()

            static func logSuppressedManualApproval(threadID: ExchangeThread.ID, turnID: ExchangeTurn.ID) {
                let key = "\(threadID.uuidString)|\(turnID.uuidString)"
                lock.lock()
                defer { lock.unlock() }
                guard suppressedManualApprovalKeys.insert(key).inserted else { return }
                Swift.print(
                    "[ConversationProjection] suppressedManualApproval thread=\(threadID.uuidString) turn=\(turnID.uuidString)"
                )
            }

            static func logRender(
                threadID: ExchangeThread.ID,
                turnCount: Int,
                replyTurnCount: Int,
                inboxItemCount: Int,
                emittedReplyTurns: Int,
                inboxFallbackCandidates: Int,
                emittedInboxFallbacks: Int,
                skippedFallbackByEnvelope: Int,
                skippedFallbackByInboxID: Int,
                skippedFallbackByBodyOnly: Int,
                finalEntryCount: Int
            ) {
                let signature =
                    "\(threadID.uuidString)|turns=\(turnCount)|replyTurns=\(replyTurnCount)|" +
                    "inboxItems=\(inboxItemCount)|finalEntries=\(finalEntryCount)"
                lock.lock()
                defer { lock.unlock() }
                guard renderSignatures.insert(signature).inserted else { return }
                Swift.print(
                    "[ThreadConversationRender] threadID=\(threadID.uuidString) " +
                    "turns=\(turnCount) replyTurns=\(replyTurnCount) inboxItems=\(inboxItemCount) " +
                    "emittedReplyTurns=\(emittedReplyTurns) inboxFallbackCandidates=\(inboxFallbackCandidates) " +
                    "emittedInboxFallbacks=\(emittedInboxFallbacks) skippedFallbackByEnvelope=\(skippedFallbackByEnvelope) " +
                    "skippedFallbackByInboxID=\(skippedFallbackByInboxID) skippedFallbackByBodyOnly=\(skippedFallbackByBodyOnly) " +
                    "finalEntries=\(finalEntryCount)"
                )
            }
        }
        #endif

        // MARK: - Internals

        private static func outboundSentTitle(
            for draft: ExchangeMessageDraft,
            approval: ExchangeApproval?
        ) -> String {
            if draft.metadata["trusted_node_manual_message"] == "true" {
                return "You sent"
            }
            if draft.metadata["second_half_user_directed_outbound_approved"] == "true"
                || approval?.metadata["second_half_user_directed_outbound"] == "true" {
                return "Sent after your approval"
            }
            if isSecretaryOriginatedOutbox(draft: draft, approval: approval) {
                return "Unify sent"
            }
            return "You sent"
        }

        private static func isSecretaryOriginatedOutbox(
            draft: ExchangeMessageDraft,
            approval: ExchangeApproval?
        ) -> Bool {
            if draft.metadata["second_half_auto_response_queued"] == "true"
                || draft.metadata["second_half_auto_response_approved"] == "true"
                || approval?.metadata["second_half_auto_response"] == "true" {
                return true
            }
            if approval?.metadata["second_half_requester_autonomous_outbound"] == "true"
                || draft.metadata["second_half_requester_outbound_approved"] == "true" {
                return true
            }
            if draft.metadata["autonomous_first_contact_queued"] == "true"
                || draft.metadata["autonomous_first_contact_approved"] == "true"
                || approval?.metadata["autonomous_first_contact"] == "true" {
                return true
            }
            return false
        }

        private static func draftPreviewText(_ draft: ExchangeMessageDraft) -> String {
            let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = String(body.prefix(220))
            if let sub = draft.subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                return "\(sub) — \(clipped)"
            }
            return clipped
        }

        private static func normalizedTranscriptBodyMatchKey(_ raw: String) -> String {
            raw.split(whereSeparator: { $0.isNewline || $0.isWhitespace }).joined(separator: " ").lowercased()
        }

        private static func inboundTranscriptBodyMatchKeys(for detail: ExchangeModels.ThreadDetail) -> Set<String> {
            let threadID = detail.thread.id
            var keys = Set<String>()
            for turn in detail.turns where turn.kind == .replyReceived {
                let raw = (turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(\.nilIfBlank)
                    ?? turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                keys.insert(normalizedTranscriptBodyMatchKey(raw))
            }
            for item in detail.inboxItems {
                guard item.threadID == threadID else { continue }
                switch item.processingState {
                case .reconciledIntoThread, .received, .deferred:
                    break
                default:
                    continue
                }
                let preview = inboxBodyPreview(item)
                guard !preview.isEmpty else { continue }
                keys.insert(normalizedTranscriptBodyMatchKey(preview))
            }
            return keys
        }

        private static func secondHalfDraftBodyMatchesDisplayPreview(
            draft: ExchangeMessageDraft,
            secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel
        ) -> Bool {
            let preview = secondHalfDisplay.draft?.bodyPreview.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !preview.isEmpty else { return false }
            let bodyKey = normalizedTranscriptBodyMatchKey(String(draft.body.prefix(8192)))
            let previewKey = normalizedTranscriptBodyMatchKey(preview)
            guard !previewKey.isEmpty else { return false }
            if bodyKey.hasPrefix(previewKey) { return true }
            if previewKey.hasPrefix(String(bodyKey.prefix(min(bodyKey.count, previewKey.count)))) { return true }
            return false
        }

        /// Suppresses transcript rows that duplicate the main second-half draft card (projection-only; no store writes).
        ///
        /// Callers must already filter open drafts through `userFacingRenderableExternalOutboundDraftIDs`.
        /// Do not gate on a second global `hasUserFacing...` check (that incorrectly blocked dedupe when no draft passed).
        private static func shouldSuppressSecondHalfDraftTranscriptRow(
            draft: ExchangeMessageDraft,
            detail: ExchangeModels.ThreadDetail,
            secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel?,
            secondHalfOpenOutboundDraftCount: Int
        ) -> Bool {
            guard let secondHalfDisplay else { return false }
            guard draft.metadata["second_half_generated"] == "true" else { return false }
            guard draft.audience == .externalCounterparty else { return false }
            switch draft.status {
            case .draft, .awaitingApproval:
                break
            default:
                return false
            }

            if secondHalfOpenOutboundDraftCount <= 1 {
                return true
            }

            return secondHalfDraftBodyMatchesDisplayPreview(draft: draft, secondHalfDisplay: secondHalfDisplay)
        }

        private static func transcriptDraftDebugBodyPrefix(_ body: String, maxLen: Int = 80) -> String {
            let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count > maxLen else { return t }
            return String(t.prefix(maxLen)) + "…"
        }

        private static func inboxBodyPreview(_ item: ExchangeInboxItem) -> String {
            let parts = [
                item.metadata["body_preview"],
                item.visibleSummary,
                item.metadata["subject_preview"]
            ]
            for p in parts {
                let t = p?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !t.isEmpty { return String(t.prefix(400)) }
            }
            return "Inbound message received."
        }

        private static func normalizedInboundSourceID(_ raw: String?) -> String? {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return nil }
            return trimmed.lowercased()
        }

        private static func shouldSuppressManualMessageApprovalTranscriptRow(_ turn: ExchangeTurn) -> Bool {
            let summary = turn.summary.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let detail = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let source = turn.metadata["source"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

            let metadataHit =
                turn.metadata["trusted_node_manual_message"] == "true"
                || turn.metadata["inbound_provider_manual_reply"] == "true"
                || turn.metadata["conversation_card_manual_outbound"] == "true"

            let tokenHit =
                summary == "trusted_node_manual_message"
                || detail == "trusted_node_manual_message"
                || summary == "inbound_provider_manual_reply"
                || detail == "inbound_provider_manual_reply"
                || source == "trusted_node_manual_message"
                || source == "inbound_provider_manual_reply"
                || isInternalTranscriptMetadataToken(summary)
                || isInternalTranscriptMetadataToken(detail)
                || isInternalTranscriptMetadataToken(source)

            let visibleScaffoldHit =
                summary.contains("manual reply approved")
                || detail.contains("manual reply approved")
                || summary.contains("message approved")
                || detail.contains("message approved")

            return metadataHit || tokenHit || visibleScaffoldHit
        }

        private static func isConversationCardManualOutboundDraft(_ draft: ExchangeMessageDraft) -> Bool {
            guard draft.metadata["conversation_card_manual_outbound"] == "true" else { return false }
            guard draft.metadata["trusted_node_manual_message"] != "true" else { return false }
            guard draft.metadata["second_half_generated"] != "true" else { return false }
            return true
        }

        private static func isInternalTranscriptMetadataToken(_ raw: String) -> Bool {
            let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lowered.isEmpty else { return false }
            let internalTokens: Set<String> = [
                "conversation_card_manual_outbound",
                "trusted_node_manual_message",
                "inbound_provider_manual_reply",
                "second_half_generated",
                "direct_message_thread",
                "dm_manual_v2",
                "payload_kind",
                "direct_message",
            ]
            if internalTokens.contains(lowered) { return true }
            if lowered.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                return internalTokens.contains(where: { lowered.contains($0) })
            }
            return false
        }

        private static func approvalGrantedRowPresentation(rawText: String, turn: ExchangeTurn) -> (String, String) {
            let t = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = t.lowercased()
            let trustedManual =
                turn.metadata["trusted_node_manual_message"] == "true"
                || lowered == "trusted_node_manual_message"
                || t == "trusted_node_manual_message"
            if trustedManual {
                return ("Message approved", scrubUserFacing("Manual reply approved."))
            }
            if t.isEmpty {
                return ("You approved", "")
            }
            if lowered.contains("trusted_node_manual") && t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                return ("Message approved", scrubUserFacing("Manual reply approved."))
            }
            return ("You approved", scrubUserFacing(String(t.prefix(300))))
        }

        private static func userFacingTranscriptEntry(for turn: ExchangeTurn) -> ThreadTranscriptEntry? {
            let text = (turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(\.nilIfBlank)
                ?? turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty || turn.kind == .approvalGranted else { return nil }

            switch turn.kind {
            case .requestCaptured:
                return ThreadTranscriptEntry(
                    id: "turn-request-\(turn.id.uuidString)",
                    title: "You asked",
                    bodyPreview: scrubUserFacing(String(text.prefix(400))),
                    timestamp: turn.createdAt
                )
            case .clarificationAnswered:
                return ThreadTranscriptEntry(
                    id: "turn-clarification-answered-\(turn.id.uuidString)",
                    title: "You answered",
                    bodyPreview: scrubUserFacing(String(text.prefix(400))),
                    timestamp: turn.createdAt
                )
            case .approvalGranted:
                if shouldSuppressManualMessageApprovalTranscriptRow(turn) {
                    #if DEBUG
                    ThreadTranscriptDebugLog.logSuppressedManualApproval(
                        threadID: turn.threadID,
                        turnID: turn.id
                    )
                    #endif
                    return nil
                }
                let (approvalTitle, approvalBody) = approvalGrantedRowPresentation(rawText: text, turn: turn)
                return ThreadTranscriptEntry(
                    id: "turn-approval-granted-\(turn.id.uuidString)",
                    title: approvalTitle,
                    bodyPreview: approvalBody,
                    timestamp: turn.createdAt
                )
            case .approvalRejected:
                return ThreadTranscriptEntry(
                    id: "turn-approval-rejected-\(turn.id.uuidString)",
                    title: "You declined",
                    bodyPreview: scrubUserFacing(String(text.prefix(300))),
                    timestamp: turn.createdAt
                )
            case .threadResolved:
                return ThreadTranscriptEntry(
                    id: "turn-resolved-\(turn.id.uuidString)",
                    title: "Thread completed",
                    bodyPreview: scrubUserFacing(String(text.prefix(300))),
                    timestamp: turn.createdAt
                )
            default:
                return nil
            }
        }

        /// User-visible titles for outbound-phase mapping.
        private static let transcriptSendingTitle = "Sending"
        private static let transcriptDraftReadyTitle = "Draft ready"
        private static let transcriptCouldntSendTitle = "Couldn’t send"

        private static func outboxCandidatesForDraft(
            draftID: ExchangeMessageDraft.ID,
            threadID: ExchangeThread.ID,
            outboxItems: [ExchangeOutboxItem]
        ) -> [ExchangeOutboxItem] {
            outboxItems.filter { $0.threadID == threadID && $0.draftID == draftID }
                .sorted {
                    if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
        }

        /// Active outbox awaiting relay finalize: queued / prerequisite / defer / sending, plus `.sent`
        /// outbox-phase only while the draft remains unsent (rare transient desync guard).
        private static func prioritizedOutboxItemIndicatingSending(
            draftID: ExchangeMessageDraft.ID,
            threadID: ExchangeThread.ID,
            outboxItems: [ExchangeOutboxItem]
        ) -> ExchangeOutboxItem? {
            for item in outboxCandidatesForDraft(draftID: draftID, threadID: threadID, outboxItems: outboxItems) {
                if transcriptOutboxIndicatesSending(for: item) {
                    return item
                }
            }
            return nil
        }

        /// Phases mapped to **Sending** while `draft.status` is not yet `.sent`.
        ///
        /// - **queued / blockedByPrerequisite / deferred / sending:** active outbound work awaiting completion.
        /// - **sent (outbox phase):** local hand-off before acknowledgement; retained when draft is still `.approved` transiently.
        private static func transcriptOutboxIndicatesSending(for item: ExchangeOutboxItem) -> Bool {
            switch item.deliveryState.phase {
            case .queued, .blockedByPrerequisite, .deferred, .sending:
                return item.isActive
            case .sent:
                return true
            case .acknowledged, .failed, .cancelledBeforeSend, .tooLateToCancel, .incompatible:
                return false
            }
        }

        private static func inboundReceivedRowTitle(
            turnDate: Date,
            momentKey: String,
            winning: (Date, String)?
        ) -> String {
            guard let w = winning else { return "Received" }
            if w.0 == turnDate && w.1 == momentKey {
                return "Just received"
            }
            return "Received"
        }

        private static func prioritizedOutboxItemIndicatingFailure(
            draftID: ExchangeMessageDraft.ID,
            threadID: ExchangeThread.ID,
            outboxItems: [ExchangeOutboxItem]
        ) -> ExchangeOutboxItem? {
            for item in outboxCandidatesForDraft(draftID: draftID, threadID: threadID, outboxItems: outboxItems) {
                guard transcriptOutboxIndicatesTerminalFailure(for: item) else { continue }
                return item
            }
            return nil
        }

        private static func transcriptOutboxIndicatesTerminalFailure(for item: ExchangeOutboxItem) -> Bool {
            switch item.deliveryState.phase {
            case .failed, .incompatible:
                return true
            default:
                return false
            }
        }

        private static func failureNote(from failedItem: ExchangeOutboxItem) -> String {
            let trimmed = failedItem.deliveryState.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
            return "The last send did not go through."
        }

        private static func deliveryFailureRow(
            thread: ExchangeThread,
            outbox: [ExchangeOutboxItem],
            suppressedFailureDraftIDs: Set<ExchangeMessageDraft.ID>
        ) -> ThreadTranscriptEntry? {
            var stamp = thread.updatedAt
            var message: String?

            if case .blockedByDeliveryFailure = thread.state {
                if let f = thread.latestFailure {
                    stamp = f.createdAt
                    message = f.visibleExplanation
                } else if let n = thread.delivery?.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                    message = n
                } else {
                    message = "The last send did not go through."
                }
            } else if thread.delivery?.status == .failed {
                stamp = thread.delivery?.lastAttemptAt ?? thread.updatedAt
                message = thread.delivery?.note ?? thread.latestFailure?.visibleExplanation
            } else if let f = thread.latestFailure, f.kind == .deliveryFailure {
                stamp = f.createdAt
                message = f.visibleExplanation
            }

            let failedOutbox = outbox
                .filter { $0.threadID == thread.id }
                .filter {
                    switch $0.deliveryState.phase {
                    case .failed, .incompatible:
                        return true
                    default:
                        return false
                    }
                }
                .filter { !suppressedFailureDraftIDs.contains($0.draftID) }
                .max(by: { $0.updatedAt < $1.updatedAt })

            if message == nil, let ob = failedOutbox {
                stamp = ob.updatedAt
                message = ob.deliveryState.note ?? "The last send did not go through."
            }

            guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
                return nil
            }

            return ThreadTranscriptEntry(
                id: "delivery-fail-\(thread.id.uuidString)",
                title: transcriptCouldntSendTitle,
                bodyPreview: scrubUserFacing(text),
                timestamp: stamp,
                statusChip: nil
            )
        }

        private static func waitingForReplyRow(
            thread: ExchangeThread,
            drafts: [ExchangeMessageDraft],
            turns: [ExchangeTurn]
        ) -> Bool {
            guard case .awaitingResponse = thread.state else { return false }
            guard thread.latestFailure == nil else { return false }
            guard thread.delivery?.status != .failed else { return false }

            if ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(in: drafts, thread: thread, turns: turns) {
                #if DEBUG
                Swift.print(
                    "[WaitingReplyProjection] suppressedWaitingBecauseActionableDraft thread=\(thread.id.uuidString)"
                )
                #endif
                return false
            }

            let sentOutbound = drafts
                .filter { $0.audience == .externalCounterparty && $0.status == .sent }
            guard let lastSent = sentOutbound.max(by: { $0.updatedAt < $1.updatedAt }) else { return false }

            let lastSentAt = lastSent.updatedAt
            let replyAfter = turns.contains { turn in
                turn.kind == .replyReceived && turn.createdAt > lastSentAt
            }
            return !replyAfter
        }

        private static func postApprovalOutboundStatusRowIfNeeded(
            detail: ExchangeModels.ThreadDetail
        ) -> ThreadTranscriptEntry? {
            guard let grantTurn = detail.turns
                .filter({ $0.kind == .approvalGranted })
                .max(by: { $0.createdAt < $1.createdAt })
            else {
                return nil
            }

            let pivot = grantTurn.createdAt
            if hasOutboundPipelineEvidence(after: pivot, detail: detail) {
                return nil
            }

            if providerInboundNeedsUserInputBeforeOutbound(detail: detail) {
                return ThreadTranscriptEntry(
                    id: "post-approval-reply-status-\(grantTurn.id.uuidString)",
                    title: "After your approval",
                    bodyPreview: scrubUserFacing(
                        "Approval recorded. Unify needs your input before it can send a reply."
                    ),
                    timestamp: pivot.addingTimeInterval(0.001),
                    statusChip: nil
                )
            }

            let reason = postApprovalNoSendReason(detail: detail)
            return ThreadTranscriptEntry(
                id: "post-approval-reply-status-\(grantTurn.id.uuidString)",
                title: "After your approval",
                bodyPreview: scrubUserFacing("Approval recorded. Nothing has been sent yet — \(reason)."),
                timestamp: pivot.addingTimeInterval(0.001),
                statusChip: nil
            )
        }

        private static func hasOutboundPipelineEvidence(
            after pivot: Date,
            detail: ExchangeModels.ThreadDetail
        ) -> Bool {
            let threadID = detail.thread.id
            if detail.drafts.contains(where: { draft in
                draft.audience == .externalCounterparty
                    && draft.status == .sent
                    && draft.updatedAt >= pivot
            }) {
                return true
            }

            if let delivery = detail.thread.delivery, delivery.status == .sent,
               let at = delivery.lastAttemptAt ?? delivery.lastConfirmedSendAt, at >= pivot {
                return true
            }

            return detail.outboxItems.contains { ob in
                guard ob.threadID == threadID else { return false }
                guard ob.updatedAt >= pivot else { return false }
                switch ob.deliveryState.phase {
                case .queued, .blockedByPrerequisite, .deferred, .sending, .sent:
                    return true
                case .acknowledged, .failed, .cancelledBeforeSend, .tooLateToCancel, .incompatible:
                    return false
                }
            }
        }

        private static func providerInboundNeedsUserInputBeforeOutbound(
            detail: ExchangeModels.ThreadDetail
        ) -> Bool {
            guard let sh = detail.secondHalfDisplay else { return false }
            guard sh.status.role.caseInsensitiveCompare(ExchangeSecondHalfRole.provider.displayTitle) == .orderedSame else {
                return false
            }
            if sh.placement == .needsInput { return true }
            if sh.agencyPhase == .needsUserInput { return true }
            if sh.nextMove?.needsUserInput == true { return true }
            if sh.nextMove?.actionRaw == ExchangeSecondHalfAction.requestUserInput.rawValue { return true }
            return false
        }

        private static func postApprovalNoSendReason(detail: ExchangeModels.ThreadDetail) -> String {
            if let note = detail.thread.delivery?.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                return note
            }
            if let step = detail.thread.workTrace?.steps.last(where: { $0.key == "coordination_input_needed_after_approval" }),
               let d = step.detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                return d
            }
            if let headline = detail.thread.workTrace?.headline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                return headline
            }
            return "this couldn’t be queued or sent yet"
        }

        /// Removes internal vocabulary from user-visible transcript strings (best-effort).
        ///
        /// Uses phrase + whole-word scrubbing so benign words like “permutation” are not corrupted
        /// by substring removal of “mutation”.
        public static func scrubUserFacing(_ raw: String) -> String {
            var s = scrubUserFacingInternalPhrases(raw)
            s = scrubUserFacingInternalWholeWords(s)
            return scrubUserFacingCollapseWhitespace(s)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func scrubUserFacingInternalPhrases(_ raw: String) -> String {
            var s = replaceAllMatches(
                pattern: #"(?:second[\s_-]+half|second_half)"#,
                in: raw,
                replacement: " "
            )
            s = replaceAllMatches(
                pattern:
                    #"\b(?:conversation_card_manual_outbound|trusted_node_manual_message|inbound_provider_manual_reply|second_half_generated|direct_message_thread|dm_manual_v2|payload_kind|direct_message)\b"#,
                in: s,
                replacement: " "
            )
            s = replaceAllMatches(
                pattern: #"(?:approval_source|permit|conversation_surface)\b"#,
                in: s,
                replacement: " ",
                options: [.caseInsensitive]
            )
            return s
        }

        private static func scrubUserFacingInternalWholeWords(_ raw: String) -> String {
            replaceAllMatches(
                pattern:
                #"\b(?:relay|envelope|envelopes|outbox|metadata|execution|trace|agency|mutation|pipeline|autonomous|projection)\b"#,
                in: raw,
                replacement: " "
            )
        }

        private static func scrubUserFacingCollapseWhitespace(_ raw: String) -> String {
            raw
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        private static func replaceAllMatches(
            pattern: String,
            in text: String,
            replacement: String,
            options: NSRegularExpression.Options = [.caseInsensitive]
        ) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                return text
            }
            let span = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.stringByReplacingMatches(in: text, options: [], range: span, withTemplate: replacement)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
