import Foundation
import XCTest
@testable import AnumCore

private actor FixedTestIdentityService: ExchangeIdentityService {
    private let identity: ExchangeLocalIdentity

    init(nodeID: String = "local-contract-test-node") {
        self.identity = ExchangeLocalIdentity(
            nodeID: nodeID,
            displayName: "Contract Test Local",
            publicKeyID: "test-key",
            verification: .selfAsserted,
            supportedProtocolVersions: [ExchangeProtocolVersion.current],
            defaultRouteHint: nil,
            metadata: [:]
        )
    }

    func localIdentity() async throws -> ExchangeLocalIdentity {
        identity
    }

    func signEnvelope(_ envelope: ExchangeRelayEnvelope) async throws -> ExchangeRelayEnvelope.Signature {
        ExchangeRelayEnvelope.Signature(
            algorithm: .other,
            value: "test-sig:\(envelope.id.uuidString)",
            keyID: identity.publicKeyID,
            signatureVersion: "1"
        )
    }

    func verifyEnvelopeSignature(
        _ envelope: ExchangeRelayEnvelope,
        expectedKeyID: String?
    ) async throws -> ExchangeEnvelopeVerificationResult {
        if envelope.signature == nil, envelope.sender.publicKeyID == nil {
            return .missingSignature
        }
        return .valid
    }
}

final class ContactRequestFederationContractTests: XCTestCase {

    private let localNodeID = "local-contract-test-node"
    private let remoteSenderNodeID = "remote-peer-contract-node"

