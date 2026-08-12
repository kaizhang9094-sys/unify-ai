import Foundation

public protocol Orchestrator: Sendable {
    func handleTurn(_ input: TurnInput) async throws -> AsyncThrowingStream<String, Error>
}
