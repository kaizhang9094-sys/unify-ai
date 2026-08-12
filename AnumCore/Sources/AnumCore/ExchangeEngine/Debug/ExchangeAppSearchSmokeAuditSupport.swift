import Foundation

#if DEBUG

public enum ExchangeAppSearchSmokeAuditSupport {
    public typealias UIProjectionCapture = @Sendable @MainActor (
        ExchangeModels.ThreadDetail
    ) -> AppSearchSmokeUIProjectionSnapshot

    public static func run(
        facade: ExchangeFacade,
        baseURL: URL,
        scenarios: [ExchangeAppSearchSmokeScenario] = ExchangeAppSearchSmokeScenarios.mandatory,
        captureUIProjection: UIProjectionCapture
    ) async throws -> AppSearchSmokeBatchResult {
        let manifest = try loadManifestIfPresent()
        let expectedNodeIDs = Set(manifest?.expectedNodeIDs ?? [])
        let expectedDocIDs = Set(manifest?.expectedDocIDs ?? [])

        var runs: [AppSearchSmokeRunSnapshot] = []
        runs.reserveCapacity(scenarios.count)

        for (index, scenario) in scenarios.enumerated() {
            let run = try await runOne(
                facade: facade,
                baseURL: baseURL,
                scenario: scenario,
                runIndex: index + 1,
                totalRuns: scenarios.count,
                expectedNodeIDs: expectedNodeIDs,
                expectedDocIDs: expectedDocIDs,
                publishGenerationID: manifest?.publishGenerationID,
                captureUIProjection: captureUIProjection
            )
            ExchangeAppSearchSmokeReport.printRun(run)
            runs.append(run)
        }

        let metrics = ExchangeAppSearchSmokeReport.makeAggregateMetrics(from: runs)
        let artifactURL = defaultArtifactURL()
        try? ExchangeAppSearchSmokeReport.writeJSONL(runs: runs, to: artifactURL)
        let aggregateText = ExchangeAppSearchSmokeReport.printAggregate(
            metrics: metrics,
            artifactPath: artifactURL.path,
            publishGenerationID: manifest?.publishGenerationID
        )

        return AppSearchSmokeBatchResult(
            runs: runs,
            aggregateReportText: aggregateText,
            artifactPath: artifactURL.path
        )
    }

    private static func runOne(
        facade: ExchangeFacade,
        baseURL: URL,
        scenario: ExchangeAppSearchSmokeScenario,
        runIndex: Int,
        totalRuns: Int,
        expectedNodeIDs: Set<String>,
        expectedDocIDs: Set<String>,
        publishGenerationID: String?,
        captureUIProjection: UIProjectionCapture
    ) async throws -> AppSearchSmokeRunSnapshot {
        ExchangeRetrievalDebugTrace.clearCapturedRows()
        ExchangeHTTPDirectorySearchCapture.record(
            retrievalResponseMode: nil,
            matchCount: 0,
            matches: []
        )

        let started = CFAbsoluteTimeGetCurrent()
        let response = try await facade.submit(scenario.queryText, threadID: nil, progressContext: nil)
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)

        if response.isTransientNonPersistent {
            return buildTransientFailureRunSnapshot(
                response: response,
                baseURL: baseURL,
                scenario: scenario,
                runIndex: runIndex,
                totalRuns: totalRuns,
                latencyMs: latencyMs,
                publishGenerationID: publishGenerationID
            )
        }

        let detail = try await facade.getThread(threadID: response.thread.id)
        let ui = await captureUIProjection(detail)

        let rankingTrace = ExchangeRetrievalDebugTrace.capturedRows()
        let serverMatches = ExchangeHTTPDirectorySearchCapture.lastMatches
        let observedMode = ExchangeHTTPDirectorySearchCapture.lastRetrievalResponseMode
            ?? ExchangeDirectorySearchRequest.RetrievalResponseMode.clientRerank.rawValue

        let serverRoundTrip = ExchangeRetrievalLocalFederationSmokeReport.auditServerRoundTrip(
            matches: serverMatches,
            expectedNodeIDs: expectedNodeIDs,
            expectedDocIDs: expectedDocIDs,
            observedResponseMode: observedMode
        )

        let engine = buildEngineSnapshot(
            response: response,
            scenario: scenario,
            rankingTrace: rankingTrace,
            serverRoundTrip: serverRoundTrip,
            observedMode: observedMode
        )
        let thread = buildThreadSnapshot(from: detail)
        let wiring = evaluateWiring(
            expectation: scenario.expectation,
            engine: engine,
            thread: thread,
            ui: ui
        )

