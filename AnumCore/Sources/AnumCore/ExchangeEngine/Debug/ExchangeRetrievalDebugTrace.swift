import Foundation

/// Structured retrieval ranking trace for accuracy harnesses and DEBUG diagnostics.
/// Does not capture private document text.
public enum ExchangeRetrievalDebugTrace: Sendable {
    public struct RankingRow: Sendable, Hashable, Codable {
        public var documentID: String
        public var docKind: String?
        public var surfaceType: String
        public var counterpartyID: String
        public var nodeID: String?
        public var publicProfileID: String?
        public var offerID: String?
        public var bm25Rank: Int?
        public var vectorRank: Int?
        public var objectLaneRank: Int?
        public var bm25Score: Double?
        public var vectorScore: Double?
        public var objectLaneScore: Double?
        public var surfaceBias: Double
        public var docKindBias: Double
        public var finalScore: Double

        public init(
            documentID: String,
            docKind: String?,
            surfaceType: String,
            counterpartyID: String,
            nodeID: String?,
            publicProfileID: String?,
            offerID: String?,
            bm25Rank: Int?,
            vectorRank: Int?,
            objectLaneRank: Int?,
            bm25Score: Double?,
            vectorScore: Double?,
            objectLaneScore: Double?,
            surfaceBias: Double,
            docKindBias: Double,
            finalScore: Double
        ) {
            self.documentID = documentID
            self.docKind = docKind
            self.surfaceType = surfaceType
            self.counterpartyID = counterpartyID
            self.nodeID = nodeID
            self.publicProfileID = publicProfileID
            self.offerID = offerID
            self.bm25Rank = bm25Rank
            self.vectorRank = vectorRank
            self.objectLaneRank = objectLaneRank
            self.bm25Score = bm25Score
            self.vectorScore = vectorScore
            self.objectLaneScore = objectLaneScore
            self.surfaceBias = surfaceBias
            self.docKindBias = docKindBias
            self.finalScore = finalScore
        }
    }

    public struct QueryContext: Sendable, Hashable, Codable {
        public var rawQuery: String
        public var queryIntentClass: String
        public var surfacePreference: String
        public var domainCategory: String?
        public var objectType: String?
        public var transactionIntent: String?
        public var semanticEmbeddingTextPresent: Bool
        public var queryObjectText: String?

        public init(
            rawQuery: String,
            queryIntentClass: String,
            surfacePreference: String,
            domainCategory: String?,
            objectType: String?,
            transactionIntent: String?,
            semanticEmbeddingTextPresent: Bool,
            queryObjectText: String?
        ) {
            self.rawQuery = rawQuery
            self.queryIntentClass = queryIntentClass
            self.surfacePreference = surfacePreference
            self.domainCategory = domainCategory
            self.objectType = objectType
            self.transactionIntent = transactionIntent
            self.semanticEmbeddingTextPresent = semanticEmbeddingTextPresent
            self.queryObjectText = queryObjectText
        }
    }

    public struct DirectoryRecall: Sendable, Hashable, Codable {
        public var retrievalResponseMode: String
        public var retrievalDocumentsCount: Int
        public var retrievalHitsCount: Int
        public var docKindCounts: [String: Int]
        public var embeddingCountsByDocKind: [String: Int]
        public var candidateOfferIDsFromDocs: [String]

        public init(
            retrievalResponseMode: String,
            retrievalDocumentsCount: Int,
            retrievalHitsCount: Int,
            docKindCounts: [String: Int],
            embeddingCountsByDocKind: [String: Int],
            candidateOfferIDsFromDocs: [String]
        ) {
            self.retrievalResponseMode = retrievalResponseMode
            self.retrievalDocumentsCount = retrievalDocumentsCount
            self.retrievalHitsCount = retrievalHitsCount
            self.docKindCounts = docKindCounts
            self.embeddingCountsByDocKind = embeddingCountsByDocKind
            self.candidateOfferIDsFromDocs = candidateOfferIDsFromDocs
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _rankingCollector: (@Sendable (RankingRow) -> Void)?
    nonisolated(unsafe) private static var _capturedRows: [RankingRow] = []

    /// Optional per-row callback; nil by default (no behavior change).
    public static var rankingCollector: (@Sendable (RankingRow) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _rankingCollector
        }
        set {
            lock.lock()
            _rankingCollector = newValue
            lock.unlock()
        }
    }

    public static func clearCapturedRows() {
        lock.lock()
        _capturedRows = []
        lock.unlock()
    }

    public static func capturedRows() -> [RankingRow] {
        lock.lock()
        defer { lock.unlock() }
        return _capturedRows
    }

    public static func recordRankingRow(_ row: RankingRow) {
        lock.lock()
        _capturedRows.append(row)
        let collector = _rankingCollector
        lock.unlock()
        collector?(row)
    }
}
