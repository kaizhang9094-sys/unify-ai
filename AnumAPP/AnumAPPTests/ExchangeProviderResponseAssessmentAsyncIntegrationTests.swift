import XCTest
@testable import AnumCore

final class ExchangeProviderResponseAssessmentAsyncIntegrationTests: XCTestCase {
    func test_asyncAssessmentInjected_usedForFollowUp_whenAllowed() async {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                asyncAssessmentEngine: FixedAsyncAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm seller financing terms", source: .commercialConstraint, status: .notAnswered)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )

        let result = await coordinator.evaluateAsync(
            context: anchoredContext(clarificationRounds: 0),
            policy: ExchangeSecondHalfPolicy(clarificationRoundLimit: 2)
        )
        XCTAssertEqual(result.plan.selectedAction, .askClarification)
    }

    func test_asyncAssessmentContradiction_producesJudgmentOrInputMove() async {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                asyncAssessmentEngine: FixedAsyncAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "seller financing", source: .commercialConstraint, status: .contradicted)
                        ],
                        nextMoveRecommendation: .requestUserInput,
                        requiresHumanJudgment: true,
                        safeForAutonomousFollowup: false
                    )
                )
            )
        )

        let result = await coordinator.evaluateAsync(context: anchoredContext())
        XCTAssertTrue(result.plan.selectedAction == .requestUserInput || result.plan.selectedAction == .frameDecision)
    }

    func test_noAsyncEngine_behaviorMatchesCurrentSyncPath() async {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                assessmentEngine: nil,
                asyncAssessmentEngine: nil
            )
        )
        let context = anchoredContext()

        let sync = coordinator.evaluate(context: context)
        let async = await coordinator.evaluateAsync(context: context)

        XCTAssertEqual(sync.plan.selectedAction, async.plan.selectedAction)
        XCTAssertEqual(sync.nextState, async.nextState)
    }

    func test_asyncEngineFallbackAssessmentStillConsumed() async {
        let fallbackAssessment = ExchangeProviderResponseAssessment(
            conditionAssessments: [
                .init(conditionText: "confirm availability", source: .gapFill, status: .needsFollowUp)
            ],
            nextMoveRecommendation: .askClarification,
            safeForAutonomousFollowup: true
        )
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                asyncAssessmentEngine: FixedAsyncAssessmentEngine(assessment: fallbackAssessment)
            )
        )

        let result = await coordinator.evaluateAsync(context: anchoredContext())
        XCTAssertEqual(result.plan.selectedAction, .askClarification)
    }

    func test_anchorGuardStillWins_withAsyncAssessmentFollowUp() async {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                asyncAssessmentEngine: FixedAsyncAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm provider pricing", source: .gapFill, status: .notAnswered)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )

        let result = await coordinator.evaluateAsync(context: unanchoredContext())
        XCTAssertEqual(result.plan.selectedAction, .requestUserInput)
    }

    func test_clarificationLimitStillWins_withAsyncAssessmentFollowUp() async {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                asyncAssessmentEngine: FixedAsyncAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm timeline", source: .timingConstraint, status: .needsFollowUp)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )

        let result = await coordinator.evaluateAsync(
            context: anchoredContext(clarificationRounds: 1),
            policy: ExchangeSecondHalfPolicy(clarificationRoundLimit: 1)
        )
        XCTAssertNotEqual(result.plan.selectedAction, .askClarification)
    }

    func test_boundaryGateStillWins_withAsyncAssessmentFollowUp() async {
        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                asyncAssessmentEngine: FixedAsyncAssessmentEngine(
                    assessment: .init(
                        conditionAssessments: [
                            .init(conditionText: "confirm legal terms", source: .commercialConstraint, status: .needsFollowUp)
                        ],
                        nextMoveRecommendation: .askClarification,
                        safeForAutonomousFollowup: true
                    )
                )
            )
        )

        var context = anchoredContext()
        context.includesLegalCommercialCommitment = true
        let result = await coordinator.evaluateAsync(context: context)
        XCTAssertTrue(result.boundary.requiresHumanApproval)
    }
}

private extension ExchangeProviderResponseAssessmentAsyncIntegrationTests {
    struct FixedAsyncAssessmentEngine: AsyncExchangeProviderResponseAssessmentEngine, Sendable {
        let assessment: ExchangeProviderResponseAssessment?

