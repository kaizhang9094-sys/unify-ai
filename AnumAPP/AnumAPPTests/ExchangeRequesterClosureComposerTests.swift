import XCTest
@testable import AnumCore

final class ExchangeRequesterClosureComposerTests: XCTestCase {

    // MARK: - Timeout

    func test_composeWithTimeout_returnsNilWhenComposeIsSlow() async {
        struct SlowComposer: ExchangeRequesterClosureComposing {
            func compose(_ input: ExchangeRequesterClosureComposerInput) async throws -> ExchangeRequesterClosureComposedCopy {
                try await Task.sleep(nanoseconds: 500_000_000)
                return ExchangeRequesterClosureComposedCopy(
                    title: "Late",
                    summary: "Should not win.",
                    recommendation: "Too slow.",
                    nextActionLabel: "Wait"
                )
            }
        }

        let pause = ExchangeRequesterPauseFrame(
            summaryLine: "Paused.",
            recommendationLine: "Review.",
            nextActionLabel: "Next"
        )
        let input = ExchangeRequesterClosureComposerInput(
            requesterAskBlob: "Need piano lessons.",
            deterministicPause: pause,
            styleProfile: .default
        )

        let out = await ExchangeRequesterClosureComposeSupport.composeWithTimeout(
            composer: SlowComposer(),
            input: input,
            timeoutSeconds: 0.05
        )
        XCTAssertNil(out)
    }

    // MARK: - Validator rejects

    func test_validator_rejectsInternalPass2Leakage() {
        let pause = ExchangeRequesterPauseFrame()
        let composed = ExchangeRequesterClosureComposedCopy(
            title: "Title here",
            summary: "pass 2 says we should wait",
            recommendation: "Do something reasonable next.",
            nextActionLabel: "Next step"
        )
        XCTAssertNil(ExchangeRequesterClosureCopyValidator().validate(composed, against: pause))
    }

    func test_validator_commitmentSignals_requireWarningTone() {
        let pause = ExchangeRequesterPauseFrame(
            commitmentSignals: ["deposit mentioned"],
            summaryLine: "They mentioned money.",
            recommendationLine: "Review carefully.",
            nextActionLabel: "Review terms"
        )
        let bad = ExchangeRequesterClosureComposedCopy(
            title: "Update",
            summary: "Everything looks fine so far.",
            recommendation: "You can proceed whenever you want.",
            nextActionLabel: "Continue"
        )
        XCTAssertNil(ExchangeRequesterClosureCopyValidator().validate(bad, against: pause))
    }

    func test_validator_providerQuestions_requireUserFacingCue() {
        let pause = ExchangeRequesterPauseFrame(
            providerQuestions: ["What time works for you?"],
            summaryLine: "They asked a scheduling question.",
            recommendationLine: "Respond with your preference.",
            nextActionLabel: "Reply with your answer"
        )
        let bad = ExchangeRequesterClosureComposedCopy(
            title: "Update",
            summary: "The provider sent information.",
            recommendation: "Review the material.",
            nextActionLabel: "Next"
        )
        XCTAssertNil(ExchangeRequesterClosureCopyValidator().validate(bad, against: pause))
    }

    func test_validator_stillMissingFacts_rejectsAllClearClaims() {
        let pause = ExchangeRequesterPauseFrame(
            stillMissingFacts: ["Pricing for rush turnaround"],
            summaryLine: "Some details remain unclear.",
            recommendationLine: "Ask about pricing.",
            nextActionLabel: "Ask one more question"
        )
        let bad = ExchangeRequesterClosureComposedCopy(
            title: "Update",
            summary: "Pricing looks good — everything is clear now.",
            recommendation: "Book whenever you like.",
            nextActionLabel: "Book now"
        )
        XCTAssertNil(ExchangeRequesterClosureCopyValidator().validate(bad, against: pause))
    }

    func test_validator_weakeningSignals_rejectsOptimisticFit() {
        let pause = ExchangeRequesterPauseFrame(
            weakeningSignals: ["Hours may not match"],
            summaryLine: "Timing might not line up.",
            recommendationLine: "Compare carefully.",
            nextActionLabel: "Compare options"
        )
        let bad = ExchangeRequesterClosureComposedCopy(
            title: "Update",
            summary: "Despite the calendar notes, this looks like a strong fit overall.",
            recommendation: "If timing slips, keep searching — still worth comparing.",
            nextActionLabel: "Compare"
        )
        XCTAssertNil(ExchangeRequesterClosureCopyValidator().validate(bad, against: pause))
    }

    // MARK: - Style

