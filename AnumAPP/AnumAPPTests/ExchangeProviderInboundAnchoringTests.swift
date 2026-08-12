import Foundation
import XCTest
@testable import AnumCore

final class ExchangeProviderInboundAnchoringTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_726_000_000)

    override func setUp() {
        super.setUp()
        setenv("ANUM_DISABLE_RUNTIME_PREWARM", "1", 1)
        setenv("ANUM_DISABLE_ONDEVICE_LLM", "1", 1)
    }

    /// A. Outgoing envelopes include `selected_offer_id` metadata when the thread anchors an offer.
    func test_buildEnvelope_includesSelectedOfferID_whenThreadAnchorsOffer() async throws {
        let threadID = UUID()
        let offerID = "00000000-0000-0000-0000-00000000ABCD"
        let counterpartyID = "cp-anchor-test"
        let profileID = "pub-profile-anchor-test"

        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Anchoring envelope metadata fixture",
            objective: "Exercise buildMetadata anchors.",
            readiness: .ready
        )

        let thread = ExchangeThread(
            id: threadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            mode: .transactional,
            intent: intent,
            posture: .default,
            state: .matchFound(.init(foundAt: fixedNow, candidateCount: 1, summary: "Fixture")),
            selectedCounterpartyID: counterpartyID,
            selectedPublicProfileID: profileID,
            selectedOfferID: offerID
        )

        let counterparty = ExchangeCounterparty(
            id: counterpartyID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .person,
            displayName: "Fixture CP",
            source: .manualEntry,
            identity: .init(
                nodeID: counterpartyID,
                publicKeyID: nil,
                verification: .unverified
            )
        )

        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: counterpartyID,
            counterpartyID: counterpartyID,
            displayName: "Fixture Pub",
            createdAt: fixedNow,
            updatedAt: fixedNow
        )

        let draft = ExchangeMessageDraft(
            threadID: threadID,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Hello from fixture",
            posture: .default,
            targetCounterpartyID: counterpartyID
        )

        let identity = BootstrappedIdentityService()
        let service = ExchangeEnvelopeService(identityService: identity)

        let built = try await service.buildEnvelope(
            thread: thread,
            counterparty: counterparty,
            publicProfile: profile,
            draft: draft,
            disclosureLevel: .balanced,
            sequenceNumber: 1,
            idempotencyKey: "fixture-anchor-metadata-key"
        )

        XCTAssertEqual(built.envelope.metadata["selected_offer_id"], offerID)
        XCTAssertEqual(built.envelope.metadata["selected_public_profile_id"], profileID)
        XCTAssertEqual(built.envelope.metadata["public_profile_id"], profileID)
    }

    /// B. receiveEnvelope merges allow-listed sender envelope metadata into inbox rows.
    func test_receiveEnvelope_preservesAllowlistedAnchors_butNotArbitraryKeys() async throws {
        let store = try makeEmptyStore()
        let (federation, identity) = makeFederationService(store: store)
        let localNodeID = try await identity.localIdentity().nodeID
        let senderNode = "prov-anchor-inbound-sender"

        let stableKey = "inbox-anchor-stable-001"
        let unrelatedThreadHandle = UUID()
        let envelope = ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow,
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: unrelatedThreadHandle,
            sender: ExchangeRelayEnvelope.Party(nodeID: senderNode, displayName: "Sender", publicKeyID: nil),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: localNodeID)),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .introduction,
                subject: "Offer question",
                body: "Availability next week?",
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 1,
                parentEnvelopeID: nil,
                idempotencyKey: stableKey
            ),
            metadata: [
                "selected_offer_id": "offer-allowlist-001",
                "selected_public_profile_id": "prof-allowlist-001",
                "internal_trade_secret": "nope-should-not-appear",
                "selected_match_rationale": "also-not-allowlisted",
            ]
        )

        let result = try await federation.receiveEnvelope(envelope, route: nil, receivedAt: fixedNow)
        XCTAssertEqual(result.inboxItem.envelopeID, stableKey)

        let fetchedInboxItem = try await store.fetchInboxItem(id: result.inboxItem.id)
        let persisted = try XCTUnwrap(fetchedInboxItem)
        XCTAssertEqual(persisted.metadata["selected_offer_id"], "offer-allowlist-001")
        XCTAssertEqual(persisted.metadata["selected_public_profile_id"], "prof-allowlist-001")
        XCTAssertNil(persisted.metadata["internal_trade_secret"])
        XCTAssertNil(persisted.metadata["selected_match_rationale"])
    }

    /// C + E (first-contact): reconcile creates a grounded thread with anchors and last inbound envelope pointer.
    func test_firstContactReconcile_appliesAnchorsAndLastInboundEnvelope() async throws {
        let store = try makeEmptyStore()
        let (federation, identity) = makeFederationService(store: store)
        let localNodeID = try await identity.localIdentity().nodeID
        let senderNode = "prov-first-contact-node"

        let stableKey = "first-contact-stable-77"
        let profileAnchor = "pp-first-contact-match"
        let offerAnchor = "offer-first-contact-match"

        let envelope = ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow,
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: UUID(),
            sender: ExchangeRelayEnvelope.Party(nodeID: senderNode, displayName: "Requester Secretary", publicKeyID: nil),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: localNodeID)),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .introduction,
                subject: "Inbound inquiry subject",
                body: "Inbound inquiry body preview text for fixture.",
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 1,
                parentEnvelopeID: nil,
                idempotencyKey: stableKey
            ),
            metadata: [
                "selected_offer_id": offerAnchor,
                "matched_profile_id": profileAnchor,
            ]
        )

        _ = try await federation.receiveEnvelope(envelope, route: nil, receivedAt: fixedNow)
        let reconcile = try await federation.reconcileInbox(now: fixedNow.addingTimeInterval(5))
        XCTAssertEqual(reconcile.reconciledCount, 1)

        let inboxMaybe = try await store.fetchInboxItemByEnvelopeID(stableKey)
        let inbox = try XCTUnwrap(inboxMaybe)
        let linkedThreadID = try XCTUnwrap(inbox.threadID)
        let threadMaybe = try await store.fetchThread(id: linkedThreadID)
        let thread = try XCTUnwrap(threadMaybe)

        XCTAssertEqual(thread.selectedOfferID, offerAnchor)
        XCTAssertEqual(thread.selectedPublicProfileID, profileAnchor)
        XCTAssertEqual(thread.selectedCounterpartyID, senderNode)
        XCTAssertEqual(thread.lastInboundEnvelopeID, stableKey)
    }

    func test_receiveEnvelope_selfSender_ignored_noReplyTurn() async throws {
        let store = try makeEmptyStore()
        let (federation, identity) = makeFederationService(store: store)
        let localNodeID = try await identity.localIdentity().nodeID

        let stableKey = "self-echo-stable-001"
        let envelope = ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow,
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: UUID(),
            sender: ExchangeRelayEnvelope.Party(nodeID: localNodeID, displayName: "Local", publicKeyID: nil),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: localNodeID)),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .followUp,
                subject: nil,
                body: "echo body",
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 1,
                parentEnvelopeID: nil,
                idempotencyKey: stableKey
            ),
            metadata: [:]
        )

        _ = try await federation.receiveEnvelope(envelope, route: nil, receivedAt: fixedNow)
        let reconcile = try await federation.reconcileInbox(now: fixedNow.addingTimeInterval(1))
        XCTAssertEqual(reconcile.reconciledCount, 0)

        let inbox = try await store.fetchInboxItemByEnvelopeID(stableKey)
        XCTAssertEqual(inbox?.processingState, .duplicateIgnored)
        let threads = try await store.listThreads(filter: .init(limit: nil))
        XCTAssertTrue(threads.isEmpty)
    }

    func test_receiveEnvelope_recipientMismatch_ignored_noReconcile() async throws {
        let store = try makeEmptyStore()
        let (federation, identity) = makeFederationService(store: store)
        _ = try await identity.localIdentity().nodeID

        let stableKey = "recipient-mismatch-stable-001"
        let envelope = ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow,
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: UUID(),
            sender: ExchangeRelayEnvelope.Party(nodeID: "remote-node", displayName: "Remote", publicKeyID: nil),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: "different-local-node")),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .followUp,
                subject: nil,
                body: "wrong recipient",
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 1,
                parentEnvelopeID: nil,
                idempotencyKey: stableKey
            ),
            metadata: [:]
        )

        _ = try await federation.receiveEnvelope(envelope, route: nil, receivedAt: fixedNow)
        let reconcile = try await federation.reconcileInbox(now: fixedNow.addingTimeInterval(1))
        XCTAssertEqual(reconcile.reconciledCount, 0)
        let inbox = try await store.fetchInboxItemByEnvelopeID(stableKey)
        XCTAssertEqual(inbox?.processingState, .duplicateIgnored)
    }

    func test_receiveEnvelope_matchesLocalOutbox_ignored() async throws {
        let store = try makeEmptyStore()
        let (federation, identity) = makeFederationService(store: store)
        let localNodeID = try await identity.localIdentity().nodeID
        let stableKey = "local-outbox-echo-stable-001"

        let threadID = UUID()
        let draftID = UUID()
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture",
            objective: "Fixture",
            readiness: .ready
        )
        let thread = ExchangeThread(
            id: threadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            mode: .transactional,
            intent: intent,
            posture: .default,
            state: .drafting,
            selectedCounterpartyID: "remote-node"
        )
        try await store.createThread(thread)
        try await store.saveDraft(
            ExchangeMessageDraft(
                id: draftID,
                threadID: threadID,
                createdAt: fixedNow,
                updatedAt: fixedNow,
                kind: .followUp,
                audience: .externalCounterparty,
                body: "outbound body",
                posture: .default,
                targetCounterpartyID: "remote-node"
            )
        )
        try await store.saveOutboxItem(
            ExchangeOutboxItem(
                threadID: threadID,
                draftID: draftID,
                targetNodeID: "remote-node",
                envelopeID: stableKey,
                payloadSummary: "outbound summary"
            )
        )

        let envelope = ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow,
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: threadID,
            sender: ExchangeRelayEnvelope.Party(nodeID: "remote-node", displayName: "Remote", publicKeyID: nil),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: localNodeID)),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .followUp,
                subject: nil,
                body: "echoed outbound",
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 1,
                parentEnvelopeID: nil,
                idempotencyKey: stableKey
            ),
            metadata: [:]
        )

        _ = try await federation.receiveEnvelope(envelope, route: nil, receivedAt: fixedNow)
        let reconcile = try await federation.reconcileInbox(now: fixedNow.addingTimeInterval(1))
        XCTAssertEqual(reconcile.reconciledCount, 0)
        let inbox = try await store.fetchInboxItemByEnvelopeID(stableKey)
        XCTAssertEqual(inbox?.processingState, .duplicateIgnored)
    }

    func test_validCounterpartyReply_stillReconciles() async throws {
        let store = try makeEmptyStore()
        let (federation, identity) = makeFederationService(store: store)
        let localNodeID = try await identity.localIdentity().nodeID

        let threadID = UUID()
        let draftID = UUID()
        let parentEnvelopeID = "valid-parent-envelope-001"
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture",
            objective: "Fixture",
            readiness: .ready
        )
        try await store.createThread(
            ExchangeThread(
                id: threadID,
                createdAt: fixedNow,
                updatedAt: fixedNow,
                mode: .transactional,
                intent: intent,
                posture: .default,
                state: .awaitingResponse(.init(since: fixedNow, lastOutboundAt: fixedNow)),
                selectedCounterpartyID: "remote-node"
            )
        )
        try await store.saveDraft(
            ExchangeMessageDraft(
                id: draftID,
                threadID: threadID,
                createdAt: fixedNow,
                updatedAt: fixedNow,
                kind: .followUp,
                audience: .externalCounterparty,
                body: "sent",
                posture: .default,
                targetCounterpartyID: "remote-node"
            )
        )
        try await store.saveOutboxItem(
            ExchangeOutboxItem(
                threadID: threadID,
                draftID: draftID,
                targetNodeID: "remote-node",
                envelopeID: parentEnvelopeID,
                payloadSummary: "sent"
            )
        )

        let inboundStable = "valid-inbound-stable-001"
        let envelope = ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow.addingTimeInterval(10),
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: threadID,
            sender: ExchangeRelayEnvelope.Party(nodeID: "remote-node", displayName: "Remote", publicKeyID: nil),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: localNodeID)),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .followUp,
                subject: nil,
                body: "valid reply",
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 2,
                parentEnvelopeID: parentEnvelopeID,
                idempotencyKey: inboundStable
            ),
            metadata: ["conversation_id": parentEnvelopeID]
        )

        _ = try await federation.receiveEnvelope(envelope, route: nil, receivedAt: fixedNow.addingTimeInterval(11))
        let reconcile = try await federation.reconcileInbox(now: fixedNow.addingTimeInterval(12))
        XCTAssertEqual(reconcile.reconciledCount, 1)
        XCTAssertTrue(reconcile.reconciledEnvelopeIDs.contains(inboundStable))
    }

    /// D — patch only missing anchors + E on existing-thread path; inbound `matched_offer_id` variant.
    func test_existingThread_reconcilePatchesMissingAnchors_andDoesNotOverwrite() async throws {
        let store = try makeEmptyStore()
        let (federation, identity) = makeFederationService(store: store)
        let localNodeID = try await identity.localIdentity().nodeID
        let senderNode = "prov-existing-route-sender"

        let threadID = UUID()
        let draftID = UUID()
        let parentEnv = "outbox-parent-env-fixed-9901"
        let profileAnchor = "pp-existing-patch"

        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture existing inbound route",
            objective: "Respond to counterparties.",
            readiness: .ready
        )

        let threadBefore = ExchangeThread(
            id: threadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            mode: .transactional,
            intent: intent,
            posture: .default,
            state: .matchFound(
                .init(
                    foundAt: fixedNow,
                    candidateCount: 1,
                    summary: "Fixture match anchor",
                    selectedCounterpartyID: senderNode,
                    selectedPublicProfileID: profileAnchor,
                    selectedOfferID: "EXISTING-OFFER-ANCHOR"
                )
            ),
            selectedCounterpartyID: senderNode,
            selectedPublicProfileID: profileAnchor,
            selectedOfferID: "EXISTING-OFFER-ANCHOR",
            lastInboundEnvelopeID: nil,
            metadata: [:]
        )
        try await store.createThread(threadBefore)

        let draft = ExchangeMessageDraft(
            id: draftID,
            threadID: threadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .followUp,
            audience: .externalCounterparty,
            body: "Fixture outbound parental context",
            posture: .default,
            targetCounterpartyID: senderNode
        )
        try await store.saveDraft(draft)

        let outbox = ExchangeOutboxItem(
            threadID: threadID,
            draftID: draftID,
            targetNodeID: senderNode,
            envelopeID: parentEnv,
            payloadSummary: "Fixture outbound"
        )
        try await store.saveOutboxItem(outbox)

        let counterparty = ExchangeCounterparty(
            id: senderNode,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .secretaryNode,
            displayName: "Remote Secretary",
            source: .relayNetwork,
            identity: .init(nodeID: senderNode, publicKeyID: nil, verification: .unverified),
            trust: .unverified,
            status: .active
        )
        try await store.upsertCounterparties([counterparty])

        /// Thread missing profile but carries offer anchor (patched via `public_profile_id`).
        let patchThreadID = UUID()
        let patchDraftID = UUID()
        let patchParentEnv = "outbox-parent-env-patch-prof-6622"
        let threadPatchOnlyOffer = ExchangeThread(
            id: patchThreadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            mode: .transactional,
            intent: intent,
            posture: .default,
            state: .matchFound(
                .init(
                    foundAt: fixedNow,
                    candidateCount: 1,
                    summary: "Fixture profile patch target",
                    selectedCounterpartyID: senderNode,
                    selectedOfferID: "OFFER-only-before"
                )
            ),
            selectedCounterpartyID: senderNode,
            selectedOfferID: "OFFER-only-before",
            lastInboundEnvelopeID: nil,
            metadata: [:]
        )
        try await store.createThread(threadPatchOnlyOffer)

        let patchDraft = ExchangeMessageDraft(
            id: patchDraftID,
            threadID: patchThreadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            kind: .followUp,
            audience: .externalCounterparty,
            body: "Parent for profile patch reconcile",
            posture: .default,
            targetCounterpartyID: senderNode
        )
        try await store.saveDraft(patchDraft)
        try await store.saveOutboxItem(
            ExchangeOutboxItem(
                threadID: patchThreadID,
                draftID: patchDraftID,
                targetNodeID: senderNode,
                envelopeID: patchParentEnv,
                payloadSummary: "Fixture outbound patch profile"
            )
        )

        let stableOverwrite = "inbound-stable-overwrite-881"
        let envOverwrite = ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow.addingTimeInterval(60),
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: threadID,
            sender: ExchangeRelayEnvelope.Party(nodeID: senderNode, displayName: "Remote Secretary", publicKeyID: nil),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: localNodeID)),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .followUp,
                subject: nil,
                body: "Reply with contradictory anchors that must be ignored.",
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 2,
                parentEnvelopeID: parentEnv,
                idempotencyKey: stableOverwrite
            ),
            metadata: [
                "matched_offer_id": "SHOULD-NOT-REPLACE",
                "public_profile_id": "SHOULD-NOT-REPLACE-PROFILE",
            ]
        )

        let stablePatchProfile = "inbound-stable-patch-profile-882"
        let envPatchProfile = ExchangeRelayEnvelope(
            id: UUID(),
            createdAt: fixedNow.addingTimeInterval(61),
            protocolVersion: ExchangeProtocolVersion.current,
            threadID: patchThreadID,
            sender: ExchangeRelayEnvelope.Party(nodeID: senderNode, displayName: "Remote Secretary", publicKeyID: nil),
            recipient: ExchangeRelayEnvelope.Recipient(route: .node(id: localNodeID)),
            payload: ExchangeRelayEnvelope.Payload(
                kind: .followUp,
                subject: nil,
                body: "Adds missing public_profile_id anchor.",
                disclosureLevel: .balanced
            ),
            signature: nil,
            ordering: ExchangeRelayEnvelope.Ordering(
                sequenceNumber: 2,
                parentEnvelopeID: patchParentEnv,
                idempotencyKey: stablePatchProfile
            ),
            metadata: ["public_profile_id": "incoming-profile-augment"],
        )

        _ = try await federation.receiveEnvelope(envOverwrite, route: nil, receivedAt: fixedNow.addingTimeInterval(120))
        _ = try await federation.receiveEnvelope(envPatchProfile, route: nil, receivedAt: fixedNow.addingTimeInterval(121))

        let reconcile = try await federation.reconcileInbox(now: fixedNow.addingTimeInterval(600))
        XCTAssertEqual(reconcile.reconciledCount, 2)

        let loadedOverwrite = try await store.fetchThread(id: threadID)
        let afterOverwrite = try XCTUnwrap(loadedOverwrite)
        XCTAssertEqual(afterOverwrite.selectedOfferID, "EXISTING-OFFER-ANCHOR")
        XCTAssertEqual(afterOverwrite.selectedPublicProfileID, profileAnchor)
        XCTAssertEqual(afterOverwrite.lastInboundEnvelopeID, stableOverwrite)

        XCTAssertEqual(afterOverwrite.metadata["inbound_anchor_offer_mismatch"], "true")
        XCTAssertEqual(afterOverwrite.metadata["inbound_anchor_profile_mismatch"], "true")
        XCTAssertEqual(
            afterOverwrite.metadata["inbound_anchor_offer_inbound_suffix"],
            String("SHOULD-NOT-REPLACE".suffix(8))
        )
        XCTAssertEqual(
            afterOverwrite.metadata["inbound_anchor_offer_thread_suffix"],
            String("EXISTING-OFFER-ANCHOR".suffix(8))
        )
        XCTAssertEqual(
            afterOverwrite.metadata["inbound_anchor_profile_inbound_suffix"],
            String("SHOULD-NOT-REPLACE-PROFILE".suffix(8))
        )
        XCTAssertEqual(
            afterOverwrite.metadata["inbound_anchor_profile_thread_suffix"],
            String(profileAnchor.suffix(8))
        )

        let overwriteAudits = try await store.listAuditRecords(
            filter: ExchangeAuditFilter(threadID: threadID, envelopeID: stableOverwrite, limit: 10)
        )
        let overwriteAudit = try XCTUnwrap(overwriteAudits.first)
        XCTAssertEqual(overwriteAudit.metadata["anchor_offer_mismatch"], "true")
        XCTAssertEqual(overwriteAudit.metadata["anchor_profile_mismatch"], "true")
        XCTAssertEqual(
            overwriteAudit.metadata["inbound_offer_suffix"],
            String("SHOULD-NOT-REPLACE".suffix(8))
        )

        let loadedProfilePatch = try await store.fetchThread(id: patchThreadID)
        let afterProfilePatch = try XCTUnwrap(loadedProfilePatch)
        XCTAssertEqual(afterProfilePatch.selectedOfferID, "OFFER-only-before")
        XCTAssertEqual(afterProfilePatch.selectedPublicProfileID, "incoming-profile-augment")
        XCTAssertEqual(afterProfilePatch.lastInboundEnvelopeID, stablePatchProfile)
        XCTAssertNil(afterProfilePatch.metadata["inbound_anchor_profile_mismatch"])
        XCTAssertNil(afterProfilePatch.metadata["inbound_anchor_offer_mismatch"])

        XCTAssertEqual(reconcile.reconciledEnvelopeIDs.count, 2)
    }

    /// F. `makeInboundInquiryIfAvailable` propagates seller offer/profile anchor text for classification.
    func test_makeInboundInquiryIfAvailable_matchedAnchor_fromSelectedOffer() async throws {
        let harness = try makeFacadeHarness()

        let threadID = UUID()
        let anchoredOfferID = "inquiry-anchor-offer-fixture-554"
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Provider inbound qualification",
            objective: "Handle inbound inquiries.",
            readiness: .ready
        )

        let thread = ExchangeThread(
            id: threadID,
            createdAt: fixedNow,
            updatedAt: fixedNow,
            mode: .transactional,
            intent: intent,
            posture: .default,
            state: .awaitingResponse(.init(since: fixedNow)),
            selectedCounterpartyID: "sender-node-fixture",
            selectedOfferID: anchoredOfferID,
            visibleSummary: "Fixture inbound qualification",
            lastInboundEnvelopeID: "last-env-present-887",
            metadata: [:]
        )

        let inquiry = await harness.facade.test_support_makeInboundInquiryIfAvailable(
            thread: thread,
            turns: [],
            selectedCounterparty: nil,
            knownFacts: [],
            unresolvedIssues: []
        )

        let unwrapped = try XCTUnwrap(inquiry)
        XCTAssertEqual(unwrapped.matchedOfferOrProfileAnchor, anchoredOfferID)
    }

    /// G. Hydrated operating memory exposes non-empty seller contact facts for active visible offers only.
    func test_offerContactInfo_surfaces_inOperatingMemoryHydration_forActiveOffers() {
        let contactActive = ExchangeOffer.ContactInfo(
            contactName: "Alex Seller",
            businessName: "Compact Fixtures LLC",
            email: "seller@fixture.test",
            phone: "+15550199",
            website: "fixture.test",
            preferredContactMethod: .email,
            availabilityNote: "Weekdays until 7pm ET",
            serviceAddressOrArea: "Remote / US Eastern"
        )
        let visibleOffer = ExchangeOffer(
            id: "offer-hydr-contact-1",
            nodeID: "node-hydr-1",
            publicProfileID: "pp-hydr-1",
            title: "Studio session",
            status: .active,
            visibility: .publicDiscoverable,
            contactInfo: contactActive
        )
        let memVisible = ExchangeSellerSurfaceOperatingMemoryHydrator.hydrate(publicProfile: nil, offer: visibleOffer)

        func policyTexts(_ memory: ExchangeStructuredOperatingMemory) -> String {
            memory.standardPolicies
                .map { rule in "\(rule.title): \(rule.details)" }
                .joined(separator: " | ")
        }

        let blob = policyTexts(memVisible).lowercased()
        XCTAssertTrue(blob.contains("offer — preferred contact method".lowercased()))
        XCTAssertTrue(blob.contains("email"))
        XCTAssertTrue(blob.contains("+15550199"))
        XCTAssertTrue(blob.contains("fixture.test"))

        let hiddenOffer = ExchangeOffer(
            id: "offer-hydr-contact-hidden",
            nodeID: "node-hydr-2",
            publicProfileID: "pp-hydr-2",
            title: "Hidden listing",
            status: .active,
            visibility: .hidden,
            contactInfo: contactActive
        )
        let memHidden = ExchangeSellerSurfaceOperatingMemoryHydrator.hydrate(publicProfile: nil, offer: hiddenOffer)
        let hiddenBlob = policyTexts(memHidden).lowercased()
        XCTAssertFalse(hiddenBlob.contains("offer — email".lowercased()))
    }

    // MARK: - Harness

    private func makeTempDatabaseURL() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("exchange-provider-anchor-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("db-\(UUID().uuidString).sqlite")
    }

    private func makeEmptyStore() throws -> ExchangeSQLiteStore {
        try ExchangeSQLiteStore(databaseURL: makeTempDatabaseURL())
    }

    private func makeFederationService(
        store: ExchangeSQLiteStore
    ) -> (service: ExchangeDefaultFederationService, identity: BootstrappedIdentityService) {
        let identityService = BootstrappedIdentityService()
        let envelopeService = ExchangeEnvelopeService(identityService: identityService)
        let federation = ExchangeDefaultFederationService(
            store: store,
            policyEngine: ExchangePolicyEngine(),
            envelopeService: envelopeService,
            identityService: identityService,
            relayClient: EmptyRelayFixtureClient(),
            runtimeMonitor: ExchangeRuntimeActivityState(),
            transportPolicy: ExchangeTransportPolicy(),
            continuationCoordinator: ExchangeThreadContinuationCoordinator(),
            threadEngine: ExchangeThreadEngine()
        )
        return (federation, identityService)
    }

    private func makeFacadeHarness() throws -> (facade: ExchangeFacade, store: ExchangeSQLiteStore) {
        UserDefaults.standard.set(
            ExchangeModels.ExchangeThreadAutonomyMode.fullWithinBoundaries.rawValue,
            forKey: "secretary.threadAutonomy.mode"
        )

        let store = try makeEmptyStore()
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
        let envelopeService = ExchangeEnvelopeService(identityService: identityService)
        let federationService = ExchangeDefaultFederationService(
            store: store,
            policyEngine: policyEngine,
            envelopeService: envelopeService,
            identityService: identityService,
            relayClient: EmptyRelayFixtureClient(),
            runtimeMonitor: ExchangeRuntimeActivityState(),
            transportPolicy: ExchangeTransportPolicy(),
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

        return (facade, store)
    }
}

// MARK: - Test doubles

private struct EmptyRelayFixtureClient: ExchangeRelayClient {
    func send(
        _ envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?
    ) async throws -> ExchangeRelaySendResult {
        ExchangeRelaySendResult(status: .unknown)
    }

    func fetchDeliveryStatus(reference: String) async throws -> ExchangeRelayDeliveryStatus? {
        nil
    }

    func syncInbox(
        request: ExchangeRelayInboxSyncRequest
    ) async throws -> ExchangeRelayInboxSyncResponse {
        ExchangeRelayInboxSyncResponse(receipts: [])
    }

    func acknowledgeInboxItems(
        _ acknowledgements: [ExchangeRelayInboxAcknowledgement]
    ) async throws -> ExchangeRelayInboxAcknowledgeResponse {
        ExchangeRelayInboxAcknowledgeResponse(
            acknowledgedReceiptIDs: [],
            rejectedReceiptIDs: [],
            updatedCount: 0
        )
    }
}
