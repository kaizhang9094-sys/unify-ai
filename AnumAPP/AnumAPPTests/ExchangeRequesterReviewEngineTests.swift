import XCTest
import AnumCore

/// Requester-side post-match review: clarification vs surface vs decline vs decision-ready.
final class ExchangeRequesterReviewEngineTests: XCTestCase {
    private let engine = ExchangeRequesterReviewEngine()
    private let policy = SecondHalfEngineTestFixtures.explicitSecondHalfPolicy()

    private func promisingWithGaps() -> ExchangeOpportunityQualification {
        ExchangeOpportunityQualification(
            qualityTier: .promising,
            missingFacts: ["Public list price", "Next available slot"],
            strengthReasons: ["Good category fit"],
            weaknessReasons: [],
            qualificationStatus: .needsClarification,
            isOneMoreClarificationWorthwhile: true
        )
    }

    func test_promisingWithMissingFacts_suggestsClarificationWhenUnderRoundLimit() {
        let input = ExchangeRequesterReviewEngine.Input(
            qualification: promisingWithGaps(),
            stance: .neutral,
            priors: .empty,
            clarificationRounds: 0,
            hasComparableAlternatives: false,
            hasFreshProviderAnswer: false,
            boundary: nil
        )
        let result = engine.evaluate(input: input, policy: policy)
        XCTAssertEqual(result.decision, .askAnotherClarification)
        XCTAssertEqual(result.suggestedAction, .askClarification)
    }

    func test_knownFactsReduceMissing_doesNotAskClarificationWhenGapsClosed() {
        let qualification = ExchangeOpportunityQualification(
            qualityTier: .promising,
            missingFacts: [],
            strengthReasons: ["Price confirmed", "Availability confirmed"],
            weaknessReasons: [],
            qualificationStatus: .qualified,
            isOneMoreClarificationWorthwhile: true
        )
        let input = ExchangeRequesterReviewEngine.Input(
            qualification: qualification,
            stance: .neutral,
            priors: .empty,
            clarificationRounds: 0,
            hasComparableAlternatives: false,
            hasFreshProviderAnswer: true,
            boundary: nil
        )
        let result = engine.evaluate(input: input, policy: policy)
        XCTAssertEqual(result.decision, .surfaceNow)
        XCTAssertEqual(result.suggestedAction, .recommendNextMove)
    }

    func test_weakOpportunity_recommendsDeclineWithoutAlternatives() {
        let qualification = ExchangeOpportunityQualification(
            qualityTier: .weak,
            missingFacts: ["Fit unclear"],
            weaknessReasons: ["Sparse counterparty signals"],
            qualificationStatus: .incomplete,
            isOneMoreClarificationWorthwhile: false
        )
        let input = ExchangeRequesterReviewEngine.Input(
            qualification: qualification,
            stance: .neutral,
            priors: .empty,
            clarificationRounds: 0,
            hasComparableAlternatives: false,
            hasFreshProviderAnswer: false,
            boundary: nil
        )
        let result = engine.evaluate(input: input, policy: policy)
        XCTAssertEqual(result.decision, .recommendDecline)
        XCTAssertEqual(result.suggestedAction, .decline)
    }

    func test_weakWithAlternatives_suggestsCompare() {
        let qualification = ExchangeOpportunityQualification(
            qualityTier: .weak,
            missingFacts: [],
            weaknessReasons: ["Low signal"],
            qualificationStatus: .incomplete,
            isOneMoreClarificationWorthwhile: false
        )
        let input = ExchangeRequesterReviewEngine.Input(
            qualification: qualification,
            stance: .neutral,
            priors: .empty,
            clarificationRounds: 0,
            hasComparableAlternatives: true,
            hasFreshProviderAnswer: false,
            boundary: nil
        )
        let result = engine.evaluate(input: input, policy: policy)
        XCTAssertEqual(result.decision, .compareOptions)
        XCTAssertEqual(result.suggestedAction, .compareOptions)
    }

    func test_promisingWithAlternativesAndFreshAnswer_surfacesInsteadOfGenericQualification() {
        let qualification = ExchangeOpportunityQualification(
            qualityTier: .strong,
            missingFacts: [],
            strengthReasons: ["Price and schedule clarified"],
            weaknessReasons: [],
            qualificationStatus: .qualified,
            isOneMoreClarificationWorthwhile: false
        )
        let input = ExchangeRequesterReviewEngine.Input(
            qualification: qualification,
            stance: .neutral,
            priors: .empty,
            clarificationRounds: 0,
            hasComparableAlternatives: true,
            hasFreshProviderAnswer: true,
            boundary: nil
        )
        let result = engine.evaluate(input: input, policy: policy)
        XCTAssertEqual(result.decision, .surfaceNow)
        XCTAssertEqual(result.suggestedAction, .recommendNextMove)
    }

