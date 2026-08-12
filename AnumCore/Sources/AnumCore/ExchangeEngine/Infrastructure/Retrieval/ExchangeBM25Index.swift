import Foundation

/// Lightweight in-memory BM25 index for Exchange retrieval.
///
/// Notes:
/// - Built for on-device use.
/// - Indexes pre-tokenized retrieval documents.
/// - Keeps implementation simple and deterministic.
/// - Reads the current ExchangeRetrievalQuery shape.
public struct ExchangeBM25Index: Sendable {
    public struct SearchHit: Sendable, Hashable {
        public let documentID: String
        public let score: Double

        public init(documentID: String, score: Double) {
            self.documentID = documentID
            self.score = score
        }
    }

    private struct Posting: Sendable, Hashable {
        let documentID: String
        let termFrequency: Int
    }

    private struct DocumentStats: Sendable, Hashable {
        let length: Int
        let terms: [String: Int]
    }

    private let bm25K1: Double
    private let bm25B: Double

    private var postingsByTerm: [String: [Posting]]
    private var docFreqByTerm: [String: Int]
    private var statsByDocumentID: [String: DocumentStats]
    private var averageDocumentLength: Double
    private var totalDocuments: Int

    public init(
        k1: Double = 1.2,
        b: Double = 0.75
    ) {
        self.bm25K1 = k1
        self.bm25B = b
        self.postingsByTerm = [:]
        self.docFreqByTerm = [:]
        self.statsByDocumentID = [:]
        self.averageDocumentLength = 0
        self.totalDocuments = 0
    }

    public var isEmpty: Bool {
        totalDocuments == 0
    }

    /// Same lexical token stream as ``rebuild(documents:)`` / ``search(query:limit:)`` (lowercase, split on non-alphanumerics, Exchange stopwords only; no stemming).
    public static func debugTokenize(_ text: String) -> [String] {
        Self.tokenizeForBM25(text)
    }

    /// Concatenated query string that ``search(query:limit:)`` tokenizes for BM25 (must stay in sync with ``search``).
    public static func lexicalQueryTextForBM25Search(_ query: ExchangeRetrievalQuery) -> String {
        let hardConstraintValues = query.explicitHardConstraints.map(\.value)

        var queryParts: [String] = []
        queryParts.append(query.normalizedQueryText)
        queryParts.append(query.normalizedSemanticText)
        queryParts.append(query.providerTerms.joined(separator: " "))
        queryParts.append(query.capabilityTerms.joined(separator: " "))
        queryParts.append(query.affinityTerms.joined(separator: " "))
        queryParts.append(query.regionTerms.joined(separator: " "))
        queryParts.append(query.softRegionTerms.joined(separator: " "))
        queryParts.append(query.commercialIntentTerms.joined(separator: " "))
        queryParts.append(query.timeTerms.joined(separator: " "))
        queryParts.append(query.keywords.joined(separator: " "))
        queryParts.append(hardConstraintValues.joined(separator: " "))
        if let targetKind = query.targetKind { queryParts.append(targetKind) }
        if let fulfillmentMode = query.fulfillmentMode { queryParts.append(fulfillmentMode) }

        return queryParts
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tokenizeForBM25(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !$0.exchangeIsStopWord }
    }

    public mutating func rebuild(documents: [ExchangeRetrievalDocument]) {
        postingsByTerm.removeAll(keepingCapacity: true)
        docFreqByTerm.removeAll(keepingCapacity: true)
        statsByDocumentID.removeAll(keepingCapacity: true)
        averageDocumentLength = 0
        totalDocuments = 0

        guard !documents.isEmpty else { return }

        var totalLength = 0

        for document in documents {
            let tokens = Self.tokenizeForBM25(document.searchableText)
            guard !tokens.isEmpty else {
                statsByDocumentID[document.id] = DocumentStats(length: 0, terms: [:])
                continue
            }

            let tf = termFrequency(tokens)
            let length = tokens.count

            statsByDocumentID[document.id] = DocumentStats(
                length: length,
                terms: tf
            )

            totalLength += length

            for (term, frequency) in tf {
                postingsByTerm[term, default: []].append(
                    Posting(documentID: document.id, termFrequency: frequency)
                )
                docFreqByTerm[term, default: 0] += 1
            }
        }

        totalDocuments = documents.count
        averageDocumentLength = totalDocuments > 0
            ? Double(totalLength) / Double(totalDocuments)
            : 0
    }

    public func search(
        query: ExchangeRetrievalQuery,
        limit: Int
    ) -> [SearchHit] {
        guard totalDocuments > 0 else { return [] }

        let cappedLimit = max(0, limit)
        guard cappedLimit > 0 else { return [] }

        let queryText = Self.lexicalQueryTextForBM25Search(query)

        let queryTokens = Self.tokenizeForBM25(queryText)
        guard !queryTokens.isEmpty else { return [] }

        let uniqueQueryTerms = Array(Set(queryTokens))
        var scoresByDocumentID: [String: Double] = [:]

        for term in uniqueQueryTerms {
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
                let norm: Double
                if averageDocumentLength > 0 {
                    norm = (1.0 - bm25B) + bm25B * (docLen / averageDocumentLength)
                } else {
                    norm = 1.0
                }

                let numerator = tf * (bm25K1 + 1.0)
                let denominator = tf + bm25K1 * norm
                let safeRatio: Double = denominator > 0 ? numerator / denominator : 0.0
                let contribution = idf * safeRatio

                scoresByDocumentID[posting.documentID, default: 0.0] += contribution
            }
        }

        return scoresByDocumentID
            .map { SearchHit(documentID: $0.key, score: $0.value) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.documentID < $1.documentID
            }
            .prefix(cappedLimit)
            .map { $0 }
    }

    private func inverseDocumentFrequency(documentFrequency df: Int) -> Double {
        let n = Double(totalDocuments)
        let dfValue = Double(df)
        return log(1.0 + ((n - dfValue + 0.5) / (dfValue + 0.5)))
    }

    private func termFrequency(_ tokens: [String]) -> [String: Int] {
        var tf: [String: Int] = [:]
        for token in tokens {
            tf[token, default: 0] += 1
        }
        return tf
    }

}

private extension String {
    var exchangeIsStopWord: Bool {
        [
            "the", "a", "an", "for", "to", "with", "and", "or", "of", "in", "on",
            "my", "me", "our", "their", "is", "are", "be", "this", "that"
        ].contains(self)
    }
}
