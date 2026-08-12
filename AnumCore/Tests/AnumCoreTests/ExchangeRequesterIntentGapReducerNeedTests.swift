import XCTest

@testable import AnumCore

final class ExchangeRequesterIntentGapReducerNeedTests: XCTestCase {

  private let reducer = ExchangeRequesterIntentGapReducer()

  // MARK: - 1. Plumber + leak repair (task missing on offer)

  func testPlumberLeakRepairProducesServiceGapWithTaskQuestion() {
    let si = plumberLeakRepairIntent()
    let offer = genericPlumbingOffer(leakRepairMentioned: false)
    let output = reduce(searchIntent: si, offer: offer)

    let gap = canonicalServiceGap(from: output)
    XCTAssertNotNil(gap)
    XCTAssertEqual(gap?.status, .unknown)
    XCTAssertEqual(gap?.requestedValue, "leak repair")
    XCTAssertEqual(gap?.label, "Service / category")
    XCTAssertEqual(gap?.source, "canonicalIntent")

    let question = gap?.questionForProvider?.lowercased() ?? ""
    XCTAssertTrue(question.contains("leak repair"), "question=\(question)")
    XCTAssertFalse(question.contains("services matching"), "should not use noisy recall wrapper; question=\(question)")
    XCTAssertTrue(
      question.contains("handle") || question.contains("provide") || question.contains("offer"),
      question
    )

    let missingLines = ExchangeRequesterIntentGapReducer.userFacingMissingLines(from: output.gaps)
    XCTAssertTrue(missingLines.contains { $0.lowercased().contains("leak repair") }, missingLines.description)
  }

  // MARK: - 2. Plumber + leak repair satisfied

  func testPlumberLeakRepairSatisfiedWhenOfferMentionsTask() {
    let si = plumberLeakRepairIntent()
    let offer = genericPlumbingOffer(leakRepairMentioned: true)
    let output = reduce(searchIntent: si, offer: offer)

    let gap = canonicalServiceGap(from: output)
    XCTAssertNotNil(gap)
    XCTAssertEqual(gap?.status, .satisfied)
    XCTAssertNil(gap?.questionForProvider)
    XCTAssertTrue((gap?.evidence ?? "").lowercased().contains("matched"), gap?.evidence ?? "")
  }

  // MARK: - 3. Contractor + kitchen remodel

  func testContractorKitchenRemodelProducesTaskGap() {
    let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
      domainCategory: .homeService,
      objectType: "contractor",
      transactionIntent: .hire,
      broadRecallTokens: ["kitchen remodel"],
      semanticConcepts: ["kitchen remodel"],
      extractionSource: .llmFlatSummary
    )
    let offer = ExchangeOffer(
      id: "offer-contractor",
      nodeID: "node-1",
      title: "General Contractor",
      summary: "Residential renovation and handyman services.",
      category: "contractor",
      tags: ["contractor", "renovation"]
    )
    let output = reduce(searchIntent: si, offer: offer)

    let gap = canonicalServiceGap(from: output)
    XCTAssertEqual(gap?.status, .unknown)
    let question = gap?.questionForProvider?.lowercased() ?? ""
    XCTAssertTrue(question.contains("kitchen remodel"), question)
    XCTAssertFalse(question.contains("services matching"), question)
  }

  // MARK: - 4. Spanish tutor + conversational practice

  func testSpanishTutorConversationalPracticeProducesTaskGap() {
    let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
      domainCategory: .professionalService,
      objectType: "Spanish tutor",
      transactionIntent: .hire,
      broadRecallTokens: ["conversational practice"],
      semanticConcepts: ["conversational practice"],
      extractionSource: .llmFlatSummary
    )
    let offer = ExchangeOffer(
      id: "offer-tutor",
      nodeID: "node-1",
      title: "Spanish Tutor — Online Lessons",
      summary: "Native speaker offering Spanish lessons for beginners and intermediate students.",
      category: "tutoring",
      tags: ["spanish", "tutor", "lessons"]
    )
    let output = reduce(searchIntent: si, offer: offer)

    let gap = canonicalServiceGap(from: output)
    XCTAssertEqual(gap?.status, .unknown)
    let question = gap?.questionForProvider?.lowercased() ?? ""
    XCTAssertTrue(question.contains("conversational practice"), question)
    XCTAssertTrue(question.contains("offer"), "professional practice should use offer wording; question=\(question)")
  }

  // MARK: - 5. Object-only fallback

  func testObjectOnlyWithoutTaskPhrasesProducesNoCanonicalServiceGap() {
    let si = ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
      domainCategory: .homeService,
      objectType: "plumber",
      transactionIntent: .hire,
      broadRecallTokens: [],
      semanticConcepts: [],
      extractionSource: .llmFlatSummary
    )
    let offer = genericPlumbingOffer(leakRepairMentioned: false)
    let output = reduce(searchIntent: si, offer: offer)

  // Current model: empty recall + no extractable task phrase => no canonical service gap row.
    XCTAssertNil(canonicalServiceGap(from: output))
  }

  // MARK: - Helpers

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
    let summary: String
    let tags: [String]
    if leakRepairMentioned {
      summary = "Licensed plumber offering leak repair and general plumbing in Austin."
      tags = ["plumber", "plumbing", "Austin", "leak repair"]
    } else {
      summary = "Licensed plumber providing general plumbing services for residential homes in Austin."
      tags = ["plumber", "plumbing", "Austin"]
    }
    return ExchangeOffer(
      id: "offer-plumber",
      nodeID: "node-1",
      title: "Licensed Plumber — Austin",
      summary: summary,
      category: "plumbing",
      tags: tags,
      regionTags: ["Austin"]
    )
  }

  private func reduce(
    searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
    offer: ExchangeOffer
  ) -> ExchangeRequesterIntentGapReducer.Output {
    let thread = ExchangeThread(
      mode: .transactional,
      intent: ExchangeIntent(
        kind: .find,
        mode: .transactional,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer,
        title: "Find plumber",
        objective: "Find a plumber for leak repair in Austin"
      ),
      posture: ExchangePosture(privacy: .balanced),
      facets: ExchangeIntentFacets(
        searchIntent: searchIntent,
        queryIntentClass: .offerSearch,
        surfacePreference: .offer
      ),
      state: .searching(.init())
    )
    return reducer.reduce(
      input: .init(
        thread: thread,
        searchIntent: searchIntent,
        offer: offer,
        operatingMemory: ExchangeStructuredOperatingMemory()
      )
    )
  }



  private func canonicalServiceGap(
    from output: ExchangeRequesterIntentGapReducer.Output
  ) -> ExchangeRequesterIntentGap? {
    output.gaps.first { $0.kind == .service && $0.source == "canonicalIntent" }
  }
}
