import XCTest
@testable import AnumCore

final class DirectReplyIntentClassifierTests: XCTestCase {
    func testInvitationCoffeeSaturday() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Want to grab coffee Saturday morning?",
            contactContext: friendContext()
        )
        XCTAssertEqual(intent.kind, .invitation)
    }

    func testStatusCheckDeck() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Did you get a chance to send the deck?",
            contactContext: colleagueContext()
        )
        XCTAssertEqual(intent.kind, .statusCheck)
        XCTAssertTrue(intent.requestedMove.contains("current status"))
    }

    func testDelayConfirmationRunningLate() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Running about 10 min late — still good?",
            contactContext: friendContext()
        )
        XCTAssertTrue(
            intent.kind == .delayConfirmation || intent.kind == .schedulingConfirmation
        )
    }

    func testChoiceQuestionTacosOrPizza() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Should we do tacos or pizza?",
            contactContext: friendContext()
        )
        XCTAssertEqual(intent.kind, .choiceQuestion)
    }

    private func friendContext() -> ExchangeModels.ContactContext {
        ExchangeModels.ContactContext(
            remoteNodeID: "node-a",
            relationshipType: .friend,
            relationshipGoal: .maintainFriendship
        )
    }

    private func colleagueContext() -> ExchangeModels.ContactContext {
        ExchangeModels.ContactContext(
            remoteNodeID: "node-b",
            relationshipType: .colleague,
            relationshipGoal: .warmProfessionalContact
        )
    }
}
