import XCTest
import AnumCore

/// Post-match second-half integration: requester/provider flows, coordinator wiring,
/// and facade persistence seams. No real network, federation, or LLM.
final class ExchangeSecondHalfPostMatchIntegrationTests: XCTestCase {

    private let requesterFlow = ExchangeSecondHalfRequesterFlow()
    private let providerFlow = ExchangeSecondHalfProviderFlow()
    private let coordinator = ExchangeSecondHalfCoordinator()
    private let priorsBuilder = ExchangeThreadPriorsBuilder()
    private let qualifier = ExchangeOpportunityQualifier()
    private let structuredAnswerEngine = ExchangeStructuredAnswerEngine()
    private let stanceEngine = ExchangeThreadStanceEngine()
    private let deltaEngine = ExchangeThreadDeltaEngine()
    private let boundaryEngine = ExchangeCommitmentBoundaryEngine()
    private let nextMoveEngine = ExchangeNextMoveEngine()
    private let providerIntakeEngine = ExchangeProviderIntakeEngine()
    private let requesterReviewEngine = ExchangeRequesterReviewEngine()
    private let decisionFramer = ExchangeDecisionFramer()
    private let draftComposer = ExchangeDraftComposer()

    private var policy: ExchangeSecondHalfPolicy {
        SecondHalfEngineTestFixtures.explicitSecondHalfPolicy()
    }

    override func setUp() {
        super.setUp()
        setenv("ANUM_DISABLE_RUNTIME_PREWARM", "1", 1)
        setenv("ANUM_DISABLE_ONDEVICE_LLM", "1", 1)
    }

    // MARK: - Requester flow (missing facts → packet / draft)

    func test_requesterFlow_surfacesUnresolvedIssuesInDraftAfterMatch() {
        let issue = "List price for the matched package"
        let context = SecondHalfPostMatchTestSupport.requesterPostMatchContext(
            unresolvedIssues: [issue]
        )

        let result = requesterFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            requesterReviewEngine: requesterReviewEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        XCTAssertFalse(result.qualification.missingFacts.isEmpty)
        XCTAssertTrue(
            result.qualification.missingFacts.joined(separator: " ")
                .localizedCaseInsensitiveContains("list price"),
            "Missing facts should carry the surfaced gap from unresolvedIssues."
        )
        XCTAssertTrue(result.plan.needsGeneration, "Expected a generative plan; got \(result.plan.selectedAction.rawValue).")
        XCTAssertNotNil(result.draft, "Draft should be produced for the generative post-match plan.")
        let body = result.draft?.body ?? ""
        XCTAssertTrue(
            body.localizedCaseInsensitiveContains("list price")
                || body.localizedCaseInsensitiveContains("unresolved"),
            "Draft or decision body should surface the gap; body=\(body)"
        )
    }

    func test_requesterFlow_preservesServiceLocationTimeAndPurposeInClarificationDraft() {
        let request = "help me find a roofer in Aurora for tomorrow 2:30 to do an appraisal"
        let context = SecondHalfPostMatchTestSupport.requesterPipelineContext(
            userRequest: request,
            unresolvedIssues: [
                "Can the provider perform a roofing appraisal?",
                "Can they come to Aurora tomorrow at 2:30?"
            ],
            knownFacts: [
                "Service needed: roofing appraisal",
                "Location: Aurora",
                "Requested time: tomorrow 2:30",
                "Purpose: appraisal"
            ]
        )

        let result = requesterFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            requesterReviewEngine: requesterReviewEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        let draftBody = (result.draft?.body ?? "").lowercased()
        XCTAssertTrue(draftBody.contains("roof") || draftBody.contains("appraisal"))
        XCTAssertTrue(draftBody.contains("aurora"))
        XCTAssertTrue(draftBody.contains("2:30") || draftBody.contains("tomorrow"))
    }

