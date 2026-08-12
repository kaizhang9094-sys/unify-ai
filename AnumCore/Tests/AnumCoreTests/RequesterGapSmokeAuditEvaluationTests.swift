#if DEBUG
import XCTest

@testable import AnumCore

/// Synthetic evaluator / policy / serialization tests only — does **not** run on-device LLM smoke.
final class RequesterGapSmokeAuditEvaluationTests: XCTestCase {

    private func satisfiedTutorFixture() -> RequesterGapOnDeviceSmokeAuditFixtures.Fixture {
        RequesterGapOnDeviceSmokeAuditFixtures.all.first { $0.id == "tutor.conversation.satisfied" }!
    }

    private func satisfiedKitchenFixture() -> RequesterGapOnDeviceSmokeAuditFixtures.Fixture {
        RequesterGapOnDeviceSmokeAuditFixtures.all.first { $0.id == "contractor.kitchen_remodel.satisfied" }!
    }

    private func emptyGapOutput() -> ExchangeRequesterIntentGapReducer.Output {
        ExchangeRequesterIntentGapReducer.Output(gaps: [], combinedProviderQuestion: nil)
    }

    private func compareStub() -> ExchangeRequesterMatchCompareResult {
        ExchangeRequesterMatchCompareResult(
            missingFacts: [],
            providerQuestions: [],
            shouldAskProvider: false,
            reason: "test"
        )
    }

    // MARK: - Legacy gap scoring (unit / synthetic compare)

    func testSatisfiedEmptyFinalWithRawTaskReaskSucceeds() {
        let fixture = satisfiedTutorFixture()
        let raw = ["Do you offer conversational practice sessions?"]
        let evaluation = RequesterGapOnDeviceSmokeAuditSupport.evaluateRow(
            fixture: fixture,
            compare: compareStub(),
            rawLlmLines: raw,
            llmLines: [],
            deterministicLines: [],
            finalLines: [],
            gapOutput: emptyGapOutput()
        )
        XCTAssertTrue(evaluation.rawFalsePositiveGapOnSatisfiedCase)
        XCTAssertFalse(evaluation.finalFalsePositiveGapOnSatisfiedCase)
        XCTAssertTrue(evaluation.success)
    }

    func testSatisfiedFinalTaskReaskFails() {
        let fixture = satisfiedTutorFixture()
        let final = ["Do you offer conversational practice on weekday mornings?"]
        let evaluation = RequesterGapOnDeviceSmokeAuditSupport.evaluateRow(
            fixture: fixture,
            compare: compareStub(),
            rawLlmLines: final,
            llmLines: final,
            deterministicLines: [],
            finalLines: final,
            gapOutput: emptyGapOutput()
        )
        XCTAssertTrue(evaluation.finalFalsePositiveGapOnSatisfiedCase)
        XCTAssertFalse(evaluation.success)
    }

    func testTurnaroundGuardedAwayBeforeEvaluationIsCleanFinal() {
        let fixture = satisfiedKitchenFixture()
        let turnaround = "What is your typical turnaround time for kitchen remodels in Chaoyang?"
        let grounding = """
        task: kitchen remodel
        place: 北京 Chaoyang
        time: 下周
        credentialOrLicenseRequired: false
        """
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: [turnaround],
            shouldAskProvider: true,
            reason: "timing"
        )
        let guarded = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "kitchen remodel renovation chaoyang",
            originalRequesterMessage: fixture.userRequest,
            requesterRequirementsSummary: grounding
        )
        let guardedLines = guarded.providerQuestions
        XCTAssertTrue(guardedLines.isEmpty)

        let evaluation = RequesterGapOnDeviceSmokeAuditSupport.evaluateRow(
            fixture: fixture,
            compare: guarded,
            rawLlmLines: [turnaround],
            llmLines: guardedLines,
            deterministicLines: [],
            finalLines: guardedLines,
            gapOutput: emptyGapOutput()
        )
        XCTAssertFalse(evaluation.finalFalsePositiveGapOnSatisfiedCase)
        XCTAssertTrue(evaluation.success)
    }
}
#endif
