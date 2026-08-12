import Foundation
import Testing
@testable import AnumCore

@Suite("Contact signal friend request send (V2 lane)")
struct ContactSignalFriendRequestSendTests {
    @Test func sendDoesNotCreateThreadOrOutboxRow() async throws {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("contact-signal-send-tests-\(UUID().uuidString).sqlite", isDirectory: false)
        if FileManager.default.fileExists(atPath: db.path) {
            try FileManager.default.removeItem(at: db)
        }
        defer { try? FileManager.default.removeItem(at: db) }

        let bundle = try ExchangeBootstrap.makeBundle(
            databaseURL: db,
            dependencies: .init()
        )
        let facade = bundle.facade
        let store = bundle.store

        let threadsBefore = try await store.listThreads(filter: .init(limit: 500))
        let outboxBefore = try await store.listOutboxItems(filter: .init(activeOnly: false, limit: 500))

        let source = try await BootstrappedIdentityService().localIdentity().nodeID
        #expect(!source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let target = "acme-peer-contact-signal-01"
        _ = try await facade.sendContactRequestToNode(
            sourceNodeID: source,
            targetNodeID: target,
            displayNameOverride: "Target Display",
            note: "Hello from test",
            now: Date()
        )

        let threadsAfter = try await store.listThreads(filter: .init(limit: 500))
        #expect(threadsAfter.count == threadsBefore.count)

        let outboxAfter = try await store.listOutboxItems(filter: .init(activeOnly: false, limit: 500))
        #expect(outboxAfter.count == outboxBefore.count)

        let outgoing = try await store.listOutgoingContactRequests(
            filter: .init(targetNodeID: target, limit: 10)
        )
        #expect(outgoing.count == 1)
        #expect(outgoing[0].phase == .sent)
    }

    @Test func envelopeContractUsesContactFriendRequestMetadata() async throws {
        let identity = BootstrappedIdentityService()
        let envelopeService = ExchangeEnvelopeService(identityService: identity)
        let local = try await identity.localIdentity()
        let correlation = UUID()
        let counterparty = ExchangeCounterparty(
            id: "cp-node-xyz",
            kind: .person,
            displayName: "CP",
            source: .manualEntry,
            identity: .init(nodeID: "cp-node-xyz", publicKeyID: nil, verification: .unverified),
            publicProfile: ExchangePublicNodeProfile(
                id: "profile-1",
                nodeID: "cp-node-xyz",
                counterpartyID: "cp-node-xyz",
                displayName: "CP",
                reachability: .init(
                    accessMode: .direct,
                    acceptingInbound: true,
                    intentCategoryPolicy: .permissive,
                    disclosureCeiling: .balanced
                )
            )
        )
        let profile = counterparty.publicProfile!
        let built = try await envelopeService.buildContactFriendRequestEnvelope(
            correlationID: correlation,
            counterparty: counterparty,
            publicProfile: profile,
            subject: "Contact request",
            body: "Hi",
            disclosureLevel: .balanced,
            draftMetadata: [
                "sender_node_id": local.nodeID,
                "target_node_id": counterparty.id,
                "conversation_kind": "friend_request",
                "contact_request": "true",
                "introduction_request": "true"
            ],
            now: Date()
        )
        let env = built.envelope
        #expect(env.payload.kind == .friendRequest)
        #expect(env.metadata["conversation_surface"] == "contact")
        #expect(env.metadata["conversation_kind"] == "friend_request")
        #expect(env.metadata["contact_request"] == "true")
        #expect(env.metadata["target_node_id"] == counterparty.id)
        #expect(env.metadata["sender_node_id"] == local.nodeID)
    }

    @Test func duplicatePendingReturnsExistingWithoutSecondOutgoingRow() async throws {
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("contact-signal-dup-tests-\(UUID().uuidString).sqlite", isDirectory: false)
        if FileManager.default.fileExists(atPath: db.path) {
            try FileManager.default.removeItem(at: db)
        }
        defer { try? FileManager.default.removeItem(at: db) }

        let bundle = try ExchangeBootstrap.makeBundle(databaseURL: db, dependencies: .init())
        let facade = bundle.facade
        let store = bundle.store

        let source = try await BootstrappedIdentityService().localIdentity().nodeID
        #expect(!source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let target = "acme-peer-dup-bravo-02"

        let first = try await facade.sendContactRequestToNode(
            sourceNodeID: source,
            targetNodeID: target,
            displayNameOverride: nil,
            note: "one",
            now: Date()
        )
        let second = try await facade.sendContactRequestToNode(
            sourceNodeID: source,
            targetNodeID: target,
            displayNameOverride: nil,
            note: "two",
            now: Date()
        )

        #expect(first.envelopeID == second.envelopeID)
        #expect(first.outgoingContactRequestID == second.outgoingContactRequestID)

        let rows = try await store.listOutgoingContactRequests(filter: .init(targetNodeID: target, limit: 20))
        #expect(rows.count == 1)
    }

    @Test func inboundClassificationStillRecognizesFriendRequestSignal() async throws {
        let item = ExchangeInboxItem(
            envelopeID: "env-test-1",
            visibleSummary: "Contact request",
            metadata: [
                "conversation_surface": "contact",
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue,
                "conversation_kind": "friend_request"
            ]
        )
        #expect(ExchangeDefaultFederationService.contactRequestContract_isInboundFriendOrContactRequestSignal(item))
    }
}
