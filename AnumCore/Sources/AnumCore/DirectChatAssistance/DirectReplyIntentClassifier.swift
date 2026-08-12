import Foundation

public struct DirectReplyLatestIntent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case invitation
        case statusCheck
        case delayConfirmation
        case schedulingConfirmation
        case choiceQuestion
        case request
        case acknowledgement
        case greeting
        case closing
        case unknown
    }

    public var kind: Kind
    public var summary: String
    public var requestedMove: String
    public var register: String
    public var entities: [String]

    public init(
        kind: Kind,
        summary: String,
        requestedMove: String,
        register: String,
        entities: [String] = []
    ) {
        self.kind = kind
        self.summary = summary
        self.requestedMove = requestedMove
        self.register = register
        self.entities = entities
    }
}

/// Deterministic latest-inbound intent for direct-chat reply suggestions (no LLM).
public enum DirectReplyIntentClassifier {
    public static func classify(
        latestIncoming: String?,
        contactContext: ExchangeModels.ContactContext?
    ) -> DirectReplyLatestIntent {
        let trimmed = latestIncoming?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return unknownIntent(summary: "No incoming message.", normalized: "")
        }

        let normalized = normalize(trimmed)

        if matchesStatusCheck(normalized) {
            return makeIntent(
                kind: .statusCheck,
                summary: clippedSummary(trimmed, maxChars: 120),
                requestedMove: "Answer current status. Do not repeat an earlier promise.",
                register: registerFor(normalized, contactContext: contactContext),
                normalized: normalized
            )
        }

        if matchesDelayConfirmation(normalized) {
            let kind: DirectReplyLatestIntent.Kind =
                containsSchedulingSignal(normalized) ? .schedulingConfirmation : .delayConfirmation
            return makeIntent(
                kind: kind,
                summary: clippedSummary(trimmed, maxChars: 120),
                requestedMove: "Reassure, object, or confirm the plan. Do not restate the delay.",
                register: registerFor(normalized, contactContext: contactContext),
                normalized: normalized
            )
        }

        if matchesChoiceQuestion(trimmed, normalized: normalized) {
            return makeIntent(
                kind: .choiceQuestion,
                summary: clippedSummary(trimmed, maxChars: 120),
                requestedMove: "Choose one option or state a preference.",
                register: registerFor(normalized, contactContext: contactContext),
                normalized: normalized
            )
        }

        if matchesInvitation(normalized) {
            return makeIntent(
                kind: .invitation,
                summary: clippedSummary(trimmed, maxChars: 120),
                requestedMove: "Accept, decline, or ask for details such as time.",
                register: registerFor(normalized, contactContext: contactContext),
                normalized: normalized
            )
        }

        if matchesRequest(normalized) {
            return makeIntent(
                kind: .request,
                summary: clippedSummary(trimmed, maxChars: 120),
                requestedMove: "Confirm, decline, or ask a clarifying question.",
                register: registerFor(normalized, contactContext: contactContext),
                normalized: normalized
            )
        }

        if matchesClosing(normalized) {
            return makeIntent(
                kind: .closing,
                summary: clippedSummary(trimmed, maxChars: 120),
                requestedMove: "Close warmly without opening a new topic.",
                register: registerFor(normalized, contactContext: contactContext),
                normalized: normalized
            )
        }

        if matchesAcknowledgement(normalized) {
            return makeIntent(
                kind: .acknowledgement,
                summary: clippedSummary(trimmed, maxChars: 120),
                requestedMove: "Respond briefly and naturally.",
                register: registerFor(normalized, contactContext: contactContext),
                normalized: normalized
            )
        }

        if matchesGreetingOnly(normalized) {
            return makeIntent(
                kind: .greeting,
                summary: clippedSummary(trimmed, maxChars: 120),
                requestedMove: "Greet back briefly and invite the next topic.",
                register: registerFor(normalized, contactContext: contactContext),
                normalized: normalized
            )
        }

