import Foundation

#if DEBUG
/// DEBUG-only single-line body preview for envelope payload audit (matches ExchangeFacade audit style).
private func exchangeEnvelopeDebugAuditBodyPrefix(_ text: String, maxLen: Int = 220) -> String {
    var t = text
    t = t.replacingOccurrences(of: "\n", with: " ")
    t = t.replacingOccurrences(of: "\r", with: " ")
    t = t.replacingOccurrences(of: "\t", with: " ")
    t = t.trimmingCharacters(in: .whitespacesAndNewlines)
    while t.contains("  ") {
        t = t.replacingOccurrences(of: "  ", with: " ")
    }
    if t.count > maxLen {
        return String(t.prefix(maxLen))
    }
    return t
}
#endif

/// Builds relay-safe outbound envelopes from Exchange domain objects.
///
/// This service is intentionally narrow:
/// - it does not mutate threads
/// - it does not send envelopes
/// - it does not decide high-level policy
///
/// It converts approved local state into a transport-safe envelope through
/// the recipient's selected public execution surface rather than route
/// reachability alone.
public struct ExchangeEnvelopeService: Sendable {
    private let identityService: any ExchangeIdentityService
    private let privateTextE2EEResolver: ExchangePrivateTextE2EEResolver?

    public init(
        identityService: any ExchangeIdentityService,
        federationBaseURL: URL? = nil,
        messageSealer: ExchangeMessageSealer = ExchangeMessageSealer()
    ) {
        self.identityService = identityService
        if let federationBaseURL {
            self.privateTextE2EEResolver = ExchangePrivateTextE2EEResolver(
                federationBaseURL: federationBaseURL,
                messageSealer: messageSealer
            )
        } else {
            self.privateTextE2EEResolver = nil
        }
    }

