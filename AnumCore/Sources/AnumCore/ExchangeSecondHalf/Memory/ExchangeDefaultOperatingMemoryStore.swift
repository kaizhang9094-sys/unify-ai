import Foundation

/// Default canonical operating memory store.
///
/// This starts as a simple in-memory implementation so the new second-half
/// subsystem can be developed cleanly before being attached to older stores.
public actor ExchangeDefaultOperatingMemoryStore: ExchangeOperatingMemoryStore {
    private struct ThreadKey: Hashable, Sendable {
        let threadID: UUID
        let role: ExchangeSecondHalfRole
    }

    private struct NodeKey: Hashable, Sendable {
        let nodeID: UUID
        let role: ExchangeSecondHalfRole
    }

    private var threadScopedMemory: [ThreadKey: ExchangeStructuredOperatingMemory]
    private var nodeScopedMemory: [NodeKey: ExchangeStructuredOperatingMemory]

    public init(
        threadScopedMemory: [UUID: ExchangeStructuredOperatingMemory] = [:],
        nodeScopedMemory: [UUID: ExchangeStructuredOperatingMemory] = [:]
    ) {
        self.threadScopedMemory = threadScopedMemory.reduce(into: [:]) { partial, entry in
            partial[ThreadKey(threadID: entry.key, role: .requester)] = entry.value
        }
        self.nodeScopedMemory = nodeScopedMemory.reduce(into: [:]) { partial, entry in
            partial[NodeKey(nodeID: entry.key, role: .requester)] = entry.value
        }
    }

    public func loadOperatingMemory(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeStructuredOperatingMemory? {
        threadScopedMemory[ThreadKey(threadID: threadID, role: role)]
    }

    public func loadOperatingMemory(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeStructuredOperatingMemory? {
        nodeScopedMemory[NodeKey(nodeID: nodeID, role: role)]
    }

    public func saveOperatingMemory(
        _ memory: ExchangeStructuredOperatingMemory,
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        threadScopedMemory[ThreadKey(threadID: threadID, role: role)] = memory
    }

    public func saveOperatingMemory(
        _ memory: ExchangeStructuredOperatingMemory,
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        nodeScopedMemory[NodeKey(nodeID: nodeID, role: role)] = memory
    }

    public func clearOperatingMemory(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        threadScopedMemory.removeValue(forKey: ThreadKey(threadID: threadID, role: role))
    }

    public func clearOperatingMemory(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        nodeScopedMemory.removeValue(forKey: NodeKey(nodeID: nodeID, role: role))
    }
}
