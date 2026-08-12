import Foundation

/// Resolves optional outbound `ExchangeRelayPayloadEncryption` for private relay text envelopes.
struct ExchangePrivateTextE2EEResolver: Sendable {
    let federationBaseURL: URL
    let messageSealer: ExchangeMessageSealer

    init(
        federationBaseURL: URL,
        messageSealer: ExchangeMessageSealer = ExchangeMessageSealer()
    ) {
        self.federationBaseURL = federationBaseURL
        self.messageSealer = messageSealer
    }

    /// Returns sealed payload encryption when required/available.
    /// Returns `nil` only for ineligible envelopes or confirmed no-recipient-key fallback.
    /// Throws `ExchangePrivateE2EESendBlockedError` when plaintext fallback is not allowed.
    func resolvePayloadEncryption(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        draft: ExchangeMessageDraft,
        disclosedBody: String,
        disclosedSubject: String?,
        resolvedRoute: ExchangeRelayRoute,
        recipientNodeID: String,
        envelopeID: String,
        sentAt: Date,
        localIdentity: ExchangeLocalIdentity
    ) async throws -> ExchangeRelayPayloadEncryption? {
        let surface = ExchangeFederationPrivateTextE2EE.conversationSurfaceLabel(
            thread: thread,
            draft: draft
        )
        let eligible = ExchangeFederationPrivateTextE2EE.isEligiblePrivateTextOutbound(
            thread: thread,
            draft: draft,
            counterparty: counterparty,
            resolvedRoute: resolvedRoute,
            recipientNodeID: recipientNodeID
        )

        guard eligible else {
            ExchangeFederationPrivateTextE2EE.logSend(
                encrypted: false,
                surface: surface,
                reason: "notEligible"
            )
            return nil
        }

        guard let localEncryptionKeyID = localIdentity.encryptionKeyID?.exchangeNilIfBlank,
              localIdentity.encryptionPublicKey?.exchangeNilIfBlank != nil else {
            ExchangeFederationPrivateTextE2EE.logSend(
                encrypted: false,
                surface: surface,
                blocked: true,
                reason: "missingLocalEncryptionKey"
            )
            throw ExchangePrivateE2EESendBlockedError.blocked(reason: "missingLocalEncryptionKey")
        }

        switch await ExchangeFederationPrivateTextE2EE.resolveRecipientEncryptionKey(
            federationBaseURL: federationBaseURL,
            recipientNodeID: recipientNodeID
        ) {
        case .keyFetchFailed:
            ExchangeFederationPrivateTextE2EE.logSend(
                encrypted: false,
                surface: surface,
                blocked: true,
                reason: "keyFetchFailed"
            )
            throw ExchangePrivateE2EESendBlockedError.blocked(reason: "keyFetchFailed")
        case .noRecipientKey:
            ExchangeFederationPrivateTextE2EE.logSend(
                encrypted: false,
                surface: surface,
                fallback: true,
                reason: "noRecipientKey"
            )
            return nil
        case .available(let recipientEncryptionKeyID, let recipientEncryptionPublicKey):
            guard let senderSigningKeyID = localIdentity.publicKeyID?.exchangeNilIfBlank else {
                ExchangeFederationPrivateTextE2EE.logSend(
                    encrypted: false,
                    surface: surface,
                    blocked: true,
                    reason: "missingLocalSigningKey"
                )
                throw ExchangePrivateE2EESendBlockedError.blocked(reason: "missingLocalSigningKey")
            }

            do {
                let innerAttachments = DirectMessageAttachmentMetadata.innerPlaintextAttachments(from: draft.metadata)
                let sealed = try messageSealer.sealDMText(
                    body: disclosedBody,
                    subject: disclosedSubject,
                    envelopeID: envelopeID,
                    sentAt: sentAt,
                    senderEncryptionKeyID: localEncryptionKeyID,
                    senderSigningKeyID: senderSigningKeyID,
                    recipientEncryptionKeyID: recipientEncryptionKeyID,
                    recipientEncryptionPublicKeyBase64: recipientEncryptionPublicKey,
                    attachments: innerAttachments
                )
                ExchangeFederationPrivateTextE2EE.logSend(
                    encrypted: true,
                    surface: surface,
                    reason: nil
                )
                return sealed
            } catch {
                ExchangeFederationPrivateTextE2EE.logSend(
                    encrypted: false,
                    surface: surface,
                    blocked: true,
                    reason: "sealFailed"
                )
                throw ExchangePrivateE2EESendBlockedError.blocked(reason: "sealFailed")
            }
        }
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
