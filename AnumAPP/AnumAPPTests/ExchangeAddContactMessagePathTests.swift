import XCTest
import AnumCore
@testable import AnumAPP

/// Integration path: manually add trusted contact → direct message eligibility and `sendManualMessageToTrustedNode`
/// (`userApproved`, not secretary bridge). Reuses orchestrator+federation patterns from sibling Exchange tests.
@MainActor
final class ExchangeAddContactMessagePathTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_734_567_910)
    private let threadAutonomyModeKey = "secretary.threadAutonomy.mode"

    override func setUp() {
        super.setUp()
        setenv("ANUM_DISABLE_RUNTIME_PREWARM", "1", 1)
        setenv("ANUM_DISABLE_ONDEVICE_LLM", "1", 1)
        UserDefaults.standard.set(
            ExchangeModels.ExchangeThreadAutonomyMode.fullWithinBoundaries.rawValue,
            forKey: threadAutonomyModeKey
        )
    }

    // MARK: - 1) Eligibility after add + thread

    func test_addManualTrustedContact_withHydratedProfile_thenMessageEligibilityIsTrue() async throws {
        let source = "local-source-eligibility-\(UUID().uuidString.prefix(8))"
        let target = "contact-target-msg-\(UUID().uuidString.prefix(8))"
        let profileID = "pub-profile-msg-\(UUID().uuidString.prefix(8))"
        let directory = AddContactMessagePathHarness.stubDirectory(target: target, profileID: profileID, fixedNow: fixedNow)
        let harness = try AddContactMessagePathHarness.make(directoryClient: directory)

        _ = try await harness.facade.addManualTrustedContact(
            sourceNodeID: source,
            rawTargetInput: target,
            displayNameOverride: "DM Contact",
            note: nil,
            now: fixedNow
        )

        let cp = try await harness.store.requireCounterparty(id: target)
        XCTAssertEqual(cp.displayName, "DM Contact")
        XCTAssertNotNil(cp.publicProfile)
        XCTAssertEqual(cp.publicProfile?.id, profileID)

        let savedPublicProfile = try await harness.store.fetchPublicProfile(id: profileID)
        XCTAssertNotNil(savedPublicProfile)

        let edges = try await harness.store.listTrustEdges(
            filter: .init(sourceNodeID: source, targetNodeID: target, activeOnly: true)
        )
        XCTAssertEqual(edges.count, 1)

        let items = try await harness.facade.listTrustedNodes(sourceNodeID: source)
        XCTAssertEqual(items.filter { $0.nodeID == target }.count, 1)
        let item = try XCTUnwrap(items.first { $0.nodeID == target })
        XCTAssertTrue(item.hasPublicProfileForMessaging)

        let threadID = UUID()
        try await harness.store.createThread(
            awaitingThread(
                id: threadID,
                selectedCounterpartyID: target,
                publicProfileID: profileID,
                now: fixedNow
            )
        )

        let detail = try await harness.facade.getThread(threadID: threadID)
        XCTAssertTrue(SecretaryProjectionEngine.canShowDirectMessageToTrustedNode(for: detail))
        XCTAssertEqual(
            SecretaryProjectionEngine.resolvedTrustedNodeIDForManualMessage(for: detail),
            target
        )
    }

    // MARK: - 2) Send queues outbox / transcript “You sent”

    func test_addManualTrustedContact_withHydratedProfile_thenSendManualMessageQueuesOutbox() async throws {
        let source = "local-source-send-\(UUID().uuidString.prefix(8))"
        let target = "contact-target-send-\(UUID().uuidString.prefix(8))"
        let profileID = "pub-profile-send-\(UUID().uuidString.prefix(8))"
        let directory = AddContactMessagePathHarness.stubDirectory(target: target, profileID: profileID, fixedNow: fixedNow)
        let harness = try AddContactMessagePathHarness.make(directoryClient: directory)

        _ = try await harness.facade.addManualTrustedContact(
            sourceNodeID: source,
            rawTargetInput: target,
            displayNameOverride: nil,
            note: nil,
            now: fixedNow
        )

        let userBody = "Hello after add-contact path."
        let returnedID = try await harness.facade.sendManualMessageToTrustedNode(
            trustedNodeID: target,
            existingThreadID: nil,
            subject: nil,
            body: userBody,
            now: fixedNow.addingTimeInterval(1)
        )

        XCTAssertNotNil(UUID(uuidString: returnedID.uuidString))
        _ = try await harness.store.requireThread(id: returnedID)

        let thread = try await harness.store.requireThread(id: returnedID)
        XCTAssertEqual(
            thread.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines),
            target
        )

        let drafts = try await harness.store.listDrafts(threadID: returnedID)
        let manualDrafts = drafts.filter { $0.metadata["trusted_node_manual_message"] == "true" }
        XCTAssertEqual(manualDrafts.count, 1)
        let manualDraft = try XCTUnwrap(manualDrafts.first)
        XCTAssertEqual(manualDraft.body, userBody)

        let outbox = try await harness.store.listOutboxItems(filter: .init(threadID: returnedID))
        XCTAssertEqual(outbox.count, 1)

        let approval = try await harness.store.fetchLatestApproval(threadID: returnedID)
        XCTAssertEqual(approval?.decisionNote, ExchangeFacade.trustedNodeManualMessagePermitSource)
        XCTAssertEqual(approval?.metadata["trusted_node_manual_message"], "true")
        XCTAssertEqual(approval?.status, .approved)

        let autonomyNoise = [
            "second_half_auto_response",
            "second_half_requester_autonomous_outbound",
            "second_half_generated",
            "agencyAutonomy"
        ]
        for key in autonomyNoise {
            XCTAssertNil(approval?.metadata[key])
        }

        let counts = await harness.federation.callCounts()
        XCTAssertEqual(counts.eligibility, 1)
        XCTAssertEqual(counts.queued, 1)
        XCTAssertEqual(counts.flush, 1)

        let detail = try await harness.facade.getThread(threadID: returnedID)
        let transcript = ExchangeModels.ThreadTranscriptBuilder.build(from: detail)
        // Stub federation queues active outbox (.queued) but does not finalize relay success → draft stays `.approved`.
        // Transcript surfaces **Sending…** via outbox ↔ draft linkage; **You sent** only after finalize marks `.sent`.
        let sendingRows = transcript.filter { $0.title == "Sending…" }
        XCTAssertEqual(sendingRows.count, 1)
        XCTAssertTrue(sendingRows[0].bodyPreview.localizedStandardContains(userBody))
        XCTAssertNil(transcript.first { $0.title == "You sent" })
        XCTAssertNil(transcript.first { $0.title == "Draft ready" })
    }

    // MARK: - 3) Duplicate add

    func test_addManualTrustedContact_twiceSameTarget_updatesWithoutDuplicateCounterpartyOrTrustEdge() async throws {
        let source = "local-source-dup-\(UUID().uuidString.prefix(8))"
        let target = "contact-target-dup-\(UUID().uuidString.prefix(8))"
        let profileID = "pub-profile-dup-\(UUID().uuidString.prefix(8))"
        let directory = AddContactMessagePathHarness.stubDirectory(target: target, profileID: profileID, fixedNow: fixedNow)
        let harness = try AddContactMessagePathHarness.make(directoryClient: directory)

        let edge1 = try await harness.facade.addManualTrustedContact(
            sourceNodeID: source,
            rawTargetInput: target,
            displayNameOverride: "First label",
            note: "Round one",
            now: fixedNow
        )

        let edge2 = try await harness.facade.addManualTrustedContact(
            sourceNodeID: source,
            rawTargetInput: target,
            displayNameOverride: "Second label",
            note: "Round two revised",
            now: fixedNow.addingTimeInterval(5)
        )

        XCTAssertEqual(edge1.id, edge2.id)

        let cp = try await harness.store.requireCounterparty(id: target)
        XCTAssertEqual(cp.displayName, "Second label")

        let edges = try await harness.store.listTrustEdges(
            filter: .init(sourceNodeID: source, targetNodeID: target, activeOnly: false, limit: 50)
        )
        XCTAssertEqual(edges.count, 1)

        let profilesForCp = try await harness.store.listPublicProfiles(
            filter: .init(counterpartyID: target, limit: 50)
        )
        XCTAssertEqual(
            profilesForCp.count,
            1,
            "Expected single public profile row for that counterparty, not duplicates."
        )

        let items = try await harness.facade.listTrustedNodes(sourceNodeID: source)
        XCTAssertEqual(items.filter { $0.nodeID == target }.count, 1)
    }

    // MARK: - 4) No profile → hide message / send fails cleanly

    func test_addManualTrustedContact_withoutResolvableProfile_isSavedButMessageHiddenOrSendFailsCleanly() async throws {
        let source = "local-source-nopro-\(UUID().uuidString.prefix(8))"
        let target = "contact-target-nopro-\(UUID().uuidString.prefix(8))"
        let harness = try AddContactMessagePathHarness.make(directoryClient: nil)

        _ = try await harness.facade.addManualTrustedContact(
            sourceNodeID: source,
            rawTargetInput: target,
            displayNameOverride: "Local-only",
            note: nil,
            now: fixedNow
        )

        let items = try await harness.facade.listTrustedNodes(sourceNodeID: source)
        let trustItem = try XCTUnwrap(items.first { $0.nodeID == target })
        XCTAssertFalse(trustItem.hasPublicProfileForMessaging)

        let threadID = UUID()
        try await harness.store.createThread(
            awaitingThread(
                id: threadID,
                selectedCounterpartyID: target,
                publicProfileID: nil,
                now: fixedNow
            )
        )

        let detail = try await harness.facade.getThread(threadID: threadID)
        XCTAssertFalse(SecretaryProjectionEngine.canShowDirectMessageToTrustedNode(for: detail))

        do {
            _ = try await harness.facade.sendManualMessageToTrustedNode(
                trustedNodeID: target,
                existingThreadID: nil,
                subject: nil,
                body: "Should not ship without profile.",
                now: fixedNow.addingTimeInterval(2)
            )
            XCTFail("Expected storage failure — no federation send without public profile.")
        } catch let err as ExchangeStoreError {
            if case .storageFailure(let reason) = err {
                XCTAssertTrue(
                    reason.localizedStandardContains("public") || reason.localizedStandardContains("federation"),
                    "Unexpected failure reason: \(reason)"
                )
            } else {
                XCTFail("Expected storageFailure with messaging reason; got \(err)")
            }
        }

        let outbox = try await harness.store.listOutboxItems(filter: .init(limit: 20))
        XCTAssertEqual(outbox.count, 0)

        let counts = await harness.federation.callCounts()
        XCTAssertEqual(counts.queued, 0)
    }
}

