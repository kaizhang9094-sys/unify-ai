import Foundation

/// Strategy context for direct-chat reply quality checks only.
public struct DirectReplyQualityContext: Sendable, Equatable {
    public var latestIntent: DirectReplyLatestIntent
    public var selectedMove: DirectReplySelectedMove
    public var conversationState: DirectReplyConversationState

    public init(
        latestIntent: DirectReplyLatestIntent,
        selectedMove: DirectReplySelectedMove,
        conversationState: DirectReplyConversationState
    ) {
        self.latestIntent = latestIntent
        self.selectedMove = selectedMove
        self.conversationState = conversationState
    }
}
