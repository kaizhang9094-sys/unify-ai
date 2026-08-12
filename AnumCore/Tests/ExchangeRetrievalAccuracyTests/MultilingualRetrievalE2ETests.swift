import XCTest
@testable import AnumCore

#if DEBUG

final class MultilingualRetrievalE2ETests: XCTestCase {
    private let providerEnglishTokens = ["roofer", "roof", "aurora", "estimate", "newmarket"]

    func testFixtureBuilderProjectsEnglishCarrierAndServiceAreas() {
        let catalog = MultilingualRetrievalE2EFixtureBuilder.buildCatalog(includeAxisEmbeddings: true)
        let audit = MultilingualRetrievalE2EFixtureBuilder.providerProjectionAudit(from: catalog)

        XCTAssertNotNil(audit)
        XCTAssertEqual(audit?.offerID, MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer)
        XCTAssertTrue(audit?.offerObjectUsesEnglishOnlyRetrievalProjection == true)
        XCTAssertTrue(audit?.offerDetailUsesEnglishOnlyRetrievalProjection == true)
        XCTAssertTrue(audit?.serviceAreas.contains("Aurora") == true)
        XCTAssertTrue(audit?.serviceAreas.contains("Newmarket") == true)
        XCTAssertTrue(audit?.preservedChineseInSourceBlocks == true)
    }

    func testLocalEvaluationPassesWithMockIntentDiscoveryAndUI() {
        let scenario = ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer
        let catalog = MultilingualRetrievalE2EFixtureBuilder.buildCatalog(includeAxisEmbeddings: true)
        let providerProjection = MultilingualRetrievalE2EFixtureBuilder.providerProjectionAudit(from: catalog)
        let providerIndexing = MultilingualRetrievalE2EProviderIndexingAudit.injectedBaselineSnapshot(
            projection: providerProjection,
            buildTimings: .init(indexedSurfaceMs: 0, enricherMs: 0, retrievalDocsMs: 0, embedMs: 1, totalMs: 1),
            expectedEnglishTokens: providerEnglishTokens
        )

        let searchIntent = makeMockSearchIntent(scenario: scenario)
        let thread = makeMockThread(scenario: scenario, searchIntent: searchIntent)
        let rooferMatch = makeMockRooferMatch(thread: thread, scenario: scenario)
        let noisyMatch = makeMockNoisyMatch(thread: thread)
        let ui = makeMockUI(scenario: scenario)
        let secondHalf = MultilingualE2ESecondHalfSnapshot(
            missingFacts: ["exact availability confirmation"],
            forbiddenMissingFactsTriggered: [],
            clarificationText: nil,
            clarificationLanguage: nil,
            compareSucceeded: false
        )
        let rankingTrace = makeMockRankingTrace(scenario: scenario)

        let result = MultilingualRetrievalE2EAuditSupport.evaluateForTests(
            scenario: scenario,
            runMode: .injectedCarrierFixture,
            searchIntent: searchIntent,
            thread: thread,
            sortedMatches: [rooferMatch, noisyMatch],
            rankingTrace: rankingTrace,
            selectedOfferID: scenario.expectedSelectedOfferID,
            selectedCandidateID: scenario.expectedSelectedNodeID,
            objectLaneActive: false,
            providerProjection: providerProjection,
            providerIndexing: providerIndexing,
            secondHalf: secondHalf,
            ui: ui
        )

        XCTAssertTrue(result.passed, result.failures.joined(separator: "; "))
    }

