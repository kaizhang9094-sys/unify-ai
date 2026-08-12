import Foundation
@testable import AnumCore

struct FixtureDirectoryClient: ExchangeDirectoryClient, Sendable {
    let matches: [ExchangeDirectoryMatch]

    func search(_ request: ExchangeDirectorySearchRequest) async throws -> ExchangeDirectorySearchResponse {
        _ = request
        return ExchangeDirectorySearchResponse(
            matches: matches,
            source: .remote,
            summary: "fixture catalog coarse recall",
            searchedAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate,
            trustAwareRankingApplied: false
        )
    }

    func publishSellerSurface(_ request: ExchangeSellerSurfacePublishRequest) async throws -> ExchangeSellerSurfacePublishResponse {
        fatalError("FixtureDirectoryClient.publishSellerSurface unavailable")
    }

    func unpublishSellerSurface(nodeID: String, publicProfileID: String) async throws -> ExchangeSellerSurfaceUnpublishResponse {
        fatalError("FixtureDirectoryClient.unpublishSellerSurface unavailable")
    }

    func publishRetrievalDocuments(_ request: ExchangeRetrievalDocumentPublishRequest) async throws -> ExchangeRetrievalDocumentPublishResponse {
        fatalError("FixtureDirectoryClient.publishRetrievalDocuments unavailable")
    }

    func uploadPublicMedia(data: Data, mimeType: String, nodeID: String, role: String, publicProfileID: String?, offerID: String?) async throws -> String {
        fatalError("FixtureDirectoryClient.uploadPublicMedia unavailable")
    }

    func deletePublicMedia(storageKey: String, nodeID: String) async -> ExchangePublicMediaDeleteOutcome {
        .failed(reason: "fixture client")
    }
}

struct ExchangeRetrievalAccuracyHarness: Sendable {
    let discoveryService: ExchangeDiscoveryService
    let catalog: [ExchangeDirectoryMatch]

    static func make() -> ExchangeRetrievalAccuracyHarness {
        let catalog = ExchangeRetrievalAccuracyFixtureBuilder.buildCatalog()
        let embeddingProvider = RetrievalAccuracyAxisEmbeddingProvider()
        let retrievalStore = ExchangeRetrievalStore()
        let retrievalEngine = ExchangeRetrievalEngine(store: retrievalStore, embeddingProvider: embeddingProvider)
        let retrievalIngestor = ExchangeRetrievalIngestor(store: retrievalStore, embeddingProvider: embeddingProvider)
        let directoryClient = FixtureDirectoryClient(matches: catalog)
        let discoveryEngine = ExchangeDiscoveryEngine(
            directoryClient: directoryClient,
            embeddingProvider: embeddingProvider,
            retrievalStore: retrievalStore,
            retrievalEngine: retrievalEngine,
            retrievalIngestor: retrievalIngestor
        )
        let discoveryService = ExchangeDiscoveryService(discoveryEngine: discoveryEngine, fitEngine: ExchangeFitEngine())
        return ExchangeRetrievalAccuracyHarness(discoveryService: discoveryService, catalog: catalog)
    }

    func run(thread: ExchangeThread, expectation: ExchangeRetrievalAccuracyScenarioExpectation) async throws -> ExchangeRetrievalAccuracyScenarioResult {
        ExchangeRetrievalDebugTrace.clearCapturedRows()
        let result = try await discoveryService.discoverAndRank(thread: thread, limit: 12)
        let ranked = rankedCandidates(from: result)
        let selectedOfferID = resolveSelectedOfferID(from: result, thread: thread)
        let objectLaneActive = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
        let queryContext = makeQueryContext(thread: thread)
        let directoryRecall = makeDirectoryRecall()
        let trace = ExchangeRetrievalDebugTrace.capturedRows()
        return ExchangeRetrievalAccuracyReport.evaluate(
            expectation: expectation,
            rankedCandidates: ranked,
            selectedOfferID: selectedOfferID,
            objectLaneActive: objectLaneActive,
            queryContext: queryContext,
            directoryRecall: directoryRecall,
            rankingTrace: trace
        )
    }

    private func rankedCandidates(from result: ExchangeDiscoveryService.ResultSet) -> [ExchangeDiscoveryService.RankedCandidate] {
        switch result {
        case .found(let found): return found.candidates
        case .weak(let weak): return weak.candidates
        case .none: return []
        }
    }

