import Foundation

/// Per-suggestion structured strategy inputs derived from transcript and contact context.
public struct DirectReplyPromptContext: Sendable, Equatable {
    public var latestIntent: DirectReplyLatestIntent
    public var conversationState: DirectReplyConversationState
    public var contactBrief: DirectReplyContactBrief?
    public var selectedMove: DirectReplySelectedMove
    public var voiceAnchors: [DirectReplyVoiceAnchor]

    public init(
        latestIntent: DirectReplyLatestIntent,
        conversationState: DirectReplyConversationState,
        contactBrief: DirectReplyContactBrief?,
        selectedMove: DirectReplySelectedMove,
        voiceAnchors: [DirectReplyVoiceAnchor]
    ) {
        self.latestIntent = latestIntent
        self.conversationState = conversationState
        self.contactBrief = contactBrief
        self.selectedMove = selectedMove
        self.voiceAnchors = voiceAnchors
    }

    public static func make(
        latestIncoming: String?,
        contactContext: ExchangeModels.ContactContext?,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage]
    ) -> DirectReplyPromptContext {
        let latestText = latestIncoming?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        let latestIntent = DirectReplyIntentClassifier.classify(
            latestIncoming: latestText.isEmpty ? nil : latestText,
            contactContext: contactContext
        )

        let contactBrief = DirectReplyContactBriefCompiler.compile(contactContext: contactContext)

        let conversationState = DirectReplyConversationStateBuilder.build(
            latestIntent: latestIntent,
            latestIncoming: latestText,
            recentMessages: recentMessages,
            contactBrief: contactBrief
        )

        let selectedMove = DirectReplyMoveSelector.select(
            intent: latestIntent,
            state: conversationState,
            contactBrief: contactBrief
        )

        let voiceAnchors = DirectReplyVoiceAnchorExtractor.extract(from: recentMessages)

        return DirectReplyPromptContext(
            latestIntent: latestIntent,
            conversationState: conversationState,
            contactBrief: contactBrief,
            selectedMove: selectedMove,
            voiceAnchors: voiceAnchors
        )
    }
}