    private func contactThread() -> ExchangeThread {
        ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Contact request",
                objective: "Connect",
                readiness: .ready
            ),
            posture: .default,
            state: .draftReady(
                .init(preparedAt: Date(), summary: "Prepared", draftID: UUID())
            ),
            metadata: ["contact_request_thread": "true"]
        )
    }

    private func exchangeDeskThread() -> ExchangeThread {
        ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .generalDiscovery,
                title: "Inquiry",
                objective: "Ask supplier",
                readiness: .ready
            ),
            posture: .default,
            state: .draftReady(
                .init(preparedAt: Date(), summary: "Prepared", draftID: UUID())
            ),
            metadata: [:]
        )
    }

    private func counterparty(id: String) -> ExchangeCounterparty {
        ExchangeCounterparty(
            id: id,
            kind: .person,
            displayName: "Peer \(id)",
            source: .manualEntry,
            identity: .init(nodeID: id, publicKeyID: nil, verification: .unverified)
        )
    }

    private func publicProfile(nodeID: String, counterpartyID: String) -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: "profile-\(nodeID)",
            nodeID: nodeID,
            counterpartyID: counterpartyID,
            displayName: "Public \(nodeID)",
            reachability: .init(
                accessMode: .direct,
                acceptingInbound: true,
                intentCategoryPolicy: .permissive,
                disclosureCeiling: .balanced
            )
        )
    }

    private func route(to nodeID: String) -> ExchangeRelayRoute {
        ExchangeRelayRoute(
            routeKey: "node:\(nodeID)",
            kind: .node,
            destination: nodeID
        )
    }

    func testOutboundContactRequestMetadata_contract() throws {
        let svc = ExchangeEnvelopeService(identityService: FixedTestIdentityService(nodeID: localNodeID))
        let thread = contactThread()
        let cp = counterparty(id: remoteSenderNodeID)
        let profile = publicProfile(nodeID: remoteSenderNodeID, counterpartyID: cp.id)
        let draft = ExchangeMessageDraft(
            threadID: thread.id,
            kind: .introduction,
            audience: .externalCounterparty,
            subject: "Contact request",
            body: "Hello",
            posture: thread.posture,
            targetCounterpartyID: cp.id,
            metadata: [
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue,
                "conversation_kind": "friend_request",
                "contact_request": "true",
                "target_node_id": cp.id
            ]
        )

        let md = svc.contactRequestContract_buildMetadata(
            thread: thread,
            counterparty: cp,
            publicProfile: profile,
            draft: draft,
            requestedDisclosureLevel: .balanced,
            effectiveDisclosureLevel: .balanced,
            resolvedRoute: route(to: remoteSenderNodeID),
            resolvedTargetNodeID: remoteSenderNodeID
        )

        XCTAssertEqual(md["conversation_surface"], "contact")
        XCTAssertEqual(md["conversation_kind"], "friend_request")
        XCTAssertEqual(md["payload_kind"], ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue)
        XCTAssertEqual(md["contact_request"], "true")
        XCTAssertNotEqual(md["conversation_surface"], "exchange_thread")
    }

    func testOutboundExchangeDeskThread_stillExchangeSurface() throws {
        let svc = ExchangeEnvelopeService(identityService: FixedTestIdentityService(nodeID: localNodeID))
        let thread = exchangeDeskThread()
        let cp = counterparty(id: remoteSenderNodeID)
        let profile = publicProfile(nodeID: remoteSenderNodeID, counterpartyID: cp.id)
        let draft = ExchangeMessageDraft(
            threadID: thread.id,
            kind: .inquiry,
            audience: .externalCounterparty,
            subject: "Quote",
            body: "Pricing?",
            posture: thread.posture,
            targetCounterpartyID: cp.id,
            metadata: [:]
        )

        let md = svc.contactRequestContract_buildMetadata(
            thread: thread,
            counterparty: cp,
            publicProfile: profile,
            draft: draft,
            requestedDisclosureLevel: .balanced,
            effectiveDisclosureLevel: .balanced,
            resolvedRoute: route(to: remoteSenderNodeID),
            resolvedTargetNodeID: remoteSenderNodeID
        )

        XCTAssertEqual(md["conversation_surface"], "exchange_thread")
    }

    func testPayloadKind_contactRequestDraft_mapsToFriendRequest() {
        let svc = ExchangeEnvelopeService(identityService: FixedTestIdentityService())
        let threadID = UUID()
        let draft = ExchangeMessageDraft(
            threadID: threadID,
            kind: .introduction,
            audience: .externalCounterparty,
            body: "Hi",
            posture: .default,
            metadata: ["contact_request": "true"]
        )
        XCTAssertEqual(svc.contactRequestContract_payloadKind(for: draft), .friendRequest)
    }

    func testPayloadKind_legacyIntroduction_withoutContactFlag_staysIntroduction() {
        let svc = ExchangeEnvelopeService(identityService: FixedTestIdentityService())
        let threadID = UUID()
        let draft = ExchangeMessageDraft(
            threadID: threadID,
            kind: .introduction,
            audience: .externalCounterparty,
            body: "Intro",
            posture: .default,
            metadata: [:]
        )
        XCTAssertEqual(svc.contactRequestContract_payloadKind(for: draft), .introduction)
    }

    func testInboundFriendSignal_contactSurfaceAndKind() {
        let item = ExchangeInboxItem(
            envelopeID: "env-contract-1",
            senderNodeID: remoteSenderNodeID,
            senderDisplayName: "Remote",
            processingState: .received,
            visibleSummary: "Wants to connect",
            metadata: [
                "conversation_surface": "contact",
                "conversation_kind": "friend_request",
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue
            ]
        )
        XCTAssertTrue(ExchangeDefaultFederationService.contactRequestContract_isInboundFriendOrContactRequestSignal(item))
    }

    func testInboundFriendSignal_payloadKindOnly() {
        let item = ExchangeInboxItem(
            envelopeID: "env-contract-2",
            senderNodeID: remoteSenderNodeID,
            processingState: .received,
            visibleSummary: "Hi",
            metadata: ["payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue]
        )
        XCTAssertTrue(ExchangeDefaultFederationService.contactRequestContract_isInboundFriendOrContactRequestSignal(item))
    }

    func testInboundFriendSignal_falseForDirectMessageSurface() {
        let item = ExchangeInboxItem(
            envelopeID: "env-contract-dm",
            senderNodeID: remoteSenderNodeID,
            processingState: .received,
            visibleSummary: "DM",
            metadata: [
                "conversation_surface": "direct_message",
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.inquiry.rawValue
            ]
        )
        XCTAssertFalse(ExchangeDefaultFederationService.contactRequestContract_isInboundFriendOrContactRequestSignal(item))
    }

    func testInboundFriendSignal_falseForExchangeInquiry() {
        let item = ExchangeInboxItem(
            envelopeID: "env-contract-ex",
            senderNodeID: remoteSenderNodeID,
            processingState: .received,
            visibleSummary: "Inquiry",
            metadata: [
                "conversation_surface": "exchange_thread",
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.inquiry.rawValue
            ]
        )
        XCTAssertFalse(ExchangeDefaultFederationService.contactRequestContract_isInboundFriendOrContactRequestSignal(item))
    }

    func testIsContactRequestInboxItem_friendRequestPayload() {
        let item = ExchangeInboxItem(
            envelopeID: "env-cr-1",
            senderNodeID: remoteSenderNodeID,
            processingState: .reconciledIntoThread,
            visibleSummary: "x",
            metadata: ["payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue]
        )
        XCTAssertTrue(ExchangeFacade.isContactRequestInboxItem(item))
    }

    func testIsContactRequestInboxItem_contactSurfaceAndKind() {
        let item = ExchangeInboxItem(
            envelopeID: "env-cr-2",
            senderNodeID: remoteSenderNodeID,
            processingState: .reconciledIntoThread,
            visibleSummary: "x",
            metadata: [
                "conversation_surface": "contact",
                "conversation_kind": "friend_request",
                "payload_kind": "introduction"
            ]
        )
        XCTAssertTrue(ExchangeFacade.isContactRequestInboxItem(item))
    }

    func testIsContactRequestInboxItem_legacyContactRequestIntroduction() {
        let item = ExchangeInboxItem(
            envelopeID: "env-cr-3",
            senderNodeID: remoteSenderNodeID,
            processingState: .received,
            visibleSummary: "x",
            metadata: [
                "contact_request": "true",
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue
            ]
        )
        XCTAssertTrue(ExchangeFacade.isContactRequestInboxItem(item))
    }

    func testIsContactRequestInboxItem_plainIntroductionNotContactRequest() {
        let item = ExchangeInboxItem(
            envelopeID: "env-cr-4",
            senderNodeID: remoteSenderNodeID,
            processingState: .received,
            visibleSummary: "x",
            metadata: ["payload_kind": ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue]
        )
        XCTAssertFalse(ExchangeFacade.isContactRequestInboxItem(item))
    }

    func testReconcile_contactFriendRequest_doesNotCreateThreadOrTrust() async throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("contact-contract-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let deps = ExchangeBootstrap.Dependencies(identityService: FixedTestIdentityService(nodeID: localNodeID))
        let bundle = try ExchangeBootstrap.makeBundle(databaseURL: dbURL, dependencies: deps)
        let store = bundle.store
        let facade = bundle.facade

        let threadsBefore = try await store.listThreads(filter: ExchangeThreadFilter(limit: 500))
        XCTAssertEqual(threadsBefore.count, 0)

        let edgesBefore = try await store.listTrustEdges(
            filter: ExchangeTrustEdgeFilter(activeOnly: false, limit: 100)
        )
        XCTAssertEqual(edgesBefore.count, 0)

        let inbox = ExchangeInboxItem(
            envelopeID: "env-reconcile-contact-\(UUID().uuidString)",
            threadID: nil,
            senderNodeID: remoteSenderNodeID,
            senderDisplayName: "Remote Peer",
            ordering: .init(parentEnvelopeID: nil),
            compatibility: .supported,
            processingState: .received,
            visibleSummary: "Contact request",
            metadata: [
                "payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue,
                "conversation_surface": "contact",
                "conversation_kind": "friend_request",
                "contact_request": "true",
                "recipient_node_id": localNodeID
            ]
        )

        try await store.saveInboxItem(inbox)
        _ = try await facade.reconcileInbox(now: Date())

        let threadsAfter = try await store.listThreads(filter: ExchangeThreadFilter(limit: 500))
        XCTAssertEqual(
            threadsAfter.count,
            0,
            "Contact friend-request reconcile must not create an exchange work thread."
        )

        let edgesAfter = try await store.listTrustEdges(
            filter: ExchangeTrustEdgeFilter(activeOnly: false, limit: 100)
        )
        XCTAssertEqual(edgesAfter.count, 0, "Contact request reconcile must not create a trust edge.")

        let reloaded = try await store.requireInboxItem(id: inbox.id)
        XCTAssertEqual(reloaded.processingState, .reconciledIntoThread)
        XCTAssertNil(reloaded.threadID)
        XCTAssertTrue(ExchangeFacade.isContactRequestInboxItem(reloaded))

        let responseReceivedThreads = threadsAfter.filter { $0.intent.title.contains("Response received") }
        XCTAssertEqual(responseReceivedThreads.count, 0)
    }
}
