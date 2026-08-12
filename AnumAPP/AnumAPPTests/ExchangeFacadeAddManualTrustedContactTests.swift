import XCTest
@testable import AnumCore

@MainActor
final class ExchangeFacadeAddManualTrustedContactTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_730_100_000)

    func test_normalizePlainNodeId() {
        XCTAssertEqual(
            ManualTrustedContactInputNormalizer.normalizedNodeID(from: "  my-node-123  "),
            "my-node-123"
        )
    }

    func test_normalizeURLQueryNodeId() {
        let url = "https://example.com/path?node_id=target-from-query"
        XCTAssertEqual(
            ManualTrustedContactInputNormalizer.normalizedNodeID(from: url),
            "target-from-query"
        )
    }

    func test_normalizeURLPathLastSegment() {
        let url = "https://example.com/directory/nodes/last-segment-id"
        XCTAssertEqual(
            ManualTrustedContactInputNormalizer.normalizedNodeID(from: url),
            "last-segment-id"
        )
    }

    func test_normalizeEmbeddedNodeIDInPlainText() {
        let text = "Please add me on Unify, my id is node-embedded-445."
        XCTAssertEqual(
            ManualTrustedContactInputNormalizer.normalizedNodeID(from: text),
            "node-embedded-445"
        )
    }

    func test_normalizeUnifySchemeContactNode() {
        let text = "unify://contact/node-abc-123"
        XCTAssertEqual(
            ManualTrustedContactInputNormalizer.normalizedNodeID(from: text),
            "node-abc-123"
        )
    }

    func test_normalizeHttpsContactNodePath() {
        let text = "https://unify.app/contact/node-hello-777"
        XCTAssertEqual(
            ManualTrustedContactInputNormalizer.normalizedNodeID(from: text),
            "node-hello-777"
        )
    }

    func test_addManualTrustedContact_withoutDirectory_createsEdgeAndCounterparty() async throws {
        let harness = try makeHarness(directoryClient: nil)
        let source = "local-source-node"
        let target = "manual-target-node-a"

        let edge = try await harness.facade.addManualTrustedContact(
            sourceNodeID: source,
            rawTargetInput: target,
            displayNameOverride: "Custom Name",
            note: "Remember café",
            now: fixedNow
        )

        XCTAssertEqual(edge.targetNodeID, target)
        XCTAssertEqual(edge.relationshipType, .knownContact)
        XCTAssertEqual(edge.trustLevel, .low)
        XCTAssertTrue(edge.scopes.contains(.generalCommunication))

        let cp = try await harness.store.fetchCounterparty(id: target)
        let counterparty = try XCTUnwrap(cp)
        XCTAssertEqual(counterparty.displayName, "Custom Name")
        XCTAssertNil(counterparty.publicProfile)

        let items = try await harness.facade.listTrustedNodes(sourceNodeID: source)
        let item = try XCTUnwrap(items.first { $0.nodeID == target })
        XCTAssertFalse(item.hasPublicProfileForMessaging)
    }

    func test_addManualTrustedContact_directoryHydratesPublicProfile() async throws {
        let target = "hydrate-node-1"
        let profileID = "profile-hydrate-1"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: "legacy-node-field",
            counterpartyID: nil,
            displayName: "From Directory",
            createdAt: fixedNow,
            updatedAt: fixedNow
        )
        let directoryCounterparty = ExchangeCounterparty(
            id: "different-cp-id",
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .person,
            displayName: "Directory Row",
            source: .relayNetwork,
            identity: ExchangeCounterparty.Identity(nodeID: target, verification: .unverified),
            publicProfile: profile
        )
        let match = ExchangeDirectoryMatch.fromCounterparty(directoryCounterparty)
        let directory = StubManualAddDirectoryClient(matches: [match])

        let harness = try makeHarness(directoryClient: directory)
        let source = "local-source-node-2"

        _ = try await harness.facade.addManualTrustedContact(
            sourceNodeID: source,
            rawTargetInput: target,
            displayNameOverride: nil,
            note: nil,
            now: fixedNow
        )

        let savedProfile = try await harness.store.fetchPublicProfile(id: profileID)
        XCTAssertNotNil(savedProfile)

        let cp = try await harness.store.fetchCounterparty(id: target)
        let counterparty = try XCTUnwrap(cp)
        XCTAssertNotNil(counterparty.publicProfile)

        let items = try await harness.facade.listTrustedNodes(sourceNodeID: source)
        let item = try XCTUnwrap(items.first { $0.nodeID == target })
        XCTAssertTrue(item.hasPublicProfileForMessaging)
    }

    func test_listPendingContactRequests_groupsIntoSingleRequesterRow() async throws {
        let harness = try makeHarness(directoryClient: nil)
        let now = fixedNow
        let senderNode = "node-contact-request-grouped"

        let one = ExchangeInboxItem(
            receivedAt: now,
            updatedAt: now,
            envelopeID: "contact-req-env-1",
            senderNodeID: senderNode,
            senderDisplayName: "Pat",
            processingState: .received,
            visibleSummary: "Please add me",
            metadata: [
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue,
                "body_preview": "Let's connect"
            ]
        )
        let two = ExchangeInboxItem(
            receivedAt: now.addingTimeInterval(60),
            updatedAt: now.addingTimeInterval(60),
            envelopeID: "contact-req-env-2",
            senderNodeID: senderNode,
            senderDisplayName: "Pat",
            processingState: .received,
            visibleSummary: "Follow-up intro",
            metadata: [
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue,
                "body_preview": "Please accept"
            ]
        )
        try await harness.store.saveInboxItem(one)
        try await harness.store.saveInboxItem(two)

        let requests = try await harness.facade.listPendingContactRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].requesterNodeID, senderNode)
        XCTAssertEqual(requests[0].pendingCount, 2)
    }

    func test_acceptContactRequest_createsTrustedContactAndArchivesSourceInboxItems() async throws {
        let harness = try makeHarness(directoryClient: nil)
        let sourceNodeID = "local-source-node-accept"
        let requester = "node-contact-request-accept"
        let inbox = ExchangeInboxItem(
            receivedAt: fixedNow,
            updatedAt: fixedNow,
            envelopeID: "contact-accept-env-1",
            senderNodeID: requester,
            senderDisplayName: "Avery",
            processingState: .received,
            visibleSummary: "Contact request",
            metadata: [
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue
            ]
        )
        try await harness.store.saveInboxItem(inbox)

        let request = try XCTUnwrap(try await harness.facade.listPendingContactRequests().first)
        _ = try await harness.facade.acceptContactRequest(
            sourceNodeID: sourceNodeID,
            request: request,
            now: fixedNow
        )

        let trusted = try await harness.facade.listTrustedNodes(sourceNodeID: sourceNodeID)
        XCTAssertNotNil(trusted.first(where: { $0.nodeID == requester }))

        let persisted = try await harness.store.fetchInboxItem(id: inbox.id)
        XCTAssertEqual(persisted?.processingState, .archived)
    }

    func test_declineContactRequest_doesNotCreateTrustedContact() async throws {
        let harness = try makeHarness(directoryClient: nil)
        let sourceNodeID = "local-source-node-decline"
        let requester = "node-contact-request-decline"
        let inbox = ExchangeInboxItem(
            receivedAt: fixedNow,
            updatedAt: fixedNow,
            envelopeID: "contact-decline-env-1",
            senderNodeID: requester,
            senderDisplayName: "Kai",
            processingState: .received,
            visibleSummary: "Contact request",
            metadata: [
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue
            ]
        )
        try await harness.store.saveInboxItem(inbox)

        let request = try XCTUnwrap(try await harness.facade.listPendingContactRequests().first)
        try await harness.facade.declineContactRequest(request: request, now: fixedNow)

        let trusted = try await harness.facade.listTrustedNodes(sourceNodeID: sourceNodeID)
        XCTAssertNil(trusted.first(where: { $0.nodeID == requester }))

        let persisted = try await harness.store.fetchInboxItem(id: inbox.id)
        XCTAssertEqual(persisted?.processingState, .archived)
    }

    func test_sendContactRequestToNode_createsIntroductionDraftAndApprovalMetadata() async throws {
        let harness = try makeHarness(directoryClient: nil)
        let sourceNodeID = "local-node-send-contact-request"
        let targetNodeID = "node-send-contact-request-target"
        let note = "Hi, let's connect."

        let result = try await harness.facade.sendContactRequestToNode(
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            displayNameOverride: "Target Name",
            note: note,
            now: fixedNow
        )

        XCTAssertEqual(result.targetNodeID, targetNodeID)
        XCTAssertNotNil(result.threadID)
        let threadID = try XCTUnwrap(result.threadID)
        let drafts = try await harness.store.listDrafts(threadID: threadID)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.kind, .introduction)
        XCTAssertEqual(draft.metadata["payload_kind"], ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue)
        XCTAssertEqual(draft.metadata["contact_request"], "true")
        XCTAssertEqual(draft.metadata["introduction_request"], "true")

        let approval = try await harness.store.fetchLatestApproval(threadID: threadID)
        XCTAssertEqual(approval?.metadata["payload_kind"], ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue)
        XCTAssertEqual(approval?.metadata["contact_request"], "true")
        XCTAssertEqual(approval?.metadata["introduction_request"], "true")
    }

    func test_sendContactRequestToNode_doesNotCreateTrustedContactBeforeAcceptance() async throws {
        let harness = try makeHarness(directoryClient: nil)
        let sourceNodeID = "local-node-preaccept"
        let targetNodeID = "node-preaccept-target"

        _ = try await harness.facade.sendContactRequestToNode(
            sourceNodeID: sourceNodeID,
            targetNodeID: targetNodeID,
            displayNameOverride: nil,
            note: "Please add me.",
            now: fixedNow
        )

        let trusted = try await harness.facade.listTrustedNodes(sourceNodeID: sourceNodeID)
        XCTAssertNil(trusted.first(where: { $0.nodeID == targetNodeID }))
    }

    func test_addManualTrustedContact_addsLocallyWithoutIntroductionDraft() async throws {
        let harness = try makeHarness(directoryClient: nil)
        let source = "local-add-only-source"
        let target = "local-add-only-target"

        _ = try await harness.facade.addManualTrustedContact(
            sourceNodeID: source,
            rawTargetInput: target,
            displayNameOverride: "Local Only",
            note: nil,
            now: fixedNow
        )

        let threads = try await harness.store.listThreads(filter: .init(limit: 50))
        XCTAssertTrue(threads.isEmpty, "Local add should not enqueue a contact request thread/send.")
    }

    func test_addManualTrustedContact_rejectsSelfAsTarget() async throws {
        let harness = try makeHarness(directoryClient: nil)
        let source = "same-node"
        do {
            _ = try await harness.facade.addManualTrustedContact(
                sourceNodeID: source,
                rawTargetInput: source,
                displayNameOverride: nil,
                note: nil,
                now: fixedNow
            )
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is ExchangeStoreError)
        }
    }

    // MARK: - Harness

    private func makeHarness(directoryClient: (any ExchangeDirectoryClient)?) throws -> Harness {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-manual-trusted-add-tests", isDirectory: true)
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
            intelligenceProvider: intelligence,
            directoryClient: directoryClient
        )

        return Harness(facade: facade, store: store)
    }

    private struct Harness {
        let facade: ExchangeFacade
        let store: ExchangeSQLiteStore
    }
}

