import Foundation

#if DEBUG
@inline(__always)
private func exRetrievalStoreLog(_ message: @autoclosure () -> String) {
    print("[ExchangeRetrievalStore] \(message())")
}
#else
@inline(__always)
private func exRetrievalStoreLog(_ message: @autoclosure () -> String) { }
#endif

/// Retrieval-layer store / cache.
///
/// Purpose:
/// - Holds retrieval documents
/// - Maintains BM25 and vector indexes
/// - Provides a single boundary for retrieval engine reads
///
/// This is intentionally in-memory first.
/// SQLite persistence should be wired through a separate persistence adapter,
/// not directly inside this actor.
public actor ExchangeRetrievalStore {
    private var documentsByID: [String: ExchangeRetrievalDocument]
    private var bm25Index: ExchangeBM25Index
    private var vectorIndex: ExchangeVectorIndex

    public init() {
        self.documentsByID = [:]
        self.bm25Index = ExchangeBM25Index()
        self.vectorIndex = ExchangeVectorIndex()
    }

    public var documentCount: Int {
        documentsByID.count
    }

    public var embeddedDocumentCount: Int {
        documentsByID.values.filter(\.hasEmbedding).count
    }

    public var embeddingDimensions: [Int] {
        Array(
            Set(
                documentsByID.values
                    .compactMap { $0.embedding?.count }
                    .filter { $0 > 0 }
            )
        )
        .sorted()
    }

    public func replaceAllDocuments(
        _ documents: [ExchangeRetrievalDocument]
    ) {
        exRetrievalStoreLog(
            "replaceAllDocuments start incoming=\(documents.count) embedded=\(documents.filter(\.hasEmbedding).count) dims=\(embeddingDimensions(from: documents))"
        )

        documentsByID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        rebuildIndexes()

        exRetrievalStoreLog(
            "replaceAllDocuments done stored=\(documentsByID.count) embedded=\(embeddedDocumentCount) dims=\(embeddingDimensions)"
        )
    }

    public func upsertDocuments(
        _ documents: [ExchangeRetrievalDocument]
    ) {
        exRetrievalStoreLog(
            "upsertDocuments start incoming=\(documents.count) embedded=\(documents.filter(\.hasEmbedding).count) dims=\(embeddingDimensions(from: documents)) existing=\(documentsByID.count)"
        )

        guard !documents.isEmpty else {
            exRetrievalStoreLog("upsertDocuments skipped empty")
            return
        }

        for document in documents {
            documentsByID[document.id] = document
        }

        rebuildIndexes()

        exRetrievalStoreLog(
            "upsertDocuments done stored=\(documentsByID.count) embedded=\(embeddedDocumentCount) dims=\(embeddingDimensions)"
        )
    }

    public func removeDocuments(
        ids: [String]
    ) {
        exRetrievalStoreLog("removeDocuments start ids=\(ids.count) existing=\(documentsByID.count)")

        guard !ids.isEmpty else {
            exRetrievalStoreLog("removeDocuments skipped empty")
            return
        }

        for id in ids {
            documentsByID.removeValue(forKey: id)
        }

        rebuildIndexes()

        exRetrievalStoreLog(
            "removeDocuments done stored=\(documentsByID.count) embedded=\(embeddedDocumentCount) dims=\(embeddingDimensions)"
        )
    }

    public func removeDocuments(
        sourceKind: ExchangeRetrievalDocument.SourceKind
    ) {
        exRetrievalStoreLog("removeDocuments(sourceKind) start source=\(sourceKind.rawValue) existing=\(documentsByID.count)")

        documentsByID = documentsByID.filter { $0.value.sourceKind != sourceKind }
        rebuildIndexes()

        exRetrievalStoreLog(
            "removeDocuments(sourceKind) done stored=\(documentsByID.count) embedded=\(embeddedDocumentCount) dims=\(embeddingDimensions)"
        )
    }

    public func clear() {
        exRetrievalStoreLog("clear start existing=\(documentsByID.count)")
        documentsByID.removeAll(keepingCapacity: false)
        bm25Index.rebuild(documents: [])
        vectorIndex.rebuild(documents: [])
        exRetrievalStoreLog("clear done")
    }

    public func listDocuments() -> [ExchangeRetrievalDocument] {
        documentsByID.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public func fetchDocument(
        id: String
    ) -> ExchangeRetrievalDocument? {
        documentsByID[id]
    }

    public func searchBM25(
        query: ExchangeRetrievalQuery,
        limit: Int
    ) -> [ExchangeBM25Index.SearchHit] {
        bm25Index.search(query: query, limit: limit)
    }

    public func searchVector(
        queryEmbedding: [Float],
        limit: Int
    ) -> [ExchangeVectorIndex.SearchHit] {
        exRetrievalStoreLog(
            "searchVector start queryDim=\(queryEmbedding.count) docs=\(documentsByID.count) embedded=\(embeddedDocumentCount) dims=\(embeddingDimensions) limit=\(limit)"
        )

        guard !queryEmbedding.isEmpty else {
            exRetrievalStoreLog("searchVector skipped empty_query_embedding")
            return []
        }

        let hits = vectorIndex.search(embedding: queryEmbedding, limit: limit)

        exRetrievalStoreLog(
            "searchVector done hits=\(hits.count)"
        )

        return hits
    }

    private func rebuildIndexes() {
        let values = Array(documentsByID.values)
        bm25Index.rebuild(documents: values)
        vectorIndex.rebuild(documents: values)

        exRetrievalStoreLog(
            "rebuildIndexes docs=\(values.count) embedded=\(values.filter(\.hasEmbedding).count) dims=\(embeddingDimensions(from: values))"
        )
    }

    private func embeddingDimensions(
        from documents: [ExchangeRetrievalDocument]
    ) -> [Int] {
        Array(
            Set(
                documents
                    .compactMap { $0.embedding?.count }
                    .filter { $0 > 0 }
            )
        )
        .sorted()
    }
}
