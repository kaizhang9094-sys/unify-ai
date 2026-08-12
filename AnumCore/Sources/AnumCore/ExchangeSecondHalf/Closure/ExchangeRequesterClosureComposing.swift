import Foundation

/// Composes user-facing closure copy from deterministic pause evidence and secretary style (P1 mock; P2 local LLM).
public protocol ExchangeRequesterClosureComposing: Sendable {
    func compose(_ input: ExchangeRequesterClosureComposerInput) async throws -> ExchangeRequesterClosureComposedCopy
}