    func testPairComparisonLogic() {
        let scenario = ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer
        let baseline = makeRunSnapshot(
            scenario: scenario,
            runMode: .injectedCarrierFixture,
            selectedOfferID: scenario.expectedSelectedOfferID,
            serviceAreas: ["Aurora", "Newmarket"],
            carrier: "roofer roof estimate aurora",
            objectEnglish: true,
            totalMs: 1000,
            forbiddenMissingFacts: [],
            uiText: scenario.rawUserText
        )
        let live = makeRunSnapshot(
            scenario: scenario,
            runMode: .livePublishEnricher,
            selectedOfferID: scenario.expectedSelectedOfferID,
            serviceAreas: ["Aurora", "Newmarket"],
            carrier: "roofer roof estimate aurora newmarket",
            objectEnglish: true,
            totalMs: 1500,
            forbiddenMissingFacts: [],
            uiText: scenario.rawUserText
        )

        let comparison = MultilingualRetrievalE2EPairComparisonBuilder.compare(baseline: baseline, live: live)
        XCTAssertTrue(comparison.bothHaveProviderCanonicalEnglishRetrievalText)
        XCTAssertTrue(comparison.bothOfferObjectUseEnglishOnlyProjection)
        XCTAssertTrue(comparison.serviceAreasMatch)
        XCTAssertTrue(comparison.selectedOfferIDMatch)
        XCTAssertEqual(comparison.timingDeltaMs, 500)
        XCTAssertTrue(comparison.summaryLines.contains(where: { $0.contains("timingMs") }))
    }

    func testLiveModeFailureClassificationWhenEnricherMissingCarrier() {
        let projection = MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit(
            nodeID: MultilingualRetrievalE2EFixtureBuilder.NodeID.roofer,
            offerID: MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer,
            canonicalEnglishRetrievalText: nil,
            offerDetailUsesEnglishOnlyRetrievalProjection: false,
            offerObjectUsesEnglishOnlyRetrievalProjection: false,
            serviceAreas: [],
            offerObjectSearchableText: nil,
            preservedChineseInSourceBlocks: true
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingSnapshot(
            runMode: MultilingualRetrievalE2EMode.livePublishEnricher.rawValue,
            providerIndexingSource: "liveEnricherCorePath",
            providerEnricherAttempted: true,
            providerEnricherSucceeded: false,
            providerEnricherFailureReason: ProviderSurfaceEnrichmentFailureReason.timeout.rawValue,
            providerCanonicalEnglishRetrievalText: nil,
            providerCanonicalEnglishRetrievalTextTokenCheck: [:],
            providerOriginalLanguageTextPreserved: true,
            providerUnsafeFallbackTriggered: true,
            providerBuildTimings: nil
        )

        let reasons = MultilingualRetrievalE2EEvaluation.classifyLiveModeFailureReasons(
            providerIndexing: indexing,
            projection: projection
        )
        XCTAssertTrue(reasons.contains("enricher_missing_carrier"))
        XCTAssertTrue(reasons.contains("unsafe_fallback_without_carrier"))
        XCTAssertTrue(reasons.contains("offer_object_missing_english_projection"))

        let failures = MultilingualRetrievalE2EEvaluation.evaluateLiveProviderIndexing(
            scenario: ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer,
            providerIndexing: indexing,
            projection: projection
        )
        XCTAssertFalse(failures.isEmpty)
    }

    func testLiveModePassClassificationWhenCarrierObjectAndServiceAreasPresent() {
        let projection = MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit(
            nodeID: MultilingualRetrievalE2EFixtureBuilder.NodeID.roofer,
            offerID: MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer,
            canonicalEnglishRetrievalText: "roofer roof estimate aurora newmarket",
            offerDetailUsesEnglishOnlyRetrievalProjection: true,
            offerObjectUsesEnglishOnlyRetrievalProjection: true,
            serviceAreas: ["Aurora", "Newmarket"],
            offerObjectSearchableText: "roofer roof repair",
            preservedChineseInSourceBlocks: true
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingSnapshot(
            runMode: MultilingualRetrievalE2EMode.livePublishEnricher.rawValue,
            providerIndexingSource: "liveEnricherCorePath",
            providerEnricherAttempted: true,
            providerEnricherSucceeded: true,
            providerEnricherFailureReason: nil,
            providerCanonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
            providerCanonicalEnglishRetrievalTextTokenCheck: ["roofer": true, "aurora": true],
            providerOriginalLanguageTextPreserved: true,
            providerUnsafeFallbackTriggered: false,
            providerBuildTimings: nil
        )

        XCTAssertTrue(
            MultilingualRetrievalE2EEvaluation.classifyLiveModePass(
                providerIndexing: indexing,
                projection: projection,
                selectedOfferID: MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer,
                scenario: ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer
            )
        )
    }

    func testForbiddenMissingFactsClassification() {
        let triggered = MultilingualRetrievalE2EEvaluation.classifyForbiddenMissingFacts(
            missingFacts: ["Need the user's budget", "Need exact time slot"],
            forbiddenCategories: ["location", "budget", "time"]
        )
        XCTAssertTrue(triggered.contains("budget"))
        XCTAssertTrue(triggered.contains("time"))
    }

    // MARK: - Helpers

    private func makeMockSearchIntent(
        scenario: ExchangeMultilingualRetrievalE2EScenario
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "roofer",
            transactionIntent: .hire,
            places: [
                .init(normalizedText: "Aurora", aliases: ["Aurora"], confidence: 0.95, isHard: true)
            ],
            timeConstraints: [
                .init(kind: .specific, text: "tomorrow at 2pm")
            ],
            commercialConstraints: [
                .init(kind: .budget, key: "maxBudget", value: "200", isHard: true)
            ],
            broadRecallTokens: ["roof estimate", "roofer"],
            semanticConcepts: ["roof estimate", "roofer"],
            rawUserText: scenario.rawUserText,
            extractedRoute: .init(
                routeClassRaw: ExchangeIntent.QueryIntentClass.providerSearch.rawValue,
                surfacePreferenceRaw: "offer",
                targetKindRaw: "provider",
                routeConfidence: 0.9,
                routeRationale: "mock-local"
            ),
            canonicalEnglishSearchText:
                "find roofer in Aurora for roof estimate tomorrow at 2pm budget under 200"
        )
    }

    private func makeMockThread(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> ExchangeThread {
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: scenario.rawUserText,
            objective: scenario.rawUserText
        )
        let facets = ExchangeIntentFacets(
            searchIntent: searchIntent,
            targetKind: .provider,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer
        )
        return ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            state: .matchFound(
                .init(
                    candidateCount: 1,
                    summary: "mock-local match",
                    selectedOfferID: scenario.expectedSelectedOfferID
                )
            )
        )
    }

