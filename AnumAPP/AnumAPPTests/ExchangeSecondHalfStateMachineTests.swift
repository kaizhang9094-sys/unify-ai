import XCTest
import AnumCore

/// Canonical second-half lifecycle: `ExchangeSecondHalfStateMachine` legal table + illegal guards.
/// Coordinator wiring checks only where execution context mirrors production fixtures.
///
/// Lifecycle table (canonical `ExchangeSecondHalfStateMachine`; actions must be `.validate` true):
///
/// ```
/// ┌─────────────────────────────────────┬─────────────────────────┬───────────────────────────────┐
/// │ From                                │ Action                  │ To                            │
/// ├─────────────────────────────────────┼─────────────────────────┼───────────────────────────────┤
/// │ matchFound                          │ qualifyMatch            │ qualifying                    │
/// │ matchFound                          │ requestUserInput        │ requesterReview               │
/// │ matchFound                          │ markBlocked             │ blocked                       │
/// │ matchFound                          │ markStalled             │ stalled                       │
/// │ qualifying                          │ askClarification        │ awaitingProviderClarification │
/// │ qualifying                          │ requestUserInput        │ requesterReview               │
/// │ qualifying                          │ frameDecision           │ decisionReady                 │
/// │ qualifying                          │ recommendNextMove       │ decisionReady                 │
/// │ qualifying                          │ markBlocked             │ blocked                       │
/// │ qualifying                          │ markStalled             │ stalled                       │
/// │ awaitingProviderClarification       │ answerClarification     │ requesterReview               │
/// │ awaitingProviderClarification       │ requestUserInput        │ providerReview                │
/// │ awaitingRequesterClarification      │ answerClarification     │ providerReview                │
/// │ awaitingRequesterClarification      │ requestUserInput        │ requesterReview               │
/// │ providerReview                      │ autoRespond             │ requesterReview               │
/// │ decisionReady                       │ escalateForApproval     │ awaitingCommitmentApproval    │
/// │ accepted                            │ complete                │ completed                     │
/// │ …                                   │ …                       │ …                             │
/// └─────────────────────────────────────┴─────────────────────────┴───────────────────────────────┘
/// ```
///
/// Coordinator note: outbound auto-send belongs to façade policy; tests here forbid **illegal SM moves**.
final class ExchangeSecondHalfStateMachineTests: XCTestCase {
    private let sut = ExchangeSecondHalfStateMachine()
    private var policy: ExchangeSecondHalfPolicy { SecondHalfEngineTestFixtures.explicitSecondHalfPolicy() }

    override func setUp() {
        super.setUp()
        setenv("ANUM_DISABLE_RUNTIME_PREWARM", "1", 1)
        setenv("ANUM_DISABLE_ONDEVICE_LLM", "1", 1)
    }

    // MARK: - Legal transition table (explicit enum assertions)

    func test_transitionTable_matchFound_qualify_advancesQualifying_and_input_toRequesterReview() {
        XCTAssertEqual(sut.nextState(from: .matchFound, action: .qualifyMatch), .qualifying)
        XCTAssertEqual(sut.nextState(from: .matchFound, action: .requestUserInput), .requesterReview)
        XCTAssertEqual(sut.nextState(from: .matchFound, action: .markBlocked), .blocked)
        XCTAssertEqual(sut.nextState(from: .matchFound, action: .markStalled), .stalled)
    }

    func test_transitionTable_qualifying_clarifying_and_decisionAndReviewPaths() {
        XCTAssertEqual(sut.nextState(from: .qualifying, action: .askClarification), .awaitingProviderClarification)
        XCTAssertEqual(sut.nextState(from: .qualifying, action: .requestUserInput), .requesterReview)
        XCTAssertEqual(sut.nextState(from: .qualifying, action: .frameDecision), .decisionReady)
        XCTAssertEqual(sut.nextState(from: .qualifying, action: .recommendNextMove), .decisionReady)
        XCTAssertEqual(sut.nextState(from: .qualifying, action: .markBlocked), .blocked)
        XCTAssertEqual(sut.nextState(from: .qualifying, action: .markStalled), .stalled)
    }

    func test_transitionTable_awaitingClarification_partnerPaths() {
        XCTAssertEqual(sut.nextState(from: .awaitingProviderClarification, action: .answerClarification), .requesterReview)
        XCTAssertEqual(sut.nextState(from: .awaitingProviderClarification, action: .requestUserInput), .providerReview)

        XCTAssertEqual(sut.nextState(from: .awaitingRequesterClarification, action: .answerClarification), .providerReview)
        XCTAssertEqual(sut.nextState(from: .awaitingRequesterClarification, action: .requestUserInput), .requesterReview)
    }

    func test_transitionTable_providerReview_autoRespond_movesToRequesterReview() {
        XCTAssertEqual(sut.nextState(from: .providerReview, action: .autoRespond), .requesterReview)
    }

    func test_transitionTable_requesterReview_decisionShaping_movesToDecisionReady() {
        XCTAssertEqual(sut.nextState(from: .requesterReview, action: .frameDecision), .decisionReady)
        XCTAssertEqual(sut.nextState(from: .requesterReview, action: .recommendNextMove), .decisionReady)
        XCTAssertEqual(sut.nextState(from: .requesterReview, action: .compareOptions), .decisionReady)
    }

