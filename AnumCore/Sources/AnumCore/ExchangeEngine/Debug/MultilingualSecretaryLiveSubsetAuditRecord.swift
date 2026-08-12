import Foundation

#if DEBUG

public struct MultilingualSecretaryLiveSubsetAuditRecord: Sendable, Hashable, Codable {
    public var fixtureID: String
    public var vertical: String
    public var languagePair: String
    public var runMode: String
    public var rawUserText: String
    public var rawProviderText: String
    public var canonicalEnglishSearchText: String?
    public var providerCanonicalEnglishRetrievalText: String?
    public var selectedOfferID: String?
    public var expectedOfferID: String
    public var topCandidates: [MultilingualE2ERetrievedCandidateRow]
    public var noisyOutrankingDetected: Bool
    public var forbiddenMissingFactsTriggered: [String]
    public var displaySearchQuery: String?
    public var capturedRequestText: String?
    public var timings: MultilingualE2ETimingSnapshot
    public var resultTier: String
    public var productionParityConfidence: String
    public var federationVerified: Bool
    public var overlayFallbackUsed: Bool
    public var passed: Bool
    public var warnings: [String]
    public var failureReasons: [String]
    public var carrierLost: Bool
    public var failureCategories: [String]

    public init(
        fixtureID: String,
        vertical: String,
        languagePair: String,
        runMode: String,
        rawUserText: String,
        rawProviderText: String,
        canonicalEnglishSearchText: String?,
        providerCanonicalEnglishRetrievalText: String?,
        selectedOfferID: String?,
        expectedOfferID: String,
        topCandidates: [MultilingualE2ERetrievedCandidateRow],
        noisyOutrankingDetected: Bool,
        forbiddenMissingFactsTriggered: [String],
        displaySearchQuery: String?,
        capturedRequestText: String?,
        timings: MultilingualE2ETimingSnapshot,
        resultTier: String,
        productionParityConfidence: String,
        federationVerified: Bool,
        overlayFallbackUsed: Bool,
        passed: Bool,
        warnings: [String],
        failureReasons: [String],
        carrierLost: Bool,
        failureCategories: [String] = []
    ) {
        self.fixtureID = fixtureID
        self.vertical = vertical
        self.languagePair = languagePair
        self.runMode = runMode
        self.rawUserText = rawUserText
        self.rawProviderText = rawProviderText
        self.canonicalEnglishSearchText = canonicalEnglishSearchText
        self.providerCanonicalEnglishRetrievalText = providerCanonicalEnglishRetrievalText
        self.selectedOfferID = selectedOfferID
        self.expectedOfferID = expectedOfferID
        self.topCandidates = topCandidates
        self.noisyOutrankingDetected = noisyOutrankingDetected
        self.forbiddenMissingFactsTriggered = forbiddenMissingFactsTriggered
        self.displaySearchQuery = displaySearchQuery
        self.capturedRequestText = capturedRequestText
        self.timings = timings
        self.resultTier = resultTier
        self.productionParityConfidence = productionParityConfidence
        self.federationVerified = federationVerified
        self.overlayFallbackUsed = overlayFallbackUsed
        self.passed = passed
        self.warnings = warnings
        self.failureReasons = failureReasons
        self.carrierLost = carrierLost
        self.failureCategories = failureCategories
    }
}

public struct MultilingualSecretaryLiveSubsetSummary: Sendable, Hashable, Codable {
    public var passCount: Int
    public var failCount: Int
    public var warningCount: Int
    public var averageTotalLatencyMs: Int
    public var slowestFixtureID: String?
    public var slowestTotalLatencyMs: Int
    public var carrierLossCount: Int
    public var noisyOutrankingCount: Int
    public var forbiddenMissingFactCount: Int
    public var failuresByFixture: [String: [String]]
    public var categoryCounts: [String: Int]
    public var fixturesByCategory: [String: [String]]
    public var slowestByCategory: [String: String]

    public init(
        passCount: Int,
        failCount: Int,
        warningCount: Int,
        averageTotalLatencyMs: Int,
        slowestFixtureID: String?,
        slowestTotalLatencyMs: Int,
        carrierLossCount: Int,
        noisyOutrankingCount: Int,
        forbiddenMissingFactCount: Int,
        failuresByFixture: [String: [String]],
        categoryCounts: [String: Int] = [:],
        fixturesByCategory: [String: [String]] = [:],
        slowestByCategory: [String: String] = [:]
    ) {
        self.passCount = passCount
        self.failCount = failCount
        self.warningCount = warningCount
        self.averageTotalLatencyMs = averageTotalLatencyMs
        self.slowestFixtureID = slowestFixtureID
        self.slowestTotalLatencyMs = slowestTotalLatencyMs
        self.carrierLossCount = carrierLossCount
        self.noisyOutrankingCount = noisyOutrankingCount
        self.forbiddenMissingFactCount = forbiddenMissingFactCount
        self.failuresByFixture = failuresByFixture
        self.categoryCounts = categoryCounts
        self.fixturesByCategory = fixturesByCategory
        self.slowestByCategory = slowestByCategory
    }
}

public struct MultilingualSecretaryLiveSubsetBatchSummaryArtifact: Sendable, Hashable, Codable {
    public var summary: MultilingualSecretaryLiveSubsetSummary
    public var generatedAt: String

    public init(summary: MultilingualSecretaryLiveSubsetSummary, generatedAt: String) {
        self.summary = summary
        self.generatedAt = generatedAt
    }
}

public struct MultilingualSecretaryLiveSubsetBatchResult: Sendable, Hashable, Codable {
    public var records: [MultilingualSecretaryLiveSubsetAuditRecord]
    public var summary: MultilingualSecretaryLiveSubsetSummary
    public var aggregateReportText: String
    public var artifactPath: String?
    public var summaryArtifactPath: String?

    public init(
        records: [MultilingualSecretaryLiveSubsetAuditRecord],
        summary: MultilingualSecretaryLiveSubsetSummary,
        aggregateReportText: String,
        artifactPath: String?,
        summaryArtifactPath: String? = nil
    ) {
        self.records = records
        self.summary = summary
        self.aggregateReportText = aggregateReportText
        self.artifactPath = artifactPath
        self.summaryArtifactPath = summaryArtifactPath
    }
}

#endif