// MARK: - Thread fixture

private func awaitingThread(
    id: UUID,
    selectedCounterpartyID: String,
    publicProfileID: String?,
    now: Date
) -> ExchangeThread {
    ExchangeThread(
        id: id,
        createdAt: now,
        updatedAt: now,
        mode: .transactional,
        intent: ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Message",
            objective: "Fixture thread for eligibility after manual add.",
            readiness: .ready,
            interpretationConfidence: 1.0
        ),
        posture: ExchangePosture(privacy: .balanced),
        state: .awaitingResponse(.init(since: now)),
        selectedCounterpartyID: selectedCounterpartyID,
        selectedPublicProfileID: publicProfileID
    )
}

// MARK: - Harness & stubs

private enum AddContactMessagePathHarness {
    struct Harness {
        let facade: ExchangeFacade
        let store: ExchangeSQLiteStore
        let federation: CountingTestFederationService
    }

    static func stubDirectory(target: String, profileID: String, fixedNow: Date) -> StubDirectoryClient {
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: "ignored-node-column",
            counterpartyID: nil,
            displayName: "Directory Name",
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let directoryCp = ExchangeCounterparty(
            id: "different-cp-id-\(UUID().uuidString.prefix(6))",
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .person,
            displayName: "Directory Row",
            source: .relayNetwork,
            identity: ExchangeCounterparty.Identity(nodeID: target, verification: .unverified),
            publicProfile: profile
        )
        let match = ExchangeDirectoryMatch.fromCounterparty(directoryCp)
        return StubDirectoryClient(matches: [match])
    }

