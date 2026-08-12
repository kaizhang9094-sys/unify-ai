import XCTest
@testable import AnumCore

final class ExchangeChildCoordinationSearchQueryTests: XCTestCase {

    private let engine = ExchangeThreadEngine()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let posture = ExchangePosture(privacy: .balanced)

    private func dogPurchaseIntent() -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .offer,
            title: "Buy a dog",
            objective: "Buy a dog"
        )
    }

    private func sampleMatch(threadID: ExchangeThread.ID) -> ExchangeMatch {
        ExchangeMatch(
            threadID: threadID,
            counterpartyID: "provider-1",
            publicProfileID: "profile-1",
            offerID: "offer-dog",
            strength: .strong,
            score: 0.9
        )
    }

    func testBeginChildCoordinationThreadWritesSingleSearchStartedWithChildRequestText() throws {
        let userRequest = "I want to buy a dog."
        let umbrella = engine.beginThread(
            userText: userRequest,
            mode: .transactional,
            intent: dogPurchaseIntent(),
            posture: posture,
            now: now
        )

        let creation = try engine.beginChildCoordinationThread(
            from: umbrella.thread,
            sourceMatch: sampleMatch(threadID: umbrella.thread.id),
            sourceRank: 1,
            originalRequesterText: userRequest,
            originalRequesterTextSource: "umbrellaRequestCaptured",
            summary: "Found a likely path through Provider One.",
            now: now
        )

        let searchStartedTurns = creation.turns.filter { $0.kind == .searchStarted }
        XCTAssertEqual(searchStartedTurns.count, 1)
        XCTAssertEqual(searchStartedTurns.first?.summary, userRequest)
        XCTAssertEqual(searchStartedTurns.first?.detail, userRequest)
    }

    func testRecordSelectedMatchDoesNotAppendSecondSearchStarted() throws {
        let userRequest = "find me a computer under 500 tomorrow"
        let umbrella = engine.beginThread(
            userText: userRequest,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                title: "Computer",
                objective: userRequest
            ),
            posture: posture,
            now: now
        )

        let selectionSummary = "Found a likely path through Tech Seller."
        let creation = try engine.beginChildCoordinationThread(
            from: umbrella.thread,
            sourceMatch: sampleMatch(threadID: umbrella.thread.id),
            sourceRank: 1,
            originalRequesterText: userRequest,
            originalRequesterTextSource: "umbrellaRequestCaptured",
            summary: selectionSummary,
            now: now
        )

        XCTAssertEqual(creation.turns.filter { $0.kind == .searchStarted }.count, 1)
        XCTAssertEqual(creation.turns.filter { $0.kind == .candidateSelected }.count, 1)
        XCTAssertEqual(creation.turns.last?.kind, .candidateSelected)
        XCTAssertEqual(creation.turns.last?.summary, selectionSummary)
        XCTAssertEqual(creation.thread.visibleSummary, selectionSummary)
    }

    func testResolvePrefersOriginalRequesterTextMetadataOverPoisonedInterpretation() {
        var umbrella = ExchangeThread(
            mode: .transactional,
            intent: dogPurchaseIntent(),
            posture: posture,
            interpretation: ExchangeThread.InterpretationSnapshot(
                userSummary: "Found a likely path through Provider One."
            ),
            state: .matchCandidatesWeak(
                .init(candidateCount: 2, explanation: "Found paths", suggestedRefinement: nil)
            ),
            visibleSummary: "Found a likely path through Provider One."
        )
        umbrella.metadata[ExchangeThread.originalRequesterTextMetadataKey] = "I want to buy a dog."

        let resolution = ExchangeChildCoordinationRequestText.resolveChildRequestCapturedText(
            umbrellaTurns: [],
            umbrellaThread: umbrella
        )

        XCTAssertEqual(resolution.text, "I want to buy a dog.")
        XCTAssertEqual(resolution.source, "originalRequesterText")
    }

    func testResolveUsesRequestCapturedWhenMetadataAbsent() {
        let threadID = UUID()
        let turns = [
            ExchangeTurn.requestCaptured(
                threadID: threadID,
                summary: "find me a cleaner tomorrow at 2 under 200",
                createdAt: now
            )
        ]
        let umbrella = ExchangeThread(
            id: threadID,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .providerSearch,
                title: "Cleaner",
                objective: "Cleaner"
            ),
            posture: posture,
            state: .matchCandidatesWeak(
                .init(candidateCount: 1, explanation: "Found paths", suggestedRefinement: nil)
            )
        )

        let resolution = ExchangeChildCoordinationRequestText.resolveChildRequestCapturedText(
            umbrellaTurns: turns,
            umbrellaThread: umbrella
        )

        XCTAssertEqual(resolution.text, "find me a cleaner tomorrow at 2 under 200")
        XCTAssertEqual(resolution.source, "umbrellaLatestRequestCaptured")
    }

    func testDisplaySearchQueryUsesOriginalRequestNotSelectionSummary() throws {
        let userRequest = "find me someone who repairs laptops"
        let umbrella = engine.beginThread(
            userText: userRequest,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .providerSearch,
                title: "Laptop repair",
                objective: userRequest
            ),
            posture: posture,
            now: now
        )

        let creation = try engine.beginChildCoordinationThread(
            from: umbrella.thread,
            sourceMatch: sampleMatch(threadID: umbrella.thread.id),
            sourceRank: 1,
            originalRequesterText: userRequest,
            originalRequesterTextSource: "umbrellaRequestCaptured",
            summary: "Found a likely path through Repair Shop.",
            now: now
        )

        let query = ExchangeThreadSearchQueryDisplay.displaySearchQuery(
            for: creation.thread,
            turns: creation.turns
        )

        XCTAssertEqual(query?.text, userRequest)
        XCTAssertNotEqual(query?.text, creation.thread.visibleSummary)
    }

    func testResolveUsesPrimarySearchTextWhenMetadataAndTurnsAbsent() {
        let umbrella = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                title: "Car",
                objective: "find me a car"
            ),
            posture: posture,
            state: .matchCandidatesWeak(
                .init(candidateCount: 1, explanation: "Found paths", suggestedRefinement: nil)
            )
        )

        let resolution = ExchangeChildCoordinationRequestText.resolveChildRequestCapturedText(
            umbrellaTurns: [],
            umbrellaThread: umbrella
        )

        XCTAssertEqual(resolution.source, "primarySearchText")
        XCTAssertEqual(resolution.text, "Car find me a car")
    }

    func testVisibleSummaryFallbackOnlyWhenAllStrongerSourcesAbsent() {
        let umbrella = ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .generalDiscovery,
                title: " ",
                objective: " "
            ),
            posture: posture,
            interpretation: ExchangeThread.InterpretationSnapshot(
                discoveryKeywords: ["exchange", "request"],
                userSummary: "Found a likely path through Provider One."
            ),
            state: .matchCandidatesWeak(
                .init(candidateCount: 1, explanation: "Found paths", suggestedRefinement: nil)
            ),
            visibleSummary: "Emergency visible summary only"
        )

        let resolution = ExchangeChildCoordinationRequestText.resolveChildRequestCapturedText(
            umbrellaTurns: [],
            umbrellaThread: umbrella
        )

        XCTAssertEqual(resolution.source, "visibleSummaryFallback")
        XCTAssertEqual(resolution.text, "Emergency visible summary only")
    }

    func testVisibleSummaryStillUsedForDisplayWhileQueryHelperUsesOriginalRequest() throws {
        let userRequest = "find me a computer under 500 tomorrow"
        let umbrella = engine.beginThread(
            userText: userRequest,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                title: "Computer",
                objective: userRequest
            ),
            posture: posture,
            now: now
        )

        let selectionSummary = "Found a likely path through Tech Seller."
        let creation = try engine.beginChildCoordinationThread(
            from: umbrella.thread,
            sourceMatch: sampleMatch(threadID: umbrella.thread.id),
            sourceRank: 1,
            originalRequesterText: userRequest,
            originalRequesterTextSource: "umbrellaRequestCaptured",
            summary: selectionSummary,
            now: now
        )

        XCTAssertEqual(creation.thread.visibleSummary, selectionSummary)
        XCTAssertEqual(
            ExchangeThreadSearchQueryDisplay.displaySearchQuery(for: creation.thread, turns: creation.turns)?.text,
            userRequest
        )
    }
}
