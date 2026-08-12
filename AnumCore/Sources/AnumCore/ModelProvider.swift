import Foundation

public protocol ModelProvider: Sendable {
    func generate(prompt: String) async throws -> AsyncThrowingStream<String, Error>
}
