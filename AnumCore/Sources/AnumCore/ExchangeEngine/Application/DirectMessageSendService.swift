import Foundation

/// Relay-direct manual DM send (V2). Does not use exchange outbox, approvals, or `grantApproval`.
public struct DirectMessageSendService: Sendable {
    private let store: any ExchangeStore
    private let envelopeService: ExchangeEnvelopeService
    private let identityService: any ExchangeIdentityService
    private let relayClient: any ExchangeRelayClient
    private let dmAttachmentClient: ExchangeHTTPDMAttachmentClient?
    private let federationBaseURL: URL
    private let attachmentSealer: ExchangeAttachmentSealer

    public init(
        store: any ExchangeStore,
        envelopeService: ExchangeEnvelopeService,
        identityService: any ExchangeIdentityService,
        relayClient: any ExchangeRelayClient,
        dmAttachmentClient: ExchangeHTTPDMAttachmentClient? = nil,
        federationBaseURL: URL,
        attachmentSealer: ExchangeAttachmentSealer = ExchangeAttachmentSealer()
    ) {
        self.store = store
        self.envelopeService = envelopeService
        self.identityService = identityService
        self.relayClient = relayClient
        self.dmAttachmentClient = dmAttachmentClient
        self.federationBaseURL = federationBaseURL
        self.attachmentSealer = attachmentSealer
    }

