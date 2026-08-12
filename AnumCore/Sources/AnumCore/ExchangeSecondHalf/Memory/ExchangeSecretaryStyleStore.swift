import Foundation

/// Clean boundary for secretary style persistence.
///
/// Style should not live only inside prompt text or temporary UI state.
public protocol ExchangeSecretaryStyleStore: Sendable {
    func loadStyleProfile(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeSecretaryStyleProfile?

    func loadStyleProfile(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeSecretaryStyleProfile?

    func saveStyleProfile(
        _ profile: ExchangeSecretaryStyleProfile,
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws

    func saveStyleProfile(
        _ profile: ExchangeSecretaryStyleProfile,
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws

    func clearStyleProfile(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws

    func clearStyleProfile(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws
}
