import Foundation
import AnumCore

struct StubModelProvider: ModelProvider {
    func generate(prompt: String) async throws -> AsyncThrowingStream<String, Error> {
        let tokens = [
            "Got it. ",
            "This is the first streaming reply from Anūm vNext. ",
            "Next we’ll plug in real inference + memory."
        ]

        return AsyncThrowingStream { continuation in
            Task {
                for t in tokens {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    continuation.yield(t)
                }
                continuation.finish()
            }
        }
    }
}
