import Foundation
import Combine
import AnumCore

/// App-level orchestrator.
///
/// Why this exists:
/// - The *app* target is the right place to run one-time boot wiring (dev toggles, embedding provider selection, etc.)
/// - The *core* target should stay platform-agnostic.
///
/// Phase 4 hook:
/// - This file includes a single boot entry point (`AppBoot.ensureBooted()`).
/// - We wire a tiny embedder here without touching the model/runtime.
@MainActor
final class AppOrchestrator: ObservableObject, Orchestrator {
    let model: ModelProvider

    init(model: ModelProvider) {
        self.model = model
        AppBoot.ensureBooted()
    }

    func handleTurn(_ input: TurnInput) async throws -> AsyncThrowingStream<String, Error> {
        // IMPORTANT:
        // Prompt composition (identity + memory injection) should happen in Core.
        // The app orchestrator just forwards the already-composed userText for now.
        return try await model.generate(prompt: input.userText)
    }
}

// MARK: - App boot wiring

@MainActor
enum AppBoot {
    private static var didBoot = false

    static func ensureBooted() {
        guard !didBoot else { return }
        didBoot = true

        // Phase 4 (Embeddings) — app-level wiring point
        //
        // For now we wire a deterministic, ultra-light provider so everything compiles
        // and the retrieval pipeline can be verified end-to-end.
        //
        // Next step: replace `HashedEmbeddingProvider` with a real tiny sentence embedder
        // (CoreML / ONNX) without changing MemoryStore.

        Task { @MainActor in
            // Phase 4 (Embeddings) — wire the real ONNX embedder.
            // Assets live in the AnumCore SwiftPM resources bundle (EmbeddingAssets/...).
            // If anything fails, fall back to the deterministic hashed provider so the app still runs.

            #if DEBUG
            print("[AppBoot] Phase4: wiring embedding provider…")
            #endif

            // ONNXSentenceEmbedder's init is non-throwing, so we can't use do/catch.
            // Instead, do a tiny probe embed and fall back if it returns nil/empty.
            let onnx = ONNXSentenceEmbedder()
            let probe = onnx.embed("phase4 probe")
            
            if let v = probe, !v.isEmpty {
                await MemoryStore.shared.setEmbeddingProvider(onnx)

                #if DEBUG
                print("[AppBoot] Phase4: embedding provider = ONNXSentenceEmbedder vecDim=\(v.count)")
                #endif
            } else {
                let provider = HashedEmbeddingProvider(dim: 384)
                await MemoryStore.shared.setEmbeddingProvider(provider)

                #if DEBUG
                print("[AppBoot] Phase4: ONNXSentenceEmbedder probe returned nil/empty; using HashedEmbeddingProvider")
                #endif
            }
        }
    }
}

// MARK: - Fallback embedder (dev / bring-up)

/// A deterministic, cheap embedder used to validate the plumbing on-device.
/// Fallback when the ONNX embedder cannot be created.
struct HashedEmbeddingProvider: MemoryEmbeddingProvider, Sendable {
    let dim: Int

    init(dim: Int) {
        self.dim = dim
    }

    /// Required by `MemoryEmbeddingProvider`.
    /// Return `nil` only if the provider is unavailable.
    func embed(_ text: String) -> [Float]? {
        Self.hashedUnitVector(text: text, dim: dim)
    }

    // MARK: - Implementation

    private static func hashedUnitVector(text: String, dim: Int) -> [Float] {
        // Stable-ish hashing into a dense vector, then L2 normalize.
        // This is NOT semantically meaningful — it’s a wiring placeholder.
        var v = Array(repeating: Float(0), count: dim)

        var h: UInt64 = 1469598103934665603 // FNV offset basis
        for b in text.utf8 {
            h ^= UInt64(b)
            h &*= 1099511628211
            let idx = Int(h % UInt64(dim))
            v[idx] += 1
        }

        var norm: Float = 0
        for x in v { norm += x * x }
        norm = max(norm.squareRoot(), 1e-6)
        for i in v.indices { v[i] /= norm }

        return v
    }
}