    private func resolveSelectedOfferID(from result: ExchangeDiscoveryService.ResultSet, thread: ExchangeThread) -> String? {
        let match: ExchangeMatch?
        switch result {
        case .found(let found): match = found.bestMatch
        case .weak(let weak): match = weak.bestAvailableMatch ?? weak.bestOverallMatch
        case .none: match = nil
        }
        guard let match else { return nil }
        if ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) {
            return ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: Set(match.provenObjectOfferIDs),
                objectEvidenceScoreByOfferID: match.objectEvidenceScoreByOfferID
            )
        }
        return match.offerID ?? match.matchedOfferIDs.first
    }

    private func makeQueryContext(thread: ExchangeThread) -> ExchangeRetrievalDebugTrace.QueryContext {
        let facets = thread.facets
        let si = facets?.searchIntent
        return ExchangeRetrievalDebugTrace.QueryContext(
            rawQuery: si?.rawUserText ?? thread.intent.title,
            queryIntentClass: (facets?.queryIntentClass ?? thread.intent.queryIntentClass).rawValue,
            surfacePreference: (facets?.surfacePreference ?? .mixed).rawValue,
            domainCategory: si?.domainCategory.rawValue,
            objectType: si?.objectType,
            transactionIntent: si?.transactionIntent?.rawValue,
            semanticEmbeddingTextPresent: !(si?.canonicalEnglishSearchText?.isEmpty ?? true),
            queryObjectText: ExchangeOfferObjectLane.queryObjectText(thread: thread)
        )
    }

    private func makeDirectoryRecall() -> ExchangeRetrievalDebugTrace.DirectoryRecall {
        let docs = catalog.flatMap(\.retrievalDocuments)
        var docKindCounts: [String: Int] = [:]
        var embeddingCounts: [String: Int] = [:]
        for doc in docs {
            let kind = doc.docKind?.rawValue ?? "nil"
            docKindCounts[kind, default: 0] += 1
            if doc.hasEmbedding { embeddingCounts[kind, default: 0] += 1 }
        }
        return ExchangeRetrievalDebugTrace.DirectoryRecall(
            retrievalResponseMode: ExchangeDirectorySearchRequest.RetrievalResponseMode.clientRerank.rawValue,
            retrievalDocumentsCount: docs.count,
            retrievalHitsCount: catalog.reduce(0) { $0 + $1.retrievalHits.count },
            docKindCounts: docKindCounts,
            embeddingCountsByDocKind: embeddingCounts,
            candidateOfferIDsFromDocs: Array(Set(catalog.flatMap(\.candidateOfferIDsFromDocs))).sorted()
        )
    }
}

enum ExchangeRetrievalAccuracyThreadFactory {
    static func makeThread(
        rawUserText: String,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference,
        domainCategory: ExchangeIntentFacets.DomainCategory = .general,
        objectType: String? = nil,
        transactionIntent: ExchangeIntentFacets.TransactionIntent? = nil,
        semanticConcepts: [String] = [],
        broadRecallTokens: [String] = [],
        providerTerms: [String] = [],
        capabilityTerms: [String] = [],
        affinityTerms: [String] = [],
        primaryKeywords: [String] = [],
        timeText: String? = nil,
        commercialConstraints: [ExchangeIntentFacets.StructuredCommercialConstraint] = []
    ) -> ExchangeThread {
        let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: domainCategory,
            objectType: objectType,
            transactionIntent: transactionIntent,
            commercialConstraints: commercialConstraints,
            broadRecallTokens: broadRecallTokens,
            semanticConcepts: semanticConcepts,
            rawUserText: rawUserText,
            canonicalEnglishSearchText: rawUserText
        )
        let facets = ExchangeIntentFacets(
            searchIntent: searchIntent,
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference,
            timeText: timeText,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms,
            primaryKeywords: primaryKeywords.isEmpty ? broadRecallTokens : primaryKeywords
        )
        return ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(kind: .find, mode: .transactional, queryIntentClass: queryIntentClass, title: rawUserText, objective: rawUserText),
            posture: ExchangePosture(),
            facets: facets,
            state: .searching(.init())
        )
    }
}

enum ExchangeRetrievalOnnxSmokeSkip: Error, CustomStringConvertible, Sendable {
    case disabled
    case warmupFailed(reason: String)
    case warmupTimedOut
    case catalogEmbeddingInvalid([String])

