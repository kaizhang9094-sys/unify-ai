import XCTest

@testable import AnumCore

final class ExchangeRequesterMatchCompareGroundingTests: XCTestCase {

    func testGroundingSummaryIncludesTaskPlaceTimeAndRouting() throws {
        let intent = plumberLeakIntent()
        let summary = ExchangeRequesterCompareGroundingSummary.render(
            originalRequesterMessage: "Find me a plumber in Austin for a leak repair this Saturday afternoon.",
            searchIntent: intent,
            thread: nil,
            facets: ExchangeIntentFacets(
                searchIntent: intent,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer
            )
        )
        let text = try XCTUnwrap(summary)
        XCTAssertTrue(text.contains("task: leak repair"), text)
        XCTAssertTrue(text.contains("place: Austin"), text)
        XCTAssertTrue(text.contains("time: this Saturday afternoon"), text)
        XCTAssertTrue(text.contains("queryIntentClass: offerSearch"), text)
        XCTAssertTrue(text.contains("routingSurface: provider/offer"), text)
    }

    func testCollaborationRoutingSurface() throws {
        let summary = ExchangeRequesterCompareGroundingSummary.render(
            originalRequesterMessage: "Find someone to collaborate on an early-stage AI app.",
            searchIntent: nil,
            thread: nil,
            facets: ExchangeIntentFacets(
                queryIntentClass: .collaborationSearch,
                surfacePreference: .capability,
                capabilityTerms: ["AI app"]
            )
        )
        XCTAssertTrue(summary?.contains("routingSurface: capability/collaboration") == true)
    }

    func testGuardStripsForThisRequestAndScaffold() {
        let raw = ExchangeRequesterMatchCompareResult(
            missingFacts: ["Geographic/service area fit is underspecified publicly."],
            providerQuestions: [
                "Do you handle leak repairs for this request?",
                "Could you clarify: Geographic/service area fit is underspecified publicly."
            ],
            shouldAskProvider: true,
            reason: "timing"
        )
        let evidence = "licensed plumber leak repair pipe leaks austin"
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(raw, matchedEvidenceHaystack: evidence)

        XCTAssertFalse(out.providerQuestions.contains { $0.lowercased().contains("for this request") })
        XCTAssertFalse(out.providerQuestions.contains { $0.lowercased().contains("underspecified publicly") })
        XCTAssertFalse(out.providerQuestions.contains { $0.lowercased().contains("services matching") })
        XCTAssertLessThanOrEqual(out.providerQuestions.count, ExchangeRequesterMatchCompareOutputGuard.maxProviderQuestions)
    }

