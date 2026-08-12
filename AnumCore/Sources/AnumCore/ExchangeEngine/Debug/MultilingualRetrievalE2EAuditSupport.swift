import Foundation

#if DEBUG

public enum MultilingualRetrievalE2EAuditSupport {
    public enum SeedMode: Sendable {
        case localAxisEmbeddings
        case onDeviceONNX
    }

    public struct LiveEnricherDependencies: Sendable {
        public var indexedSurfaceEnricher: any ExchangeIndexedProviderSurfaceEnricher
        public var diagnosticsStore: ProviderSurfaceEnrichmentDiagnosticsStore?

        public init(
            indexedSurfaceEnricher: any ExchangeIndexedProviderSurfaceEnricher,
            diagnosticsStore: ProviderSurfaceEnrichmentDiagnosticsStore? = nil
        ) {
            self.indexedSurfaceEnricher = indexedSurfaceEnricher
            self.diagnosticsStore = diagnosticsStore
        }
    }

    public typealias UIProjectionCapture = @Sendable @MainActor (
        ExchangeModels.ThreadDetail
    ) -> AppSearchSmokeUIProjectionSnapshot

    public typealias IntelligenceProviderFactory = @Sendable () -> (any ExchangeIntelligenceProvider)?

    public typealias LiveEnricherDependenciesFactory = @Sendable () -> LiveEnricherDependencies?

    public typealias FullFacadePublishDependenciesFactory = @Sendable () -> MultilingualRetrievalE2EFullFacadePublishSeeder.Dependencies?

    private static let providerEnglishTokens = ["roofer", "roof", "aurora", "estimate", "newmarket"]

