import Foundation
import os
import XCTest
@testable import AnumCore

/// Validates `ExchangeSyncEngine.syncInbound` pagination, cursor advancement, ACK batching,
/// and stall handling using a scripted `ExchangeRelayClient`.
///
/// Inbound envelopes are **parentless first-contact** compatible (unsigned, nil sender PK)
/// so `receiveEnvelope` → `reconcileInbox` can reconcile and produce ACK-eligible receipts.
final class ExchangeSyncEngineInboundPaginationTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_741_209_600)

    override func setUp() {
        super.setUp()
        setenv("ANUM_DISABLE_RUNTIME_PREWARM", "1", 1)
        setenv("ANUM_DISABLE_ONDEVICE_LLM", "1", 1)
    }

    func test_syncInbound_twoPages_advancesCursor_andAcksEachReconciledReceipt() async throws {
        let relay = ScriptedInboundRelayClient()
        let bundle = try makeBundle(relay: relay)

        let envA = "sync-pagination-env-a-\(UUID().uuidString.prefix(8))"
        let envB = "sync-pagination-env-b-\(UUID().uuidString.prefix(8))"
        let recv1 = inboundReceipt(stableEnvelopeKey: envA, receiptID: "rec-a", senderNode: "remote-node-page1")
        let recv2 = inboundReceipt(stableEnvelopeKey: envB, receiptID: "rec-b", senderNode: "remote-node-page2")

        relay.enqueueInboxPages([
            ExchangeRelayInboxSyncResponse(
                receipts: [recv1],
                nextCursor: "cursor-after-page1",
                hasMore: true,
                syncedAt: fixedNow,
                note: "page1"
            ),
            ExchangeRelayInboxSyncResponse(
                receipts: [recv2],
                nextCursor: nil,
                hasMore: false,
                syncedAt: fixedNow,
                note: "page2-terminal"
            )
        ])

        let result = try await bundle.syncEngine.syncInbound(from: nil, now: fixedNow)

        XCTAssertEqual(result.pagesFetched, 2, "Expected two inbound pages.")
        XCTAssertTrue(result.didFetchAnything)

        XCTAssertEqual(relay.capturedInboundCursors(), [nil, "cursor-after-page1"])

        XCTAssertEqual(
            Set(relay.flattenedAcknowledgedStableEnvelopeIDs()),
            Set([envA, envB]),
            "Each reconciled envelope should be ACK'd once."
        )

        // Terminal page returned `nextCursor: nil`, so persisted checkpoint falls back to the last request cursor.
        XCTAssertEqual(result.nextCheckpoint, "cursor-after-page1")
    }

    func test_syncInbound_repeatingNextCursor_stallsWithoutInfiniteLoop_andPagesCapped() async throws {
        let relay = ScriptedInboundRelayClient()
        let bundle = try makeBundle(relay: relay)

        let envKey = "sync-stall-env-\(UUID().uuidString.prefix(8))"
        let recv = inboundReceipt(stableEnvelopeKey: envKey, receiptID: "stall-rec", senderNode: "remote-stall-node")

        // Page 2 returns the same cursor as page 2 request (checkpoint == next), triggering stall branch.
        let stallCursor = "cursor-stalls"
        relay.enqueueInboxPages([
            ExchangeRelayInboxSyncResponse(
                receipts: [recv],
                nextCursor: stallCursor,
                hasMore: true,
                syncedAt: fixedNow,
                note: "advance"
            ),
            ExchangeRelayInboxSyncResponse(
                receipts: [inboundReceipt(
                    stableEnvelopeKey: "sync-stall-env-orphan-\(UUID().uuidString.prefix(8))",
                    receiptID: "stall-rec-page2-unused",
                    senderNode: "remote-stall-node-2"
                )],
                nextCursor: stallCursor,
                hasMore: true,
                syncedAt: fixedNow,
                note: "duplicate-cursor-page"
            )
        ])

        let result = try await bundle.syncEngine.syncInbound(from: nil, now: fixedNow)

        XCTAssertEqual(result.pagesFetched, 2, "Should stop after detecting repeated cursor.")
        XCTAssertLessThanOrEqual(result.pagesFetched, 10, "Safety cap honored by bounded loop.")

        XCTAssertEqual(relay.capturedInboundCursors(), [nil, stallCursor])

        XCTAssertEqual(result.nextCheckpoint, stallCursor)

        XCTAssertEqual(relay.acknowledgementCallsCount(), 2, "Both pages had reconciled envelopes before stall exit.")
        XCTAssertEqual(relay.flattenedAcknowledgedStableEnvelopeIDs().count, 2)
    }

    func test_syncInbound_emptySecondPage_updatesCheckpointWithoutAck() async throws {
        let relay = ScriptedInboundRelayClient()
        let bundle = try makeBundle(relay: relay)

        let envKey = "sync-empty-tail-env-\(UUID().uuidString.prefix(8))"
        let recv = inboundReceipt(stableEnvelopeKey: envKey, receiptID: "tail-empty-rec", senderNode: "remote-tail-node")
        let tailCheckpoint = "tail-checkpoint-marker"

        relay.enqueueInboxPages([
            ExchangeRelayInboxSyncResponse(
                receipts: [recv],
                nextCursor: "cursor-to-empty-page",
                hasMore: true,
                syncedAt: fixedNow,
                note: "page1-real"
            ),
            ExchangeRelayInboxSyncResponse(
                receipts: [],
                nextCursor: tailCheckpoint,
                hasMore: false,
                syncedAt: fixedNow,
                note: "empty-terminal"
            )
        ])

        let result = try await bundle.syncEngine.syncInbound(from: nil, now: fixedNow)

        XCTAssertEqual(result.pagesFetched, 2)
        XCTAssertEqual(result.nextCheckpoint?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), tailCheckpoint)

        let envelopesAckedSet = Set(relay.flattenedAcknowledgedStableEnvelopeIDs())
        XCTAssertEqual(envelopesAckedSet, [envKey])

        XCTAssertEqual(relay.acknowledgementCallsCount(), 1, "Terminal empty page skips ACK invocation.")
    }

    // MARK: - Harness

    private func makeBundle(relay: ExchangeRelayClient) throws -> ExchangeBootstrap.Bundle {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-sync-pagination-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbURL = tmp.appendingPathComponent("exchange.sqlite")

        let deps = ExchangeBootstrap.Dependencies(
            relayClient: relay,
            syncPolicy: ExchangeSyncPolicy(minSecondsBetweenLaunchRuns: 0, minSecondsBetweenActiveRuns: 0)
        )
        return try ExchangeBootstrap.makeBundle(databaseURL: dbURL, dependencies: deps)
    }

    /// Parentless inbound envelope: compatible with bootstrap identity (missing signature + nil sender publicKeyID → supported).
    private func inboundEnvelope(stableEnvelopeKey: String, senderNode: String, threadSeed: UUID) -> ExchangeRelayEnvelope {
        ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow,
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: threadSeed,
            sender: ExchangeRelayEnvelope.Party(
                nodeID: senderNode,
                displayName: "Remote Sender",
                publicKeyID: nil
            ),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: "local-recipient-placeholder")),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .followUp,
                subject: nil,
                body: "Synced inbound body \(stableEnvelopeKey)"
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 1,
                parentEnvelopeID: nil,
                idempotencyKey: stableEnvelopeKey
            )
        )
    }

    private func inboundReceipt(
        stableEnvelopeKey: String,
        receiptID: String,
        senderNode: String,
        receiverThreadSeed: UUID = UUID()
    ) -> ExchangeRelayInboundReceipt {
        ExchangeRelayInboundReceipt(
            receiptID: receiptID,
            mailboxNodeID: nil,
            receivedAt: fixedNow,
            envelope: inboundEnvelope(stableEnvelopeKey: stableEnvelopeKey, senderNode: senderNode, threadSeed: receiverThreadSeed),
            route: ExchangeRelayRoute?.none,
            externalReference: nil,
            status: .new,
            compatibility: .supported,
            metadata: [:]
        )
    }
}

