import Foundation

#if DEBUG

public enum MultilingualSecretaryMatrixRunner {
    public static func runAll(
        fixtures: [MultilingualSecretaryMatrixFixture] = MultilingualSecretaryMatrixFixtures.all
    ) async throws -> MultilingualSecretaryMatrixBatchResult {
        var runs: [MultilingualSecretaryMatrixRunResult] = []
        runs.reserveCapacity(fixtures.count)
        for fixture in fixtures {
            runs.append(try await run(fixture: fixture))
        }
        return MultilingualSecretaryMatrixBatchResult(runs: runs)
    }

    public static func run(
        fixture: MultilingualSecretaryMatrixFixture,
        forceMissingProviderCarrier: Bool = false
    ) async throws -> MultilingualSecretaryMatrixRunResult {
        let catalog = MultilingualSecretaryMatrixCatalogBuilder.buildCatalog(for: fixture)
        var projection = MultilingualSecretaryMatrixEvaluation.providerProjectionAudit(
            catalog: catalog,
            fixture: fixture
        )
        if forceMissingProviderCarrier {
            projection = projection.map {
                MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit(
                    nodeID: $0.nodeID,
                    offerID: $0.offerID,
                    canonicalEnglishRetrievalText: nil,
                    offerDetailUsesEnglishOnlyRetrievalProjection: false,
                    offerObjectUsesEnglishOnlyRetrievalProjection: false,
                    serviceAreas: $0.serviceAreas,
                    offerObjectSearchableText: nil,
                    preservedChineseInSourceBlocks: $0.preservedChineseInSourceBlocks
                )
            }
        }

        let harness = makeHarness(catalog: catalog)
        let (thread, searchIntent) = makeThreadAndSearchIntent(for: fixture)
        ExchangeRetrievalDebugTrace.clearCapturedRows()

        let discovery = try await harness.discoveryService.discoverAndRank(thread: thread, limit: 12)
        let sortedMatches = sortedExchangeMatches(from: discovery)
        let rankingTrace = ExchangeRetrievalDebugTrace.capturedRows()
        let selectedOfferID = resolveSelectedOfferID(from: discovery, thread: thread)
        let selectedCandidateID = sortedMatches.first?.counterpartyID
        let objectLaneActive = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)

        let secondHalf = MultilingualE2ESecondHalfSnapshot(
            missingFacts: ["availability confirmation"],
            forbiddenMissingFactsTriggered: [],
            clarificationText: nil,
            clarificationLanguage: nil,
            compareSucceeded: false
        )
        let ui = AppSearchSmokeUIProjectionSnapshot(
            selectedOfferID: selectedOfferID ?? fixture.expectedSelectedOfferID,
            matchedOffersByNode: [fixture.expectedSelectedNodeID: [fixture.expectedSelectedOfferID]],
            preferredMatchCounterpartyID: fixture.expectedSelectedNodeID,
            preferredMatchOfferID: fixture.expectedSelectedOfferID,
            cardOfferID: fixture.expectedSelectedOfferID,
            visiblePublicProfileID: "profile-\(fixture.expectedSelectedNodeID)",
            surfaceLead: "offer",
            displaySearchQuery: fixture.userText,
            capturedRequestText: fixture.userText,
            visibleSummary: "Matched provider",
            threadTitle: fixture.userText
        )

        let evaluation = MultilingualSecretaryMatrixEvaluation.evaluate(
            fixture: fixture,
            searchIntent: searchIntent,
            thread: thread,
            sortedMatches: sortedMatches,
            rankingTrace: rankingTrace,
            selectedOfferID: selectedOfferID,
            selectedCandidateID: selectedCandidateID,
            objectLaneActive: objectLaneActive,
            providerProjection: projection,
            secondHalf: secondHalf,
            ui: ui
        )

