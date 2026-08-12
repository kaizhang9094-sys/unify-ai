import Foundation

public enum DirectChatReplySuggestionPolicy {
    public static func fallbackDirectReplySuggestion(
        displayName: String?,
        latestInboundMessage: String?,
        relationshipType: ExchangeModels.ContactRelationshipType,
        relationshipGoal: ExchangeModels.RelationshipGoal,
        selectionKey: String
    ) -> ExchangeModels.DirectReplySuggestionOutput {
        let reply = fallbackReplyText(
            latestInboundMessage: latestInboundMessage,
            relationshipType: relationshipType,
            selectionKey: selectionKey
        )
        return ExchangeModels.DirectReplySuggestionOutput(
            reply: reply,
            reason: "Fallback suggestion used.",
            safety: "manual_only",
            requiresApproval: true
        )
    }

    /// Deterministic short fallback when model output is unusable.
    public static func fallbackReplyText(
        latestInboundMessage: String?,
        relationshipType: ExchangeModels.ContactRelationshipType,
        selectionKey: String
    ) -> String {
        let inbound = normalizedInbound(latestInboundMessage)

        if matchesRunningLateInbound(inbound) {
            return selectVariant(
                from: [
                    "No worries, still good.",
                    "Still good — no rush.",
                    "Yep, all good on my end."
                ],
                selectionKey: selectionKey + "|running_late"
            )
        }

        if matchesDeckSendInbound(inbound) {
            return selectVariant(
                from: [
                    "Not yet — I'm working on it and will send it over when it's ready.",
                    "Still putting it together — I'll send it your way soon.",
                    "Not quite ready yet, but I'll share it shortly."
                ],
                selectionKey: selectionKey + "|deck"
            )
        }

        if relationshipType == .friend {
            return selectVariant(
                from: [
                    "Sounds good — let me know what works.",
                    "Works for me — what time were you thinking?",
                    "I'm in — ping me the details."
                ],
                selectionKey: selectionKey + "|friend"
            )
        }

        return selectVariant(
            from: [
                "Thanks — I'll check and get back to you.",
                "Got it — I'll follow up shortly.",
                "Understood — I'll take a look and reply soon."
            ],
            selectionKey: selectionKey + "|default"
        )
    }

    public static func selectVariant(from variants: [String], selectionKey: String) -> String {
        guard !variants.isEmpty else { return "" }
        guard variants.count > 1 else { return variants[0] }
        let index = abs(stableSelectionHash(selectionKey)) % variants.count
        return variants[index]
    }

    static func stableSelectionHash(_ key: String) -> Int {
        var hash = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return hash
    }

    private static func normalizedInbound(_ message: String?) -> String {
        message?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func matchesRunningLateInbound(_ inbound: String) -> Bool {
        guard !inbound.isEmpty else { return false }
        if inbound.contains("running late") { return true }
        if inbound.contains("still good") { return true }
        if inbound.contains(" min late") { return true }
        if inbound.contains("be late") { return true }
        return false
    }

    private static func matchesDeckSendInbound(_ inbound: String) -> Bool {
        guard !inbound.isEmpty else { return false }
        let phrases = [
            "did you send",
            "get a chance to send",
            "send the deck",
            "sent the deck"
        ]
        return phrases.contains { inbound.contains($0) }
    }
}
