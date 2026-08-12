import Foundation

/// Lightweight in-memory vector index.
///
/// Notes:
/// - Stores normalized embeddings internally
/// - Uses cosine similarity via dot product
/// - Keeps dependencies minimal for on-device use
public struct ExchangeVectorIndex: Sendable {
    public struct SearchHit: Sendable, Hashable {
        public let documentID: String
        public let score: Double

        public init(documentID: String, score: Double) {
            self.documentID = documentID
            self.score = score
        }
    }

    private var embeddingsByDocumentID: [String: [Float]]

    public init() {
        self.embeddingsByDocumentID = [:]
    }

    public var isEmpty: Bool {
        embeddingsByDocumentID.isEmpty
    }

    public mutating func rebuild(documents: [ExchangeRetrievalDocument]) {
        embeddingsByDocumentID.removeAll(keepingCapacity: true)

        for document in documents {
            guard let embedding = document.embedding, !embedding.isEmpty else { continue }
            embeddingsByDocumentID[document.id] = l2Normalize(embedding)
        }
    }

    public func search(
        embedding queryEmbedding: [Float],
        limit: Int
    ) -> [SearchHit] {
        guard !queryEmbedding.isEmpty else { return [] }
        guard !embeddingsByDocumentID.isEmpty else { return [] }

        let normalizedQuery = l2Normalize(queryEmbedding)
        let cappedLimit = max(0, limit)
        guard cappedLimit > 0 else { return [] }

        return embeddingsByDocumentID
            .compactMap { documentID, embedding in
                guard embedding.count == normalizedQuery.count else { return nil }
                let score = dot(lhs: normalizedQuery, rhs: embedding)
                return SearchHit(documentID: documentID, score: Double(score))
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.documentID < $1.documentID
            }
            .prefix(cappedLimit)
            .map { $0 }
    }

    private func dot(lhs: [Float], rhs: [Float]) -> Float {
        var sum: Float = 0
        for i in 0..<lhs.count {
            sum += lhs[i] * rhs[i]
        }
        return sum
    }

    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var sum: Float = 0
        for x in vector { sum += x * x }
        let norm = sqrt(sum)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
