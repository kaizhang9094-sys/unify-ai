import Foundation

#if DEBUG

public enum MultilingualSecretaryLiveSubsetRunner {
    public static func run(
        facade: ExchangeFacade,
        baseURL: URL?,
        fixtures: [MultilingualSecretaryMatrixFixture] = MultilingualSecretaryLiveSubsetFixtures.all,
        runMode: MultilingualRetrievalE2EMode = .livePublishEnricher,
        executionMode: ExchangeE2EMode = .discoveryOnly,
        includeFullFacadeFirstScenario: Bool = false,
        seedMode: MultilingualRetrievalE2EAuditSupport.SeedMode = .onDeviceONNX,
        liveEnricherDependencies: MultilingualRetrievalE2EAuditSupport.LiveEnricherDependenciesFactory = { nil },
        fullFacadeDependencies: MultilingualRetrievalE2EAuditSupport.FullFacadePublishDependenciesFactory = { nil },
        intelligenceProvider: MultilingualRetrievalE2EAuditSupport.IntelligenceProviderFactory = { nil },
        captureUIProjection: MultilingualRetrievalE2EAuditSupport.UIProjectionCapture
    ) async throws -> MultilingualSecretaryLiveSubsetBatchResult {
        try await ExchangeE2EActiveRun.withMode(executionMode) {
            defer { ExchangeDebugMultilingualFixtureRegistry.clear() }

            var records: [MultilingualSecretaryLiveSubsetAuditRecord] = []
            records.reserveCapacity(fixtures.count)

            for (index, fixture) in fixtures.enumerated() {
            let effectiveMode: MultilingualRetrievalE2EMode
            if includeFullFacadeFirstScenario && index == 0 {
                effectiveMode = .fullFacadePublishPath
            } else {
                effectiveMode = runMode
            }

            ExchangeDebugMultilingualFixtureRegistry.clear()
            let seedResult = try await MultilingualRetrievalE2EAuditSupport.seedFixtures(
                for: fixture,
                runMode: effectiveMode,
                seedMode: seedMode,
                facade: facade,
                liveEnricherDependencies: liveEnricherDependencies,
                fullFacadeDependencies: fullFacadeDependencies
            )
            ExchangeDebugMultilingualFixtureRegistry.setMatches(seedResult.matches)

            let scenario = fixture.toMultilingualScenario()
            let capture = try await MultilingualRetrievalE2EAuditSupport.runLiveCapture(
                facade: facade,
                scenario: scenario,
                seedResult: seedResult,
                executionMode: executionMode,
                intelligenceProvider: intelligenceProvider,
                captureUIProjection: captureUIProjection
            )

            let providerProjection = seedResult.providerProjection
                ?? MultilingualSecretaryMatrixEvaluation.providerProjectionAudit(
                    catalog: seedResult.matches,
                    fixture: fixture
                )

            let evaluation = MultilingualSecretaryMatrixEvaluation.evaluate(
                fixture: fixture,
                searchIntent: capture.searchIntent,
                thread: capture.thread,
                sortedMatches: capture.sortedMatches,
                rankingTrace: capture.rankingTrace,
                selectedOfferID: capture.selectedOfferID,
                selectedCandidateID: capture.selectedCandidateID,
                objectLaneActive: capture.objectLaneActive,
                providerProjection: providerProjection,
                secondHalf: capture.secondHalf,
                ui: capture.ui
            )

            let warnings = deriveWarnings(
                providerIndexing: seedResult.providerIndexing,
                secondHalf: capture.secondHalf
            )
            let resultOutcome = MultilingualE2EResultTierResolver.resolve(
                runMode: effectiveMode,
                passed: evaluation.passed,
                publication: seedResult.providerIndexing.fullFacadePublication
            )

            let indexingMs = seedResult.providerIndexing.providerBuildTimings?.totalMs ?? 0
            let timings = MultilingualE2ETimingSnapshot(
                intentMs: capture.timings.intentMs,
                indexingMs: indexingMs,
                retrievalMs: max(
                    capture.timings.totalMs - capture.timings.intentMs - capture.timings.secondHalfMs - indexingMs,
                    0
                ),
                secondHalfMs: capture.timings.secondHalfMs,
                totalMs: capture.timings.totalMs + indexingMs
            )

            let providerCarrier = providerProjection?.canonicalEnglishRetrievalText
                ?? seedResult.providerIndexing.providerCanonicalEnglishRetrievalText
            let noisyOutranking = MultilingualSecretaryLiveSubsetReport.noisyOutrankingDetected(
                failureReasons: evaluation.failures
            )
            let carrierLost = MultilingualSecretaryLiveSubsetReport.carrierLost(
                failureReasons: evaluation.failures,
                providerCanonicalEnglishRetrievalText: providerCarrier
            )

            let record = MultilingualSecretaryLiveSubsetReport.applyFailureCategories(
                to: MultilingualSecretaryLiveSubsetAuditRecord(
                fixtureID: fixture.id,
                vertical: fixture.vertical.rawValue,
                languagePair: fixture.languagePair.rawValue,
                runMode: effectiveMode.rawValue,
                rawUserText: fixture.userText,
                rawProviderText: combinedProviderText(for: fixture),
                canonicalEnglishSearchText: capture.searchIntent?.canonicalEnglishSearchText,
                providerCanonicalEnglishRetrievalText: providerCarrier,
                selectedOfferID: capture.selectedOfferID,
                expectedOfferID: fixture.expectedSelectedOfferID,
                topCandidates: makeTopCandidates(
                    from: capture.sortedMatches,
                    rankingTrace: capture.rankingTrace
                ),
                noisyOutrankingDetected: noisyOutranking,
                forbiddenMissingFactsTriggered: capture.secondHalf.forbiddenMissingFactsTriggered,
                displaySearchQuery: capture.ui.displaySearchQuery,
                capturedRequestText: capture.ui.capturedRequestText,
                timings: timings,
                resultTier: resultOutcome.resultTier.rawValue,
                productionParityConfidence: resultOutcome.productionParityConfidence.rawValue,
                federationVerified: resultOutcome.federationVerified,
                overlayFallbackUsed: resultOutcome.overlayFallbackUsed,
                passed: evaluation.passed,
                warnings: warnings,
                failureReasons: evaluation.failures,
                carrierLost: carrierLost
                )
            )
            records.append(record)
            MultilingualSecretaryLiveSubsetReport.printRecord(record)
        }

        let artifactURL = MultilingualSecretaryLiveSubsetReport.defaultArtifactURL()
        try? MultilingualSecretaryLiveSubsetReport.writeJSONL(records: records, to: artifactURL)
        let summary = MultilingualSecretaryLiveSubsetReport.summarize(records)
        let summaryArtifactURL = MultilingualSecretaryLiveSubsetReport.defaultSummaryArtifactURL()
        try? MultilingualSecretaryLiveSubsetReport.writeSummaryJSON(summary: summary, to: summaryArtifactURL)
        let aggregateText = MultilingualSecretaryLiveSubsetReport.printSummary(
            summary,
            artifactPath: artifactURL.path,
            summaryArtifactPath: summaryArtifactURL.path
        )

        if let baseURL {
            print("[MultilingualLiveSubset] federationBaseURL=\(baseURL.absoluteString) scenarios=\(records.count)")
        }

        return MultilingualSecretaryLiveSubsetBatchResult(
            records: records,
            summary: summary,
            aggregateReportText: aggregateText,
            artifactPath: artifactURL.path,
            summaryArtifactPath: summaryArtifactURL.path
        )
        }
    }