    public func buildEnvelope(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        draft: ExchangeMessageDraft,
        disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        sequenceNumber: Int? = nil,
        parentEnvelopeID: String? = nil,
        idempotencyKey: String? = nil,
        routeHint: ExchangeRelayRoute? = nil,
        payloadEncryption: ExchangeRelayPayloadEncryption? = nil,
        now: Date = Date()
    ) async throws -> BuiltEnvelope {
        try validateExecutionBasis(
            thread: thread,
            counterparty: counterparty,
            publicProfile: publicProfile
        )

        let localIdentity = try await identityService.localIdentity()

        let effectiveDisclosureLevel = disclosureLevel.clamped(
            to: relayDisclosureLevel(from: publicProfile.reachability.disclosureCeiling)
        )

        let resolvedTargetNodeID = targetNodeID(for: counterparty)

        let resolvedRoute = try resolveRelayRoute(
            thread: thread,
            counterparty: counterparty,
            publicProfile: publicProfile,
            routeHint: routeHint,
            localIdentity: localIdentity,
            targetNodeID: resolvedTargetNodeID
        )

        let recipientRoute = relayRecipientRoute(from: resolvedRoute)

        let sender = ExchangeRelayEnvelope.Party(
            nodeID: localIdentity.nodeID,
            displayName: localIdentity.displayName,
            publicKeyID: localIdentity.publicKeyID
        )

        let disclosedBodyText = disclosedBody(
            draft.body,
            threadID: thread.id,
            draftID: draft.id,
            draftMetadata: draft.metadata,
            level: effectiveDisclosureLevel
        )
        let disclosedSubjectText = disclosedSubject(draft.subject, level: effectiveDisclosureLevel)

        let stableEnvelopeID = idempotencyKey?.exchangeNilIfBlank ?? defaultIdempotencyKey(
            threadID: thread.id,
            draftID: draft.id,
            targetExecutionID: resolvedTargetNodeID
        )

        let effectivePayloadEncryption: ExchangeRelayPayloadEncryption?
        if let payloadEncryption {
            effectivePayloadEncryption = payloadEncryption
        } else if let privateTextE2EEResolver {
            effectivePayloadEncryption = try await privateTextE2EEResolver.resolvePayloadEncryption(
                thread: thread,
                counterparty: counterparty,
                draft: draft,
                disclosedBody: disclosedBodyText,
                disclosedSubject: disclosedSubjectText,
                resolvedRoute: resolvedRoute,
                recipientNodeID: resolvedTargetNodeID,
                envelopeID: stableEnvelopeID,
                sentAt: now,
                localIdentity: localIdentity
            )
        } else {
            effectivePayloadEncryption = nil
        }

        let payload = ExchangeRelayEnvelope.Payload(
            kind: payloadKind(for: draft),
            subject: effectivePayloadEncryption == nil
                ? disclosedSubjectText
                : nil,
            body: effectivePayloadEncryption == nil ? disclosedBodyText : "",
            disclosureLevel: effectiveDisclosureLevel,
            threadContext: effectivePayloadEncryption == nil
                ? disclosedThreadContext(thread: thread, level: effectiveDisclosureLevel)
                : disclosedThreadContext(thread: thread, level: .minimal),
            encryption: effectivePayloadEncryption
        )

        #if DEBUG
        if effectivePayloadEncryption == nil {
            Swift.print(
                "[EnvelopeBody] thread=\(thread.id.uuidString) draft=\(draft.id.uuidString) disclosure=\(effectiveDisclosureLevel.rawValue) bodyLen=\(disclosedBodyText.count) bodyPrefix=\(exchangeEnvelopeDebugAuditBodyPrefix(disclosedBodyText))"
            )
        } else {
            Swift.print(
                "[EnvelopeBody] thread=\(thread.id.uuidString) draft=\(draft.id.uuidString) disclosure=\(effectiveDisclosureLevel.rawValue) encrypted=1 wireBodyLen=0"
            )
        }
        #endif

        let ordering = ExchangeRelayEnvelope.Ordering(
            sequenceNumber: sequenceNumber,
            parentEnvelopeID: parentEnvelopeID?.exchangeNilIfBlank,
            idempotencyKey: idempotencyKey?.exchangeNilIfBlank ?? defaultIdempotencyKey(
                threadID: thread.id,
                draftID: draft.id,
                targetExecutionID: resolvedTargetNodeID
            )
        )

        let unsigned = ExchangeRelayEnvelope(
            createdAt: now,
            protocolVersion: bestProtocolVersion(from: localIdentity),
            threadID: thread.id,
            sender: sender,
            recipient: .init(
                route: recipientRoute,
                displayName: disclosedRecipientDisplayName(
                    counterparty.displayName,
                    level: effectiveDisclosureLevel
                )
            ),
            payload: payload,
            signature: nil,
            ordering: ordering,
            metadata: buildMetadata(
                thread: thread,
                counterparty: counterparty,
                publicProfile: publicProfile,
                draft: draft,
                requestedDisclosureLevel: disclosureLevel,
                effectiveDisclosureLevel: effectiveDisclosureLevel,
                resolvedRoute: resolvedRoute,
                resolvedTargetNodeID: resolvedTargetNodeID,
                isEncrypted: effectivePayloadEncryption != nil
            )
        )

        let signature = try await identityService.signEnvelope(unsigned)

        let signed = ExchangeRelayEnvelope(
            id: unsigned.id,
            createdAt: unsigned.createdAt,
            protocolVersion: unsigned.protocolVersion,
            threadID: unsigned.threadID,
            sender: unsigned.sender,
            recipient: unsigned.recipient,
            payload: unsigned.payload,
            signature: signature,
            ordering: unsigned.ordering,
            metadata: unsigned.metadata
        )

        #if DEBUG
        Swift.print(
            "[DMRoute][outbound] envelopeID=\(signed.stableEnvelopeID) threadID=\(signed.threadID.uuidString) " +
                "conversation_surface=\(signed.metadata["conversation_surface"] ?? "nil") " +
                "conversation_kind=\(signed.metadata["conversation_kind"] ?? "nil") " +
                "draft_kind=\(signed.metadata["draft_kind"] ?? "nil") payload_kind=\(signed.payload.kind.rawValue)"
        )
        #endif

        return BuiltEnvelope(
            envelope: signed,
            route: resolvedRoute
        )
    }