    func test_transitionTable_decisionReady_commitmentOrTerminalMoves() {
        XCTAssertEqual(sut.nextState(from: .decisionReady, action: .escalateForApproval), .awaitingCommitmentApproval)
        XCTAssertEqual(sut.nextState(from: .decisionReady, action: .proposeTerms), .awaitingCommitmentApproval)
        XCTAssertEqual(sut.nextState(from: .decisionReady, action: .accept), .accepted)
        XCTAssertEqual(sut.nextState(from: .decisionReady, action: .decline), .declined)
        XCTAssertEqual(sut.nextState(from: .decisionReady, action: .pause), .stalled)
    }

    func test_transitionTable_accepted_complete_isTerminalSeal() {
        XCTAssertEqual(sut.nextState(from: .accepted, action: .complete), .completed)
    }

    func test_terminalStates_declined_completed_expired_haveNoOutboundTransitions() {
        for terminal in ExchangeSecondHalfState.allCases.filter({
            [.declined, .completed, .expired].contains($0)
        }) {
            for action in ExchangeSecondHalfAction.allCases {
                XCTAssertFalse(
                    sut.validate(action: action, state: terminal),
                    "Illegal outbound from terminal \(terminal.rawValue) via \(action.rawValue)"
                )
                XCTAssertNil(
                    sut.nextState(from: terminal, action: action),
                    "nextState must be nil from terminal \(terminal.rawValue)"
                )
            }
        }
    }

    func test_terminalState_accepted_onlyAllows_complete() {
        for action in ExchangeSecondHalfAction.allCases {
            if action == .complete {
                XCTAssertTrue(sut.validate(action: action, state: .accepted))
                XCTAssertEqual(sut.nextState(from: .accepted, action: action), .completed)
            } else {
                XCTAssertFalse(sut.validate(action: action, state: .accepted), "\(action.rawValue)")
                XCTAssertNil(sut.nextState(from: .accepted, action: action))
            }
        }
    }

    func test_humanReviewStalePaths_doNotAutoAdvanceWithAutoRespond() {
        XCTAssertNil(sut.nextState(from: .awaitingProviderClarification, action: .autoRespond))
        XCTAssertNil(sut.nextState(from: .awaitingRequesterClarification, action: .autoRespond))

        XCTAssertNil(sut.nextState(from: .qualifying, action: .autoRespond))
        XCTAssertNil(sut.nextState(from: .matchFound, action: .autoRespond))
        XCTAssertNil(sut.nextState(from: .blocked, action: .autoRespond))
        XCTAssertNil(sut.nextState(from: .awaitingCommitmentApproval, action: .autoRespond))
    }

    // MARK: - Illegal transitions (explicit invariants)

    func test_blocked_doesNotAllow_autoRespond_transition() {
        XCTAssertFalse(sut.validate(action: .autoRespond, state: .blocked))
        XCTAssertNil(sut.nextState(from: .blocked, action: .autoRespond))
    }

    func test_awaitingCommitmentApproval_autoRespond_isIllegal_transition() {
        XCTAssertFalse(sut.validate(action: .autoRespond, state: .awaitingCommitmentApproval))
        XCTAssertNil(sut.nextState(from: .awaitingCommitmentApproval, action: .autoRespond))
    }

    func test_completed_doesNotReopen_toActive_coordination_moves() {
        XCTAssertFalse(sut.validate(action: .recommendNextMove, state: .completed))
        XCTAssertFalse(sut.validate(action: .autoRespond, state: .completed))
        XCTAssertNil(sut.nextState(from: .completed, action: .recommendNextMove))
        XCTAssertNil(sut.nextState(from: .completed, action: .autoRespond))
    }

    func test_declined_doesNot_transition_toDecisionReady() {
        XCTAssertFalse(sut.validate(action: .frameDecision, state: .declined))
        XCTAssertNil(sut.nextState(from: .declined, action: .frameDecision))
        XCTAssertNil(sut.nextState(from: .declined, action: .recommendNextMove))
    }

    func test_knownMissingFactsStages_do_notAllow_autoRespond() {
        XCTAssertFalse(sut.validate(action: .autoRespond, state: .matchFound))
        XCTAssertFalse(sut.validate(action: .autoRespond, state: .qualifying))
    }

    // MARK: - Coordinator ↔ stateMachine parity for fixture contexts

