import Foundation

/// Small, fast sentence embedder interface.
/// Returns a float vector (already in the model's native dimension).
public protocol EmbeddingProvider: Sendable {
    var dim: Int { get }
    func embed(_ text: String) -> [Float]?
}
