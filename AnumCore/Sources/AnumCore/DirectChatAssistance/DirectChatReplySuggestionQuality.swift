import Foundation

public enum DirectReplyQualityIssue: String, Sendable, Hashable {
    case exactDuplicate
    case highInboundOverlap
    case highPriorSuggestionOverlap
    case repeatedOpening
    case answeredOlderMessage
    case oldLocalContentCopy
    case wrongSpeakerPerspective
}

public struct DirectReplyQualityFinding: Sendable, Hashable {
    public var issue: DirectReplyQualityIssue
    public var matchedRole: ExchangeModels.DirectReplyTranscriptRole?
    public var matchedIndex: Int?

    public init(
        issue: DirectReplyQualityIssue,
        matchedRole: ExchangeModels.DirectReplyTranscriptRole? = nil,
        matchedIndex: Int? = nil
    ) {
        self.issue = issue
        self.matchedRole = matchedRole
        self.matchedIndex = matchedIndex
    }
}

/// Deterministic reply-quality checks for direct-chat suggestions (no LLM).
public enum DirectChatReplySuggestionQuality {
    public static let minTokenCountForOverlapCheck = 4
    public static let inboundOverlapThreshold = 0.55
    public static let priorSuggestionOverlapThreshold = 0.70
    public static let openingPhraseWordCount = 3

    public static let answeredOlderMinReplyTokens = 5
    public static let answeredOlderRemoteOverlapThreshold = 0.45
    public static let answeredOlderOpeningWordCount = 2

    public static let oldLocalCopyMinReplyTokens = 6
    public static let oldLocalCopyTokenOverlapThreshold = 0.50
    public static let oldLocalCopyPhraseWordCount = 4
    public static let oldLocalCopyMinPhraseCharacters = 12

    public static func evaluate(
        reply: String,
        latestInbound: String?,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        fullTranscript: [ExchangeModels.DirectReplyTranscriptMessage] = [],
        previousSuggestions: [String],
        strategyContext: DirectReplyQualityContext? = nil
    ) -> [DirectReplyQualityIssue] {
        evaluateFindings(
            reply: reply,
            latestInbound: latestInbound,
            recentMessages: recentMessages,
            fullTranscript: fullTranscript,
            previousSuggestions: previousSuggestions,
            strategyContext: strategyContext
        )
        .map(\.issue)
    }