    private func makeMockRooferMatch(thread: ExchangeThread, scenario: ExchangeMultilingualRetrievalE2EScenario) -> ExchangeMatch {
        ExchangeMatch(
            threadID: thread.id,
            counterpartyID: scenario.expectedSelectedNodeID,
            scope: .offer,
            offerID: scenario.expectedSelectedOfferID,
            matchedOfferIDs: [scenario.expectedSelectedOfferID],
            strength: .strong,
            score: 0.95
        )
    }

    private func makeMockNoisyMatch(thread: ExchangeThread) -> ExchangeMatch {
        ExchangeMatch(
            threadID: thread.id,
            counterpartyID: MultilingualRetrievalE2EFixtureBuilder.NodeID.noisyHome,
            scope: .offer,
            offerID: MultilingualRetrievalE2EFixtureBuilder.OfferID.noisyHome,
            matchedOfferIDs: [MultilingualRetrievalE2EFixtureBuilder.OfferID.noisyHome],
            strength: .weak,
            score: 0.40
        )
    }

    private func makeMockUI(scenario: ExchangeMultilingualRetrievalE2EScenario) -> AppSearchSmokeUIProjectionSnapshot {
        AppSearchSmokeUIProjectionSnapshot(
            selectedOfferID: scenario.expectedSelectedOfferID,
            matchedOffersByNode: [
                scenario.expectedSelectedNodeID: [scenario.expectedSelectedOfferID]
            ],
            preferredMatchCounterpartyID: scenario.expectedSelectedNodeID,
            preferredMatchOfferID: scenario.expectedSelectedOfferID,
            cardOfferID: scenario.expectedSelectedOfferID,
            visiblePublicProfileID: "profile-multilingual-roofer-zh",
            surfaceLead: "offer",
            displaySearchQuery: scenario.rawUserText,
            capturedRequestText: scenario.rawUserText,
            visibleSummary: "Matched roofing provider",
            threadTitle: scenario.rawUserText
        )
    }

