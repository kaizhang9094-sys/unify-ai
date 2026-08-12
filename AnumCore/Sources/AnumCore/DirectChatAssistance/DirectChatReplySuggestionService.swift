import Foundation

public struct DirectChatReplySuggestionService: Sendable {
    private let runner: any ExchangeIntelligenceModelRunner

    public init(runner: any ExchangeIntelligenceModelRunner) {
        self.runner = runner
    }

    public func suggestReply(
        input: ExchangeModels.DirectReplySuggestionInput,
        userInstruction: String? = nil,
        previousSuggestions: [String] = []
    ) async -> ExchangeModels.DirectReplySuggestionOutput {
        #if DEBUG
        let perfServiceStart = CFAbsoluteTimeGetCurrent()
        #endif

        let context = input.contactContext
        let recentMessages = Array(input.recentTranscript.suffix(4))
        let priorSuggestions = trimmedPreviousSuggestions(previousSuggestions)

        let latestInboundRaw = input.latestIncomingMessage?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let latestInbound: String? = latestInboundRaw.isEmpty ? nil : latestInboundRaw

        let hasTone = !(context.toneOverride?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .isEmpty ?? true)

        #if DEBUG
        var summaryPromptChars = 0
        var summaryReplyChars = 0
        defer {
            Self.logDirectReplySummary(
                promptChars: summaryPromptChars,
                recentCount: recentMessages.count,
                hasInbound: latestInbound != nil,
                hasTone: hasTone,
                replyChars: summaryReplyChars
            )
        }
        #endif

        let nodeID = input.remoteNodeID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !nodeID.isEmpty else {
            #if DEBUG
            print("[DirectReplySuggestBlocked] reason=missing_node_id")
            #endif
            return .init(
                reply: "",
                reason: "Missing contact node ID.",
                safety: "manual_only",
                requiresApproval: true
            )
        }

        if context.aiAssistLevel == .autoReplyDisabled {
            #if DEBUG
            print("[DirectReplySuggestBlocked] reason=auto_reply_disabled")
            #endif
            return .init(
                reply: "",
                reason: "AI suggestions disabled for this contact.",
                safety: "manual_only",
                requiresApproval: true
            )
        }

        guard latestInbound != nil else {
            #if DEBUG
            print("[DirectReplySuggestBlocked] reason=no_inbound_messages")
            #endif
            return .init(
                reply: "",
                reason: "No incoming message to reply to.",
                safety: "manual_only",
                requiresApproval: true
            )
        }

        let instructionRaw = userInstruction?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let instruction: String? = instructionRaw.isEmpty ? nil : instructionRaw

        #if DEBUG
        let latestPreview = Self.debugPreview(latestInbound, maxLength: 120)
        let recentPreview = recentMessages.enumerated().map { index, message in
            let text = Self.debugPreview(message.text, maxLength: 90)
            return "\(index):\(message.role.rawValue):\(message.source ?? "nil"):\(text)"
        }.joined(separator: " | ")

        print(
            "[DirectReplyInput] nodeID=\(nodeID) messages=\(recentMessages.count) latestIncoming=\(latestInbound != nil) relationship=\(context.relationshipType.rawValue) goal=\(context.relationshipGoal.rawValue) notesChars=\(context.notes.count) toneChars=\(context.toneOverride?.count ?? 0) previousSuggestionsCount=\(priorSuggestions.count)"
        )
        print(
            "[DirectReplyPromptBasis] latestIncoming=\(latestPreview) recent=\(recentPreview)"
        )
        #endif

        let promptContext = DirectReplyPromptContext.make(
            latestIncoming: latestInbound,
            contactContext: context,
            recentMessages: recentMessages
        )

        #if DEBUG
        Self.logDirectReplyStrategy(promptContext: promptContext)
        #endif

        let prompt = DirectChatReplySuggestionPromptBuilder.buildPrompt(
            input: input,
            recentMessages: recentMessages,
            latestIncomingMessage: latestInbound,
            userInstruction: instruction,
            promptContext: promptContext
        )

        let localVoiceCount = recentMessages.filter { $0.role == .localUser }.suffix(4).count

        #if DEBUG
        summaryPromptChars = prompt.count
        let promptBuiltMs = Int((CFAbsoluteTimeGetCurrent() - perfServiceStart) * 1000)
        print(
            "[DirectReplyPerf] prompt_built promptChars=\(prompt.count) elapsedMs=\(promptBuiltMs) transcriptCount=\(input.recentTranscript.count) recentMessagesCount=\(recentMessages.count)"
        )
        Self.logDirectReplyAudit(
            event: "builtPrompt",
            latestIncomingChars: latestInbound?.count ?? 0,
            recentMessagesCount: recentMessages.count,
            localSentVoiceExamplesCount: localVoiceCount,
            contactContextNonEmptyFields: Self.contactContextNonEmptyFieldCount(context),
            userInstructionChars: instruction?.count ?? 0,
            promptChars: prompt.count,
            previousSuggestionsCount: priorSuggestions.count
        )
        #endif

        var pendingFallbackReason = DirectReplyFallbackReason.parse_failed

        do {
            var raw = try await runModel(prompt: prompt)

            #if DEBUG
            let rawOutputChars = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).count
            print(
                "[DirectReplyRawOutput] chars=\(rawOutputChars) preview=\(Self.debugPreview(raw, maxLength: 300))"
            )
            Self.logDirectReplyAudit(
                event: "modelOutput",
                rawOutputChars: rawOutputChars
            )
            #endif

            if Self.shouldAttemptParseRetry(raw: raw) {
                #if DEBUG
                print("[DirectReplyParseRetry] phase=start")
                #endif
                if let retryRaw = try? await runModel(prompt: prompt) {
                    raw = retryRaw
                    #if DEBUG
                    print(
                        "[DirectReplyParseRetry] phase=raw chars=\(retryRaw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).count)"
                    )
                    #endif
                }
            }

            if let parsed = DirectChatReplySuggestionParser.parse(raw: raw) {
                if let accepted = await acceptParsedReply(
                    parsed: parsed,
                    input: input,
                    recentMessages: recentMessages,
                    latestInbound: latestInbound,
                    previousSuggestions: priorSuggestions,
                    promptContext: promptContext
                ) {
                    #if DEBUG
                    summaryReplyChars = accepted.reply.count
                    #endif
                    return Self.deliverFinalSuggestion(
                        accepted,
                        promptContext: promptContext,
                        fallback: false
                    )
                }

                pendingFallbackReason = .duplicate_retry_failed
            } else {
                pendingFallbackReason = .parse_failed

                #if DEBUG
                let parseFailMs = Int((CFAbsoluteTimeGetCurrent() - perfServiceStart) * 1000)
                print(
                    "[DirectReplyPerf] parse_done elapsedMs=\(parseFailMs) replyChars=0 rawOutputChars=\(raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).count)"
                )
                print("[DirectReplySuggest] nodeID=\(nodeID) success=false replyChars=0 reasonChars=0 requiresApproval=true")
                Self.logDirectReplyAudit(
                    event: "parsed",
                    parsedReplyChars: 0,
                    duplicateGuardTriggered: false,
                    duplicateRetryAttempted: false,
                    duplicateRetrySucceeded: false,
                    fallbackUsed: false
                )
                #endif
            }
        } catch {
            pendingFallbackReason = .runner_failed

            #if DEBUG
            let errMs = Int((CFAbsoluteTimeGetCurrent() - perfServiceStart) * 1000)
            print(
                "[DirectReplyPerf] runner_error elapsedMs=\(errMs) error=\(String(describing: error))"
            )
            print(
                "[DirectReplySuggest] nodeID=\(nodeID) success=false replyChars=0 reasonChars=0 requiresApproval=true"
            )
            #endif
        }