    public static func evaluateFindings(
        reply: String,
        latestInbound: String?,
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        fullTranscript: [ExchangeModels.DirectReplyTranscriptMessage] = [],
        previousSuggestions: [String],
        strategyContext: DirectReplyQualityContext? = nil
    ) -> [DirectReplyQualityFinding] {
        let normalizedReply = normalizeForQualityCheck(reply)
        guard !normalizedReply.isEmpty else { return [] }

        var findings: [DirectReplyQualityFinding] = []
        var seenIssues = Set<DirectReplyQualityIssue>()

        func appendFinding(_ finding: DirectReplyQualityFinding) {
            guard seenIssues.insert(finding.issue).inserted else { return }
            findings.append(finding)
        }

        let normalizedLatestInbound = normalizeForQualityCheck(latestInbound)

        if !normalizedLatestInbound.isEmpty, normalizedLatestInbound == normalizedReply {
            appendFinding(DirectReplyQualityFinding(issue: .exactDuplicate))
        }

        for (index, message) in recentMessages.enumerated() {
            if normalizeForQualityCheck(message.text) == normalizedReply {
                appendFinding(
                    DirectReplyQualityFinding(
                        issue: .exactDuplicate,
                        matchedRole: message.role,
                        matchedIndex: index
                    )
                )
                break
            }
        }

        if !seenIssues.contains(.exactDuplicate) {
            for (index, message) in fullTranscript.enumerated() {
                if normalizeForQualityCheck(message.text) == normalizedReply {
                    appendFinding(
                        DirectReplyQualityFinding(
                            issue: .exactDuplicate,
                            matchedRole: message.role,
                            matchedIndex: index
                        )
                    )
                    break
                }
            }
        }

        let replyTokens = tokenSet(normalizedReply)
        let replyTokenCount = replyTokens.count

        if replyTokenCount >= minTokenCountForOverlapCheck,
           !normalizedLatestInbound.isEmpty {
            let inboundOverlap = tokenOverlapRatio(
                replyTokens,
                tokenSet(normalizedLatestInbound)
            )
            if inboundOverlap >= inboundOverlapThreshold {
                appendFinding(DirectReplyQualityFinding(issue: .highInboundOverlap))
            }
        }

        if replyTokenCount >= answeredOlderMinReplyTokens {
            let olderRemotes = olderRemoteMessages(
                recentMessages: recentMessages,
                normalizedLatestInbound: normalizedLatestInbound
            )
            for (index, message) in olderRemotes {
                let olderNorm = normalizeForQualityCheck(message.text)
                guard !olderNorm.isEmpty else { continue }

                if replyStartsWithOpening(
                    normalizedReply,
                    olderNorm,
                    wordCount: answeredOlderOpeningWordCount
                ) {
                    appendFinding(
                        DirectReplyQualityFinding(
                            issue: .answeredOlderMessage,
                            matchedRole: .remoteContact,
                            matchedIndex: index
                        )
                    )
                    break
                }

                let olderTokens = tokenSet(olderNorm)
                guard olderTokens.count >= answeredOlderOpeningWordCount else { continue }

                let overlap = tokenOverlapRatio(replyTokens, olderTokens)
                if overlap >= answeredOlderRemoteOverlapThreshold {
                    appendFinding(
                        DirectReplyQualityFinding(
                            issue: .answeredOlderMessage,
                            matchedRole: .remoteContact,
                            matchedIndex: index
                        )
                    )
                    break
                }

                if normalizedReply.hasPrefix(olderNorm),
                   olderNorm.split(separator: " ").count >= answeredOlderOpeningWordCount {
                    appendFinding(
                        DirectReplyQualityFinding(
                            issue: .answeredOlderMessage,
                            matchedRole: .remoteContact,
                            matchedIndex: index
                        )
                    )
                    break
                }
            }
        }

        if replyTokenCount >= oldLocalCopyMinReplyTokens {
            for (index, message) in recentMessages.enumerated() where message.role == .localUser {
                let localNorm = normalizeForQualityCheck(message.text)
                guard !localNorm.isEmpty else { continue }

                if containsDistinctivePhrase(
                    normalizedReply,
                    from: localNorm,
                    phraseWordCount: oldLocalCopyPhraseWordCount,
                    minPhraseCharacters: oldLocalCopyMinPhraseCharacters
                ) {
                    appendFinding(
                        DirectReplyQualityFinding(
                            issue: .oldLocalContentCopy,
                            matchedRole: .localUser,
                            matchedIndex: index
                        )
                    )
                    break
                }

                let localTokens = tokenSet(localNorm)
                guard !localTokens.isEmpty else { continue }

                let overlap = tokenOverlapRatio(replyTokens, localTokens)
                if overlap >= oldLocalCopyTokenOverlapThreshold {
                    appendFinding(
                        DirectReplyQualityFinding(
                            issue: .oldLocalContentCopy,
                            matchedRole: .localUser,
                            matchedIndex: index
                        )
                    )
                    break
                }
            }
        }

        if replyTokenCount >= minTokenCountForOverlapCheck {
            let replyOpening = openingPhrase(
                normalizedReply,
                wordCount: openingPhraseWordCount
            )
            if !replyOpening.isEmpty {
                for prior in previousSuggestions {
                    let priorNorm = normalizeForQualityCheck(prior)
                    guard !priorNorm.isEmpty else { continue }

                    let priorOverlap = tokenOverlapRatio(replyTokens, tokenSet(priorNorm))
                    if priorOverlap >= priorSuggestionOverlapThreshold {
                        appendFinding(DirectReplyQualityFinding(issue: .highPriorSuggestionOverlap))
                        break
                    }

                    let priorOpening = openingPhrase(
                        priorNorm,
                        wordCount: openingPhraseWordCount
                    )
                    if !priorOpening.isEmpty, priorOpening == replyOpening {
                        appendFinding(DirectReplyQualityFinding(issue: .repeatedOpening))
                        break
                    }
                }

                if !seenIssues.contains(.repeatedOpening) {
                    var lastLocalIndex: Int?
                    var lastLocalText: String?
                    for (index, message) in recentMessages.enumerated() where message.role == .localUser {
                        lastLocalIndex = index
                        lastLocalText = message.text
                    }
                    if let lastLocalIndex, let lastLocalText {
                        let localOpening = openingPhrase(
                            normalizeForQualityCheck(lastLocalText),
                            wordCount: openingPhraseWordCount
                        )
                        if !localOpening.isEmpty, localOpening == replyOpening {
                            appendFinding(
                                DirectReplyQualityFinding(
                                    issue: .repeatedOpening,
                                    matchedRole: .localUser,
                                    matchedIndex: lastLocalIndex
                                )
                            )
                        }
                    }
                }
            }
        }

        if let strategyContext,
           matchesWrongSpeakerPerspective(
               normalizedReply: normalizedReply,
               latestInbound: normalizedLatestInbound,
               strategyContext: strategyContext
           ) {
            appendFinding(DirectReplyQualityFinding(issue: .wrongSpeakerPerspective))
        }

        return findings.sorted { $0.issue.rawValue < $1.issue.rawValue }
    }

