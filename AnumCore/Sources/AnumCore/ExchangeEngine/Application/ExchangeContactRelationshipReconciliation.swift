import Foundation

/// Canonical post-trust relationship reconciliation (approval-owned, not discovery-owned).
struct ExchangeContactRelationshipReconciliation {
    let store: any ExchangeStore

    /// After an active trust edge exists, collapse competing pending state for one remote node.
    func reconcileConnectedState(
        sourceNodeID: String,
        remoteNodeID: String,
        now: Date,
        archiveInboxItems: (_ itemIDs: [ExchangeInboxItem.ID], _ now: Date) async throws -> Void,
        markOutgoingAccepted: (_ targetNodeID: String, _ now: Date) async throws -> Int
    ) async {
        let local = sourceNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = remoteNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !local.isEmpty, !remote.isEmpty else { return }

        guard let edge = try? await store.fetchTrustEdge(
            sourceNodeID: local,
            targetNodeID: remote
        ), edge.revokedAt == nil else {
            return
        }

        _ = try? await markOutgoingAccepted(remote, now)

        if let inboxItems = try? await store.listInboxItems(
            filter: .init(
                processingStates: [
                    .received,
                    .deferred,
                    .awaitingOrderingGapResolution,
                    .reconciledIntoThread
                ],
                processableOnly: false,
                limit: 500
            )
        ) {
            let pendingIDs = inboxItems.filter { item in
                guard ExchangeContactSignalClassifier.isInboundContactRequest(item) else { return false }
                let sender = item.senderNodeID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""
                return sender == remote.lowercased()
            }.map(\.id)

            if !pendingIDs.isEmpty {
                try? await archiveInboxItems(pendingIDs, now)
                #if DEBUG
                Swift.print(
                    "[ContactRelationshipReconcile] archivedPendingContactRequests remote=\(remote) count=\(pendingIDs.count)"
                )
                #endif
            }
        }

        await archiveMisplacedContactSignalDeskThreads(counterpartyNodeID: remote, now: now)

        #if DEBUG
        Swift.print(
            "[ContactRelationshipReconcile] connected source=\(local) remote=\(remote) edgeID=\(edge.id.uuidString)"
        )
        #endif
    }

    /// Completes messaging readiness after trust exists. Throws if the canonical DM thread cannot be opened.
    @discardableResult
    func completeRelationshipAfterTrust(
        sourceNodeID: String,
        remoteNodeID: String,
        displayName: String?,
        openDirectMessageThread: (_ counterpartyNodeID: String, _ displayName: String?, _ now: Date) async throws -> ExchangeThread.ID,
        archiveInboxItems: (_ itemIDs: [ExchangeInboxItem.ID], _ now: Date) async throws -> Void,
        markOutgoingAccepted: (_ targetNodeID: String, _ now: Date) async throws -> Int,
        now: Date
    ) async throws -> ExchangeThread.ID {
        #if DEBUG
        Swift.print(
            "[ContactRequestAccept] transaction begin remote=\(remoteNodeID)"
        )
        #endif

        await ExchangeFederationNodePresenceService.ensureLocalNodePresencePublishedIfNeeded()
        await ExchangeFederationNodePresenceService.ensureRecipientEncryptionKeyAvailable(
            remoteNodeID: remoteNodeID
        )

        await reconcileConnectedState(
            sourceNodeID: sourceNodeID,
            remoteNodeID: remoteNodeID,
            now: now,
            archiveInboxItems: archiveInboxItems,
            markOutgoingAccepted: markOutgoingAccepted
        )

        do {
            let threadID = try await openDirectMessageThread(remoteNodeID, displayName, now)
            #if DEBUG
            Swift.print(
                "[ContactRequestAccept] dmThreadEnsured remote=\(remoteNodeID) threadID=\(threadID.uuidString)"
            )
            Swift.print(
                "[ContactRequestAccept] transaction complete remote=\(remoteNodeID)"
            )
            #endif
            return threadID
        } catch {
            #if DEBUG
            Swift.print(
                "[ContactRequestAccept] dmThreadEnsureFailed remote=\(remoteNodeID) error=\(error)"
            )
            #endif
            throw ExchangeStoreError.storageFailure(
                reason: "Contact connected, but the direct message thread could not be opened: \(error)"
            )
        }
    }

    private func archiveMisplacedContactSignalDeskThreads(
        counterpartyNodeID: String,
        now: Date
    ) async {
        let remote = counterpartyNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty else { return }

        guard let threads = try? await store.listThreads(filter: .init(limit: 400)) else { return }

        for thread in threads {
            guard !thread.isArchived else { continue }
            guard ExchangeContactSignalClassifier.isContactSignalDeskThread(thread) else { continue }

            let counterparty = thread.selectedCounterpartyID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let inboundSender = thread.metadata["first_inbound_sender_node_id"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""

            guard counterparty == remote.lowercased() || inboundSender == remote.lowercased() else {
                continue
            }

            var archived = thread
            archived.metadata[ExchangeThreadArchiveMetadata.archivedKey] = "true"
            archived.metadata[ExchangeThreadArchiveMetadata.archivedAtKey] =
                String(now.timeIntervalSince1970)
            archived.updatedAt = now
            try? await store.updateThread(archived)

            #if DEBUG
            Swift.print(
                "[ContactRelationshipReconcile] archivedMisplacedContactSignalThread " +
                    "threadID=\(thread.id.uuidString) remote=\(remote)"
            )
            #endif
        }
    }
}

extension ExchangeContactRelationshipReconciliation {
    static func postRelationshipRefreshNotification(remoteNodeID: String, reason: String) {
        NotificationCenter.default.post(
            name: Notification.Name("secretaryWorkspaceShouldRefresh"),
            object: nil,
            userInfo: [
                "secretaryRefreshReason": ExchangeContactRelationshipRefreshNotification.relationshipChangedSecretaryRefreshReason,
                "reason": reason,
                "nodeID": remoteNodeID
            ]
        )
    }
}

/// Cross-module notification tokens for relationship status refresh (not coalesced like `.manual` desk replay).
public enum ExchangeContactRelationshipRefreshNotification {
    public static let relationshipChangedSecretaryRefreshReason = "relationshipChanged"
}
