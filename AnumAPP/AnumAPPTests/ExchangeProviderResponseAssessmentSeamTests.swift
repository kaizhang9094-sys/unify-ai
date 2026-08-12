import XCTest
@testable import AnumCore

final class ExchangeProviderResponseAssessmentSeamTests: XCTestCase {
    func test_assessment_impliedFlexibleCommercialConstraint_doesNotForceFollowUp() {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: FixedAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(
                                conditionText: "vendor take-back mortgage",
                                source: .commercialConstraint,
                                status: .impliedFlexible
                            )
                        ],
                        nextMoveRecommendation: .frameDecision,
                        safeForAutonomousFollowup: false
                    )
                )
            )
        )

        var context = anchoredContext()
        context.unresolvedIssues = []
        let result = coordinator.evaluate(context: context)
        XCTAssertNotEqual(result.plan.selectedAction, .askClarification)
    }

    func test_assessment_notAnswered_triggersFollowUp_whenPolicyAllows() {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: FixedAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(
                                conditionText: "confirm seller financing",
                                source: .gapFill,
                                status: .notAnswered
                            )
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )

        let result = coordinator.evaluate(
            context: anchoredContext(clarificationRounds: 0),
            policy: .init(clarificationRoundLimit: 2)
        )
        XCTAssertEqual(result.plan.selectedAction, .askClarification)
    }

    func test_assessment_contradicted_surfacesJudgmentNotBlindFollowUp() {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: FixedAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(
                                conditionText: "small renovation budget accepted",
                                source: .commercialConstraint,
                                status: .contradicted
                            )
                        ],
                        nextMoveRecommendation: .requestUserInput,
                        requiresHumanJudgment: true,
                        safeForAutonomousFollowup: false
                    )
                )
            )
        )

        let result = coordinator.evaluate(context: anchoredContext())
        XCTAssertNotEqual(result.plan.selectedAction, .askClarification)
        XCTAssertTrue(result.plan.selectedAction == .requestUserInput || result.plan.selectedAction == .frameDecision)
    }

    func test_assessment_safeFollowUp_cannotBypassBoundaryApprovalGate() {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: FixedAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm schedule", source: .timingConstraint, status: .notAnswered)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )

        let context = anchoredContext(
            includesLegalCommercialCommitment: true,
            clarificationRounds: 0
        )
        let result = coordinator.evaluate(context: context)

        XCTAssertTrue(result.boundary.requiresHumanApproval)
    }

    func test_whenAssessmentEngineIsNil_fallbackBehaviorRemains() {
        let defaultCoordinator = ExchangeSecondHalfCoordinator()
        let explicitNilCoordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(assessmentEngine: nil)
        )

        let context = anchoredContext()
        let a = defaultCoordinator.evaluate(context: context)
        let b = explicitNilCoordinator.evaluate(context: context)

        XCTAssertEqual(a.plan.selectedAction, b.plan.selectedAction)
    }

    func test_recipientAnchorGuard_stillWins_overAssessmentFollowUpRecommendation() {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: FixedAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm pricing", source: .gapFill, status: .notAnswered)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )

        let result = coordinator.evaluate(context: unanchoredContext())
        XCTAssertEqual(result.plan.selectedAction, .requestUserInput)
    }

    func test_clarificationLimit_stillWins_overAssessmentFollowUpRecommendation() {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: FixedAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm availability", source: .gapFill, status: .notAnswered)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )

        let result = coordinator.evaluate(
            context: anchoredContext(clarificationRounds: 1),
            policy: .init(clarificationRoundLimit: 1)
        )
        XCTAssertNotEqual(result.plan.selectedAction, .askClarification)
    }
}

private extension ExchangeProviderResponseAssessmentSeamTests {
    struct FixedAssessmentEngine: ExchangeProviderResponseAssessmentEngine, Sendable {
        let assessment: ExchangeProviderResponseAssessment?

        func assessProviderResponse(
            context: ExchangeSecondHalfExecutionContext,
            priorAssessment: ExchangeProviderResponseAssessment?
        ) -> ExchangeProviderResponseAssessment? {
            assessment
        }
    }

    func anchoredContext(
        includesLegalCommercialCommitment: Bool = false,
        clarificationRounds: Int = 0
    ) -> ExchangeSecondHalfExecutionContext {
        ExchangeSecondHalfExecutionContext(
            role: .requester,
            currentState: .stalled,
            knownFacts: ["Requester wants seller financing flexibility."],
            unresolvedIssues: ["Please confirm seller financing flexibility."],
            surfacedCandidateCount: 1,
            hasFreshProviderAnswer: true,
            clarificationRounds: clarificationRounds,
            includesLegalCommercialCommitment: includesLegalCommercialCommitment,
            selectedCounterpartyID: "cp-1",
            selectedPublicProfileID: "profile-1",
            selectedOfferID: "offer-1",
            subjectMatter: "Find a home in GTA",
            requestedItems: ["Confirm financing flexibility"],
            clarifiedFacts: ["Budget and location are known."]
        )
    }

    func unanchoredContext() -> ExchangeSecondHalfExecutionContext {
        ExchangeSecondHalfExecutionContext(
            role: .requester,
            currentState: .stalled,
            knownFacts: ["Need details from provider."],
            unresolvedIssues: ["Please confirm provider pricing and timing."],
            surfacedCandidateCount: 2,
            hasFreshProviderAnswer: true,
            selectedCounterpartyID: nil,
            selectedPublicProfileID: nil,
            selectedOfferID: nil,
            subjectMatter: "Need provider confirmation",
            requestedItems: ["Ask if availability next Saturday works"],
            clarifiedFacts: []
        )
    }
}
