import Foundation

/// Clean boundary for storing compact second-half priors.
///
/// This keeps second-half reasoning state separate from raw thread history,
/// transcripts, or first-half interpretation artifacts.
public protocol ExchangeThreadPriorsStore: Sendable {
    func loadPriors(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeThreadPriors?

    func savePriors(
        _ priors: ExchangeThreadPriors,
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws

    func clearPriors(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws
}