    func test_mockComposer_warmVersusDirect_producesDifferentCopyBothValidate() async throws {
        let pause = ExchangeRequesterPauseFrame(
            answeredFacts: ["They confirmed weekday evenings."],
            pauseReason: .waitingForRequesterDecision,
            summaryLine: "They replied about scheduling.",
            recommendationLine: "Pick the slot that fits best.",
            nextActionLabel: "Pick your slot"
        )
        let composer = MockExchangeRequesterClosureComposer()
        let validator = ExchangeRequesterClosureCopyValidator()

        let warmProfile = ExchangeSecretaryStyleProfile(tone: .warm, warmthDirectness: .warm)
        let directProfile = ExchangeSecretaryStyleProfile(tone: .concise, warmthDirectness: .direct)

        let warmInput = ExchangeRequesterClosureComposerInput(
            requesterAskBlob: "Lessons in Aurora please.",
            latestProviderReply: "Evenings work.",
            deterministicPause: pause,
            styleProfile: warmProfile
        )
        let directInput = ExchangeRequesterClosureComposerInput(
            requesterAskBlob: "Lessons in Aurora please.",
            latestProviderReply: "Evenings work.",
            deterministicPause: pause,
            styleProfile: directProfile
        )

        let warmRaw = try await composer.compose(warmInput)
        let directRaw = try await composer.compose(directInput)

        guard let warmValid = validator.validate(warmRaw, against: pause),
              let directValid = validator.validate(directRaw, against: pause)
        else {
            return XCTFail("Expected both compositions to validate")
        }

        XCTAssertNotEqual(warmValid.title, directValid.title)
        XCTAssertNotEqual(warmValid.summary, directValid.summary)
    }

    // MARK: - Projection merge

    func test_projection_mergesValidatedComposedCopyIntoDecisionPacket() {
        let pause = ExchangeRequesterPauseFrame(
            answeredFacts: ["Published rate is $60/hour."],
            summaryLine: "They shared pricing.",
            recommendationLine: "Confirm fit before booking.",
            nextActionLabel: "Confirm fit"
        )

        let composed = ExchangeRequesterClosureComposedCopy(
            title: "Pricing snapshot",
            summary: "They quoted $60/hour — confirm it matches what you need.",
            answeredBullets: ["Rate shared"],
            stillOpenBullets: ["Compare against budget"],
            recommendation: "Confirm fit before booking.",
            nextActionLabel: "Confirm fit"
        )

        let plan = ExchangeSecondHalfPlan(
            selectedAction: .frameDecision,
            role: .requester,
            rationale: "Fixture"
        )

        let coordinatorResult = ExchangeSecondHalfCoordinator.Result(
            nextState: .matchFound,
            qualification: .empty,
            stance: .neutral,
            delta: .none,
            boundary: .safe,
            plan: plan,
            decisionFrame: nil,
            draft: nil,
            projection: ExchangeSecondHalfCoordinator.ProjectionSeed(
                stateTitle: ExchangeSecondHalfState.matchFound.displayTitle,
                roleTitle: ExchangeSecondHalfRole.requester.displayTitle,
                postureSummary: "Fixture posture",
                recommendation: "Fixture reco",
                visibleAction: plan.selectedAction,
                escalationReason: nil,
                canSurfaceNow: true
            ),
            requesterPauseFrame: pause,
            requesterClosureComposedCopy: composed
        )

        let projection = ExchangeSecondHalfProjection(coordinatorResult: coordinatorResult)

        XCTAssertEqual(projection.decisionPacket?.summary, composed.summary)
        XCTAssertEqual(projection.decisionPacket?.clarifiedFacts, composed.answeredBullets)
        XCTAssertEqual(projection.decisionPacket?.unresolvedIssues, composed.stillOpenBullets)
        XCTAssertEqual(projection.nextMove?.title, composed.nextActionLabel)
        XCTAssertEqual(projection.requesterReviewCard?.title, composed.title)
    }

    // MARK: - Coordinator isolation

    func test_composedCopyDoesNotMutatePlanOrState() {
        let plan = ExchangeSecondHalfPlan(
            selectedAction: .autoRespond,
            role: .requester,
            rationale: "Fixture"
        )

        let baseline = ExchangeSecondHalfCoordinator.Result(
            nextState: .providerReview,
            qualification: .empty,
            stance: .neutral,
            delta: .none,
            boundary: .safe,
            plan: plan,
            decisionFrame: nil,
            draft: nil,
            projection: ExchangeSecondHalfCoordinator.ProjectionSeed(
                stateTitle: ExchangeSecondHalfState.providerReview.displayTitle,
                roleTitle: ExchangeSecondHalfRole.requester.displayTitle,
                postureSummary: "p",
                recommendation: "r",
                visibleAction: plan.selectedAction,
                escalationReason: nil,
                canSurfaceNow: true
            ),
            requesterPauseFrame: ExchangeRequesterPauseFrame()
        )

        var withCopy = baseline
        withCopy.requesterClosureComposedCopy = ExchangeRequesterClosureComposedCopy(
            title: "T",
            summary: "S",
            recommendation: "R",
            nextActionLabel: "N"
        )

        XCTAssertEqual(baseline.plan.selectedAction, withCopy.plan.selectedAction)
        XCTAssertEqual(baseline.nextState, withCopy.nextState)
        XCTAssertEqual(baseline.qualification.qualityTier, withCopy.qualification.qualityTier)
    }