        let fallback = Self.makeFallbackSuggestion(
            input: input,
            latestInbound: latestInbound,
            reason: pendingFallbackReason,
            duplicateRetry: Self.duplicateRetryNoneLabel
        )

        #if DEBUG
        let fbMs = Int((CFAbsoluteTimeGetCurrent() - perfServiceStart) * 1000)
        print(
            "[DirectReplyPerf] suggest_complete totalSuggestMs=\(fbMs) promptChars=\(prompt.count) replyChars=\(fallback.reply.count) fallback=true"
        )
        summaryReplyChars = fallback.reply.count
        Self.logDirectReplyAudit(
            event: "fallback",
            parsedReplyChars: fallback.reply.count,
            duplicateGuardTriggered: false,
            duplicateRetryAttempted: false,
            duplicateRetrySucceeded: false,
            fallbackUsed: true,
            fallbackReason: pendingFallbackReason.rawValue
        )
        #endif
        return Self.deliverFinalSuggestion(
            fallback,
            promptContext: promptContext,
            fallback: true
        )
    }

    private func acceptParsedReply(
        parsed: ExchangeModels.DirectReplySuggestionOutput,
        input: ExchangeModels.DirectReplySuggestionInput,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        latestInbound: String?,
        previousSuggestions: [String],
        promptContext: DirectReplyPromptContext
    ) async -> ExchangeModels.DirectReplySuggestionOutput? {
        let findings = qualityFindings(
            reply: parsed.reply,
            input: input,
            recentMessages: recentMessages,
            latestInbound: latestInbound,
            previousSuggestions: previousSuggestions,
            promptContext: promptContext
        )
        let issues = findings.map(\.issue)

        #if DEBUG
        Self.logDirectReplyAudit(
            event: "parsed",
            parsedReplyChars: parsed.reply.count,
            duplicateGuardTriggered: !issues.isEmpty,
            duplicateRetryAttempted: false,
            duplicateRetrySucceeded: false,
            fallbackUsed: false,
            qualityIssues: issues.map(\.rawValue).joined(separator: ",")
        )
        #endif

        if issues.isEmpty {
            var successOutput = parsed
            successOutput.duplicateRetry = Self.duplicateRetryNoneLabel
            return successOutput
        }

        #if DEBUG
        for finding in findings {
            let roleLabel = finding.matchedRole?.rawValue ?? "-"
            let indexLabel = finding.matchedIndex.map(String.init) ?? "-"
            print(
                "[DirectReplyQualityRejected] issues=\(finding.issue.rawValue) " +
                    "matchedRole=\(roleLabel) matchedIndex=\(indexLabel)"
            )
        }
        print(
            "[DirectReplyQualityRejected] summary issues=\(issues.map(\.rawValue).joined(separator: ",")) " +
                "replyPreview=\(Self.debugPreview(parsed.reply, maxLength: 180))"
        )
        Self.logDirectReplyAudit(
            event: "duplicate",
            parsedReplyChars: parsed.reply.count,
            duplicateGuardTriggered: true,
            duplicateRetryAttempted: true,
            duplicateRetrySucceeded: false,
            fallbackUsed: false,
            qualityIssues: issues.map(\.rawValue).joined(separator: ",")
        )
        #endif

        let retryInstruction = retryInstructionForQualityIssues(issues)
        if let retryOutput = await attemptModelRetry(
            input: input,
            recentMessages: recentMessages,
            latestInbound: latestInbound,
            userInstruction: retryInstruction,
            previousSuggestions: previousSuggestions,
            promptContext: promptContext
        ) {
            #if DEBUG
            Self.logDirectReplyAudit(
                event: "duplicate",
                parsedReplyChars: retryOutput.reply.count,
                duplicateGuardTriggered: true,
                duplicateRetryAttempted: true,
                duplicateRetrySucceeded: true,
                fallbackUsed: false,
                qualityIssues: issues.map(\.rawValue).joined(separator: ",")
            )
            #endif
            return retryOutput
        }

        return nil
    }

    private func qualityFindings(
        reply: String,
        input: ExchangeModels.DirectReplySuggestionInput,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        latestInbound: String?,
        previousSuggestions: [String],
        promptContext: DirectReplyPromptContext
    ) -> [DirectReplyQualityFinding] {
        #if DEBUG
        let remoteCount = recentMessages.filter { $0.role == .remoteContact }.count
        let localCount = recentMessages.filter { $0.role == .localUser }.count
        print(
            "[DirectReplyQualityInput] recentMessagesCount=\(recentMessages.count) " +
                "remoteCount=\(remoteCount) localCount=\(localCount) " +
                "priorSuggestionsCount=\(previousSuggestions.count)"
        )
        #endif

        let strategyContext = DirectReplyQualityContext(
            latestIntent: promptContext.latestIntent,
            selectedMove: promptContext.selectedMove,
            conversationState: promptContext.conversationState
        )

        var findings = DirectChatReplySuggestionQuality.evaluateFindings(
            reply: reply,
            latestInbound: latestInbound,
            recentMessages: recentMessages,
            fullTranscript: input.recentTranscript,
            previousSuggestions: previousSuggestions,
            strategyContext: strategyContext
        )

        if findings.isEmpty,
           Self.findExactTranscriptDuplicate(
               reply,
               input: input,
               recentMessages: recentMessages,
               latestInbound: latestInbound
           ) != nil {
            findings = [DirectReplyQualityFinding(issue: .exactDuplicate)]
        }

        return findings
    }

    private func qualityIssues(
        reply: String,
        input: ExchangeModels.DirectReplySuggestionInput,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        latestInbound: String?,
        previousSuggestions: [String],
        promptContext: DirectReplyPromptContext
    ) -> [DirectReplyQualityIssue] {
        qualityFindings(
            reply: reply,
            input: input,
            recentMessages: recentMessages,
            latestInbound: latestInbound,
            previousSuggestions: previousSuggestions,
            promptContext: promptContext
        )
        .map(\.issue)
    }

    private static let directChatReplyMaxTokens = 220

    private static let duplicateRetryNoneLabel = "none"
    private static let duplicateRetrySuccessLabel = "success"
    private static let duplicateRetryFailedLabel = "failed"

    #if DEBUG
    private static let parseRetryDefaultsKey = "DirectChatReplyParseRetryEnabled"
    #endif

    private static let duplicateRetryUserInstruction =
        "Generate a different reply. Do not use the same opening or sentence pattern. " +
        "Do not copy, quote, paraphrase, or repeat latestIncomingMessage or any transcript message. " +
        "Write a natural reply that moves the conversation forward."

    private static let contextAwareRetryUserInstruction =
        "Answer only the latest incoming message. Do not answer earlier messages. " +
        "Do not copy or reuse previous local messages as the reply. " +
        "If asked whether something was done, answer the current status instead of repeating an old promise. " +
        "Write one natural DM reply that moves the conversation forward."

    private static let wrongSpeakerRetryUserInstruction =
        "The other person is the one reporting the delay. Reply from the local user's perspective. " +
        "Do not say you are running late. Reassure or object directly."

    private func runModel(prompt: String) async throws -> String {
        try await runner.run(
            .init(
                task: .directChatReply,
                prompt: prompt,
                maxTokens: Self.directChatReplyMaxTokens,
                representationSupplement: nil
            )
        )
    }

    private func attemptModelRetry(
        input: ExchangeModels.DirectReplySuggestionInput,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        latestInbound: String?,
        userInstruction: String,
        previousSuggestions: [String],
        promptContext: DirectReplyPromptContext
    ) async -> ExchangeModels.DirectReplySuggestionOutput? {
        #if DEBUG
        print("[DirectReplyDuplicateRetry] phase=start")
        #endif

        let retryPromptContext = DirectReplyPromptContext.make(
            latestIncoming: latestInbound,
            contactContext: input.contactContext,
            recentMessages: recentMessages
        )

        let retryPrompt = DirectChatReplySuggestionPromptBuilder.buildPrompt(
            input: input,
            recentMessages: recentMessages,
            latestIncomingMessage: latestInbound,
            userInstruction: userInstruction,
            promptContext: retryPromptContext
        )

        let raw: String
        do {
            raw = try await runModel(prompt: retryPrompt)
        } catch {
            #if DEBUG
            print("[DirectReplyDuplicateRetry] phase=failed reason=runner_failed")
            #endif
            return nil
        }

        #if DEBUG
        let rawChars = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).count
        print("[DirectReplyDuplicateRetry] phase=raw chars=\(rawChars)")
        #endif

        guard let parsed = DirectChatReplySuggestionParser.parse(raw: raw) else {
            #if DEBUG
            print("[DirectReplyDuplicateRetry] phase=failed reason=parse_failed")
            #endif
            return nil
        }

        let replyTrimmed = parsed.reply.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if replyTrimmed.isEmpty {
            #if DEBUG
            print("[DirectReplyDuplicateRetry] phase=failed reason=empty_reply")
            #endif
            return nil
        }

        let retryIssues = qualityIssues(
            reply: parsed.reply,
            input: input,
            recentMessages: recentMessages,
            latestInbound: latestInbound,
            previousSuggestions: previousSuggestions,
            promptContext: promptContext
        )
        if !retryIssues.isEmpty {
            #if DEBUG
            print(
                "[DirectReplyDuplicateRetry] phase=failed reason=quality issues=\(retryIssues.map(\.rawValue).joined(separator: ","))"
            )
            #endif
            return nil
        }

        var successOutput = parsed
        successOutput.duplicateRetry = Self.duplicateRetrySuccessLabel

        #if DEBUG
        print("[DirectReplyDuplicateRetry] phase=success replyChars=\(successOutput.reply.count)")
        #endif

        return successOutput
    }

    private func retryInstructionForQualityIssues(_ issues: [DirectReplyQualityIssue]) -> String {
        if issues.contains(.wrongSpeakerPerspective) {
            return Self.wrongSpeakerRetryUserInstruction
        }

        if issues.contains(.answeredOlderMessage) || issues.contains(.oldLocalContentCopy) {
            return Self.contextAwareRetryUserInstruction
        }

        var parts = [Self.duplicateRetryUserInstruction]
        if issues.contains(.highInboundOverlap) {
            parts.append("Do not paraphrase latestIncomingMessage.")
        }
        if issues.contains(.highPriorSuggestionOverlap) || issues.contains(.repeatedOpening) {
            parts.append("Use a clearly different opening and wording from any previous suggestion.")
        }
        return parts.joined(separator: " ")
    }

    private func trimmedPreviousSuggestions(_ suggestions: [String]) -> [String] {
        suggestions
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    #if DEBUG
    private static func shouldAttemptParseRetry(raw: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: parseRetryDefaultsKey) else { return false }
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return DirectChatReplySuggestionParser.parse(raw: raw) == nil
    }
    #else
    private static func shouldAttemptParseRetry(raw: String) -> Bool { false }
    #endif

    private enum DirectReplyFallbackReason: String {
        case parse_failed
        case duplicate
        case duplicate_retry_failed
        case runner_failed
    }

    private static func makeFallbackSuggestion(
        input: ExchangeModels.DirectReplySuggestionInput,
        latestInbound: String?,
        reason: DirectReplyFallbackReason,
        duplicateRetry: String
    ) -> ExchangeModels.DirectReplySuggestionOutput {
        let context = input.contactContext
        let selectionKey = fallbackSelectionKey(
            remoteNodeID: input.remoteNodeID,
            latestInbound: latestInbound
        )
        #if DEBUG
        logDirectReplyFallback(
            reason: reason,
            relationshipType: context.relationshipType,
            latestInboundMessage: latestInbound
        )
        #endif
        var output = DirectChatReplySuggestionPolicy.fallbackDirectReplySuggestion(
            displayName: input.contactDisplayName,
            latestInboundMessage: latestInbound,
            relationshipType: context.relationshipType,
            relationshipGoal: context.relationshipGoal,
            selectionKey: selectionKey
        )
        output.fallbackReason = reason.rawValue
        output.duplicateRetry = duplicateRetry
        return output
    }

    private static func fallbackSelectionKey(remoteNodeID: String, latestInbound: String?) -> String {
        let inboundPrefix = String((latestInbound ?? "").prefix(80))
        return "\(remoteNodeID)|\(inboundPrefix)"
    }

    #if DEBUG
    private static func contactContextNonEmptyFieldCount(_ context: ExchangeModels.ContactContext) -> Int {
        var count = 0
        if !(context.customRelationshipLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            count += 1
        }
        if !(context.customRelationshipGoal?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            count += 1
        }
        if !(context.goalNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            count += 1
        }
        if !context.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            count += 1
        }
        if !(context.toneOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            count += 1
        }
        count += 2
        return count
    }

    private static func logDirectReplyAudit(
        event: String,
        latestIncomingChars: Int? = nil,
        recentMessagesCount: Int? = nil,
        localSentVoiceExamplesCount: Int? = nil,
        contactContextNonEmptyFields: Int? = nil,
        userInstructionChars: Int? = nil,
        promptChars: Int? = nil,
        rawOutputChars: Int? = nil,
        parsedReplyChars: Int? = nil,
        duplicateGuardTriggered: Bool? = nil,
        duplicateRetryAttempted: Bool? = nil,
        duplicateRetrySucceeded: Bool? = nil,
        fallbackUsed: Bool? = nil,
        fallbackReason: String? = nil,
        previousSuggestionsCount: Int? = nil,
        qualityIssues: String? = nil
    ) {
        var parts: [String] = [
            "promptKind=directChatReply",
            "maxTokens=\(directChatReplyMaxTokens)"
        ]
        if let latestIncomingChars {
            parts.append("latestIncomingChars=\(latestIncomingChars)")
        }
        if let recentMessagesCount {
            parts.append("recentMessagesCount=\(recentMessagesCount)")
        }
        if let localSentVoiceExamplesCount {
            parts.append("localSentVoiceExamplesCount=\(localSentVoiceExamplesCount)")
        }
        if let contactContextNonEmptyFields {
            parts.append("contactContextNonEmptyFields=\(contactContextNonEmptyFields)")
        }
        if let userInstructionChars {
            parts.append("userInstructionChars=\(userInstructionChars)")
        }
        if let promptChars {
            parts.append("promptChars=\(promptChars)")
        }
        if let rawOutputChars {
            parts.append("rawOutputChars=\(rawOutputChars)")
        }
        if let parsedReplyChars {
            parts.append("parsedReplyChars=\(parsedReplyChars)")
        }
        if let duplicateGuardTriggered {
            parts.append("duplicateGuardTriggered=\(duplicateGuardTriggered)")
        }
        if let duplicateRetryAttempted {
            parts.append("duplicateRetryAttempted=\(duplicateRetryAttempted)")
        }
        if let duplicateRetrySucceeded {
            parts.append("duplicateRetrySucceeded=\(duplicateRetrySucceeded)")
        }
        if let fallbackUsed {
            parts.append("fallbackUsed=\(fallbackUsed)")
        }
        if let fallbackReason, !fallbackReason.isEmpty {
            parts.append("fallbackReason=\(fallbackReason)")
        }
        if let previousSuggestionsCount {
            parts.append("previousSuggestionsCount=\(previousSuggestionsCount)")
        }
        if let qualityIssues, !qualityIssues.isEmpty {
            parts.append("qualityIssues=\(qualityIssues)")
        }
        print("[DirectReplyAudit] \(event) \(parts.joined(separator: " "))")
    }

    private static func logDirectReplyFallback(
        reason: DirectReplyFallbackReason,
        relationshipType: ExchangeModels.ContactRelationshipType,
        latestInboundMessage: String?
    ) {
        let latestIncomingChars = latestInboundMessage?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .count ?? 0
        print(
            "[DirectReplyFallback] reason=\(reason.rawValue) " +
                "relationship=\(relationshipType.rawValue) latestIncomingChars=\(latestIncomingChars)"
        )
    }

    public static func logDirectReplySummary(
        promptChars: Int,
        recentCount: Int,
        hasInbound: Bool,
        hasTone: Bool,
        replyChars: Int
    ) {
        print(
            "[DirectReplySummary] task=directChatReply promptChars=\(promptChars) " +
                "recentCount=\(recentCount) hasInbound=\(hasInbound) hasTone=\(hasTone) " +
                "replyChars=\(replyChars) requiresApproval=true path=suggestionOnly"
        )
    }

    private static func logDirectReplyStrategy(promptContext: DirectReplyPromptContext) {
        let stakes = promptContext.contactBrief?.stakes.rawValue ?? "-"
        let reasonPreview = debugPreview(promptContext.selectedMove.reason, maxLength: 80)
        print(
            "[DirectReplyStrategy] intent=\(promptContext.latestIntent.kind.rawValue) " +
                "statePhase=\(promptContext.conversationState.phase.rawValue) " +
                "move=\(promptContext.selectedMove.kind.rawValue) " +
                "reason=\(reasonPreview) " +
                "constraints=\(promptContext.selectedMove.constraints.count) " +
                "stakes=\(stakes) " +
                "anchors=\(promptContext.voiceAnchors.count)"
        )
    }

    private static func logFinalReply(
        _ reply: String,
        fallback: Bool,
        retryUsed: Bool,
        intent: DirectReplyLatestIntent?,
        selectedMove: DirectReplySelectedMove?
    ) {
        let preview = reply
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let capped = String(preview.prefix(180))
        print(
            "[DirectReplyFinal] replyChars=\(reply.count) fallback=\(fallback) retryUsed=\(retryUsed) " +
                "move=\(selectedMove?.kind.rawValue ?? "-") intent=\(intent?.kind.rawValue ?? "-") " +
                "replyPreview=\(capped)"
        )
    }
    #endif

    private static func deliverFinalSuggestion(
        _ output: ExchangeModels.DirectReplySuggestionOutput,
        promptContext: DirectReplyPromptContext,
        fallback: Bool
    ) -> ExchangeModels.DirectReplySuggestionOutput {
        #if DEBUG
        let retryUsed = output.duplicateRetry == duplicateRetrySuccessLabel
        logFinalReply(
            output.reply,
            fallback: fallback,
            retryUsed: retryUsed,
            intent: promptContext.latestIntent,
            selectedMove: promptContext.selectedMove
        )
        #endif
        return output
    }

    private struct TranscriptDuplicateDiagnosis: Sendable {
        enum MatchedSource: String, Sendable {
            case latestIncoming
            case recentMessages
            case inputRecentTranscript
        }

        var matchedSource: MatchedSource
        var role: ExchangeModels.DirectReplyTranscriptRole?
        var index: Int?
        var matchedText: String
    }

    #if DEBUG
    private static func logDirectReplyDuplicateDiagnosis(
        reply: String,
        diagnosis: TranscriptDuplicateDiagnosis
    ) {
        let roleLabel = diagnosis.role?.rawValue ?? "none"
        let indexLabel = diagnosis.index.map(String.init) ?? "-"
        print(
            "[DirectReplyDuplicateDiagnosis] matchedSource=\(diagnosis.matchedSource.rawValue) " +
                "role=\(roleLabel) index=\(indexLabel) " +
                "replyPreview=\"\(debugPreview(reply, maxLength: 180))\" " +
                "matchedPreview=\"\(debugPreview(diagnosis.matchedText, maxLength: 180))\""
        )
    }
    #endif

    private static func findExactTranscriptDuplicate(
        _ reply: String,
        input: ExchangeModels.DirectReplySuggestionInput,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        latestInbound: String?
    ) -> TranscriptDuplicateDiagnosis? {
        let normalizedReply = normalizeForDuplicateCheck(reply)
        guard !normalizedReply.isEmpty else { return nil }

        if normalizeForDuplicateCheck(latestInbound) == normalizedReply {
            return TranscriptDuplicateDiagnosis(
                matchedSource: .latestIncoming,
                role: nil,
                index: nil,
                matchedText: latestInbound ?? ""
            )
        }

        for (index, message) in recentMessages.enumerated() {
            if normalizeForDuplicateCheck(message.text) == normalizedReply {
                return TranscriptDuplicateDiagnosis(
                    matchedSource: .recentMessages,
                    role: message.role,
                    index: index,
                    matchedText: message.text
                )
            }
        }

        for (index, message) in input.recentTranscript.enumerated() {
            if normalizeForDuplicateCheck(message.text) == normalizedReply {
                return TranscriptDuplicateDiagnosis(
                    matchedSource: .inputRecentTranscript,
                    role: message.role,
                    index: index,
                    matchedText: message.text
                )
            }
        }

        return nil
    }

    private static func normalizeForDuplicateCheck(_ value: String?) -> String {
        DirectChatReplySuggestionQuality.normalizeForQualityCheck(value)
    }

    private static func debugPreview(_ value: String?, maxLength: Int) -> String {
        let cleaned = value?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t") ?? "nil"

        return String(cleaned.prefix(maxLength))
    }
}
