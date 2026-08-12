import XCTest
@testable import AnumCore

final class DirectChatReplySuggestionQualityTests: XCTestCase {
    private func message(
        role: ExchangeModels.DirectReplyTranscriptRole,
        text: String
    ) -> ExchangeModels.DirectReplyTranscriptMessage {
        ExchangeModels.DirectReplyTranscriptMessage(role: role, text: text, timestamp: nil)
    }

    func testExactDuplicateInboundDetected() {
        let issues = DirectChatReplySuggestionQuality.evaluate(
            reply: "Want coffee Saturday?",
            latestInbound: "Want coffee Saturday?",
            recentMessages: [],
            previousSuggestions: []
        )
        XCTAssertTrue(issues.contains(.exactDuplicate))
    }

    func testHighInboundOverlapParaphraseDetected() {
        let issues = DirectChatReplySuggestionQuality.evaluate(
            reply: "Yeah I want coffee Saturday morning too",
            latestInbound: "Want to grab coffee Saturday morning?",
            recentMessages: [],
            previousSuggestions: []
        )
        XCTAssertTrue(issues.contains(.highInboundOverlap))
    }

    func testShortReplySkipsOverlapChecks() {
        let issues = DirectChatReplySuggestionQuality.evaluate(
            reply: "OK",
            latestInbound: "Want to grab coffee Saturday morning?",
            recentMessages: [],
            previousSuggestions: ["Sounds good — let me know what works."]
        )
        XCTAssertFalse(issues.contains(.highInboundOverlap))
        XCTAssertFalse(issues.contains(.highPriorSuggestionOverlap))
    }

    func testRepeatedOpeningAgainstPriorSuggestion() {
        let issues = DirectChatReplySuggestionQuality.evaluate(
            reply: "Sounds good — I'll be there at 8",
            latestInbound: "See you tomorrow?",
            recentMessages: [],
            previousSuggestions: ["Sounds good — let me know what works."]
        )
        XCTAssertTrue(
            issues.contains(.repeatedOpening) || issues.contains(.highPriorSuggestionOverlap)
        )
    }

    func testAnsweredOlderMessageGreetingRepeatDetected() {
        let recent = [
            message(role: .remoteContact, text: "Hey! Long time."),
            message(role: .remoteContact, text: "Want to grab coffee Saturday morning?"),
        ]
        let issues = DirectChatReplySuggestionQuality.evaluate(
            reply: "Hey! Long time. How's your day going?",
            latestInbound: "Want to grab coffee Saturday morning?",
            recentMessages: recent,
            previousSuggestions: []
        )
        XCTAssertTrue(issues.contains(.answeredOlderMessage))
    }

    func testOldLocalContentCopyDetected() {
        let recent = [
            message(role: .localUser, text: "I'll pull the deck together tonight."),
            message(role: .remoteContact, text: "Did you get a chance to send the deck?"),
        ]
        let issues = DirectChatReplySuggestionQuality.evaluate(
            reply: "Got it. I'll pull the deck together tonight.",
            latestInbound: "Did you get a chance to send the deck?",
            recentMessages: recent,
            previousSuggestions: []
        )
        XCTAssertTrue(issues.contains(.oldLocalContentCopy))
    }

    func testValidRepliesAreNotFlaggedForOlderOrLocalCopy() {
        let recent = [
            message(role: .remoteContact, text: "Hey! Long time."),
            message(role: .remoteContact, text: "Want to grab coffee Saturday morning?"),
            message(role: .localUser, text: "I'll pull the deck together tonight."),
            message(role: .remoteContact, text: "Did you get a chance to send the deck?"),
        ]

        let validReplies = [
            "Saturday morning works — what time?",
            "Not yet — I'll send it over shortly.",
            "No worries, still good.",
            "Sounds like tacos. I'm in.",
            "Sounds good",
            "Sure, Saturday works",
            "No worries, see you soon.",
        ]

        for reply in validReplies {
            let issues = DirectChatReplySuggestionQuality.evaluate(
                reply: reply,
                latestInbound: "Did you get a chance to send the deck?",
                recentMessages: recent,
                previousSuggestions: []
            )
            XCTAssertFalse(
                issues.contains(.answeredOlderMessage),
                "unexpected answeredOlderMessage for: \(reply)"
            )
            XCTAssertFalse(
                issues.contains(.oldLocalContentCopy),
                "unexpected oldLocalContentCopy for: \(reply)"
            )
        }
    }

    func testAnsweredOlderMessageFindingIncludesRemoteRoleAndIndex() {
        let recent = [
            message(role: .remoteContact, text: "Hey! Long time."),
            message(role: .remoteContact, text: "Want to grab coffee Saturday morning?"),
        ]
        let findings = DirectChatReplySuggestionQuality.evaluateFindings(
            reply: "Hey! Long time. How's your day going?",
            latestInbound: "Want to grab coffee Saturday morning?",
            recentMessages: recent,
            previousSuggestions: []
        )
        let match = findings.first { $0.issue == .answeredOlderMessage }
        XCTAssertEqual(match?.matchedRole, .remoteContact)
        XCTAssertEqual(match?.matchedIndex, 0)
    }

    func testOldLocalContentCopyFindingIncludesLocalRoleAndIndex() {
        let recent = [
            message(role: .localUser, text: "I'll pull the deck together tonight."),
            message(role: .remoteContact, text: "Did you get a chance to send the deck?"),
        ]
        let findings = DirectChatReplySuggestionQuality.evaluateFindings(
            reply: "Got it. I'll pull the deck together tonight.",
            latestInbound: "Did you get a chance to send the deck?",
            recentMessages: recent,
            previousSuggestions: []
        )
        let match = findings.first { $0.issue == .oldLocalContentCopy }
        XCTAssertEqual(match?.matchedRole, .localUser)
        XCTAssertEqual(match?.matchedIndex, 0)
    }

    func testWrongSpeakerPerspectiveWhenLocalClaimsRunningLate() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Running about 10 min late — still good?",
            contactContext: nil
        )
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: "Running about 10 min late — still good?",
            recentMessages: [
                message(role: .remoteContact, text: "Running about 10 min late — still good?")
            ]
        )
        let strategy = DirectReplyQualityContext(
            latestIntent: intent,
            selectedMove: DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: nil),
            conversationState: state
        )
        let issues = DirectChatReplySuggestionQuality.evaluate(
            reply: "Hey, I'm running a bit late. Still good?",
            latestInbound: "Running about 10 min late — still good?",
            recentMessages: [],
            strategyContext: strategy
        )
        XCTAssertTrue(issues.contains(.wrongSpeakerPerspective))
    }

    func testReassureReplyAcceptedWhenLocalDoesNotClaimDelay() {
        let intent = DirectReplyIntentClassifier.classify(
            latestIncoming: "Running about 10 min late — still good?",
            contactContext: nil
        )
        let state = DirectReplyConversationStateBuilder.build(
            latestIntent: intent,
            latestIncoming: "Running about 10 min late — still good?",
            recentMessages: [
                message(role: .remoteContact, text: "Running about 10 min late — still good?")
            ]
        )
        let strategy = DirectReplyQualityContext(
            latestIntent: intent,
            selectedMove: DirectReplyMoveSelector.select(intent: intent, state: state, contactBrief: nil),
            conversationState: state
        )
        let issues = DirectChatReplySuggestionQuality.evaluate(
            reply: "No worries, still good.",
            latestInbound: "Running about 10 min late — still good?",
            recentMessages: [],
            strategyContext: strategy
        )
        XCTAssertFalse(issues.contains(.wrongSpeakerPerspective))
    }
}
