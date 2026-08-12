import XCTest
@testable import AnumCore

/// Regression: requester-role `.askClarification` must not mean “ask the provider” when no counterparty/profile/offer anchor exists.
final class ExchangeSecondHalfRequesterRecipientAnchorGateTests: XCTestCase {

    func test_coordinator_whenNoRecipientAnchor_replacesAskClarification_withRequestUserInput() {
        let coordinator = ExchangeSecondHalfCoordinator()
        let context = fixtureRequesterBugContext(selectedCounterpartyID: nil, surfacedCandidateCount: 0)

        let result = coordinator.evaluate(context: context)

        XCTAssertEqual(result.plan.selectedAction, .requestUserInput)
        XCTAssertEqual(result.nextState, .requesterReview)
        XCTAssertNil(result.draft)
        XCTAssertTrue(
            result.plan.rationale.lowercased().contains("refine")
                || result.plan.rationale.lowercased().contains("no matching seller")
                || result.plan.rationale.lowercased().contains("anchor")
        )
    }

    func test_coordinator_whenRecipientAnchored_keepsAskClarification_path() {
        let coordinator = ExchangeSecondHalfCoordinator()
        var context = fixtureRequesterBugContext(selectedCounterpartyID: "fixture-cp-1", surfacedCandidateCount: 0)
        context.selectedPublicProfileID = nil
        context.selectedOfferID = nil

        let result = coordinator.evaluate(context: context)

        XCTAssertEqual(result.plan.selectedAction, .askClarification)
        XCTAssertEqual(result.nextState, .awaitingProviderClarification)
    }

    func test_coordinator_whenWeakCandidatesSurfacedButNothingSelected_blocksProviderClarification() {
        let coordinator = ExchangeSecondHalfCoordinator()
        let context = fixtureRequesterBugContext(selectedCounterpartyID: nil, surfacedCandidateCount: 3)

        let result = coordinator.evaluate(context: context)

        XCTAssertEqual(result.plan.selectedAction, .requestUserInput)
        XCTAssertNil(result.draft)
    }

    func test_coordinator_whenInboundEnvelopeOnly_keepsAskClarification_path() {
        let coordinator = ExchangeSecondHalfCoordinator()
        var context = fixtureRequesterBugContext(selectedCounterpartyID: nil, surfacedCandidateCount: 0)
        context.lastInboundEnvelopeID = "fixture-inbound-envelope"

        let result = coordinator.evaluate(context: context)

        XCTAssertEqual(result.plan.selectedAction, .askClarification)
        XCTAssertNotNil(result.draft)
    }

    /// Mirrors `ExchangeFacade.secondHalfOutboundMaterialFollowUpIssues` wording that previously forced provider clarification.
    private func fixtureRequesterBugContext(
        selectedCounterpartyID: String?,
        surfacedCandidateCount: Int
    ) -> ExchangeSecondHalfExecutionContext {
        ExchangeSecondHalfExecutionContext(
            threadID: UUID(),
            role: .requester,
            currentState: .stalled,
            knownFacts: ["User requested after-school enrichment support."],
            unresolvedIssues: [
                "No viable match is anchored yet.",
                "Please confirm hourly lesson pricing availability with the provider."
            ],
            surfacedCandidateCount: surfacedCandidateCount,
            selectedCounterpartyID: selectedCounterpartyID,
            selectedPublicProfileID: nil,
            selectedOfferID: nil,
            subjectMatter: "Confirm lesson pricing availability with the tutor",
            requestedItems: ["See if they have slots and ask them about tutoring rates tomorrow."],
            clarifiedFacts: ["User requested after-school enrichment support."]
        )
    }
}
