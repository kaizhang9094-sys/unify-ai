import XCTest
@testable import AnumCore

final class LLMExchangeProviderResponseAssessmentEngineTests: XCTestCase {
    func test_vtbImpliedFlexibility_mapsToImpliedOrPartial_withMissingTerms_andFollowUp() async {
        let json = """
        {
          "conditionAssessments": [
            {
              "conditionText": "seller financing / VTB",
              "source": "commercialConstraint",
              "status": "impliedFlexible",
              "confidence": 0.78,
              "evidence": ["we may consider seller financing depending on down payment"],
              "missingInfo": ["down payment", "interest rate", "term"],
              "suggestedFollowUp": "Can you share required down payment, estimated rate, and term?"
            }
          ],
          "providerFitSummary": "Provider appears open to VTB with conditions.",
          "confidenceDelta": "positive",
          "shortlistRecommendation": "promote",
          "decisionReadiness": "needsFollowUp",
          "nextMoveRecommendation": "askClarification",
          "missingInfo": ["down payment", "interest rate", "term"],
          "suggestedFollowUp": "Can you share required down payment, estimated rate, and term?",
          "requesterFacingExplanation": "They are open to VTB but key terms are missing.",
          "requiresHumanJudgment": false,
          "safeForAutonomousFollowup": true,
          "confidence": 0.78
        }
        """
        let store = ProviderResponseAssessmentDiagnosticsStore()
        let engine = LLMExchangeProviderResponseAssessmentEngine(
            provider: AsyncFixedProvider(raw: json, ready: true),
            diagnosticsStore: store
        )

        let result = await engine.assessProviderResponse(context: fixtureContext(), priorAssessment: nil)
        let diag = await store.last
        XCTAssertEqual(result?.conditionAssessments.first?.status, .impliedFlexible)
        XCTAssertTrue(result?.missingInfo.joined(separator: " ").lowercased().contains("down payment") == true)
        XCTAssertEqual(result?.nextMoveRecommendation, .askClarification)
        XCTAssertEqual(diag?.source, .llm)
    }

    func test_vtbContradiction_mapsContradicted_andDowngrade() async {
        let json = """
        {
          "conditionAssessments": [
            {
              "conditionText": "seller financing / VTB",
              "source": "commercialConstraint",
              "status": "contradicted",
              "confidence": 0.93,
              "evidence": ["we do not offer seller financing"]
            }
          ],
          "providerFitSummary": "Provider explicitly rejects seller financing.",
          "confidenceDelta": "stronglyNegative",
          "shortlistRecommendation": "demote",
          "decisionReadiness": "blockedByContradiction",
          "nextMoveRecommendation": "requestUserInput",
          "requiresHumanJudgment": true,
          "safeForAutonomousFollowup": false,
          "confidence": 0.93
        }
        """
        let engine = LLMExchangeProviderResponseAssessmentEngine(
            provider: AsyncFixedProvider(raw: json, ready: true)
        )

        let result = await engine.assessProviderResponse(context: fixtureContext(), priorAssessment: nil)
        XCTAssertEqual(result?.conditionAssessments.first?.status, .contradicted)
        XCTAssertEqual(result?.confidenceDelta, .stronglyNegative)
        XCTAssertEqual(result?.shortlistRecommendation, .demote)
        XCTAssertTrue(result?.requiresHumanJudgment == true)
    }

    func test_providerFullyAnswers_vtbTerms_mapsSatisfiedOrPartial() async {
        let json = """
        {
          "conditionAssessments": [
            {
              "conditionText": "seller financing / VTB",
              "source": "commercialConstraint",
              "status": "satisfied",
              "confidence": 0.9,
              "evidence": ["vtb available up to 20%", "rate 6.2%", "term 24 months"]
            }
          ],
          "providerFitSummary": "Provider supplied key VTB terms.",
          "confidenceDelta": "stronglyPositive",
          "shortlistRecommendation": "promote",
          "decisionReadiness": "readyForDecisionFrame",
          "nextMoveRecommendation": "frameDecision",
          "missingInfo": [],
          "requiresHumanJudgment": false,
          "safeForAutonomousFollowup": false,
          "confidence": 0.9
        }
        """
        let engine = LLMExchangeProviderResponseAssessmentEngine(
            provider: AsyncFixedProvider(raw: json, ready: true)
        )

        let result = await engine.assessProviderResponse(context: fixtureContext(), priorAssessment: nil)
        XCTAssertTrue(result?.conditionAssessments.first?.status == .satisfied || result?.conditionAssessments.first?.status == .partiallySatisfied)
        XCTAssertTrue(result?.missingInfo.isEmpty == true)
        XCTAssertEqual(result?.nextMoveRecommendation, .frameDecision)
    }

    func test_noisyMarkdownJSON_repairs_andUsesLLMAssessment() async {
        let noisy = """
        Here is the result:
        ```json
        {
          "conditionAssessments":[{"conditionText":"availability next Saturday","source":"timingConstraint","status":"needsFollowUp"}],
          "confidenceDelta":"stable",
          "shortlistRecommendation":"noChange",
          "decisionReadiness":"needsFollowUp",
          "nextMoveRecommendation":"askClarification",
          "safeForAutonomousFollowup":true
        }
        ```
        """
        let store = ProviderResponseAssessmentDiagnosticsStore()
        let engine = LLMExchangeProviderResponseAssessmentEngine(
            provider: AsyncFixedProvider(raw: noisy, ready: true),
            diagnosticsStore: store
        )

        let result = await engine.assessProviderResponse(context: fixtureContext(), priorAssessment: nil)
        let diag = await store.last
        XCTAssertEqual(result?.conditionAssessments.first?.status, .needsFollowUp)
        XCTAssertEqual(diag?.source, .llmRepairedJSON)
        XCTAssertEqual(diag?.repairAttempted, true)
    }