    func test_requesterFlow_relevantProviderInquiryIsSpecificAndNonCommitmentBearing() {
        let context = SecondHalfPostMatchTestSupport.requesterPipelineContext(
            userRequest: "Need roofing appraisal in Aurora tomorrow 2:30",
            unresolvedIssues: ["Can you do a roofing appraisal in Aurora tomorrow at 2:30?"],
            knownFacts: ["Service: roofing appraisal", "Location: Aurora", "Time: tomorrow 2:30"]
        )

        let result = requesterFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            requesterReviewEngine: requesterReviewEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        let body = (result.draft?.body ?? "").lowercased()
        XCTAssertTrue(body.contains("roof") || body.contains("appraisal"))
        XCTAssertTrue(body.contains("aurora"))
        XCTAssertTrue(body.contains("2:30") || body.contains("tomorrow"))
        XCTAssertFalse(body.contains("tell me more"))
        XCTAssertFalse(body.contains("confirmed"))
        XCTAssertFalse(body.contains("booked"))
        XCTAssertFalse(body.contains("i accept"))
    }

    func test_requesterFlow_missingDateOrLocation_promptsForMissingFactsInsteadOfWeakProviderSend() {
        let context = SecondHalfPostMatchTestSupport.requesterPipelineContext(
            userRequest: "Find a roofer for an appraisal",
            unresolvedIssues: ["Need location", "Need date and time"],
            knownFacts: ["Service: roofing appraisal"]
        )

        let result = requesterFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            requesterReviewEngine: requesterReviewEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        XCTAssertEqual(result.plan.selectedAction, .askClarification)
        let body = (result.draft?.body ?? "").lowercased()
        XCTAssertTrue(
            body.contains("clarify")
                || body.contains("help with")
                || body.contains("reaching out"),
            "Expected a clarification-style buyer body; body=\(body)"
        )
        XCTAssertTrue(body.contains("location") || body.contains("date") || body.contains("time"))
    }

    func test_requesterFlow_doesNotRepeatPriorQuestionVerbatimWhenAlreadyAsked() {
        let repeated = "Can you do a roofing appraisal in Aurora tomorrow at 2:30?"
        let context = SecondHalfPostMatchTestSupport.requesterPipelineContext(
            userRequest: "Need roofing appraisal in Aurora tomorrow 2:30",
            unresolvedIssues: [repeated],
            knownFacts: ["Service: roofing appraisal", "Location: Aurora", "Time: tomorrow 2:30"],
            priorQuestionsAsked: [repeated]
        )

        let result = requesterFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            requesterReviewEngine: requesterReviewEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        XCTAssertFalse((result.draft?.body ?? "").localizedCaseInsensitiveContains(repeated))
    }

    func test_requesterFlow_withMultipleCandidates_surfacesComparisonOrReviewAction() {
        let context = SecondHalfPostMatchTestSupport.requesterPipelineContext(
            userRequest: "Need roofing appraisal in Aurora tomorrow 2:30",
            unresolvedIssues: [],
            knownFacts: ["Service: roofing appraisal", "Location: Aurora", "Time: tomorrow 2:30"],
            surfacedCandidateCount: 3,
            hasComparableAlternatives: true,
            hasFreshProviderAnswer: true
        )

        let result = requesterFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            requesterReviewEngine: requesterReviewEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        XCTAssertTrue(
            result.plan.selectedAction == .compareOptions ||
            result.plan.selectedAction == .recommendNextMove ||
            result.plan.selectedAction == .frameDecision
        )
    }

    // MARK: - Provider flow (structured memory + escalation)

    func test_providerFlow_routineStructuredQueryAnswersFromOperatingMemory() {
        let query = ExchangeStructuredAnswerEngine.Query(
            rawText: "What is your home visit price?",
            kind: .pricing
        )
        let context = SecondHalfPostMatchTestSupport.providerRoutineContext(structuredQuery: query)

        let result = providerFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            structuredAnswerEngine: structuredAnswerEngine,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            providerIntakeEngine: providerIntakeEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        XCTAssertNotNil(result.structuredAnswer)
        XCTAssertTrue(result.structuredAnswer?.text.contains("$120") == true)
        XCTAssertEqual(result.plan.selectedAction, .autoRespond)
        XCTAssertFalse(result.plan.needsApproval)
        XCTAssertTrue(result.plan.isAutonomous)
        XCTAssertNotNil(result.draft)
        XCTAssertFalse(result.draft?.usedStructuredFacts.isEmpty ?? true)
    }