    /// Builds a signed friend-request envelope for the **contact-signal lane** (no persisted `ExchangeThread`).
    /// `correlationID` becomes `ExchangeRelayEnvelope.threadID` for relay correlation only.
    public func buildContactFriendRequestEnvelope(
        correlationID: UUID,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        subject: String,
        body: String,
        disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        draftMetadata: [String: String],
        routeHint: ExchangeRelayRoute? = nil,
        now: Date = Date()
    ) async throws -> BuiltEnvelope {
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Contact request",
            objective: "Request to connect with a contact",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
        var threadMetadata: [String: String] = ["contact_request_thread": "true"]
        threadMetadata["contact_signal_lane"] = "true"
        ExchangeThreadLaneResolver.applyLane(.contactSignal, to: &threadMetadata)

        let thread = ExchangeThread(
            id: correlationID,
            createdAt: now,
            updatedAt: now,
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(privacy: .balanced),
            state: .drafting,
            selectedCounterpartyID: counterparty.id,
            selectedPublicProfileID: publicProfile.id,
            metadata: threadMetadata
        )

        var mergedDraftMeta = draftMetadata
        mergedDraftMeta["contact_request"] = "true"
        mergedDraftMeta["payload_kind"] = ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue
        mergedDraftMeta["conversation_kind"] = mergedDraftMeta["conversation_kind"] ?? "friend_request"
        mergedDraftMeta["introduction_request"] = mergedDraftMeta["introduction_request"] ?? "true"

        let draft = ExchangeMessageDraft(
            threadID: correlationID,
            kind: .introduction,
            audience: .externalCounterparty,
            subject: subject,
            body: body,
            posture: thread.posture,
            targetCounterpartyID: counterparty.id,
            metadata: mergedDraftMeta
        )

        let idempotencyKey = "\(correlationID.uuidString)|contact_friend_request|\(counterparty.id)"

        return try await buildEnvelope(
            thread: thread,
            counterparty: counterparty,
            publicProfile: publicProfile,
            draft: draft,
            disclosureLevel: disclosureLevel,
            idempotencyKey: idempotencyKey,
            routeHint: routeHint,
            now: now
        )
    }

    /// Builds a signed contact-request **acceptance** envelope (contact-signal lane).
    public func buildContactFriendRequestAcceptedEnvelope(
        correlationID: UUID,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        accepterNodeID: String,
        inReplyToEnvelopeID: String?,
        disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        draftMetadata: [String: String],
        routeHint: ExchangeRelayRoute? = nil,
        now: Date
    ) async throws -> BuiltEnvelope {
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Contact request accepted",
            objective: "Notify requester that a contact request was accepted",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
        var threadMetadata: [String: String] = ["contact_request_thread": "true"]
        threadMetadata["contact_signal_lane"] = "true"
        ExchangeThreadLaneResolver.applyLane(.contactSignal, to: &threadMetadata)

        let thread = ExchangeThread(
            id: correlationID,
            createdAt: now,
            updatedAt: now,
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(privacy: .balanced),
            state: .drafting,
            selectedCounterpartyID: counterparty.id,
            selectedPublicProfileID: publicProfile.id,
            metadata: threadMetadata
        )

        var mergedDraftMeta = draftMetadata
        mergedDraftMeta["contact_request"] = "true"
        mergedDraftMeta["contact_request_outcome"] = "accepted"
        mergedDraftMeta["accepted"] = "true"
        mergedDraftMeta["payload_kind"] = ExchangeRelayEnvelope.Payload.Kind.friendRequestAccepted.rawValue
        mergedDraftMeta["conversation_kind"] = "friend_request_accepted"
        mergedDraftMeta["sender_node_id"] = accepterNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        mergedDraftMeta["target_node_id"] = counterparty.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reply = inReplyToEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines).exchangeNilIfBlank {
            mergedDraftMeta["in_reply_to_envelope_id"] = reply
        }

        let draft = ExchangeMessageDraft(
            threadID: correlationID,
            kind: .introduction,
            audience: .externalCounterparty,
            subject: "Contact request accepted",
            body: "Your contact request was accepted.",
            posture: thread.posture,
            targetCounterpartyID: counterparty.id,
            metadata: mergedDraftMeta
        )

        let idempotencyKey = "\(correlationID.uuidString)|contact_friend_request_accepted|\(counterparty.id)"

