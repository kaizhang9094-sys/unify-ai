import XCTest
@testable import AnumCore

final class ExchangeDraftComposerClarificationNoiseFilterTests: XCTestCase {
    func test_buyerAskClarification_dropsStructuredMemoryGarbageFromUnresolvedIssues() {
        let composer = ExchangeDraftComposer()
        let input = ExchangeDraftComposer.Input(
            role: .requester,
            action: .askClarification,
            priors: .empty,
            style: .default,
            operatingMemory: .empty,
            counterpartyName: nil,
            subjectMatter: "3 bedroom GTA home purchase with VTB financing",
            requestedItems: [],
            clarifiedFacts: [],
            unresolvedIssues: [
                "Are published seller surfaces anchored on this snapshot?",
                "Please confirm VTB eligibility for suitable listings.",
                "What hardened timeline should I rely on?",
                "Could you clarify capacity/throughput specifics?"
            ],
            customInstructions: nil
        )
        let draft = composer.compose(input: input)
        let lower = draft.body.lowercased()
        XCTAssertFalse(lower.contains("published seller surface"))
        XCTAssertFalse(lower.contains("anchored snapshot"))
        XCTAssertFalse(lower.contains("throughput"))
        XCTAssertFalse(lower.contains("hardened timeline"))
        XCTAssertTrue(lower.contains("vtb") || lower.contains("financing"))
    }
}