// MARK: - Stub directory

private struct StubManualAddDirectoryClient: ExchangeDirectoryClient, Sendable {
    let matches: [ExchangeDirectoryMatch]

    func search(_ request: ExchangeDirectorySearchRequest) async throws -> ExchangeDirectorySearchResponse {
        _ = request
        return ExchangeDirectorySearchResponse(matches: matches, source: .remote)
    }

    func publishSellerSurface(
        _ request: ExchangeSellerSurfacePublishRequest
    ) async throws -> ExchangeSellerSurfacePublishResponse {
        _ = request
        throw ExchangeDirectoryClientError.backendFailure(reason: "stub")
    }

    func unpublishSellerSurface(
        nodeID: String,
        publicProfileID: String
    ) async throws -> ExchangeSellerSurfaceUnpublishResponse {
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

// MARK: - Minimal federation stub (reuse pattern from trusted message tests)

private actor TestFederationService: ExchangeFederationService {
    let store: ExchangeSQLiteStore
    let eligibilityAllowed: Bool
    let queueAllowed: Bool

    init(store: ExchangeSQLiteStore, eligibilityAllowed: Bool, queueAllowed: Bool) {
        self.store = store
        self.eligibilityAllowed = eligibilityAllowed
        self.queueAllowed = queueAllowed
    }

    func evaluateSendEligibility(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        draft: ExchangeMessageDraft
    ) async throws -> ExchangeFederationSendEligibility {
        _ = thread
        _ = counterparty
        _ = draft
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
            payloadSummary: "Manual trusted add test"
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
        throw ExchangeFederationError.transportFailed(reason: "stub")
    }

    func flushOutbox(now: Date) async throws -> ExchangeFederationFlushResult {
        _ = now
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

    func recentAudit(
        threadID: ExchangeThread.ID?,
        limit: Int
    ) async throws -> [ExchangeAuditRecord] {
        _ = threadID
        _ = limit
        return []
    }
}