    static func make(directoryClient: (any ExchangeDirectoryClient)?) throws -> Harness {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-add-contact-msg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbURL = tmp.appendingPathComponent("exchange.sqlite")

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

        let federation = CountingTestFederationService(store: store, eligibilityAllowed: true, queueAllowed: true)
        let facade = ExchangeFacade(
            orchestrator: orchestrator,
            federationService: federation,
            store: store,
            summaryEngine: ExchangeSummaryEngine(),
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            secondHalfFacade: ExchangeSecondHalfFacade(exchangeStore: store),
            intelligenceProvider: intelligence,
            directoryClient: directoryClient
        )

        return Harness(facade: facade, store: store, federation: federation)
    }
}

private struct StubDirectoryClient: ExchangeDirectoryClient, Sendable {
    let matches: [ExchangeDirectoryMatch]

    func search(_ request: ExchangeDirectorySearchRequest) async throws -> ExchangeDirectorySearchResponse {
        _ = request
        return ExchangeDirectorySearchResponse(matches: matches, source: .remote)
    }

    func publishSellerSurface(_ request: ExchangeSellerSurfacePublishRequest) async throws -> ExchangeSellerSurfacePublishResponse {
        _ = request
        throw ExchangeDirectoryClientError.backendFailure(reason: "stub")
    }