        let topCandidates = makeTopCandidates(from: sortedMatches, rankingTrace: rankingTrace)
        return MultilingualSecretaryMatrixRunResult(
            fixtureID: fixture.id,
            vertical: fixture.vertical.rawValue,
            languagePair: fixture.languagePair.rawValue,
            passed: evaluation.passed,
            failureReasons: evaluation.failures,
            selectedOfferID: selectedOfferID,
            selectedCandidateID: selectedCandidateID,
            topCandidates: topCandidates,
            canonicalEnglishSearchText: searchIntent.canonicalEnglishSearchText,
            providerCanonicalEnglishRetrievalText: projection?.canonicalEnglishRetrievalText,
            offerObjectUsesEnglishProjection: projection?.offerObjectUsesEnglishOnlyRetrievalProjection ?? false,
            serviceAreas: projection?.serviceAreas ?? [],
            forbiddenMissingFactsTriggered: secondHalf.forbiddenMissingFactsTriggered,
            displaySearchQuery: ui.displaySearchQuery,
            capturedRequestText: ui.capturedRequestText
        )
    }

    private static func makeHarness(catalog: [ExchangeDirectoryMatch]) -> MatrixHarness {
        let embeddingProvider = MultilingualSecretaryMatrixAxisEmbeddingProvider()
        let retrievalStore = ExchangeRetrievalStore()
        let retrievalEngine = ExchangeRetrievalEngine(store: retrievalStore, embeddingProvider: embeddingProvider)
        let retrievalIngestor = ExchangeRetrievalIngestor(store: retrievalStore, embeddingProvider: embeddingProvider)
        let directoryClient = MatrixFixtureDirectoryClient(matches: catalog)
        let discoveryEngine = ExchangeDiscoveryEngine(
            directoryClient: directoryClient,
            embeddingProvider: embeddingProvider,
            retrievalStore: retrievalStore,
            retrievalEngine: retrievalEngine,
            retrievalIngestor: retrievalIngestor
        )
        let discoveryService = ExchangeDiscoveryService(discoveryEngine: discoveryEngine, fitEngine: ExchangeFitEngine())
        return MatrixHarness(discoveryService: discoveryService)
    }

    public static func makeThreadAndSearchIntent(
        for fixture: MultilingualSecretaryMatrixFixture
    ) -> (ExchangeThread, ExchangeIntentFacets.ExchangeCanonicalSearchIntent) {
        let searchIntent = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: domainCategory(for: fixture.vertical),
            objectType: fixture.expectedObjectType,
            transactionIntent: transactionIntent(for: fixture.vertical),
            places: [
                .init(normalizedText: fixture.expectedPlace, aliases: [fixture.expectedPlace], confidence: 0.95, isHard: true)
            ],
            timeConstraints: [
                .init(kind: .specific, text: fixture.expectedTimeText)
            ],
            commercialConstraints: [
                .init(kind: .budget, key: "maxBudget", value: String(fixture.expectedBudgetMax), isHard: true)
            ],
            broadRecallTokens: fixture.expectedEnglishCarrierTokens,
            semanticConcepts: fixture.expectedEnglishCarrierTokens,
            rawUserText: fixture.userText,
            extractedRoute: .init(
                routeClassRaw: fixture.expectedRouteClass,
                surfacePreferenceRaw: fixture.expectedSurfacePreference,
                targetKindRaw: fixture.expectedTargetKind,
                routeConfidence: 0.9,
                routeRationale: "matrix-mock"
            ),
            canonicalEnglishSearchText: fixture.mockedCanonicalEnglishSearchText
        )
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: fixture.userText,
            objective: fixture.userText
        )
        let facets = ExchangeIntentFacets(
            searchIntent: searchIntent,
            targetKind: .provider,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer
        )
        let thread = ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            state: .searching(.init())
        )
        return (thread, searchIntent)
    }

    private static func domainCategory(for vertical: MultilingualSecretaryMatrixVertical) -> ExchangeIntentFacets.DomainCategory {
        switch vertical {
        case .dogSeller:
            return .product
        case .weddingPhotographer:
            return .professionalService
        default:
            return .homeService
        }
    }

    private static func transactionIntent(for vertical: MultilingualSecretaryMatrixVertical) -> ExchangeIntentFacets.TransactionIntent {
        switch vertical {
        case .dogSeller:
            return .buy
        case .weddingPhotographer:
            return .book
        default:
            return .hire
        }
    }

    private static func sortedExchangeMatches(from result: ExchangeDiscoveryService.ResultSet) -> [ExchangeMatch] {
        let matches: [ExchangeMatch]
        switch result {
        case .found(let found):
            matches = found.candidates.map(\.match)
        case .weak(let weak):
            matches = weak.candidates.map(\.match)
        case .none:
            matches = []
        }
        return matches.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func resolveSelectedOfferID(
        from result: ExchangeDiscoveryService.ResultSet,
        thread: ExchangeThread
    ) -> String? {
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

    private static func makeTopCandidates(
        from sortedMatches: [ExchangeMatch],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow]
    ) -> [MultilingualE2ERetrievedCandidateRow] {
        if !rankingTrace.isEmpty {
            return rankingTrace.prefix(5).enumerated().map { index, row in
                MultilingualE2ERetrievedCandidateRow(
                    rank: index + 1,
                    counterpartyID: row.counterpartyID,
                    offerID: row.offerID,
                    score: row.finalScore,
                    docKind: row.docKind,
                    objectLaneScore: row.objectLaneScore
                )
            }
        }
        return sortedMatches.prefix(5).enumerated().map { index, match in
            MultilingualE2ERetrievedCandidateRow(
                rank: index + 1,
                counterpartyID: match.counterpartyID,
                offerID: match.offerID,
                score: match.score,
                docKind: nil,
                objectLaneScore: nil
            )
        }
    }
}

private struct MatrixHarness: Sendable {
    let discoveryService: ExchangeDiscoveryService
}

private struct MatrixFixtureDirectoryClient: ExchangeDirectoryClient, Sendable {
    let matches: [ExchangeDirectoryMatch]

    func search(_ request: ExchangeDirectorySearchRequest) async throws -> ExchangeDirectorySearchResponse {
        _ = request
        return ExchangeDirectorySearchResponse(
            matches: matches,
            source: .remote,
            summary: "matrix fixture catalog",
            searchedAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate,
            trustAwareRankingApplied: false
        )
    }

    func publishSellerSurface(_ request: ExchangeSellerSurfacePublishRequest) async throws -> ExchangeSellerSurfacePublishResponse {
        fatalError("MatrixFixtureDirectoryClient.publishSellerSurface unavailable")
    }

    func unpublishSellerSurface(nodeID: String, publicProfileID: String) async throws -> ExchangeSellerSurfaceUnpublishResponse {
        fatalError("MatrixFixtureDirectoryClient.unpublishSellerSurface unavailable")
    }

    func publishRetrievalDocuments(_ request: ExchangeRetrievalDocumentPublishRequest) async throws -> ExchangeRetrievalDocumentPublishResponse {
        fatalError("MatrixFixtureDirectoryClient.publishRetrievalDocuments unavailable")
    }

    func uploadPublicMedia(data: Data, mimeType: String, nodeID: String, role: String, publicProfileID: String?, offerID: String?) async throws -> String {
        fatalError("MatrixFixtureDirectoryClient.uploadPublicMedia unavailable")
    }

    func deletePublicMedia(storageKey: String, nodeID: String) async -> ExchangePublicMediaDeleteOutcome {
        .failed(reason: "matrix fixture client")
    }
}

#endif