    static func matchesWrongSpeakerPerspective(
        normalizedReply: String,
        latestInbound: String,
        strategyContext: DirectReplyQualityContext
    ) -> Bool {
        let intent = strategyContext.latestIntent
        let move = strategyContext.selectedMove

        let delayIntent = intent.kind == .delayConfirmation
            || intent.kind == .schedulingConfirmation
        let reassureMove = move.kind == .reassure
        guard delayIntent || reassureMove else { return false }

        guard remoteReportsDelay(latestInbound: latestInbound, intent: intent) else { return false }

        let localLatePhrases = [
            "i'm running late",
            "i am running late",
            "i'm running a bit late",
            "i am running a bit late",
            "i'll be late",
            "i will be late",
            "i'm going to be late",
            "i am going to be late",
        ]
        return localLatePhrases.contains { normalizedReply.contains($0) }
    }

    static func remoteReportsDelay(latestInbound: String, intent: DirectReplyLatestIntent) -> Bool {
        if !latestInbound.isEmpty {
            let needles = [
                "running late", "running about", "be late", "i'll be late", "still good", "still on",
            ]
            if needles.contains(where: { latestInbound.contains($0) }) {
                return true
            }
        }

        let summary = normalizeForQualityCheck(intent.summary)
        let delayNeedles = ["running late", "still good", "late", "delay", "timing change"]
        return delayNeedles.contains { summary.contains($0) }
    }

    // MARK: - Role helpers

    static func olderRemoteMessages(
        recentMessages: [ExchangeModels.DirectReplyTranscriptMessage],
        normalizedLatestInbound: String
    ) -> [(index: Int, message: ExchangeModels.DirectReplyTranscriptMessage)] {
        recentMessages.enumerated().compactMap { index, message in
            guard message.role == .remoteContact else { return nil }
            let normalized = normalizeForQualityCheck(message.text)
            guard !normalized.isEmpty else { return nil }
            if !normalizedLatestInbound.isEmpty, normalized == normalizedLatestInbound {
                return nil
            }
            return (index, message)
        }
    }

    static func replyStartsWithOpening(
        _ normalizedReply: String,
        _ normalizedOlder: String,
        wordCount: Int
    ) -> Bool {
        let replyOpening = openingPhrase(normalizedReply, wordCount: wordCount)
        let olderOpening = openingPhrase(normalizedOlder, wordCount: wordCount)
        guard !replyOpening.isEmpty, !olderOpening.isEmpty else { return false }
        guard replyOpening == olderOpening else { return false }

        let olderWords = normalizedOlder
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        return olderWords.count >= wordCount
    }

    static func containsDistinctivePhrase(
        _ normalizedReply: String,
        from normalizedLocal: String,
        phraseWordCount: Int,
        minPhraseCharacters: Int
    ) -> Bool {
        let localWords = normalizedLocal
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard localWords.count >= phraseWordCount else { return false }

        for start in 0...(localWords.count - phraseWordCount) {
            let phrase = localWords[start..<(start + phraseWordCount)].joined(separator: " ")
            if phrase.count >= minPhraseCharacters, normalizedReply.contains(phrase) {
                return true
            }
        }
        return false
    }

    public static func normalizeForQualityCheck(_ value: String?) -> String {
        let trimmed = value?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased() ?? ""

        return trimmed
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    static func tokenSet(_ normalizedText: String) -> Set<String> {
        Set(
            normalizedText
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    static func tokenOverlapRatio(_ reply: Set<String>, _ other: Set<String>) -> Double {
        guard !reply.isEmpty, !other.isEmpty else { return 0 }
        let intersection = reply.intersection(other).count
        return Double(intersection) / Double(reply.count)
    }

    static func openingPhrase(_ normalizedText: String, wordCount: Int) -> String {
        let words = normalizedText
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard words.count >= wordCount else { return "" }
        return words.prefix(wordCount).joined(separator: " ")
    }
}
