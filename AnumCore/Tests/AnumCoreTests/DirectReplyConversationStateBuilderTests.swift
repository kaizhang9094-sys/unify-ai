import XCTest
@testable import AnumCore

final class DirectReplyConversationStateBuilderTests: XCTestCase {
    func testCoffeeTranscriptSteersAwayFromOlderGreeting() {
        let latest = "Want to grab coffee Saturday morning?"
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: latest,
            contactContext: nil
        )
        let recent = [
            msg(.remoteContact, "Hey! Long time."),
            msg(.remoteContact, latest),
        ]
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: recent
        )

        XCTAssertEqual(intent.kind, .invitation)
        XCTAssertTrue(state.replyMove.contains("Accept") || state.replyMove.contains("detail"))
        XCTAssertTrue(
            state.openItems.contains(where: { $0.contains("accept") || $0.contains("time") })
        )
        XCTAssertTrue(state.doNotCopy.contains("Do not answer older messages."))
    }

    func testDeckTranscriptProducesStatusCheckState() {
        let latest = "Did you get a chance to send the deck?"
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: latest,
            contactContext: nil
        )
        let recent = [
            msg(.localUser, "I'll pull the deck together tonight."),
            msg(.remoteContact, latest),
        ]
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: recent
        )

        XCTAssertEqual(intent.kind, .statusCheck)
        XCTAssertTrue(
            state.established.contains(where: { $0.contains("working on") || $0.contains("sending") })
        )
        XCTAssertTrue(state.openItems.contains(where: { $0.contains("completed") || $0.contains("sent") }))
        XCTAssertTrue(state.replyMove.contains("current status"))
        XCTAssertFalse(state.completionConfirmed)
    }

    func testRunningLateProducesConfirmDelayState() {
        let latest = "Running about 10 min late — still good?"
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: latest,
            contactContext: nil
        )
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: [msg(.remoteContact, latest)]
        )

        XCTAssertTrue(state.replyMove.contains("delay"))
        XCTAssertTrue(state.doNotCopy.contains("Do not restate latestIncomingMessage."))
    }

    func testTacosChoiceState() {
        let latest = "Should we do tacos or pizza?"
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: latest,
            contactContext: nil
        )
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: [msg(.remoteContact, latest)]
        )

        XCTAssertEqual(intent.kind, .choiceQuestion)
        XCTAssertTrue(state.replyMove.contains("option") || state.replyMove.contains("preference"))
    }

    func testFriendInvitationWithOlderGreetingIsNotAtRisk() {
        let latest = "Want to grab coffee Saturday morning?"
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: latest,
            contactContext: ExchangeModels.ContactContext(
                remoteNodeID: "node-a",
                relationshipType: .friend,
                relationshipGoal: .maintainFriendship
            )
        )
        let brief = DirectReplyContactBriefCompiler.compile(
            contactContext: ExchangeModels.ContactContext(
                remoteNodeID: "node-a",
                relationshipType: .friend,
                relationshipGoal: .maintainFriendship
            )
        )
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: [
                msg(.remoteContact, "Hey! Long time."),
                msg(.remoteContact, latest),
            ],
            contactBrief: brief
        )
        XCTAssertNotEqual(state.phase, .atRisk)
        XCTAssertTrue(state.phase == .building || state.phase == .advancing)
    }

    func testExplicitBoundaryLanguageCanBeAtRisk() {
        let latest = "I'm not sure we can do this anymore."
        let intent = DirectReplyIntentClassifier.classify(latestIncoming: latest, contactContext: nil)
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: [msg(.remoteContact, latest)]
        )
        XCTAssertEqual(state.phase, .atRisk)
    }

    private func msg(
        _ role: ExchangeModels.DirectReplyTranscriptRole,
        _ text: String
    ) -> ExchangeModels.DirectReplyTranscriptMessage {
        ExchangeModels.DirectReplyTranscriptMessage(role: role, text: text)
    }
}
