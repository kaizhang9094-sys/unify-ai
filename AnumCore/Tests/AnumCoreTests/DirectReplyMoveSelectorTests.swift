import XCTest
@testable import AnumCore

final class DirectReplyMoveSelectorTests: XCTestCase {
    func testCoffeeInvitationSelectsAcceptAndAskTime() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Want to grab coffee Saturday morning?",
            contactContext: friendContext()
        )
        let state = stateForInvitationCoffee()
        let move = DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: brief())
        XCTAssertEqual(move.kind, .acceptAndAskTime)
    }

    func testDeckStatusCheckSelectsAnswerStatusWithNextStep() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Did you get a chance to send the deck?",
            contactContext: colleagueContext()
        )
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: "Did you get a chance to send the deck?",
            recentMessages: [
                msg(.localUser, "I'll pull the deck together tonight."),
                msg(.remoteContact, "Did you get a chance to send the deck?"),
            ],
            contactBrief: brief()
        )
        let move = DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: brief())
        XCTAssertEqual(move.kind, .answerStatusWithNextStep)
    }

    func testRunningLateSelectsReassure() {
        let latest = "Running about 10 min late — still good?"
        let intent = DirectReplyIntentClassifier.classify(latestIncoming: latest, contactContext: friendContext())
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: [msg(.remoteContact, latest)],
            contactBrief: brief()
        )
        let move = DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: brief())
        XCTAssertEqual(move.kind, .reassure)
    }

    func testTacosChoiceSelectsChoosePreference() {
        let latest = "Should we do tacos or pizza?"
        let intent = DirectReplyIntentClassifier.classify(latestIncoming: latest, contactContext: friendContext())
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: [msg(.remoteContact, latest)],
            contactBrief: brief()
        )
        let move = DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: brief())
        XCTAssertEqual(move.kind, .choosePreference)
    }

    func testGreetingSelectsAcknowledgeAndContinue() {
        let latest = "Hey! Long time."
        let intent = DirectReplyIntentClassifier.classify(latestIncoming: latest, contactContext: friendContext())
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: [msg(.remoteContact, latest)],
            contactBrief: brief()
        )
        let move = DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: brief())
        XCTAssertEqual(move.kind, .acknowledgeAndContinue)
    }

    func testAcceptAndAskTimeIncludesProposedWindowConstraint() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Want to grab coffee Saturday morning?",
            contactContext: friendContext()
        )
        let move = DirectReplyMoveSelector.select(
            intent: intent,
            state: stateForInvitationCoffee(),
            contactBrief: brief()
        )
        XCTAssertEqual(move.kind, .acceptAndAskTime)
        XCTAssertTrue(move.constraints.contains(where: { $0.contains("do not ask whether that same proposed") }))
    }

    func testAnswerStatusIncludesNoCompletionClaimWithoutConfirmation() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Did you send the deck?",
            contactContext: colleagueContext()
        )
        let state = DirectReplyConversationState(
            phase: .stalling,
            established: ["Local user previously mentioned working on or sending the item."],
            openItems: ["Whether the item has been completed or sent."],
            doNotCopy: [],
            completionConfirmed: false,
            replyMove: ""
        )
        let move = DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: brief())
        XCTAssertTrue(move.constraints.contains(where: { $0.contains("Do not claim completion") }))
    }

    func testReassureIncludesWrongSpeakerPrevention() {
        let latest = "Running about 10 min late — still good?"
        let intent = DirectReplyIntentClassifier.classify(latestIncoming: latest, contactContext: friendContext())
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: [msg(.remoteContact, latest)],
            contactBrief: brief()
        )
        let move = DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: brief())
        XCTAssertEqual(move.kind, .reassure)
        XCTAssertTrue(move.constraints.contains(where: { $0.contains("Do not say I'm running late") }))
    }

    func testChoosePreferenceIncludesDirectPick() {
        let latest = "Should we do tacos or pizza?"
        let intent = DirectReplyIntentClassifier.classify(latestIncoming: latest, contactContext: friendContext())
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: latest,
            recentMessages: [msg(.remoteContact, latest)],
            contactBrief: brief()
        )
        let move = DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: brief())
        XCTAssertEqual(move.kind, .choosePreference)
        XCTAssertTrue(move.constraints.contains(where: { $0.contains("Pick one option directly") }))
    }

    private func stateForInvitationCoffee() -> DirectReplyConversationState {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Want to grab coffee Saturday morning?",
            contactContext: friendContext()
        )
        return DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: "Want to grab coffee Saturday morning?",
            recentMessages: [
                msg(.remoteContact, "Hey! Long time."),
                msg(.remoteContact, "Want to grab coffee Saturday morning?"),
            ],
            contactBrief: brief()
        )
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

    private func brief() -> DirectReplyContactBrief {
        DirectReplyContactBrief(
            relationship: "friend",
            goal: "maintain friendship",
            tone: "warm, natural, casual",
            stakes: .low,
            styleConstraints: [],
            boundaries: [],
            avoid: []
        )
    }

    private func msg(
        _ role: ExchangeModels.DirectReplyTranscriptRole,
        _ text: String
    ) -> ExchangeModels.DirectReplyTranscriptMessage {
        ExchangeModels.DirectReplyTranscriptMessage(role: role, text: text)
    }
}
