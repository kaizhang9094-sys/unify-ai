import XCTest
@testable import AnumCore

#if DEBUG

final class MultilingualSecretaryLiveSubsetTests: XCTestCase {
    func testLiveSubsetSelectsExactly10Fixtures() {
        let fixtures = MultilingualSecretaryLiveSubsetFixtures.all
        XCTAssertEqual(fixtures.count, 10)

        let verticals = Set(fixtures.map(\.vertical))
        XCTAssertEqual(verticals, Set(MultilingualSecretaryLiveSubsetFixtures.verticals))

        let pairs = Set(fixtures.map(\.languagePair))
        XCTAssertEqual(pairs, Set(MultilingualSecretaryLiveSubsetFixtures.languagePairs))

        let ids = Set(fixtures.map(\.id))
        XCTAssertEqual(ids.count, 10)
    }

    func testLiveSubsetAuditDetectsNoisyOutranking() {
        let record = MultilingualSecretaryLiveSubsetAuditRecord(
            fixtureID: "matrix.plumber.zhUserZhProvider",
            vertical: "plumber",
            languagePair: "zhUserZhProvider",
            runMode: MultilingualRetrievalE2EMode.livePublishEnricher.rawValue,
            rawUserText: "test user",
            rawProviderText: "test provider",
            canonicalEnglishSearchText: "emergency plumber",
            providerCanonicalEnglishRetrievalText: "plumber emergency pipe repair",
            selectedOfferID: "offer-matrix-noisy-plumber-zhUserZhProvider",
            expectedOfferID: "offer-matrix-plumber-zhUserZhProvider",
            topCandidates: [],
            noisyOutrankingDetected: true,
            forbiddenMissingFactsTriggered: [],
            displaySearchQuery: "test user",
            capturedRequestText: "test user",
            timings: .init(intentMs: 1, indexingMs: 2, retrievalMs: 3, secondHalfMs: 4, totalMs: 10),
            resultTier: MultilingualE2EResultTier.fail.rawValue,
            productionParityConfidence: MultilingualE2EProductionParityConfidence.failed.rawValue,
            federationVerified: false,
            overlayFallbackUsed: false,
            passed: false,
            warnings: [],
            failureReasons: ["noisy profile/offer outranked exact object offer"],
            carrierLost: false
        )

        XCTAssertTrue(record.noisyOutrankingDetected)
        XCTAssertTrue(
            MultilingualSecretaryLiveSubsetReport.noisyOutrankingDetected(failureReasons: record.failureReasons)
        )
    }

    func testLiveSubsetSummaryAggregatesFailures() {
        let records = [
            makeRecord(
                fixtureID: "matrix.roofer.zhUserZhProvider",
                passed: true,
                totalMs: 100,
                failureReasons: [],
                warnings: [],
                carrierLost: false,
                noisy: false,
                forbidden: []
            ),
            makeRecord(
                fixtureID: "matrix.cleaner.mixedUserMixedProvider",
                passed: false,
                totalMs: 300,
                failureReasons: ["noisy profile/offer outranked exact object offer"],
                warnings: ["carrier token check failed: cleaning"],
                carrierLost: true,
                noisy: true,
                forbidden: ["budget"]
            ),
            makeRecord(
                fixtureID: "matrix.plumber.zhUserZhProvider",
                passed: false,
                totalMs: 200,
                failureReasons: ["forbidden second-half missing facts: location"],
                warnings: [],
                carrierLost: false,
                noisy: false,
                forbidden: ["location"]
            )
        ]

        let summary = MultilingualSecretaryLiveSubsetReport.summarize(records)
        XCTAssertEqual(summary.passCount, 1)
        XCTAssertEqual(summary.failCount, 2)
        XCTAssertEqual(summary.warningCount, 1)
        XCTAssertEqual(summary.averageTotalLatencyMs, 200)
        XCTAssertEqual(summary.slowestFixtureID, "matrix.cleaner.mixedUserMixedProvider")
        XCTAssertEqual(summary.slowestTotalLatencyMs, 300)
        XCTAssertEqual(summary.carrierLossCount, 1)
        XCTAssertEqual(summary.noisyOutrankingCount, 1)
        XCTAssertEqual(summary.forbiddenMissingFactCount, 2)
        XCTAssertEqual(summary.failuresByFixture.count, 2)
        XCTAssertTrue(summary.failuresByFixture.keys.contains("matrix.cleaner.mixedUserMixedProvider"))
    }

