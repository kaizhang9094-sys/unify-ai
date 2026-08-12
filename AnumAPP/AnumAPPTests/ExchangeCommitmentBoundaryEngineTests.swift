import XCTest
import AnumCore

/// Direct coverage of `ExchangeCommitmentBoundaryEngine.classify` ordering and action matrix.
final class ExchangeCommitmentBoundaryEngineTests: XCTestCase {
    private let engine = ExchangeCommitmentBoundaryEngine()

    func test_safeClarification_askClarification() {
        let input = ExchangeCommitmentBoundaryEngine.Input(
            action: .askClarification,
            isCustomPricing: false,
            includesSensitiveDisclosure: false,
            includesScheduleCommitment: false,
            includesLegalCommercialCommitment: false,
            isPolicyException: false
        )
        let boundary = engine.classify(input: input)
        XCTAssertEqual(boundary.kind, .safe)
    }

    func test_sensitiveDisclosure_overridesSafeAction() {
        let input = ExchangeCommitmentBoundaryEngine.Input(
            action: .askClarification,
            includesSensitiveDisclosure: true,
            rationale: "Includes health details"
        )
        let boundary = engine.classify(input: input)
        XCTAssertEqual(boundary.kind, .sensitiveDisclosure)
        XCTAssertTrue(boundary.requiresHumanApproval)
        XCTAssertFalse(boundary.allowsAutonomousSending)
    }

    func test_obligationBearing_requestUserInput() {
        let input = ExchangeCommitmentBoundaryEngine.Input(
            action: .requestUserInput,
            rationale: "Needs explicit user choice"
        )
        let boundary = engine.classify(input: input)
        XCTAssertEqual(boundary.kind, .obligationBearing)
        XCTAssertTrue(boundary.requiresHumanApproval)
        XCTAssertFalse(boundary.allowsAutonomousSending)
    }

    func test_commitmentBearing_proposeTerms() {
        let input = ExchangeCommitmentBoundaryEngine.Input(
            action: .proposeTerms,
            rationale: "Drafts binding-looking terms"
        )
        let boundary = engine.classify(input: input)
        XCTAssertEqual(boundary.kind, .commitmentBearing)
        XCTAssertTrue(boundary.requiresHumanApproval)
    }

    func test_policyException() {
        let input = ExchangeCommitmentBoundaryEngine.Input(
            action: .askClarification,
            isPolicyException: true,
            rationale: "Outside published cancellation window"
        )
        let boundary = engine.classify(input: input)
        XCTAssertEqual(boundary.kind, .policyException)
        XCTAssertTrue(boundary.requiresHumanApproval)
    }

    func test_customPricing() {
        let input = ExchangeCommitmentBoundaryEngine.Input(
            action: .askClarification,
            isCustomPricing: true,
            rationale: "Non-list price"
        )
        let boundary = engine.classify(input: input)
        XCTAssertEqual(boundary.kind, .customPricing)
    }

    func test_scheduleCommitment() {
        let input = ExchangeCommitmentBoundaryEngine.Input(
            action: .askClarification,
            includesScheduleCommitment: true,
            rationale: "Commits to a ship date"
        )
        let boundary = engine.classify(input: input)
        XCTAssertEqual(boundary.kind, .scheduleCommitment)
    }

    func test_legalCommercialCommitment_takesPrecedenceOverSchedule() {
        let input = ExchangeCommitmentBoundaryEngine.Input(
            action: .askClarification,
            includesScheduleCommitment: true,
            includesLegalCommercialCommitment: true,
            rationale: "MSA signature plus delivery date"
        )
        let boundary = engine.classify(input: input)
        XCTAssertEqual(boundary.kind, .legalCommercialCommitment)
    }

    func test_commitmentBearing_acceptDecline() {
        let accept = engine.classify(
            input: ExchangeCommitmentBoundaryEngine.Input(action: .accept)
        )
        let decline = engine.classify(
            input: ExchangeCommitmentBoundaryEngine.Input(action: .decline)
        )
        XCTAssertEqual(accept.kind, .commitmentBearing)
        XCTAssertEqual(decline.kind, .commitmentBearing)
    }

    func test_markBlocked_isObligationBearingAndNeverAutonomousSend() {
        let boundary = engine.classify(
            input: ExchangeCommitmentBoundaryEngine.Input(action: .markBlocked)
        )
        XCTAssertEqual(boundary.kind, .obligationBearing)
        XCTAssertTrue(boundary.requiresHumanApproval)
        XCTAssertFalse(boundary.allowsAutonomousSending)
    }

    func test_markStalled_isObligationBearingAndNeverAutonomousSend() {
        let boundary = engine.classify(
            input: ExchangeCommitmentBoundaryEngine.Input(action: .markStalled)
        )
        XCTAssertEqual(boundary.kind, .obligationBearing)
        XCTAssertTrue(boundary.requiresHumanApproval)
        XCTAssertFalse(boundary.allowsAutonomousSending)
    }
}
