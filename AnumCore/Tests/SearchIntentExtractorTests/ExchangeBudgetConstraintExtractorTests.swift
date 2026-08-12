import XCTest
@testable import AnumCore

final class ExchangeBudgetConstraintExtractorTests: XCTestCase {
    func testParseBudgetUnder200() {
        XCTAssertEqual(ExchangeBudgetConstraintExtractor.parseBudgetAmount(from: "under 200", requireBudgetCue: true), 200)
    }

    func testParseBudgetIsDollar200() {
        XCTAssertEqual(ExchangeBudgetConstraintExtractor.parseBudgetAmount(from: "budget is $200", requireBudgetCue: true), 200)
    }

    func testParseBudgetTomorrow2pmUnder200() {
        XCTAssertEqual(
            ExchangeBudgetConstraintExtractor.parseBudgetAmount(from: "tomorrow 2pm under 200", requireBudgetCue: true),
            200
        )
    }

    func testParseBudgetTomorrow2pmReturnsNil() {
        XCTAssertNil(ExchangeBudgetConstraintExtractor.parseBudgetAmount(from: "tomorrow 2pm", requireBudgetCue: true))
    }

    func testParseBudgetRoofEstimate200WithoutCueReturnsNil() {
        XCTAssertNil(ExchangeBudgetConstraintExtractor.parseBudgetAmount(from: "roof estimate 200", requireBudgetCue: true))
    }

    func testParseBudgetCommercialConstraintValue200() {
        XCTAssertEqual(ExchangeBudgetConstraintExtractor.parseBudgetAmount(from: "200", requireBudgetCue: false), 200)
    }

    func testExtractBudgetMaxFromCommercialBudgetConstraintValue200() {
        let intent = makeIntent(
            commercialConstraints: [
                .init(kind: .budget, key: "budget", value: "200", isHard: true)
            ]
        )
        XCTAssertEqual(ExchangeBudgetConstraintExtractor.extractBudgetMax(from: intent), 200)
    }

    func testValidatedBudgetConstraintValueRejectsTimeOnlyPhrase() {
        XCTAssertNil(ExchangeBudgetConstraintExtractor.validatedBudgetConstraintValue(from: "tomorrow at 2"))
    }

    func testEnrichCommercialConstraintsWithBudgetFromEnglishCarrier() {
        let enriched = ExchangeBudgetConstraintExtractor.enrichCommercialConstraintsWithBudget(
            commercialConstraints: [],
            hardConstraints: [],
            canonicalEnglishSearchText: "roof estimate tomorrow at 2 in Aurora under 200"
        )
        XCTAssertEqual(enriched.count, 1)
        XCTAssertEqual(enriched[0].kind, .budget)
        XCTAssertEqual(ExchangeBudgetConstraintExtractor.extractBudgetMax(from: makeIntent(
            commercialConstraints: enriched,
            canonicalEnglishSearchText: "roof estimate tomorrow at 2 in Aurora under 200"
        )), 200)
    }

    func testEnrichCommercialConstraintsSkipsWhenBudgetAlreadyPresent() {
        let existing: [ExchangeIntentFacets.StructuredCommercialConstraint] = [
            .init(kind: .budget, key: "budget", value: "under 100", isHard: true)
        ]
        let enriched = ExchangeBudgetConstraintExtractor.enrichCommercialConstraintsWithBudget(
            commercialConstraints: existing,
            hardConstraints: [],
            canonicalEnglishSearchText: "under 200"
        )
        XCTAssertEqual(enriched, existing)
    }

    private func makeIntent(
        commercialConstraints: [ExchangeIntentFacets.StructuredCommercialConstraint] = [],
        hardConstraints: [ExchangeIntent.Constraint] = [],
        canonicalEnglishSearchText: String? = nil
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "roofer",
            places: [],
            timeConstraints: [],
            commercialConstraints: commercialConstraints,
            hardConstraints: hardConstraints,
            rawUserText: "mock",
            canonicalEnglishSearchText: canonicalEnglishSearchText
        )
    }
}
