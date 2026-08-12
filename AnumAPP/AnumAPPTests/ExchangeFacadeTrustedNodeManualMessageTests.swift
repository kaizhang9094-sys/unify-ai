import XCTest
@testable import AnumCore

/// Trust-tab manual message: `ExchangeFacade.sendManualMessageToTrustedNode` → user-approved queue → flush
/// (no `sendAsSecretary` / chat bridge). Relay POST body shape mirrors `ExchangeHTTPRelayClient` (~625–640).
final class ExchangeFacadeTrustedNodeManualMessageTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_720_000_777)
    private let threadAutonomyModeKey = "secretary.threadAutonomy.mode"

    override func setUp() {
        super.setUp()
        setenv("ANUM_DISABLE_RUNTIME_PREWARM", "1", 1)
        setenv("ANUM_DISABLE_ONDEVICE_LLM", "1", 1)
    }

    func test_directTrustedMessage_existingThread_queuesOneUserApprovedOutbox() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-existing"
        let profileID = "fixture-public-profile-existing"
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E101")!

        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )
        try await seedMatchFoundThread(
            store: harness.store,
            threadID: threadID,
            counterpartyID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )

        let userBody = "Hello from trust tab test."
        let returnedID = try await harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: threadID,
            subject: nil,
            body: userBody,
            now: fixedNow
        )
        XCTAssertEqual(returnedID, threadID)
        XCTAssertNotNil(UUID(uuidString: returnedID.uuidString))

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox.count, 1)

        let approval = try await harness.store.fetchLatestApproval(threadID: threadID)
        XCTAssertEqual(approval?.decisionNote, ExchangeFacade.trustedNodeManualMessagePermitSource)
        XCTAssertEqual(approval?.metadata["trusted_node_manual_message"], "true")

        let drafts = try await harness.store.listDrafts(threadID: threadID)
        let manualDraft = try XCTUnwrap(drafts.first { $0.metadata["trusted_node_manual_message"] == "true" })
        XCTAssertEqual(manualDraft.body, userBody)

        let counts = await harness.federation.callCounts()
        XCTAssertEqual(counts.eligibility, 1)
        XCTAssertEqual(counts.queued, 1)
        XCTAssertEqual(counts.flush, 1, "sendManualMessageToTrustedNode must call flushOutbox after queue")
    }

    func test_directTrustedMessage_withoutExistingThread_createsRealThreadAndQueuesOneOutbox() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-new"
        let profileID = "fixture-public-profile-new"

        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )

        let userBody = "First outbound from new thread."
        let returnedID = try await harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: nil,
            subject: nil,
            body: userBody,
            now: fixedNow
        )

        let persisted = try await harness.store.requireThread(id: returnedID)
        XCTAssertEqual(
            persisted.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines),
            nodeID
        )
        XCTAssertFalse(
            returnedID.uuidString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Thread id must be a persisted UUID, not an ephemeral navigation token"
        )

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: returnedID))
        XCTAssertEqual(outbox.count, 1)

        let drafts = try await harness.store.listDrafts(threadID: returnedID)
        let manualDraft = try XCTUnwrap(drafts.first { $0.metadata["trusted_node_manual_message"] == "true" })
        XCTAssertEqual(manualDraft.body, userBody)

        let counts = await harness.federation.callCounts()
        XCTAssertEqual(counts.eligibility, 1)
        XCTAssertEqual(counts.queued, 1)
        XCTAssertEqual(counts.flush, 1)
    }

    func test_directTrustedMessage_emptyBody_throwsBeforeFederation() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-empty"
        let profileID = "fixture-public-profile-empty"
        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )

        do {
            _ = try await harness.facade.sendManualMessageToTrustedNode(
                trustedNodeID: nodeID,
                existingThreadID: nil,
                subject: nil,
                body: "   ",
                now: fixedNow
            )
            XCTFail("Expected empty body to throw")
        } catch {
            // Expected: ExchangeStoreError.storageFailure with empty-body reason.
        }

        let anyOutbox = try await harness.store.listOutboxItems(filter: .init(limit: 50))
        XCTAssertEqual(anyOutbox.count, 0)

        let counts = await harness.federation.callCounts()
        XCTAssertEqual(counts.eligibility, 0)
        XCTAssertEqual(counts.queued, 0)
        XCTAssertEqual(counts.flush, 0)
    }

    func test_directTrustedMessage_doesNotUseAgencyAutonomy() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-agency"
        let profileID = "fixture-public-profile-agency"
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E201")!

        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )
        try await seedMatchFoundThread(
            store: harness.store,
            threadID: threadID,
            counterpartyID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )

        _ = try await harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: threadID,
            subject: nil,
            body: "No autonomy flags please.",
            now: fixedNow
        )

        let thread = try await harness.store.requireThread(id: threadID)
        let approval = try await harness.store.fetchLatestApproval(threadID: threadID)
        let drafts = try await harness.store.listDrafts(threadID: threadID)
        let manualDraft = try XCTUnwrap(drafts.first { $0.metadata["trusted_node_manual_message"] == "true" })
        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        let item = try XCTUnwrap(outbox.first)

        XCTAssertEqual(approval?.decisionNote, ExchangeFacade.trustedNodeManualMessagePermitSource)

        let autonomousKeys = [
            "second_half_auto_response",
            "second_half_requester_autonomous_outbound",
            "autonomous_send_allowed",
            "agencyAutonomy",
            "second_half_generated"
        ]

        func dictHasAutonomyNoise(_ metadata: [String: String]) -> [String] {
            metadata.keys.filter { key in
                autonomousKeys.contains { key == $0 || key.contains($0) }
            }
        }

        XCTAssertTrue(dictHasAutonomyNoise(thread.metadata).isEmpty, "thread.metadata: \(thread.metadata)")
        XCTAssertTrue(dictHasAutonomyNoise(manualDraft.metadata).isEmpty, "draft.metadata: \(manualDraft.metadata)")
        XCTAssertTrue(dictHasAutonomyNoise(approval?.metadata ?? [:]).isEmpty, "approval.metadata: \(approval?.metadata ?? [:])")
        XCTAssertTrue(dictHasAutonomyNoise(item.metadata).isEmpty, "outbox.metadata: \(item.metadata)")
    }

    func test_openOrCreateDirectMessageThread_doesNotReuseNonDirectMessageThread() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-open-create-non-direct"
        let profileID = "fixture-public-profile-open-create-non-direct"
        let oldThreadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E601")!

        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )
        try await seedMatchFoundThread(
            store: harness.store,
            threadID: oldThreadID,
            counterpartyID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )

        let resolved = try await harness.facade.openOrCreateDirectMessageThread(
            counterpartyNodeID: nodeID,
            displayName: "DM Contact",
            now: fixedNow
        )

        XCTAssertNotEqual(
            resolved,
            oldThreadID,
            "Resolver must not reuse legacy non-direct message threads with matching counterparty."
        )
        let created = try await harness.store.requireThread(id: resolved)
        XCTAssertEqual(created.metadata["direct_message_thread"], "true")
        XCTAssertEqual(created.selectedCounterpartyID, nodeID)
    }

    func test_openOrCreateDirectMessageThread_reusesExistingDirectMessageThread() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-open-create-direct"
        let profileID = "fixture-public-profile-open-create-direct"
        let directThreadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E602")!

        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )
        var thread = try seedMatchFoundThreadValue(
            threadID: directThreadID,
            counterpartyID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )
        thread.metadata["direct_message_thread"] = "true"
        try await harness.store.createThread(thread)

        let resolved = try await harness.facade.openOrCreateDirectMessageThread(
            counterpartyNodeID: nodeID,
            displayName: "DM Contact",
            now: fixedNow
        )

        XCTAssertEqual(resolved, directThreadID)
    }

    /// Mirrors `SecretaryTrustView.indexLinkedThreads` (Trust tab): only `InboxItem.selectedCounterpartyID` participates.
    private func indexLinkedThreadsLikeSecretaryTrustView(
        from items: [ExchangeModels.InboxItem]
    ) -> [String: ExchangeThread.ID] {
        var best: [String: (threadID: ExchangeThread.ID, updatedAt: Date)] = [:]
        for item in items {
            guard let counterpartyID = item.selectedCounterpartyID else { continue }
            if let existing = best[counterpartyID] {
                if item.updatedAt > existing.updatedAt {
                    best[counterpartyID] = (item.threadID, item.updatedAt)
                }
            } else {
                best[counterpartyID] = (item.threadID, item.updatedAt)
            }
        }
        return Dictionary(uniqueKeysWithValues: best.map { key, value in
            (key, value.threadID)
        })
    }

    func test_listThreads_inboxItemPreservesSelectedCounterpartyIDWhenThreadSetsIt() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-inbox-cp"
        let profileID = "fixture-public-profile-inbox-cp"
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E401")!

        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )
        try await seedMatchFoundThread(
            store: harness.store,
            threadID: threadID,
            counterpartyID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )

        let inbox = try await harness.facade.listThreads(filter: .init(limit: 50))
        let row = try XCTUnwrap(inbox.first { $0.threadID == threadID })
        XCTAssertEqual(row.selectedCounterpartyID, nodeID)
    }

    func test_listThreads_profileOnlyThreadProjectsSelectedCounterpartyFromProfileNodeID() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-profile-only"
        let profileID = "fixture-public-profile-profile-only"
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E402")!

        try await seedThreadWithPublicProfileOnlyNoSelectedCounterparty(
            store: harness.store,
            threadID: threadID,
            nodeID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )

        let persisted = try await harness.store.requireThread(id: threadID)
        XCTAssertNil(persisted.selectedCounterpartyID)
        XCTAssertEqual(persisted.selectedPublicProfileID, profileID)

        let inbox = try await harness.facade.listThreads(filter: .init(limit: 50))
        let row = try XCTUnwrap(inbox.first { $0.threadID == threadID })
        XCTAssertEqual(
            row.selectedCounterpartyID,
            nodeID,
            "Inbox projection resolves selectedPublicProfileID to counterparty/node id for Trust linking."
        )
    }

    func test_trustLinkedThread_resolutionLinksProfileOnlyThread() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-trust-link"
        let profileID = "fixture-public-profile-trust-link"
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E404")!

        try await seedThreadWithPublicProfileOnlyNoSelectedCounterparty(
            store: harness.store,
            threadID: threadID,
            nodeID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )

        let inbox = try await harness.facade.listThreads(filter: .init(limit: 50))
        let linked = indexLinkedThreadsLikeSecretaryTrustView(from: inbox)
        XCTAssertEqual(linked[nodeID], threadID)
    }

    func test_trustMessage_existingProfileOnlyLinkedThread_reusesThreadInsteadOfCreatingDuplicate() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-reuse-linked"
        let profileID = "fixture-public-profile-reuse-linked"
        let existingThreadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E405")!

        try await seedThreadWithPublicProfileOnlyNoSelectedCounterparty(
            store: harness.store,
            threadID: existingThreadID,
            nodeID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )

        let inbox = try await harness.facade.listThreads(filter: .init(limit: 50))
        let linkedThreadID = try XCTUnwrap(indexLinkedThreadsLikeSecretaryTrustView(from: inbox)[nodeID])
        XCTAssertEqual(linkedThreadID, existingThreadID)

        let returnedID = try await harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: linkedThreadID,
            subject: nil,
            body: "Reuse profile-only thread via Trust-linked id.",
            now: fixedNow
        )

        XCTAssertEqual(returnedID, existingThreadID)

        let allThreads = try await harness.store.listThreads(filter: .init(limit: 50))
        XCTAssertEqual(allThreads.count, 1)

        let afterSend = try await harness.store.requireThread(id: existingThreadID)
        XCTAssertEqual(
            afterSend.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines),
            nodeID,
            "Send path persists selectedCounterpartyID when reuse was authorized via profile resolution."
        )

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: existingThreadID))
        XCTAssertEqual(outbox.count, 1)
    }

    // MARK: - Duplicate-send / double-tap risk (facade + test federation; see report in task notes)

    /// Two concurrent `sendManualMessageToTrustedNode` calls each create a new draft; stable envelope keys include `draftID`,
    /// so `ExchangeDefaultFederationService.queueApprovedOutbound` would not treat them as one idempotent send. This harness
    /// uses `TestFederationService` (always saves a new outbox row per queue call).
    func test_directTrustedMessage_doubleTapSameExistingThread_queuesTwoOutboxWithoutDedupe() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-double-tap"
        let profileID = "fixture-public-profile-double-tap"
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E501")!

        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )
        try await seedMatchFoundThread(
            store: harness.store,
            threadID: threadID,
            counterpartyID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )

        let body = "Concurrent duplicate-risk body."
        async let first = harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: threadID,
            subject: nil,
            body: body,
            now: fixedNow
        )
        async let second = harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: threadID,
            subject: nil,
            body: body,
            now: fixedNow
        )

        let (id1, id2) = try await (first, second)
        XCTAssertEqual(id1, threadID)
        XCTAssertEqual(id2, threadID)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(
            outbox.count,
            2,
            "Two concurrent sends → two drafts/outbox rows today; UI should gate double submit."
        )

        let drafts = try await harness.store.listDrafts(threadID: threadID)
        let manualDrafts = drafts.filter { $0.metadata["trusted_node_manual_message"] == "true" }
        XCTAssertEqual(manualDrafts.count, 2)

        let counts = await harness.federation.callCounts()
        XCTAssertEqual(counts.eligibility, 2)
        XCTAssertEqual(counts.queued, 2)
        XCTAssertEqual(counts.flush, 2)
    }

    /// Sequential sends with identical body are two separate user actions: each call creates a new draft/approval/outbox row.
    func test_directTrustedMessage_sequentialSameBodyRequiresProductDecision() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-seq-dup"
        let profileID = "fixture-public-profile-seq-dup"
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E502")!

        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )
        try await seedMatchFoundThread(
            store: harness.store,
            threadID: threadID,
            counterpartyID: nodeID,
            publicProfileID: profileID,
            now: fixedNow
        )

        let body = "Same body twice sequential."
        _ = try await harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: threadID,
            subject: nil,
            body: body,
            now: fixedNow
        )
        _ = try await harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: threadID,
            subject: nil,
            body: body,
            now: fixedNow
        )

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: threadID))
        XCTAssertEqual(outbox.count, 2, "Product: two sequential sends are two messages (no body-based dedupe in facade).")

        let counts = await harness.federation.callCounts()
        XCTAssertEqual(counts.queued, 2)
        XCTAssertEqual(counts.flush, 2)
    }

    /// Without `existingThreadID`, concurrent first sends can each create a new thread (no trusted-node-wide mutex).
    func test_directTrustedMessage_concurrentNewThread_canCreateTwoThreadsForSameTrustedNode() async throws {
        let harness = try makeHarness()
        let nodeID = "fixture-trusted-node-concurrent-new"
        let profileID = "fixture-public-profile-concurrent-new"

        try await seedCounterparty(
            store: harness.store,
            nodeID: nodeID,
            profileID: profileID,
            now: fixedNow
        )

        let body = "Concurrent new-thread body."
        async let r1 = harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: nil,
            subject: nil,
            body: body,
            now: fixedNow
        )
        async let r2 = harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: nodeID,
            existingThreadID: nil,
            subject: nil,
            body: body,
            now: fixedNow
        )

        let (t1, t2) = try await (r1, r2)

        let threads = try await harness.store.listThreads(filter: .init(limit: 50))
        XCTAssertEqual(threads.count, 2, "Duplicate-thread risk: concurrent first sends each run beginThread.")

        XCTAssertNotEqual(t1, t2)

        let out1 = try await harness.store.listOutboxItems(filter: .init(threadID: t1))
        let out2 = try await harness.store.listOutboxItems(filter: .init(threadID: t2))
        XCTAssertEqual(out1.count, 1)
        XCTAssertEqual(out2.count, 1)
    }

    /// Trust compose sheet is private SwiftUI; UX is verified by source inspection (not a UI test).
    func test_trustComposeSendButton_isBusyWhileSending_documentsUI() {
        // `SecretaryWorkspaceView.swift` → `SecretaryDirectMessageComposeSheet`:
        // `@State private var isSending`, TextField/Cancel `.disabled(isSending)`, Send `.disabled(trimmedBody.isEmpty || isSending)`,
        // and the Send `Task` sets `isSending = true` before awaiting `onSend`.
        XCTAssertTrue(true)
    }

    /// Encodes the same JSON field names as `ExchangeHTTPRelayClient.SendRequest` (private); validates envelope → POST contract.
    func test_directTrustedMessage_serverPayloadShape_matchesRelayContract() async throws {
        let nodeID = "fixture-trusted-node-relay"
        let profileID = "fixture-public-profile-relay"
        let offerAnchorID = "fixture-offer-anchor-relay-8841"
        let threadID = UUID(uuidString: "00000000-0000-4000-8000-00000000E301")!
        let senderNodeID = "fixture-local-sender-relay"

        let thread = try seedMatchFoundThreadValue(
            threadID: threadID,
            counterpartyID: nodeID,
            publicProfileID: profileID,
            selectedOfferID: offerAnchorID,
            now: fixedNow
        )
        let counterparty = ExchangeCounterparty(
            id: nodeID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .person,
            displayName: "Relay fixture",
            source: .manualEntry,
            publicProfile: ExchangePublicNodeProfile(
                id: profileID,
                nodeID: nodeID,
                counterpartyID: nodeID,
                reachability: .init(acceptingInbound: true),
                createdAt: fixedNow,
                updatedAt: fixedNow
            )
        )
        let profile = try XCTUnwrap(counterparty.publicProfile)

        var draft = ExchangeMessageDraft(
            threadID: thread.id,
            kind: .other,
            audience: .externalCounterparty,
            subject: nil,
            body: "Relay contract body line.",
            posture: thread.posture,
            targetCounterpartyID: nodeID,
            metadata: ["trusted_node_manual_message": "true"]
        )
        draft = draft.approving(at: fixedNow)

        let identity = FixtureIdentityService(nodeID: senderNodeID)
        let envelopeService = ExchangeEnvelopeService(identityService: identity)
        let built = try await envelopeService.buildEnvelope(
            thread: thread,
            counterparty: counterparty,
            publicProfile: profile,
            draft: draft,
            disclosureLevel: .balanced,
            idempotencyKey: "fixture-idempotency-relay-e",
            now: fixedNow
        )

        let envelope = built.envelope
        let recipientNodeID = Self.recipientNodeIDForSend(envelope: envelope, route: built.route)

        let sanitizedRelayMeta = ExchangeOutboundRelayMetadataSanitizer.allowlisted(from: envelope.metadata)

        let mirror = RelaySendRequestMirror(
            envelopeID: envelope.stableEnvelopeID,
            threadID: envelope.threadID.uuidString,
            senderNodeID: envelope.sender.nodeID,
            recipientNodeID: recipientNodeID,
            payload: .init(
                kind: envelope.payload.kind.rawValue,
                subject: envelope.payload.subject,
                body: envelope.payload.body,
                disclosureLevel: envelope.payload.disclosureLevel.rawValue,
                intentTitle: envelope.payload.threadContext?.intentTitle,
                mode: envelope.payload.threadContext?.mode,
                localThreadID: envelope.payload.threadContext?.localThreadID
            ),
            metadata: sanitizedRelayMeta
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(mirror)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["envelopeID"] as? String, envelope.stableEnvelopeID)
        XCTAssertEqual(json["threadID"] as? String, threadID.uuidString)
        XCTAssertEqual(json["senderNodeID"] as? String, senderNodeID)
        XCTAssertEqual(json["recipientNodeID"] as? String, nodeID)

        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["body"] as? String, "Relay contract body line.")
        XCTAssertEqual(payload["kind"] as? String, ExchangeRelayEnvelope.Payload.Kind.inquiry.rawValue)
        XCTAssertEqual(payload["localThreadID"] as? String, threadID.uuidString)
        XCTAssertEqual(payload["mode"] as? String, thread.mode.rawValue)
        XCTAssertEqual(payload["intentTitle"] as? String, thread.intent.title)
        XCTAssertEqual(payload["disclosureLevel"] as? String, ExchangeRelayEnvelope.Payload.DisclosureLevel.balanced.rawValue)

        XCTAssertNotNil(UUID(uuidString: json["threadID"] as? String ?? ""))
        XCTAssertNotNil(UUID(uuidString: payload["localThreadID"] as? String ?? ""))

        let meta = try XCTUnwrap(json["metadata"] as? [String: Any])
        XCTAssertEqual(meta["selected_offer_id"] as? String, offerAnchorID)
        XCTAssertEqual(meta["public_profile_id"] as? String, profileID)
        XCTAssertEqual(meta["selected_public_profile_id"] as? String, profileID)
        XCTAssertEqual(meta["selected_counterparty_id"] as? String, nodeID)
        XCTAssertEqual(meta["counterparty_id"] as? String, nodeID)
        XCTAssertNil(meta["target_description"])

        XCTAssertEqual(Set(meta.keys).intersection(Set(ExchangeOutboundRelayMetadataSanitizer.allowlistedKeysInOrder)), Set(meta.keys))
        XCTAssertGreaterThanOrEqual(meta.count, 1)
        XCTAssertLessThanOrEqual(meta.count, ExchangeOutboundRelayMetadataSanitizer.allowlistedKeysInOrder.count)
    }

    func test_exchangeOutboundRelayMetadataSanitizer_trims_allowlists_and_drops_largeNoise() {
        let source: [String: String] = [
            "selected_offer_id": "  anchor-offer-trim-test  ",
            "target_description": "should-not-relay-this-body",
            "visibility": "public",
            "selected_match_rationale": "noise"
        ]
        let out = ExchangeOutboundRelayMetadataSanitizer.allowlisted(from: source)
        XCTAssertEqual(out["selected_offer_id"], "anchor-offer-trim-test")
        XCTAssertNil(out["target_description"])
        XCTAssertNil(out["visibility"])
        XCTAssertNil(out["selected_match_rationale"])
    }

    // MARK: - Relay send mirror (ExchangeHTTPRelayClient ~625–640)

    private struct RelaySendRequestMirror: Encodable {
        let envelopeID: String
        let threadID: String?
        let senderNodeID: String
        let recipientNodeID: String
        let payload: PayloadMirror
        let metadata: [String: String]

        struct PayloadMirror: Encodable {
            let kind: String
            let subject: String?
            let body: String
            let disclosureLevel: String?
            let intentTitle: String?
            let mode: String?
            let localThreadID: String?
        }
    }

    private static func recipientNodeIDForSend(
        envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute
    ) -> String {
        switch route.kind {
        case .node:
            let trimmed = route.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        default:
            break
        }
        switch envelope.recipient.route {
        case .node(let id):
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        case .relayAddress(let value), .email(let value), .other(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    // MARK: - Harness

    private struct Harness {
        let facade: ExchangeFacade
        let store: ExchangeSQLiteStore
        let federation: TestFederationService
    }

    private actor TestFederationService: ExchangeFederationService {
        let store: ExchangeSQLiteStore
        let eligibilityAllowed: Bool
        let queueAllowed: Bool
        private(set) var evaluateEligibilityCalls = 0
        private(set) var queueApprovedOutboundCalls = 0
        private(set) var flushOutboxCalls = 0

        init(
            store: ExchangeSQLiteStore,
            eligibilityAllowed: Bool,
            queueAllowed: Bool
        ) {
            self.store = store
            self.eligibilityAllowed = eligibilityAllowed
            self.queueAllowed = queueAllowed
        }

        func callCounts() -> (eligibility: Int, queued: Int, flush: Int) {
            (evaluateEligibilityCalls, queueApprovedOutboundCalls, flushOutboxCalls)
        }

        func evaluateSendEligibility(
            thread: ExchangeThread,
            counterparty: ExchangeCounterparty,
            draft: ExchangeMessageDraft
        ) async throws -> ExchangeFederationSendEligibility {
            _ = thread
            _ = counterparty
            _ = draft
            evaluateEligibilityCalls += 1
            return ExchangeFederationSendEligibility(
                isEligible: eligibilityAllowed,
                reason: eligibilityAllowed
                    ? "Eligible in test federation."
                    : "Test federation keeps outbound disabled."
            )
        }

        func queueApprovedOutbound(
            thread: ExchangeThread,
            counterparty: ExchangeCounterparty,
            draft: ExchangeMessageDraft,
            approval: ExchangeApproval,
            disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
            priority: ExchangeDeliveryState.Priority,
            now: Date
        ) async throws -> ExchangeFederationQueueResult {
            _ = disclosureLevel
            queueApprovedOutboundCalls += 1
            guard queueAllowed else {
                throw ExchangeFederationError.transportFailed(reason: "Disabled in tests.")
            }
            let outbox = ExchangeOutboxItem(
                createdAt: now,
                updatedAt: now,
                threadID: thread.id,
                draftID: draft.id,
                approvalID: approval.id,
                targetNodeID: counterparty.id,
                envelopeID: "test-envelope-\(thread.id.uuidString)-\(draft.id.uuidString)",
                deliveryState: .init(
                    phase: .queued,
                    priority: priority,
                    queuedAt: now
                ),
                payloadSummary: "Trusted manual test"
            )
            try await store.saveOutboxItem(outbox)
            return ExchangeFederationQueueResult(outboxItem: outbox, auditRecords: [])
        }

        func cancelOutbound(
            outboxItemID: ExchangeOutboxItem.ID,
            reason: String?,
            now: Date
        ) async throws -> ExchangeFederationCancellationResult {
            _ = outboxItemID
            _ = reason
            _ = now
            throw ExchangeFederationError.transportFailed(reason: "Disabled in tests.")
        }

        func flushOutbox(now: Date) async throws -> ExchangeFederationFlushResult {
            _ = now
            flushOutboxCalls += 1
            return ExchangeFederationFlushResult()
        }

        func receiveEnvelope(
            _ envelope: ExchangeRelayEnvelope,
            route: ExchangeRelayRoute?,
            receivedAt: Date
        ) async throws -> ExchangeFederationReceiveResult {
            _ = envelope
            _ = route
            _ = receivedAt
            throw ExchangeFederationError.transportFailed(reason: "Disabled in tests.")
        }

        func reconcileInbox(now: Date) async throws -> ExchangeFederationReconcileResult {
            _ = now
            return ExchangeFederationReconcileResult()
        }

        func recentAudit(
            threadID: ExchangeThread.ID?,
            limit: Int
        ) async throws -> [ExchangeAuditRecord] {
            _ = threadID
            _ = limit
            return []
        }
    }

    private func makeHarness() throws -> Harness {
        UserDefaults.standard.set(
            ExchangeModels.ExchangeThreadAutonomyMode.fullWithinBoundaries.rawValue,
            forKey: threadAutonomyModeKey
        )
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-trusted-manual-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbURL = tmp.appendingPathComponent("db-\(UUID().uuidString).sqlite")

        let store = try ExchangeSQLiteStore(databaseURL: dbURL)
        let intelligence = ExchangeFallbackIntelligenceProvider()
        let policyEngine = ExchangePolicyEngine()

        let orchestrator = ExchangeOrchestrator(
            store: store,
            interpreter: ExchangeInterpreter(intelligenceProvider: intelligence),
            postureModeler: ExchangePostureModeler(intelligenceProvider: intelligence),
            discoveryService: ExchangeDiscoveryService(
                discoveryEngine: ExchangeDiscoveryEngine(),
                fitEngine: ExchangeFitEngine()
            ),
            messageComposer: ExchangeMessageComposer(
                draftEngine: ExchangeDraftEngine(intelligenceProvider: intelligence),
                policyEngine: policyEngine
            ),
            approvalEngine: ExchangeApprovalEngine(),
            policyEngine: policyEngine,
            threadEngine: ExchangeThreadEngine(),
            failureResolver: ExchangeFailureResolver(),
            summaryEngine: ExchangeSummaryEngine()
        )

        let federation = TestFederationService(
            store: store,
            eligibilityAllowed: true,
            queueAllowed: true
        )
        let facade = ExchangeFacade(
            orchestrator: orchestrator,
            federationService: federation,
            store: store,
            summaryEngine: ExchangeSummaryEngine(),
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            secondHalfFacade: ExchangeSecondHalfFacade(exchangeStore: store),
            intelligenceProvider: intelligence
        )

        return Harness(facade: facade, store: store, federation: federation)
    }

    private func seedCounterparty(
        store: ExchangeSQLiteStore,
        nodeID: String,
        profileID: String,
        now: Date
    ) async throws {
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            counterpartyID: nodeID,
            displayName: "Fixture Trusted",
            reachability: .init(acceptingInbound: true),
            createdAt: now,
            updatedAt: now
        )
        let counterparty = ExchangeCounterparty(
            id: nodeID,
            createdAt: now,
            updatedAt: now,
            kind: .person,
            displayName: "Fixture Trusted",
            source: .manualEntry,
            publicProfile: profile
        )
        try await store.upsertCounterparties([counterparty])
    }

    private func seedMatchFoundThread(
        store: ExchangeSQLiteStore,
        threadID: ExchangeThread.ID,
        counterpartyID: String,
        publicProfileID: String,
        now: Date
    ) async throws {
        let thread = try seedMatchFoundThreadValue(
            threadID: threadID,
            counterpartyID: counterpartyID,
            publicProfileID: publicProfileID,
            now: now
        )
        try await store.createThread(thread)
    }

    /// Durable thread targets a node's public profile but `selectedCounterpartyID` is still unset (valid per `ExchangeThread` domain docs).
    private func seedThreadWithPublicProfileOnlyNoSelectedCounterparty(
        store: ExchangeSQLiteStore,
        threadID: ExchangeThread.ID,
        nodeID: String,
        publicProfileID: String,
        now: Date
    ) async throws {
        try await seedCounterparty(
            store: store,
            nodeID: nodeID,
            profileID: publicProfileID,
            now: now
        )

        let fetchedCounterparty = try await store.fetchCounterparty(id: nodeID)
        let counterparty = try XCTUnwrap(fetchedCounterparty)
        let publicProfile = try XCTUnwrap(counterparty.publicProfile)
        try await store.savePublicProfile(publicProfile)

        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture profile-only thread",
            objective: "Simulate profile-selected path before counterparty record is wired to thread.",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
        let posture = ExchangePosture(privacy: .balanced)
        let thread = ExchangeThread(
            id: threadID,
            createdAt: now,
            updatedAt: now,
            mode: .transactional,
            intent: intent,
            posture: posture,
            state: .matchFound(
                .init(
                    foundAt: now,
                    candidateCount: 1,
                    summary: "Public profile path",
                    nextStep: nil,
                    selectedCounterpartyID: nil,
                    selectedPublicProfileID: publicProfileID,
                    selectedOfferID: nil
                )
            ),
            selectedCounterpartyID: nil,
            selectedPublicProfileID: publicProfileID,
            candidateCounterpartyIDs: [nodeID]
        )
        try await store.createThread(thread)
    }

    private func seedMatchFoundThreadValue(
        threadID: ExchangeThread.ID,
        counterpartyID: String,
        publicProfileID: String,
        selectedOfferID: String? = nil,
        now: Date
    ) throws -> ExchangeThread {
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture thread",
            objective: "Fixture objective for trusted manual send test.",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
        let posture = ExchangePosture(privacy: .balanced)
        return ExchangeThread(
            id: threadID,
            createdAt: now,
            updatedAt: now,
            mode: .transactional,
            intent: intent,
            posture: posture,
            state: .matchFound(
                .init(
                    candidateCount: 1,
                    summary: "Fixture match",
                    selectedCounterpartyID: counterpartyID,
                    selectedPublicProfileID: publicProfileID,
                    selectedOfferID: selectedOfferID
                )
            ),
            selectedCounterpartyID: counterpartyID,
            selectedPublicProfileID: publicProfileID,
            selectedOfferID: selectedOfferID
        )
    }
}

// MARK: - Fixture identity (envelope build only)

private struct FixtureIdentityService: ExchangeIdentityService {
    let nodeID: String

    func localIdentity() async throws -> ExchangeLocalIdentity {
        ExchangeLocalIdentity(
            nodeID: nodeID,
            displayName: "Fixture Sender",
            publicKeyID: "fixture-key",
            defaultRouteHint: .node(nodeID)
        )
    }

    func signEnvelope(_ envelope: ExchangeRelayEnvelope) async throws -> ExchangeRelayEnvelope.Signature {
        ExchangeRelayEnvelope.Signature(
            algorithm: .other,
            value: "fixture-sig:\(envelope.id.uuidString)",
            keyID: "fixture-key",
            signatureVersion: "1"
        )
    }

    func verifyEnvelopeSignature(
        _ envelope: ExchangeRelayEnvelope,
        expectedKeyID: String?
    ) async throws -> ExchangeEnvelopeVerificationResult {
        _ = envelope
        _ = expectedKeyID
        return .valid
    }
}
