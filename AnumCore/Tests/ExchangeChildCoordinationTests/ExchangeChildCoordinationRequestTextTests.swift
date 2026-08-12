import XCTest
@testable import AnumCore

final class ExchangeChildCoordinationRequestTextTests: XCTestCase {

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

    private func interpretationWithKeywordRails() -> ExchangeThread.InterpretationSnapshot {
        ExchangeThread.InterpretationSnapshot(
            semanticTags: ["dog", "seller"],
            discoveryKeywords: ["dog", "seller", "find", "general", "hire"],
            targetTags: ["dog seller"],
            userSummary: "I understood this as general discovery."
        )
    }

    private func sampleMatch(threadID: ExchangeThread.ID) -> ExchangeMatch {
        ExchangeMatch(
            threadID: threadID,
            counterpartyID: "provider-1",
            publicProfileID: "profile-1",
            strength: .strong,
            score: 0.9
        )
    }

    func testCapturedRequesterTextPrefersUserRequestCapturedTurn() {
        let threadID = UUID()
        let turns = [
            ExchangeTurn.requestCaptured(
                threadID: threadID,
                summary: "I want to buy a dog.",
                createdAt: now
            )
        ]

        XCTAssertEqual(
            ExchangeChildCoordinationRequestText.capturedRequesterText(from: turns),
            "I want to buy a dog."
        )
    }

    func testIsLikelyKeywordRailDetectsJoinedDiscoveryKeywords() {
        let interpretation = interpretationWithKeywordRails()
        XCTAssertTrue(
            ExchangeChildCoordinationRequestText.isLikelyKeywordRail(
                "dog seller find general hire",
                interpretation: interpretation
            )
        )
        XCTAssertFalse(
            ExchangeChildCoordinationRequestText.isLikelyKeywordRail(
                "I want to buy a dog.",
                interpretation: interpretation
            )
        )
    }

    func testResolveChildRequestCapturedTextPrefersUmbrellaTurnOverKeywordRails() {
        let threadID = UUID()
        let turns = [
            ExchangeTurn.requestCaptured(
                threadID: threadID,
                summary: "I want to buy a dog.",
                createdAt: now
            )
        ]
        let opened = engine.beginThread(
            userText: "dog seller find general hire",
            mode: .transactional,
            intent: dogPurchaseIntent(),
            posture: posture,
            interpretation: interpretationWithKeywordRails(),
            now: now
        )

        let resolution = ExchangeChildCoordinationRequestText.resolveChildRequestCapturedText(
            umbrellaTurns: turns,
            umbrellaThread: opened.thread,
            requestUserSummary: nil
        )

        XCTAssertEqual(resolution.text, "I want to buy a dog.")
        XCTAssertEqual(resolution.source, "umbrellaLatestRequestCaptured")
        XCTAssertNotEqual(
            resolution.text,
            opened.thread.interpretation!.discoveryKeywords.joined(separator: " ")
        )
    }

    func testBeginChildCoordinationThreadRequestCapturedUsesOriginalSentence() throws {
        let userRequest = "I want to buy a dog."
        let keywordRail = "dog seller find general hire"
        let interpretation = interpretationWithKeywordRails()

        let umbrella = engine.beginThread(
            userText: userRequest,
            mode: .transactional,
            intent: dogPurchaseIntent(),
            posture: posture,
            interpretation: interpretation,
            now: now
        )
        XCTAssertEqual(umbrella.turns.first?.summary, userRequest)

        let match = sampleMatch(threadID: umbrella.thread.id)
        let creation = try engine.beginChildCoordinationThread(
            from: umbrella.thread,
            sourceMatch: match,
            sourceRank: 1,
            originalRequesterText: userRequest,
            originalRequesterTextSource: "umbrellaRequestCaptured",
            now: now
        )

        let childRequestTurn = creation.turns.first(where: { $0.kind == ExchangeTurn.Kind.requestCaptured })
        XCTAssertEqual(childRequestTurn?.summary, userRequest)
        XCTAssertNotEqual(childRequestTurn?.summary, keywordRail)

        let searchQuery = creation.thread.primarySearchText
        XCTAssertTrue(searchQuery.contains("dog") || searchQuery.contains("seller"))
        XCTAssertNotEqual(searchQuery, userRequest)
    }

    func testDirectQueryChildRequestCapturedPreservesFullSentence() throws {
        let query = "roofer in Aurora tomorrow 2 PM"
        let interpretation = ExchangeThread.InterpretationSnapshot(
            discoveryKeywords: ["roofer", "aurora", "find", "general"],
            userSummary: "I understood this as a provider-facing search."
        )
        let umbrella = engine.beginThread(
            userText: query,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .offerSearch,
                surfacePreference: .offer,
                title: "Roofer in Aurora",
                objective: query
            ),
            posture: posture,
            interpretation: interpretation,
            now: now
        )

        let resolution = ExchangeChildCoordinationRequestText.resolveChildRequestCapturedText(
            umbrellaTurns: umbrella.turns,
            umbrellaThread: umbrella.thread
        )
        XCTAssertEqual(resolution.text, query)

        let creation = try engine.beginChildCoordinationThread(
            from: umbrella.thread,
            sourceMatch: sampleMatch(threadID: umbrella.thread.id),
            sourceRank: 1,
            originalRequesterText: resolution.text,
            originalRequesterTextSource: resolution.source,
            now: now
        )
        XCTAssertEqual(
            creation.turns.first(where: { $0.kind == ExchangeTurn.Kind.requestCaptured })?.summary,
            query
        )
    }

    func testSocialQueryChildRequestCapturedPreservesFullSentence() {
        let query = "hiking buddy near Toronto this weekend"
        let umbrella = engine.beginThread(
            userText: query,
            mode: .relational,
            intent: ExchangeIntent(
                kind: .find,
                mode: .relational,
                queryIntentClass: .socialAffinitySearch,
                surfacePreference: .affinity,
                title: "Hiking buddy",
                objective: query
            ),
            posture: posture,
            now: now
        )

        let resolution = ExchangeChildCoordinationRequestText.resolveChildRequestCapturedText(
            umbrellaTurns: umbrella.turns,
            umbrellaThread: umbrella.thread
        )
        XCTAssertEqual(resolution.text, query)
    }

    func testLegacyFallbackWhenNoRequestCapturedTurn() {
        let interpretation = interpretationWithKeywordRails()
        let umbrella = engine.beginThread(
            userText: "dog seller find general hire",
            mode: .transactional,
            intent: dogPurchaseIntent(),
            posture: posture,
            interpretation: interpretation,
            now: now
        )

        var thread = umbrella.thread
        thread.visibleSummary = nil

        let resolution = ExchangeChildCoordinationRequestText.resolveChildRequestCapturedText(
            umbrellaTurns: [],
            umbrellaThread: thread,
            requestUserSummary: nil
        )

        XCTAssertEqual(resolution.source, "humanizedIntent")
        XCTAssertEqual(resolution.text, "Buy a dog")
    }
}
