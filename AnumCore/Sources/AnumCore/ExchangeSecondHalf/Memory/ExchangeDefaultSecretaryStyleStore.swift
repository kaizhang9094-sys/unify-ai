import Foundation

/// Default canonical secretary style store.
///
/// Simple in-memory implementation for greenfield second-half development.
public actor ExchangeDefaultSecretaryStyleStore: ExchangeSecretaryStyleStore {
    private struct ThreadKey: Hashable, Sendable {
        let threadID: UUID
        let role: ExchangeSecondHalfRole
    }

    private struct NodeKey: Hashable, Sendable {
        let nodeID: UUID
        let role: ExchangeSecondHalfRole
    }

    private var threadScopedProfiles: [ThreadKey: ExchangeSecretaryStyleProfile]
    private var nodeScopedProfiles: [NodeKey: ExchangeSecretaryStyleProfile]

    public init(
        threadScopedProfiles: [UUID: ExchangeSecretaryStyleProfile] = [:],
        nodeScopedProfiles: [UUID: ExchangeSecretaryStyleProfile] = [:]
    ) {
        self.threadScopedProfiles = threadScopedProfiles.reduce(into: [:]) { partial, entry in
            partial[ThreadKey(threadID: entry.key, role: .requester)] = entry.value
        }
        self.nodeScopedProfiles = nodeScopedProfiles.reduce(into: [:]) { partial, entry in
            partial[NodeKey(nodeID: entry.key, role: .requester)] = entry.value
        }
    }

    public func loadStyleProfile(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeSecretaryStyleProfile? {
        threadScopedProfiles[ThreadKey(threadID: threadID, role: role)]
    }

    public func loadStyleProfile(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeSecretaryStyleProfile? {
        nodeScopedProfiles[NodeKey(nodeID: nodeID, role: role)]
    }

    public func saveStyleProfile(
        _ profile: ExchangeSecretaryStyleProfile,
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        threadScopedProfiles[ThreadKey(threadID: threadID, role: role)] = profile
    }

    public func saveStyleProfile(
        _ profile: ExchangeSecretaryStyleProfile,
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        nodeScopedProfiles[NodeKey(nodeID: nodeID, role: role)] = profile
    }

    public func clearStyleProfile(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        threadScopedProfiles.removeValue(forKey: ThreadKey(threadID: threadID, role: role))
    }

    public func clearStyleProfile(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        nodeScopedProfiles.removeValue(forKey: NodeKey(nodeID: nodeID, role: role))
    }
}
