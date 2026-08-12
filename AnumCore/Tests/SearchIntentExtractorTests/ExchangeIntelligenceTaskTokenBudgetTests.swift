import XCTest
@testable import AnumCore

final class ExchangeIntelligenceTaskTokenBudgetTests: XCTestCase {
    func testSearchIntentExtractionTokenBudgetIsAtLeast320() {
        XCTAssertGreaterThanOrEqual(
            ExchangeIntelligenceTaskTokenBudget.searchIntentExtractionMaxTokens,
            320
        )
    }

    func testSearchIntentExtractionTokenBudgetIs320() {
        XCTAssertEqual(
            ExchangeIntelligenceTaskTokenBudget.searchIntentExtractionMaxTokens,
            320
        )
    }
}
