import Foundation

#if DEBUG
@inline(__always)
private func exIntentExemplarStoreLog(_ message: @autoclosure () -> String) {
    print("[ExchangeIntentExemplarStore] \(message())")
}
#else
@inline(__always)
private func exIntentExemplarStoreLog(_ message: @autoclosure () -> String) { }
#endif

/// In-memory exemplar store with lexical and vector indexes.
///
/// Notes:
/// - small corpus by design
/// - optimized for on-device lookup
/// - supports cheap rebuild when exemplars evolve
public struct ExchangeIntentExemplarStore: Sendable {
    public struct LexicalHit: Sendable, Hashable {
        public let exemplarID: String
        public let score: Double

        public init(exemplarID: String, score: Double) {
            self.exemplarID = exemplarID
            self.score = score
        }
    }

    public struct VectorHit: Sendable, Hashable {
        public let exemplarID: String
        public let score: Double

        public init(exemplarID: String, score: Double) {
            self.exemplarID = exemplarID
            self.score = score
        }
    }

    private let exemplarsByID: [String: ExchangeIntentExemplar]
    private let lexicalIndex: ExemplarBM25Index
    private let vectorIndex: ExemplarVectorIndex

    public init(
        exemplars: [ExchangeIntentExemplar],
        embeddingProvider: (any MemoryEmbeddingProvider)? = nil
    ) {
        let deduped = Self.dedupedExemplars(exemplars)

        var lexicalIndex = ExemplarBM25Index()
        lexicalIndex.rebuild(exemplars: deduped)

        var vectorIndex = ExemplarVectorIndex()
        if let embeddingProvider {
            vectorIndex.rebuild(
                exemplars: deduped,
                embeddingProvider: embeddingProvider
            )
        }

        self.exemplarsByID = Dictionary(uniqueKeysWithValues: deduped.map { ($0.id, $0) })
        self.lexicalIndex = lexicalIndex
        self.vectorIndex = vectorIndex

        exIntentExemplarStoreLog(
            "init exemplars=\(deduped.count) lexicalReady=\(!lexicalIndex.isEmpty) vectorReady=\(!vectorIndex.isEmpty)"
        )
    }

    public static func bootstrap(
        embeddingProvider: (any MemoryEmbeddingProvider)? = nil
    ) -> ExchangeIntentExemplarStore {
        .init(
            exemplars: ExchangeIntentExemplar.bootstrap,
            embeddingProvider: embeddingProvider
        )
    }

    public var exemplars: [ExchangeIntentExemplar] {
        exemplarsByID.values.sorted { $0.id < $1.id }
    }

    public var isEmpty: Bool {
        exemplarsByID.isEmpty
    }

    public func exemplar(
        for id: String
    ) -> ExchangeIntentExemplar? {
        exemplarsByID[id]
    }

    public func searchLexical(
        text: String,
        limit: Int
    ) -> [LexicalHit] {
        lexicalIndex.search(text: text, limit: limit)
            .map { .init(exemplarID: $0.documentID, score: $0.score) }
    }

    public func searchVector(
        text: String,
        embeddingProvider: any MemoryEmbeddingProvider,
        limit: Int
    ) -> [VectorHit] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        guard let embedding = embeddingProvider.embed(normalized), !embedding.isEmpty else {
            return []
        }

        return vectorIndex.search(queryEmbedding: embedding, limit: limit)
            .map { .init(exemplarID: $0.documentID, score: $0.score) }
    }
}

private extension ExchangeIntentExemplarStore {
    static func dedupedExemplars(
        _ exemplars: [ExchangeIntentExemplar]
    ) -> [ExchangeIntentExemplar] {
        var seen = Set<String>()
        var output: [ExchangeIntentExemplar] = []

        for exemplar in exemplars {
            let key = exemplar.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(exemplar)
        }

        return output
    }
}

// MARK: - Internal lexical index

private struct ExemplarBM25Index: Sendable {
    struct SearchHit: Sendable, Hashable {
        let documentID: String
        let score: Double
    }

    private struct Posting: Sendable, Hashable {
        let documentID: String
        let termFrequency: Int
    }

    private struct DocumentStats: Sendable, Hashable {
        let length: Int
    }

    private let k1: Double
    private let b: Double

    private var postingsByTerm: [String: [Posting]]
    private var docFreqByTerm: [String: Int]
    private var statsByDocumentID: [String: DocumentStats]
    private var averageDocumentLength: Double
    private var totalDocuments: Int

    init(
        k1: Double = 1.2,
        b: Double = 0.75
    ) {
        self.k1 = k1
        self.b = b
        self.postingsByTerm = [:]
        self.docFreqByTerm = [:]
        self.statsByDocumentID = [:]
        self.averageDocumentLength = 0
        self.totalDocuments = 0
    }