    func test_secondHalfCoordinator_nextState_alwaysMatchesEmbeddedStateMachine_forFixtures() {
        let coordinator = ExchangeSecondHalfCoordinator()
        let sm = ExchangeSecondHalfStateMachine()

        let contexts: [ExchangeSecondHalfExecutionContext] = [
            SecondHalfPostMatchTestSupport.providerRoutineContext(
                structuredQuery: .init(rawText: "What is your home visit price?", kind: .pricing)
            ),
            SecondHalfPostMatchTestSupport.providerRoutineContext(
                structuredQuery: .init(rawText: "submarine emergency rate", kind: .pricing)
            ),
            SecondHalfPostMatchTestSupport.providerRoutineContext(
                structuredQuery: .init(rawText: "What is your home visit price?", kind: .pricing),
                includesLegalCommercialCommitment: true
            ),
            SecondHalfPostMatchTestSupport.requesterPostMatchContext(
                unresolvedIssues: ["List price for the matched package"]
            )
        ]

        for ctx in contexts {
            let result = coordinator.evaluate(context: ctx, policy: policy)
            let expected = sm.nextState(from: ctx.currentState, action: result.plan.selectedAction) ?? ctx.currentState
            XCTAssertEqual(
                result.nextState,
                expected,
                "Coordinator must mirror StateMachine for role=\(ctx.role.rawValue) state=\(ctx.currentState.rawValue) action=\(result.plan.selectedAction.rawValue)"
            )
        }
    }

    // MARK: - State → display placement (AnumCore UIAdapter; no UI target edits)

    func test_stateDisplayParity_blocked_placesRecovery() {
        let ui = ExchangeSecondHalfUIAdapter()
        let projection = minimalProjection(currentState: .blocked)
        let display = ui.makeDisplayModel(from: projection)
        XCTAssertEqual(display.placement, .recovery)
    }

    func test_stateDisplayParity_stalled_placesRecovery() {
        let ui = ExchangeSecondHalfUIAdapter()
        let projection = minimalProjection(currentState: .stalled)
        let display = ui.makeDisplayModel(from: projection)
        XCTAssertEqual(display.placement, .recovery)
    }

    func test_stateDisplayParity_completed_placesCompleted() {
        let ui = ExchangeSecondHalfUIAdapter()
        let projection = minimalProjection(currentState: .completed)
        let display = ui.makeDisplayModel(from: projection)
        XCTAssertEqual(display.placement, .completed)
        XCTAssertEqual(display.agencyPhase, .completed)
    }

    func test_stateDisplayParity_awaitingCommitment_escalation_placesNeedsApproval_notActive_coordination() {
        let ui = ExchangeSecondHalfUIAdapter()
        var projection = minimalProjection(currentState: .awaitingCommitmentApproval)
        projection = ExchangeSecondHalfProjection(
            currentState: projection.currentState,
            role: projection.role,
            stance: projection.stance,
            qualification: projection.qualification,
            latestDecisionFrame: projection.latestDecisionFrame,
            latestDelta: projection.latestDelta,
            pendingDraft: projection.pendingDraft,
            escalationReason: "Legal review required before outbound send.",
            visibleActions: projection.visibleActions,
            nextMove: ExchangeNextMoveViewModel(
                action: .pause,
                title: "",
                rationale: "",
                needsGeneration: false,
                needsUserInput: false,
                needsApproval: false
            ),
            decisionPacket: projection.decisionPacket,
            providerInboxCard: projection.providerInboxCard,
            requesterReviewCard: projection.requesterReviewCard,
            agencyAssessment: projection.agencyAssessment
        )
        let display = ui.makeDisplayModel(from: projection)
        XCTAssertEqual(display.placement, .needsApproval)
        XCTAssertNotEqual(display.placement, .activeCoordination)
    }

    func test_stateDisplayParity_qualifying_needUserNextMove_placesNeedsInput() {
        let ui = ExchangeSecondHalfUIAdapter()
        var projection = minimalProjection(currentState: .awaitingProviderClarification)
        projection.nextMove = ExchangeNextMoveViewModel(
            action: .answerClarification,
            title: "Answer clarification",
            rationale: "",
            needsGeneration: true,
            needsUserInput: true,
            needsApproval: false
        )
        let display = ui.makeDisplayModel(from: projection)
        XCTAssertEqual(display.placement, .needsInput)
    }

    func test_projection_buildFromCoordinator_matchesCoordinatorNextState_fixtureProvider() {
        let coordinator = ExchangeSecondHalfCoordinator()
        let ctx = SecondHalfPostMatchTestSupport.providerRoutineContext(
            structuredQuery: .init(rawText: "What is your home visit price?", kind: .pricing)
        )
        let result = coordinator.evaluate(context: ctx, policy: policy)
        let projection = ExchangeSecondHalfProjection(coordinatorResult: result)
        XCTAssertEqual(projection.currentState, result.nextState)
        XCTAssertEqual(projection.visibleActions, [result.plan.selectedAction])
    }

    private func minimalProjection(
        currentState: ExchangeSecondHalfState,
        escalationReason: String? = nil,
        role: ExchangeSecondHalfRole = .requester
    ) -> ExchangeSecondHalfProjection {
        ExchangeSecondHalfProjection(
            currentState: currentState,
            role: role,
            stance: ExchangeThreadStance(postureSummary: "Fixture stance"),
            qualification: ExchangeOpportunityQualification(),
            latestDecisionFrame: nil,
            latestDelta: nil,
            pendingDraft: nil,
            escalationReason: escalationReason,
            visibleActions: [],
            nextMove: nil,
            decisionPacket: nil,
            providerInboxCard: nil,
            requesterReviewCard: nil,
            agencyAssessment: nil
        )
    }
}
