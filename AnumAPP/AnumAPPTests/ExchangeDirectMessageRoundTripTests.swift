import Foundation
import XCTest
@testable import AnumCore

// TODO: When product supports merge via envelope.threadID / payload.threadContext alone (no parentEnvelopeID),
// add `test_inboundReply_withoutParentButWithThreadID_stillMergesWhenSupported`.

/// End-to-end local send → default federation finalize → scripted inbound reply → reconcile → transcript + `newReply` notification.
/// Harness mirrors `ExchangeFacadeTrustedNodeManualMessageTests` but uses `ExchangeDefaultFederationService` and a scripted relay (no `ExchangeBootstrap.makeBundle` / ONNX retrieval graph).
final class ExchangeDirectMessageRoundTripTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_725_000_000)
    private let threadAutonomyModeKey = "secretary.threadAutonomy.mode"

    private let trustedNodeID = "dm-rt-trusted-node"
    private let publicProfileID = "dm-rt-public-profile"

    override func setUp() {
        super.setUp()
        setenv("ANUM_DISABLE_RUNTIME_PREWARM", "1", 1)
        setenv("ANUM_DISABLE_ONDEVICE_LLM", "1", 1)
    }

    func test_directTrustedSend_thenInboundReply_transcriptAndNotification() async throws {
        let harness = try makeHarness()
        let facade = harness.facade
        let store = harness.store

        try await seedCounterparty(store: store, now: fixedNow)
        let threadID = UUID()
        try await seedMatchFoundThread(
            store: store,
            threadID: threadID,
            counterpartyID: trustedNodeID,
            publicProfileID: publicProfileID,
            now: fixedNow
        )

        let outboundBody = "Are you free for a movie this weekend?"
        let returnedID = try await facade.sendManualMessageToTrustedNode(
            trustedNodeID: trustedNodeID,
            existingThreadID: threadID,
            subject: nil,
            body: outboundBody,
            now: fixedNow
        )
        XCTAssertEqual(returnedID, threadID)

        let outboxRows = try await store.listOutboxItems(
            filter: ExchangeOutboxFilter(threadID: threadID, limit: 10)
        )
        let outbox = try XCTUnwrap(outboxRows.first)
        let parentEnvelopeID = outbox.envelopeID
        XCTAssertFalse(parentEnvelopeID.isEmpty)

        let localNodeID = try await harness.identityService.localIdentity().nodeID
        let inboundStableKey = "dm-rt-reply-stable-\(threadID.uuidString.prefix(8))"

        let inboundEnvelope = buildInboundReplyEnvelope(
            trustedNodeID: trustedNodeID,
            localRecipientNodeID: localNodeID,
            threadID: threadID,
            parentEnvelopeID: parentEnvelopeID,
            inboundStableKey: inboundStableKey,
            replyBody: "Yes, Saturday works.",
            receivedAt: fixedNow.addingTimeInterval(120)
        )

        _ = try await facade.receiveEnvelope(inboundEnvelope, route: nil, receivedAt: fixedNow.addingTimeInterval(121))
        let reconcile1 = try await facade.reconcileInbox(now: fixedNow.addingTimeInterval(122))
        XCTAssertEqual(reconcile1.reconciledCount, 1)

        let detail = try await facade.getThread(threadID: threadID)
        let transcript = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)

        let youSentTitles = transcript.filter { $0.title == "You sent" }
        let sendingTitles = transcript.filter { $0.title == "Sending…" }
        if !youSentTitles.isEmpty {
            XCTAssertEqual(youSentTitles.count, 1, "Finalized outbound should yield a single ‘You sent’ row.")
            XCTAssertTrue(
                youSentTitles[0].bodyPreview.lowercased().contains("movie"),
                "Outbound preview should retain user text (after scrub): \(youSentTitles[0].bodyPreview)"
            )
        } else {
            XCTAssertEqual(
                sendingTitles.count,
                1,
                "If finalize did not flip draft to `.sent`, transcript should surface ‘Sending…’ instead of silently showing nothing."
            )
            XCTAssertFalse(sendingTitles[0].bodyPreview.isEmpty)
        }

        let theyReplied = transcript.filter { $0.title == "They replied" }
        XCTAssertEqual(theyReplied.count, 1)
        XCTAssertTrue(
            theyReplied[0].bodyPreview.lowercased().contains("saturday"),
            theyReplied[0].bodyPreview
        )

        assertTranscriptUserFacingBannedFree(transcript)

        let newReplyRowsAll = try await facade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(kinds: [.newReply], limit: 50)
        )
        let newReplyForThread = newReplyRowsAll.filter { $0.threadID == threadID }
        XCTAssertEqual(newReplyForThread.count, 1)
        let notifRow = try XCTUnwrap(newReplyForThread.first)
        XCTAssertFalse(notifRow.isRead)
        let expectedDedupe = SecretaryNotificationDedupeKey.newReply(
            threadID: threadID,
            envelopeID: inboundStableKey
        )
        XCTAssertEqual(notifRow.dedupeKey, expectedDedupe)
        assertNotificationCopyBannedFree(notifRow.title)
        assertNotificationCopyBannedFree(notifRow.body)

        let persistedInbound = try await store.fetchInboxItemByEnvelopeID(inboundStableKey)
        XCTAssertNotNil(persistedInbound)
        if let persistedInbound {
            XCTAssertEqual(persistedInbound.processingState, .reconciledIntoThread)
        }

        let unreadBeforePeek = try await facade.countUnreadSecretaryNotifications(excludingPriorityLow: true)
        XCTAssertGreaterThanOrEqual(unreadBeforePeek, 1)

        try await facade.markSecretaryThreadPeekNotificationsRead(threadID: threadID)

        let refreshed = try await facade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(kinds: [.newReply], limit: 50)
        )
        let refreshedMine = refreshed.filter { $0.threadID == threadID && $0.dedupeKey == expectedDedupe }
        XCTAssertEqual(refreshedMine.count, 1)
        XCTAssertTrue(refreshedMine[0].isRead)
        let unreadAfterPeek = try await facade.countUnreadSecretaryNotifications(excludingPriorityLow: true)
        XCTAssertEqual(unreadAfterPeek, 0)
    }

    func test_sameInboundEnvelope_receiveOrReconcileTwice_dedupesTurnTranscriptNotification() async throws {
        let harness = try makeHarness()
        let facade = harness.facade
        let store = harness.store

        try await seedCounterparty(store: store, now: fixedNow)
        let threadID = UUID()
        try await seedMatchFoundThread(
            store: store,
            threadID: threadID,
            counterpartyID: trustedNodeID,
            publicProfileID: publicProfileID,
            now: fixedNow
        )

        let outboundBody = "Are you free for a movie this weekend?"
        _ = try await facade.sendManualMessageToTrustedNode(
            trustedNodeID: trustedNodeID,
            existingThreadID: threadID,
            subject: nil,
            body: outboundBody,
            now: fixedNow
        )

        let outboxList = try await store.listOutboxItems(
            filter: ExchangeOutboxFilter(threadID: threadID, limit: 5)
        )
        let outboxEnvelopeID = try XCTUnwrap(outboxList.first).envelopeID

        let localNodeID = try await harness.identityService.localIdentity().nodeID
        let inboundStableKey = "dm-rt-reply-stable-dedupe-\(threadID.uuidString.prefix(8))"
        let inboundEnvelope = buildInboundReplyEnvelope(
            trustedNodeID: trustedNodeID,
            localRecipientNodeID: localNodeID,
            threadID: threadID,
            parentEnvelopeID: outboxEnvelopeID,
            inboundStableKey: inboundStableKey,
            replyBody: "Yes, Saturday works.",
            receivedAt: fixedNow.addingTimeInterval(220)
        )

        _ = try await facade.receiveEnvelope(inboundEnvelope, route: nil, receivedAt: fixedNow.addingTimeInterval(221))
        _ = try await facade.reconcileInbox(now: fixedNow.addingTimeInterval(222))

        let secondReceive = try await facade.receiveEnvelope(
            inboundEnvelope,
            route: nil,
            receivedAt: fixedNow.addingTimeInterval(300)
        )
        XCTAssertEqual(
            secondReceive.inboxItem.envelopeID,
            inboundStableKey,
            "Duplicate ingest should resolve to the persisted inbox envelope id."
        )

        let reconcileDup = try await facade.reconcileInbox(now: fixedNow.addingTimeInterval(301))
        XCTAssertEqual(reconcileDup.reconciledCount, 0)
        XCTAssertEqual(reconcileDup.deferredCount, 0)

        let turns = try await store.listTurns(threadID: threadID, limit: 50, ascending: true)
        let replyTurns = turns.filter { turn in
            turn.kind == .replyReceived &&
                turn.metadata["source_envelope_id"] == inboundStableKey
        }
        XCTAssertEqual(replyTurns.count, 1)

        let detail = try await facade.getThread(threadID: threadID)
        let transcript = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        let theyReplied = transcript.filter { row in
            (row.title == "Inbound message" || row.title.hasPrefix("Message from")) &&
                row.bodyPreview.lowercased().contains("saturday")
        }
        XCTAssertEqual(theyReplied.count, 1)

        assertTranscriptUserFacingBannedFree(transcript)

        let inboxForStable = try await store.fetchInboxItemByEnvelopeID(inboundStableKey)
        XCTAssertNotNil(inboxForStable)

        let newReplyRowsAll = try await facade.listSecretaryNotifications(
            filter: ExchangeSecretaryNotificationFilter(kinds: [.newReply], limit: 50)
        )
        let newReplyForThread = newReplyRowsAll.filter { $0.threadID == threadID }
        XCTAssertEqual(newReplyForThread.count, 1)
        let expectedDedupe = SecretaryNotificationDedupeKey.newReply(
            threadID: threadID,
            envelopeID: inboundStableKey
        )
        XCTAssertEqual(newReplyForThread[0].dedupeKey, expectedDedupe)
        assertNotificationCopyBannedFree(newReplyForThread[0].title)
        assertNotificationCopyBannedFree(newReplyForThread[0].body)

        let unreadAfterDedupePath = try await facade.countUnreadSecretaryNotifications(
            excludingPriorityLow: true
        )
        XCTAssertEqual(unreadAfterDedupePath, 1)

        XCTAssertEqual(reconcileDup.reconciledEnvelopeIDs.count, 0)
    }

    func test_reconcileInbox_parentEnvelopeCorrelation_appendsExistingThreadAndSuppressesDefaultInboxList() async throws {
        let harness = try makeHarness()
        let facade = harness.facade
        let store = harness.store

        try await seedCounterparty(store: store, now: fixedNow)
        let threadID = UUID()
        try await seedMatchFoundThread(
            store: store,
            threadID: threadID,
            counterpartyID: trustedNodeID,
            publicProfileID: publicProfileID,
            now: fixedNow
        )

        _ = try await facade.sendManualMessageToTrustedNode(
            trustedNodeID: trustedNodeID,
            existingThreadID: threadID,
            subject: nil,
            body: "Is this still available?",
            now: fixedNow
        )

        let outboxRowsForCorr = try await store.listOutboxItems(filter: .init(threadID: threadID, limit: 5))
        let outbox = try XCTUnwrap(outboxRowsForCorr.first)
        let localNodeID = try await harness.identityService.localIdentity().nodeID
        let inboundStableKey = "dm-rt-parent-corr-\(threadID.uuidString.prefix(8))"
        let inbound = buildInboundReplyEnvelope(
            trustedNodeID: trustedNodeID,
            localRecipientNodeID: localNodeID,
            threadID: UUID(),
            parentEnvelopeID: outbox.envelopeID,
            inboundStableKey: inboundStableKey,
            replyBody: "Yes, still available.",
            receivedAt: fixedNow.addingTimeInterval(600)
        )

        _ = try await facade.receiveEnvelope(inbound, route: nil, receivedAt: fixedNow.addingTimeInterval(601))
        let beforeThreadCount = try await store.listThreads(filter: .init(limit: 1000)).count
        let rec = try await facade.reconcileInbox(now: fixedNow.addingTimeInterval(602))
        XCTAssertEqual(rec.reconciledCount, 1)
        let afterThreadCount = try await store.listThreads(filter: .init(limit: 1000)).count
        XCTAssertEqual(beforeThreadCount, afterThreadCount)

        let turns = try await store.listTurns(threadID: threadID, limit: nil, ascending: true)
        XCTAssertTrue(turns.contains(where: {
            $0.kind == .replyReceived && $0.metadata["source_envelope_id"] == inboundStableKey
        }))

        let inboxItemCorr = try await store.fetchInboxItemByEnvelopeID(inboundStableKey)
        let inbox = try XCTUnwrap(inboxItemCorr)
        XCTAssertEqual(inbox.threadID, threadID)
        XCTAssertEqual(inbox.processingState, .reconciledIntoThread)

        let defaultInbox = try await facade.listInboxItems()
        XCTAssertFalse(defaultInbox.contains(where: { $0.envelopeID == inboundStableKey }))

        let explicitReconciled = try await facade.listInboxItems(
            filter: .init(processingStates: [.reconciledIntoThread], limit: 100)
        )
        XCTAssertTrue(explicitReconciled.contains(where: { $0.envelopeID == inboundStableKey }))
    }

    func test_reconcileInbox_conversationIDCorrelation_appendsWithoutParentEnvelope() async throws {
        let harness = try makeHarness()
        let facade = harness.facade
        let store = harness.store

        try await seedCounterparty(store: store, now: fixedNow)
        let threadID = UUID()
        let conversationID = "conversation-\(UUID().uuidString)"
        let rootEnvelopeID = "root-\(UUID().uuidString)"
        try await seedMatchFoundThread(
            store: store,
            threadID: threadID,
            counterpartyID: trustedNodeID,
            publicProfileID: publicProfileID,
            now: fixedNow,
            metadata: [
                "conversation_id": conversationID,
                "root_envelope_id": rootEnvelopeID,
                "original_requester_envelope_id": rootEnvelopeID
            ]
        )

        let localNodeID = try await harness.identityService.localIdentity().nodeID
        let stable = "dm-rt-conv-corr-\(threadID.uuidString.prefix(8))"
        let inbound = buildInboundReplyEnvelope(
            trustedNodeID: trustedNodeID,
            localRecipientNodeID: localNodeID,
            threadID: UUID(),
            parentEnvelopeID: "",
            inboundStableKey: stable,
            replyBody: "Conversation correlated reply.",
            receivedAt: fixedNow.addingTimeInterval(700),
            metadata: [
                "conversation_id": conversationID,
                "root_envelope_id": rootEnvelopeID
            ]
        )

        _ = try await facade.receiveEnvelope(inbound, route: nil, receivedAt: fixedNow.addingTimeInterval(701))
        let beforeCount = try await store.listThreads(filter: .init(limit: 1000)).count
        let rec = try await facade.reconcileInbox(now: fixedNow.addingTimeInterval(702))
        XCTAssertEqual(rec.reconciledCount, 1)
        let afterCount = try await store.listThreads(filter: .init(limit: 1000)).count
        XCTAssertEqual(beforeCount, afterCount)

        let inboxItemConv = try await store.fetchInboxItemByEnvelopeID(stable)
        let inbox = try XCTUnwrap(inboxItemConv)
        XCTAssertEqual(inbox.threadID, threadID)
        XCTAssertEqual(inbox.processingState, .reconciledIntoThread)
        let defaultInboxConv = try await facade.listInboxItems()
        XCTAssertFalse(defaultInboxConv.contains(where: { $0.envelopeID == stable }))
    }

    func test_reconcileInbox_fallbackCounterpartyOfferProfile_stillWorksWithoutCorrelation() async throws {
        let harness = try makeHarness()
        let facade = harness.facade
        let store = harness.store

        try await seedCounterparty(store: store, now: fixedNow)
        let inboundThreadID = UUID()
        try await seedInboundThreadForFallback(
            store: store,
            threadID: inboundThreadID,
            counterpartyID: trustedNodeID,
            publicProfileID: publicProfileID,
            offerID: "offer-fallback-1",
            now: fixedNow
        )

        let localNodeID = try await harness.identityService.localIdentity().nodeID
        let stable = "dm-rt-fallback-\(inboundThreadID.uuidString.prefix(8))"
        let inbound = buildInboundReplyEnvelope(
            trustedNodeID: trustedNodeID,
            localRecipientNodeID: localNodeID,
            threadID: UUID(),
            parentEnvelopeID: "",
            inboundStableKey: stable,
            replyBody: "Fallback matched reply.",
            receivedAt: fixedNow.addingTimeInterval(800),
            metadata: [
                "selected_offer_id": "offer-fallback-1",
                "selected_public_profile_id": publicProfileID
            ]
        )

        _ = try await facade.receiveEnvelope(inbound, route: nil, receivedAt: fixedNow.addingTimeInterval(801))
        let rec = try await facade.reconcileInbox(now: fixedNow.addingTimeInterval(802))
        XCTAssertEqual(rec.reconciledCount, 1)
        let inboxItemFallback = try await store.fetchInboxItemByEnvelopeID(stable)
        let inbox = try XCTUnwrap(inboxItemFallback)
        XCTAssertEqual(inbox.threadID, inboundThreadID)
    }

    func test_reconcileInbox_newContactWithoutCorrelation_createsNewThread() async throws {
        let harness = try makeHarness()
        let facade = harness.facade
        let store = harness.store

        let localNodeID = try await harness.identityService.localIdentity().nodeID
        let stable = "dm-rt-new-contact-\(UUID().uuidString.prefix(8))"
        let inbound = buildInboundReplyEnvelope(
            trustedNodeID: "new-contact-node-\(UUID().uuidString.prefix(8))",
            localRecipientNodeID: localNodeID,
            threadID: UUID(),
            parentEnvelopeID: "",
            inboundStableKey: stable,
            replyBody: "Hello from first contact.",
            receivedAt: fixedNow.addingTimeInterval(900)
        )

        _ = try await facade.receiveEnvelope(inbound, route: nil, receivedAt: fixedNow.addingTimeInterval(901))
        let beforeCount = try await store.listThreads(filter: .init(limit: 1000)).count
        let rec = try await facade.reconcileInbox(now: fixedNow.addingTimeInterval(902))
        XCTAssertEqual(rec.reconciledCount, 1)
        let afterCount = try await store.listThreads(filter: .init(limit: 1000)).count
        XCTAssertEqual(afterCount, beforeCount + 1)

        let inboxItemNew = try await store.fetchInboxItemByEnvelopeID(stable)
        let inbox = try XCTUnwrap(inboxItemNew)
        XCTAssertNotNil(inbox.threadID)
        XCTAssertEqual(inbox.processingState, .reconciledIntoThread)
    }

    func test_coldOutboundStillRequiresNormalRoutePosture() async throws {
        let harness = try makeHarness()
        let now = fixedNow
        let store = harness.store
        let federation = harness.federationService

        let noProfileCounterparty = ExchangeCounterparty(
            id: "cold-no-profile-\(UUID().uuidString.prefix(8))",
            createdAt: now,
            updatedAt: now,
            kind: .person,
            displayName: "Cold Contact",
            source: .manualEntry,
            publicProfile: nil
        )
        try await store.upsertCounterparties([noProfileCounterparty])

        let threadID = UUID()
        try await seedMatchFoundThread(
            store: store,
            threadID: threadID,
            counterpartyID: noProfileCounterparty.id,
            publicProfileID: "",
            now: now
        )
        let draft = ExchangeMessageDraft(
            id: UUID(),
            threadID: threadID,
            createdAt: now,
            updatedAt: now,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Cold outbound hello.",
            posture: ExchangePosture(privacy: .balanced)
        )
        try await store.saveDraft(draft)
        let fetchedThreadCold = try await store.fetchThread(id: threadID)
        let thread = try XCTUnwrap(fetchedThreadCold)

        let eligibility = try await federation.evaluateSendEligibility(
            thread: thread,
            counterparty: noProfileCounterparty,
            draft: draft
        )
        XCTAssertFalse(eligibility.isEligible)
    }

    // MARK: - Harness (local SQLite + default federation)

    private struct Harness {
        let facade: ExchangeFacade
        let store: ExchangeSQLiteStore
        let identityService: BootstrappedIdentityService
        let federationService: ExchangeDefaultFederationService
    }

    private func makeHarness() throws -> Harness {
        UserDefaults.standard.set(
            ExchangeModels.ExchangeThreadAutonomyMode.fullWithinBoundaries.rawValue,
            forKey: threadAutonomyModeKey
        )
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-dm-round-trip-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbURL = tmp.appendingPathComponent("db-\(UUID().uuidString).sqlite")

        let store = try ExchangeSQLiteStore(databaseURL: dbURL)
        let intelligence = ExchangeFallbackIntelligenceProvider()
        let policyEngine = ExchangePolicyEngine()
        let threadEngine = ExchangeThreadEngine()
        let continuationCoordinator = ExchangeThreadContinuationCoordinator()

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
            threadEngine: threadEngine,
            failureResolver: ExchangeFailureResolver(),
            summaryEngine: ExchangeSummaryEngine()
        )

        let identityService = BootstrappedIdentityService()
        let relayClient = ScriptedAcceptRelayClient()
        let envelopeService = ExchangeEnvelopeService(identityService: identityService)
        let transportPolicy = ExchangeTransportPolicy()
        let runtimeMonitor = ExchangeRuntimeActivityState()

        let federationService = ExchangeDefaultFederationService(
            store: store,
            policyEngine: policyEngine,
            envelopeService: envelopeService,
            identityService: identityService,
            relayClient: relayClient,
            runtimeMonitor: runtimeMonitor,
            transportPolicy: transportPolicy,
            continuationCoordinator: continuationCoordinator,
            threadEngine: threadEngine
        )

        let facade = ExchangeFacade(
            orchestrator: orchestrator,
            federationService: federationService,
            store: store,
            summaryEngine: ExchangeSummaryEngine(),
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            secondHalfFacade: ExchangeSecondHalfFacade(exchangeStore: store),
            intelligenceProvider: intelligence
        )

        return Harness(
            facade: facade,
            store: store,
            identityService: identityService,
            federationService: federationService
        )
    }

    /// Inbound reply envelope: binds to outbound via `parentEnvelopeID`; distinct stable receipt id via `inboundStableKey`.
    private func buildInboundReplyEnvelope(
        trustedNodeID: String,
        localRecipientNodeID: String,
        threadID: ExchangeThread.ID,
        parentEnvelopeID: String,
        inboundStableKey: String,
        replyBody: String,
        receivedAt: Date,
        metadata: [String: String] = [:]
    ) -> ExchangeRelayEnvelope {
        let parent = parentEnvelopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: receivedAt,
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: threadID,
            sender: ExchangeRelayEnvelope.Party(
                nodeID: trustedNodeID,
                displayName: "Trusted Contact Fixture",
                publicKeyID: nil
            ),
            recipient: ExchangeRelayEnvelope.Recipient(
                route: .node(id: localRecipientNodeID)
            ),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .followUp,
                subject: nil,
                body: replyBody,
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 2,
                parentEnvelopeID: parent.isEmpty ? nil : parent,
                idempotencyKey: inboundStableKey
            ),
            metadata: metadata
        )
    }

    private func seedCounterparty(store: ExchangeSQLiteStore, now: Date) async throws {
        let profile = ExchangePublicNodeProfile(
            id: publicProfileID,
            nodeID: trustedNodeID,
            counterpartyID: trustedNodeID,
            displayName: "DM RT Trusted",
            reachability: .init(acceptingInbound: true),
            createdAt: now,
            updatedAt: now
        )
        let counterparty = ExchangeCounterparty(
            id: trustedNodeID,
            createdAt: now,
            updatedAt: now,
            kind: .person,
            displayName: "DM RT Trusted",
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
        now: Date,
        metadata: [String: String] = [:]
    ) async throws {
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture DM round trip",
            objective: "Fixture objective for direct-message round-trip test.",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
        let thread = ExchangeThread(
            id: threadID,
            createdAt: now,
            updatedAt: now,
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(privacy: .balanced),
            state: .matchFound(
                .init(
                    foundAt: now,
                    candidateCount: 1,
                    summary: "Fixture match",
                    selectedCounterpartyID: counterpartyID,
                    selectedPublicProfileID: publicProfileID
                )
            ),
            selectedCounterpartyID: counterpartyID,
            selectedPublicProfileID: {
                let trimmed = publicProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }(),
            metadata: metadata
        )
        try await store.createThread(thread)
    }

    private func seedInboundThreadForFallback(
        store: ExchangeSQLiteStore,
        threadID: ExchangeThread.ID,
        counterpartyID: String,
        publicProfileID: String,
        offerID: String,
        now: Date
    ) async throws {
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Inbound fallback fixture",
            objective: "Fallback fixture",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
        let thread = ExchangeThread(
            id: threadID,
            createdAt: now,
            updatedAt: now,
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(privacy: .balanced),
            state: .matchFound(
                .init(
                    foundAt: now,
                    candidateCount: 1,
                    summary: "Inbound fallback fixture",
                    selectedCounterpartyID: counterpartyID,
                    selectedPublicProfileID: publicProfileID,
                    selectedOfferID: offerID
                )
            ),
            selectedCounterpartyID: counterpartyID,
            selectedPublicProfileID: publicProfileID,
            selectedOfferID: offerID,
            metadata: [
                "inbound_thread": "true",
                "inbound_envelope": "seed-\(UUID().uuidString)"
            ]
        )
        try await store.createThread(thread)
    }

    // MARK: - Banned vocabulary (mirror SecretaryThreadTranscriptTests / ExchangeSecretaryNotificationTests)

    private func assertTranscriptUserFacingBannedFree(_ rows: [ExchangeModels.ThreadTranscriptEntry]) {
        for row in rows {
            let bundle = [row.title, row.bodyPreview, row.statusChip].compactMap { $0 }.joined(separator: " ")
            assertTranscriptBannedFree(bundle, context: "row id=\(row.id)")
        }
    }

    private func assertTranscriptBannedFree(_ text: String, context: String = "") {
        let lower = text.lowercased()
        XCTAssertFalse(
            lower.range(of: #"second([\s_-]+half|_half)"#, options: [.regularExpression, .caseInsensitive]) != nil,
            "second-half phrasing leaked \(context)"
        )
        for term in [
            "relay", "envelope", "outbox", "metadata", "execution",
            "trace", "agency", "mutation", "pipeline", "autonomous"
        ] {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            XCTAssertNil(
                lower.range(of: "\\b\(escaped)\\b", options: [.regularExpression, .caseInsensitive]),
                "\(term) leaked \(context)"
            )
        }
    }

    private func assertNotificationCopyBannedFree(_ text: String) {
        let lower = text.lowercased()
        XCTAssertNil(
            lower.range(of: #"second(?:[\s_-]+half|_half)"#, options: [.regularExpression, .caseInsensitive])
        )
        for term in [
            "relay", "envelope", "outbox", "metadata", "execution",
            "trace", "agency", "mutation", "pipeline", "autonomous"
        ] {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            XCTAssertNil(
                lower.range(of: "\\b\(escaped)\\b", options: [.regularExpression, .caseInsensitive]),
                "'\(term)' leaked into notification copy."
            )
        }
    }
}

// MARK: - Scripted relay (outbound finalize)

private final class ScriptedAcceptRelayClient: ExchangeRelayClient, Sendable {
    func send(
        _: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?
    ) async throws -> ExchangeRelaySendResult {
        _ = route
        return ExchangeRelaySendResult(status: .accepted, acceptedAt: Date())
    }

    func fetchDeliveryStatus(reference _: String) async throws -> ExchangeRelayDeliveryStatus? { nil }

    func syncInbox(request _: ExchangeRelayInboxSyncRequest) async throws -> ExchangeRelayInboxSyncResponse {
        ExchangeRelayInboxSyncResponse(receipts: [])
    }

    func acknowledgeInboxItems(_ acknowledgements: [ExchangeRelayInboxAcknowledgement]) async throws
        -> ExchangeRelayInboxAcknowledgeResponse
    {
        ExchangeRelayInboxAcknowledgeResponse(
            acknowledgedReceiptIDs: acknowledgements.map(\.receiptID),
            rejectedReceiptIDs: [],
            updatedCount: acknowledgements.count,
            note: nil
        )
    }
}