    /// Persists a **sent** manual DM draft after successful relay delivery (local transcript source of truth).
    public func sendTrustedManualMessage(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        subject: String?,
        body: String,
        attachment: DirectMessageOutboundAttachmentInput? = nil,
        disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        now: Date
    ) async throws {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachment = attachment != nil
        guard !trimmedBody.isEmpty || hasAttachment else {
            throw ExchangeStoreError.storageFailure(reason: "Message body and attachment are both empty.")
        }

        let inbound = thread.metadata["inbound_thread"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        guard !inbound else {
            throw ExchangeStoreError.storageFailure(
                reason: "DirectMessageSendV2 is only for trusted manual DM threads, not inbound provider threads."
            )
        }

        #if DEBUG
        Swift.print("[DirectMessageSendV2][start] threadID=\(thread.id.uuidString) target=\(counterparty.id)")
        #endif

        let repair = DirectMessageThreadExecutionBasis.repairedThreadForTrustedManualSend(
            thread: thread,
            counterparty: counterparty,
            publicProfile: publicProfile,
            now: now
        )
        let basisThread = repair.thread
        if repair.mutated {
            try await store.updateThread(basisThread)
            #if DEBUG
            Swift.print(
                "[DMThreadMetadataSanitize] threadID=\(thread.id.uuidString) " +
                    "clearedSelectedProfile=\(repair.clearedSelectedPublicProfileID ?? "nil") " +
                    "clearedSelectedOffer=\(repair.clearedSelectedOfferID ?? "nil") " +
                    "reason=dm_basis_mismatch"
            )
            #endif
        }

        #if DEBUG
        Swift.print(
            "[DirectMessageSendV2][basis] threadID=\(basisThread.id.uuidString) target=\(counterparty.id) " +
                "selectedProfile=\(basisThread.selectedPublicProfileID ?? "nil") " +
                "selectedOffer=\(basisThread.selectedOfferID ?? "nil")"
        )
        #endif

        let local = try await identityService.localIdentity()
        let draftID = UUID()
        var draftMeta: [String: String] = [
            "trusted_node_manual_message": "true",
            "payload_kind": "direct_message/message",
            "dm_manual_v2": "true",
            "sender_node_id": local.nodeID,
            "counterparty_id": counterparty.id
        ]
        if let target = counterparty.identity?.nodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? counterparty.id.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            draftMeta["target_node_id"] = target
        }

        var draft = ExchangeMessageDraft(
            id: draftID,
            threadID: basisThread.id,
            createdAt: now,
            updatedAt: now,
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            subject: subject,
            body: trimmedBody,
            posture: basisThread.posture,
            targetCounterpartyID: counterparty.id,
            metadata: draftMeta
        )

        if let attachment {
            guard let dmAttachmentClient else {
                throw ExchangeStoreError.storageFailure(
                    reason: "DM attachment upload is not configured on this client."
                )
            }
            let recipientNodeID =
                counterparty.identity?.nodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                ?? counterparty.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let fileData: Data
            do {
                fileData = try Data(contentsOf: attachment.fileURL)
            } catch {
                throw ExchangeStoreError.storageFailure(
                    reason: "Could not read attachment file: \(error.localizedDescription)"
                )
            }

            let localHasEncryptionKey = local.encryptionKeyID?.nilIfBlank != nil
                && local.encryptionPublicKey?.nilIfBlank != nil

            switch await ExchangeFederationPrivateTextE2EE.resolveRecipientEncryptionKey(
                federationBaseURL: federationBaseURL,
                recipientNodeID: recipientNodeID
            ) {
            case .keyFetchFailed:
                ExchangeFederationAttachmentE2EE.logSend(
                    encrypted: false,
                    blocked: true,
                    reason: "keyFetchFailed"
                )
                throw ExchangePrivateE2EESendBlockedError.blocked(reason: "keyFetchFailed")
            case .noRecipientKey:
                ExchangeFederationAttachmentE2EE.logSend(
                    encrypted: false,
                    byteSize: fileData.count,
                    fallback: true,
                    reason: "noRecipientKey"
                )
                let descriptor = try await dmAttachmentClient.uploadDMAttachment(
                    fileData: fileData,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    recipientNodeID: recipientNodeID,
                    encrypted: false
                )
                DirectMessageAttachmentMetadata.apply(descriptors: [descriptor], to: &draft.metadata)
                _ = try? DirectMessageAttachmentCache.write(
                    data: fileData,
                    storageKey: descriptor.storageKey,
                    filename: descriptor.filename
                )
            case .available(_, let recipientEncryptionPublicKey):
                guard localHasEncryptionKey else {
                    ExchangeFederationAttachmentE2EE.logSend(
                        encrypted: false,
                        blocked: true,
                        reason: "missingLocalEncryptionKey"
                    )
                    throw ExchangePrivateE2EESendBlockedError.blocked(reason: "missingLocalEncryptionKey")
                }

                let sealed: ExchangeAttachmentSealerResult
                do {
                    sealed = try attachmentSealer.seal(
                        fileData: fileData,
                        originalFilename: attachment.filename,
                        originalMimeType: attachment.mimeType,
                        recipientEncryptionPublicKeyBase64: recipientEncryptionPublicKey
                    )
                } catch {
                    ExchangeFederationAttachmentE2EE.logSend(
                        encrypted: false,
                        blocked: true,
                        reason: "cryptoError"
                    )
                    throw ExchangePrivateE2EESendBlockedError.blocked(reason: "cryptoError")
                }

                let uploadDescriptor: DirectMessageAttachmentDescriptor
                do {
                    uploadDescriptor = try await dmAttachmentClient.uploadDMAttachment(
                        fileData: sealed.encryptedData,
                        filename: "encrypted.bin",
                        mimeType: "application/vnd.unify.encrypted-attachment",
                        recipientNodeID: recipientNodeID,
                        encrypted: true
                    )
                } catch {
                    ExchangeFederationAttachmentE2EE.logSend(
                        encrypted: false,
                        blocked: true,
                        reason: "encryptedUploadFailed"
                    )
                    throw ExchangePrivateE2EESendBlockedError.blocked(reason: "encryptedUploadFailed")
                }

                let innerAttachment = sealed.completed(
                    storageKey: uploadDescriptor.storageKey,
                    downloadPath: uploadDescriptor.downloadPath
                )
                DirectMessageAttachmentMetadata.applyEncryptedRelayFlags(to: &draft.metadata)
                DirectMessageAttachmentMetadata.applyInnerPlaintextAttachments(
                    [innerAttachment],
                    to: &draft.metadata
                )
                let localDescriptor = DirectMessageAttachmentDescriptor(
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    byteSize: fileData.count,
                    storageKey: uploadDescriptor.storageKey,
                    downloadPath: uploadDescriptor.downloadPath,
                    sha256: sealed.plaintextSHA256,
                    uploadedAt: now,
                    accessScope: .dmPrivate
                )
                DirectMessageAttachmentMetadata.apply(descriptors: [localDescriptor], to: &draft.metadata)
                _ = try? DirectMessageAttachmentCache.write(
                    data: fileData,
                    storageKey: uploadDescriptor.storageKey,
                    filename: attachment.filename
                )
                ExchangeFederationAttachmentE2EE.logSend(
                    encrypted: true,
                    byteSize: sealed.encryptedByteSize,
                    reason: nil
                )
            }
        }

        let built = try await envelopeService.buildDirectMessageManualEnvelope(
            thread: basisThread,
            counterparty: counterparty,
            publicProfile: publicProfile,
            draft: draft,
            disclosureLevel: disclosureLevel,
            routeHint: nil,
            now: now
        )

        let envelope = built.envelope
        let stableID = envelope.stableEnvelopeID

        #if DEBUG
        Swift.print(
            "[DirectMessageSendV2][envelope] envelopeID=\(stableID) threadID=\(basisThread.id.uuidString) " +
                "surface=\(envelope.metadata["conversation_surface"] ?? "nil") " +
                "conversation_kind=\(envelope.metadata["conversation_kind"] ?? "nil") " +
                "payload=\(envelope.payload.kind.rawValue) encrypted=\(envelope.payload.encryption != nil)"
        )
        #endif

        let sendResult = try await relayClient.send(envelope, route: built.route)
        guard sendResult.indicatesOutboundProgress else {
            let detail = sendResult.note ?? "status=\(sendResult.status.rawValue)"
            throw ExchangeStoreError.storageFailure(reason: "Direct message relay send was not accepted (\(detail)).")
        }

        #if DEBUG
        Swift.print(
            "[RelaySendAccepted] envelopeID=\(stableID) recipient=\(counterparty.id) status=\(sendResult.status) time=\(Date())"
        )
        #endif

        let ref = sendResult.externalReference?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? stableID
        let sentDraft = draft.markingSent(externalReference: ref, at: now)

        let basisForBump = basisThread
        try await store.performTransaction {
            try await store.saveDraft(sentDraft)
            var bumped = basisForBump
            bumped.updatedAt = now
            try await store.updateThread(bumped)
        }

        try await DirectMessageLegacyExchangeOutbox.quarantineStaleItemsAfterDirectMessageSendV2Succeeded(
            store: store,
            threadID: basisThread.id,
            now: now
        )

        #if DEBUG
        Swift.print(
            "[DirectMessageSendV2][sent] threadID=\(basisThread.id.uuidString) draftID=\(draftID.uuidString) envelopeID=\(stableID)"
        )
        #endif
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
