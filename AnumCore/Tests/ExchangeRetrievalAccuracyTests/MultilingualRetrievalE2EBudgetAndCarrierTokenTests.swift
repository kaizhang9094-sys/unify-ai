import XCTest
@testable import AnumCore

#if DEBUG

final class MultilingualRetrievalE2EBudgetAndCarrierTokenTests: XCTestCase {
    func testExtractBudgetMaxFromCommercialBudgetField() {
        let intent = makeIntent(
            commercialConstraints: [
                .init(kind: .budget, key: "budget", value: "under 200", isHard: true)
            ]
        )
        XCTAssertEqual(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent), 200)
    }

    func testExtractBudgetMaxFromHardConstraintUnder200() {
        let intent = makeIntent(
            hardConstraints: [
                .init(key: "budget", value: "under 200", isHardConstraint: true)
            ]
        )
        XCTAssertEqual(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent), 200)
    }

    func testExtractBudgetMaxFromCanonicalEnglishBudgetUnder200() {
        let intent = makeIntent(
            canonicalEnglishSearchText: "Find a roofer in Aurora for roof estimate tomorrow with budget under 200"
        )
        XCTAssertEqual(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent), 200)
    }

    func testExtractBudgetMaxIgnoresBareNumberWithoutBudgetCue() {
        let intent = makeIntent(
            canonicalEnglishSearchText: "Find a roofer in Aurora tomorrow at 2pm"
        )
        XCTAssertNil(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent))
    }

    func testAppraisalSatisfiesEstimateCarrierTokenGroup() {
        let lowered = "find roofer in aurora for roof appraisal tomorrow budget under 200"
        XCTAssertTrue(
            MultilingualEnglishCarrierTokenEquivalence.isSatisfied(expectedToken: "estimate", in: lowered)
        )
    }

    func testEvaluateCanonicalIntentAcceptsAppraisalForEstimateToken() {
        let scenario = ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer
        let searchIntent = makeIntent(
            commercialConstraints: [
                .init(kind: .budget, key: "budget", value: "under 200", isHard: true)
            ],
            timeConstraints: [
                .init(kind: .specific, text: "tomorrow at 2pm")
            ],
            places: [
                .init(normalizedText: "Aurora", aliases: ["Aurora"], confidence: 0.95, isHard: true)
            ],
            canonicalEnglishSearchText:
                "Find a roofer in Aurora for a roof appraisal tomorrow at 2pm with budget under 200"
        )
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
        let thread = ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            state: .drafting
        )

        let failures = MultilingualRetrievalE2EEvaluation.evaluateCanonicalIntent(
            scenario: scenario,
            searchIntent: searchIntent,
            thread: thread
        )

        XCTAssertFalse(
            failures.contains(where: { $0.contains("missing token=estimate") }),
            failures.joined(separator: "; ")
        )
        XCTAssertFalse(
            failures.contains(where: { $0.contains("budget max missing") }),
            failures.joined(separator: "; ")
        )
    }

    func testExtractBudgetMaxDelegatesToProductionHelper() {
        let intent = makeIntent(canonicalEnglishSearchText: "tomorrow at 2 under 200")
        XCTAssertEqual(
            MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent),
            ExchangeBudgetConstraintExtractor.extractBudgetMax(from: intent)
        )
    }


    func testStructuredEnglishFallbackCountsAsCarrierSuccessInAudit() {
        let diagnostics = ProviderSurfaceEnrichmentDiagnostics(
            attemptedLLM: true,
            source: .deterministicStructuredEnglish,
            failureReason: .timeout
        )
        XCTAssertTrue(
            MultilingualRetrievalE2EProviderIndexingAudit.enricherProducedEnglishCarrier(
                diagnostics: diagnostics,
                carrier: "roofing, Aurora, Free estimate",
                projection: nil
            )
        )
        XCTAssertFalse(
            MultilingualRetrievalE2EProviderIndexingAudit.unsafeFallbackTriggered(
                surface: makeIntentForAudit(),
                diagnostics: diagnostics,
                carrier: "roofing, Aurora, Free estimate"
            )
        )
    }

    private func makeIntentForAudit() -> ExchangeIndexedProviderSurface {
        ExchangeIndexedProviderSurfaceBuilder().build(
            profile: MultilingualRetrievalE2EFixtureBuilder.rawRooferEntities().profile,
            offers: [MultilingualRetrievalE2EFixtureBuilder.rawRooferEntities().offer]
        )
    }


    private func makeIntent(
        commercialConstraints: [ExchangeIntentFacets.StructuredCommercialConstraint] = [],
        hardConstraints: [ExchangeIntent.Constraint] = [],
        timeConstraints: [ExchangeIntentFacets.StructuredTimeConstraint] = [],
        places: [ExchangeIntentFacets.StructuredPlace] = [],
        canonicalEnglishSearchText: String? = nil
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "roofer",
            places: places,
            timeConstraints: timeConstraints,
            commercialConstraints: commercialConstraints,
            hardConstraints: hardConstraints,
            rawUserText: "mock",
            canonicalEnglishSearchText: canonicalEnglishSearchText
        )
    }

    func testExtractBudgetMaxUnder200() {
        let intent = makeIntent(canonicalEnglishSearchText: "under 200")
        XCTAssertEqual(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent), 200)
    }

    func testExtractBudgetMaxTomorrowAt2Under200() {
        let intent = makeIntent(canonicalEnglishSearchText: "tomorrow at 2 under 200")
        XCTAssertEqual(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent), 200)
    }

    func testExtractBudgetMaxTomorrowAt2ReturnsNil() {
        let intent = makeIntent(canonicalEnglishSearchText: "tomorrow at 2")
        XCTAssertNil(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent))
    }

    func testExtractBudgetMaxMay25At2pmReturnsNil() {
        let intent = makeIntent(canonicalEnglishSearchText: "May 25 at 2pm")
        XCTAssertNil(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent))
    }

    func testExtractBudgetMaxBudgetIsDollar200() {
        let intent = makeIntent(canonicalEnglishSearchText: "budget is $200")
        XCTAssertEqual(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent), 200)
    }

    func testExtractBudgetMaxLessThan200Dollars() {
        let intent = makeIntent(canonicalEnglishSearchText: "less than 200 dollars")
        XCTAssertEqual(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent), 200)
    }

    func testExtractBudgetMaxRooferScenarioWithTimeAndBudget() {
        let intent = makeIntent(
            canonicalEnglishSearchText: "roof estimate tomorrow at 2 in Aurora under 200"
        )
        XCTAssertEqual(MultilingualRetrievalE2EEvaluation.extractBudgetMax(from: intent), 200)
    }
}

#endif
