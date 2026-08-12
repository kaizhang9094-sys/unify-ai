import Foundation

#if DEBUG

public struct MultilingualE2ERetrievedCandidateRow: Sendable, Hashable, Codable {
    public var rank: Int
    public var counterpartyID: String
    public var offerID: String?
    public var score: Double
    public var docKind: String?
    public var objectLaneScore: Double?

    public init(
        rank: Int,
        counterpartyID: String,
        offerID: String?,
        score: Double,
        docKind: String?,
        objectLaneScore: Double?
    ) {
        self.rank = rank
        self.counterpartyID = counterpartyID
        self.offerID = offerID
        self.score = score
        self.docKind = docKind
        self.objectLaneScore = objectLaneScore
    }
}

public struct MultilingualE2ESecondHalfSnapshot: Sendable, Hashable, Codable {
    public var missingFacts: [String]
    public var forbiddenMissingFactsTriggered: [String]
    public var clarificationText: String?
    public var clarificationLanguage: String?
    public var compareSucceeded: Bool

    public init(
        missingFacts: [String],
        forbiddenMissingFactsTriggered: [String],
        clarificationText: String?,
        clarificationLanguage: String?,
        compareSucceeded: Bool
    ) {
        self.missingFacts = missingFacts
        self.forbiddenMissingFactsTriggered = forbiddenMissingFactsTriggered
        self.clarificationText = clarificationText
        self.clarificationLanguage = clarificationLanguage
        self.compareSucceeded = compareSucceeded
    }

    public static var skipped: Self {
        Self(
            missingFacts: [],
            forbiddenMissingFactsTriggered: [],
            clarificationText: nil,
            clarificationLanguage: nil,
            compareSucceeded: false
        )
    }
}

public struct MultilingualE2ETimingSnapshot: Sendable, Hashable, Codable {
    public var intentMs: Int
    public var indexingMs: Int
    public var retrievalMs: Int
    public var secondHalfMs: Int
    public var totalMs: Int

    public init(
        intentMs: Int,
        indexingMs: Int,
        retrievalMs: Int,
        secondHalfMs: Int,
        totalMs: Int
    ) {
        self.intentMs = intentMs
        self.indexingMs = indexingMs
        self.retrievalMs = retrievalMs
        self.secondHalfMs = secondHalfMs
        self.totalMs = totalMs
    }
}

public struct MultilingualE2ERunSnapshot: Sendable, Hashable, Codable {
    public var scenarioID: String
    public var runMode: String
    public var rawUserText: String
    public var detectedRequestLanguage: String?
    public var canonicalEnglishSearchText: String?
    public var objectType: String?
    public var routeClass: String?
    public var targetKind: String?
    public var surfacePreference: String?
    public var placeTexts: [String]
    public var budgetMax: Int?
    public var timeTexts: [String]
    public var providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot
    public var providerCanonicalEnglishRetrievalText: String?
    public var offerDetailUsesEnglishOnlyRetrievalProjection: Bool
    public var offerObjectUsesEnglishOnlyRetrievalProjection: Bool
    public var serviceAreas: [String]
    public var topCandidates: [MultilingualE2ERetrievedCandidateRow]
    public var selectedCandidateID: String?
    public var selectedOfferID: String?
    public var objectLaneEvidence: [String]
    public var fitEngineSelectedCandidateID: String?
    public var secondHalf: MultilingualE2ESecondHalfSnapshot
    public var displaySearchQuery: String?
    public var capturedRequestText: String?
    public var visibleSummary: String?
    public var threadTitle: String?
    public var timings: MultilingualE2ETimingSnapshot
    public var passed: Bool
    public var warnings: [String]
    public var failureReasons: [String]
    public var resultTier: String
    public var federationVerified: Bool
    public var overlayFallbackUsed: Bool
    public var productionParityConfidence: String