    private func makeRecord(
        fixtureID: String,
        passed: Bool,
        totalMs: Int,
        failureReasons: [String],
        warnings: [String],
        carrierLost: Bool,
        noisy: Bool,
        forbidden: [String]
    ) -> MultilingualSecretaryLiveSubsetAuditRecord {
        MultilingualSecretaryLiveSubsetAuditRecord(
            fixtureID: fixtureID,
            vertical: "test",
            languagePair: "zhUserZhProvider",
            runMode: MultilingualRetrievalE2EMode.livePublishEnricher.rawValue,
            rawUserText: "user",
            rawProviderText: "provider",
            canonicalEnglishSearchText: "english",
            providerCanonicalEnglishRetrievalText: carrierLost ? nil : "carrier",
            selectedOfferID: nil,
            expectedOfferID: "expected-offer",
            topCandidates: [],
            noisyOutrankingDetected: noisy,
            forbiddenMissingFactsTriggered: forbidden,
            displaySearchQuery: "user",
            capturedRequestText: "user",
            timings: .init(intentMs: 1, indexingMs: 1, retrievalMs: 1, secondHalfMs: 1, totalMs: totalMs),
            resultTier: passed ? MultilingualE2EResultTier.passLocal.rawValue : MultilingualE2EResultTier.fail.rawValue,
            productionParityConfidence: passed
                ? MultilingualE2EProductionParityConfidence.medium.rawValue
                : MultilingualE2EProductionParityConfidence.failed.rawValue,
            federationVerified: false,
            overlayFallbackUsed: false,
            passed: passed,
            warnings: warnings,
            failureReasons: failureReasons,
            carrierLost: carrierLost
        )
    }
    func testFailureClusteringProviderCarrierLossWhenCarrierLost() {
        let record = makeRecord(
            fixtureID: "matrix.plumber.zhUserZhProvider",
            passed: false,
            totalMs: 100,
            failureReasons: ["provider canonicalEnglishRetrievalText missing"],
            warnings: [],
            carrierLost: true,
            noisy: false,
            forbidden: []
        )
        let categories = MultilingualSecretaryLiveSubsetFailureClustering.categorize(record)
        XCTAssertTrue(categories.contains(.providerCarrierLoss))
    }

    func testFailureClusteringUserIntentCarrierLossWhenCanonicalEnglishSearchMissing() {
        var record = makeRecord(
            fixtureID: "matrix.roofer.zhUserZhProvider",
            passed: false,
            totalMs: 100,
            failureReasons: ["canonicalEnglishSearchText missing"],
            warnings: [],
            carrierLost: false,
            noisy: false,
            forbidden: []
        )
        record.rawUserText = "帮我找一个屋顶工"
        record.canonicalEnglishSearchText = nil
        let categories = MultilingualSecretaryLiveSubsetFailureClustering.categorize(record)
        XCTAssertTrue(categories.contains(.userIntentCarrierLoss))
    }

    func testFailureClusteringNoisyOutranking() {
        let record = makeRecord(
            fixtureID: "matrix.cleaner.zhUserZhProvider",
            passed: false,
            totalMs: 100,
            failureReasons: ["noisy profile/offer outranked exact object offer"],
            warnings: [],
            carrierLost: false,
            noisy: true,
            forbidden: []
        )
        let categories = MultilingualSecretaryLiveSubsetFailureClustering.categorize(record)
        XCTAssertTrue(categories.contains(.noisyOutranking))
    }

    func testFailureClusteringForbiddenMissingFacts() {
        let record = makeRecord(
            fixtureID: "matrix.roofer.mixedUserMixedProvider",
            passed: false,
            totalMs: 100,
            failureReasons: ["forbidden second-half missing facts: budget,time"],
            warnings: [],
            carrierLost: false,
            noisy: false,
            forbidden: ["budget", "time"]
        )
        let categories = MultilingualSecretaryLiveSubsetFailureClustering.categorize(record)
        XCTAssertTrue(categories.contains(.forbiddenMissingFacts))
    }

    func testFailureClusterSummaryGroupsMultipleCategoriesForOneRow() {
        let record = makeRecord(
            fixtureID: "matrix.postpartumCaregiver.mixedUserMixedProvider",
            passed: false,
            totalMs: 35_000,
            failureReasons: [
                "noisy profile/offer outranked exact object offer",
                "provider canonicalEnglishRetrievalText missing"
            ],
            warnings: ["full facade used overlay fallback"],
            carrierLost: true,
            noisy: true,
            forbidden: []
        )
        var overlayRecord = record
        overlayRecord.overlayFallbackUsed = true
        let categories = MultilingualSecretaryLiveSubsetFailureClustering.categorize(
            overlayRecord,
            config: .init(slowScenarioThresholdMs: 30_000)
        )
        XCTAssertTrue(categories.contains(.noisyOutranking))
        XCTAssertTrue(categories.contains(.providerCarrierLoss))
        XCTAssertTrue(categories.contains(.federationOverlayFallback))
        XCTAssertTrue(categories.contains(.slowScenario))

        let summary = MultilingualSecretaryLiveSubsetReport.summarize([overlayRecord])
        XCTAssertGreaterThanOrEqual(summary.categoryCounts.count, 4)
        XCTAssertEqual(
            summary.fixturesByCategory[MultilingualSecretaryLiveSubsetFailureCategory.noisyOutranking.rawValue],
            ["matrix.postpartumCaregiver.mixedUserMixedProvider"]
        )
    }

}

#endif
