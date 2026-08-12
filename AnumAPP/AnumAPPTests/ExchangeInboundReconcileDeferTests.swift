import Foundation
import XCTest
@testable import AnumCore

/// When `ExchangeTransportPolicy` defers inbound receive (e.g. critical thermal),
/// `reconcileInbox` must not apply thread mutations yet — items stay `.deferred`.
final class ExchangeInboundReconcileDeferTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_726_000_000)

    override func setUp() {
        super.setUp()
        setenv("ANUM_DISABLE_RUNTIME_PREWARM", "1", 1)
        setenv("ANUM_DISABLE_ONDEVICE_LLM", "1", 1)
    }

    func test_reconcileInbox_defersWhenTransportPolicyDefersInboundReceive() async throws {
        let store = try makeEmptyStore()
        let identityService = BootstrappedIdentityService()
        let localNodeID = try await identityService.localIdentity().nodeID
        let senderNode = "defer-test-sender"

        let envelope = ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow,
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: UUID(),
            sender: ExchangeRelayEnvelope.Party(nodeID: senderNode, displayName: "S", publicKeyID: nil),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: localNodeID)),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .introduction,
                subject: "Hi",
                body: "Deferred reconcile fixture.",
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 1,
                parentEnvelopeID: nil,
                idempotencyKey: "defer-reconcile-stable-001"
            ),
            metadata: [:]
        )

        let envelopeService = ExchangeEnvelopeService(identityService: identityService)
        let runtime = FixtureRuntimeMonitor(
            snapshot: ExchangeRuntimeActivitySnapshot(
                isThermalCritical: true,
                allowsBackgroundWork: true
            )
        )
        let federation = ExchangeDefaultFederationService(
            store: store,
            policyEngine: ExchangePolicyEngine(),
            envelopeService: envelopeService,
            identityService: identityService,
            relayClient: EmptyRelayClient(),
            runtimeMonitor: runtime,
            transportPolicy: ExchangeTransportPolicy(),
            continuationCoordinator: ExchangeThreadContinuationCoordinator(),
            threadEngine: ExchangeThreadEngine()
        )

        _ = try await federation.receiveEnvelope(envelope, route: nil, receivedAt: fixedNow)
        let reconcile = try await federation.reconcileInbox(now: fixedNow.addingTimeInterval(1))

        XCTAssertEqual(reconcile.reconciledCount, 0)
        XCTAssertEqual(reconcile.deferredCount, 1)
        XCTAssertEqual(reconcile.rejectedCount, 0)

        let item = try await store.fetchInboxItemByEnvelopeID("defer-reconcile-stable-001")
        let loaded = try XCTUnwrap(item)
        XCTAssertEqual(loaded.processingState, .deferred)
    }

    private func makeTempDatabaseURL() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-inbound-defer-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("db-\(UUID().uuidString).sqlite")
    }

    private func makeEmptyStore() throws -> ExchangeSQLiteStore {
        try ExchangeSQLiteStore(databaseURL: makeTempDatabaseURL())
    }
}

// MARK: - Test doubles

private struct FixtureRuntimeMonitor: ExchangeRuntimeActivityMonitor {
    let snapshot: ExchangeRuntimeActivitySnapshot
    func snapshot() async -> ExchangeRuntimeActivitySnapshot { snapshot }
}

private struct EmptyRelayClient: ExchangeRelayClient {
    func send(_ envelope: ExchangeRelayEnvelope, route: ExchangeRelayRoute?) async throws -> ExchangeRelaySendResult {
        ExchangeRelaySendResult(status: .unknown)
    }

    func fetchDeliveryStatus(reference: String) async throws -> ExchangeRelayDeliveryStatus? { nil }

    func syncInbox(request: ExchangeRelayInboxSyncRequest) async throws -> ExchangeRelayInboxSyncResponse {
        ExchangeRelayInboxSyncResponse(receipts: [], hasMore: false)
    }

    func acknowledgeInboxItems(_ acknowledgements: [ExchangeRelayInboxAcknowledgement]) async throws -> ExchangeRelayInboxAcknowledgeResponse {
        ExchangeRelayInboxAcknowledgeResponse(acknowledgedReceiptIDs: [], updatedCount: 0)
    }
}
