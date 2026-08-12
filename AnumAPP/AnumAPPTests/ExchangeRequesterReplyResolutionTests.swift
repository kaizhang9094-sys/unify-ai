import XCTest
@testable import AnumCore

final class ExchangeRequesterReplyResolutionTests: XCTestCase {
    private let engine = ExchangeRequesterReplyResolutionEngine()

    /// Request text that clearly asks for price, availability, and location/mode (per resolver heuristics).
    private let fullProbeRequest =
        "Find piano lessons in Aurora. I need weekday evening availability, hourly rate, and whether we meet online, in-studio, or in-person."

    private func resolve(
        request: String,
        reply: String,
        hasFreshProviderAnswer: Bool = true,
        secondHalfState: ExchangeSecondHalfState = .matchFound
    ) -> ExchangeRequesterPauseFrame {
        engine.resolve(
            input: ExchangeRequesterReplyResolutionEngine.Input(
                requestTextBlob: request,
                knownFactsLines: [],
                clarifiedFactsLines: [],
                unresolvedIssuesLines: [],
                qualificationMissingFacts: [],
                latestCounterpartyReplyText: reply,
                hasFreshProviderAnswer: hasFreshProviderAnswer,
                qualificationTier: .promising,
                secondHalfState: secondHalfState,
                isThreadExplicitlyCompleted: false
            )
        )
    }

    func test_fullProviderAnswer_decisionReadyPause() {
        let reply =
            "I teach piano in Aurora. My rate is $60/hour. I’m available weekday evenings. Lessons can be at my studio or online."
        let frame = resolve(request: fullProbeRequest, reply: reply)

        let answeredBlob = frame.answeredFacts.joined(separator: " ").lowercased()
        XCTAssertTrue(answeredBlob.contains("price") || answeredBlob.contains("rate"))
        XCTAssertTrue(answeredBlob.contains("availability") || answeredBlob.contains("schedule"))
        XCTAssertTrue(answeredBlob.contains("location") || answeredBlob.contains("format") || answeredBlob.contains("studio"))

        XCTAssertEqual(frame.pauseReason, .waitingForRequesterDecision)
        XCTAssertTrue(
            frame.recommendationLine.lowercased().contains("decide")
                || frame.recommendationLine.lowercased().contains("review"),
            "recommendationLine=\(frame.recommendationLine)"
        )
        XCTAssertTrue(frame.canContinueOnReply)
        XCTAssertTrue(frame.resolvedMissingLabels.contains("price"))
    }

    func test_partialAnswer_priceOnly_needsClarification() {
        let reply = "I teach piano in Aurora and charge $60/hour."
        let frame = resolve(request: fullProbeRequest, reply: reply)

        XCTAssertTrue(frame.answeredFacts.joined(separator: " ").lowercased().contains("price")
            || frame.answeredFacts.joined(separator: " ").lowercased().contains("rate"))
        XCTAssertFalse(frame.stillMissingFacts.isEmpty, "Availability/location should remain thin: \(frame.stillMissingFacts)")
        XCTAssertEqual(frame.pauseReason, .needsOneMoreClarification)
    }

    /// Second-half re-run after a fuller provider body should tighten the pause (no stale “partial” semantics).
    func test_sequentialReplySimulation_fullAnswerAfterPartial_reducesStillMissing() {
        let partialReply = "I teach piano in Aurora and charge $60/hour."
        let partialFrame = resolve(request: fullProbeRequest, reply: partialReply)
        XCTAssertFalse(partialFrame.stillMissingFacts.isEmpty)

        let fullReply =
            "I teach piano in Aurora. My rate is $60/hour. I’m available weekday evenings. Lessons can be at my studio or online."
        let fullFrame = resolve(request: fullProbeRequest, reply: fullReply)

        XCTAssertTrue(
            fullFrame.stillMissingFacts.count <= partialFrame.stillMissingFacts.count,
            "partialStill=\(partialFrame.stillMissingFacts) fullStill=\(fullFrame.stillMissingFacts)"
        )
        XCTAssertGreaterThanOrEqual(fullFrame.answeredFacts.count, partialFrame.answeredFacts.count)
    }

    func test_weakWrongFit_weakeningAndWeakFitPause() {
        let request = "Looking for a piano teacher in Aurora for my child."
        let reply = "I only teach guitar and I’m based in Toronto."
        let frame = resolve(request: request, reply: reply)

        XCTAssertFalse(frame.weakeningSignals.isEmpty, "Expected weakening signals: \(frame.weakeningSignals)")
        XCTAssertEqual(frame.pauseReason, .weakFitKeepSearching)
    }

    func test_providerQuestion_waitsForRequesterInput() {
        let reply = "I can help. Do you prefer online or in-person lessons?"
        let frame = resolve(request: fullProbeRequest, reply: reply)

        XCTAssertFalse(frame.providerQuestions.isEmpty)
        XCTAssertEqual(frame.pauseReason, .waitingForRequesterInput)
    }

    func test_commitment_commitmentReview() {
        let reply =
            "I can guarantee Tuesday 2pm if you sign a 6-month contract and pay a deposit."
        let frame = resolve(request: fullProbeRequest, reply: reply)

        XCTAssertFalse(frame.commitmentSignals.isEmpty, frame.commitmentSignals.description)
        XCTAssertEqual(frame.pauseReason, .commitmentReview)
    }

    func test_projection_exposesPauseOnDecisionPacketAndReviewCard() {
        let rawPause = resolve(
            request: fullProbeRequest,
            reply: "I teach piano in Aurora. My rate is $60/hour. I’m available weekday evenings. Lessons can be at my studio or online."
        )
        guard let sanitized = ExchangeRequesterReviewPresentation.sanitizedPauseFrame(rawPause) else {
            XCTFail("Expected sanitized pause frame")
            return
        }

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
            requesterPauseFrame: sanitized
        )

        let projection = ExchangeSecondHalfProjection(coordinatorResult: coordinatorResult)
        XCTAssertEqual(projection.requesterPauseFrame?.pauseReason, sanitized.pauseReason)
        XCTAssertEqual(projection.decisionPacket?.requesterPause?.pauseReason, sanitized.pauseReason)
        XCTAssertEqual(projection.requesterReviewCard?.pauseFrame?.pauseReason, sanitized.pauseReason)
    }

    func test_sanitizedPauseUserFacingStrings_noInternalLeakage() {
        let raw = resolve(
            request: fullProbeRequest,
            reply: "I teach piano in Aurora. My rate is $60/hour. I’m available weekday evenings. Lessons can be at my studio or online."
        )
        guard let frame = ExchangeRequesterReviewPresentation.sanitizedPauseFrame(raw) else {
            XCTFail("Expected sanitized pause frame")
            return
        }

        var blob = [
            frame.summaryLine,
            frame.recommendationLine,
            frame.nextActionLabel
        ]
        blob.append(contentsOf: frame.answeredFacts)
        blob.append(contentsOf: frame.stillMissingFacts)
        blob.append(contentsOf: frame.providerQuestions)
        blob.append(contentsOf: frame.commitmentSignals)
        blob.append(contentsOf: frame.weakeningSignals)

        let joined = blob.joined(separator: " ").lowercased()
        let forbidden = [
            "knownfacts",
            "unresolvedissues",
            "qualificationstatus",
            "pass 2",
            "pass 3",
            "anchoring score",
            "offer row present",
            "row present"
        ]
        for phrase in forbidden {
            XCTAssertFalse(
                joined.contains(phrase),
                "Unexpected internal phrase in pause copy: \(phrase) joined=\(joined)"
            )
        }
    }
}