        func assessProviderResponse(
            context: ExchangeSecondHalfExecutionContext,
            priorAssessment: ExchangeProviderResponseAssessment?
        ) async -> ExchangeProviderResponseAssessment? {
            assessment
        }
    }

    func anchoredContext(
        clarificationRounds: Int = 0
    ) -> ExchangeSecondHalfExecutionContext {
        ExchangeSecondHalfExecutionContext(
            role: .requester,
            currentState: .stalled,
            knownFacts: ["Need home in GTA"],
            unresolvedIssues: ["Please confirm seller financing terms."],
            hasFreshProviderAnswer: true,
            clarificationRounds: clarificationRounds,
            selectedCounterpartyID: "cp-1",
            selectedPublicProfileID: "profile-1",
            selectedOfferID: "offer-1",
            subjectMatter: "home with seller financing",
            requestedItems: ["confirm vtb terms"],
            clarifiedFacts: ["location: gta"]
        )
    }

    func unanchoredContext() -> ExchangeSecondHalfExecutionContext {
        ExchangeSecondHalfExecutionContext(
            role: .requester,
            currentState: .stalled,
            knownFacts: ["Need provider details"],
            unresolvedIssues: ["Please confirm provider pricing."],
            hasFreshProviderAnswer: true,
            selectedCounterpartyID: nil,
            selectedPublicProfileID: nil,
            selectedOfferID: nil,
            subjectMatter: "need provider details",
            requestedItems: ["confirm pricing"],
            clarifiedFacts: []
        )
    }
}

final class ExchangeEndToEndPipelineAdversarialTests: XCTestCase {
    func test_adversarialPipelineMatrix_reportsShortfallsAcross20Scenarios() async throws {
        let scenarios = makeScenarios()
        XCTAssertEqual(scenarios.count, 20)

        var reports: [ScenarioReport] = []
        reports.reserveCapacity(scenarios.count)

        for scenario in scenarios {
            let report = await runScenario(scenario)
            reports.append(report)
            print(
                "E2E_SCENARIO|\(scenario.id)|\(scenario.name)|backend=\(report.backendResult.rawValue)|ui=\(report.uiResult.rawValue)|layer=\(report.failedLayer)|mismatch=\(report.mismatchType.rawValue)|notes=\(report.notes)"
            )
        }

        let passCount = reports.filter { $0.backendResult == .pass && $0.uiResult == .pass }.count
        let failCount = reports.filter { $0.backendResult == .fail || $0.uiResult == .fail }.count
        let riskCount = reports.filter { $0.backendResult == .risk || $0.uiResult == .risk }.count
        let partialCount = reports.filter { $0.backendResult == .partial || $0.uiResult == .partial }.count
        let blockedCount = reports.filter { $0.backendResult == .blocked || $0.uiResult == .blocked }.count

        print(
            "E2E_SUMMARY|total=\(reports.count)|pass=\(passCount)|partial=\(partialCount)|fail=\(failCount)|risk=\(riskCount)|blocked=\(blockedCount)"
        )
        XCTAssertEqual(reports.count, 20)
    }
}

private extension ExchangeEndToEndPipelineAdversarialTests {
    enum ScenarioStatus: String {
        case pass = "PASS"
        case partial = "PARTIAL"
        case fail = "FAIL"
        case blocked = "BLOCKED"
        case risk = "RISK"
    }

    enum MismatchType: String {
        case backendNotSurfaced = "backend-not-surfaced"
        case surfacedTooGeneric = "surfaced-too-generic"
        case staleUIState = "stale-ui-state"
        case wrongCTA = "wrong-CTA"
        case wrongBucket = "wrong-bucket"
        case privateInfoRisk = "private-info-risk"
        case debugOnlyNeeded = "debug-only-needed"
        case userConfusingExplanation = "user-confusing-explanation"
        case noMismatch = "no-mismatch"
    }

    struct ScenarioDefinition {
        let id: Int
        let name: String
        let requesterAsk: String
        let providerReply: String?
        let offers: [ExchangeOffer]
        let profileSummary: String
        let extractionJSON: String
        let enrichmentJSON: String?
        let assessmentJSON: String?
        let assessmentReady: Bool
        let forceAssessmentThrow: Bool
        let context: ExchangeSecondHalfExecutionContext
        let expectedAction: ExchangeSecondHalfAction?
        let expectDecisionReady: Bool
        let expectHiddenLeakBlocked: Bool
    }