    // MARK: - Release-style persisted snapshot (nil composer / no composed copy)

    /// Mirrors `getThread` cached second-half projection: deterministic pause + snapshot fields
    /// must still yield non-empty user-facing copy without optional closure composer.
    func test_persistedSecondHalfSnapshot_nilComposedCopy_pauseStillUserFacingNoInternalLeak() throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Find a music tutor",
            objective: "Exercise cached display without composed closure.",
            readiness: .ready
        )
        let pause = ExchangeRequesterPauseFrame(
            summaryLine: "The provider suggested Tuesday morning or Thursday afternoon.",
            recommendationLine: "Pick the window that fits your schedule best.",
            nextActionLabel: "Reply with your preference"
        )
        let snapshot = ExchangeThread.SecondHalfSnapshot(
            schemaVersion: 2,
            currentStateRaw: ExchangeSecondHalfState.requesterReview.rawValue,
            roleRaw: ExchangeSecondHalfRole.requester.rawValue,
            decisionSummary: nil,
            recommendation: "Compare both slots against your calendar.",
            needsHumanAttention: true,
            requesterReviewSummary: "They replied with two concrete time options.",
            requesterPauseFrame: pause,
            requesterClosureComposedCopy: nil,
            lastEvaluatedAt: now,
            updatedAt: now
        )
        let thread = ExchangeThread(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            mode: .transactional,
            intent: intent,
            posture: .default,
            secondHalf: snapshot,
            state: .matchFound(.init(foundAt: now, candidateCount: 1, summary: "Fixture")),
            visibleSummary: "Need piano lessons this month."
        )

        let display = ExchangeSecondHalfUIAdapter().makeDisplayModel(
            from: snapshot,
            thread: thread,
            selectedCounterpartyName: "Pat's Music Studio"
        )

        XCTAssertNil(display.requesterClosureComposedCopy)
        XCTAssertNotNil(display.decision?.requesterPause)
        let decisionSummary = try XCTUnwrap(display.decision?.summary)
        XCTAssertFalse(decisionSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let blob = [
            display.summary,
            display.subtitle,
            display.recommendation,
            decisionSummary,
            display.decision?.recommendation,
            display.requesterReview?.subtitle,
            display.requesterReview?.title
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        XCTAssertFalse(blob.contains("pass 2"))
        XCTAssertFalse(ExchangeRequesterReviewPresentation.containsInternalRequesterLeak(blob))
    }

    // MARK: - Leak scan

    func test_displayModelSurfaces_noForbiddenComposerTokens() {
        let pause = ExchangeRequesterPauseFrame(
            answeredFacts: ["Detail"],
            summaryLine: "Summary",
            recommendationLine: "Reco with clarification option.",
            nextActionLabel: "Pick next step"
        )

        let composed = ExchangeRequesterClosureComposedCopy(
            title: "Grounded review",
            summary: "They replied — compare against what you asked.",
            answeredBullets: ["Shared detail"],
            stillOpenBullets: [],
            recommendation: "Ask one clarifying question if timing still unclear.",
            nextActionLabel: "Pick your next step"
        )

        let plan = ExchangeSecondHalfPlan(
            selectedAction: .frameDecision,
            role: .requester,
            rationale: "Fixture"
        )

        let coordinatorResult = ExchangeSecondHalfCoordinator.Result(
            nextState: .matchFound,
            qualification: .empty,
            stance: .neutral,
            delta: .none,
            boundary: .safe,
            plan: plan,
            decisionFrame: nil,
            draft: nil,
            projection: ExchangeSecondHalfCoordinator.ProjectionSeed(
                stateTitle: ExchangeSecondHalfState.matchFound.displayTitle,
                roleTitle: ExchangeSecondHalfRole.requester.displayTitle,
                postureSummary: "Fixture posture",
                recommendation: "Fixture reco",
                visibleAction: plan.selectedAction,
                escalationReason: nil,
                canSurfaceNow: true
            ),
            requesterPauseFrame: pause,
            requesterClosureComposedCopy: composed
        )

        let projection = ExchangeSecondHalfProjection(coordinatorResult: coordinatorResult)
        let display = ExchangeSecondHalfUIAdapter().makeDisplayModel(from: projection)

        let blob = [
            display.title,
            display.subtitle,
            display.summary,
            display.recommendation,
            display.hero.title,
            display.hero.subtitle,
            display.hero.statusLine,
            display.decision?.summary,
            display.decision?.recommendation,
            display.nextMove?.title,
            display.requesterReview?.title
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        let forbidden = [
            "pausereason",
            "fitmovement",
            "knownfacts",
            "pass 2",
            "planner",
            "provider answerability",
            "json",
            "anchoring score",
            "qualificationstatus"
        ]

        for token in forbidden {
            XCTAssertFalse(blob.contains(token), "Leak token \(token) in \(blob)")
        }
    }
}