    private func makeMockRankingTrace(
        scenario: ExchangeMultilingualRetrievalE2EScenario
    ) -> [ExchangeRetrievalDebugTrace.RankingRow] {
        [
            ExchangeRetrievalDebugTrace.RankingRow(
                documentID: "doc-roofer-object",
                docKind: ExchangeRetrievalDocument.DocKind.offerObject.rawValue,
                surfaceType: "offer",
                counterpartyID: scenario.expectedSelectedNodeID,
                nodeID: scenario.expectedSelectedNodeID,
                publicProfileID: "profile-multilingual-roofer-zh",
                offerID: scenario.expectedSelectedOfferID,
                bm25Rank: 1,
                vectorRank: 1,
                objectLaneRank: nil,
                bm25Score: 0.9,
                vectorScore: 0.9,
                objectLaneScore: 0.0,
                surfaceBias: 0,
                docKindBias: 0,
                finalScore: 0.95
            )
        ]
    }

    func testResultTierPassTrueFederationHighConfidence() {
        let publication = makeFullFacadePublication(
            federationRoundTripSucceeded: true,
            usesOverlayFallbackForRoofer: false
        )
        let outcome = MultilingualE2EResultTierResolver.resolve(
            runMode: .fullFacadePublishPath,
            passed: true,
            publication: publication
        )
        XCTAssertEqual(outcome.resultTier, .passTrueFederation)
        XCTAssertTrue(outcome.federationVerified)
        XCTAssertFalse(outcome.overlayFallbackUsed)
        XCTAssertEqual(outcome.productionParityConfidence, .high)
    }

    func testResultTierPassOverlayFallbackMediumConfidence() {
        let publication = makeFullFacadePublication(
            federationRoundTripSucceeded: false,
            usesOverlayFallbackForRoofer: true
        )
        let outcome = MultilingualE2EResultTierResolver.resolve(
            runMode: .fullFacadePublishPath,
            passed: true,
            publication: publication
        )
        XCTAssertEqual(outcome.resultTier, .passOverlayFallback)
        XCTAssertFalse(outcome.federationVerified)
        XCTAssertTrue(outcome.overlayFallbackUsed)
        XCTAssertEqual(outcome.productionParityConfidence, .medium)
    }

    func testResultTierFailDespiteFederationSucceeded() {
        let publication = makeFullFacadePublication(
            federationRoundTripSucceeded: true,
            usesOverlayFallbackForRoofer: false
        )
        let outcome = MultilingualE2EResultTierResolver.resolve(
            runMode: .fullFacadePublishPath,
            passed: false,
            publication: publication
        )
        XCTAssertEqual(outcome.resultTier, .fail)
        XCTAssertFalse(outcome.federationVerified)
        XCTAssertEqual(outcome.productionParityConfidence, .failed)
    }

    func testTripleComparisonIncludesResultTiers() {
        let scenario = ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer
        let baseline = makeRunSnapshot(
            scenario: scenario,
            runMode: .injectedCarrierFixture,
            selectedOfferID: scenario.expectedSelectedOfferID,
            serviceAreas: ["Aurora", "Newmarket"],
            carrier: "roofer roof estimate aurora",
            objectEnglish: true,
            totalMs: 1000,
            forbiddenMissingFacts: [],
            uiText: scenario.rawUserText
        )
        let live = makeRunSnapshot(
            scenario: scenario,
            runMode: .livePublishEnricher,
            selectedOfferID: scenario.expectedSelectedOfferID,
            serviceAreas: ["Aurora", "Newmarket"],
            carrier: "roofer roof estimate aurora",
            objectEnglish: true,
            totalMs: 1200,
            forbiddenMissingFacts: [],
            uiText: scenario.rawUserText
        )
        let fullFacade = makeRunSnapshot(
            scenario: scenario,
            runMode: .fullFacadePublishPath,
            selectedOfferID: scenario.expectedSelectedOfferID,
            serviceAreas: ["Aurora", "Newmarket"],
            carrier: "roofer roof estimate aurora",
            objectEnglish: true,
            totalMs: 1800,
            forbiddenMissingFacts: [],
            uiText: scenario.rawUserText,
            fullFacadePublicationOverride: makeFullFacadePublication(
                federationRoundTripSucceeded: false,
                usesOverlayFallbackForRoofer: true
            )
        )

        let comparison = MultilingualRetrievalE2ETripleComparisonBuilder.compare(
            baseline: baseline,
            live: live,
            fullFacade: fullFacade
        )
        XCTAssertEqual(comparison.resultTierByMode[baseline.runMode], MultilingualE2EResultTier.passLocal.rawValue)
        XCTAssertEqual(comparison.resultTierByMode[live.runMode], MultilingualE2EResultTier.passLocal.rawValue)
        XCTAssertEqual(comparison.resultTierByMode[fullFacade.runMode], MultilingualE2EResultTier.passOverlayFallback.rawValue)
        XCTAssertFalse(comparison.federationVerified)
        XCTAssertTrue(comparison.overlayFallbackUsed)
        XCTAssertTrue(comparison.summaryLines.contains(where: { $0.contains("resultTier") }))
    }

