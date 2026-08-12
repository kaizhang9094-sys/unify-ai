import Foundation

#if DEBUG
@inline(__always)
private func exRetrievalIngestorLog(_ message: @autoclosure () -> String) {
    print("[ExchangeRetrievalIngestor] \(message())")
}
#else
@inline(__always)
private func exRetrievalIngestorLog(_ message: @autoclosure () -> String) { }
#endif

/// Ingests public surfaces into the retrieval store.
///
/// Flow:
/// 1. build retrieval documents
/// 2. compute embeddings for docs missing them when policy allows
/// 3. upsert into retrieval store
///
/// Important:
/// - This is retrieval infrastructure, not domain truth
/// - It should not mutate ExchangeThread or discovery state
/// - It prepares searchable records for the hybrid retrieval layer
/// - Remote directory matches are not re-embedded by default because the server
///   should already have used pushed document vectors for first-pass matching
public struct ExchangeRetrievalIngestor: Sendable {
    private let builder: ExchangeRetrievalDocumentBuilder
    private let store: ExchangeRetrievalStore
    private let embeddingProvider: any MemoryEmbeddingProvider

    /// Controls whether hydrated remote directory matches should be embedded again
    /// on the client for local vector reranking/cache.
    ///
    /// Default is false to avoid duplicating server-side vector work and reduce
    /// heat/latency on mobile devices.
    private let embedRemoteDirectoryMatches: Bool

    public init(
        builder: ExchangeRetrievalDocumentBuilder = .init(),
        store: ExchangeRetrievalStore,
        embeddingProvider: any MemoryEmbeddingProvider,
        embedRemoteDirectoryMatches: Bool = false
    ) {
        self.builder = builder
        self.store = store
        self.embeddingProvider = embeddingProvider
        self.embedRemoteDirectoryMatches = embedRemoteDirectoryMatches
    }

    public func ingestDirectoryMatches(
        _ matches: [ExchangeDirectoryMatch],
        sourceKind: ExchangeRetrievalDocument.SourceKind = .remote
    ) async {
        exRetrievalIngestorLog(
            "ingestDirectoryMatches start matches=\(matches.count) source=\(sourceKind.rawValue) embedRemote=\(embedRemoteDirectoryMatches)"
        )

        let baseDocuments = builder.buildDocuments(
            matches: matches,
            sourceKind: sourceKind
        )

        let storedDocuments = documentsAfterEmbeddingPolicy(
            baseDocuments,
            sourceKind: sourceKind,
            context: "ingestDirectoryMatches"
        )

        let embeddedCount = storedDocuments.filter(\.hasEmbedding).count
        let dimensions = embeddingDimensions(from: storedDocuments)

        await store.upsertDocuments(storedDocuments)

        exRetrievalIngestorLog(
            "ingestDirectoryMatches done base=\(baseDocuments.count) stored=\(storedDocuments.count) embedded=\(embeddedCount) dims=\(dimensions)"
        )
    }

    public func ingestCounterparties(
        _ counterparties: [ExchangeCounterparty],
        sourceKind: ExchangeRetrievalDocument.SourceKind = .local
    ) async {
        exRetrievalIngestorLog(
            "ingestCounterparties start count=\(counterparties.count) source=\(sourceKind.rawValue)"
        )

        let baseDocuments = builder.buildDocuments(
            counterparties: counterparties,
            sourceKind: sourceKind
        )

        let embeddedDocuments = enrichEmbeddings(baseDocuments)
        let embeddedCount = embeddedDocuments.filter(\.hasEmbedding).count
        let dimensions = embeddingDimensions(from: embeddedDocuments)

        await store.upsertDocuments(embeddedDocuments)

        exRetrievalIngestorLog(
            "ingestCounterparties done base=\(baseDocuments.count) stored=\(embeddedDocuments.count) embedded=\(embeddedCount) dims=\(dimensions)"
        )
    }

