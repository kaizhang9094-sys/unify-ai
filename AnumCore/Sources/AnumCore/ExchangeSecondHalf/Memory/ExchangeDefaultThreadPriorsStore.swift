import Foundation

/// Default canonical priors persistence implementation.
///
/// Starts as a simple in-memory store so the second-half module can evolve
/// cleanly before being attached to legacy persistence.
public actor ExchangeDefaultThreadPriorsStore: ExchangeThreadPriorsStore {
    private struct ThreadKey: Hashable, Sendable {
        let threadID: UUID
        let role: ExchangeSecondHalfRole
    }

    private var storage: [ThreadKey: ExchangeThreadPriors]

    public init(
        seed: [UUID: ExchangeThreadPriors] = [:]
    ) {
        self.storage = seed.reduce(into: [:]) { partial, entry in
            partial[ThreadKey(threadID: entry.key, role: .requester)] = entry.value
        }
    }

    public func loadPriors(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeThreadPriors? {
        storage[ThreadKey(threadID: threadID, role: role)]
    }

    public func savePriors(
        _ priors: ExchangeThreadPriors,
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        storage[ThreadKey(threadID: threadID, role: role)] = priors
    }

    public func clearPriors(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        storage.removeValue(forKey: ThreadKey(threadID: threadID, role: role))
    }
}
