import Foundation

public struct DirectReplyConversationState: Codable, Sendable, Equatable {
    public enum Phase: String, Codable, Sendable, Hashable {
        case opening
        case building
        case advancing
        case stalling
        case atRisk
        case closing
    }

    public var phase: Phase
    public var established: [String]
    public var openItems: [String]
    public var doNotCopy: [String]
    public var completionConfirmed: Bool
    /// Internal selector hint; not sent to the narrow generator prompt.
    public var replyMove: String

    public init(
        phase: Phase,
        established: [String],
        openItems: [String],
        doNotCopy: [String],
        completionConfirmed: Bool = false,
        replyMove: String
    ) {
        self.phase = phase
        self.established = established
        self.openItems = openItems
        self.doNotCopy = doNotCopy
        self.completionConfirmed = completionConfirmed
        self.replyMove = replyMove
    }
}

public enum DirectReplyConversationStateBuilder {
    public static func build(
        latestIntent: DirectReplyLatestIntent,
        latestIncoming: String,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        contactBrief: DirectReplyContactBrief? = nil
    ) -> DirectReplyConversationState {
        var established: [String] = []
        var openItems: [String] = []
        var replyMove = latestIntent.requestedMove
        var completionConfirmed = false

        switch latestIntent.kind {
        case .statusCheck:
            if localMentionedWorkOrSend(recentMessages) {
                established.append("Local user previously mentioned working on or sending the item.")
            }
            if localConfirmedCompletion(recentMessages) {
                established.append("Local user indicated the item was completed or sent.")
                completionConfirmed = true
            }
            openItems.append("Whether the item has been completed or sent.")
            replyMove = "Answer current status; do not repeat the previous promise."

        case .invitation:
            openItems.append("Whether to accept and what time or details are needed.")
            replyMove = "Accept, decline, or ask for the missing detail."
            if let olderRemoteGreeting = olderRemoteGreetingLine(recentMessages, latestIncoming: latestIncoming) {
                established.append("Earlier remote message: \(olderRemoteGreeting)")
                openItems.append("Respond to the invitation, not the older greeting.")
            }

        case .delayConfirmation, .schedulingConfirmation:
            openItems.append("Whether the delay or timing change is okay.")
            replyMove = "Confirm whether the delay is okay; do not mirror the delay wording."

        case .choiceQuestion:
            openItems.append("Which option the local user prefers.")
            replyMove = "Pick one option or state preference."

        case .request:
            openItems.append("Whether the local user can fulfill the request.")
            replyMove = "Confirm, decline, or ask one clarifying question."

        case .acknowledgement:
            replyMove = "Respond briefly and naturally."

        case .closing:
            replyMove = "Close warmly without opening a new topic."

        case .greeting:
            openItems.append("A friendly next step for the conversation.")
            replyMove = "Greet back briefly; do not reopen older topics."

        case .unknown:
            break
        }

        established = Array(established.prefix(3))
        openItems = Array(openItems.prefix(3))

        let doNotCopy = [
            "Do not answer older messages.",
            "Do not restate latestIncomingMessage.",
            "Do not reuse previous local messages as the reply.",
        ]

        let phase = detectPhase(
            latestIntent: latestIntent,
            latestIncoming: latestIncoming,
            recentMessages: recentMessages,
            contactBrief: contactBrief
        )

        return DirectReplyConversationState(
            phase: phase,
            established: established,
            openItems: openItems,
            doNotCopy: doNotCopy,
            completionConfirmed: completionConfirmed,
            replyMove: replyMove
        )
    }

    static func detectPhase(
        latestIntent: DirectReplyLatestIntent,
        latestIncoming: String,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        contactBrief: DirectReplyContactBrief?
    ) -> DirectReplyConversationState.Phase {
        if hasExplicitAtRiskSignals(latestIncoming: latestIncoming, recentMessages: recentMessages) {
            return .atRisk
        }

        switch latestIntent.kind {
        case .closing:
            return .closing
        case .greeting:
            return recentMessages.count <= 2 ? .opening : .building
        case .statusCheck:
            return .stalling
        case .invitation:
            if isCloseRelationship(contactBrief) {
                return .advancing
            }
            return .building
        case .choiceQuestion, .delayConfirmation, .schedulingConfirmation:
            return .advancing
        case .acknowledgement, .request:
            return .building
        case .unknown:
            return .building
        }
    }

    static func hasExplicitAtRiskSignals(
        latestIncoming: String,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage]
    ) -> Bool {
        let texts = [latestIncoming] + recentMessages.map(\.text)
        let needles = [
            "we need to talk", "not sure", "can't do this", "cannot do this",
            "sorry i've been", "sorry i have been", "been distant", "avoiding",
            "don't want to", "do not want to", "not interested", "leave me alone",
            "boundary", "conflict", "upset with you", "angry with you",
        ]
        return texts.contains { text in
            let normalized = normalize(text)
            return needles.contains { normalized.contains($0) }
        }
    }

    static func isCloseRelationship(_ contactBrief: DirectReplyContactBrief?) -> Bool {
        guard let contactBrief else { return false }
        let relationship = contactBrief.relationship.lowercased()
        let goal = contactBrief.goal.lowercased()
        if relationship == "friend" || relationship == "family" {
            return true
        }
        return goal.contains("friendship") || goal.contains("personal")
    }

    static func localConfirmedCompletion(
        _ recentMessages: [ExchangeModels.DirectReplyTranscriptMessage]
    ) -> Bool {
        let needles = [
            "already sent", "i sent it", "sent it over", "sent the deck",
            "it's ready", "it is ready", "all set", "done with the deck",
        ]
        return recentMessages.contains { message in
            guard message.role == .localUser else { return false }
            let normalized = normalize(message.text)
            return needles.contains { normalized.contains($0) }
        }
    }

    static func localMentionedWorkOrSend(
        _ recentMessages: [ExchangeModels.DirectReplyTranscriptMessage]
    ) -> Bool {
        let needles = [
            "pull the deck", "send the deck", "send it", "send over", "working on",
            "finish", "tonight", "will send", "i'll send", "get it to you",
        ]
        return recentMessages.contains { message in
            guard message.role == .localUser else { return false }
            let normalized = normalize(message.text)
            return needles.contains { normalized.contains($0) }
        }
    }

    static func olderRemoteGreetingLine(
        _ recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        latestIncoming: String
    ) -> String? {
        let normalizedLatest = normalize(latestIncoming)
        for message in recentMessages where message.role == .remoteContact {
            let normalized = normalize(message.text)
            guard !normalized.isEmpty, normalized != normalizedLatest else { continue }
            if isGreetingLike(normalized) {
                return clipped(message.text, maxChars: 80)
            }
        }
        return nil
    }

    static func isGreetingLike(_ normalized: String) -> Bool {
        let needles = ["hey", "hi", "hello", "long time", "how are you", "how's it going"]
        return needles.contains { normalized.contains($0) }
    }

    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func clipped(_ text: String, maxChars: Int) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        return String(trimmed.prefix(maxChars)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
