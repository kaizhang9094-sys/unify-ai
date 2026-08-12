import Foundation
@testable import AnumCore

struct ExchangeRetrievalLocalFederationHarness: Sendable {
    let discoveryService: ExchangeDiscoveryService
    let baseURL: URL
    let manifest: ExchangeRetrievalAccuracyFederationCatalogExport.GenerationManifest
    let expectedNodeIDs: Set<String>
    let expectedDocIDs: Set<String>

    static func make() async throws -> ExchangeRetrievalLocalFederationHarness {
        let baseURL = try ExchangeRetrievalLocalFederationSmokeGate.requireConfiguration()
        try await preflightHealth(baseURL: baseURL)

        let manifestURL = URL(fileURLWithPath: ExchangeRetrievalLocalFederationSmokeGate.generationManifestPath)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw LocalFederationSmokeSkip.manifestMissing(manifestURL.path)
        }
        let manifest = try ExchangeRetrievalAccuracyFederationCatalogExport.loadManifest(from: manifestURL)

        var config = ONNXSentenceEmbedder.Config()
        config.enableTraceLogs = false
        let embedder = ONNXSentenceEmbedder(config: config)
        let warmupVector = try await warmupONNXEmbedder(embedder)
        guard warmupVector.count == ExchangeRetrievalAccuracyFixtureBuilder.onnxEmbeddingDimension else {
            throw LocalFederationSmokeSkip.harnessSetup(
                "ONNX dim mismatch expected \(ExchangeRetrievalAccuracyFixtureBuilder.onnxEmbeddingDimension) got \(warmupVector.count)"
            )
        }

        let retrievalStore = ExchangeRetrievalStore()
        let retrievalEngine = ExchangeRetrievalEngine(store: retrievalStore, embeddingProvider: embedder)
        let retrievalIngestor = ExchangeRetrievalIngestor(
            store: retrievalStore,
            embeddingProvider: embedder,
            embedRemoteDirectoryMatches: false
        )
        let directoryClient = ExchangeHTTPDirectoryClient(baseURL: baseURL)
        let discoveryEngine = ExchangeDiscoveryEngine(
            directoryClient: directoryClient,
            embeddingProvider: embedder,
            retrievalStore: retrievalStore,
            retrievalEngine: retrievalEngine,
            retrievalIngestor: retrievalIngestor
        )
        let discoveryService = ExchangeDiscoveryService(
            discoveryEngine: discoveryEngine,
            fitEngine: ExchangeFitEngine()
        )

        return ExchangeRetrievalLocalFederationHarness(
            discoveryService: discoveryService,
            baseURL: baseURL,
            manifest: manifest,
            expectedNodeIDs: Set(manifest.expectedNodeIDs),
            expectedDocIDs: Set(manifest.expectedDocIDs)
        )
    }

    func run(
        batchEntry: LocalFederationSmokeBatchEntry,
        thread: ExchangeThread,
        expectation: ExchangeRetrievalAccuracyScenarioExpectation
    ) async throws -> LocalFederationSmokeRunResult {
        ExchangeRetrievalDebugTrace.clearCapturedRows()
        ExchangeHTTPDirectorySearchCapture.record(
            retrievalResponseMode: nil,
            matchCount: 0,
            matches: []
        )

        let started = CFAbsoluteTimeGetCurrent()
        let result = try await discoveryService.discoverAndRank(thread: thread, limit: 12)
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)

        let ranked = rankedCandidates(from: result)
        let selectedOfferID = resolveSelectedOfferID(from: result, thread: thread)
        let objectLaneActive = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
        let queryContext = makeQueryContext(thread: thread)
        let serverMatches = ExchangeHTTPDirectorySearchCapture.lastMatches
        let observedMode = ExchangeHTTPDirectorySearchCapture.lastRetrievalResponseMode
            ?? ExchangeDirectorySearchRequest.RetrievalResponseMode.clientRerank.rawValue

        let serverRoundTrip = ExchangeRetrievalLocalFederationSmokeReport.auditServerRoundTrip(
            matches: serverMatches,
            expectedNodeIDs: expectedNodeIDs,
            expectedDocIDs: expectedDocIDs,
            observedResponseMode: observedMode
        )

        let directoryRecall = ExchangeRetrievalDebugTrace.DirectoryRecall(
            retrievalResponseMode: observedMode,
            retrievalDocumentsCount: serverRoundTrip.serverRetrievalDocumentsCount,
            retrievalHitsCount: serverRoundTrip.serverRetrievalHitsCount,
            docKindCounts: serverRoundTrip.docKindCounts,
            embeddingCountsByDocKind: serverRoundTrip.embeddingCountsByDocKind,
            candidateOfferIDsFromDocs: serverRoundTrip.candidateOfferIDsFromDocs
        )

        let trace = ExchangeRetrievalDebugTrace.capturedRows()
        let accuracyResult = ExchangeRetrievalAccuracyReport.evaluate(
            expectation: expectation,
            rankedCandidates: ranked,
            selectedOfferID: selectedOfferID,
            objectLaneActive: objectLaneActive,
            queryContext: queryContext,
            directoryRecall: directoryRecall,
            rankingTrace: trace
        )

        let strictFailures = ExchangeRetrievalLocalFederationSmokeReport.strictFailures(
            expectation: expectation,
            accuracyResult: accuracyResult,
            rankingTrace: trace,
            serverRoundTrip: serverRoundTrip
        )
        let observationalAssessment = ExchangeRetrievalAccuracyReport.observationalAssessment(
            expectation: expectation,
            result: accuracyResult,
            rankingTrace: trace,
            serverRoundTripIssues: serverRoundTrip.issues
        )
        let observational = ExchangeRetrievalAccuracyReport.observationalIssues(
            expectation: expectation,
            result: accuracyResult,
            rankingTrace: trace,
            serverRoundTripIssues: serverRoundTrip.issues
        )

        return LocalFederationSmokeRunResult(
            batchID: batchEntry.batchID,
            runID: batchEntry.runID,
            scenarioID: batchEntry.scenarioID,
            repeatIndex: batchEntry.repeatIndex,
            strictPassed: strictFailures.isEmpty,
            strictFailures: strictFailures,
            serverRoundTrip: serverRoundTrip,
            accuracyResult: accuracyResult,
            latencyMs: latencyMs,
            observationalIssues: observational,
            observationalAssessment: observationalAssessment
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

    private static func preflightHealth(baseURL: URL) async throws {
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw LocalFederationSmokeSkip.serverUnreachable("GET /health failed")
            }
        } catch let skip as LocalFederationSmokeSkip {
            throw skip
        } catch {
            throw LocalFederationSmokeSkip.serverUnreachable(error.localizedDescription)
        }
    }

    private static func warmupONNXEmbedder(_ embedder: ONNXSentenceEmbedder) async throws -> [Float] {
        try await withThrowingTaskGroup(of: Result<[Float], Error>.self) { group in
            group.addTask {
                let vector = await Task.detached(priority: .userInitiated) {
                    embedder.embedQuery("warmup local federation smoke")
                }.value
                guard let vector, !vector.isEmpty else {
                    return .failure(LocalFederationSmokeSkip.harnessSetup("ONNX warmup returned nil/empty"))
                }
                return .success(vector)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return .failure(LocalFederationSmokeSkip.harnessSetup("ONNX warmup timed out"))
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw LocalFederationSmokeSkip.harnessSetup("ONNX warmup produced no result")
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