    struct ScenarioReport {
        let backendResult: ScenarioStatus
        let uiResult: ScenarioStatus
        let failedLayer: String
        let mismatchType: MismatchType
        let notes: String
    }

    actor FixedAsyncSearchProvider: AsyncSearchIntentJSONProvider {
        let rawJSON: String
        let ready: Bool
        init(rawJSON: String, ready: Bool = true) {
            self.rawJSON = rawJSON
            self.ready = ready
        }
        func isReadyForImmediateExtraction() async -> Bool { ready }
        func extractSearchIntentJSON(prompt: String) async throws -> String {
            rawJSON
        }
    }

    actor FixedAsyncEnrichmentProvider: AsyncProviderSurfaceEnrichmentJSONProvider {
        let rawJSON: String
        let ready: Bool
        init(rawJSON: String, ready: Bool = true) {
            self.rawJSON = rawJSON
            self.ready = ready
        }
        func isReadyForImmediateExtraction() async -> Bool { ready }
        func enrichProviderSurfaceJSON(prompt: String) async throws -> String { rawJSON }
    }

    actor FixedAsyncAssessmentProvider: AsyncProviderResponseAssessmentJSONProvider {
        let rawJSON: String
        let ready: Bool
        let throwing: Bool
        init(rawJSON: String, ready: Bool = true, throwing: Bool = false) {
            self.rawJSON = rawJSON
            self.ready = ready
            self.throwing = throwing
        }
        enum ProviderErr: Error { case unavailable }
        func isReadyForImmediateExtraction() async -> Bool { ready }
        func assessProviderResponseJSON(prompt: String) async throws -> String {
            if throwing { throw ProviderErr.unavailable }
            return rawJSON
        }
    }

    func runScenario(_ s: ScenarioDefinition) async -> ScenarioReport {
        let intent = fixtureIntent(s.requesterAsk)
        let searchStore = SearchIntentExtractionDiagnosticsStore()
        let extractionProvider = FixedAsyncSearchProvider(rawJSON: s.extractionJSON, ready: true)
        let asyncExtractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: extractionProvider,
            diagnosticsStore: searchStore
        )
        let canonical = await asyncExtractor.extract(sourceText: s.requesterAsk, intent: intent)

        let profile = fixtureProfile(summary: s.profileSummary)
        let indexed = ExchangeIndexedProviderSurfaceBuilder().build(profile: profile, offers: s.offers)

