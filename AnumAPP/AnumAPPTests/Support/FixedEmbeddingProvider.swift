import Foundation
import AnumCore

/// Deterministic, ONNX-free `MemoryEmbeddingProvider` for retrieval tests.
/// Same input string always yields the same vector of `dimensions` floats.
struct FixedEmbeddingProvider: MemoryEmbeddingProvider, Sendable {
    let dimensions: Int

    init(dimensions: Int = 32) {
        self.dimensions = max(4, dimensions)
    }

    func embed(_ text: String) -> [Float]? {
        var hash: UInt64 = 1_469_581_033_466_560_3
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        var vector = [Float]()
        vector.reserveCapacity(dimensions)
        var state = hash
        for index in 0..<dimensions {
            state = state &* 1_099_511_628_211 &+ UInt64(index * 17 + 31)
            let frac = Float(state % 10_007) / Float(10_007)
            vector.append(sin(Float(index) * 0.07) * 0.5 + frac * 0.5 + 0.01)
        }
        return vector
    }
}
