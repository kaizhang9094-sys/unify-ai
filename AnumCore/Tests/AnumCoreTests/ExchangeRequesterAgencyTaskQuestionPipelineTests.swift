import XCTest

@testable import AnumCore

/// Pass-2 pipeline: gap reducer → decision needs → agency packet → compose prompt (no on-device LLM).
final class ExchangeRequesterAgencyTaskQuestionPipelineTests: XCTestCase {

  private let userRequest =
    "Find me a plumber in Austin for a leak repair this Saturday afternoon."

  func testTaskQuestionSurvivesDecisionNeedsAndAutonomousPacketWithoutLLMCompare() throws {
    let offer = genericPlumbingOffer(leakRepairMentioned: false)
    let pipeline = buildPipeline(
      offer: offer,
      pass2DirectedOverride: nil,
      pass2LLMCompareSucceeded: false
    )

    let needs = pipeline.decisionNeeds
    XCTAssertTrue(
      needs.recommendedQuestions.contains { $0.lowercased().contains("leak repair") },
      "recommended=\(needs.recommendedQuestions)"
    )
    XCTAssertFalse(
      needs.recommendedQuestions.contains { $0.lowercased().contains("services matching") }
    )

    let packet = pipeline.autonomousPacket
    XCTAssertFalse(packet.pass2LLMCompareSucceeded)
    XCTAssertTrue(
      packet.recommendedQuestions.contains { $0.lowercased().contains("leak repair") },
      "rec=\(packet.recommendedQuestions)"
    )
    let directed = try XCTUnwrap(packet.providerDirectedQuestionLines)
    XCTAssertTrue(
      directed.contains { $0.lowercased().contains("leak repair") },
      "directed=\(directed)"
    )
    XCTAssertFalse(directed.joined(separator: " ").lowercased().contains("services matching"))

    let prompt = ExchangeAgencyDraftRewriteEngine.debugRequesterAutonomousComposePrompt(packet: packet)
    XCTAssertTrue(prompt.lowercased().contains("leak repair"), prompt.prefix(400).description)
    XCTAssertTrue(prompt.contains("REQUIRED PROVIDER QUESTIONS"), prompt.prefix(200).description)
    XCTAssertFalse(prompt.lowercased().contains("canonicalintent"))
    XCTAssertFalse(prompt.lowercased().contains("intent gap"))
    XCTAssertFalse(prompt.lowercased().contains("services matching"))

    XCTAssertTrue(
      pipeline.autonomousPacket.missingFacts.allSatisfy { !$0.lowercased().contains("intent gap") },
      "missingFacts should strip internal intent-gap labels from autonomous packet: \(packet.missingFacts)"
    )
  }

  func testSatisfiedOfferOmitsLeakRepairClarificationQuestion() {
    let offer = genericPlumbingOffer(leakRepairMentioned: true)
    let pipeline = buildPipeline(
      offer: offer,
      pass2DirectedOverride: nil,
      pass2LLMCompareSucceeded: false
    )

    let serviceGap = pipeline.gapOutput.gaps.first {
      $0.kind == .service && $0.source == "canonicalIntent"
    }
    XCTAssertEqual(serviceGap?.status, .satisfied)

    XCTAssertFalse(
      pipeline.decisionNeeds.recommendedQuestions.contains { $0.lowercased().contains("leak repair") }
    )
    let directed = pipeline.autonomousPacket.providerDirectedQuestionLines ?? []
    XCTAssertFalse(directed.contains { $0.lowercased().contains("leak repair") })
  }

  func testCompareSucceededEmptyDirectedOmitsDeterministicGapMaterialFromComposePrompt() {
    let offer = genericPlumbingOffer(leakRepairMentioned: false)
    let pipeline = buildPipeline(
      offer: offer,
      pass2DirectedOverride: [],
      pass2LLMCompareSucceeded: true
    )

    XCTAssertTrue(
      pipeline.decisionNeeds.recommendedQuestions.contains { $0.lowercased().contains("leak repair") },
      "decision needs still reflect gaps for diagnostics"
    )

    let packet = pipeline.autonomousPacket
    XCTAssertTrue(packet.pass2LLMCompareSucceeded)
    XCTAssertTrue(packet.recommendedQuestions.isEmpty, "rec=\(packet.recommendedQuestions)")
    XCTAssertTrue(packet.missingFacts.isEmpty, "missing=\(packet.missingFacts)")
    XCTAssertNil(packet.providerDirectedQuestionLines)

    let prompt = ExchangeAgencyDraftRewriteEngine.debugRequesterAutonomousComposePrompt(packet: packet)
    XCTAssertTrue(
      prompt.lowercased().contains("do not invent new provider questions"),
      prompt.prefix(500).description
    )
    XCTAssertFalse(prompt.contains("for this request?"))
    XCTAssertFalse(prompt.contains("Can you confirm whether you are available"))
    XCTAssertFalse(prompt.contains("What hardened timeline"))
    XCTAssertTrue(prompt.contains("not used to invent provider questions"))
    XCTAssertFalse(prompt.lowercased().contains("derive only from user request + missing facts"))
  }

