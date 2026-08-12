import XCTest
@testable import AnumCore

final class DirectChatReplySuggestionPromptBuilderTests: XCTestCase {
    func testDedupedRecentMessagesRemovesLatestInbound() {
        let recent = [
            msg(.remoteContact, "Hello"),
            msg(.localUser, "Hi"),
            msg(.remoteContact, "Want coffee Saturday?")
        ]
        let (deduped, removed) = DirectChatReplySuggestionPromptBuilder.dedupedRecentMessages(
            recentMessages: recent,
            latestIncomingMessage: "Want coffee Saturday?"
        )
        XCTAssertTrue(removed)
        XCTAssertEqual(deduped.count, 2)
        XCTAssertFalse(deduped.contains(where: { $0.text == "Want coffee Saturday?" }))
    }

    func testBuildContactContextPayloadOmitsEmptyOptionalFields() {
        let context = ExchangeModels.ContactContext(
            remoteNodeID: "node-a",
            relationshipType: .friend,
            relationshipGoal: .maintainFriendship,
            goalNotes: "",
            notes: "",
            toneOverride: nil
        )
        let payload = DirectChatReplySuggestionPromptBuilder.buildContactContextPayload(context)
        XCTAssertEqual(payload["relationshipType"] as? String, ExchangeModels.ContactRelationshipType.friend.rawValue)
        XCTAssertNil(payload["goalNotes"])
        XCTAssertNil(payload["toneOverride"])
        XCTAssertNil(payload["customRelationshipLabel"])
    }

    func testBuildPromptUsesSelectedMoveAndVoiceAnchors() {
        let context = ExchangeModels.ContactContext(
            remoteNodeID: "node-a",
            relationshipType: .colleague,
            relationshipGoal: .warmProfessionalContact,
            notes: "Met at conference",
            toneOverride: "Professional and concise"
        )
        let input = ExchangeModels.DirectReplySuggestionInput(
            remoteNodeID: "node-a",
            contactDisplayName: "Jordan",
            latestIncomingMessage: "Did you get a chance to send the deck?",
            recentTranscript: [
                msg(.localUser, "Sounds good to me."),
                msg(.localUser, "I'll pull the deck together tonight."),
                msg(.remoteContact, "Did you get a chance to send the deck?"),
            ],
            contactContext: context,
            relationshipType: .colleague,
            relationshipGoal: .warmProfessionalContact,
            relationshipNotes: "Met at conference",
            toneOverride: "Professional and concise",
            contactPublicProfileSummary: "Product designer, SaaS focus",
            safetyRules: []
        )

        let prompt = DirectChatReplySuggestionPromptBuilder.buildPromptForTesting(
            input: input,
            latestInboundMessage: input.latestIncomingMessage,
            userInstruction: nil
        )

        XCTAssertTrue(prompt.contains("selectedMove"))
        XCTAssertTrue(prompt.contains("\"reason\""))
        XCTAssertTrue(prompt.contains("voiceAnchors"))
        XCTAssertTrue(prompt.contains("inboundIntent"))
        XCTAssertTrue(prompt.contains("conversationState"))
        XCTAssertTrue(prompt.contains("contactBrief"))
        XCTAssertTrue(prompt.contains("privateContext"))
        XCTAssertTrue(prompt.contains("profileSummary"))
        XCTAssertTrue(prompt.contains("The strategy layer already selected the move"))
        XCTAssertTrue(prompt.contains("Do not choose a different move"))
        XCTAssertFalse(prompt.contains("\"contactContext\""))
        XCTAssertFalse(prompt.contains("rawBackgroundMessages"))
        XCTAssertFalse(prompt.contains("localSentVoiceExamples"))
        XCTAssertFalse(prompt.contains("latestIncomingMessage"))
        XCTAssertFalse(prompt.contains("requestedMove"))
        XCTAssertFalse(prompt.contains("replyMove"))
        XCTAssertFalse(prompt.contains("## BASE"))
        XCTAssertFalse(prompt.contains("providerInquiryCompare"))
        XCTAssertFalse(prompt.contains("USER_SECRETARY_CONSTITUTION"))
        XCTAssertFalse(prompt.contains("You are the local Exchange intelligence worker"))
    }

    private func msg(
        _ role: ExchangeModels.DirectReplyTranscriptRole,
        _ text: String
    ) -> ExchangeModels.DirectReplyTranscriptMessage {
        ExchangeModels.DirectReplyTranscriptMessage(role: role, text: text)
    }
}