        let accuracyResult = buildAccuracyResult(
            scenario: scenario,
            engine: engine,
            rankingTrace: rankingTrace
        )
        let strictFailures = ExchangeRetrievalLocalFederationSmokeReport.strictFailures(
            expectation: scenario.expectation,
            accuracyResult: accuracyResult,
            rankingTrace: rankingTrace,
            serverRoundTrip: serverRoundTrip
        )
        let observational = ExchangeRetrievalAccuracyReport.observationalAssessment(
            expectation: scenario.expectation,
            result: accuracyResult,
            rankingTrace: rankingTrace,
            serverRoundTripIssues: serverRoundTrip.issues
        )

        let runtimeWiringIssues = wiring.runtimeWiringIssues + wiring.uiProjectionIssues
        let strictPassed = strictFailures.isEmpty
            && wiring.engineVsThreadMismatch.isEmpty
            && wiring.threadVsUIMismatch.isEmpty
            && wiring.wrongFallbackOfferSelections == 0

        return AppSearchSmokeRunSnapshot(
            runIndex: runIndex,
            totalRuns: totalRuns,
            query: scenario.queryText,
            scenarioID: scenario.expectation.id,
            serverBaseURL: baseURL.absoluteString,
            publishGenerationID: publishGenerationID,
            strictPassed: strictPassed,
            latencyMs: latencyMs,
            engine: engine,
            thread: thread,
            ui: ui,
            engineVsThreadMismatch: wiring.engineVsThreadMismatch,
            threadVsUIMismatch: wiring.threadVsUIMismatch,
            uiProjectionIssues: wiring.uiProjectionIssues,
            runtimeWiringIssues: runtimeWiringIssues,
            wrongFallbackOfferSelections: wiring.wrongFallbackOfferSelections,
            observationalTop1PrimaryHit: observational.top1PrimaryHit,
            observationalTop1AnyRequiredHit: observational.top1AnyRequiredHit,
            observationalTop3AnyRequiredHit: observational.top3AnyRequiredHit
        )
    }

    private static func buildEngineSnapshot(
        response: ExchangeOrchestrator.Response,
        scenario: ExchangeAppSearchSmokeScenario,
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        serverRoundTrip: LocalFederationServerRoundTripAudit,
        observedMode: String
    ) -> AppSearchSmokeEngineSnapshot {
        let thread = response.thread
        let sortedMatches = response.matches.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }

        let matchedOffersByNode = ExchangeDebugProjectionMerge.aggregateProjectedOffersByNode(from: sortedMatches)

        let topNodes = sortedMatches.prefix(scenario.expectation.topK).map(\.counterpartyID)
        let selectedOfferID = ExchangeCanonicalSelectionResolution.resolve(
            anchors: ExchangeCanonicalSelectionResolution.anchors(from: response),
            thread: response.thread,
            matches: sortedMatches,
            location: "AppSearchSmokeEngine"
        ).selectedOfferID
        let provenObjectOfferIDs = Array(
            Set(sortedMatches.flatMap(\.provenObjectOfferIDs))
        ).sorted()
        var objectEvidence: [String: Double] = [:]
        for match in sortedMatches {
            for (offerID, score) in match.objectEvidenceScoreByOfferID {
                objectEvidence[offerID] = max(objectEvidence[offerID] ?? 0, score)
            }
        }

        let accuracyResult = ExchangeRetrievalAccuracyScenarioResult(
            scenarioID: scenario.expectation.id,
            queryLabel: scenario.expectation.queryLabel,
            passed: true,
            expectedSummary: scenario.expectation.expectedSummary,
            failureReason: nil,
            actualTopSummaries: topNodes.enumerated().map { index, nodeID in
                "#\(index + 1) node=\(nodeID) offers=[\((matchedOffersByNode[nodeID] ?? []).joined(separator: ","))] docKind=unknown score=0.000"
            },
            selectedOfferID: selectedOfferID,
            matchedOffersByNode: matchedOffersByNode,
            objectLaneActive: ExchangeOfferObjectLane.isObjectLaneActive(thread: thread),
            provenObjectOfferIDs: provenObjectOfferIDs,
            topDocKinds: rankingTrace.prefix(scenario.expectation.topK).compactMap(\.docKind),
            topObjectEvidenceScores: objectEvidence,
            queryContext: nil,
            directoryRecall: nil
        )

        let strictFailures = ExchangeRetrievalAccuracyReport.strictInvariantFailures(
            expectation: scenario.expectation,
            result: accuracyResult,
            rankingTrace: rankingTrace
        )

        var forbidden = 0
        var olFP = 0
        var olFN = 0
        for failure in strictFailures {
            if failure.contains("forbidden attachment") { forbidden += 1 }
            if failure.contains("false positive") { olFP += 1 }
            if failure.contains("false negative") { olFN += 1 }
        }

        let searchIntent = thread.facets?.searchIntent
        let discoveryCalled = !response.isTransientNonPersistent
            && !response.matches.isEmpty

        return AppSearchSmokeEngineSnapshot(
            query: scenario.queryText,
            scenarioID: scenario.expectation.id,
            intentClass: thread.intent.queryIntentClass.rawValue,
            facetsQueryIntentClass: thread.facets?.queryIntentClass.rawValue,
            objectType: searchIntent?.objectType,
            domainCategory: searchIntent?.domainCategory.rawValue,
            transactionIntent: searchIntent?.transactionIntent?.rawValue,
            objectLaneActive: ExchangeOfferObjectLane.isObjectLaneActive(thread: thread),
            discoveryCalled: discoveryCalled,
            responseMode: observedMode,
            topNodes: topNodes,
            selectedOfferID: selectedOfferID,
            matchedOffersByNode: matchedOffersByNode,
            provenObjectOfferIDs: provenObjectOfferIDs,
            objectEvidenceScoreByOfferID: objectEvidence,
            topDocKinds: accuracyResult.topDocKinds,
            forbiddenAttachmentViolations: forbidden,
            objectLaneFP: olFP,
            objectLaneFN: olFN,
            strictFailures: strictFailures,
            serverRoundTripIssues: serverRoundTrip.issues
        )
    }

    private static func buildThreadSnapshot(
        from detail: ExchangeModels.ThreadDetail
    ) -> AppSearchSmokeThreadSnapshot {
        let sortedMatches = detail.matches.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .selected
            }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }

        let matchedOffersByNode = ExchangeDebugProjectionMerge.aggregateProjectedOffersByNode(from: sortedMatches)

        return AppSearchSmokeThreadSnapshot(
            threadID: detail.thread.id.uuidString,
            selectedOfferID: detail.selectedOfferID ?? detail.thread.selectedOfferID,
            selectedPublicProfileID: detail.selectedPublicProfileID ?? detail.thread.selectedPublicProfileID,
            selectedCounterpartyID: detail.thread.selectedCounterpartyID,
            matchedOffersByNode: matchedOffersByNode,
            provenObjectOfferIDs: Array(Set(sortedMatches.flatMap(\.provenObjectOfferIDs))).sorted(),
            topNodes: sortedMatches.map(\.counterpartyID)
        )
    }

    internal static func evaluateWiringForTests(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation,
        engine: AppSearchSmokeEngineSnapshot,
        thread: AppSearchSmokeThreadSnapshot,
        ui: AppSearchSmokeUIProjectionSnapshot
    ) -> (
        engineVsThreadMismatch: [String],
        threadVsUIMismatch: [String],
        uiProjectionIssues: [String],
        runtimeWiringIssues: [String],
        wrongFallbackOfferSelections: Int
    ) {
        evaluateWiring(
            expectation: expectation,
            engine: engine,
            thread: thread,
            ui: ui
        )
    }

    private static func evaluateWiring(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation,
        engine: AppSearchSmokeEngineSnapshot,
        thread: AppSearchSmokeThreadSnapshot,
        ui: AppSearchSmokeUIProjectionSnapshot
    ) -> (
        engineVsThreadMismatch: [String],
        threadVsUIMismatch: [String],
        uiProjectionIssues: [String],
        runtimeWiringIssues: [String],
        wrongFallbackOfferSelections: Int
    ) {
        var engineVsThread: [String] = []
        var threadVsUI: [String] = []
        var uiIssues: [String] = []
        var runtimeIssues: [String] = []
        var fallbackCount = 0

        if normalized(engine.selectedOfferID) != normalized(thread.selectedOfferID) {
            if shouldRequireSelectedOffer(expectation: expectation) {
                engineVsThread.append(
                    "selectedOfferID engine=\(engine.selectedOfferID ?? "nil") thread=\(thread.selectedOfferID ?? "nil")"
                )
            }
        }

        if shouldRequireSelectedOffer(expectation: expectation) {
            if normalized(thread.selectedOfferID) != normalized(ui.selectedOfferID) {
                threadVsUI.append(
                    "selectedOfferID thread=\(thread.selectedOfferID ?? "nil") ui=\(ui.selectedOfferID ?? "nil")"
                )
            }
        }

        for (nodeID, engineOffers) in engine.matchedOffersByNode {
            let threadOffers = Set(thread.matchedOffersByNode[nodeID] ?? [])
            let engineSet = Set(engineOffers)
            let extras = threadOffers.subtracting(engineSet)
            if !extras.isEmpty {
                runtimeIssues.append(
                    "thread matchedOffers include offers not in engine snapshot on \(nodeID): \(Array(extras))"
                )
            }
        }

        if expectation.objectLaneActive, let selected = thread.selectedOfferID {
            if !engine.provenObjectOfferIDs.contains(selected) {
                fallbackCount += 1
                runtimeIssues.append(
                    "object-lane selectedOfferID \(selected) not in provenObjectOfferIDs \(engine.provenObjectOfferIDs)"
                )
            }
        }

        if let uiOffer = ui.selectedOfferID,
           expectation.objectLaneActive,
           !engine.provenObjectOfferIDs.contains(uiOffer) {
            uiIssues.append("UI offerID \(uiOffer) not proven by object evidence")
        }

        if expectation.requiresAdvanceable == true {
            if thread.selectedPublicProfileID == nil, thread.selectedOfferID == nil, thread.selectedCounterpartyID == nil {
                runtimeIssues.append("expected advanceable match anchors but thread selection is empty")
            }
        }

        for forbidden in expectation.forbiddenAttachments {
            let threadOffers = Set(thread.matchedOffersByNode[forbidden.nodeID] ?? [])
            if threadOffers.contains(forbidden.offerID) {
                runtimeIssues.append("forbidden attachment \(forbidden.offerID) on \(forbidden.nodeID) in thread snapshot")
            }
        }

        return (engineVsThread, threadVsUI, uiIssues, runtimeIssues, fallbackCount)
    }

    private static func buildAccuracyResult(
        scenario: ExchangeAppSearchSmokeScenario,
        engine: AppSearchSmokeEngineSnapshot,
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow]
    ) -> ExchangeRetrievalAccuracyScenarioResult {
        ExchangeRetrievalAccuracyScenarioResult(
            scenarioID: scenario.expectation.id,
            queryLabel: scenario.expectation.queryLabel,
            passed: engine.strictFailures.isEmpty,
            expectedSummary: scenario.expectation.expectedSummary,
            failureReason: engine.strictFailures.isEmpty ? nil : engine.strictFailures.joined(separator: "; "),
            actualTopSummaries: engine.topNodes.enumerated().map { index, nodeID in
                "#\(index + 1) node=\(nodeID) offers=[\((engine.matchedOffersByNode[nodeID] ?? []).joined(separator: ","))] docKind=\(rankingTrace[safe: index]?.docKind ?? "unknown") score=0.000"
            },
            selectedOfferID: engine.selectedOfferID,
            matchedOffersByNode: engine.matchedOffersByNode,
            objectLaneActive: engine.objectLaneActive,
            provenObjectOfferIDs: engine.provenObjectOfferIDs,
            topDocKinds: engine.topDocKinds,
            topObjectEvidenceScores: engine.objectEvidenceScoreByOfferID,
            queryContext: nil,
            directoryRecall: ExchangeRetrievalDebugTrace.DirectoryRecall(
                retrievalResponseMode: engine.responseMode,
                retrievalDocumentsCount: 0,
                retrievalHitsCount: 0,
                docKindCounts: [:],
                embeddingCountsByDocKind: [:],
                candidateOfferIDsFromDocs: []
            )
        )
    }

    private static func shouldRequireSelectedOffer(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation
    ) -> Bool {
        if expectation.selectedOfferIDMustBeNil { return false }
        if expectation.selectedOfferID != nil { return true }
        if expectation.objectLaneActive, expectation.requiresAdvanceable != false { return true }
        return false
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func buildTransientFailureRunSnapshot(
        response: ExchangeOrchestrator.Response,
        baseURL: URL,
        scenario: ExchangeAppSearchSmokeScenario,
        runIndex: Int,
        totalRuns: Int,
        latencyMs: Int,
        publishGenerationID: String?
    ) -> AppSearchSmokeRunSnapshot {
        let observedMode = ExchangeHTTPDirectorySearchCapture.lastRetrievalResponseMode
            ?? ExchangeDirectorySearchRequest.RetrievalResponseMode.clientRerank.rawValue
        let engine = buildEngineSnapshot(
            response: response,
            scenario: scenario,
            rankingTrace: [],
            serverRoundTrip: LocalFederationServerRoundTripAudit(
                responseMode: observedMode,
                serverRetrievalDocumentsCount: 0,
                serverRetrievalHitsCount: 0,
                docKindCounts: [:],
                embeddingCountsByDocKind: [:],
                candidateOfferIDsFromDocs: [],
                issues: ["transient submit skipped directory round trip"]
            ),
            observedMode: observedMode
        )
        let thread = AppSearchSmokeThreadSnapshot(
            threadID: response.thread.id.uuidString,
            selectedOfferID: response.thread.selectedOfferID,
            selectedPublicProfileID: response.thread.selectedPublicProfileID,
            selectedCounterpartyID: response.thread.selectedCounterpartyID,
            matchedOffersByNode: [:],
            provenObjectOfferIDs: [],
            topNodes: []
        )
        let ui = AppSearchSmokeUIProjectionSnapshot(
            selectedOfferID: nil,
            matchedOffersByNode: [:],
            preferredMatchCounterpartyID: nil,
            preferredMatchOfferID: nil,
            cardOfferID: nil,
            visiblePublicProfileID: nil,
            surfaceLead: "transient_non_persistent"
        )
        let failureReason = response.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let runtimeWiringIssues = [
            "transientNonPersistent=true",
            failureReason.isEmpty ? "submit returned transient non-persistent response" : failureReason
        ]
        let strictFailures = engine.strictFailures + [
            "transient submit did not create durable thread"
        ]

        return AppSearchSmokeRunSnapshot(
            runIndex: runIndex,
            totalRuns: totalRuns,
            query: scenario.queryText,
            scenarioID: scenario.expectation.id,
            serverBaseURL: baseURL.absoluteString,
            publishGenerationID: publishGenerationID,
            strictPassed: false,
            latencyMs: latencyMs,
            engine: AppSearchSmokeEngineSnapshot(
                query: engine.query,
                scenarioID: engine.scenarioID,
                intentClass: engine.intentClass,
                facetsQueryIntentClass: engine.facetsQueryIntentClass,
                objectType: engine.objectType,
                domainCategory: engine.domainCategory,
                transactionIntent: engine.transactionIntent,
                objectLaneActive: engine.objectLaneActive,
                discoveryCalled: false,
                responseMode: engine.responseMode,
                topNodes: engine.topNodes,
                selectedOfferID: engine.selectedOfferID,
                matchedOffersByNode: engine.matchedOffersByNode,
                provenObjectOfferIDs: engine.provenObjectOfferIDs,
                objectEvidenceScoreByOfferID: engine.objectEvidenceScoreByOfferID,
                topDocKinds: engine.topDocKinds,
                forbiddenAttachmentViolations: engine.forbiddenAttachmentViolations,
                objectLaneFP: engine.objectLaneFP,
                objectLaneFN: engine.objectLaneFN,
                strictFailures: strictFailures,
                serverRoundTripIssues: engine.serverRoundTripIssues
            ),
            thread: thread,
            ui: ui,
            engineVsThreadMismatch: [],
            threadVsUIMismatch: ["transient submit has no persisted thread snapshot"],
            uiProjectionIssues: ["transient submit has no UI projection"],
            runtimeWiringIssues: runtimeWiringIssues,
            wrongFallbackOfferSelections: 0,
            observationalTop1PrimaryHit: false,
            observationalTop1AnyRequiredHit: false,
            observationalTop3AnyRequiredHit: false
        )
    }

    private static func loadManifestIfPresent() throws -> ExchangeRetrievalAccuracyFederationCatalogExport.GenerationManifest? {
        let path = ExchangeAppSearchSmokeGate.generationManifestPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try ExchangeRetrievalAccuracyFederationCatalogExport.loadManifest(
            from: URL(fileURLWithPath: path)
        )
    }

    public static func defaultArtifactURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("app_search_smoke_audit.jsonl", isDirectory: false)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

#endif