    private static func combinedProviderText(for fixture: MultilingualSecretaryMatrixFixture) -> String {
        [fixture.providerProfileText, fixture.providerOfferText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func deriveWarnings(
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        secondHalf: MultilingualE2ESecondHalfSnapshot
    ) -> [String] {
        var warnings: [String] = []
        if providerIndexing.providerEnricherAttempted && !providerIndexing.providerEnricherSucceeded {
            warnings.append("provider enricher did not produce English carrier")
        }
        if providerIndexing.providerUnsafeFallbackTriggered {
            warnings.append("unsafe non-English retrieval fallback triggered")
        }
        let failedTokens = providerIndexing.providerCanonicalEnglishRetrievalTextTokenCheck
            .filter { !$0.value }
            .map(\.key)
            .sorted()
        if !failedTokens.isEmpty {
            warnings.append("carrier token check failed: \(failedTokens.joined(separator: ","))")
        }
        if !secondHalf.compareSucceeded {
            warnings.append("second-half compare unavailable")
        }
        if !secondHalf.forbiddenMissingFactsTriggered.isEmpty {
            warnings.append(
                "forbidden missing facts triggered: \(secondHalf.forbiddenMissingFactsTriggered.joined(separator: ","))"
            )
        }
        if providerIndexing.fullFacadePublication?.usesOverlayFallbackForRoofer == true {
            warnings.append("full facade used overlay fallback")
        }
        return warnings
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

#endif
