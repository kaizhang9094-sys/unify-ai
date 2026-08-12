import XCTest
@testable import AnumCore

final class ExchangeDeskSnapshotTitleProjectionTests: XCTestCase {

    private let threadID = UUID()

    func testShouldRejectInterpreterRouteClassifierTitles() {
        XCTAssertTrue(ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate("Find Provider"))
        XCTAssertTrue(ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate("Find Shared-Interest Match"))
        XCTAssertTrue(ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate("find provider"))
        XCTAssertTrue(ExchangeUserFacingCopySanitizer.isGenericExchangeTitle("Find Provider"))
    }

    func testShouldRejectAllowsUserDiscoveryTitle() {
        XCTAssertFalse(
            ExchangeThreadCardTitleProjection.shouldRejectTitleCandidate(
                "find me a wedding photographer in Toronto next Saturday under $800"
            )
        )
    }

    func testInboxCardTitlePrefersCapturedRequestOverProviderClassifierStoredTitle() {
        let userText = "find me a roofer in Aurora tomorrow at 2pm"
        let pick = ExchangeThreadCardTitleProjection.inboxCardTitle(
            requestCapturedFromTurn: userText,
            interpretationUserQuestion: nil,
            threadStoredTitle: "Find Provider",
            draftedSubject: nil,
            hydratedOpportunityTitle: nil,
            prioritizeHydratedOpportunityTitle: false,
            threadID: threadID,
            surface: "deskSnapshot"
        )

        XCTAssertEqual(pick.titleSource, "capturedRequest")
        XCTAssertTrue(pick.title.localizedCaseInsensitiveContains("roofer"))
        XCTAssertFalse(pick.title.localizedCaseInsensitiveContains("find provider"))
    }

    func testInboxCardTitlePrefersCapturedRequestOverSharedInterestClassifierStoredTitle() {
        let userText = "find someone nearby who likes hiking"
        let pick = ExchangeThreadCardTitleProjection.inboxCardTitle(
            requestCapturedFromTurn: userText,
            interpretationUserQuestion: nil,
            threadStoredTitle: "Find Shared-Interest Match",
            draftedSubject: nil,
            hydratedOpportunityTitle: nil,
            prioritizeHydratedOpportunityTitle: false,
            threadID: threadID,
            surface: "deskSnapshot"
        )

        XCTAssertEqual(pick.titleSource, "capturedRequest")
        XCTAssertTrue(pick.title.localizedCaseInsensitiveContains("hiking"))
    }

    func testInboxCardTitleFallbackWhenOnlyClassifierStoredTitle() {
        let pick = ExchangeThreadCardTitleProjection.inboxCardTitle(
            requestCapturedFromTurn: nil,
            interpretationUserQuestion: nil,
            threadStoredTitle: "Find Provider",
            draftedSubject: nil,
            hydratedOpportunityTitle: nil,
            prioritizeHydratedOpportunityTitle: false,
            threadID: threadID,
            surface: "deskSnapshot"
        )

        XCTAssertEqual(pick.titleSource, "fallback")
        XCTAssertEqual(pick.title, "New request")
    }

    func testInboxCardTitleUsesNonGenericStoredTitleWhenNoCapture() {
        let userTitle = "find me a wedding photographer in Toronto"
        let pick = ExchangeThreadCardTitleProjection.inboxCardTitle(
            requestCapturedFromTurn: nil,
            interpretationUserQuestion: nil,
            threadStoredTitle: userTitle,
            draftedSubject: nil,
            hydratedOpportunityTitle: nil,
            prioritizeHydratedOpportunityTitle: false,
            threadID: threadID,
            surface: "deskSnapshot"
        )

        XCTAssertEqual(pick.titleSource, "threadTitle")
        XCTAssertTrue(pick.title.localizedCaseInsensitiveContains("wedding photographer"))
    }

    func testDisplaySearchQueryUsesMetadataWhenTurnsEmpty() {
        var metadata: [String: String] = [:]
        metadata[ExchangeThread.originalRequesterTextMetadataKey] = "find me a roofer in Aurora tomorrow at 2pm"
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            surfacePreference: .offer,
            title: "Find Provider",
            objective: "find me a roofer in Aurora tomorrow at 2pm"
        )
        let thread = ExchangeThread(
            id: threadID,
            createdAt: Date(),
            updatedAt: Date(),
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(privacy: .balanced),
            state: .drafting,
            metadata: metadata
        )

        let resolution = ExchangeThreadSearchQueryDisplay.displaySearchQuery(for: thread, turns: [])
        XCTAssertEqual(resolution?.source, "originalRequesterText")
        XCTAssertTrue(resolution?.text.localizedCaseInsensitiveContains("roofer") == true)
    }
}