    func test_decisionReady_movesTowardDecision() {
        let qualification = ExchangeOpportunityQualification(
            qualityTier: .decisionReady,
            missingFacts: [],
            strengthReasons: ["All gates passed"],
            qualificationStatus: .decisionReady,
            isOneMoreClarificationWorthwhile: false
        )
        let input = ExchangeRequesterReviewEngine.Input(
            qualification: qualification,
            stance: .neutral,
            priors: .empty,
            clarificationRounds: 0,
            hasComparableAlternatives: false,
            hasFreshProviderAnswer: false,
            boundary: nil
        )
        let result = engine.evaluate(input: input, policy: policy)
        XCTAssertEqual(result.decision, .moveTowardDecision)
        XCTAssertEqual(result.suggestedAction, .frameDecision)
    }

    func test_clarificationRoundLimitReached_doesNotSuggestAnotherClarification() {
        let input = ExchangeRequesterReviewEngine.Input(
            qualification: promisingWithGaps(),
            stance: .neutral,
            priors: .empty,
            clarificationRounds: 1,
            hasComparableAlternatives: false,
            hasFreshProviderAnswer: false,
            boundary: nil
        )
        let result = engine.evaluate(input: input, policy: policy)
        XCTAssertNotEqual(result.decision, .askAnotherClarification)
        XCTAssertEqual(result.decision, .qualifyFurther)
    }

    func test_decisionReady_takesPrecedenceOverWeakSignalsFromPriors() {
        let qualification = ExchangeOpportunityQualification(
            qualityTier: .decisionReady,
            missingFacts: [],
            strengthReasons: ["Facts complete and aligned"],
            weaknessReasons: [],
            qualificationStatus: .decisionReady,
            isOneMoreClarificationWorthwhile: false
        )
        let priors = ExchangeThreadPriors(
            priorQuestionsAsked: ["Can you confirm price?"],
            priorAnswersReceived: ["Price confirmed"],
            currentConstraints: [],
            priorNonCommitments: [],
            lastKnownRecommendation: "needs clarification"
        )
        let input = ExchangeRequesterReviewEngine.Input(
            qualification: qualification,
            stance: .neutral,
            priors: priors,
            clarificationRounds: 1,
            hasComparableAlternatives: false,
            hasFreshProviderAnswer: true,
            boundary: nil
        )
        let result = engine.evaluate(input: input, policy: policy)
        XCTAssertEqual(result.decision, .moveTowardDecision)
        XCTAssertEqual(result.suggestedAction, .frameDecision)
    }

    func test_commitmentBoundaryWithPolicy_requiresUserFraming() {
        let boundary = ExchangeCommitmentBoundary.customPricing(reason: "Tailored quote")
        let qualification = promisingWithGaps()
        let input = ExchangeRequesterReviewEngine.Input(
            qualification: qualification,
            stance: .neutral,
            priors: .empty,
            clarificationRounds: 0,
            hasComparableAlternatives: false,
            hasFreshProviderAnswer: true,
            boundary: boundary
        )
        let result = engine.evaluate(input: input, policy: policy)
        XCTAssertEqual(result.decision, .moveTowardDecision)
        XCTAssertEqual(result.suggestedAction, .frameDecision)
    }

    func test_requesterFacingCopySanitizer_rejectsInternalAgencyPhrases() {
        let polluted = """
        Anchoring score 0.82
        Offer row present for SKU-9
        knownFacts unresolvedIssues
        pass 2 pass 3
        qualificationStatus blocked
        """
        XCTAssertTrue(ExchangeRequesterReviewPresentation.containsInternalRequesterLeak(polluted))

        let cleaned = ExchangeRequesterReviewPresentation.sanitizedRecommendationBlock(polluted)
        XCTAssertNil(cleaned)

        let lines = ExchangeRequesterReviewPresentation.sanitizedStrengthReasons([
            "Anchoring score is high",
            "Matches the service you asked for"
        ])
        XCTAssertEqual(lines, ["Matches the service you asked for"])
    }
}
