import Foundation

/// Clean boundary for structured operating memory.
///
/// This keeps second-half logic from depending directly on old stores,
/// raw prompts, or UI-owned state.
public protocol ExchangeOperatingMemoryStore: Sendable {
    func loadOperatingMemory(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeStructuredOperatingMemory?

    func loadOperatingMemory(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeStructuredOperatingMemory?

    func saveOperatingMemory(
        _ memory: ExchangeStructuredOperatingMemory,
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws

    func saveOperatingMemory(
        _ memory: ExchangeStructuredOperatingMemory,
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws

    func clearOperatingMemory(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws

    func clearOperatingMemory(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws
}