        return try await buildEnvelope(
            thread: thread,
            counterparty: counterparty,
            publicProfile: publicProfile,
            draft: draft,
            disclosureLevel: disclosureLevel,
            idempotencyKey: idempotencyKey,
            routeHint: routeHint,
            now: now
        )
    }

    /// Signed outbound envelope for **manual trusted DM** (relay-direct lane; no exchange outbox).
    /// Caller supplies an in-memory `draft` (typically not persisted until after relay send succeeds).
    public func buildDirectMessageManualEnvelope(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        draft: ExchangeMessageDraft,
        disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        routeHint: ExchangeRelayRoute? = nil,
        payloadEncryption: ExchangeRelayPayloadEncryption? = nil,
        now: Date = Date()
    ) async throws -> BuiltEnvelope {
        let dm = thread.metadata["direct_message_thread"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "true"
        guard dm else {
            throw ExchangeEnvelopeServiceError.executionBasisMismatch(
                reason: "Direct message manual send requires thread.metadata[direct_message_thread]=true."
            )
        }

        let idempotencyKey = "\(thread.id.uuidString)|dm_manual_v2|\(draft.id.uuidString)|\(counterparty.id)"

        return try await buildEnvelope(
            thread: thread,
            counterparty: counterparty,
            publicProfile: publicProfile,
            draft: draft,
            disclosureLevel: disclosureLevel,
            idempotencyKey: idempotencyKey,
            routeHint: routeHint,
            payloadEncryption: payloadEncryption,
            now: now
        )
    }
}

public extension ExchangeEnvelopeService {
    struct BuiltEnvelope: Sendable, Hashable {
        public var envelope: ExchangeRelayEnvelope
        public var route: ExchangeRelayRoute

        public init(
            envelope: ExchangeRelayEnvelope,
            route: ExchangeRelayRoute
        ) {
            self.envelope = envelope
            self.route = route
        }
    }
}

private extension ExchangeEnvelopeService {
    // MARK: - Execution basis validation

    func validateExecutionBasis(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile
    ) throws {
        if let selectedCounterpartyID = thread.selectedCounterpartyID?.exchangeNilIfBlank,
           selectedCounterpartyID != counterparty.id {
            throw ExchangeEnvelopeServiceError.executionBasisMismatch(
                reason: "Thread selected counterparty \(selectedCounterpartyID), but envelope build was requested for \(counterparty.id)."
            )
        }

        if let selectedPublicProfileID = thread.selectedPublicProfileID?.exchangeNilIfBlank,
           selectedPublicProfileID != publicProfile.id {
            throw ExchangeEnvelopeServiceError.executionBasisMismatch(
                reason: "Thread selected public profile \(selectedPublicProfileID), but envelope build was requested for \(publicProfile.id)."
            )
        }

        if let linkedCounterpartyID = publicProfile.counterpartyID?.exchangeNilIfBlank,
           linkedCounterpartyID != counterparty.id {
            throw ExchangeEnvelopeServiceError.executionBasisMismatch(
                reason: "Public profile \(publicProfile.id) belongs to counterparty \(linkedCounterpartyID), not \(counterparty.id)."
            )
        }
    }

    func targetNodeID(
        for counterparty: ExchangeCounterparty
    ) -> String {
        counterparty.identity?.nodeID?.exchangeNilIfBlank ?? counterparty.id
    }

