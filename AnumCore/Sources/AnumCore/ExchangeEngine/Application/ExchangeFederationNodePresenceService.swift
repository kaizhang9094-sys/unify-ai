import Foundation

/// Publishes local federation node presence and encryption keys (bootstrap-owned, not discovery).
enum ExchangeFederationNodePresenceService {
    @discardableResult
    static func ensureLocalNodePresencePublishedIfNeeded() async -> Bool {
        do {
            let identity = try await BootstrappedIdentityService().localIdentity()
            let client = ExchangeHTTPDirectoryClient(
                baseURL: ExchangeBootstrap.resolvedFederationBaseURL()
            )

            let localHasEncryptionKey =
                identity.encryptionKeyID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                && identity.encryptionPublicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

            try await client.registerNode(
                nodeID: identity.nodeID,
                displayName: identity.displayName ?? "Unify Node \(identity.nodeID.suffix(6))",
                publicKeyID: identity.publicKeyID,
                publicProfile: ExchangeHTTPDirectoryClient.RegisterPublicProfile(
                    id: "node-presence-\(identity.nodeID)",
                    visibility: .limited,
                    availability: .open,
                    openTo: ["coordination"],
                    offers: ["secretary-node"],
                    semantic: [
                        "tags": ["unify", "secretary", "node"]
                    ],
                    reachability: ExchangeHTTPDirectoryClient.RegisterPublicProfile.Reachability(
                        acceptingInbound: true,
                        accessMode: "direct"
                    )
                ),
                encryptionKeyID: identity.encryptionKeyID,
                encryptionPublicKey: identity.encryptionPublicKey
            )

            _ = try? await client.fetchNodePublicKeys(
                nodeID: identity.nodeID,
                forceRefresh: true
            )

            #if DEBUG
            Swift.print(
                "[ContactRelationshipBootstrap] localNodePresencePublished nodeID=\(identity.nodeID) " +
                    "encryptionPublished=\(localHasEncryptionKey)"
            )
            #endif
            return true
        } catch {
            #if DEBUG
            Swift.print(
                "[ContactRelationshipBootstrap] localNodePresencePublishFailed error=\(error)"
            )
            #endif
            return false
        }
    }

    static func ensureRecipientEncryptionKeyAvailable(remoteNodeID: String) async {
        let trimmed = remoteNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch await ExchangeFederationPrivateTextE2EE.resolveRecipientEncryptionKey(
            federationBaseURL: ExchangeBootstrap.resolvedFederationBaseURL(),
            recipientNodeID: trimmed
        ) {
        case .available:
            #if DEBUG
            Swift.print(
                "[ContactRelationshipBootstrap] recipientEncryptionKeyAvailable nodeID=\(trimmed)"
            )
            #endif
        case .noRecipientKey:
            #if DEBUG
            Swift.print(
                "[ContactRelationshipBootstrap] recipientEncryptionKeyMissing nodeID=\(trimmed)"
            )
            #endif
        case .keyFetchFailed:
            #if DEBUG
            Swift.print(
                "[ContactRelationshipBootstrap] recipientEncryptionKeyFetchFailed nodeID=\(trimmed)"
            )
            #endif
        }
    }
}
