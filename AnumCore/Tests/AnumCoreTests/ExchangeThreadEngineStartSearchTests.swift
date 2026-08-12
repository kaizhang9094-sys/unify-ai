import XCTest
@testable import AnumCore

final class ExchangeThreadEngineStartSearchTests: XCTestCase {

    private let engine = ExchangeThreadEngine()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func sampleIntent(title: String = "Find a roofer") -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            title: title,
            objective: title
        )
    }

    private func auroraFacets() -> ExchangeIntentFacets {
        ExchangeIntentFacets(
            searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
                places: [.init(normalizedText: "Aurora", aliases: [], confidence: 0.9, isHard: true)],
                extractionSource: .heuristicFallback
            ),
            queryIntentClass: .offerSearch,
            surfacePreference: .offer,
            placeName: "Aurora",
            locationRequirement: ExchangeLocationRequirement(
                displayName: "Aurora",
                normalizedName: "aurora",
                kind: .namedPlace,
                strictness: .required
            ),
            regionTerms: ["aurora"]
        )
    }

    func testDraftingFirstSearchUsesSearchStarted() throws {
        let opened = engine.beginThread(
            userText: "Find me a roofer.",
            mode: .transactional,
            intent: sampleIntent(),
            now: now
        )

        XCTAssertEqual(opened.thread.stateKey, .drafting)

        let mutation = try engine.startSearch(
            thread: opened.thread,
            querySummary: "Find me a roofer.",
            now: now
        )

        guard case .searching(let status) = mutation.thread.state else {
            return XCTFail("expected searching, got \(mutation.thread.state)")
        }
        XCTAssertEqual(status.querySummary, "Find me a roofer.")
        XCTAssertEqual(mutation.turns.count, 1)
        XCTAssertEqual(mutation.turns.first?.kind, .searchStarted)
    }

    func testNoViableMatchRetryUsesRetryRequestedAndPreservesFacets() throws {
        let opened = engine.beginThread(
            userText: "Find me a roofer.",
            mode: .transactional,
            intent: sampleIntent(),
            now: now
        )

        let searching = try engine.startSearch(
            thread: opened.thread,
            querySummary: "Find me a roofer.",
            now: now
        )

        let noMatch = try engine.recordNoMatch(
            thread: searching.thread,
            explanation: "No viable matches found.",
            nextStep: "Refine your search.",
            now: now
        )

        XCTAssertEqual(noMatch.thread.stateKey, .noViableMatch)

        let refinedIntent = sampleIntent(title: "Find a roofer in Aurora")
        let facets = auroraFacets()
        let refreshed = noMatch.thread.refreshingForReuse(
            intent: refinedIntent,
            posture: ExchangePosture(privacy: .balanced),
            facets: facets,
            at: now
        )

        XCTAssertEqual(refreshed.facets?.regionTerms, ["aurora"])
        XCTAssertEqual(refreshed.facets?.placeName, "Aurora")

        let retry = try engine.startSearch(
            thread: refreshed,
            querySummary: "Find a roofer in Aurora",
            now: now
        )

        guard case .searching(let status) = retry.thread.state else {
            return XCTFail("expected searching after retry, got \(retry.thread.state)")
        }
        XCTAssertEqual(status.querySummary, "Find a roofer in Aurora")
        XCTAssertEqual(retry.thread.facets?.regionTerms, ["aurora"])
        XCTAssertEqual(retry.thread.facets?.placeName, "Aurora")
        XCTAssertEqual(retry.turns.first?.kind, .searchStarted)
        XCTAssertEqual(retry.thread.visibleSummary, "Searching for candidates.")
    }

    func testNoViableMatchToSearchingViaSearchStartedIsIllegal() {
        let illegal = ExchangeTransition(
            from: .noViableMatch,
            to: .searching,
            trigger: .searchStarted
        )
        XCTAssertFalse(ExchangeTransition.legalTransitions.contains(illegal))

        let legal = ExchangeTransition(
            from: .noViableMatch,
            to: .searching,
            trigger: .retryRequested
        )
        XCTAssertTrue(ExchangeTransition.legalTransitions.contains(legal))
    }
}

private extension ExchangeThread {
    var stateKey: ExchangeTransition.ExchangeStateKey {
        ExchangeTransition.ExchangeStateKey(state)
    }
}