    public static func defaultArtifactURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("multilingual_e2e_audit.jsonl", isDirectory: false)
    }

    public static func defaultPairComparisonArtifactURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("multilingual_e2e_pair_comparison.json", isDirectory: false)
    }

    public static func defaultTripleComparisonArtifactURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("multilingual_e2e_triple_comparison.json", isDirectory: false)
    }

    /// Preflights federation reachability for multilingual runs. Skips legacy retrieval-smoke manifest
    /// unless a selected run mode explicitly depends on remote manifest fixtures.
    public static func preflightFederation(
        baseURL: URL,
        runModes: [MultilingualRetrievalE2EMode]
    ) async throws {
        let manifestModes = runModes.filter(\.requiresLegacyRetrievalSmokeManifest)
        if manifestModes.isEmpty {
            try await ExchangeRetrievalE2EGate.preflight(
                baseURL: baseURL,
                options: .multilingualLocalSeeded(
                    reason: manifestSkipReason(for: runModes)
                )
            )
            return
        }

        try await ExchangeRetrievalE2EGate.preflight(baseURL: baseURL)
    }

    public static func preflightFederationForTripleComparison(baseURL: URL) async throws {
        try await preflightFederation(
            baseURL: baseURL,
            runModes: [.injectedCarrierFixture, .livePublishEnricher, .fullFacadePublishPath]
        )
    }

    public static func preflightFederationForPairComparison(baseURL: URL) async throws {
        try await preflightFederation(
            baseURL: baseURL,
            runModes: [.injectedCarrierFixture, .livePublishEnricher]
        )
    }

    private static func manifestSkipReason(for runModes: [MultilingualRetrievalE2EMode]) -> String {
        let labels = runModes.map(\.rawValue).sorted().joined(separator: ",")
        return "local_debug_seeded_modes(\(labels))"
    }

    public static func run(
        facade: ExchangeFacade,
        baseURL: URL?,
        runMode: MultilingualRetrievalE2EMode = .injectedCarrierFixture,
        executionMode: ExchangeE2EMode = .discoveryOnly,
        scenarios: [ExchangeMultilingualRetrievalE2EScenario] = ExchangeMultilingualRetrievalE2EScenarios.mandatory,
        seedMode: SeedMode = .onDeviceONNX,
        liveEnricherDependencies: LiveEnricherDependenciesFactory = { nil },
        fullFacadeDependencies: FullFacadePublishDependenciesFactory = { nil },
        intelligenceProvider: IntelligenceProviderFactory = { nil },
        captureUIProjection: UIProjectionCapture
    ) async throws -> MultilingualE2EBatchResult {
        try await ExchangeE2EActiveRun.withMode(executionMode) {
            defer { ExchangeDebugMultilingualFixtureRegistry.clear() }

            let seedResult = try await seedFixtures(
                runMode: runMode,
                seedMode: seedMode,
                facade: facade,
                liveEnricherDependencies: liveEnricherDependencies,
                fullFacadeDependencies: fullFacadeDependencies
            )
            ExchangeDebugMultilingualFixtureRegistry.setMatches(seedResult.matches)

            var runs: [MultilingualE2ERunSnapshot] = []
            runs.reserveCapacity(scenarios.count)

            for scenario in scenarios {
                let run = try await runOne(
                    facade: facade,
                    scenario: scenario,
                    runMode: runMode,
                    executionMode: executionMode,
                    seedResult: seedResult,
                    intelligenceProvider: intelligenceProvider,
                    captureUIProjection: captureUIProjection
                )
                MultilingualRetrievalE2EReport.printRun(run)
                runs.append(run)
            }

            let artifactURL = defaultArtifactURL()
            try? MultilingualRetrievalE2EReport.writeJSONL(runs: runs, to: artifactURL)
            let aggregateText = MultilingualRetrievalE2EReport.printAggregate(
                runs: runs,
                artifactPath: artifactURL.path
            )

            if let baseURL {
                print("[MultilingualE2E] federationBaseURL=\(baseURL.absoluteString) runMode=\(runMode.rawValue) executionMode=\(executionMode.rawValue)")
            }

            return MultilingualE2EBatchResult(
                runs: runs,
                aggregateReportText: aggregateText,
                artifactPath: artifactURL.path
            )
        }
    }

    public static func runPair(
        facade: ExchangeFacade,
        baseURL: URL?,
        scenarios: [ExchangeMultilingualRetrievalE2EScenario] = ExchangeMultilingualRetrievalE2EScenarios.mandatory,
        executionMode: ExchangeE2EMode = .discoveryOnly,
        seedMode: SeedMode = .onDeviceONNX,
        liveEnricherDependencies: LiveEnricherDependenciesFactory,
        fullFacadeDependencies: FullFacadePublishDependenciesFactory = { nil },
        intelligenceProvider: IntelligenceProviderFactory = { nil },
        captureUIProjection: UIProjectionCapture
    ) async throws -> MultilingualE2EPairBatchResult {
        let baseline = try await run(
            facade: facade,
            baseURL: baseURL,
            runMode: .injectedCarrierFixture,
            executionMode: executionMode,
            scenarios: scenarios,
            seedMode: seedMode,
            liveEnricherDependencies: liveEnricherDependencies,
            fullFacadeDependencies: fullFacadeDependencies,
            intelligenceProvider: intelligenceProvider,
            captureUIProjection: captureUIProjection
        )
        let live = try await run(
            facade: facade,
            baseURL: baseURL,
            runMode: .livePublishEnricher,
            executionMode: executionMode,
            scenarios: scenarios,
            seedMode: seedMode,
            liveEnricherDependencies: liveEnricherDependencies,
            fullFacadeDependencies: fullFacadeDependencies,
            intelligenceProvider: intelligenceProvider,
            captureUIProjection: captureUIProjection
        )

        guard let baselineRun = baseline.runs.first, let liveRun = live.runs.first else {
            throw MultilingualRetrievalE2EAuditError.missingPairRuns
        }

        let comparison = MultilingualRetrievalE2EPairComparisonBuilder.compare(
            baseline: baselineRun,
            live: liveRun
        )
        let comparisonURL = defaultPairComparisonArtifactURL()
        try? writePairComparison(comparison, to: comparisonURL)
        _ = MultilingualRetrievalE2EPairComparisonBuilder.printComparison(comparison)

        let mergedRuns = baseline.runs + live.runs
        try? MultilingualRetrievalE2EReport.writeJSONL(runs: mergedRuns, to: defaultArtifactURL())

        return MultilingualE2EPairBatchResult(
            baseline: baseline,
            live: live,
            comparison: comparison,
            comparisonArtifactPath: comparisonURL.path
        )
    }

    public static func runTriple(
        facade: ExchangeFacade,
        baseURL: URL?,
        scenarios: [ExchangeMultilingualRetrievalE2EScenario] = ExchangeMultilingualRetrievalE2EScenarios.mandatory,
        executionMode: ExchangeE2EMode = .discoveryOnly,
        seedMode: SeedMode = .onDeviceONNX,
        liveEnricherDependencies: LiveEnricherDependenciesFactory,
        fullFacadeDependencies: FullFacadePublishDependenciesFactory,
        intelligenceProvider: IntelligenceProviderFactory = { nil },
        captureUIProjection: UIProjectionCapture
    ) async throws -> MultilingualE2ETripleBatchResult {
        let baseline = try await run(
            facade: facade,
            baseURL: baseURL,
            runMode: .injectedCarrierFixture,
            executionMode: executionMode,
            scenarios: scenarios,
            seedMode: seedMode,
            liveEnricherDependencies: liveEnricherDependencies,
            fullFacadeDependencies: fullFacadeDependencies,
            intelligenceProvider: intelligenceProvider,
            captureUIProjection: captureUIProjection
        )
        let live = try await run(
            facade: facade,
            baseURL: baseURL,
            runMode: .livePublishEnricher,
            executionMode: executionMode,
            scenarios: scenarios,
            seedMode: seedMode,
            liveEnricherDependencies: liveEnricherDependencies,
            fullFacadeDependencies: fullFacadeDependencies,
            intelligenceProvider: intelligenceProvider,
            captureUIProjection: captureUIProjection
        )
        let fullFacade = try await run(
            facade: facade,
            baseURL: baseURL,
            runMode: .fullFacadePublishPath,
            executionMode: executionMode,
            scenarios: scenarios,
            seedMode: seedMode,
            liveEnricherDependencies: liveEnricherDependencies,
            fullFacadeDependencies: fullFacadeDependencies,
            intelligenceProvider: intelligenceProvider,
            captureUIProjection: captureUIProjection
        )

        guard let baselineRun = baseline.runs.first,
              let liveRun = live.runs.first,
              let fullFacadeRun = fullFacade.runs.first else {
            throw MultilingualRetrievalE2EAuditError.missingTripleRuns
        }

        let comparison = MultilingualRetrievalE2ETripleComparisonBuilder.compare(
            baseline: baselineRun,
            live: liveRun,
            fullFacade: fullFacadeRun
        )
        let comparisonURL = defaultTripleComparisonArtifactURL()
        try? writeTripleComparison(comparison, to: comparisonURL)
        _ = MultilingualRetrievalE2ETripleComparisonBuilder.printComparison(comparison)

        let mergedRuns = baseline.runs + live.runs + fullFacade.runs
        try? MultilingualRetrievalE2EReport.writeJSONL(runs: mergedRuns, to: defaultArtifactURL())

        return MultilingualE2ETripleBatchResult(
            baseline: baseline,
            live: live,
            fullFacade: fullFacade,
            comparison: comparison,
            comparisonArtifactPath: comparisonURL.path
        )
    }

    internal static func evaluateForTests(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        runMode: MultilingualRetrievalE2EMode,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        thread: ExchangeThread,
        sortedMatches: [ExchangeMatch],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        selectedOfferID: String?,
        selectedCandidateID: String?,
        objectLaneActive: Bool,
        providerProjection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        secondHalf: MultilingualE2ESecondHalfSnapshot,
        ui: AppSearchSmokeUIProjectionSnapshot
    ) -> (passed: Bool, failures: [String], warnings: [String]) {
        let result = MultilingualRetrievalE2EEvaluation.evaluate(
            .init(
                scenario: scenario,
                runMode: runMode,
                searchIntent: searchIntent,
                thread: thread,
                sortedMatches: sortedMatches,
                rankingTrace: rankingTrace,
                selectedOfferID: selectedOfferID,
                selectedCandidateID: selectedCandidateID,
                objectLaneActive: objectLaneActive,
                providerProjection: providerProjection,
                providerIndexing: providerIndexing,
                secondHalf: secondHalf,
                ui: ui
            )
        )
        return (result.passed, result.failures, result.warnings)
    }

    public static func seedFixtures(
        for fixture: MultilingualSecretaryMatrixFixture,
        runMode: MultilingualRetrievalE2EMode,
        seedMode: SeedMode,
        facade: ExchangeFacade? = nil,
        liveEnricherDependencies: LiveEnricherDependenciesFactory = { nil },
        fullFacadeDependencies: FullFacadePublishDependenciesFactory = { nil }
    ) async throws -> MultilingualRetrievalE2ESeedResult {
        switch runMode {
        case .injectedCarrierFixture:
            return try await seedInjectedFixtures(for: fixture, seedMode: seedMode)
        case .livePublishEnricher:
            guard let deps = liveEnricherDependencies() else {
                throw MultilingualRetrievalE2EAuditError.liveEnricherDependenciesMissing
            }
            return try await MultilingualRetrievalE2ELiveEnricherSeeder.seedCatalog(
                for: fixture,
                seedMode: seedMode,
                indexedSurfaceEnricher: deps.indexedSurfaceEnricher,
                diagnosticsStore: deps.diagnosticsStore
            )
        case .fullFacadePublishPath:
            guard let facade else {
                throw MultilingualRetrievalE2EAuditError.fullFacadeFacadeMissing
            }
            guard let deps = fullFacadeDependencies() else {
                throw MultilingualRetrievalE2EAuditError.fullFacadeDependenciesMissing
            }
            return try await MultilingualRetrievalE2EFullFacadePublishSeeder.seedCatalog(
                for: fixture,
                facade: facade,
                dependencies: deps,
                seedMode: seedMode
            )
        }
    }

    public static func runLiveCapture(
        facade: ExchangeFacade,
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        seedResult: MultilingualRetrievalE2ESeedResult,
        executionMode: ExchangeE2EMode = .discoveryOnly,
        intelligenceProvider: IntelligenceProviderFactory,
        captureUIProjection: UIProjectionCapture
    ) async throws -> MultilingualRetrievalE2ELiveRunContext {
        _ = seedResult
        await SearchIntentExtractionDebugTrace.shared.reset()
        ExchangeRetrievalDebugTrace.clearCapturedRows()
        ExchangeHTTPDirectorySearchCapture.record(
            retrievalResponseMode: nil,
            matchCount: 0,
            matches: []
        )

        let totalStarted = CFAbsoluteTimeGetCurrent()
        let intentStarted = CFAbsoluteTimeGetCurrent()
        let response = try await facade.submit(scenario.rawUserText, threadID: nil, progressContext: nil)
        let intentMs = Int((CFAbsoluteTimeGetCurrent() - intentStarted) * 1000)

        let detail = try await facade.getThread(threadID: response.thread.id)
        let ui = await captureUIProjection(detail)
        let thread = response.thread
        let searchIntent = thread.facets?.searchIntent
        let rankingTrace = ExchangeRetrievalDebugTrace.capturedRows()

        let sortedMatches = response.matches.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }

        let objectLaneActive = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
        let selectedResolution = ExchangeCanonicalSelectionResolution.resolve(
            anchors: ExchangeCanonicalSelectionResolution.anchors(from: response),
            thread: thread,
            matches: sortedMatches,
            location: "MultilingualLiveSubset"
        )
        let selectedOfferID = selectedResolution.selectedOfferID
        let selectedCandidateID = sortedMatches.first?.counterpartyID

        let secondHalfStarted = CFAbsoluteTimeGetCurrent()
        let secondHalf = await captureSecondHalfIfNeeded(
            executionMode: executionMode,
            detail: detail,
            sortedMatches: sortedMatches,
            intelligenceProvider: intelligenceProvider(),
            rawUserText: scenario.rawUserText,
            forbiddenCategories: scenario.forbiddenMissingFactCategories
        )
        let secondHalfMs = Int((CFAbsoluteTimeGetCurrent() - secondHalfStarted) * 1000)
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStarted) * 1000)
        let indexingMs = 0

        return MultilingualRetrievalE2ELiveRunContext(
            thread: thread,
            searchIntent: searchIntent,
            sortedMatches: sortedMatches,
            rankingTrace: rankingTrace,
            selectedOfferID: selectedOfferID,
            selectedCandidateID: selectedCandidateID,
            objectLaneActive: objectLaneActive,
            secondHalf: secondHalf,
            ui: ui,
            timings: .init(
                intentMs: intentMs,
                indexingMs: indexingMs,
                retrievalMs: max(totalMs - intentMs - secondHalfMs - indexingMs, 0),
                secondHalfMs: secondHalfMs,
                totalMs: totalMs
            )
        )
    }

    public static func seedFixtures(
        runMode: MultilingualRetrievalE2EMode,
        seedMode: SeedMode,
        facade: ExchangeFacade? = nil,
        liveEnricherDependencies: LiveEnricherDependenciesFactory = { nil },
        fullFacadeDependencies: FullFacadePublishDependenciesFactory = { nil }
    ) async throws -> MultilingualRetrievalE2ESeedResult {
        switch runMode {
        case .injectedCarrierFixture:
            return try await seedInjectedFixtures(seedMode: seedMode)
        case .livePublishEnricher:
            guard let deps = liveEnricherDependencies() else {
                throw MultilingualRetrievalE2EAuditError.liveEnricherDependenciesMissing
            }
            return try await MultilingualRetrievalE2ELiveEnricherSeeder.seedCatalog(
                seedMode: seedMode,
                indexedSurfaceEnricher: deps.indexedSurfaceEnricher,
                diagnosticsStore: deps.diagnosticsStore,
                expectedEnglishTokens: providerEnglishTokens
            )
        case .fullFacadePublishPath:
            guard let facade else {
                throw MultilingualRetrievalE2EAuditError.fullFacadeFacadeMissing
            }
            guard let deps = fullFacadeDependencies() else {
                throw MultilingualRetrievalE2EAuditError.fullFacadeDependenciesMissing
            }
            return try await MultilingualRetrievalE2EFullFacadePublishSeeder.seedCatalog(
                facade: facade,
                dependencies: deps,
                seedMode: seedMode,
                expectedEnglishTokens: providerEnglishTokens
            )
        }
    }

    private static func seedInjectedFixtures(for fixture: MultilingualSecretaryMatrixFixture, seedMode: SeedMode) async throws -> MultilingualRetrievalE2ESeedResult {
        let indexingStarted = CFAbsoluteTimeGetCurrent()
        var catalog = MultilingualSecretaryMatrixCatalogBuilder.buildCatalog(for: fixture)

        if seedMode == .onDeviceONNX {
            var config = ONNXSentenceEmbedder.Config()
            config.enableTraceLogs = false
            let embedder = ONNXSentenceEmbedder(config: config)
            _ = embedder.embedPassage("multilingual live subset injected warmup")
            catalog = ExchangeRetrievalAccuracyFixtureBuilder.preEmbedCatalogWithONNX(catalog, embedder: embedder)
        }

        let indexingMs = Int((CFAbsoluteTimeGetCurrent() - indexingStarted) * 1000)
        let projection = MultilingualSecretaryMatrixEvaluation.providerProjectionAudit(catalog: catalog, fixture: fixture)
        let buildTimings = MultilingualRetrievalE2EProviderBuildTimings(
            indexedSurfaceMs: 0,
            enricherMs: 0,
            retrievalDocsMs: 0,
            embedMs: indexingMs,
            totalMs: indexingMs
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingAudit.injectedBaselineSnapshot(
            projection: projection,
            buildTimings: buildTimings,
            expectedEnglishTokens: fixture.expectedEnglishCarrierTokens
        )
        print("[MultilingualLiveSubset] injectedCarrier seeded fixture=\(fixture.id) count=\(catalog.count) indexingMs=\(indexingMs)")
        return MultilingualRetrievalE2ESeedResult(
            matches: catalog,
            providerProjection: projection,
            providerIndexing: indexing
        )
    }

    private static func seedInjectedFixtures(seedMode: SeedMode) async throws -> MultilingualRetrievalE2ESeedResult {
        let indexingStarted = CFAbsoluteTimeGetCurrent()
        var catalog = MultilingualRetrievalE2EFixtureBuilder.buildCatalog(
            includeAxisEmbeddings: seedMode == .localAxisEmbeddings
        )

        if seedMode == .onDeviceONNX {
            var config = ONNXSentenceEmbedder.Config()
            config.enableTraceLogs = false
            let embedder = ONNXSentenceEmbedder(config: config)
            _ = embedder.embedPassage("multilingual retrieval e2e warmup")
            catalog = ExchangeRetrievalAccuracyFixtureBuilder.preEmbedCatalogWithONNX(catalog, embedder: embedder)
        }

        let indexingMs = Int((CFAbsoluteTimeGetCurrent() - indexingStarted) * 1000)
        let projection = MultilingualRetrievalE2EFixtureBuilder.providerProjectionAudit(from: catalog)
        let buildTimings = MultilingualRetrievalE2EProviderBuildTimings(
            indexedSurfaceMs: 0,
            enricherMs: 0,
            retrievalDocsMs: 0,
            embedMs: indexingMs,
            totalMs: indexingMs
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingAudit.injectedBaselineSnapshot(
            projection: projection,
            buildTimings: buildTimings,
            expectedEnglishTokens: providerEnglishTokens
        )
        print("[MultilingualE2E] injectedCarrier seeded fixtures count=\(catalog.count) indexingMs=\(indexingMs)")
        return MultilingualRetrievalE2ESeedResult(
            matches: catalog,
            providerProjection: projection,
            providerIndexing: indexing
        )
    }

    private static func runOne(
        facade: ExchangeFacade,
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        runMode: MultilingualRetrievalE2EMode,
        executionMode: ExchangeE2EMode,
        seedResult: MultilingualRetrievalE2ESeedResult,
        intelligenceProvider: IntelligenceProviderFactory,
        captureUIProjection: UIProjectionCapture
    ) async throws -> MultilingualE2ERunSnapshot {
        await SearchIntentExtractionDebugTrace.shared.reset()
        ExchangeRetrievalDebugTrace.clearCapturedRows()
        ExchangeHTTPDirectorySearchCapture.record(
            retrievalResponseMode: nil,
            matchCount: 0,
            matches: []
        )

        let totalStarted = CFAbsoluteTimeGetCurrent()
        let intentStarted = CFAbsoluteTimeGetCurrent()
        let response = try await facade.submit(scenario.rawUserText, threadID: nil, progressContext: nil)
        let intentMs = Int((CFAbsoluteTimeGetCurrent() - intentStarted) * 1000)

        let detail = try await facade.getThread(threadID: response.thread.id)
        let ui = await captureUIProjection(detail)
        let thread = response.thread
        let searchIntent = thread.facets?.searchIntent
        let rankingTrace = ExchangeRetrievalDebugTrace.capturedRows()

        let sortedMatches = response.matches.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }

        let objectLaneActive = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
        let selectedResolution = ExchangeCanonicalSelectionResolution.resolve(
            anchors: ExchangeCanonicalSelectionResolution.anchors(from: response),
            thread: thread,
            matches: sortedMatches,
            location: "MultilingualE2E"
        )
        let selectedOfferID = selectedResolution.selectedOfferID
        let selectedCandidateID = sortedMatches.first?.counterpartyID

        let secondHalfStarted = CFAbsoluteTimeGetCurrent()
        let secondHalf = await captureSecondHalfIfNeeded(
            executionMode: executionMode,
            detail: detail,
            sortedMatches: sortedMatches,
            intelligenceProvider: intelligenceProvider(),
            rawUserText: scenario.rawUserText,
            forbiddenCategories: scenario.forbiddenMissingFactCategories
        )
        let secondHalfMs = Int((CFAbsoluteTimeGetCurrent() - secondHalfStarted) * 1000)
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStarted) * 1000)

        let providerProjection = seedResult.providerProjection
        let providerIndexing = seedResult.providerIndexing
        let evaluation = MultilingualRetrievalE2EEvaluation.evaluate(
            .init(
                scenario: scenario,
                runMode: runMode,
                searchIntent: searchIntent,
                thread: thread,
                sortedMatches: sortedMatches,
                rankingTrace: rankingTrace,
                selectedOfferID: selectedOfferID,
                selectedCandidateID: selectedCandidateID,
                objectLaneActive: objectLaneActive,
                providerProjection: providerProjection,
                providerIndexing: providerIndexing,
                secondHalf: secondHalf,
                ui: ui
            )
        )

        let placeTexts = searchIntent?.places.map(\.normalizedText) ?? []
        let timeTexts = searchIntent?.timeConstraints.map(\.text) ?? []
        let budgetMax = searchIntent.flatMap { MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: $0) }
        let indexingMs = providerIndexing.providerBuildTimings?.totalMs ?? 0
        let resultOutcome = MultilingualE2EResultTierResolver.resolve(
            runMode: runMode,
            passed: evaluation.passed,
            publication: providerIndexing.fullFacadePublication
        )

        return MultilingualE2ERunSnapshot(
            scenarioID: scenario.id,
            runMode: runMode.rawValue,
            rawUserText: scenario.rawUserText,
            detectedRequestLanguage: MultilingualRetrievalE2EEvaluation.detectedRequestLanguage(for: scenario.rawUserText),
            canonicalEnglishSearchText: searchIntent?.canonicalEnglishSearchText,
            objectType: searchIntent?.objectType,
            routeClass: thread.facets?.queryIntentClass.rawValue ?? thread.intent.queryIntentClass.rawValue,
            targetKind: thread.facets?.targetKind.rawValue,
            surfacePreference: thread.facets?.surfacePreference.rawValue ?? thread.intent.surfacePreference.rawValue,
            placeTexts: placeTexts,
            budgetMax: budgetMax,
            timeTexts: timeTexts,
            providerIndexing: providerIndexing,
            providerCanonicalEnglishRetrievalText: providerProjection?.canonicalEnglishRetrievalText,
            offerDetailUsesEnglishOnlyRetrievalProjection: providerProjection?.offerDetailUsesEnglishOnlyRetrievalProjection ?? false,
            offerObjectUsesEnglishOnlyRetrievalProjection: providerProjection?.offerObjectUsesEnglishOnlyRetrievalProjection ?? false,
            serviceAreas: providerProjection?.serviceAreas ?? [],
            topCandidates: makeTopCandidates(from: sortedMatches, rankingTrace: rankingTrace),
            selectedCandidateID: selectedCandidateID,
            selectedOfferID: selectedOfferID,
            objectLaneEvidence: objectLaneEvidence(from: sortedMatches, rankingTrace: rankingTrace),
            fitEngineSelectedCandidateID: sortedMatches.first?.counterpartyID,
            secondHalf: secondHalf,
            displaySearchQuery: ui.displaySearchQuery,
            capturedRequestText: ui.capturedRequestText,
            visibleSummary: ui.visibleSummary,
            threadTitle: ui.threadTitle,
            timings: .init(
                intentMs: intentMs,
                indexingMs: indexingMs,
                retrievalMs: max(totalMs - intentMs - secondHalfMs - indexingMs, 0),
                secondHalfMs: secondHalfMs,
                totalMs: totalMs
            ),
            passed: evaluation.passed,
            warnings: evaluation.warnings,
            failureReasons: evaluation.failures,
            resultTier: resultOutcome.resultTier.rawValue,
            federationVerified: resultOutcome.federationVerified,
            overlayFallbackUsed: resultOutcome.overlayFallbackUsed,
            productionParityConfidence: resultOutcome.productionParityConfidence.rawValue
        )
    }

    private static func writePairComparison(
        _ comparison: MultilingualRetrievalE2EPairComparison,
        to url: URL
    ) throws {
        try writeComparisonJSON(comparison, to: url)
    }

    private static func writeTripleComparison(
        _ comparison: MultilingualRetrievalE2ETripleComparison,
        to url: URL
    ) throws {
        try writeComparisonJSON(comparison, to: url)
    }

    private static func writeComparisonJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
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

    private static func objectLaneEvidence(
        from sortedMatches: [ExchangeMatch],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow]
    ) -> [String] {
        var evidence: [String] = []
        for match in sortedMatches {
            for offerID in match.provenObjectOfferIDs {
                evidence.append("match:\(match.counterpartyID):\(offerID)")
            }
        }
        for row in rankingTrace where row.docKind == ExchangeRetrievalDocument.DocKind.offerObject.rawValue {
            if let offerID = row.offerID {
                evidence.append("trace:\(row.counterpartyID):\(offerID):\(row.objectLaneScore ?? 0)")
            }
        }
        return Array(Set(evidence)).sorted()
    }

    private static func captureSecondHalfIfNeeded(
        executionMode: ExchangeE2EMode,
        detail: ExchangeModels.ThreadDetail,
        sortedMatches: [ExchangeMatch],
        intelligenceProvider: (any ExchangeIntelligenceProvider)?,
        rawUserText: String,
        forbiddenCategories: [String]
    ) async -> MultilingualE2ESecondHalfSnapshot {
        guard executionMode.includesManualSecondHalfCapture else {
            return .skipped
        }
        return await captureSecondHalf(
            detail: detail,
            sortedMatches: sortedMatches,
            intelligenceProvider: intelligenceProvider,
            rawUserText: rawUserText,
            forbiddenCategories: forbiddenCategories
        )
    }

    private static func captureSecondHalf(
        detail: ExchangeModels.ThreadDetail,
        sortedMatches: [ExchangeMatch],
        intelligenceProvider: (any ExchangeIntelligenceProvider)?,
        rawUserText: String,
        forbiddenCategories: [String]
    ) async -> MultilingualE2ESecondHalfSnapshot {
        let selectedOfferID = detail.selectedOfferID
            ?? detail.canonicalDiscoverySelectedOfferID
            ?? sortedMatches.first?.offerID
        let selectedMatch = sortedMatches.first(where: { $0.offerID == selectedOfferID }) ?? sortedMatches.first
        let counterparty = detail.counterparties.first(where: { $0.id == selectedMatch?.counterpartyID })
        let registryOffer = ExchangeDebugMultilingualFixtureRegistry.currentMatches()
            .first(where: { $0.id == selectedMatch?.counterpartyID })?
            .offers
            .first(where: { $0.id == selectedOfferID })

        var missingFacts: [String] = []
        var clarificationText: String?
        var compareSucceeded = false

        if let onDevice = intelligenceProvider as? OnDeviceExchangeIntelligenceProvider,
           let offer = registryOffer {
            let profile = counterparty?.publicProfile
            let compare = await onDevice.compareRequesterMatchToSurface(
                originalRequesterMessage: rawUserText,
                selectedOfferSummary: offer.summary,
                selectedProfileSummary: profile?.summary,
                counterpartyDisplayName: counterparty?.displayName,
                knownFacts: [],
                styleProfile: .default,
                requesterRequirementsSummary: nil
            )
            missingFacts = compare.missingFacts
            clarificationText = compare.providerQuestions.first ?? (compare.shouldAskProvider ? compare.reason : nil)
            compareSucceeded = true
        } else if let display = detail.secondHalfDisplay {
            missingFacts = display.requesterReview?.missingFacts ?? display.operatingContext.missingFacts
            clarificationText = display.plain.primaryUserQuestion
        }

        let forbidden = MultilingualRetrievalE2EEvaluation.classifyForbiddenMissingFacts(
            missingFacts: missingFacts,
            forbiddenCategories: forbiddenCategories
        )

        return MultilingualE2ESecondHalfSnapshot(
            missingFacts: missingFacts,
            forbiddenMissingFactsTriggered: forbidden,
            clarificationText: clarificationText,
            clarificationLanguage: clarificationText.flatMap { MultilingualRetrievalE2EEvaluation.detectedRequestLanguage(for: $0) },
            compareSucceeded: compareSucceeded
        )
    }
}

public enum MultilingualRetrievalE2EAuditError: Error, CustomStringConvertible, Sendable {
    case liveEnricherDependenciesMissing
    case fullFacadeDependenciesMissing
    case fullFacadeFacadeMissing
    case missingPairRuns
    case missingTripleRuns

    public var description: String {
        switch self {
        case .liveEnricherDependenciesMissing:
            return "live publish/enricher mode requires indexedSurfaceEnricher dependencies"
        case .fullFacadeDependenciesMissing:
            return "full facade publish mode requires directory client dependencies"
        case .fullFacadeFacadeMissing:
            return "full facade publish mode requires ExchangeFacade"
        case .missingPairRuns:
            return "paired comparison requires baseline and live runs"
        case .missingTripleRuns:
            return "triple comparison requires baseline, live, and full facade runs"
        }
    }
}

#endif
