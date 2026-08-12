import Foundation

public enum DirectChatReplySuggestionPromptBuilder {
    private static let replyVoiceGuide =
        "Natural DM voice: match contactBrief tone and voiceAnchors rhythm only."

    private static let profileSummaryMaxChars = 200
    private static let commercialSummaryMaxChars = 120

    public nonisolated static func buildPrompt(
        input: ExchangeModels.DirectReplySuggestionInput,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        latestIncomingMessage: String?,
        userInstruction: String?,
        promptContext: DirectReplyPromptContext
    ) -> String {
        _ = recentMessages
        _ = latestIncomingMessage

        var payload: [String: Any] = [
            "localUserDisplayName": input.localUserDisplayName ?? "Me",
            "contactDisplayName": input.contactDisplayName ?? "",
            "inboundIntent": inboundIntentPayload(promptContext.latestIntent),
            "conversationState": conversationStatePayload(promptContext.conversationState),
            "selectedMove": selectedMovePayload(promptContext.selectedMove),
            "voiceAnchors": promptContext.voiceAnchors.map(\.text),
            "replyVoice": replyVoiceGuide,
            "outputSchema": [
                "reply": "string",
            ],
        ]

        if let contactBrief = promptContext.contactBrief {
            payload["contactBrief"] = contactBriefPayload(contactBrief)
        }

        if let privateContext = buildPrivateContextPayload(input: input), !privateContext.isEmpty {
            payload["privateContext"] = privateContext
        }

        let trimmedInstruction = userInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedInstruction, !trimmedInstruction.isEmpty {
            payload["userInstruction"] = trimmedInstruction
        }

        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return instructionBlock + "\nINPUT:\n\(json)"
    }

    public nonisolated static func buildPromptForTesting(
        input: ExchangeModels.DirectReplySuggestionInput,
        latestInboundMessage: String?,
        userInstruction: String?
    ) -> String {
        let recent = Array(input.recentTranscript.suffix(4))
        let promptContext = DirectReplyPromptContext.make(
            latestIncoming: latestInboundMessage ?? input.latestIncomingMessage,
            contactContext: input.contactContext,
            recentMessages: recent
        )
        return buildPrompt(
            input: input,
            recentMessages: recent,
            latestIncomingMessage: latestInboundMessage ?? input.latestIncomingMessage,
            userInstruction: userInstruction,
            promptContext: promptContext
        )
    }

    // MARK: - Structured payloads

    static func inboundIntentPayload(_ intent: DirectReplyLatestIntent) -> [String: Any] {
        [
            "kind": intent.kind.rawValue,
            "summary": intent.summary,
            "entities": intent.entities,
            "register": intent.register,
        ]
    }

    static func conversationStatePayload(_ state: DirectReplyConversationState) -> [String: Any] {
        [
            "phase": state.phase.rawValue,
            "established": state.established,
            "openItems": state.openItems,
        ]
    }

    static func selectedMovePayload(_ move: DirectReplySelectedMove) -> [String: Any] {
        [
            "kind": move.kind.rawValue,
            "reason": move.reason,
            "constraints": move.constraints,
            "requiresCaution": move.requiresCaution,
        ]
    }

    static func contactBriefPayload(_ brief: DirectReplyContactBrief) -> [String: Any] {
        [
            "relationship": brief.relationship,
            "goal": brief.goal,
            "tone": brief.tone,
            "stakes": brief.stakes.rawValue,
            "styleConstraints": brief.styleConstraints,
            "boundaries": brief.boundaries,
            "avoid": brief.avoid,
            "alwaysDo": brief.alwaysDo,
            "neverDo": brief.neverDo,
            "sourceVersion": brief.sourceVersion,
        ]
    }

    /// Legacy helper retained for tests that assert empty-field omission behavior.
    static func buildContactContextPayload(_ context: ExchangeModels.ContactContext) -> [String: Any] {
        var out: [String: Any] = [
            "relationshipType": context.relationshipType.rawValue,
            "relationshipGoal": context.relationshipGoal.rawValue,
            "aiAssistLevel": context.aiAssistLevel.rawValue,
        ]

        if let label = trimmedNonEmpty(context.customRelationshipLabel) {
            out["customRelationshipLabel"] = label
        }
        if let goal = trimmedNonEmpty(context.customRelationshipGoal) {
            out["customRelationshipGoal"] = goal
        }
        if let notes = trimmedNonEmpty(context.goalNotes) {
            out["goalNotes"] = notes
        }
        if let relationshipNotes = trimmedNonEmpty(context.notes) {
            out["notes"] = relationshipNotes
        }
        if let tone = trimmedNonEmpty(context.toneOverride) {
            out["toneOverride"] = tone
        }

        return out
    }

    static func buildPrivateContextPayload(input: ExchangeModels.DirectReplySuggestionInput) -> [String: String]? {
        var out: [String: String] = [:]

        if let profile = clippedSummary(input.contactPublicProfileSummary, maxChars: profileSummaryMaxChars) {
            out["profileSummary"] = profile
        }
        if let commercial = clippedSummary(input.contactCommercialProfileSummary, maxChars: commercialSummaryMaxChars) {
            out["commercialSummary"] = commercial
        }

        return out.isEmpty ? nil : out
    }

    private static let instructionBlock = """
        Return only JSON object: {"reply":"..."}.
        The strategy layer already selected the move.
        Express selectedMove only.
        Do not choose a different move.
        Write as the local user replying to the remote contact.
        Do not change speaker perspective.
        Use contactBrief privately for warmth, directness, formality, and boundaries.
        Use voiceAnchors only for rhythm and style, never for facts, phrases, promises, dates, or topics.
        Do not reuse words, phrases, facts, promises, dates, or topics from voiceAnchors.
        Use inboundIntent summary and entities plus conversationState to know what is being answered.
        Do not echo the inbound phrasing.
        Do not answer older messages.
        Do not copy previous local messages.
        One reply only.
        No explanation or meta commentary.
        If unsafe or inappropriate, return {"reply":""}.
        """

    // MARK: - Dedupe

    /// Omits the last `recentMessages` row whose normalized text equals `latestIncomingMessage`.
    static func dedupedRecentMessages(
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        latestIncomingMessage: String?
    ) -> (messages: [ExchangeModels.DirectReplyTranscriptMessage], removedLatestIncoming: Bool) {
        let normalizedLatest = normalizeForPromptDedupe(latestIncomingMessage)
        guard !normalizedLatest.isEmpty else {
            return (recentMessages, false)
        }

        guard let removeIndex = recentMessages.indices.reversed().first(where: { index in
            normalizeForPromptDedupe(recentMessages[index].text) == normalizedLatest
        }) else {
            return (recentMessages, false)
        }

        var deduped = recentMessages
        deduped.remove(at: removeIndex)
        return (deduped, true)
    }

    /// Matches `DirectChatReplySuggestionService.normalizeForDuplicateCheck`.
    static func normalizeForPromptDedupe(_ value: String?) -> String {
        let trimmed = value?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased() ?? ""

        return trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clippedSummary(_ value: String?, maxChars: Int) -> String? {
        guard let trimmed = trimmedNonEmpty(value) else { return nil }
        if trimmed.count <= maxChars { return trimmed }
        return String(trimmed.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