    func test_providerFlow_legalCommercialFlag_escalatesWithNoAutonomousExecution() {
        let query = ExchangeStructuredAnswerEngine.Query(
            rawText: "What is your home visit price?",
            kind: .pricing
        )
        let context = SecondHalfPostMatchTestSupport.providerRoutineContext(
            structuredQuery: query,
            includesLegalCommercialCommitment: true
        )

        let result = providerFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            structuredAnswerEngine: structuredAnswerEngine,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            providerIntakeEngine: providerIntakeEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        XCTAssertEqual(result.plan.selectedAction, .escalateForApproval)
        XCTAssertTrue(result.plan.needsApproval)
        XCTAssertTrue(result.plan.needsUserInput)
        XCTAssertFalse(result.plan.isAutonomous)
        XCTAssertTrue(result.boundary.requiresHumanApproval)
        XCTAssertTrue(result.decisionFrame?.needsCommitmentApproval == true)
    }

    func test_providerFlow_decisionFrameGainsClarifiedFactsWhenStructuredAnswerPresent() {
        let withoutQuery = SecondHalfPostMatchTestSupport.providerRoutineContext(structuredQuery: nil)
        let rBaseline = providerFlow.run(
            context: withoutQuery,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            structuredAnswerEngine: structuredAnswerEngine,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            providerIntakeEngine: providerIntakeEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        let query = ExchangeStructuredAnswerEngine.Query(
            rawText: "What is your home visit price?",
            kind: .pricing
        )
        let withQuery = SecondHalfPostMatchTestSupport.providerRoutineContext(structuredQuery: query)
        let rAugmented = providerFlow.run(
            context: withQuery,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            structuredAnswerEngine: structuredAnswerEngine,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            providerIntakeEngine: providerIntakeEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        let baseFacts = rBaseline.decisionFrame?.clarifiedFacts.count ?? 0
        let augmentedFacts = rAugmented.decisionFrame?.clarifiedFacts.count ?? 0
        XCTAssertGreaterThan(
            augmentedFacts,
            baseFacts,
            "Provider flow should fold structured sourced facts into the decision frame."
        )
        let joined = (rAugmented.decisionFrame?.clarifiedFacts ?? []).joined(separator: " ")
        XCTAssertTrue(joined.contains("$120") || joined.contains("120"))
    }

    func test_providerFlow_availabilityAndServiceAreaAndPolicyQueries_returnStructuredAnswers() {
        let availability = providerFlow.run(
            context: SecondHalfPostMatchTestSupport.providerRoutineContext(
                structuredQuery: .init(rawText: "weekdays availability", kind: .availability)
            ),
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            structuredAnswerEngine: structuredAnswerEngine,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            providerIntakeEngine: providerIntakeEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )
        XCTAssertNotNil(availability.structuredAnswer)

        let serviceArea = providerFlow.run(
            context: SecondHalfPostMatchTestSupport.providerRoutineContext(
                structuredQuery: .init(rawText: "metro east service area", kind: .serviceArea)
            ),
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            structuredAnswerEngine: structuredAnswerEngine,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            providerIntakeEngine: providerIntakeEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )
        XCTAssertNotNil(serviceArea.structuredAnswer)

        let policyResult = providerFlow.run(
            context: SecondHalfPostMatchTestSupport.providerRoutineContext(
                structuredQuery: .init(rawText: "cancellation policy", kind: .standardPolicy)
            ),
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            structuredAnswerEngine: structuredAnswerEngine,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            providerIntakeEngine: providerIntakeEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )
        XCTAssertNotNil(policyResult.structuredAnswer)
    }

    func test_providerFlow_unknownFactDoesNotProduceAutonomousStructuredAnswer() {
        let context = SecondHalfPostMatchTestSupport.providerRoutineContext(
            structuredQuery: .init(rawText: "submarine emergency rate", kind: .pricing)
        )
        let result = providerFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            structuredAnswerEngine: structuredAnswerEngine,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            providerIntakeEngine: providerIntakeEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )
        XCTAssertNil(result.structuredAnswer)
        XCTAssertTrue(result.plan.selectedAction == .requestUserInput || result.plan.selectedAction == .recommendNextMove)
        XCTAssertFalse(result.plan.isAutonomous)
    }

    func test_providerFlow_commitmentBoundaryFlagsUserJudgmentInDecisionFrame() {
        let context = SecondHalfPostMatchTestSupport.providerRoutineContext(
            structuredQuery: .init(rawText: "home visit price", kind: .pricing),
            includesLegalCommercialCommitment: true
        )
        let result = providerFlow.run(
            context: context,
            policy: policy,
            priorsBuilder: priorsBuilder,
            qualifier: qualifier,
            structuredAnswerEngine: structuredAnswerEngine,
            stanceEngine: stanceEngine,
            deltaEngine: deltaEngine,
            boundaryEngine: boundaryEngine,
            nextMoveEngine: nextMoveEngine,
            providerIntakeEngine: providerIntakeEngine,
            decisionFramer: decisionFramer,
            draftComposer: draftComposer
        )

        XCTAssertTrue(result.boundary.requiresHumanApproval)
        XCTAssertTrue(result.decisionFrame?.needsUserJudgment == true || result.decisionFrame?.needsCommitmentApproval == true)
    }

    // MARK: - Coordinator (end-to-end wiring)

    func test_coordinator_requesterAndProvider_evaluateWithoutThrowing() {
        let reqCtx = SecondHalfPostMatchTestSupport.requesterPostMatchContext(
            unresolvedIssues: ["Timeline for first visit"]
        )
        let reqResult = coordinator.evaluate(context: reqCtx, policy: policy)
        XCTAssertFalse(reqResult.qualification.missingFacts.isEmpty)
        XCTAssertNotNil(reqResult.draft)

        let provCtx = SecondHalfPostMatchTestSupport.providerRoutineContext(
            structuredQuery: ExchangeStructuredAnswerEngine.Query(
                rawText: "What is your home visit price?",
                kind: .pricing
            )
        )
        let provResult = coordinator.evaluate(context: provCtx, policy: policy)
        XCTAssertEqual(provResult.plan.selectedAction, .autoRespond)
        XCTAssertFalse(provResult.boundary.requiresHumanApproval)
        XCTAssertNil(provResult.projection.escalationReason)
    }

    func test_coordinator_providerLegalBoundary_neverMarksAutonomousPlan() {
        let provCtx = SecondHalfPostMatchTestSupport.providerRoutineContext(
            structuredQuery: ExchangeStructuredAnswerEngine.Query(
                rawText: "What is your home visit price?",
                kind: .pricing
            ),
            includesLegalCommercialCommitment: true
        )
        let provResult = coordinator.evaluate(context: provCtx, policy: policy)
        XCTAssertEqual(provResult.plan.selectedAction, .escalateForApproval)
        XCTAssertFalse(provResult.plan.isAutonomous)
        XCTAssertNotNil(provResult.projection.escalationReason)
    }

    // MARK: - Facade + store adapter

    func test_facade_evaluateThread_persistsSecondHalfRecord() async throws {
        let threadID = SecondHalfPostMatchTestSupport.threadID
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let operatingStore = ExchangeDefaultOperatingMemoryStore()
        try await operatingStore.saveOperatingMemory(memory, forThreadID: threadID, role: .provider)

        let storeAdapter = ExchangeDefaultSecondHalfStoreAdapter(exchangeStore: nil)
        let facade = ExchangeSecondHalfFacade(
            storeAdapter: storeAdapter,
            operatingMemoryStore: operatingStore,
            localNodeIDProvider: { nil }
        )

        let snapshot = SecondHalfPostMatchTestSupport.providerSnapshot(
            structuredQuery: ExchangeStructuredAnswerEngine.Query(
                rawText: "What is your home visit price?",
                kind: .pricing
            )
        )

        let result = try await facade.evaluateThread(snapshot, policy: policy)
        XCTAssertEqual(result.plan.selectedAction, .autoRespond)

        let persisted = try await storeAdapter.loadSecondHalfRecord(forThreadID: threadID, role: .provider)
        XCTAssertNotNil(persisted)
        XCTAssertEqual(persisted?.latestPlan?.selectedAction, result.plan.selectedAction)
        XCTAssertEqual(persisted?.state, result.nextState)
        XCTAssertNotNil(persisted?.pendingDraft)
    }

    func test_facade_duplicateEvaluate_secondHalfStateAndPlanRemainStable_withoutNewInput() async throws {
        let threadID = SecondHalfPostMatchTestSupport.threadID
        let memory = SecondHalfEngineTestFixtures.memoryWithRoutineFacts()
        let operatingStore = ExchangeDefaultOperatingMemoryStore()
        try await operatingStore.saveOperatingMemory(memory, forThreadID: threadID, role: .provider)

        let storeAdapter = ExchangeDefaultSecondHalfStoreAdapter(exchangeStore: nil)
        let facade = ExchangeSecondHalfFacade(
            storeAdapter: storeAdapter,
            operatingMemoryStore: operatingStore,
            localNodeIDProvider: { nil }
        )

        let snapshot = SecondHalfPostMatchTestSupport.providerSnapshot(
            structuredQuery: ExchangeStructuredAnswerEngine.Query(
                rawText: "What is your home visit price?",
                kind: .pricing
            )
        )

        let first = try await facade.evaluateThread(snapshot, policy: policy)
        let second = try await facade.evaluateThread(snapshot, policy: policy)

        XCTAssertEqual(first.plan.selectedAction, second.plan.selectedAction)
        XCTAssertEqual(first.nextState, second.nextState)

        let persisted = try await storeAdapter.loadSecondHalfRecord(forThreadID: threadID, role: .provider)
        XCTAssertEqual(persisted?.state, second.nextState)
        XCTAssertEqual(persisted?.latestPlan?.selectedAction, second.plan.selectedAction)
    }

    // MARK: - Requester review / decision projection (capability 6–7)

    private func displayForRequesterReviewProjection(
        qualification: ExchangeOpportunityQualification,
        frame: ExchangeDecisionFrame?,
        decisionNeeds: ExchangeRequesterDecisionNeeds?,
        surface: ExchangeRequesterReviewSurfaceContext?
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel {
        let plan = ExchangeSecondHalfPlan(
            selectedAction: .frameDecision,
            role: .requester,
            rationale: "Fixture",
            needsGeneration: false,
            needsUserInput: true,
            needsApproval: false
        )
        let seed = ExchangeSecondHalfCoordinator.ProjectionSeed(
            stateTitle: "Fixture",
            roleTitle: ExchangeSecondHalfRole.requester.displayTitle,
            postureSummary: "Fixture",
            recommendation: "Fixture",
            visibleAction: plan.selectedAction,
            escalationReason: nil,
            canSurfaceNow: true
        )
        let result = ExchangeSecondHalfCoordinator.Result(
            nextState: .requesterReview,
            qualification: qualification,
            stance: .neutral,
            delta: .none,
            boundary: .safe,
            plan: plan,
            decisionFrame: frame,
            draft: nil,
            projection: seed
        )
        let assessment = ExchangeAgencyAssessment(
            requesterDecisionNeeds: decisionNeeds,
            providerAnswerability: nil,
            groundedFactLines: [],
            suggestedQuestionLines: [],
            answerabilityLine: nil,
            agencySuggestions: []
        )
        let projection = ExchangeSecondHalfProjection(
            coordinatorResult: result,
            inquiry: nil,
            agencyAssessment: assessment,
            requesterSurfaceContext: surface
        )
        return ExchangeSecondHalfUIAdapter().makeDisplayModel(from: projection)
    }

    func test_requesterReviewProjection_strongFit_geoTitleAndSanitizedDecisionSurface() {
        let qual = ExchangeOpportunityQualification(
            qualityTier: .strong,
            missingFacts: [],
            strengthReasons: ["Has enough thread detail to work with."],
            weaknessReasons: [],
            qualificationStatus: .qualified,
            isOneMoreClarificationWorthwhile: false
        )
        let frame = ExchangeDecisionFrame(
            summary: "Anchoring score high for this path.",
            clarifiedFacts: [
                "Piano lessons available weekday evenings in Aurora.",
                "Published rate is $60 per hour."
            ],
            recommendation: "Offer row present — anchoring score 0.9",
            needsUserJudgment: true
        )
        let needs = ExchangeRequesterDecisionNeeds(
            knownDecisionFacts: [],
            missingDecisionFacts: [],
            recommendedQuestions: [],
            decisionReadiness: .decisionReady,
            rationale: "Enough public and thread detail to decide from."
        )
        let surface = ExchangeRequesterReviewSurfaceContext(
            subjectMatter: "Piano lessons",
            offerTitle: "Piano lessons",
            regionHint: "Aurora"
        )
        let display = displayForRequesterReviewProjection(
            qualification: qual,
            frame: frame,
            decisionNeeds: needs,
            surface: surface
        )

        let reviewTitle = display.requesterReview?.title ?? ""
        XCTAssertTrue(reviewTitle.localizedCaseInsensitiveContains("Strong fit"))
        XCTAssertTrue(reviewTitle.localizedCaseInsensitiveContains("Aurora"))

        let bundle: [String] =
            [
                display.title,
                display.subtitle,
                display.summary,
                display.recommendation,
                display.requesterReview?.title,
                display.requesterReview?.subtitle,
                display.requesterReview?.recommendation,
                display.decision?.summary,
                display.decision?.recommendation
            ].compactMap { $0 }
                + (display.decision?.clarifiedFacts ?? [])
                + (display.requesterReview?.strengthReasons ?? [])
        let joined = bundle.joined(separator: " ")
        XCTAssertFalse(joined.localizedCaseInsensitiveContains("anchoring score"))
        XCTAssertFalse(joined.localizedCaseInsensitiveContains("offer row present"))
        XCTAssertFalse(joined.localizedCaseInsensitiveContains("knownFacts"))
        XCTAssertFalse(joined.localizedCaseInsensitiveContains("pass 2"))
        XCTAssertFalse(joined.localizedCaseInsensitiveContains("pass 3"))
        XCTAssertFalse(joined.localizedCaseInsensitiveContains("qualificationStatus"))

        XCTAssertTrue(display.hasDecisionPacket)
        XCTAssertNotNil(display.decision)
        XCTAssertTrue(display.decisionPacketProjectionAligned)
    }

    func test_requesterReviewProjection_partialFit_mentionsMissingDetails() {
        let qual = ExchangeOpportunityQualification(
            qualityTier: .promising,
            missingFacts: ["Exact lesson price", "Next available lesson slot"],
            strengthReasons: ["Has enough thread detail to work with."],
            weaknessReasons: [],
            qualificationStatus: .needsClarification,
            isOneMoreClarificationWorthwhile: true
        )
        let needs = ExchangeRequesterDecisionNeeds(
            knownDecisionFacts: [],
            missingDecisionFacts: ["Exact lesson price", "Next available lesson slot"],
            recommendedQuestions: [],
            decisionReadiness: .needsFacts,
            rationale: "Worth clarifying before you decide."
        )
        let surface = ExchangeRequesterReviewSurfaceContext(
            offerTitle: "Piano lessons",
            regionHint: "Aurora"
        )
        let display = displayForRequesterReviewProjection(
            qualification: qual,
            frame: nil,
            decisionNeeds: needs,
            surface: surface
        )

        let title = display.requesterReview?.title ?? ""
        XCTAssertTrue(
            title.localizedCaseInsensitiveContains("Possible fit")
                || title.localizedCaseInsensitiveContains("Needs detail")
        )

        let subtitle = display.requesterReview?.subtitle ?? ""
        XCTAssertTrue(
            subtitle.localizedCaseInsensitiveContains("Worth clarifying")
                || subtitle.localizedCaseInsensitiveContains("Missing")
        )

        let reco = display.requesterReview?.recommendation ?? ""
        XCTAssertTrue(reco.localizedCaseInsensitiveContains("missing"))
        XCTAssertFalse(reco.localizedCaseInsensitiveContains("Ready to decide"))
    }

    func test_requesterReviewProjection_weakFit_surfacesWeakCopy() {
        let qual = ExchangeOpportunityQualification(
            qualityTier: .weak,
            missingFacts: [],
            strengthReasons: [],
            weaknessReasons: ["Not enough evidence yet to recommend."],
            qualificationStatus: .incomplete,
            isOneMoreClarificationWorthwhile: false
        )
        let needs = ExchangeRequesterDecisionNeeds(
            knownDecisionFacts: [],
            missingDecisionFacts: [],
            recommendedQuestions: [],
            decisionReadiness: .weak,
            rationale: "This path still looks thin; add detail or keep looking."
        )
        let display = displayForRequesterReviewProjection(
            qualification: qual,
            frame: nil,
            decisionNeeds: needs,
            surface: nil
        )

        let title = display.requesterReview?.title ?? ""
        XCTAssertTrue(title.localizedCaseInsensitiveContains("Weak match"))

        let reco = display.requesterReview?.recommendation ?? ""
        XCTAssertTrue(
            reco.localizedCaseInsensitiveContains("Weak match")
                || reco.localizedCaseInsensitiveContains("keep searching")
                || reco.localizedCaseInsensitiveContains("thin")
        )
    }
}