    func testGuardSuppressesRedundantServiceReaskWhenEvidenceConfirmsTask() {
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: ["Do you handle leak repairs?"],
            shouldAskProvider: true,
            reason: "test"
        )
        let evidence = "licensed plumber specializing in leak repair and pipe leaks in austin"
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(raw, matchedEvidenceHaystack: evidence)
        XCTAssertTrue(out.providerQuestions.isEmpty)
        XCTAssertFalse(out.shouldAskProvider)
    }

    func testGuardKeepsAvailabilityQuestionWhenTimingNotInEvidence() {
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: ["Are you available this Saturday afternoon?"],
            shouldAskProvider: true,
            reason: "timing"
        )
        let evidence = "licensed plumber leak repair austin"
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(raw, matchedEvidenceHaystack: evidence)
        XCTAssertEqual(out.providerQuestions.count, 1)
        XCTAssertTrue(out.providerQuestions.first?.lowercased().contains("saturday") == true)
    }

    func testCommercialSatisfiedCompareProducesNoQuestionsAfterGuard() {
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: [],
            shouldAskProvider: false,
            reason: "task and timing confirmed on surface"
        )
        let evidence = "leak repair austin saturday afternoon availability"
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(raw, matchedEvidenceHaystack: evidence)
        XCTAssertTrue(out.providerQuestions.isEmpty)
        XCTAssertFalse(out.shouldAskProvider)
    }

    func testPromptIncludesGroundingAndMatchedSurfaceEvidenceBlocks() {
        let grounding = """
        task: leak repair
        place: Austin
        time: this Saturday afternoon
        routingSurface: provider/offer
        """
        let prompt = ExchangeIntelligencePromptBuilder.requesterMatchComparePrompt(
            originalRequesterMessage: "Find plumber for leak repair",
            selectedOfferSummary: "Licensed plumber, leak repair",
            selectedProfileSummary: nil,
            counterpartyDisplayName: "Alex",
            knownFacts: [],
            styleProfile: .default,
            requesterRequirementsSummary: grounding
        )
        XCTAssertTrue(prompt.contains("REQUESTER INTENT GROUNDING"), prompt)
        XCTAssertTrue(prompt.contains("MATCHED SURFACE EVIDENCE"), prompt)
        XCTAssertTrue(prompt.contains("task: leak repair"), prompt)
        XCTAssertTrue(prompt.contains("grounded DELTA detector"), prompt)
        XCTAssertTrue(prompt.contains("Ask at most ONE natural clarification question"), prompt)
        XCTAssertTrue(prompt.contains("Never use robotic phrases"), prompt)
    }

    private func plumberLeakIntent() -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: .homeService,
            objectType: "plumber",
            transactionIntent: .hire,
            places: [.init(normalizedText: "Austin", aliases: [], confidence: 0.9, isHard: true)],
            timeConstraints: [.init(kind: .specific, text: "this Saturday afternoon")],
            broadRecallTokens: ["leak repair"],
            semanticConcepts: ["leak repair"],
            extractionSource: .llmFlatSummary
        )
    }

    // MARK: - Over-diligence / scaffold suppression

    func testGuardRemovesHardenedTimelineScaffoldQuestion() {
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: ["What hardened timeline should I rely on beyond high-level cues?"],
            shouldAskProvider: true,
            reason: "scaffold"
        )
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "conversation practice speaking"
        )
        XCTAssertTrue(out.providerQuestions.isEmpty)
        XCTAssertFalse(out.shouldAskProvider)
    }

    func testGuardRemovesRequesterPreferenceContractorTypeQuestion() {
        let grounding = """
        task: kitchen remodel
        place: 北京 Chaoyang
        time: 下周
        credentialOrLicenseRequired: false
        """
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: ["What is your preferred contractor type (general vs. specialized)?"],
            shouldAskProvider: true,
            reason: "preference"
        )
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "general contractor painting flooring",
            originalRequesterMessage: "Need contractor for kitchen remodel",
            requesterRequirementsSummary: grounding
        )
        XCTAssertTrue(out.providerQuestions.isEmpty)
        XCTAssertFalse(out.shouldAskProvider)
    }

    func testGuardRemovesUnrequestedCertificationQuestion() {
        let grounding = """
        task: check circuit at home
        place: 上海 Pudong
        time: 周末
        credentialOrLicenseRequired: false
        """
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: [
                "What is your preferred certification body or standard for this inspection?"
            ],
            shouldAskProvider: true,
            reason: "credential"
        )
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "electrician wiring breaker panels",
            originalRequesterMessage: "need certified electrician 上门检查电路",
            requesterRequirementsSummary: grounding
        )
        XCTAssertTrue(out.providerQuestions.isEmpty)
        XCTAssertFalse(out.shouldAskProvider)
    }

    func testGuardPreservesCleanTaskQuestion() {
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: ["Do you handle leak repairs?"],
            shouldAskProvider: true,
            reason: "task"
        )
        let evidence = "plumber general plumbing austin"
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: evidence,
            originalRequesterMessage: "plumber leak repair austin",
            requesterRequirementsSummary: "task: leak repair\ncredentialOrLicenseRequired: false"
        )
        XCTAssertEqual(out.providerQuestions, ["Do you handle leak repairs?"])
    }

    func testGuardPreservesCollaborationQuestion() {
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: ["Would you be open to collaborating on an early-stage AI app?"],
            shouldAskProvider: true,
            reason: "collaboration"
        )
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "ios swift ai builder open to collaboration",
            originalRequesterMessage: "Find someone to collaborate on an early-stage AI app",
            requesterRequirementsSummary: """
            routingSurface: capability/collaboration
            credentialOrLicenseRequired: false
            """
        )
        XCTAssertEqual(out.providerQuestions.count, 1)
        XCTAssertTrue(out.providerQuestions.first?.lowercased().contains("collaborat") == true)
    }

    func testGuardPreservesSocialAvailabilityQuestion() {
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: ["Are you open to hiking together on weekends?"],
            shouldAskProvider: true,
            reason: "social"
        )
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "hiking outdoors trail interest",
            originalRequesterMessage: "find people for weekend hiking",
            requesterRequirementsSummary: """
            routingSurface: social/affinity
            time: weekends
            credentialOrLicenseRequired: false
            """
        )
        XCTAssertEqual(out.providerQuestions.count, 1)
        XCTAssertTrue(out.providerQuestions.first?.lowercased().contains("weekend") == true)
    }

    func testGuardKeepsCredentialQuestionWhenIntentRequiresLicense() {
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: ["Are you licensed for residential electrical work?"],
            shouldAskProvider: true,
            reason: "credential"
        )
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "electrician wiring",
            originalRequesterMessage: "Need a licensed electrician",
            requesterRequirementsSummary: "credentialOrLicenseRequired: true"
        )
        XCTAssertEqual(out.providerQuestions.count, 1)
    }

    func testGuardRemovesTypicalTurnaroundWhenIntentOnlyHasSchedulingWeek() {
        let grounding = """
        task: kitchen remodel
        place: 北京 Chaoyang
        time: 下周
        credentialOrLicenseRequired: false
        """
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: [
                "What is your typical turnaround time for kitchen remodels in Chaoyang?"
            ],
            shouldAskProvider: true,
            reason: "timing"
        )
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "kitchen remodel renovation chaoyang",
            originalRequesterMessage: "Need contractor for kitchen remodel next week",
            requesterRequirementsSummary: grounding
        )
        XCTAssertTrue(out.providerQuestions.isEmpty)
        XCTAssertFalse(out.shouldAskProvider)
    }

    func testGuardPreservesAvailabilityQuestionForSchedulingWeek() {
        let grounding = """
        task: kitchen remodel
        place: 北京 Chaoyang
        time: 下周
        credentialOrLicenseRequired: false
        """
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: [
                "Are you available next week for a kitchen remodel in Chaoyang?"
            ],
            shouldAskProvider: true,
            reason: "timing"
        )
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "kitchen remodel renovation chaoyang",
            originalRequesterMessage: "Need contractor for kitchen remodel",
            requesterRequirementsSummary: grounding
        )
        XCTAssertEqual(out.providerQuestions.count, 1)
        XCTAssertTrue(out.providerQuestions.first?.lowercased().contains("available") == true)
    }

    func testGuardPreservesTurnaroundWhenRequesterExplicitlyAsks() {
        let message = "What is your typical turnaround time for a kitchen remodel?"
        let raw = ExchangeRequesterMatchCompareResult(
            providerQuestions: ["What is your turnaround time for kitchen remodels?"],
            shouldAskProvider: true,
            reason: "timing"
        )
        let out = ExchangeRequesterMatchCompareOutputGuard.sanitize(
            raw,
            matchedEvidenceHaystack: "kitchen remodel",
            originalRequesterMessage: message,
            requesterRequirementsSummary: "task: kitchen remodel\ntime: flexible"
        )
        XCTAssertEqual(out.providerQuestions.count, 1)
        XCTAssertTrue(out.providerQuestions.first?.lowercased().contains("turnaround") == true)
    }

}