    private func makeFullFacadePublication(
        federationRoundTripSucceeded: Bool,
        usesOverlayFallbackForRoofer: Bool
    ) -> MultilingualRetrievalE2EFullFacadePublicationSnapshot {
        MultilingualRetrievalE2EFullFacadePublicationSnapshot(
            fullFacadeProfileSaveAttempted: true,
            fullFacadeProfileSaveSucceeded: true,
            fullFacadeOfferSaveAttempted: true,
            fullFacadeOfferSaveSucceeded: true,
            fullFacadePublishAttempted: true,
            fullFacadePublishSucceeded: true,
            publishRetrievalDocumentsAttempted: true,
            publishRetrievalDocumentsSucceeded: true,
            federationRoundTripAttempted: true,
            federationRoundTripSucceeded: federationRoundTripSucceeded,
            federationRoundTripFailureReason: federationRoundTripSucceeded ? nil : "probe_failed",
            retrievalDocumentsPublishedCount: 6,
            retrievalDocumentsRecoveredCount: 6,
            canonicalEnglishCarrierBeforePublish: nil,
            canonicalEnglishCarrierAfterPublish: "roofer roof estimate aurora",
            offerObjectCarrierAfterPublish: "roofer roof repair",
            serviceAreasAfterPublish: ["Aurora", "Newmarket"],
            originalChinesePreservedAfterPublish: true,
            usesOverlayFallbackForRoofer: usesOverlayFallbackForRoofer
        )
    }


