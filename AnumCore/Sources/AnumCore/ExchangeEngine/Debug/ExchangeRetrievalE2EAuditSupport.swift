import Foundation

#if DEBUG

public enum ExchangeRetrievalE2EAuditSupport {
    public typealias UIProjectionCapture = @Sendable @MainActor (
        ExchangeModels.ThreadDetail
    ) -> AppSearchSmokeUIProjectionSnapshot

    public static func defaultArtifactURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("retrieval_e2e_smoke_audit.jsonl", isDirectory: false)
    }

    public static func run(
        facade: ExchangeFacade,
        baseURL: URL,
        scenarios: [ExchangeRetrievalE2EScenario] = ExchangeRetrievalE2EScenarios.mandatory,
        executionMode: ExchangeE2EMode = .discoveryOnly,
        captureUIProjection: UIProjectionCapture
    ) async throws -> RetrievalE2EBatchResult {
        try await ExchangeE2EActiveRun.withMode(executionMode) {
            var runs: [RetrievalE2ERunSnapshot] = []
            runs.reserveCapacity(scenarios.count)

            for (index, scenario) in scenarios.enumerated() {
                let run = try await runOne(
                    facade: facade,
                    baseURL: baseURL,
                    scenario: scenario,
                    runIndex: index + 1,
                    totalRuns: scenarios.count,
                    captureUIProjection: captureUIProjection
                )
                ExchangeRetrievalE2EReport.printRun(run)
                runs.append(run)
            }

            let artifactURL = defaultArtifactURL()
            try? ExchangeRetrievalE2EReport.writeJSONL(runs: runs, to: artifactURL)
            let aggregateText = ExchangeRetrievalE2EReport.printAggregate(
                runs: runs,
                artifactPath: artifactURL.path
            )

            return RetrievalE2EBatchResult(
                runs: runs,
                aggregateReportText: aggregateText,
                artifactPath: artifactURL.path
            )
        }
    }

    internal static func evaluateForTests(
        scenario: ExchangeRetrievalE2EScenario,
        thread: ExchangeThread,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        sortedMatches: [ExchangeMatch],
        counterparties: [ExchangeCounterparty],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        ui: AppSearchSmokeUIProjectionSnapshot,
        selectedOfferID: String?,
        matchedOffersByNode: [String: [String]]
    ) -> RetrievalE2EEvaluationResult {
        let objectLaneActive = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
        let queryContext = makeQueryContext(thread: thread)
        return ExchangeRetrievalE2EEvaluation.evaluate(
            scenario: scenario,
            thread: thread,
            searchIntent: searchIntent,
            sortedMatches: sortedMatches,
            counterparties: counterparties,
            rankingTrace: rankingTrace,
            queryContext: queryContext,
            objectLaneActive: objectLaneActive,
            selectedOfferID: selectedOfferID,
            matchedOffersByNode: matchedOffersByNode,
            ui: ui
        )
    }

    private static func runOne(
        facade: ExchangeFacade,
        baseURL: URL,
        scenario: ExchangeRetrievalE2EScenario,
        runIndex: Int,
        totalRuns: Int,
        captureUIProjection: UIProjectionCapture
    ) async throws -> RetrievalE2ERunSnapshot {
        await SearchIntentExtractionDebugTrace.shared.reset()
        ExchangeRetrievalDebugTrace.clearCapturedRows()
        ExchangeHTTPDirectorySearchCapture.record(
            retrievalResponseMode: nil,
            matchCount: 0,
            matches: []
        )

        let started = CFAbsoluteTimeGetCurrent()
        let response = try await facade.submit(scenario.queryText, threadID: nil, progressContext: nil)
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        let extractionTrace = await SearchIntentExtractionDebugTrace.shared.currentSnapshot()

        if response.isTransientNonPersistent {
            return buildTransientSnapshot(
                scenario: scenario,
                runIndex: runIndex,
                totalRuns: totalRuns,
                latencyMs: latencyMs,
                compactLLMOutput: extractionTrace.rawLLMOutputExact,
                evaluation: ExchangeRetrievalE2EEvaluation.buildTransientEvaluation(
                    fallbackReason: response.handoff.latestAction?.rawValue ?? response.summary
                )
            )
        }

        let detail = try await facade.getThread(threadID: response.thread.id)
        let ui = await captureUIProjection(detail)
        let thread = response.thread
        let searchIntent = thread.facets?.searchIntent
        let rankingTrace = ExchangeRetrievalDebugTrace.capturedRows()
        let queryContext = makeQueryContext(thread: thread)
        let topDocs = makeTopRetrievedDocs(from: rankingTrace)
        let emittedDocKinds = emittedDocKindLabels(
            rankingTrace: rankingTrace,
            serverMatches: ExchangeHTTPDirectorySearchCapture.lastMatches
        )

        let sortedMatches = response.matches.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }
        let matchedOffersByNode = ExchangeDebugProjectionMerge.aggregateProjectedOffersByNode(
            from: Array(sortedMatches.prefix(5))
        )

        let objectLaneActive = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
        let discoveryCalled = !response.matches.isEmpty
        let selectedOfferID = ExchangeCanonicalSelectionResolution.resolve(
            anchors: ExchangeCanonicalSelectionResolution.anchors(from: response),
            thread: thread,
            matches: sortedMatches,
            location: "RetrievalE2E"
        ).selectedOfferID

        let evaluation = ExchangeRetrievalE2EEvaluation.evaluate(
            scenario: scenario,
            thread: thread,
            searchIntent: searchIntent,
            sortedMatches: sortedMatches,
            counterparties: response.counterparties,
            rankingTrace: rankingTrace,
            queryContext: queryContext,
            objectLaneActive: objectLaneActive,
            selectedOfferID: selectedOfferID,
            matchedOffersByNode: matchedOffersByNode,
            ui: ui
        )

        return RetrievalE2ERunSnapshot(
            runIndex: runIndex,
            totalRuns: totalRuns,
            query: scenario.queryText,
            scenarioID: scenario.retrieval?.id ?? "e2e.\(runIndex)",
            passed: evaluation.passed,
            failureReasons: evaluation.allFailures,
            latencyMs: latencyMs,
            compactLLMOutput: extractionTrace.rawLLMOutputExact,
            routeClass: thread.intent.queryIntentClass.rawValue,
            surfacePreference: thread.facets?.surfacePreference.rawValue ?? thread.intent.surfacePreference.rawValue,
            objectType: searchIntent?.objectType,
            domainCategory: searchIntent?.domainCategory.rawValue,
            transactionIntent: searchIntent?.transactionIntent?.rawValue,
            retrievalQueryObjectText: queryContext.queryObjectText,
            objectLaneActive: objectLaneActive,
            discoveryCalled: discoveryCalled,
            emittedDocKinds: emittedDocKinds,
            topRetrievedDocs: topDocs,
            projectedMatchedOfferIDs: matchedOffersByNode,
            selectedOfferID: selectedOfferID,
            uiCardOfferID: ui.cardOfferID,
            uiSurfaceLead: ui.surfaceLead,
            fullEvaluateApplied: evaluation.fullEvaluateApplied,
            structuralFailures: evaluation.structuralFailures,
            rankingFailures: evaluation.rankingFailures,
            strictFailures: evaluation.strictFailures,
            uiFailures: evaluation.uiFailures
        )
    }

    private static func buildTransientSnapshot(
        scenario: ExchangeRetrievalE2EScenario,
        runIndex: Int,
        totalRuns: Int,
        latencyMs: Int,
        compactLLMOutput: String?,
        evaluation: RetrievalE2EEvaluationResult
    ) -> RetrievalE2ERunSnapshot {
        return RetrievalE2ERunSnapshot(
            runIndex: runIndex,
            totalRuns: totalRuns,
            query: scenario.queryText,
            scenarioID: scenario.retrieval?.id ?? "e2e.\(runIndex)",
            passed: evaluation.passed,
            failureReasons: evaluation.allFailures,
            latencyMs: latencyMs,
            compactLLMOutput: compactLLMOutput,
            routeClass: nil,
            surfacePreference: nil,
            objectType: nil,
            domainCategory: nil,
            transactionIntent: nil,
            retrievalQueryObjectText: nil,
            objectLaneActive: false,
            discoveryCalled: false,
            emittedDocKinds: [],
            topRetrievedDocs: [],
            projectedMatchedOfferIDs: [:],
            selectedOfferID: nil,
            uiCardOfferID: nil,
            uiSurfaceLead: nil,
            fullEvaluateApplied: evaluation.fullEvaluateApplied,
            structuralFailures: evaluation.structuralFailures,
            rankingFailures: evaluation.rankingFailures,
            strictFailures: evaluation.strictFailures,
            uiFailures: evaluation.uiFailures
        )
    }

    private static func makeQueryContext(thread: ExchangeThread) -> ExchangeRetrievalDebugTrace.QueryContext {
        let facets = thread.facets
        let si = facets?.searchIntent
        return ExchangeRetrievalDebugTrace.QueryContext(
            rawQuery: si?.rawUserText ?? thread.intent.title,
            queryIntentClass: (facets?.queryIntentClass ?? thread.intent.queryIntentClass).rawValue,
            surfacePreference: (facets?.surfacePreference ?? thread.intent.surfacePreference).rawValue,
            domainCategory: si?.domainCategory.rawValue,
            objectType: si?.objectType,
            transactionIntent: si?.transactionIntent?.rawValue,
            semanticEmbeddingTextPresent: !(si?.canonicalEnglishSearchText?.isEmpty ?? true),
            queryObjectText: ExchangeOfferObjectLane.queryObjectText(thread: thread)
        )
    }

    private static func makeTopRetrievedDocs(
        from rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow]
    ) -> [RetrievalE2ERetrievedDocRow] {
        rankingTrace.prefix(5).enumerated().map { index, row in
            RetrievalE2ERetrievedDocRow(
                rank: index + 1,
                docKind: row.docKind,
                surfaceType: row.surfaceType,
                offerID: row.offerID,
                counterpartyID: row.counterpartyID,
                finalScore: row.finalScore,
                objectLaneScore: row.objectLaneScore
            )
        }
    }

    private static func emittedDocKindLabels(
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        serverMatches: [ExchangeDirectoryMatch]
    ) -> [String] {
        var kinds = Set<String>()
        for row in rankingTrace {
            if let kind = row.docKind {
                kinds.insert(kind)
            }
        }
        for match in serverMatches {
            for doc in match.retrievalDocuments {
                if let kind = doc.docKind?.rawValue {
                    kinds.insert(kind)
                }
            }
        }
        return kinds.sorted()
    }
}

#endif
