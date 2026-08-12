import Foundation

/// Wire types for direct chat reply suggestion use ``ExchangeModels``:
/// ``ExchangeModels/DirectReplySuggestionInput``, ``ExchangeModels/DirectReplyTranscriptMessage``,
/// ``ExchangeModels/DirectReplySuggestionOutput``.
public enum DirectChatReplySuggestionModels {
    /// JSON decode shape for model output. Only `reply` is read; extra keys (legacy reason/safety) are ignored.
    struct Payload: Codable, Sendable {
        var reply: String
    }
}