    private func makeRunSnapshot(
        scenario: ExchangeMultilingualRetrievalE2EScenario,
        runMode: MultilingualRetrievalE2EMode,
        selectedOfferID: String?,
        serviceAreas: [String],
        carrier: String?,
        objectEnglish: Bool,
        totalMs: Int,
        forbiddenMissingFacts: [String],
        uiText: String,
        failureReasonsOverride: [String]? = nil,
        fullFacadePublicationOverride: MultilingualRetrievalE2EFullFacadePublicationSnapshot? = nil
    ) -> MultilingualE2ERunSnapshot {
        let indexing = MultilingualRetrievalE2EProviderIndexingSnapshot(
            runMode: runMode.rawValue,
            providerIndexingSource: runMode == .injectedCarrierFixture ? "injectedCarrierFixture" : "liveEnricherCorePath",
            providerEnricherAttempted: runMode == .livePublishEnricher,
            providerEnricherSucceeded: runMode == .livePublishEnricher && carrier != nil,
            providerEnricherFailureReason: nil,
            providerCanonicalEnglishRetrievalText: carrier,
            providerCanonicalEnglishRetrievalTextTokenCheck: ["roofer": true],
            providerOriginalLanguageTextPreserved: true,
            providerUnsafeFallbackTriggered: false,
            providerBuildTimings: nil,
            fullFacadePublication: fullFacadePublicationOverride
        )
        let passed = failureReasonsOverride?.isEmpty ?? true
        let failures = failureReasonsOverride ?? []
        let publication = fullFacadePublicationOverride
        let outcome = MultilingualE2EResultTierResolver.resolve(
            runMode: runMode,
            passed: passed,
            publication: publication
        )
        return MultilingualE2ERunSnapshot(
            scenarioID: scenario.id,
            runMode: runMode.rawValue,
            rawUserText: scenario.rawUserText,
            detectedRequestLanguage: "zh",
            canonicalEnglishSearchText: "roofer aurora estimate",
            objectType: "roofer",
            routeClass: "providerSearch",
            targetKind: "provider",
            surfacePreference: "offer",
            placeTexts: ["Aurora"],
            budgetMax: 200,
            timeTexts: ["tomorrow at 2pm"],
            providerIndexing: indexing,
            providerCanonicalEnglishRetrievalText: carrier,
            offerDetailUsesEnglishOnlyRetrievalProjection: objectEnglish,
            offerObjectUsesEnglishOnlyRetrievalProjection: objectEnglish,
            serviceAreas: serviceAreas,
            topCandidates: [],
            selectedCandidateID: scenario.expectedSelectedNodeID,
            selectedOfferID: selectedOfferID,
            objectLaneEvidence: [],
            fitEngineSelectedCandidateID: scenario.expectedSelectedNodeID,
            secondHalf: .init(
                missingFacts: [],
                forbiddenMissingFactsTriggered: forbiddenMissingFacts,
                clarificationText: nil,
                clarificationLanguage: nil,
                compareSucceeded: false
            ),
            displaySearchQuery: uiText,
            capturedRequestText: uiText,
            visibleSummary: "summary",
            threadTitle: uiText,
            timings: .init(intentMs: 100, indexingMs: 10, retrievalMs: 100, secondHalfMs: 50, totalMs: totalMs),
            passed: passed,
            warnings: [],
            failureReasons: failures,
            resultTier: outcome.resultTier.rawValue,
            federationVerified: outcome.federationVerified,
            overlayFallbackUsed: outcome.overlayFallbackUsed,
            productionParityConfidence: outcome.productionParityConfidence.rawValue
        )
    }
    func testFullFacadeModeFailureWhenCarrierLostAfterPublish() {
        let projection = MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit(
            nodeID: MultilingualRetrievalE2EFixtureBuilder.NodeID.roofer,
            offerID: MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer,
            canonicalEnglishRetrievalText: nil,
            offerDetailUsesEnglishOnlyRetrievalProjection: false,
            offerObjectUsesEnglishOnlyRetrievalProjection: false,
            serviceAreas: [],
            offerObjectSearchableText: nil,
            preservedChineseInSourceBlocks: true
        )
        let publication = MultilingualRetrievalE2EFullFacadePublicationSnapshot(
            fullFacadeProfileSaveAttempted: true,
            fullFacadeProfileSaveSucceeded: true,
            fullFacadeOfferSaveAttempted: true,
            fullFacadeOfferSaveSucceeded: true,
            fullFacadePublishAttempted: true,
            fullFacadePublishSucceeded: true,
            publishRetrievalDocumentsAttempted: true,
            publishRetrievalDocumentsSucceeded: true,
            federationRoundTripAttempted: true,
            federationRoundTripSucceeded: false,
            federationRoundTripFailureReason: "published_node_not_in_federation_search",
            retrievalDocumentsPublishedCount: 4,
            retrievalDocumentsRecoveredCount: 4,
            canonicalEnglishCarrierBeforePublish: "roofer roof estimate aurora",
            canonicalEnglishCarrierAfterPublish: nil,
            offerObjectCarrierAfterPublish: nil,
            serviceAreasAfterPublish: [],
            originalChinesePreservedAfterPublish: true,
            usesOverlayFallbackForRoofer: true
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingSnapshot(
            runMode: MultilingualRetrievalE2EMode.fullFacadePublishPath.rawValue,
            providerIndexingSource: "fullFacadePublishPathWithOverlay",
            providerEnricherAttempted: true,
            providerEnricherSucceeded: false,
            providerEnricherFailureReason: nil,
            providerCanonicalEnglishRetrievalText: nil,
            providerCanonicalEnglishRetrievalTextTokenCheck: [:],
            providerOriginalLanguageTextPreserved: true,
            providerUnsafeFallbackTriggered: true,
            providerBuildTimings: nil,
            fullFacadePublication: publication
        )

        let reasons = MultilingualRetrievalE2EEvaluation.classifyFullFacadeModeFailureReasons(
            providerIndexing: indexing,
            projection: projection
        )
        XCTAssertTrue(reasons.contains("carrier_lost_after_publish"))
        XCTAssertTrue(reasons.contains("enricher_missing_carrier"))

        let failures = MultilingualRetrievalE2EEvaluation.evaluateFullFacadeProviderIndexing(
            scenario: ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer,
            providerIndexing: indexing,
            projection: projection
        )
        XCTAssertTrue(failures.contains(where: { $0.contains("carrier existed before publish") }))
    }

    func testFullFacadeModePassWhenCarrierObjectAndServiceAreasSurvive() {
        let projection = MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit(
            nodeID: MultilingualRetrievalE2EFixtureBuilder.NodeID.roofer,
            offerID: MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer,
            canonicalEnglishRetrievalText: "roofer roof estimate aurora newmarket",
            offerDetailUsesEnglishOnlyRetrievalProjection: true,
            offerObjectUsesEnglishOnlyRetrievalProjection: true,
            serviceAreas: ["Aurora", "Newmarket"],
            offerObjectSearchableText: "roofer roof repair",
            preservedChineseInSourceBlocks: true
        )
        let publication = MultilingualRetrievalE2EFullFacadePublicationSnapshot(
            fullFacadeProfileSaveAttempted: true,
            fullFacadeProfileSaveSucceeded: true,
            fullFacadeOfferSaveAttempted: true,
            fullFacadeOfferSaveSucceeded: true,
            fullFacadePublishAttempted: true,
            fullFacadePublishSucceeded: true,
            publishRetrievalDocumentsAttempted: true,
            publishRetrievalDocumentsSucceeded: true,
            federationRoundTripAttempted: true,
            federationRoundTripSucceeded: true,
            federationRoundTripFailureReason: nil,
            retrievalDocumentsPublishedCount: 6,
            retrievalDocumentsRecoveredCount: 6,
            canonicalEnglishCarrierBeforePublish: nil,
            canonicalEnglishCarrierAfterPublish: projection.canonicalEnglishRetrievalText,
            offerObjectCarrierAfterPublish: projection.offerObjectSearchableText,
            serviceAreasAfterPublish: projection.serviceAreas,
            originalChinesePreservedAfterPublish: true,
            usesOverlayFallbackForRoofer: false
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingSnapshot(
            runMode: MultilingualRetrievalE2EMode.fullFacadePublishPath.rawValue,
            providerIndexingSource: "fullFacadePublishPath",
            providerEnricherAttempted: true,
            providerEnricherSucceeded: true,
            providerEnricherFailureReason: nil,
            providerCanonicalEnglishRetrievalText: projection.canonicalEnglishRetrievalText,
            providerCanonicalEnglishRetrievalTextTokenCheck: ["roofer": true, "aurora": true],
            providerOriginalLanguageTextPreserved: true,
            providerUnsafeFallbackTriggered: false,
            providerBuildTimings: nil,
            fullFacadePublication: publication
        )

        XCTAssertTrue(
            MultilingualRetrievalE2EEvaluation.classifyFullFacadeModePass(
                providerIndexing: indexing,
                projection: projection,
                selectedOfferID: MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer,
                scenario: ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer
            )
        )
    }

    func testTripleComparisonDetectsFirstModeMissingCarrier() {
        XCTAssertEqual(
            MultilingualRetrievalE2ETripleComparisonBuilder.firstModeMissingCarrier(
                baselineHasCarrier: true,
                liveHasCarrier: false,
                fullFacadeHasCarrier: true
            ),
            MultilingualRetrievalE2EMode.livePublishEnricher.rawValue
        )

        let scenario = ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer
        let baseline = makeRunSnapshot(
            scenario: scenario,
            runMode: .injectedCarrierFixture,
            selectedOfferID: scenario.expectedSelectedOfferID,
            serviceAreas: ["Aurora", "Newmarket"],
            carrier: "roofer roof estimate aurora",
            objectEnglish: true,
            totalMs: 1000,
            forbiddenMissingFacts: [],
            uiText: scenario.rawUserText
        )
        let live = makeRunSnapshot(
            scenario: scenario,
            runMode: .livePublishEnricher,
            selectedOfferID: scenario.expectedSelectedOfferID,
            serviceAreas: ["Aurora", "Newmarket"],
            carrier: nil,
            objectEnglish: false,
            totalMs: 1200,
            forbiddenMissingFacts: [],
            uiText: scenario.rawUserText
        )
        let fullFacade = makeRunSnapshot(
            scenario: scenario,
            runMode: .fullFacadePublishPath,
            selectedOfferID: scenario.expectedSelectedOfferID,
            serviceAreas: ["Aurora", "Newmarket"],
            carrier: "roofer roof estimate aurora",
            objectEnglish: true,
            totalMs: 1800,
            forbiddenMissingFacts: [],
            uiText: scenario.rawUserText
        )

        let comparison = MultilingualRetrievalE2ETripleComparisonBuilder.compare(
            baseline: baseline,
            live: live,
            fullFacade: fullFacade
        )
        XCTAssertEqual(
            comparison.firstModeMissingProviderCarrier,
            MultilingualRetrievalE2EMode.livePublishEnricher.rawValue
        )
    }

    func testFederationRoundTripFailureIsWarningWhenOverlayFallbackSucceeds() {
        let publication = MultilingualRetrievalE2EFullFacadePublicationSnapshot(
            fullFacadeProfileSaveAttempted: true,
            fullFacadeProfileSaveSucceeded: true,
            fullFacadeOfferSaveAttempted: true,
            fullFacadeOfferSaveSucceeded: true,
            fullFacadePublishAttempted: true,
            fullFacadePublishSucceeded: true,
            publishRetrievalDocumentsAttempted: true,
            publishRetrievalDocumentsSucceeded: true,
            federationRoundTripAttempted: true,
            federationRoundTripSucceeded: false,
            federationRoundTripFailureReason: "network",
            retrievalDocumentsPublishedCount: 4,
            retrievalDocumentsRecoveredCount: 4,
            canonicalEnglishCarrierBeforePublish: nil,
            canonicalEnglishCarrierAfterPublish: "roofer roof estimate aurora",
            offerObjectCarrierAfterPublish: "roofer roof repair",
            serviceAreasAfterPublish: ["Aurora", "Newmarket"],
            originalChinesePreservedAfterPublish: true,
            usesOverlayFallbackForRoofer: true
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingSnapshot(
            runMode: MultilingualRetrievalE2EMode.fullFacadePublishPath.rawValue,
            providerIndexingSource: "fullFacadePublishPathWithOverlay",
            providerEnricherAttempted: true,
            providerEnricherSucceeded: true,
            providerEnricherFailureReason: nil,
            providerCanonicalEnglishRetrievalText: "roofer roof estimate aurora",
            providerCanonicalEnglishRetrievalTextTokenCheck: ["roofer": true],
            providerOriginalLanguageTextPreserved: true,
            providerUnsafeFallbackTriggered: false,
            providerBuildTimings: nil,
            fullFacadePublication: publication
        )
        let warnings = MultilingualRetrievalE2EEvaluation.evaluateFullFacadeWarnings(
            providerIndexing: indexing,
            secondHalf: .init(
                missingFacts: [],
                forbiddenMissingFactsTriggered: [],
                clarificationText: nil,
                clarificationLanguage: nil,
                compareSucceeded: false
            ),
            ui: makeMockUI(scenario: ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer),
            baselineTimingMs: nil
        )
        XCTAssertTrue(warnings.contains("federation round-trip failed but overlay fallback succeeded"))
    }

    func testLocalSeededModesDoNotRequireLegacyRetrievalSmokeManifest() {
        for mode in MultilingualRetrievalE2EMode.allCases {
            XCTAssertFalse(
                mode.requiresLegacyRetrievalSmokeManifest,
                "expected \(mode.rawValue) to skip legacy retrieval-smoke manifest preflight"
            )
        }
    }

    func testMultilingualPreflightOptionsSkipManifestForLocalSeededModes() {
        let options = ExchangeRetrievalE2EGate.PreflightOptions.multilingualLocalSeeded(
            reason: "local_debug_seeded_modes(fullFacadePublishPath,injectedCarrierFixture,livePublishEnricher)"
        )
        XCTAssertFalse(options.requiresRetrievalSmokeManifest)
        XCTAssertEqual(options.manifestSkippedLogTag, "MultilingualE2E")
        XCTAssertEqual(
            options.manifestSkippedReason,
            "local_debug_seeded_modes(fullFacadePublishPath,injectedCarrierFixture,livePublishEnricher)"
        )
    }

}

#endif
