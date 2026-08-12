import XCTest
import Foundation
import AnumCore

/// Coverage for `ExchangeModels.ThreadTranscriptBuilder` (Conversation projection).
@MainActor
final class SecretaryThreadTranscriptTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_720_000_000)

    // MARK: - Classification

    func test_trustedNodeManualDraft_sent_titleYouSent() {
        let tid = UUID()
        let draftID = UUID()
        let draft = sentExternalDraft(
            id: draftID,
            threadID: tid,
            body: "Hello there",
            metadata: ["trusted_node_manual_message": "true"]
        )
        let detail = makeDetail(
            thread: baseThread(id: tid, state: .draftReady(.init(preparedAt: t0, summary: "ok"))),
            drafts: [draft]
        )
        let row = assertSingleSentRow(in: detail, draftID: draftID)
        XCTAssertEqual(row.title, "You sent")
    }

    func test_secondHalfAutoResponseDraft_sent_titleUnifySent() {
        let tid = UUID()
        let draftID = UUID()
        let draft = sentExternalDraft(
            id: draftID,
            threadID: tid,
            body: "Auto follow-up",
            metadata: ["second_half_auto_response_approved": "true"]
        )
        let detail = makeDetail(thread: baseThread(id: tid), drafts: [draft])
        let row = assertSingleSentRow(in: detail, draftID: draftID)
        XCTAssertEqual(row.title, "Unify sent")
    }

    func test_secondHalfRequesterAutonomousOutboundApproval_sent_titleUnifySent() {
        let tid = UUID()
        let draftID = UUID()
        let draft = sentExternalDraft(id: draftID, threadID: tid, body: "Outbound", metadata: [:])
        let approval = ExchangeApproval(
            threadID: tid,
            kind: .outboundSend,
            requestedAction: .sendMessage,
            draftID: draftID,
            summary: "Send",
            metadata: ["second_half_requester_autonomous_outbound": "true"]
        )
        let detail = makeDetail(thread: baseThread(id: tid), approvals: [approval], drafts: [draft])
        let row = assertSingleSentRow(in: detail, draftID: draftID)
        XCTAssertEqual(row.title, "Unify sent")
    }

    func test_secondHalfRequesterOutboundApprovedOnDraft_sent_titleUnifySent() {
        let tid = UUID()
        let draftID = UUID()
        let draft = sentExternalDraft(
            id: draftID,
            threadID: tid,
            body: "Approved path",
            metadata: ["second_half_requester_outbound_approved": "true"]
        )
        let detail = makeDetail(thread: baseThread(id: tid), drafts: [draft])
        let row = assertSingleSentRow(in: detail, draftID: draftID)
        XCTAssertEqual(row.title, "Unify sent")
    }

    func test_secondHalfUserDirectedDraft_sent_titleSentAfterYourApproval() {
        let tid = UUID()
        let draftID = UUID()
        let draft = sentExternalDraft(
            id: draftID,
            threadID: tid,
            body: "As you asked",
            metadata: ["second_half_user_directed_outbound_approved": "true"]
        )
        let detail = makeDetail(thread: baseThread(id: tid), drafts: [draft])
        let row = assertSingleSentRow(in: detail, draftID: draftID)
        XCTAssertEqual(row.title, "Sent after your approval")
    }

    func test_postApprovalWithoutOutbound_surfacesReplyStatusWhenProviderNeedsInput() {
        let tid = UUID()
        let grant = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(200),
            actor: .user,
            kind: .approvalGranted,
            summary: "Approval granted",
            detail: "You approved sending the prepared reply."
        )
        var sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .needsInput,
            agencyPhase: .needsUserInput,
            statusRole: ExchangeSecondHalfRole.provider.displayTitle
        )
        sh.nextMove = ExchangeSecondHalfUIAdapter.NextMove(
            action: "Needs your input",
            actionRaw: ExchangeSecondHalfAction.requestUserInput.rawValue,
            title: "Add detail",
            rationale: "Missing commercial facts.",
            requiredInputs: [],
            needsGeneration: false,
            needsUserInput: true,
            needsApproval: false,
            isAutonomous: false,
            isBlockingOnHuman: true
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [grant], secondHalfDisplay: sh)
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertTrue(
            rows.contains { row in
                row.title == "After your approval"
                    && row.bodyPreview.localizedCaseInsensitiveContains("approval recorded")
                    && row.bodyPreview.localizedCaseInsensitiveContains("needs your input")
            },
            "Expected reply outcome row, got: \(rows.map(\.title))"
        )
    }

    func test_unsentPreparedDraft_titleDraftReady() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(3),
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Still editing this note.",
            posture: ExchangePosture()
        )
        let detail = makeDetail(
            thread: baseThread(id: tid, selectedCounterpartyID: fixtureRecipientAnchorCP),
            drafts: [draft]
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertTrue(rows.contains { $0.title == "Draft ready" && $0.bodyPreview.contains("Still editing") })
    }

    func test_unsentPreparedDraft_withoutRecipientAnchor_suppressesDraftReadyRow() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(3),
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "LLM preview without routing anchor.",
            posture: ExchangePosture(),
            metadata: ["second_half_generated": "true"]
        )
        let detail = makeDetail(
            thread: baseThread(id: tid, state: .noViableMatch(.init(searchedAt: t0, explanation: "None"))),
            drafts: [draft]
        )
        XCTAssertFalse(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: detail.thread))
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertFalse(rows.contains { $0.title == "Draft ready" })
    }

    func test_approvedExternalDraft_queuedOutbox_sameDraft_titleSending() {
        let tid = UUID()
        let draftID = UUID()
        let draft = approvedExternalDraft(
            id: draftID,
            threadID: tid,
            body: "Queued copy for delivery."
        )
        let outbox = fixtureOutbox(threadID: tid, draftID: draftID, phase: .queued)
        let detail = makeDetail(
            thread: baseThread(id: tid, selectedCounterpartyID: fixtureRecipientAnchorCP),
            drafts: [draft],
            outboxItems: [outbox]
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let sending = rows.filter { $0.title == "Sending…" }
        XCTAssertEqual(sending.count, 1)
        XCTAssertTrue(sending[0].bodyPreview.contains("Queued copy"))
        XCTAssertFalse(rows.contains { $0.title == "Draft ready" && $0.id == "draft-open-\(draftID.uuidString)" })
    }

    func test_approvedExternalDraft_sendingOutbox_sameDraft_titleSending() {
        let tid = UUID()
        let draftID = UUID()
        let draft = approvedExternalDraft(id: draftID, threadID: tid, body: "In-flight body.")
        let outbox = fixtureOutbox(threadID: tid, draftID: draftID, phase: .sending)
        let detail = makeDetail(
            thread: baseThread(id: tid, selectedCounterpartyID: fixtureRecipientAnchorCP),
            drafts: [draft],
            outboxItems: [outbox]
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertEqual(rows.filter { $0.title == "Sending…" }.count, 1)
        XCTAssertNil(rows.first { $0.id == "draft-open-\(draftID.uuidString)" })
    }

    func test_failedOutbox_matchingDraft_emitsDraftScopedCouldntSend() {
        let tid = UUID()
        let draftID = UUID()
        let draft = approvedExternalDraft(id: draftID, threadID: tid, body: "This did not arrive.")
        let outbox = fixtureOutbox(
            threadID: tid,
            draftID: draftID,
            phase: .failed,
            isActive: false,
            note: "Remote service unreachable in fixture."
        )
        let detail = makeDetail(
            thread: baseThread(id: tid, selectedCounterpartyID: fixtureRecipientAnchorCP),
            drafts: [draft],
            outboxItems: [outbox]
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let fails = rows.filter { $0.title == "Couldn’t send" }
        XCTAssertEqual(fails.count, 1)
        XCTAssertEqual(fails.first?.id, "draft-send-failed-\(draftID.uuidString)")
        XCTAssertTrue(fails.first?.bodyPreview.localizedStandardContains("unreachable") ?? false)
    }

    func test_approvedExternalDraft_withoutOutbox_suppressesDraftReadyRow() {
        let tid = UUID()
        let draftID = UUID()
        let draft = approvedExternalDraft(id: draftID, threadID: tid, body: "Approved but never queued.")
        let detail = makeDetail(
            thread: baseThread(id: tid, selectedCounterpartyID: fixtureRecipientAnchorCP),
            drafts: [draft]
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertFalse(rows.contains { $0.id == "draft-open-\(draftID.uuidString)" })
        XCTAssertFalse(rows.contains { $0.title == "Draft ready" })
        XCTAssertFalse(rows.contains { $0.title == "Sending…" })
    }

    func test_queuedOutbox_sameDraft_emitsSingleTranscriptOutboundRow() {
        let tid = UUID()
        let draftID = UUID()
        let draft = approvedExternalDraft(id: draftID, threadID: tid, body: "Single row sanity.")
        let outbox = fixtureOutbox(threadID: tid, draftID: draftID, phase: .queued)
        let detail = makeDetail(
            thread: baseThread(id: tid, selectedCounterpartyID: fixtureRecipientAnchorCP),
            drafts: [draft],
            outboxItems: [outbox]
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let tiedToDraft = rows.filter {
            $0.id.contains(draftID.uuidString) && !$0.id.hasPrefix("waiting-") && !$0.id.hasPrefix("delivery-fail")
        }
        XCTAssertEqual(tiedToDraft.count, 1)
    }

    func test_ambiguousSentDraft_titleSent() {
        let tid = UUID()
        let draftID = UUID()
        let draft = sentExternalDraft(id: draftID, threadID: tid, body: "Plain send", metadata: [:])
        let detail = makeDetail(thread: baseThread(id: tid), drafts: [draft])
        let row = assertSingleSentRow(in: detail, draftID: draftID)
        XCTAssertEqual(row.title, "Sent")
    }

    func test_replyReceivedTurn_titleTheyReplied() {
        let tid = UUID()
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(10),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Thanks, sounds good.",
            detail: "We can meet Tuesday."
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [turn], drafts: [])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let reply = rows.first { row in
            row.title == "Inbound message" || row.title.hasPrefix("Message from")
        }
        XCTAssertNotNil(reply)
        XCTAssertEqual(reply?.bodyPreview.trimmingCharacters(in: .whitespacesAndNewlines), "We can meet Tuesday.")
    }

    func test_replyReceived_prefersCounterpartyDisplay_andTrustChip() {
        let tid = UUID()
        let node = "node-abcdef12"
        let cp = ExchangeCounterparty(
            id: node,
            kind: .person,
            displayName: "Hansen Studio",
            source: .relayNetwork,
            trust: ExchangeCounterparty.TrustSnapshot(level: .high)
        )
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: t0,
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Hello",
            detail: "Hey Hansen.",
            metadata: ["source_sender_node_id": node]
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [turn], counterparties: [cp])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let row = rows.first { $0.id.hasPrefix("turn-reply-") }
        XCTAssertNotNil(row)
        XCTAssertTrue(row!.title.contains("Hansen Studio"))
        XCTAssertEqual(row?.statusChip, "Known contact")
    }

    func test_requestCapturedTurn_isVisibleAsYouAsked() {
        let tid = UUID()
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: t0,
            actor: .user,
            kind: .requestCaptured,
            summary: "Find a roofer in Aurora tomorrow."
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [turn], drafts: [])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let asked = rows.first { $0.id.hasPrefix("turn-request-") }
        XCTAssertNotNil(asked)
        XCTAssertEqual(asked?.title, "You asked")
    }

    func test_internalSystemTurns_areNotProjectedAsConversationRows() {
        let tid = UUID()
        let internalTurn = ExchangeTurn(
            threadID: tid,
            createdAt: t0,
            actor: .system,
            kind: .systemNotice,
            summary: "state mutated projection recalculated"
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [internalTurn], drafts: [])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertTrue(rows.isEmpty, "System/internal turns should not appear in user transcript")
    }

    func test_sentAwaitingResponse_noLaterReply_showsWaitingForReply() {
        let tid = UUID()
        let sentAt = t0.addingTimeInterval(5)
        let draft = sentExternalDraft(
            id: UUID(),
            threadID: tid,
            body: "Ping",
            metadata: [:],
            updatedAt: sentAt
        )
        let thread = baseThread(
            id: tid,
            state: .awaitingResponse(.init(since: sentAt.addingTimeInterval(1), lastOutboundAt: sentAt)),
            updatedAt: sentAt.addingTimeInterval(20)
        )
        let detail = makeDetail(thread: thread, turns: [], drafts: [draft])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertTrue(rows.contains { $0.title == "Waiting for reply" })
    }

    func test_failedDelivery_showsCouldntSend() {
        let tid = UUID()
        let thread = ExchangeThread(
            id: tid,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(30),
            mode: .transactional,
            intent: fixtureIntent(),
            posture: ExchangePosture(),
            state: .draftReady(.init(preparedAt: t0, summary: "x")),
            delivery: .init(status: .failed, lastAttemptAt: t0.addingTimeInterval(25), note: "Network path unavailable.")
        )
        let detail = makeDetail(thread: thread, drafts: [])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let fail = rows.first { $0.title == "Couldn’t send" }
        XCTAssertNotNil(fail)
        XCTAssertTrue(fail?.bodyPreview.contains("Network") == true)
    }

    func test_transcriptUserFacingStrings_containNoBannedVocabulary() {
        let tid = UUID()
        let draft = sentExternalDraft(
            id: UUID(),
            threadID: tid,
            body: "Hello — internal note mentions RELAY and ENVELOPE for scrub test.",
            metadata: ["trusted_node_manual_message": "true"]
        )
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(2),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Got it",
            detail: "OUTBOX METADATA autonomous agency second_half trace"
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [turn], drafts: [draft])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        assertNoBannedSubstrings(in: rows)
    }

    // MARK: - Anchored potential match / Conversation contract

    /// Mirrors ``SecretaryThreadTranscriptView`` inputs: same `ThreadDetail` + optional second-half display.
    func test_threadTranscript_matchesSecretaryThreadTranscriptView_builderContract() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(1),
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Contract line uses same builder as Conversation card.",
            posture: ExchangePosture(),
            metadata: ["second_half_generated": "true"]
        )
        let thread = baseThread(
            id: tid,
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Incomplete signal")),
            selectedCounterpartyID: fixtureRecipientAnchorCP
        )
        let detail = makeDetail(thread: thread, drafts: [draft])
        let a = ExchangeModels.ThreadTranscriptBuilder.build(from: detail, secondHalfDisplay: nil)
        let b = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertEqual(
            a.map { $0.id },
            b.map { $0.id }
        )
    }

    func test_threadTranscript_includesPersistedRenderableDraftForAnchoredPotentialMatch() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(2),
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Could you confirm whether seller financing or VTB terms are being considered?",
            posture: ExchangePosture(),
            metadata: ["second_half_generated": "true"]
        )
        let thread = baseThread(
            id: tid,
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak candidates")),
            selectedCounterpartyID: fixtureRecipientAnchorCP,
            selectedOfferID: "offer-anchored-1"
        )
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: t0,
            actor: .user,
            kind: .requestCaptured,
            summary: "Seeking seller financing in Aurora."
        )
        let detail = makeDetail(thread: thread, turns: [turn], drafts: [draft])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let draftRows = rows.filter { $0.title == "Draft ready" }
        XCTAssertEqual(draftRows.count, 1)
        XCTAssertTrue(draftRows[0].bodyPreview.localizedStandardContains("VTB"))
        assertTranscriptProjectionBannedFree(rows)
    }

    func test_threadTranscript_excludesDraftWhenNoRecipientAnchor() {
        let tid = UUID()
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: tid,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(3),
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Should not appear without anchor.",
            posture: ExchangePosture(),
            metadata: ["second_half_generated": "true"]
        )
        let thread = baseThread(
            id: tid,
            state: .matchCandidatesWeak(.init(candidateCount: 1, explanation: "Weak")),
            selectedCounterpartyID: nil,
            selectedOfferID: nil
        )
        let detail = makeDetail(thread: thread, drafts: [draft])
        XCTAssertFalse(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: detail.thread))
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertFalse(rows.contains { $0.title == "Draft ready" })
    }

    func test_threadTranscript_sentOutboundAppearsAsSentNotDraftReady() {
        let tid = UUID()
        let draftID = UUID()
        let draft = sentExternalDraft(
            id: draftID,
            threadID: tid,
            body: "Autonomous VTB inquiry sent.",
            metadata: ["second_half_requester_outbound_approved": "true"]
        )
        let thread = baseThread(id: tid, selectedCounterpartyID: fixtureRecipientAnchorCP)
        let detail = makeDetail(thread: thread, drafts: [draft])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertEqual(rows.filter { $0.id == "draft-open-\(draftID.uuidString)" }.count, 0)
        XCTAssertEqual(rows.filter { $0.id == "draft-sent-\(draftID.uuidString)" }.count, 1)
        XCTAssertEqual(rows.first { $0.id == "draft-sent-\(draftID.uuidString)" }?.title, "Unify sent")
        XCTAssertFalse(rows.contains { $0.title == "Draft ready" && $0.bodyPreview.contains("Autonomous VTB") })
    }

    func test_providerInbound_replyReceivedSurfacesAsTheyRepliedConversationRow() {
        let tid = UUID()
        var thread = baseThread(id: tid, state: .drafting)
        thread.metadata["inbound_thread"] = "true"

        let ask = "What are your rates for a two-hour session on June 14?"
        let reply = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(5),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Inbound ask",
            detail: ask
        )
        let detail = makeDetail(thread: thread, turns: [reply])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)

        let replyRows = rows.filter { row in
            row.title == "Inbound message" || row.title.hasPrefix("Message from")
        }
        XCTAssertEqual(replyRows.count, 1, "Expected a single first-class inbound reply row: \(rows.map { $0.title })")
        XCTAssertTrue(replyRows[0].bodyPreview.localizedStandardContains("june 14"))
        assertTranscriptProjectionBannedFree(rows)
    }

    func test_threadTranscriptBuilder_userFacingStringsContainNoneOfBannedVocabulary() {
        let tid = UUID()
        let polluted = """
        Words to strip: relay envelope outbox metadata execution trace agency mutation pipeline
        second_half autonomous and second half headings.
        """
        let benign = "Permutation puzzles stay readable."
        let draft = sentExternalDraft(
            id: UUID(),
            threadID: tid,
            body: "Thanks for your note.",
            metadata: ["trusted_node_manual_message": "true"]
        )
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(2),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Reply summary",
            detail: polluted + "\n" + benign
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [turn], drafts: [draft])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        assertTranscriptProjectionBannedFree(rows)
        let replyPreview = rows.first { row in
            row.title == "Inbound message" || row.title.hasPrefix("Message from")
        }?.bodyPreview ?? ""
        XCTAssertTrue(replyPreview.localizedStandardContains("permutation"))
    }

    func test_inboundTranscript_replyTurnWithSourceEnvelope_emitsSingleInboundRow() {
        let tid = UUID()
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(8),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Summary text",
            detail: "Inbound body from counterparty.",
            metadata: ["source_envelope_id": "env-1"]
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [turn])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertEqual(rows.filter { $0.id.hasPrefix("turn-reply-") }.count, 1)
        XCTAssertEqual(rows.filter { $0.id.hasPrefix("inbox-fallback-") }.count, 0)
    }

    func test_inboundTranscript_replyTurnPlusMatchingInbox_emitsSingleRow_prefersTurn() {
        let tid = UUID()
        let inboxID = UUID()
        let turn = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(10),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Same envelope",
            detail: "Turn text wins.",
            metadata: ["source_envelope_id": "env-match", "source_inbox_item_id": inboxID.uuidString]
        )
        let inbox = ExchangeInboxItem(
            id: inboxID,
            receivedAt: t0.addingTimeInterval(10),
            updatedAt: t0.addingTimeInterval(10),
            envelopeID: "env-match",
            threadID: tid,
            processingState: .reconciledIntoThread,
            visibleSummary: "Inbox fallback text",
            metadata: ["body_preview": "Inbox fallback text"]
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [turn], inboxItems: [inbox])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertEqual(rows.filter { $0.id.hasPrefix("turn-reply-") }.count, 1)
        XCTAssertEqual(rows.filter { $0.id.hasPrefix("inbox-fallback-") }.count, 0)
    }

    func test_inboundTranscript_inboxFallbackWithoutTurn_emitsInboundRow() {
        let tid = UUID()
        let inbox = ExchangeInboxItem(
            id: UUID(),
            receivedAt: t0.addingTimeInterval(12),
            updatedAt: t0.addingTimeInterval(12),
            envelopeID: "env-fallback-only",
            threadID: tid,
            processingState: .reconciledIntoThread,
            visibleSummary: "Visible inbox-only message.",
            metadata: [:]
        )
        let detail = makeDetail(thread: baseThread(id: tid), inboxItems: [inbox])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertEqual(rows.filter { $0.id.hasPrefix("inbox-fallback-") }.count, 1)
    }

    func test_inboundTranscript_identicalBodyDifferentEnvelopes_emitsTwoRows() {
        let tid = UUID()
        let turnOne = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(14),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Dup text",
            detail: "same body",
            metadata: ["source_envelope_id": "env-a"]
        )
        let turnTwo = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(15),
            actor: .counterparty,
            kind: .replyReceived,
            summary: "Dup text",
            detail: "same body",
            metadata: ["source_envelope_id": "env-b"]
        )
        let detail = makeDetail(thread: baseThread(id: tid), turns: [turnOne, turnTwo])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertEqual(rows.filter { $0.id.hasPrefix("turn-reply-") }.count, 2)
    }

    func test_inboundTranscript_emptyInboxPreview_usesGenericFallbackText() {
        let tid = UUID()
        let inbox = ExchangeInboxItem(
            id: UUID(),
            receivedAt: t0.addingTimeInterval(20),
            updatedAt: t0.addingTimeInterval(20),
            envelopeID: "env-empty-preview",
            threadID: tid,
            processingState: .received,
            visibleSummary: "",
            metadata: [:]
        )
        let detail = makeDetail(thread: baseThread(id: tid), inboxItems: [inbox])
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        XCTAssertTrue(rows.contains { $0.id.hasPrefix("inbox-fallback-") && $0.bodyPreview == "Inbound message received." })
    }

    // MARK: - Helpers

    private func assertSingleSentRow(
        in detail: ExchangeModels.ThreadDetail,
        draftID: UUID
    ) -> ExchangeModels.ThreadTranscriptEntry {
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let sent = rows.filter { $0.id == "draft-sent-\(draftID.uuidString)" }
        XCTAssertEqual(sent.count, 1, "Expected one sent draft row, got: \(rows.map(\.id))")
        return sent[0]
    }

    private func assertNoBannedSubstrings(in rows: [ExchangeModels.ThreadTranscriptEntry]) {
        assertTranscriptProjectionBannedFree(rows)
    }

    private func assertTranscriptProjectionBannedFree(_ rows: [ExchangeModels.ThreadTranscriptEntry]) {
        let bannedTokens = [
            "relay",
            "envelope",
            "outbox",
            "metadata",
            "execution",
            "trace",
            "agency",
            "mutation",
            "pipeline",
            "autonomous"
        ]

        for row in rows {
            let bundle = [row.title, row.bodyPreview, row.statusChip].compactMap { $0 }.joined(separator: " ")
            assertTranscriptUserFacingBannedFree(bundle, context: "row id=\(row.id) title=\(row.title)")
        }
    }

    private func assertTranscriptUserFacingBannedFree(_ text: String, context: String = "") {
        let lower = text.lowercased()

        XCTAssertFalse(
            lower.range(of: #"second([\s_-]+half|_half)"#, options: [.regularExpression, .caseInsensitive]) != nil,
            "second-half phrasing leaked \(context)"
        )

        for term in [
            "relay",
            "envelope",
            "outbox",
            "metadata",
            "execution",
            "trace",
            "agency",
            "mutation",
            "pipeline",
            "autonomous"
        ] {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            XCTAssertNil(
                lower.range(of: "\\b\(escaped)\\b", options: [.regularExpression, .caseInsensitive]),
                "\(term) leaked \(context)"
            )
        }
    }

    private func approvedExternalDraft(
        id: UUID,
        threadID: UUID,
        body: String,
        metadata: [String: String] = [:]
    ) -> ExchangeMessageDraft {
        ExchangeMessageDraft(
            id: id,
            threadID: threadID,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(4),
            status: .approved,
            kind: .followUp,
            audience: .externalCounterparty,
            body: body,
            posture: ExchangePosture(),
            metadata: metadata
        )
    }

    private func fixtureOutbox(
        threadID: UUID,
        draftID: UUID,
        phase: ExchangeDeliveryState.Phase,
        isActive: Bool = true,
        note: String? = nil
    ) -> ExchangeOutboxItem {
        ExchangeOutboxItem(
            threadID: threadID,
            draftID: draftID,
            targetNodeID: "fixture-remote-node",
            envelopeID: "fixture-envelope-\(draftID.uuidString.prefix(8))",
            deliveryState: ExchangeDeliveryState(
                phase: phase,
                priority: .userInitiated,
                note: note,
                queuedAt: t0
            ),
            payloadSummary: "Fixture outbound",
            isActive: isActive
        )
    }

    private func sentExternalDraft(
        id: UUID,
        threadID: UUID,
        body: String,
        metadata: [String: String],
        updatedAt: Date? = nil
    ) -> ExchangeMessageDraft {
        ExchangeMessageDraft(
            id: id,
            threadID: threadID,
            createdAt: t0,
            updatedAt: updatedAt ?? t0.addingTimeInterval(1),
            status: .sent,
            kind: .followUp,
            audience: .externalCounterparty,
            body: body,
            posture: ExchangePosture(),
            metadata: metadata
        )
    }

    private func baseThread(
        id: UUID,
        state: ExchangeState? = nil,
        updatedAt: Date? = nil,
        selectedCounterpartyID: ExchangeCounterparty.ID? = nil,
        selectedOfferID: ExchangeOffer.ID? = nil,
        lastInboundEnvelopeID: String? = nil
    ) -> ExchangeThread {
        ExchangeThread(
            id: id,
            createdAt: t0,
            updatedAt: updatedAt ?? t0.addingTimeInterval(60),
            mode: .transactional,
            intent: fixtureIntent(),
            posture: ExchangePosture(),
            state: state ?? .draftReady(.init(preparedAt: t0, summary: "Fixture")),
            selectedCounterpartyID: selectedCounterpartyID,
            selectedOfferID: selectedOfferID,
            lastInboundEnvelopeID: lastInboundEnvelopeID
        )
    }

    /// Minimal routing surface so unsent external drafts appear in the transcript (matches real “Draft ready” gates).
    private var fixtureRecipientAnchorCP: ExchangeCounterparty.ID { "fixture-transcript-anchor-cp" }

    private func fixtureIntent() -> ExchangeIntent {
        ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture",
            objective: "Fixture objective",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
    }

    private func makeDetail(
        thread: ExchangeThread,
        turns: [ExchangeTurn] = [],
        approvals: [ExchangeApproval] = [],
        drafts: [ExchangeMessageDraft] = [],
        outboxItems: [ExchangeOutboxItem] = [],
        inboxItems: [ExchangeInboxItem] = [],
        counterparties: [ExchangeCounterparty] = [],
        secondHalfDisplay: ExchangeSecondHalfUIAdapter.DisplayModel? = nil
    ) -> ExchangeModels.ThreadDetail {
        ExchangeModels.ThreadDetail(
            thread: thread,
            turns: turns,
            approvals: approvals,
            drafts: drafts,
            matches: [],
            counterparties: counterparties,
            artifacts: [],
            outboxItems: outboxItems,
            inboxItems: inboxItems,
            summary: "Fixture summary",
            secondHalfDisplay: secondHalfDisplay
        )
    }
}