    public init(
        scenarioID: String,
        runMode: String,
        rawUserText: String,
        detectedRequestLanguage: String?,
        canonicalEnglishSearchText: String?,
        objectType: String?,
        routeClass: String?,
        targetKind: String?,
        surfacePreference: String?,
        placeTexts: [String],
        budgetMax: Int?,
        timeTexts: [String],
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        providerCanonicalEnglishRetrievalText: String?,
        offerDetailUsesEnglishOnlyRetrievalProjection: Bool,
        offerObjectUsesEnglishOnlyRetrievalProjection: Bool,
        serviceAreas: [String],
        topCandidates: [MultilingualE2ERetrievedCandidateRow],
        selectedCandidateID: String?,
        selectedOfferID: String?,
        objectLaneEvidence: [String],
        fitEngineSelectedCandidateID: String?,
        secondHalf: MultilingualE2ESecondHalfSnapshot,
        displaySearchQuery: String?,
        capturedRequestText: String?,
        visibleSummary: String?,
        threadTitle: String?,
        timings: MultilingualE2ETimingSnapshot,
        passed: Bool,
        warnings: [String],
        failureReasons: [String],
        resultTier: String,
        federationVerified: Bool,
        overlayFallbackUsed: Bool,
        productionParityConfidence: String
    ) {
        self.scenarioID = scenarioID
        self.runMode = runMode
        self.rawUserText = rawUserText
        self.detectedRequestLanguage = detectedRequestLanguage
        self.canonicalEnglishSearchText = canonicalEnglishSearchText
        self.objectType = objectType
        self.routeClass = routeClass
        self.targetKind = targetKind
        self.surfacePreference = surfacePreference
        self.placeTexts = placeTexts
        self.budgetMax = budgetMax
        self.timeTexts = timeTexts
        self.providerIndexing = providerIndexing
        self.providerCanonicalEnglishRetrievalText = providerCanonicalEnglishRetrievalText
        self.offerDetailUsesEnglishOnlyRetrievalProjection = offerDetailUsesEnglishOnlyRetrievalProjection
        self.offerObjectUsesEnglishOnlyRetrievalProjection = offerObjectUsesEnglishOnlyRetrievalProjection
        self.serviceAreas = serviceAreas
        self.topCandidates = topCandidates
        self.selectedCandidateID = selectedCandidateID
        self.selectedOfferID = selectedOfferID
        self.objectLaneEvidence = objectLaneEvidence
        self.fitEngineSelectedCandidateID = fitEngineSelectedCandidateID
        self.secondHalf = secondHalf
        self.displaySearchQuery = displaySearchQuery
        self.capturedRequestText = capturedRequestText
        self.visibleSummary = visibleSummary
        self.threadTitle = threadTitle
        self.timings = timings
        self.passed = passed
        self.warnings = warnings
        self.failureReasons = failureReasons
        self.resultTier = resultTier
        self.federationVerified = federationVerified
        self.overlayFallbackUsed = overlayFallbackUsed
        self.productionParityConfidence = productionParityConfidence
    }
}

public struct MultilingualE2EPairBatchResult: Sendable, Hashable, Codable {
    public var baseline: MultilingualE2EBatchResult
    public var live: MultilingualE2EBatchResult
    public var comparison: MultilingualRetrievalE2EPairComparison
    public var comparisonArtifactPath: String?

    public init(
        baseline: MultilingualE2EBatchResult,
        live: MultilingualE2EBatchResult,
        comparison: MultilingualRetrievalE2EPairComparison,
        comparisonArtifactPath: String?
    ) {
        self.baseline = baseline
        self.live = live
        self.comparison = comparison
        self.comparisonArtifactPath = comparisonArtifactPath
    }
}

public struct MultilingualE2ETripleBatchResult: Sendable, Hashable, Codable {
    public var baseline: MultilingualE2EBatchResult
    public var live: MultilingualE2EBatchResult
    public var fullFacade: MultilingualE2EBatchResult
    public var comparison: MultilingualRetrievalE2ETripleComparison
    public var comparisonArtifactPath: String?

    public init(
        baseline: MultilingualE2EBatchResult,
        live: MultilingualE2EBatchResult,
        fullFacade: MultilingualE2EBatchResult,
        comparison: MultilingualRetrievalE2ETripleComparison,
        comparisonArtifactPath: String?
    ) {
        self.baseline = baseline
        self.live = live
        self.fullFacade = fullFacade
        self.comparison = comparison
        self.comparisonArtifactPath = comparisonArtifactPath
    }
}

public struct MultilingualE2EBatchResult: Sendable, Hashable, Codable {
    public var runs: [MultilingualE2ERunSnapshot]
    public var aggregateReportText: String
    public var artifactPath: String?

    public init(
        runs: [MultilingualE2ERunSnapshot],
        aggregateReportText: String,
        artifactPath: String?
    ) {
        self.runs = runs
        self.aggregateReportText = aggregateReportText
        self.artifactPath = artifactPath
    }
}

public struct MultilingualRetrievalE2ELiveRunContext: Sendable {
    public var thread: ExchangeThread
    public var searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    public var sortedMatches: [ExchangeMatch]
    public var rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow]
    public var selectedOfferID: String?
    public var selectedCandidateID: String?
    public var objectLaneActive: Bool
    public var secondHalf: MultilingualE2ESecondHalfSnapshot
    public var ui: AppSearchSmokeUIProjectionSnapshot
    public var timings: MultilingualE2ETimingSnapshot

    public init(
        thread: ExchangeThread,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        sortedMatches: [ExchangeMatch],
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        selectedOfferID: String?,
        selectedCandidateID: String?,
        objectLaneActive: Bool,
        secondHalf: MultilingualE2ESecondHalfSnapshot,
        ui: AppSearchSmokeUIProjectionSnapshot,
        timings: MultilingualE2ETimingSnapshot
    ) {
        self.thread = thread
        self.searchIntent = searchIntent
        self.sortedMatches = sortedMatches
        self.rankingTrace = rankingTrace
        self.selectedOfferID = selectedOfferID
        self.selectedCandidateID = selectedCandidateID
        self.objectLaneActive = objectLaneActive
        self.secondHalf = secondHalf
        self.ui = ui
        self.timings = timings
    }
}

#endif