    func unpublishSellerSurface(nodeID: String, publicProfileID: String) async throws -> ExchangeSellerSurfaceUnpublishResponse {
        _ = nodeID
        _ = publicProfileID
        throw ExchangeDirectoryClientError.backendFailure(reason: "stub")
    }

    func publishRetrievalDocuments(
        _ request: ExchangeRetrievalDocumentPublishRequest
    ) async throws -> ExchangeRetrievalDocumentPublishResponse {
        _ = request
        throw ExchangeDirectoryClientError.backendFailure(reason: "stub")
    }
}

private actor CountingTestFederationService: ExchangeFederationService {
    let store: ExchangeSQLiteStore
    let eligibilityAllowed: Bool
    let queueAllowed: Bool
    private(set) var evaluateEligibilityCalls = 0
    private(set) var queueApprovedOutboundCalls = 0
    private(set) var flushOutboxCalls = 0

    init(store: ExchangeSQLiteStore, eligibilityAllowed: Bool, queueAllowed: Bool) {
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
            reason: eligibilityAllowed ? "Eligible in test federation." : "Not eligible."
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
            envelopeID: "test-add-contact-\(thread.id.uuidString)-\(draft.id.uuidString)",
            deliveryState: .init(phase: .queued, priority: priority, queuedAt: now),
            payloadSummary: "Add contact manual message harness"
        )
        try await store.saveOutboxItem(outbox)
        return ExchangeFederationQueueResult(outboxItem: outbox, auditRecords: [])
    }

    func cancelOutbound(outboxItemID: ExchangeOutboxItem.ID, reason: String?, now: Date) async throws
        -> ExchangeFederationCancellationResult
    {
        _ = outboxItemID
        _ = reason
        _ = now
        throw ExchangeFederationError.transportFailed(reason: "stub")
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
        throw ExchangeFederationError.transportFailed(reason: "stub")
    }

    func reconcileInbox(now: Date) async throws -> ExchangeFederationReconcileResult {
        _ = now
        return ExchangeFederationReconcileResult()
    }

    func recentAudit(threadID: ExchangeThread.ID?, limit: Int) async throws -> [ExchangeAuditRecord] {
        _ = threadID
        _ = limit
        return []
    }
}