    var isEmpty: Bool {
        totalDocuments == 0
    }

    mutating func rebuild(
        exemplars: [ExchangeIntentExemplar]
    ) {
        postingsByTerm.removeAll(keepingCapacity: true)
        docFreqByTerm.removeAll(keepingCapacity: true)
        statsByDocumentID.removeAll(keepingCapacity: true)
        averageDocumentLength = 0
        totalDocuments = 0

        guard !exemplars.isEmpty else { return }

        var totalLength = 0

        for exemplar in exemplars {
            let tokens = tokenize(exemplar.lexicalText)
            let tf = termFrequency(tokens)
            let length = tokens.count

            statsByDocumentID[exemplar.id] = .init(length: length)
            totalLength += length

            for (term, frequency) in tf {
                postingsByTerm[term, default: []].append(
                    .init(documentID: exemplar.id, termFrequency: frequency)
                )
                docFreqByTerm[term, default: 0] += 1
            }
        }

        totalDocuments = exemplars.count
        averageDocumentLength = totalDocuments > 0
            ? Double(totalLength) / Double(totalDocuments)
            : 0
    }

    func search(
        text: String,
        limit: Int
    ) -> [SearchHit] {
        guard totalDocuments > 0 else { return [] }

        let queryTokens = Array(Set(tokenize(text)))
        guard !queryTokens.isEmpty else { return [] }

        var scoresByDocumentID: [String: Double] = [:]

        for term in queryTokens {
            guard
                let postings = postingsByTerm[term],
                let df = docFreqByTerm[term],
                df > 0
            else {
                continue
            }

            let idf = inverseDocumentFrequency(documentFrequency: df)

            for posting in postings {
                guard let stats = statsByDocumentID[posting.documentID] else { continue }

                let tf = Double(posting.termFrequency)
                let docLen = Double(stats.length)

                let norm = averageDocumentLength > 0
                    ? (1.0 - b) + b * (docLen / averageDocumentLength)
                    : 1.0

                let numerator = tf * (k1 + 1.0)
                let denominator = tf + k1 * norm
                let contribution = idf * (denominator > 0 ? numerator / denominator : 0.0)

                scoresByDocumentID[posting.documentID, default: 0] += contribution
            }
        }

        return scoresByDocumentID
            .map { .init(documentID: $0.key, score: $0.value) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.documentID < $1.documentID
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private func inverseDocumentFrequency(
        documentFrequency df: Int
    ) -> Double {
        let n = Double(totalDocuments)
        let df = Double(df)
        return log(1.0 + ((n - df + 0.5) / (df + 0.5)))
    }

    private func termFrequency(
        _ tokens: [String]
    ) -> [String: Int] {
        var output: [String: Int] = [:]
        for token in tokens {
            output[token, default: 0] += 1
        }
        return output
    }

    private func tokenize(
        _ text: String
    ) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !$0.exemplarIsStopWord }
    }
}

// MARK: - Internal vector index

private struct ExemplarVectorIndex: Sendable {
    struct SearchHit: Sendable, Hashable {
        let documentID: String
        let score: Double
    }

    private var embeddingsByDocumentID: [String: [Float]]

    init() {
        self.embeddingsByDocumentID = [:]
    }

    var isEmpty: Bool {
        embeddingsByDocumentID.isEmpty
    }

    mutating func rebuild(
        exemplars: [ExchangeIntentExemplar],
        embeddingProvider: any MemoryEmbeddingProvider
    ) {
        embeddingsByDocumentID.removeAll(keepingCapacity: true)

        for exemplar in exemplars {
            guard let embedding = embeddingProvider.embed(exemplar.semanticText), !embedding.isEmpty else {
                continue
            }
            embeddingsByDocumentID[exemplar.id] = l2Normalize(embedding)
        }
    }

    func search(
        queryEmbedding: [Float],
        limit: Int
    ) -> [SearchHit] {
        guard !queryEmbedding.isEmpty else { return [] }
        guard !embeddingsByDocumentID.isEmpty else { return [] }

        let normalizedQuery = l2Normalize(queryEmbedding)

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
            .prefix(max(0, limit))
            .map { $0 }
    }

    private func dot(
        lhs: [Float],
        rhs: [Float]
    ) -> Float {
        var sum: Float = 0
        for i in 0..<lhs.count {
            sum += lhs[i] * rhs[i]
        }
        return sum
    }

    private func l2Normalize(
        _ vector: [Float]
    ) -> [Float] {
        var sum: Float = 0
        for x in vector { sum += x * x }
        let norm = sqrt(sum)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}

private extension String {
    var exemplarIsStopWord: Bool {
        [
            "the", "a", "an", "for", "to", "with", "and", "or", "of", "in", "on",
            "my", "me", "our", "their", "is", "are", "be", "this", "that"
        ].contains(self)
    }
}