        let enrichmentStore = ProviderSurfaceEnrichmentDiagnosticsStore()
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: s.enrichmentJSON.map { FixedAsyncEnrichmentProvider(rawJSON: $0, ready: true) },
            diagnosticsStore: enrichmentStore
        )
        let enriched = await enricher.enrich(surface: indexed)
        let docs = ExchangeRetrievalDocumentBuilder().build(from: enriched, counterpartyID: "cp-1", sourceKind: .local)

        let assessmentStore = ProviderResponseAssessmentDiagnosticsStore()
        let fallback = ExchangeHeuristicProviderResponseAssessmentEngine()
        let assessmentProvider = FixedAsyncAssessmentProvider(
            rawJSON: s.assessmentJSON ?? "{}",
            ready: s.assessmentReady,
            throwing: s.forceAssessmentThrow
        )
        let asyncAssessmentEngine = LLMExchangeProviderResponseAssessmentEngine(
            provider: assessmentProvider,
            fallback: fallback,
            diagnosticsStore: assessmentStore
        )

        let coordinator = ExchangeSecondHalfCoordinator(
            requesterFlow: ExchangeSecondHalfRequesterFlow(
                asyncAssessmentEngine: asyncAssessmentEngine
            )
        )
        let result = await coordinator.evaluateAsync(
            context: s.context,
            policy: ExchangeSecondHalfPolicy(clarificationRoundLimit: 2)
        )
        let display = ExchangeSecondHalfUIAdapter().makeDisplayModel(from: result)

        let searchDiag = await searchStore.last
        let enrichDiag = await enrichmentStore.last
        let assessDiag = await assessmentStore.last

        var notes: [String] = []
        var backend: ScenarioStatus = .pass
        var ui: ScenarioStatus = .pass
        var failedLayer = "none"
        var mismatch: MismatchType = .noMismatch

        if canonical == nil {
            backend = .fail
            failedLayer = "extraction"
            notes.append("canonical nil")
        }

        if docs.isEmpty {
            backend = .fail
            failedLayer = failedLayer == "none" ? "retrieval" : failedLayer
            notes.append("retrieval docs empty")
        }

        if s.expectHiddenLeakBlocked {
            let text = docs.map(\.searchableText).joined(separator: " ").lowercased()
            if text.contains("waterproofing") && s.offers.contains(where: { $0.visibility == .hidden || $0.status != .active }) {
                backend = .fail
                failedLayer = "publication/payload/privacy"
                mismatch = .privateInfoRisk
                notes.append("hidden content leaked into retrieval docs")
            }
        }

        if let expectedAction = s.expectedAction, result.plan.selectedAction != expectedAction {
            backend = backend == .fail ? .fail : .partial
            failedLayer = failedLayer == "none" ? "planning" : failedLayer
            notes.append("expected action \(expectedAction.rawValue), got \(result.plan.selectedAction.rawValue)")
        }

        if s.expectDecisionReady != display.status.isDecisionReady {
            ui = .partial
            mismatch = .surfacedTooGeneric
            notes.append("decision-ready mismatch in UI status")
        }

        if display.summary.lowercased() == "provider replied." || display.recommendation.lowercased() == "follow up" {
            ui = ui == .pass ? .risk : ui
            mismatch = mismatch == .noMismatch ? .surfacedTooGeneric : mismatch
            notes.append("generic surface wording")
        }

        if searchDiag?.source == .heuristicFallback || assessDiag?.source == .heuristicFallback || enrichDiag?.source == .fallbackOriginal {
            backend = backend == .pass ? .risk : backend
            if mismatch == .noMismatch { mismatch = .debugOnlyNeeded }
            notes.append("fallback engaged")
        }

        if s.context.selectedCounterpartyID == nil && result.plan.selectedAction != .requestUserInput {
            backend = .fail
            failedLayer = "gates"
            mismatch = .wrongCTA
            notes.append("anchor guard was not enforced")
        }

        return ScenarioReport(
            backendResult: backend,
            uiResult: ui,
            failedLayer: failedLayer,
            mismatchType: mismatch,
            notes: notes.isEmpty ? "none" : notes.joined(separator: "; ")
        )
    }

    func makeScenarios() -> [ScenarioDefinition] {
        let vtbExtraction = encode(LLMSearchIntentExtractionDTO(
            objectType: "home",
            domainHint: "real estate",
            transactionIntentHint: "for sale",
            places: [.init(text: "GTA", aliases: ["Greater Toronto Area"], confidence: 0.93, isHard: false)],
            attributes: [.init(key: "bedrooms", value: "3 bedroom", numericValue: 3)],
            commercialConstraints: [.init(kind: "financing", key: "sellerFinancing", value: "vendor take-back mortgage", isHard: false)],
            semanticConcepts: ["seller financing", "vendor take-back mortgage"],
            broadRecallTokens: ["home", "gta"],
            confidence: 0.9
        ))
        let generalExtraction = encode(LLMSearchIntentExtractionDTO(
            objectType: "service provider",
            semanticConcepts: ["general help"],
            broadRecallTokens: ["help"],
            confidence: 0.7
        ))
        let noisyAssessment = "noise ```json\n{\"conditionAssessments\":[{\"conditionText\":\"seller financing\",\"source\":\"commercialConstraint\",\"status\":\"needsFollowUp\"}],\"nextMoveRecommendation\":\"askClarification\",\"safeForAutonomousFollowup\":true}\n```"
        let positiveAssessment = "{\"conditionAssessments\":[{\"conditionText\":\"seller financing\",\"source\":\"commercialConstraint\",\"status\":\"partiallySatisfied\"}],\"missingInfo\":[\"down payment\",\"rate\",\"term\",\"amount\"],\"nextMoveRecommendation\":\"askClarification\",\"safeForAutonomousFollowup\":true}"
        let contradictedAssessment = "{\"conditionAssessments\":[{\"conditionText\":\"seller financing\",\"source\":\"commercialConstraint\",\"status\":\"contradicted\"}],\"confidenceDelta\":\"decrease\",\"nextMoveRecommendation\":\"requestUserInput\",\"safeForAutonomousFollowup\":false,\"requiresHumanJudgment\":true}"

        let activeOffer = fixtureOffer(summary: "GTA home listing; seller financing may be considered depending on deposit.")
        let hiddenWaterproofOffer = fixtureOffer(id: "hidden-1", summary: "Emergency basement waterproofing specialist", status: .active, visibility: .hidden)
        let pausedMechanicOffer = fixtureOffer(id: "paused-1", summary: "Mobile mechanic weekend service paused", status: .paused, visibility: .publicDiscoverable)
        let publicGeneralOffer = fixtureOffer(id: "public-1", summary: "General renovation and home maintenance")

        return [
            scenario(1, "Real estate VTB soft", ask: "Find me a 3 bedroom home in the GTA where the seller may offer vendor take back mortgage.", offers: [activeOffer], extraction: vtbExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(2, "VTB explicit contradiction", ask: "Find me a 3 bedroom home in the GTA where the seller may offer vendor take back mortgage.", offers: [activeOffer], extraction: vtbExtraction, assessment: contradictedAssessment, expected: .requestUserInput, decisionReady: false),
            scenario(3, "Hard location vs soft", ask: "Find a roofer in Aurora who can come tomorrow at 2pm for an appraisal.", offers: [fixtureOffer(summary: "Roofer serves Richmond Hill and Markham only")], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(4, "Nearby soft location", ask: "Find a roofer near Aurora, ideally available tomorrow.", offers: [fixtureOffer(summary: "Roofer serves Newmarket Richmond Hill Aurora region")], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(5, "Profile available offer unavailable", ask: "Find a mobile mechanic available this weekend.", offers: [pausedMechanicOffer], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(6, "Hidden offer leak", ask: "Find someone who does emergency basement waterproofing.", offers: [hiddenWaterproofOffer, publicGeneralOffer], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false, hiddenLeakBlocked: true),
            scenario(7, "Ski buddy social", ask: "Find a ski buddy for Mount St. Louis next Saturday, beginner friendly.", offers: [fixtureOffer(summary: "Enjoys skiing and beginner-friendly Saturdays")], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(8, "Dating social boundary", ask: "Find someone who likes dogs and wants to grab coffee.", offers: [fixtureOffer(summary: "Dog lover open to coffee chats")], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(9, "First-time developer budget", ask: "Find a contractor willing to work with a first-time developer on a small budget.", offers: [fixtureOffer(summary: "Works with new developers, flexible phased pricing")], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(10, "Negative constraint", ask: "Find a photographer for a wedding, but not someone who only does studio shoots.", offers: [fixtureOffer(summary: "Studio-only photographer"), fixtureOffer(id: "event-1", summary: "Wedding and event photographer")], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(11, "Multi-condition overload", ask: "Find a licensed electrician in Mississauga who handles EV charger installs, can provide ESA paperwork, and is available within 2 weeks.", offers: [fixtureOffer(summary: "EV charger installs and ESA paperwork available in 4 weeks")], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(12, "Ambiguous ask", ask: "Help me find someone for my house.", offers: [fixtureOffer(summary: "General helper")], extraction: "{}", assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(13, "Busy fallback", ask: "Looking for a house in GTA with seller financing.", offers: [activeOffer], extraction: vtbExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false, assessmentReady: false),
            scenario(14, "Noisy JSON repair", ask: "Find me a ski buddy who has time next Saturday to Mount St. Louis.", offers: [fixtureOffer(summary: "Ski buddy available Saturday")], extraction: vtbExtraction, assessment: noisyAssessment, expected: .askClarification, decisionReady: false),
            scenario(15, "Commitment boundary pressure", ask: "Ask them to confirm they will hold the house for me if I send a deposit tomorrow.", offers: [activeOffer], extraction: vtbExtraction, assessment: positiveAssessment, expected: .requestUserInput, decisionReady: false, legalCommitment: true),
            scenario(16, "Reply answers different question", ask: "Need VTB confirmation.", offers: [activeOffer], extraction: vtbExtraction, assessment: "{\"conditionAssessments\":[{\"conditionText\":\"vtb terms\",\"source\":\"commercialConstraint\",\"status\":\"notAnswered\"}],\"nextMoveRecommendation\":\"askClarification\",\"safeForAutonomousFollowup\":true}", expected: .askClarification, decisionReady: false),
            scenario(17, "Contradictory evidence", ask: "Need financing flexibility.", offers: [fixtureOffer(summary: "financing flexible")], extraction: vtbExtraction, assessment: contradictedAssessment, expected: .requestUserInput, decisionReady: false),
            scenario(18, "Disclosure ceiling private note", ask: "Can they do 20% discount?", offers: [fixtureOffer(summary: "public pricing available")], extraction: generalExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(19, "Regional alias GTA", ask: "Find a 3 bedroom place in GTA.", offers: [fixtureOffer(summary: "Toronto Mississauga Vaughan listings")], extraction: vtbExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false),
            scenario(20, "Full happy path", ask: "Find a 3 bedroom home in GTA with possible VTB.", offers: [activeOffer], extraction: vtbExtraction, assessment: positiveAssessment, expected: .askClarification, decisionReady: false)
        ]
    }

    func scenario(
        _ id: Int,
        _ name: String,
        ask: String,
        offers: [ExchangeOffer],
        extraction: String,
        assessment: String?,
        expected: ExchangeSecondHalfAction?,
        decisionReady: Bool,
        hiddenLeakBlocked: Bool = false,
        assessmentReady: Bool = true,
        legalCommitment: Bool = false
    ) -> ScenarioDefinition {
        var context = ExchangeSecondHalfExecutionContext(
            role: .requester,
            currentState: .stalled,
            knownFacts: ["Need alignment with requester ask"],
            unresolvedIssues: ["Please confirm provider specifics for \(ask)"],
            hasFreshProviderAnswer: true,
            clarificationRounds: 0,
            selectedCounterpartyID: "cp-1",
            selectedPublicProfileID: "profile-1",
            selectedOfferID: offers.first?.id ?? "offer-1",
            subjectMatter: ask,
            requestedItems: ["confirm suitability"],
            clarifiedFacts: []
        )
        context.includesLegalCommercialCommitment = legalCommitment
        return ScenarioDefinition(
            id: id,
            name: name,
            requesterAsk: ask,
            providerReply: nil,
            offers: offers,
            profileSummary: "Provider profile for \(name)",
            extractionJSON: extraction,
            enrichmentJSON: "{\"semanticConcepts\":[\"indexed signal\"],\"softPreferences\":[\"flexible\"],\"commercialConstraints\":[{\"text\":\"seller financing may be considered\",\"isHard\":false}],\"timeAvailabilityConstraints\":[{\"text\":\"weekend slots\",\"isHard\":false}],\"broadRecallTokens\":[\"gta\"],\"sourceTextBlocks\":[\"public text\"],\"confidence\":0.9}",
            assessmentJSON: assessment,
            assessmentReady: assessmentReady,
            forceAssessmentThrow: false,
            context: context,
            expectedAction: expected,
            expectDecisionReady: decisionReady,
            expectHiddenLeakBlocked: hiddenLeakBlocked
        )
    }

    func fixtureIntent(_ raw: String) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "fixture",
            objective: raw
        )
    }

    func fixtureProfile(summary: String) -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            displayName: "Provider One",
            headline: "Local provider",
            summary: summary,
            visibility: .discoverable,
            interests: ["homes"],
            offers: ["services"],
            openTo: ["requests"],
            excludedTopics: [],
            activityTags: ["service"],
            regionTags: ["gta"],
            canonicalRegionIDs: ["ca-on-gta"],
            parentRegionIDs: ["ca-on"],
            regionAliases: ["greater toronto area"],
            semantic: .init(
                domains: ["real estate"],
                intentKinds: ["service"],
                notes: summary
            )
        )
    }

    func fixtureOffer(
        id: String = UUID().uuidString,
        summary: String,
        status: ExchangeOffer.Status = .active,
        visibility: ExchangeOffer.Visibility = .publicDiscoverable
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: id,
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Offer \(id)",
            summary: summary,
            category: "service",
            tags: ["service"],
            regionTags: ["gta"],
            semantic: .init(domains: ["real estate"], serviceKinds: ["general"]),
            fulfillment: .init(
                pricingMode: .quoteRequired,
                commitmentMode: .exploratory,
                remoteFriendly: false,
                leadTimeNote: "next week"
            ),
            status: status,
            visibility: visibility,
            commercialFacts: .empty
        )
    }

    func encode(_ dto: LLMSearchIntentExtractionDTO) -> String {
        let data = try! JSONEncoder().encode(dto)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