    public func ingestProfileAndOffers(
        profile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer],
        counterpartyID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind = .local
    ) async {
        exRetrievalIngestorLog(
            "ingestProfileAndOffers start profileID=\(profile.id) offers=\(offers.count) counterpartyID=\(counterpartyID) source=\(sourceKind.rawValue)"
        )

        let baseDocuments = builder.buildDocuments(
            profile: profile,
            offers: offers,
            counterpartyID: counterpartyID,
            sourceKind: sourceKind
        )

        let embeddedDocuments = enrichEmbeddings(baseDocuments)
        let embeddedCount = embeddedDocuments.filter(\.hasEmbedding).count
        let dimensions = embeddingDimensions(from: embeddedDocuments)

        await store.upsertDocuments(embeddedDocuments)

        exRetrievalIngestorLog(
            "ingestProfileAndOffers done base=\(baseDocuments.count) stored=\(embeddedDocuments.count) embedded=\(embeddedCount) dims=\(dimensions)"
        )
    }

    public func replaceAllDirectoryMatches(
        _ matches: [ExchangeDirectoryMatch],
        sourceKind: ExchangeRetrievalDocument.SourceKind = .remote
    ) async {
        exRetrievalIngestorLog(
            "replaceAllDirectoryMatches start matches=\(matches.count) source=\(sourceKind.rawValue) embedRemote=\(embedRemoteDirectoryMatches)"
        )

        let baseDocuments = builder.buildDocuments(
            matches: matches,
            sourceKind: sourceKind
        )

        let storedDocuments = documentsAfterEmbeddingPolicy(
            baseDocuments,
            sourceKind: sourceKind,
            context: "replaceAllDirectoryMatches"
        )

        let embeddedCount = storedDocuments.filter(\.hasEmbedding).count
        let dimensions = embeddingDimensions(from: storedDocuments)

        await store.replaceAllDocuments(storedDocuments)

        exRetrievalIngestorLog(
            "replaceAllDirectoryMatches done base=\(baseDocuments.count) stored=\(storedDocuments.count) embedded=\(embeddedCount) dims=\(dimensions)"
        )
    }

    private func documentsAfterEmbeddingPolicy(
        _ documents: [ExchangeRetrievalDocument],
        sourceKind: ExchangeRetrievalDocument.SourceKind,
        context: String
    ) -> [ExchangeRetrievalDocument] {
        guard !documents.isEmpty else {
            exRetrievalIngestorLog("\(context) embedding skipped empty_documents")
            return documents
        }

        if sourceKind == .remote && !embedRemoteDirectoryMatches {
            exRetrievalIngestorLog(
                "\(context) remote embedding skipped by policy docs=\(documents.count)"
            )
            return documents
        }

        return enrichEmbeddings(documents)
    }

    private func enrichEmbeddings(
        _ documents: [ExchangeRetrievalDocument]
    ) -> [ExchangeRetrievalDocument] {
        documents.map { document in
            guard !document.hasEmbedding else {
                exRetrievalIngestorLog(
                    "embedding preserved documentID=\(document.id) surface=\(document.surfaceType.rawValue) dim=\(document.embeddingDimension)"
                )
                return document
            }

            let text = bestEmbeddingText(for: document)
            guard !text.isEmpty else {
                exRetrievalIngestorLog(
                    "embedding skipped empty_text documentID=\(document.id) surface=\(document.surfaceType.rawValue)"
                )
                return document
            }

            guard let embedding = embeddingProvider.embed(text), !embedding.isEmpty else {
                exRetrievalIngestorLog(
                    "embedding failed documentID=\(document.id) surface=\(document.surfaceType.rawValue) textChars=\(text.count)"
                )
                return document
            }

            exRetrievalIngestorLog(
                "embedding built documentID=\(document.id) surface=\(document.surfaceType.rawValue) dim=\(embedding.count) textChars=\(text.count)"
            )

            return document.updatingEmbedding(embedding)
        }
    }

    private func bestEmbeddingText(
        for document: ExchangeRetrievalDocument
    ) -> String {
        document.retrievalEmbeddingText
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

    private func normalizeWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