  func testCompareSucceededPreservesOnlyGuardedDirectedQuestionInComposePrompt() throws {
    let offer = genericPlumbingOffer(leakRepairMentioned: false)
    let guardedQuestion = "Do you handle leak repairs?"
    let pipeline = buildPipeline(
      offer: offer,
      pass2DirectedOverride: [guardedQuestion],
      pass2LLMCompareSucceeded: true
    )

    let packet = pipeline.autonomousPacket
    XCTAssertTrue(packet.pass2LLMCompareSucceeded)
    XCTAssertTrue(packet.recommendedQuestions.isEmpty)
    let directed = try XCTUnwrap(packet.providerDirectedQuestionLines)
    XCTAssertEqual(directed, [guardedQuestion])

    let prompt = ExchangeAgencyDraftRewriteEngine.debugRequesterAutonomousComposePrompt(packet: packet)
    XCTAssertTrue(prompt.contains(guardedQuestion))
    XCTAssertFalse(prompt.contains("for this request?"))
    XCTAssertFalse(prompt.contains("Can you confirm whether you are available"))
    XCTAssertFalse(prompt.contains("What hardened timeline"))
  }

  func testCompareFailedStillAllowsFilteredGapBackstopInPacket() throws {
    let offer = genericPlumbingOffer(leakRepairMentioned: false)
    let pipeline = buildPipeline(
      offer: offer,
      pass2DirectedOverride: nil,
      pass2LLMCompareSucceeded: false
    )

    XCTAssertFalse(pipeline.autonomousPacket.pass2LLMCompareSucceeded)
    let directed = try XCTUnwrap(pipeline.autonomousPacket.providerDirectedQuestionLines)
    XCTAssertTrue(directed.contains { $0.lowercased().contains("leak repair") })

    let prompt = ExchangeAgencyDraftRewriteEngine.debugRequesterAutonomousComposePrompt(packet: pipeline.autonomousPacket)
    XCTAssertFalse(prompt.lowercased().contains("intent gap"))
    XCTAssertFalse(prompt.lowercased().contains("services matching"))
  }

  // MARK: - Pipeline fixture

  private struct PipelineFixture {
    var gapOutput: ExchangeRequesterIntentGapReducer.Output
    var context: ExchangeAgencyContext
    var decisionNeeds: ExchangeRequesterDecisionNeeds
    var autonomousPacket: RequesterClarificationDraftPacket
  }

  private func buildPipeline(
    offer: ExchangeOffer,
    pass2DirectedOverride: [String]?,
    pass2LLMCompareSucceeded: Bool
  ) -> PipelineFixture {
    let searchIntent = plumberLeakRepairIntent()
    let thread = threadFixture(searchIntent: searchIntent)
    let gapOutput = ExchangeRequesterIntentGapReducer().reduce(
      input: .init(
        thread: thread,
        searchIntent: searchIntent,
        offer: offer,
        operatingMemory: ExchangeStructuredOperatingMemory()
      )
    )

    let context = ExchangeAgencyContextBuilder.buildRequesterContext(
      threadID: thread.id,
      selectedOfferID: offer.id,
      userIntent: userRequest,
      offer: offer,
      operatingMemory: ExchangeStructuredOperatingMemory(),
      intentGaps: gapOutput.gaps,
      intentGapCombinedClarificationQuestion: gapOutput.combinedProviderQuestion
    )

    let decisionNeeds = ExchangeRequesterDecisionNeedsEngine().evaluate(context: context)

    let execution = ExchangeSecondHalfExecutionContext(
      threadID: thread.id,
      role: .requester,
      currentState: .requesterReview,
      selectedOfferID: offer.id
    )

    let autonomousPacket = ExchangeAgencyDraftPacketBuilder.buildRequesterAutonomousOutboundPacket(
      context: context,
      decisionNeeds: decisionNeeds,
      executionContext: execution,
      styleProfile: .default,
      composeMode: .askClarification,
      maxLength: 420,
      providerDirectedQuestionLinesResolved: pass2DirectedOverride,
      pass2LLMCompareSucceeded: pass2LLMCompareSucceeded,
      facets: thread.facets,
      searchIntent: searchIntent
    )

    return PipelineFixture(
      gapOutput: gapOutput,
      context: context,
      decisionNeeds: decisionNeeds,
      autonomousPacket: autonomousPacket
    )
  }