    func threadHasQualifiedIntroduction(
        _ thread: ExchangeThread
    ) -> Bool {
        if let selectedPath = thread.selectedPath,
           selectedPath.status == .selected,
           (selectedPath.accessMode == .introOnly || selectedPath.introductionRequired) {
            return true
        }

        if let mode = thread.metadata["contact_mode"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           mode == "introduced" || mode == "trusted_path" {
            return true
        }

        if let trustedPathID = thread.metadata["trusted_path_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trustedPathID.isEmpty {
            return true
        }

        if thread.metadata["contact_request_thread"] == "true" {
            return true
        }

        return false
    }

    // MARK: - Route resolution

    func resolveRelayRoute(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        routeHint: ExchangeRelayRoute?,
        localIdentity: ExchangeLocalIdentity,
        targetNodeID: String
    ) throws -> ExchangeRelayRoute {
        guard publicProfile.reachability.acceptingInbound else {
            throw ExchangeEnvelopeServiceError.contactNotAcceptingInbound(counterpartyID: counterparty.id)
        }

        switch publicProfile.reachability.accessMode {
        case .closed:
            throw ExchangeEnvelopeServiceError.contactClosed(counterpartyID: counterparty.id)

        case .introRequired:
            guard threadHasQualifiedIntroduction(thread) else {
                throw ExchangeEnvelopeServiceError.introductionRequired(counterpartyID: counterparty.id)
            }

        case .direct, .introPreferred:
            break
        }

        if let routeHint,
           !routeHint.isExpired {
            guard routeAllowedByPosture(
                routeHint.kind,
                publicProfile: publicProfile,
                thread: thread
            ) else {
                throw ExchangeEnvelopeServiceError.routeNotAllowedByPosture(
                    counterpartyID: counterparty.id,
                    routeKind: routeHint.kind.rawValue
                )
            }
            return routeHint
        }

        if let preferred = counterparty.preferredRoute,
           let route = route(from: preferred, localIdentity: localIdentity),
           routeAllowedByPosture(route.kind, publicProfile: publicProfile, thread: thread) {
            return route
        }

        let nodeRoute = ExchangeRelayRoute(
            routeKey: "node:\(targetNodeID)",
            kind: .node,
            destination: targetNodeID,
            protocolVersion: bestProtocolVersion(from: localIdentity),
            priority: .preferred
        )

        if routeAllowedByPosture(nodeRoute.kind, publicProfile: publicProfile, thread: thread) {
            return nodeRoute
        }

        if publicProfile.reachability.routeableOnly {
            throw ExchangeEnvelopeServiceError.missingRecipientRoute(
                counterpartyID: counterparty.id
            )
        }

        throw ExchangeEnvelopeServiceError.routeNotAllowedByPosture(
            counterpartyID: counterparty.id,
            routeKind: nodeRoute.kind.rawValue
        )
    }

    func route(
        from preferred: ExchangeCounterparty.ContactRoute,
        localIdentity: ExchangeLocalIdentity
    ) -> ExchangeRelayRoute? {
        switch preferred.kind {
        case .exchangeNode:
            return ExchangeRelayRoute(
                routeKey: "node:\(preferred.value)",
                kind: .node,
                destination: preferred.value,
                protocolVersion: bestProtocolVersion(from: localIdentity),
                priority: .preferred
            )

        case .relayAddress:
            return ExchangeRelayRoute(
                routeKey: "relay-address:\(preferred.value)",
                kind: .relayAddress,
                destination: preferred.value,
                protocolVersion: bestProtocolVersion(from: localIdentity),
                priority: .preferred
            )

        case .email:
            return ExchangeRelayRoute(
                routeKey: "email:\(preferred.value)",
                kind: .emailBridge,
                destination: preferred.value,
                protocolVersion: bestProtocolVersion(from: localIdentity),
                priority: .normal
            )

        case .phone, .username, .other:
            return ExchangeRelayRoute(
                routeKey: "relay-address:\(preferred.value)",
                kind: .relayAddress,
                destination: preferred.value,
                protocolVersion: bestProtocolVersion(from: localIdentity),
                priority: .fallback
            )
        }
    }

    func routeAllowedByPosture(
        _ routeKind: ExchangeRelayRoute.Kind,
        publicProfile: ExchangePublicNodeProfile,
        thread: ExchangeThread
    ) -> Bool {
        guard publicProfile.reachability.acceptingInbound else {
            return false
        }

        switch publicProfile.reachability.accessMode {
        case .closed:
            return false

        case .introRequired:
            guard threadHasQualifiedIntroduction(thread) else {
                return false
            }

        case .direct, .introPreferred:
            break
        }

        switch routeKind {
        case .node, .relayAddress, .relayMailbox, .emailBridge:
            return true
        case .localLoopback:
            return false
        }
    }

    // MARK: - Disclosure mapping

    func relayDisclosureLevel(
        from ceiling: ExchangePublicNodeProfile.ReachabilityPolicy.DisclosureCeiling
    ) -> ExchangeRelayEnvelope.Payload.DisclosureLevel {
        switch ceiling {
        case .minimal:
            return .minimal
        case .balanced:
            return .balanced
        case .open:
            return .open
        }
    }

    func relayRecipientRoute(
        from route: ExchangeRelayRoute
    ) -> ExchangeRelayEnvelope.Recipient.Route {
        switch route.kind {
        case .node:
            return .node(id: route.destination)
        case .relayMailbox, .relayAddress:
            return .relayAddress(route.destination)
        case .emailBridge:
            return .email(route.destination)
        case .localLoopback:
            return .other(route.destination)
        }
    }

    func payloadKind(
        for draft: ExchangeMessageDraft
    ) -> ExchangeRelayEnvelope.Payload.Kind {
        if draft.metadata["contact_request_outcome"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "accepted" {
            return .friendRequestAccepted
        }
        if draft.metadata["payload_kind"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == ExchangeRelayEnvelope.Payload.Kind.friendRequestAccepted.rawValue {
            return .friendRequestAccepted
        }
        if draft.metadata["contact_request"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
            return .friendRequest
        }
        switch draft.kind {
        case .introduction:
            return .introduction
        case .quoteRequest:
            return .quoteRequest
        case .followUp:
            return .followUp
        case .negotiation:
            return .negotiation
        case .scheduling:
            return .scheduling
        case .closure:
            return .closure
        case .inquiry, .other:
            return .inquiry
        }
    }

    func disclosedSubject(
        _ subject: String?,
        level: ExchangeRelayEnvelope.Payload.DisclosureLevel
    ) -> String? {
        switch level {
        case .minimal, .balanced, .open:
            return subject?.exchangeNilIfBlank
        }
    }

    func disclosedBody(
        _ body: String,
        threadID: ExchangeThread.ID,
        draftID: ExchangeMessageDraft.ID,
        draftMetadata: [String: String],
        level: ExchangeRelayEnvelope.Payload.DisclosureLevel
    ) -> String {
        let source = draftMetadata["agency_body_source"] ?? "unknown"
        let materializeSkipped = draftMetadata["agency_materialize_skipped_llm"] == "true"
        let chosenBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitize: ExchangeUserFacingCopySanitizer.FederationBodySanitizeResult =
            if draftMetadata["agency_inquiry_safe_enabled"] == "true" {
                ExchangeUserFacingCopySanitizer.sanitizedFederationUserVisibleOutboundBody(
                    raw: chosenBody,
                    draftMetadata: draftMetadata
                )
            } else {
                ExchangeUserFacingCopySanitizer.cleanFederationUserVisibleBody(chosenBody)
            }

        #if DEBUG
        let fbFallback = sanitize.usedMinimalSafeFallback ? "true" : "false"
        let fbReason = sanitize.fallbackReason ?? "none"
        Swift.print(
            "[EnvelopeBodyFinal] thread=\(threadID.uuidString) draft=\(draftID.uuidString) source=\(source)|materializeSkippedLLM=\(materializeSkipped) originalLen=\(chosenBody.count) finalLen=\(sanitize.cleaned.count) removedInternalScaffold=\(sanitize.removedInternalScaffold) containsForbiddenScaffold=\(!sanitize.forbiddenTermsFound.isEmpty) fallback=\(fbFallback)|fallbackReason=\(fbReason) bodyPrefix=\(exchangeEnvelopeDebugAuditBodyPrefix(sanitize.cleaned))"
        )
        if sanitize.usedMinimalSafeFallback, sanitize.fallbackReason == "forbidden_scaffold_remaining" {
            Swift.print(
                "[EnvelopeBodyFinal] fallback=safeRequesterInquiry reason=forbiddenScaffoldRemaining thread=\(threadID.uuidString) draft=\(draftID.uuidString)"
            )
        }
        if !sanitize.forbiddenTermsFound.isEmpty {
            Swift.print(
                "[EnvelopeBodyLeak] thread=\(threadID.uuidString) draft=\(draftID.uuidString) terms=\(sanitize.forbiddenTermsFound.joined(separator: ",")) bodyPrefix=\(exchangeEnvelopeDebugAuditBodyPrefix(sanitize.cleaned))"
            )
        }
        #endif

        switch level {
        case .minimal, .balanced, .open:
            return sanitize.cleaned
        }
    }

    func disclosedThreadContext(
        thread: ExchangeThread,
        level: ExchangeRelayEnvelope.Payload.DisclosureLevel
    ) -> ExchangeRelayEnvelope.Payload.ThreadContext? {
        switch level {
        case .minimal:
            return .init(
                localThreadID: thread.id.uuidString,
                mode: thread.mode.rawValue,
                intentTitle: nil
            )

        case .balanced, .open:
            return .init(
                localThreadID: thread.id.uuidString,
                mode: thread.mode.rawValue,
                intentTitle: thread.intent.title.exchangeNilIfBlank
            )
        }
    }

    func disclosedRecipientDisplayName(
        _ displayName: String,
        level: ExchangeRelayEnvelope.Payload.DisclosureLevel
    ) -> String? {
        switch level {
        case .minimal, .balanced, .open:
            return displayName.exchangeNilIfBlank
        }
    }

    // MARK: - Metadata

    func buildMetadata(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        draft: ExchangeMessageDraft,
        requestedDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        effectiveDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        resolvedRoute: ExchangeRelayRoute,
        resolvedTargetNodeID: String,
        isEncrypted: Bool = false
    ) -> [String: String] {
        var metadata: [String: String] = [
            "thread_id": thread.id.uuidString,
            "thread_mode": thread.mode.rawValue,
            "intent_kind": thread.intent.kind.rawValue,
            "draft_id": draft.id.uuidString,
            "draft_kind": draft.kind.rawValue,
            "counterparty_id": counterparty.id,
            "target_node_id": resolvedTargetNodeID,
            "public_profile_id": publicProfile.id,
            "requested_disclosure_level": requestedDisclosureLevel.rawValue,
            "effective_disclosure_level": effectiveDisclosureLevel.rawValue,
            "route_kind": resolvedRoute.kind.rawValue,
            "route_destination": resolvedRoute.destination,
            "visibility": publicProfile.visibility.rawValue,
            "availability": publicProfile.availability.rawValue,
            "accepting_inbound": publicProfile.reachability.acceptingInbound ? "true" : "false",
            "access_mode": publicProfile.reachability.accessMode.rawValue,
            "routeable_only": publicProfile.reachability.routeableOnly ? "true" : "false",
            "disclosure_ceiling": publicProfile.reachability.disclosureCeiling.rawValue
        ]

        if let selectedCounterpartyID = thread.selectedCounterpartyID?.exchangeNilIfBlank {
            metadata["selected_counterparty_id"] = selectedCounterpartyID
        }

        if let selectedPublicProfileID = thread.selectedPublicProfileID?.exchangeNilIfBlank {
            metadata["selected_public_profile_id"] = selectedPublicProfileID
        }

        if let selectedOfferID = thread.selectedOfferID?.exchangeNilIfBlank {
            metadata["selected_offer_id"] = selectedOfferID
        }

        if let selectedMatchRationale = thread.selectedMatchRationale?.exchangeNilIfBlank,
           !isEncrypted {
            metadata["selected_match_rationale"] = selectedMatchRationale
        }

        if let conversationID = thread.metadata["conversation_id"]?.exchangeNilIfBlank {
            metadata["conversation_id"] = conversationID
        }
        if let rootEnvelopeID = thread.metadata["root_envelope_id"]?.exchangeNilIfBlank {
            metadata["root_envelope_id"] = rootEnvelopeID
        }
        if let originalRequesterEnvelopeID = thread.metadata["original_requester_envelope_id"]?.exchangeNilIfBlank {
            metadata["original_requester_envelope_id"] = originalRequesterEnvelopeID
        }

        if let selectedPath = thread.selectedPath {
            metadata["selected_path_access_mode"] = selectedPath.accessMode.rawValue
            metadata["selected_path_status"] = selectedPath.status.rawValue
            metadata["selected_path_intro_required"] = selectedPath.introductionRequired ? "true" : "false"

            if let matchedRouteKind = selectedPath.matchedRouteKind?.exchangeNilIfBlank {
                metadata["selected_path_route_kind"] = matchedRouteKind
            }
        }

        if threadHasQualifiedIntroduction(thread) {
            metadata["intro_qualified"] = "true"
        }

        switch effectiveDisclosureLevel {
        case .minimal:
            break
        case .balanced, .open:
            if !isEncrypted,
               let target = thread.intent.targetDescription?.exchangeNilIfBlank {
                metadata["target_description"] = target
            }
        }

        let draftMetadataKeys: [String] = if isEncrypted {
            [
                "payload_kind",
                "contact_request",
                "introduction_request",
                "target_node_id",
                "sender_node_id",
                "conversation_kind"
            ] + DirectMessageAttachmentMetadata.encryptedRelayMetadataKeys
        } else {
            [
                "payload_kind",
                "contact_request",
                "introduction_request",
                "target_node_id",
                "sender_display_name",
                "sender_node_id",
                "conversation_kind"
            ] + DirectMessageAttachmentMetadata.federationMetadataKeys
        }

        for key in draftMetadataKeys {
            guard let raw = draft.metadata[key]?.exchangeNilIfBlank else { continue }
            metadata[key] = raw
        }

        // Durable routing hint for inbound reconciliation (DM vs exchange desk vs contact vs social).
        let lane = ExchangeThreadLaneResolver.lane(for: thread)
        metadata[ExchangeThreadLaneResolver.metadataKey] = lane.rawValue
        metadata[ExchangeThreadLaneResolver.conversationSurfaceMetadataKey] =
            ExchangeThreadLaneResolver.conversationSurface(for: lane)

        switch lane {
        case .directMessage:
            metadata["conversation_kind"] = metadata["conversation_kind"] ?? "direct_message"
        case .contactSignal:
            metadata["conversation_kind"] = metadata["conversation_kind"] ?? "friend_request"
            metadata["payload_kind"] = metadata["payload_kind"] ?? ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue
        case .socialConnection:
            metadata["conversation_kind"] = metadata["conversation_kind"] ?? "social_connection"
        case .commercialInquiry, .unknown:
            metadata["conversation_kind"] = metadata["conversation_kind"] ?? "exchange_thread"
        }

        if isEncrypted {
            metadata["e2ee_private_text"] = "true"
        }

        return metadata
    }

    // MARK: - Helpers

    func bestProtocolVersion(
        from identity: ExchangeLocalIdentity
    ) -> String {
        if ExchangeProtocolVersion.isSupported(
            incoming: ExchangeProtocolVersion.current,
            supported: identity.supportedProtocolVersions
        ) {
            return ExchangeProtocolVersion.current
        }
        return identity.preferredProtocolVersion
    }

    func defaultIdempotencyKey(
        threadID: ExchangeThread.ID,
        draftID: ExchangeMessageDraft.ID,
        targetExecutionID: String
    ) -> String {
        "\(threadID.uuidString)|\(draftID.uuidString)|\(targetExecutionID)"
    }
}

public enum ExchangeEnvelopeServiceError: Error, Sendable, Hashable {
    case missingRecipientRoute(counterpartyID: ExchangeCounterparty.ID)
    case routeNotAllowedByPosture(counterpartyID: ExchangeCounterparty.ID, routeKind: String)
    case introductionRequired(counterpartyID: ExchangeCounterparty.ID)
    case contactClosed(counterpartyID: ExchangeCounterparty.ID)
    case contactNotAcceptingInbound(counterpartyID: ExchangeCounterparty.ID)
    case executionBasisMismatch(reason: String)
}

// MARK: - Test seams (AnumCoreTests)

extension ExchangeEnvelopeService {
    /// Test seam: mirrors private `payloadKind(for:)` used when building relay payloads.
    internal func contactRequestContract_payloadKind(for draft: ExchangeMessageDraft) -> ExchangeRelayEnvelope.Payload.Kind {
        payloadKind(for: draft)
    }

    /// Test seam: mirrors private `buildMetadata` used for outbound envelope metadata.
    internal func contactRequestContract_buildMetadata(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        draft: ExchangeMessageDraft,
        requestedDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        effectiveDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        resolvedRoute: ExchangeRelayRoute,
        resolvedTargetNodeID: String
    ) -> [String: String] {
        buildMetadata(
            thread: thread,
            counterparty: counterparty,
            publicProfile: publicProfile,
            draft: draft,
            requestedDisclosureLevel: requestedDisclosureLevel,
            effectiveDisclosureLevel: effectiveDisclosureLevel,
            resolvedRoute: resolvedRoute,
            resolvedTargetNodeID: resolvedTargetNodeID
        )
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ExchangeRelayEnvelope.Payload.DisclosureLevel {
    func clamped(
        to ceiling: ExchangeRelayEnvelope.Payload.DisclosureLevel
    ) -> Self {
        switch (self, ceiling) {
        case (_, .minimal):
            return .minimal
        case (.open, .balanced):
            return .balanced
        default:
            return self
        }
    }
}