    func test_invalidJSON_fallsBackToHeuristic_andRecordsReason() async {
        let store = ProviderResponseAssessmentDiagnosticsStore()
        let engine = LLMExchangeProviderResponseAssessmentEngine(
            provider: AsyncFixedProvider(raw: "{bad json", ready: true),
            diagnosticsStore: store
        )

        let result = await engine.assessProviderResponse(context: fixtureContext(), priorAssessment: nil)
        let diag = await store.last
        XCTAssertNotNil(result)
        XCTAssertEqual(diag?.source, .heuristicFallback)
        XCTAssertTrue([ProviderResponseAssessmentFailureReason.invalidJSON, .repairFailed].contains(diag?.fallbackReason))
    }

    func test_busyProvider_fallsBackWithoutCallingModel() async {
        let provider = AsyncRecordingProvider(ready: false, behavior: .returning("{}"))
        let store = ProviderResponseAssessmentDiagnosticsStore()
        let engine = LLMExchangeProviderResponseAssessmentEngine(
            provider: provider,
            diagnosticsStore: store
        )

        _ = await engine.assessProviderResponse(context: fixtureContext(), priorAssessment: nil)
        let calls = await provider.callCount
        let diag = await store.last
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(diag?.fallbackReason, .modelBusy)
    }

    func test_timeout_fallsBackQuickly_andRecordsTimeout() async {
        let provider = AsyncRecordingProvider(ready: true, behavior: .sleepThenReturn(seconds: 0.2, json: "{}"))
        let store = ProviderResponseAssessmentDiagnosticsStore()
        let engine = LLMExchangeProviderResponseAssessmentEngine(
            provider: provider,
            diagnosticsStore: store,
            config: .init(timeoutSeconds: 0.05)
        )

        let start = CFAbsoluteTimeGetCurrent()
        _ = await engine.assessProviderResponse(context: fixtureContext(), priorAssessment: nil)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let diag = await store.last
        XCTAssertLessThan(elapsed, 0.2)
        XCTAssertEqual(diag?.fallbackReason, .timeout)
    }

    func test_safetyGateUnchanged_boundaryStillRequiresApproval_evenIfSafeFollowUpTrue() {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: FixedAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm terms", source: .commercialConstraint, status: .needsFollowUp)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )
        var context = fixtureContext()
        context.includesLegalCommercialCommitment = true
        let result = coordinator.evaluate(context: context)
        XCTAssertTrue(result.boundary.requiresHumanApproval)
    }

    func test_recipientAnchorGuardStillWins_withAssessmentDrivenFollowUp() {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: FixedAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm availability", source: .gapFill, status: .needsFollowUp)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )
        var context = fixtureContext()
        context.selectedCounterpartyID = nil
        context.selectedPublicProfileID = nil
        context.selectedOfferID = nil
        let result = coordinator.evaluate(context: context)
        XCTAssertEqual(result.plan.selectedAction, .requestUserInput)
    }

    func test_clarificationLimitStillWins_withAssessmentDrivenFollowUp() {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: FixedAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm timing", source: .timingConstraint, status: .needsFollowUp)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )
        let result = coordinator.evaluate(
            context: fixtureContext(clarificationRounds: 1),
            policy: ExchangeSecondHalfPolicy(clarificationRoundLimit: 1)
        )
        XCTAssertNotEqual(result.plan.selectedAction, .askClarification)
    }
}

private extension LLMExchangeProviderResponseAssessmentEngineTests {
    actor AsyncRecordingProvider: AsyncProviderResponseAssessmentJSONProvider {
        enum Behavior {
            case returning(String)
            case sleepThenReturn(seconds: Double, json: String)
            case throwing(Error)
        }

        private(set) var callCount: Int = 0
        let ready: Bool
        let behavior: Behavior

        init(ready: Bool, behavior: Behavior) {
            self.ready = ready
            self.behavior = behavior
        }

        func isReadyForImmediateExtraction() async -> Bool { ready }

        func assessProviderResponseJSON(prompt: String) async throws -> String {
            callCount += 1
            switch behavior {
            case .returning(let json):
                return json
            case .sleepThenReturn(let seconds, let json):
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return json
            case .throwing(let error):
                throw error
            }
        }
    }

    struct AsyncFixedProvider: AsyncProviderResponseAssessmentJSONProvider {
        let raw: String
        let ready: Bool
        func isReadyForImmediateExtraction() async -> Bool { ready }
        func assessProviderResponseJSON(prompt: String) async throws -> String { raw }
    }

    struct FixedAssessmentEngine: ExchangeProviderResponseAssessmentEngine, Sendable {
        let assessment: ExchangeProviderResponseAssessment?
        func assessProviderResponse(
            context: ExchangeSecondHalfExecutionContext,
            priorAssessment: ExchangeProviderResponseAssessment?
        ) -> ExchangeProviderResponseAssessment? {
            assessment
        }
    }

    func fixtureContext(
        clarificationRounds: Int = 0
    ) -> ExchangeSecondHalfExecutionContext {
        ExchangeSecondHalfExecutionContext(
            role: .requester,
            currentState: .stalled,
            knownFacts: ["Need a home in GTA with seller financing flexibility."],
            unresolvedIssues: ["Please confirm seller financing terms and next Saturday availability."],
            hasFreshProviderAnswer: true,
            clarificationRounds: clarificationRounds,
            selectedCounterpartyID: "cp-1",
            selectedPublicProfileID: "profile-1",
            selectedOfferID: "offer-1",
            subjectMatter: "Find home with seller financing",
            requestedItems: ["Confirm VTB terms", "Confirm next Saturday availability"],
            clarifiedFacts: ["Location: GTA"]
        )
    }
}