  private func plumberLeakRepairIntent() -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
    ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
      domainCategory: .homeService,
      objectType: "plumber",
      transactionIntent: .hire,
      places: [
        .init(normalizedText: "Austin", aliases: [], confidence: 0.9, isHard: true)
      ],
      timeConstraints: [
        .init(kind: .specific, text: "this Saturday afternoon")
      ],
      broadRecallTokens: ["leak repair"],
      semanticConcepts: ["leak repair"],
      extractionSource: .llmFlatSummary
    )
  }

  private func genericPlumbingOffer(leakRepairMentioned: Bool) -> ExchangeOffer {
    if leakRepairMentioned {
      return ExchangeOffer(
        id: "offer-plumber",
        nodeID: "node-1",
        title: "Licensed Plumber — Austin",
        summary: "Licensed plumber offering leak repair and general plumbing in Austin.",
        category: "plumbing",
        tags: ["plumber", "plumbing", "Austin", "leak repair"],
        regionTags: ["Austin"]
      )
    }
    return ExchangeOffer(
      id: "offer-plumber",
      nodeID: "node-1",
      title: "Licensed Plumber — Austin",
      summary: "Licensed plumber providing general plumbing services for residential homes in Austin.",
      category: "plumbing",
      tags: ["plumber", "plumbing", "Austin"],
      regionTags: ["Austin"]
    )
  }

  private func threadFixture(
    searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
  ) -> ExchangeThread {
    ExchangeThread(
      mode: .transactional,
      intent: ExchangeIntent(
        kind: .find,
        mode: .transactional,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer,
        title: "Find plumber",
        objective: userRequest
      ),
      posture: ExchangePosture(privacy: .balanced),
      facets: ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer
      ),
      state: .searching(.init())
    )
  }

  // MARK: - Autonomous compose body (stub runner)

  func testCompareSucceededEmptyDirectedComposeAcceptsSafeIntroWithoutInventedQuestions() async {
    let offer = genericPlumbingOffer(leakRepairMentioned: true)
    let pipeline = buildPipeline(
      offer: offer,
      pass2DirectedOverride: [],
      pass2LLMCompareSucceeded: true
    )
    let packet = pipeline.autonomousPacket
    XCTAssertTrue(packet.pass2LLMCompareSucceeded)
    XCTAssertNil(packet.providerDirectedQuestionLines)

    let prompt = ExchangeAgencyDraftRewriteEngine.debugRequesterAutonomousComposePrompt(packet: packet)
    XCTAssertTrue(prompt.contains("grounded compare found no provider clarification needed"))
    XCTAssertTrue(prompt.lowercased().contains("do not invent new provider questions"))

    let safeJSON = """
    {"subject":"","body":"Hi — I came across your profile and it looks like a good fit for my leak repair need in Austin. I wanted to reach out and see if we might connect."}
    """
    let result = await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
      packet: packet,
      runner: FixedJSONExchangeRunner(response: safeJSON)
    )
    XCTAssertTrue(result.accepted, "rejection=\(result.rejectionReasons)")
    assertNoInventedProviderQuestionPatterns(in: result.body)
  }

  func testCompareSucceededEmptyDirectedComposeRejectsInventedProviderQuestions() async {
    let offer = genericPlumbingOffer(leakRepairMentioned: true)
    let pipeline = buildPipeline(
      offer: offer,
      pass2DirectedOverride: [],
      pass2LLMCompareSucceeded: true
    )
    let packet = pipeline.autonomousPacket

    let inventingJSON = """
    {"subject":"","body":"Can you confirm whether you are available this Saturday afternoon for this request? What is your pricing and certification?"}
    """
    let result = await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
      packet: packet,
      runner: FixedJSONExchangeRunner(response: inventingJSON)
    )
    XCTAssertFalse(result.accepted, "invented diligence should not be accepted when compare succeeded with no directed questions")
    XCTAssertFalse(result.body.isEmpty)
  }

  func testCompareSucceededPreservesDirectedQuestionWithoutExtraDiligence() async {
    let offer = genericPlumbingOffer(leakRepairMentioned: false)
    let directed = "Do you handle leak repairs?"
    let pipeline = buildPipeline(
      offer: offer,
      pass2DirectedOverride: [directed],
      pass2LLMCompareSucceeded: true
    )
    let packet = pipeline.autonomousPacket
    let prompt = ExchangeAgencyDraftRewriteEngine.debugRequesterAutonomousComposePrompt(packet: packet)
    XCTAssertTrue(prompt.contains(directed))

    let preservingJSON = """
    {"subject":"","body":"Hi — I'm looking for a plumber in Austin for a leak repair this Saturday afternoon. Do you handle leak repairs?"}
    """
    let result = await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
      packet: packet,
      runner: FixedJSONExchangeRunner(response: preservingJSON)
    )
    XCTAssertTrue(result.accepted, "rejection=\(result.rejectionReasons)")
    XCTAssertTrue(result.body.lowercased().contains("leak repair"))
    assertNoExtraProviderDiligenceBeyondDirected(in: result.body, allowedSubstance: "leak repair", packet: packet)
  }

  func testCompareSucceededRejectsBodyThatAddsExtraDiligenceBeyondDirectedQuestion() async {
    let offer = genericPlumbingOffer(leakRepairMentioned: false)
    let directed = "Do you handle leak repairs?"
    let pipeline = buildPipeline(
      offer: offer,
      pass2DirectedOverride: [directed],
      pass2LLMCompareSucceeded: true
    )
    let packet = pipeline.autonomousPacket

    let extraJSON = """
    {"subject":"","body":"Do you handle leak repairs? Also, are you available this Saturday afternoon?"}
    """
    let result = await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
      packet: packet,
      runner: FixedJSONExchangeRunner(response: extraJSON)
    )
    XCTAssertFalse(result.accepted, "extra diligence beyond directed compare lines should be rejected")
  }

  private func assertNoInventedProviderQuestionPatterns(in body: String) {
    let lower = body.lowercased()
    let forbidden = inventedProviderQuestionNeedles
    for needle in forbidden where lower.contains(needle) {
      XCTFail("body must not invent provider questions; found `\(needle)` in: \(body)")
    }
    XCTAssertFalse(body.contains("?"), "body must not contain question marks when compare succeeded with no directed questions: \(body)")
  }

  private func assertNoExtraProviderDiligenceBeyondDirected(
    in body: String,
    allowedSubstance: String,
    packet: RequesterClarificationDraftPacket
  ) {
    let lower = body.lowercased()
    let extras = [
      "are you available",
      "what is your pricing",
      "certification",
      "credential",
      "for this request?",
      "for this job?"
    ]
    let allowsPricing = packet.outboundComposeContract?.allowedEnrichmentDimensions.contains(.pricingProcess) == true
      || packet.outboundComposeContract?.allowedEnrichmentDimensions.contains(.estimateRange) == true
    for needle in extras where lower.contains(needle) {
      if allowsPricing, ["what is your pricing", "pricing", "estimate", "quote"].contains(where: { needle.contains($0) || lower.contains($0) }) {
        continue
      }
      XCTFail("body must not add extra diligence; found `\(needle)` in: \(body)")
    }
    XCTAssertTrue(lower.contains(allowedSubstance.lowercased()))
  }

  private var inventedProviderQuestionNeedles: [String] {
    [
      "can you confirm",
      "could you confirm",
      "are you available",
      "what is your pricing",
      "certification",
      "credential",
      "for this request?",
      "for this job?",
      "hardened timeline",
      "high-level cues",
      "underspecified publicly",
      "services matching"
    ]
  }
  // MARK: - Controlled optional enrichment (unit / synthetic compose)

  func testPricingProcessAllowedAcceptsHowYourPricingWorksBody() {
    let packet = packetWithDirected(
      directed: ["Do you handle leak repairs?"],
      allowedEnrichment: [.pricingProcess]
    )
    let body = """
    Hi, I'm looking for a licensed plumber in Austin to handle a leak repair this Saturday afternoon. Could you let me know if you handle leak repairs and how your pricing works? Thanks.
    """
    let reasons = ExchangeAgencyDraftValidator.validateRequesterAutonomousOutbound(body: body, packet: packet)
    XCTAssertTrue(reasons.isEmpty, "rejection=\(reasons)")
    XCTAssertTrue(ExchangeAgencyDraftValidator.detectedEnrichmentDimensions(in: body).contains(.pricingProcess))
  }

  func testEstimateWordingAllowedWhenPricingOrEstimateEnrichmentAllowed() {
    let packet = packetWithDirected(
      directed: ["Do you handle leak repairs?"],
      allowedEnrichment: [.pricingProcess]
    )
    let body = "Could you let me know if you handle leak repairs and how estimates usually work?"
    let reasons = ExchangeAgencyDraftValidator.validateRequesterAutonomousOutbound(body: body, packet: packet)
    XCTAssertTrue(reasons.isEmpty, "rejection=\(reasons)")
  }

  func testNoEnrichmentRejectsPricingBody() {
    let packet = packetWithDirected(
      directed: ["Do you handle leak repairs?"],
      allowedEnrichment: []
    )
    let body = "Could you let me know if you handle leak repairs and how your pricing works?"
    let reasons = ExchangeAgencyDraftValidator.validateRequesterAutonomousOutbound(body: body, packet: packet)
    XCTAssertTrue(reasons.contains("extra_provider_diligence_beyond_compare_directed"))
  }

  func testPricingAllowedRejectsCredentialQuestion() {
    let packet = packetWithDirected(
      directed: ["Do you handle leak repairs?"],
      allowedEnrichment: [.pricingProcess]
    )
    let body = "Could you confirm if you handle leak repairs and whether you are licensed and insured?"
    let reasons = ExchangeAgencyDraftValidator.validateRequesterAutonomousOutbound(body: body, packet: packet)
    XCTAssertTrue(reasons.contains("extra_provider_diligence_beyond_compare_directed"))
  }

  func testDirectedLeakNoEnrichmentRejectsPricingBody() async {
    let packet = packetWithDirected(
      directed: ["Do you handle leak repairs?"],
      allowedEnrichment: []
    )
    let json = """
    {"subject":"","body":"Do you handle leak repairs? How do estimates or pricing usually work for this kind of job?"}
    """
    let result = await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
      packet: packet,
      runner: FixedJSONExchangeRunner(response: json)
    )
    XCTAssertFalse(result.accepted)
    XCTAssertTrue(result.rejectionReasons.contains { $0.contains("extra_provider_diligence") })
  }

  func testDirectedLeakPricingEnrichmentAllowedAcceptsPricingBody() async {
    let packet = packetWithDirected(
      directed: ["Do you handle leak repairs?"],
      allowedEnrichment: [.pricingProcess]
    )
    let json = """
    {"subject":"","body":"Hi — I need a plumber in Austin for a leak repair Saturday afternoon. Do you handle leak repairs, and how do estimates or pricing usually work?"}
    """
    let result = await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
      packet: packet,
      runner: FixedJSONExchangeRunner(response: json)
    )
    XCTAssertTrue(result.accepted, "rejection=\(result.rejectionReasons)")
  }

  func testDirectedLeakPricingAllowedRejectsCredentialBody() async {
    let packet = packetWithDirected(
      directed: ["Do you handle leak repairs?"],
      allowedEnrichment: [.pricingProcess]
    )
    let json = """
    {"subject":"","body":"Could you confirm if you handle leak repairs and whether you are licensed and insured?"}
    """
    let result = await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
      packet: packet,
      runner: FixedJSONExchangeRunner(response: json)
    )
    XCTAssertFalse(result.accepted)
    XCTAssertTrue(result.rejectionReasons.contains { $0.contains("extra_provider_diligence") })
  }

  func testEmptyDirectedRejectsQuoteEstimateBody() {
    let packet = packetWithDirected(directed: [], allowedEnrichment: [])
    let body = "What is your pricing for leak repairs?"
    let reasons = ExchangeAgencyDraftValidator.validateRequesterAutonomousOutbound(body: body, packet: packet)
    XCTAssertTrue(reasons.contains("invented_provider_question_when_compare_empty"))
  }

  func testEmptyDirectedCompareSucceededRejectsQuoteBody() async {
    let packet = packetWithDirected(directed: [], allowedEnrichment: [])
    let json = """
    {"subject":"","body":"What is your pricing for leak repairs?"}
    """
    let result = await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
      packet: packet,
      runner: FixedJSONExchangeRunner(response: json)
    )
    XCTAssertFalse(result.accepted)
  }

  func testSocialPacketNoEnrichmentRejectsPricingBody() async {
    let packet = socialPacketWithoutEnrichment()
    let json = """
    {"subject":"","body":"Would you be open to playing tennis on weekday evenings? What is your pricing?"}
    """
    let result = await ExchangeAgencyDraftRewriteEngine.composeRequesterAutonomousOutbound(
      packet: packet,
      runner: FixedJSONExchangeRunner(response: json)
    )
    XCTAssertFalse(result.accepted)
  }

  func testPromptIncludesOptionalEnrichmentBlockWhenAllowed() {
    let packet = packetWithDirected(
      directed: ["Do you handle leak repairs?"],
      allowedEnrichment: [.pricingProcess]
    )
    let prompt = ExchangeAgencyDraftRewriteEngine.debugRequesterAutonomousComposePrompt(packet: packet)
    XCTAssertTrue(prompt.contains("OPTIONAL ENRICHMENT"))
    XCTAssertTrue(prompt.contains("pricingProcess"))
  }

  func testPromptStrictNoPricingWhenEnrichmentAbsent() {
    let packet = packetWithDirected(
      directed: ["Do you handle leak repairs?"],
      allowedEnrichment: []
    )
    let prompt = ExchangeAgencyDraftRewriteEngine.debugRequesterAutonomousComposePrompt(packet: packet)
    XCTAssertTrue(prompt.contains("No optional enrichment is allowed"))
    XCTAssertTrue(prompt.lowercased().contains("do not add quote, estimate, pricing"))
  }

  func testPromptEmptyDirectedSaysNoProviderQuestions() {
    let packet = packetWithDirected(directed: [], allowedEnrichment: [])
    let prompt = ExchangeAgencyDraftRewriteEngine.debugRequesterAutonomousComposePrompt(packet: packet)
    XCTAssertTrue(prompt.lowercased().contains("do not ask any provider question"))
  }

  private func packetWithDirected(
    directed: [String],
    allowedEnrichment: [RequesterOutboundEnrichmentDimension]
  ) -> RequesterClarificationDraftPacket {
    let hints = allowedEnrichment.map { RequesterOutboundEnrichmentPolicy.hint(for: $0) }
    return RequesterClarificationDraftPacket(
      threadID: nil,
      selectedOfferID: nil,
      selectedPublicProfileID: nil,
      selectedCounterpartyID: nil,
      originalUserRequest: userRequest,
      selectedProfileSummary: nil,
      selectedOfferSummary: "General plumbing",
      knownFacts: [],
      missingFacts: [],
      recommendedQuestions: [],
      alreadyAsked: [],
      alreadyAnswered: [],
      styleProfile: .default,
      forbiddenClaims: [],
      forbiddenActions: [],
      maxLength: 420,
      requiredIntent: .requesterClarificationOnly,
      autonomousComposeMode: .askClarification,
      providerDirectedQuestionLines: directed.isEmpty ? nil : directed,
      pass2LLMCompareSucceeded: true,
      outboundComposeContract: RequesterOutboundComposeContract(
        routingSurface: "provider/offer",
        requiredProviderQuestionLines: directed,
        allowedEnrichmentDimensions: allowedEnrichment,
        allowedEnrichmentHints: hints,
        maxOptionalEnrichmentCount: allowedEnrichment.isEmpty ? 0 : 1
      )
    )
  }

  private func socialPacketWithoutEnrichment() -> RequesterClarificationDraftPacket {
    RequesterClarificationDraftPacket(
      threadID: nil,
      selectedOfferID: nil,
      selectedPublicProfileID: nil,
      selectedCounterpartyID: nil,
      originalUserRequest: "Find people nearby who want a tennis partner for weekday evenings.",
      selectedProfileSummary: nil,
      selectedOfferSummary: "Casual tennis group",
      knownFacts: [],
      missingFacts: [],
      recommendedQuestions: [],
      alreadyAsked: [],
      alreadyAnswered: [],
      styleProfile: .default,
      forbiddenClaims: [],
      forbiddenActions: [],
      maxLength: 420,
      requiredIntent: .requesterClarificationOnly,
      autonomousComposeMode: .askClarification,
      providerDirectedQuestionLines: [],
      pass2LLMCompareSucceeded: true,
      outboundComposeContract: RequesterOutboundComposeContract(
        routingSurface: "social/affinity",
        requiredProviderQuestionLines: [],
        allowedEnrichmentDimensions: [],
        allowedEnrichmentHints: [],
        maxOptionalEnrichmentCount: 0
      )
    )
  }


}

/// Returns fixed JSON/text for deterministic autonomous compose tests.
private struct FixedJSONExchangeRunner: ExchangeIntelligenceModelRunner {
  let response: String

  func run(_ request: ExchangeIntelligenceModelRunRequest) async throws -> String {
    _ = request
    return response
  }
}
