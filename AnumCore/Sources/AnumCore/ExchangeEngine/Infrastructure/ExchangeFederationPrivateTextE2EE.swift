import Foundation

public enum ExchangePrivateE2EESendBlockedError: Error, Sendable, Hashable {
    public static let errorCode = "e2ee_send_blocked"
    public static let userFacingMessage = "Couldn't send securely. Try again in a moment."

    case blocked(reason: String)

    public var blockedReason: String {
        switch self {
        case .blocked(let reason):
            return reason
        }
    }
}

enum ExchangeRecipientEncryptionKeyResolution: Sendable {
    case available(encryptionKeyID: String, encryptionPublicKey: String)
    case noRecipientKey
    case keyFetchFailed
}

enum ExchangeFederationPrivateTextE2EE {
    static let decryptFailurePlaceholder = "Encrypted message could not be opened."

    static func resolveRecipientEncryptionKey(
        federationBaseURL: URL,
        recipientNodeID: String
    ) async -> ExchangeRecipientEncryptionKeyResolution {
        let trimmed = recipientNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .noRecipientKey
        }

        let keysClient = ExchangeHTTPDirectoryClient(baseURL: federationBaseURL)
        let keys: ExchangeNodePublicKeys
        do {
            keys = try await keysClient.fetchNodePublicKeys(nodeID: trimmed)
        } catch {
            return .keyFetchFailed
        }

        guard let encryptionKeyID = keys.encryptionKeyID?.exchangeNilIfBlank,
              let encryptionPublicKey = keys.encryptionPublicKey?.exchangeNilIfBlank else {
            return .noRecipientKey
        }
        return .available(
            encryptionKeyID: encryptionKeyID,
            encryptionPublicKey: encryptionPublicKey
        )
    }

    // MARK: - Outbound eligibility

    static func isEligiblePrivateTextOutbound(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft,
        counterparty: ExchangeCounterparty,
        resolvedRoute: ExchangeRelayRoute,
        recipientNodeID: String?
    ) -> Bool {
        guard draft.audience == .externalCounterparty else { return false }
        guard resolvedRoute.kind != .localLoopback else { return false }
        guard let recipientNodeID, !recipientNodeID.isEmpty else { return false }

        let trimmedBody = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInnerAttachments = !DirectMessageAttachmentMetadata.innerPlaintextAttachments(from: draft.metadata).isEmpty
        guard !trimmedBody.isEmpty || hasInnerAttachments else { return false }

        if isLocalOnlyDraft(draft) {
            return false
        }

        let lane = ExchangeThreadLaneResolver.lane(for: thread)
        switch lane {
        case .directMessage, .commercialInquiry, .contactSignal, .socialConnection, .unknown:
            return true
        }
    }

    static func conversationSurfaceLabel(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft
    ) -> String {
        if let explicit = draft.metadata[ExchangeThreadLaneResolver.conversationSurfaceMetadataKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !explicit.isEmpty {
            return explicit
        }
        let lane = ExchangeThreadLaneResolver.lane(for: thread)
        return ExchangeThreadLaneResolver.conversationSurface(for: lane)
    }

    // MARK: - Inbound eligibility

    static func isPrivateRelayEnvelope(_ envelope: ExchangeRelayEnvelope) -> Bool {
        guard envelope.payload.encryption != nil else {
            return isPrivateRelayEnvelopeMetadata(envelope.metadata, payloadKind: envelope.payload.kind)
        }
        return isPrivateRelayEnvelopeMetadata(envelope.metadata, payloadKind: envelope.payload.kind)
    }

    static func inboundConversationSurface(_ envelope: ExchangeRelayEnvelope) -> String {
        if let surface = envelope.metadata[ExchangeThreadLaneResolver.conversationSurfaceMetadataKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !surface.isEmpty {
            return surface
        }
        if envelope.metadata["direct_message_thread"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
            return ExchangeThreadLaneResolver.conversationSurfaceDirectMessage
        }
        if ExchangeContactSignalClassifier.matchesContactSignalMetadata(envelope.metadata) {
            return ExchangeThreadLaneResolver.conversationSurfaceContact
        }
        return ExchangeThreadLaneResolver.conversationSurfaceExchangeThread
    }

    // MARK: - Logging

    static func logSendBlocked(reason: String) {
        Swift.print(
            "[E2EE][private][send] encrypted=false blocked=true reason=\(reason)"
        )
    }

    static func logSend(
        encrypted: Bool,
        surface: String? = nil,
        blocked: Bool = false,
        fallback: Bool = false,
        reason: String? = nil
    ) {
        let surfaceSuffix = surface.map { " surface=\($0)" } ?? ""
        let reasonSuffix = reason.map { " reason=\($0)" } ?? ""
        var flags = "encrypted=\(encrypted)"
        if blocked {
            flags += " blocked=true"
        }
        if fallback {
            flags += " fallback=true"
        }
        Swift.print(
            "[E2EE][private][send] \(flags)\(surfaceSuffix)\(reasonSuffix)"
        )
    }

    static func logReceive(
        encryptionPresent: Bool,
        decrypted: Bool,
        surface: String?,
        reason: String?
    ) {
        let surfaceSuffix = surface.map { " surface=\($0)" } ?? ""
        let reasonSuffix = reason.map { " reason=\($0)" } ?? ""
        Swift.print(
            "[E2EE][private][receive] encryptionPresent=\(encryptionPresent) decrypted=\(decrypted)\(surfaceSuffix)\(reasonSuffix)"
        )
    }

    // MARK: - Private

    private static func isPrivateRelayEnvelopeMetadata(
        _ metadata: [String: String],
        payloadKind: ExchangeRelayEnvelope.Payload.Kind
    ) -> Bool {
        switch payloadKind {
        case .friendRequest, .friendRequestAccepted, .introduction, .quoteRequest,
             .followUp, .negotiation, .scheduling, .closure, .inquiry, .other:
            break
        }

        let surface = metadata[ExchangeThreadLaneResolver.conversationSurfaceMetadataKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let surface, !surface.isEmpty {
            switch surface {
            case ExchangeThreadLaneResolver.conversationSurfaceDirectMessage,
                 ExchangeThreadLaneResolver.conversationSurfaceExchangeThread,
                 ExchangeThreadLaneResolver.conversationSurfaceContact,
                 ExchangeThreadLaneResolver.conversationSurfaceSocialConnection:
                return true
            default:
                return false
            }
        }

        if metadata["direct_message_thread"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
            return true
        }
        if metadata["contact_request_thread"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
            return true
        }
        if metadata["contact_signal_lane"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
            return true
        }

        let payloadKindRaw = metadata["payload_kind"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if payloadKindRaw.hasPrefix("direct_message/") { return true }

        switch payloadKind {
        case .friendRequest, .friendRequestAccepted, .introduction, .quoteRequest,
             .followUp, .negotiation, .scheduling, .closure, .inquiry:
            return true
        case .other:
            return false
        }
    }

    private static func isLocalOnlyDraft(_ draft: ExchangeMessageDraft) -> Bool {
        if draft.metadata["agency_only"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
            return true
        }
        if draft.metadata["local_only"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
            return true
        }
        return false
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