    var description: String {
        switch self {
        case .disabled:
            return "ANUM_RETRIEVAL_ONNX_SMOKE not set"
        case .warmupFailed(let reason):
            return "ONNX warmup failed: \(reason)"
        case .warmupTimedOut:
            return "ONNX warmup timed out after 30s"
        case .catalogEmbeddingInvalid(let failures):
            return "ONNX catalog embedding invalid: \(failures.joined(separator: "; "))"
        }
    }
}

enum ExchangeRetrievalOnnxSmokeGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ANUM_RETRIEVAL_ONNX_SMOKE"] == "1"
    }

    static var isExtendedEnabled: Bool {
        ProcessInfo.processInfo.environment["ANUM_RETRIEVAL_ONNX_SMOKE_EXTENDED"] == "1"
    }
}

extension ExchangeRetrievalAccuracyHarness {
    static func makeONNX() async throws -> ExchangeRetrievalAccuracyHarness {
        var config = ONNXSentenceEmbedder.Config()
        config.enableTraceLogs = false
        let embedder = ONNXSentenceEmbedder(config: config)

        let warmupVector = try await warmupONNXEmbedder(embedder)
        guard warmupVector.count == ExchangeRetrievalAccuracyFixtureBuilder.onnxEmbeddingDimension else {
            throw ExchangeRetrievalOnnxSmokeSkip.warmupFailed(
                reason: "expected dim \(ExchangeRetrievalAccuracyFixtureBuilder.onnxEmbeddingDimension) got \(warmupVector.count)"
            )
        }

        let rawCatalog = ExchangeRetrievalAccuracyFixtureBuilder.buildCatalog(includeAxisEmbeddings: false)
        let noEmbeddingFailures = ExchangeRetrievalAccuracyFixtureBuilder.assertCatalogHasNoEmbeddings(rawCatalog)
        if !noEmbeddingFailures.isEmpty {
            throw ExchangeRetrievalOnnxSmokeSkip.catalogEmbeddingInvalid(noEmbeddingFailures)
        }

        let catalog = ExchangeRetrievalAccuracyFixtureBuilder.preEmbedCatalogWithONNX(rawCatalog, embedder: embedder)
        let onnxFailures = ExchangeRetrievalAccuracyFixtureBuilder.assertCatalogONNXEmbeddings(catalog)
        if !onnxFailures.isEmpty {
            throw ExchangeRetrievalOnnxSmokeSkip.catalogEmbeddingInvalid(onnxFailures)
        }

        let retrievalStore = ExchangeRetrievalStore()
        let retrievalEngine = ExchangeRetrievalEngine(store: retrievalStore, embeddingProvider: embedder)
        let retrievalIngestor = ExchangeRetrievalIngestor(store: retrievalStore, embeddingProvider: embedder)
        let directoryClient = FixtureDirectoryClient(matches: catalog)
        let discoveryEngine = ExchangeDiscoveryEngine(
            directoryClient: directoryClient,
            embeddingProvider: embedder,
            retrievalStore: retrievalStore,
            retrievalEngine: retrievalEngine,
            retrievalIngestor: retrievalIngestor
        )
        let discoveryService = ExchangeDiscoveryService(discoveryEngine: discoveryEngine, fitEngine: ExchangeFitEngine())
        return ExchangeRetrievalAccuracyHarness(discoveryService: discoveryService, catalog: catalog)
    }

    private static func warmupONNXEmbedder(_ embedder: ONNXSentenceEmbedder) async throws -> [Float] {
        try await withThrowingTaskGroup(of: Result<[Float], Error>.self) { group in
            group.addTask {
                let vector = await Task.detached(priority: .userInitiated) {
                    embedder.embedQuery("warmup retrieval smoke")
                }.value
                guard let vector, !vector.isEmpty else {
                    return .failure(ExchangeRetrievalOnnxSmokeSkip.warmupFailed(reason: "embedQuery returned nil/empty"))
                }
                return .success(vector)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return .failure(ExchangeRetrievalOnnxSmokeSkip.warmupTimedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw ExchangeRetrievalOnnxSmokeSkip.warmupFailed(reason: "no warmup result")
            }
            switch first {
            case .success(let vector):
                return vector
            case .failure(let error):
                throw error
            }
        }
    }
}
