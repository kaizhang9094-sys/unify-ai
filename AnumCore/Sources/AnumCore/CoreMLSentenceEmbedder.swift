import Foundation
@preconcurrency import CoreML

// -----------------------------
// DEBUG-only logging (shipping hygiene)
// -----------------------------
@inline(__always)
private func cmlLog(_ msg: @autoclosure () -> String) {
#if DEBUG
    print(msg())
#endif
}

public final class CoreMLSentenceEmbedder: EmbeddingProvider, @unchecked Sendable {    public let dim: Int

    private let model: MLModel
    private let inputKey: String
    private let outputKey: String

    /// - Parameters:
    ///   - compiledModelName: name of the `.mlmodelc` folder in the app bundle (without extension).
    ///   - inputKey/outputKey: optional overrides if you know your model's IO names.
    public init?(
        compiledModelName: String,
        inputKey: String? = nil,
        outputKey: String? = nil
    ) {
        guard let url = Bundle.main.url(forResource: compiledModelName, withExtension: "mlmodelc") else {
            cmlLog("[CoreMLSentenceEmbedder] Missing \(compiledModelName).mlmodelc in bundle")
            return nil
        }

        let loadedModel: MLModel
        do {
            loadedModel = try MLModel(contentsOf: url)
        } catch {
            cmlLog("[CoreMLSentenceEmbedder] Failed to load model: \(error)")
            return nil
        }

        // Infer keys if not provided (use locals; avoid touching `self` until the end)
        let inDesc = loadedModel.modelDescription.inputDescriptionsByName
        let outDesc = loadedModel.modelDescription.outputDescriptionsByName
        let inKeys = Array(inDesc.keys)
        let outKeys = Array(outDesc.keys)

        let resolvedInputKey: String
        if let inputKey {
            resolvedInputKey = inputKey
        } else if let k = inKeys.first(where: { inDesc[$0]?.type == .string }) {
            resolvedInputKey = k
        } else if let first = inKeys.first {
            resolvedInputKey = first
        } else {
            cmlLog("[CoreMLSentenceEmbedder] No inputs found")
            return nil
        }

        let resolvedOutputKey: String
        if let outputKey {
            resolvedOutputKey = outputKey
        } else if let k = outKeys.first(where: { outDesc[$0]?.type == .multiArray }) {
            resolvedOutputKey = k
        } else if let first = outKeys.first {
            resolvedOutputKey = first
        } else {
            cmlLog("[CoreMLSentenceEmbedder] No outputs found")
            return nil
        }

        // Best-effort dim inference from output constraints (fallback to 384)
        var resolvedDim = 384
        if let o = outDesc[resolvedOutputKey], o.type == .multiArray,
           let shape = o.multiArrayConstraint?.shape, let last = shape.last {
            resolvedDim = last.intValue
        }

        self.model = loadedModel
        self.inputKey = resolvedInputKey
        self.outputKey = resolvedOutputKey
        self.dim = resolvedDim
    }

    public func embed(_ text: String) -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // This only works if the model accepts String directly.
        let features: [String: MLFeatureValue] = [
            inputKey: MLFeatureValue(string: trimmed)
        ]

        guard let input = try? MLDictionaryFeatureProvider(dictionary: features) else {
            return nil
        }

        guard let pred = try? model.prediction(from: input) else {
            return nil
        }

        guard let fv = pred.featureValue(for: outputKey),
              let arr = fv.multiArrayValue else {
            return nil
        }

        return multiArrayToFloat(arr)
    }

    private func multiArrayToFloat(_ arr: MLMultiArray) -> [Float] {
        let n = arr.count
        var out = [Float](repeating: 0, count: n)

        switch arr.dataType {
        case .float32:
            let ptr = arr.dataPointer.bindMemory(to: Float.self, capacity: n)
            for i in 0..<n { out[i] = ptr[i] }
        case .double:
            let ptr = arr.dataPointer.bindMemory(to: Double.self, capacity: n)
            for i in 0..<n { out[i] = Float(ptr[i]) }
        case .float16:
            // float16 not directly accessible without conversion; fall back via NSNumber
            for i in 0..<n { out[i] = Float(truncating: arr[i]) }
        default:
            for i in 0..<n { out[i] = Float(truncating: arr[i]) }
        }

        return out
    }
}
