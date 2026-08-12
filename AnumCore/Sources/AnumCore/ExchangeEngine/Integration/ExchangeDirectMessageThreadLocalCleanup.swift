import Foundation

/// Thread-scoped cleanup for direct-message UserDefaults keys after a local hard-delete.
///
/// Does not remove global block lists or federation identity.
public enum ExchangeDirectMessageThreadLocalCleanup {
    public static let clearWatermarkKeyPrefix = "secretary.directMessage.clearWatermark."

    public static func clearWatermarkKey(for nodeID: String) -> String {
        let normalized = nodeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return clearWatermarkKeyPrefix + (normalized.isEmpty ? "unknown" : normalized)
    }

    /// Removes the DM clear watermark for `deletedThread`'s counterparty node when no other local DM thread remains.
    public static func clearConversationWatermarkIfNoRemainingThread(
        deletedThread: ExchangeThread,
        store: any ExchangeStore,
        defaults: UserDefaults = .standard
    ) async {
        guard ExchangeThreadLaneResolver.lane(for: deletedThread) == .directMessage else { return }
        guard let nodeID = await resolveCounterpartyNodeID(for: deletedThread, store: store) else { return }

        let hasRemaining = await hasDirectMessageThread(
            forNodeID: nodeID,
            excludingThreadID: deletedThread.id,
            store: store
        )
        guard !hasRemaining else { return }

        defaults.removeObject(forKey: clearWatermarkKey(for: nodeID))
    }

    private static func resolveCounterpartyNodeID(
        for thread: ExchangeThread,
        store: any ExchangeStore
    ) async -> String? {
        if let counterpartyID = thread.selectedCounterpartyID,
           let counterparty = try? await store.fetchCounterparty(id: counterpartyID),
           let nodeID = counterparty.identity?.nodeID?.nilIfBlank {
            return nodeID
        }

        if let metadataNode = thread.metadata["counterparty_node_id"]?.nilIfBlank {
            return metadataNode
        }
        if let metadataNode = thread.metadata["sender_node_id"]?.nilIfBlank {
            return metadataNode
        }
        return nil
    }

    private static func hasDirectMessageThread(
        forNodeID nodeID: String,
        excludingThreadID: ExchangeThread.ID,
        store: any ExchangeStore
    ) async -> Bool {
        let normalized = nodeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        let threads = (try? await store.listThreads(filter: .init())) ?? []
        for thread in threads where thread.id != excludingThreadID {
            guard ExchangeThreadLaneResolver.lane(for: thread) == .directMessage else { continue }
            if let threadNode = await resolveCounterpartyNodeID(for: thread, store: store)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               threadNode == normalized {
                return true
            }
        }
        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
