import Foundation

public struct DirectReplyVoiceAnchor: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}

/// Extracts short local-user style anchors from recent transcript (style only, not facts).
public enum DirectReplyVoiceAnchorExtractor {
    public static let maxAnchors = 3
    public static let maxAnchorCharacters = 80
    public static let excludedRecentMessageCount = 2

    public static func extract(
        from recentMessages: [ExchangeModels.DirectReplyTranscriptMessage]
    ) -> [DirectReplyVoiceAnchor] {
        let excludedTailCount = min(excludedRecentMessageCount, recentMessages.count)
        let eligibleMessages = Array(recentMessages.dropLast(excludedTailCount))

        var anchors: [DirectReplyVoiceAnchor] = []

        for message in eligibleMessages.reversed() where message.role == .localUser {
            let trimmed = message.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.count <= maxAnchorCharacters else { continue }
            guard isPreferredGenericAnchor(trimmed) else { continue }
            guard !shouldDropAsUnsafe(trimmed) else { continue }

            let anchor = DirectReplyVoiceAnchor(text: trimmed)
            if anchors.contains(where: { $0.text == anchor.text }) { continue }
            anchors.append(anchor)
            if anchors.count >= maxAnchors { break }
        }

        return anchors
    }

    static func isPreferredGenericAnchor(_ text: String) -> Bool {
        let normalized = normalize(text)
        let preferred = [
            "sounds good",
            "no worries",
            "that works for me",
            "yeah, that works",
            "sure, that sounds good",
            "sounds good to me",
            "sure",
            "ok",
            "okay",
        ]
        return preferred.contains { normalized == $0 }
    }

    static func shouldDropAsUnsafe(_ text: String) -> Bool {
        let normalized = normalize(text)

        let dropNeedles = [
            "hey", "long time", "been a minute", "thinking about", "mentioned earlier",
            "i'll", "i will", "i can", "i need", "i have", "i've", "i was", "i'm",
            "send", "deck", "tonight", "$", "address", "street", "avenue",
            "tomorrow", "saturday", "sunday", "monday", "tuesday", "wednesday",
            "thursday", "friday", "january", "february", "march", "april", "may",
            "june", "july", "august", "september", "october", "november", "december",
            "morning", "afternoon", "evening", "cafe", "coffee", "pizza", "tacos",
        ]
        if dropNeedles.contains(where: { normalized.contains($0) }) {
            return true
        }

        if normalized.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)?\b"#, options: .regularExpression) != nil {
            return true
        }

        if containsSchedulingTimeSignal(normalized) {
            return true
        }

        return false
    }

    static func containsSchedulingTimeSignal(_ normalized: String) -> Bool {
        let schedulingWords = ["at", "by", "around", "works", "meet", "see you", "cafe"]
        let hasScheduling = schedulingWords.contains { normalized.contains($0) }
        guard hasScheduling else { return false }

        let words = normalized.split(separator: " ").map(String.init)
        for word in words {
            if word == "7" || word == "3" || word == "8" || word == "9" {
                return true
            }
            if word.contains(":") {
                return true
            }
        }
        return false
    }

    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }
}