        return unknownIntent(summary: clippedSummary(trimmed, maxChars: 120), normalized: normalized)
    }

    // MARK: - Rules

    static func matchesStatusCheck(_ normalized: String) -> Bool {
        let needles = [
            "did you get a chance",
            "have you sent",
            "did you send",
            "any update",
            "where are we on",
            "status on",
            "get a chance to send",
            "chance to send",
        ]
        return needles.contains { normalized.contains($0) }
    }

    static func matchesDelayConfirmation(_ normalized: String) -> Bool {
        let needles = [
            "running late",
            "running about",
            "still good",
            "still on",
            "be there soon",
            "on my way",
        ]
        if needles.contains(where: { normalized.contains($0) }) {
            return true
        }
        if normalized.contains("late"), normalized.contains("?") {
            return true
        }
        return false
    }

    static func containsSchedulingSignal(_ normalized: String) -> Bool {
        let needles = [
            "saturday", "sunday", "monday", "tuesday", "wednesday", "thursday", "friday",
            "morning", "afternoon", "evening", "tonight", "tomorrow", "meet", "coffee", "lunch",
        ]
        return needles.contains { normalized.contains($0) }
    }

    static func matchesChoiceQuestion(_ raw: String, normalized: String) -> Bool {
        guard raw.contains("?") else { return false }
        guard normalized.contains(" or ") else { return false }
        let choiceSignals = ["tacos", "pizza", "this or that", "either", "which"]
        return choiceSignals.contains { normalized.contains($0) } || normalized.contains(" or ")
    }

    static func matchesInvitation(_ normalized: String) -> Bool {
        let needles = [
            "want to grab",
            "grab coffee",
            "grab lunch",
            "get coffee",
            "get lunch",
            "want to meet",
            "meet up",
            "hang out",
            "free for",
            "available for",
        ]
        if needles.contains(where: { normalized.contains($0) }) {
            return true
        }
        if normalized.contains("coffee") || normalized.contains("lunch") || normalized.contains("dinner") {
            return normalized.contains("?") || normalized.contains("want") || normalized.contains("grab")
        }
        if containsWeekdayOrTimeSignal(normalized) {
            return normalized.contains("?") || normalized.contains("want") || normalized.contains("meet")
        }
        return false
    }

    static func matchesRequest(_ normalized: String) -> Bool {
        let prefixes = ["can you ", "could you ", "would you ", "please send", "please share", "send me"]
        return prefixes.contains { normalized.hasPrefix($0) || normalized.contains(" \($0)") }
    }

    static func makeIntent(
        kind: DirectReplyLatestIntent.Kind,
        summary: String,
        requestedMove: String,
        register: String,
        normalized: String
    ) -> DirectReplyLatestIntent {
        DirectReplyLatestIntent(
            kind: kind,
            summary: summary,
            requestedMove: requestedMove,
            register: register,
            entities: extractEntities(from: normalized)
        )
    }

    static func extractEntities(from normalized: String) -> [String] {
        let candidates = [
            "coffee", "lunch", "dinner", "deck", "tacos", "pizza", "saturday", "sunday",
            "monday", "tuesday", "wednesday", "thursday", "friday", "morning", "afternoon",
            "evening", "tonight", "tomorrow", "cafe", "meeting", "shift",
        ]
        var entities: [String] = []
        for candidate in candidates where normalized.contains(candidate) {
            entities.append(candidate)
        }
        if normalized.contains(" or ") {
            let parts = normalized
                .components(separatedBy: " or ")
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for part in parts.prefix(2) {
                let words = part.split(separator: " ").suffix(2).joined(separator: " ")
                if !words.isEmpty {
                    entities.append(words)
                }
            }
        }
        return Array(Set(entities)).sorted().prefix(6).map { $0 }
    }

    static func matchesClosing(_ normalized: String) -> Bool {
        let needles = [
            "talk soon", "see you soon", "see you", "catch you later", "good night",
            "ttyl", "gtg", "gotta go", "got to go",
        ]
        let wordCount = normalized.split(separator: " ").count
        guard wordCount <= 10 else { return false }
        return needles.contains { normalized.contains($0) }
    }

    static func matchesAcknowledgement(_ normalized: String) -> Bool {
        let needles = ["thanks", "thank you", "thx", "appreciate it"]
        let wordCount = normalized.split(separator: " ").count
        guard wordCount <= 8 else { return false }
        return needles.contains { normalized.contains($0) }
    }

    static func matchesGreetingOnly(_ normalized: String) -> Bool {
        let greetingNeedles = [
            "hey", "hi", "hello", "good morning", "good afternoon", "good evening",
            "long time", "how are you", "how's it going", "what's up",
        ]
        guard greetingNeedles.contains(where: { normalized.contains($0) }) else { return false }
        let wordCount = normalized.split(separator: " ").count
        return wordCount <= 12
    }

    static func containsWeekdayOrTimeSignal(_ normalized: String) -> Bool {
        let needles = [
            "saturday", "sunday", "monday", "tuesday", "wednesday", "thursday", "friday",
            "morning", "afternoon", "evening", "tonight", "tomorrow", "am", "pm",
        ]
        return needles.contains { normalized.contains($0) }
    }

    static func registerFor(
        _ normalized: String,
        contactContext: ExchangeModels.ContactContext?
    ) -> String {
        if let relationship = contactContext?.relationshipType {
            switch relationship {
            case .friend, .family:
                return "casual"
            case .colleague, .professionalContact, .client, .lead:
                return "clear"
            case .supplier, .contractor, .investor, .broker, .custom:
                return "neutral"
            }
        }
        if normalized.contains("?") {
            return "direct"
        }
        return "neutral"
    }

    static func unknownIntent(summary: String, normalized: String = "") -> DirectReplyLatestIntent {
        DirectReplyLatestIntent(
            kind: .unknown,
            summary: summary,
            requestedMove: "Reply naturally to the latest message only.",
            register: "neutral",
            entities: extractEntities(from: normalized)
        )
    }

    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "’", with: "'")
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func clippedSummary(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        return String(trimmed.prefix(maxChars)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
