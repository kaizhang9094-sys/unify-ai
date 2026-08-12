import Foundation

/// Shared directory-query embedding path: prefers ``ONNXSentenceEmbedder/embedQuery(_:)`` (E5-style query prefix)
/// when the provider is ONNX; otherwise uses ``MemoryEmbeddingProvider/embed(_:)``.
public enum ExchangeDirectoryQueryEmbedding {
    public static func embedQueryText(_ text: String, provider: any MemoryEmbeddingProvider) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let onnx = provider as? ONNXSentenceEmbedder {
            return onnx.embedQuery(trimmed)
        }
        return provider.embed(trimmed)
    }
}
