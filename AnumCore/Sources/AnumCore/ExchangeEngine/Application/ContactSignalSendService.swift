import Foundation

/// Outbound **contact signal** send lane (friend request). Does not use `ExchangeThread`, drafts, approvals, or exchange outbox.
public struct ContactSignalSendService: Sendable {
    private let store: any ExchangeStore
    private let envelopeService: ExchangeEnvelopeService
    private let relayClient: any ExchangeRelayClient

    public init(
        store: any ExchangeStore,
        envelopeService: ExchangeEnvelopeService,
        relayClient: any ExchangeRelayClient
    ) {
        self.store = store
        self.envelopeService = envelopeService
        self.relayClient = relayClient
    }

    public func sendFriendRequest(
        sourceNodeID: String,
        counterparty: ExchangeCounterparty,
        displayNameOverride: String?,
        note: String?,
        hydratedFromDirectory: Bool,
        now: Date
    ) async throws -> ExchangeModels.ContactRequestSendResult {
        let trimmedSource = sourceNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalTarget = counterparty.id.trimmingCharacters(in: .whitespacesAndNewlines)

        #if DEBUG
        Swift.print("[ContactRequestSendV2][start] targetNodeID=\(canonicalTarget)")
        #endif

        let executionProfile = Self.resolveExecutionPublicProfile(counterparty: counterparty)

        let body = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "I'd like to add you on Unify."
        let subject = "Contact request"

        var draftMeta: [String: String] = [
            "payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue,
            "conversation_kind": "friend_request",
            "contact_request": "true",
            "introduction_request": "true",
            "target_node_id": canonicalTarget,
            "sender_node_id": trimmedSource
        ]
        if let display = displayNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            draftMeta["sender_display_name"] = display
        }

        let correlationID = UUID()
        let built = try await envelopeService.buildContactFriendRequestEnvelope(
            correlationID: correlationID,
            counterparty: counterparty,
            publicProfile: executionProfile,
            subject: subject,
            body: body,
            disclosureLevel: .balanced,
            draftMetadata: draftMeta,
            routeHint: nil,
            now: now
        )

        let envelope = built.envelope
        let stableID = envelope.stableEnvelopeID

        #if DEBUG
        Swift.print(
            "[ContactRequestSendV2][envelope] envelopeID=\(stableID) correlationID=\(correlationID.uuidString) " +
                "surface=\(envelope.metadata["conversation_surface"] ?? "nil") " +
                "kind=\(envelope.metadata["conversation_kind"] ?? "nil") " +
                "payload=\(envelope.payload.kind.rawValue)"
        )
        #endif

        let profileID = counterparty.publicProfile?.id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        var record = OutgoingContactRequest(
            targetNodeID: canonicalTarget,
            targetDisplayName: counterparty.displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            targetProfileID: profileID,
            envelopeID: stableID,
            correlationID: correlationID,
            phase: .queued,
            body: body,
            createdAt: now,
            updatedAt: now,
            metadata: ["contact_signal_lane": "true"]
        )

        try await store.saveOutgoingContactRequest(record)
        #if DEBUG
        Swift.print("[ContactRequestSendV2][queued] requestID=\(record.id.uuidString)")
        #endif

        record.phase = .sending
        record.updatedAt = Date()
        try await store.saveOutgoingContactRequest(record)

        do {
            _ = try await relayClient.send(envelope, route: built.route)
            var sent = record
            sent.phase = .sent
            sent.updatedAt = Date()
            sent.sentAt = Date()
            sent.lastError = nil
            try await store.saveOutgoingContactRequest(sent)
            #if DEBUG
            Swift.print("[ContactRequestSendV2][sent] requestID=\(sent.id.uuidString) envelopeID=\(stableID)")
            #endif

            return ExchangeModels.ContactRequestSendResult(
                targetNodeID: canonicalTarget,
                threadID: nil,
                outboxItemID: nil,
                envelopeID: stableID,
                outgoingContactRequestID: sent.id,
                hydratedFromDirectory: hydratedFromDirectory
            )
        } catch {
            var failed = record
            failed.phase = .failed
            failed.updatedAt = Date()
            failed.lastError = String(describing: error)
            try? await store.saveOutgoingContactRequest(failed)
            #if DEBUG
            Swift.print("[ContactRequestSendV2][failed] requestID=\(failed.id.uuidString) error=\(failed.lastError ?? "nil")")
            #endif
            throw error
        }
    }

    /// Notifies the original requester that their friend/contact request was accepted (contact-signal lane).
    public func sendFriendRequestAccepted(
        sourceNodeID: String,
        requesterCounterparty: ExchangeCounterparty,
        accepterDisplayName: String?,
        inReplyToEnvelopeID: String?,
        now: Date
    ) async throws {
        let trimmedSource = sourceNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let requesterNodeID = requesterCounterparty.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, !requesterNodeID.isEmpty else {
            throw ExchangeStoreError.storageFailure(reason: "Contact request acceptance is missing node ids.")
        }

        let executionProfile = Self.resolveExecutionPublicProfile(counterparty: requesterCounterparty)

        var draftMeta: [String: String] = [
            "payload_kind": ExchangeRelayEnvelope.Payload.Kind.friendRequestAccepted.rawValue,
            "conversation_kind": "friend_request_accepted",
            "contact_request": "true",
            "contact_request_outcome": "accepted",
            "accepted": "true",
            "target_node_id": requesterNodeID,
            "sender_node_id": trimmedSource
        ]
        if let display = accepterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            draftMeta["sender_display_name"] = display
        }
        if let reply = inReplyToEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            draftMeta["in_reply_to_envelope_id"] = reply
        }

        let correlationID = UUID()
        let built = try await envelopeService.buildContactFriendRequestAcceptedEnvelope(
            correlationID: correlationID,
            counterparty: requesterCounterparty,
            publicProfile: executionProfile,
            accepterNodeID: trimmedSource,
            inReplyToEnvelopeID: inReplyToEnvelopeID,
            disclosureLevel: .balanced,
            draftMetadata: draftMeta,
            routeHint: nil,
            now: now
        )

        let envelope = built.envelope
        let stableID = envelope.stableEnvelopeID

        #if DEBUG
        Swift.print(
            "[ContactRequestAcceptSend] requesterNodeID=\(requesterNodeID) envelopeID=\(stableID) " +
                "inReplyTo=\(inReplyToEnvelopeID ?? "nil")"
        )
        #endif

        _ = try await relayClient.send(envelope, route: built.route)

        #if DEBUG
        Swift.print("[ContactRequestAcceptSend] sent requesterNodeID=\(requesterNodeID) envelopeID=\(stableID)")
        #endif
    }

    private static func resolveExecutionPublicProfile(
        counterparty: ExchangeCounterparty
    ) -> ExchangePublicNodeProfile {
        if let existing = counterparty.publicProfile {
            return existing
        }
        let nodeID = (counterparty.identity?.nodeID ?? counterparty.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ExchangePublicNodeProfile(
            id: "contact-signal-basis-\(counterparty.id)",
            nodeID: nodeID,
            counterpartyID: counterparty.id,
            displayName: counterparty.displayName,
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                intentCategoryPolicy: .permissive,
                disclosureCeiling: .balanced
            ),
            metadata: ["synthetic_contact_signal_execution_basis": "true"]
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