// MARK: - Scripted relay client

private final class ScriptedRelayState: @unchecked Sendable {
    var inboxPageQueue: [ExchangeRelayInboxSyncResponse] = []
    var syncRequestsRecorded: [ExchangeRelayInboxSyncRequest] = []
    var ackBatchesRecorded: [[[ExchangeRelayInboxAcknowledgement]]] = []
}

private final class ScriptedInboundRelayClient: ExchangeRelayClient, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: ScriptedRelayState())

    func enqueueInboxPages(_ pages: [ExchangeRelayInboxSyncResponse]) {
        lock.withLock { $0.inboxPageQueue = pages }
    }

    func capturedInboundCursors() -> [String?] {
        lock.withLock { state in
            state.syncRequestsRecorded.map { $0.cursor?.nilIfBlank }
        }
    }

    func acknowledgementCallsCount() -> Int {
        lock.withLock { $0.ackBatchesRecorded.count }
    }

    func flattenedAcknowledgedStableEnvelopeIDs() -> [String] {
        lock.withLock { state in
            state.ackBatchesRecorded.flatMap { batch in
                batch.flatMap { acks in
                    acks.compactMap {
                        $0.envelopeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                    }
                }
            }
        }
    }

    func send(
        _: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?
    ) async throws -> ExchangeRelaySendResult {
        _ = route
        return ExchangeRelaySendResult(status: .accepted, acceptedAt: Date())
    }

    func fetchDeliveryStatus(reference _: String) async throws -> ExchangeRelayDeliveryStatus? { nil }

    func syncInbox(request: ExchangeRelayInboxSyncRequest) async throws -> ExchangeRelayInboxSyncResponse {
        try lock.withLock { state in
            state.syncRequestsRecorded.append(request)
            guard !state.inboxPageQueue.isEmpty else {
                XCTFail("ScriptedInboundRelayClient: unexpected syncInbox without queued response.")
                throw ExchangeRelayClientError.transportFailure(reason: "missing scripted inbox page")
            }
            return state.inboxPageQueue.removeFirst()
        }
    }

    func acknowledgeInboxItems(_ acknowledgements: [ExchangeRelayInboxAcknowledgement]) async throws
        -> ExchangeRelayInboxAcknowledgeResponse
    {
        lock.withLock { state in
            if !acknowledgements.isEmpty {
                state.ackBatchesRecorded.append([acknowledgements])
            }
            return ExchangeRelayInboxAcknowledgeResponse(
                acknowledgedReceiptIDs: acknowledgements.map(\.receiptID),
                rejectedReceiptIDs: [],
                updatedCount: acknowledgements.count,
                note: nil
            )
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
