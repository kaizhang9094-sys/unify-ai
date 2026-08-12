import Foundation

/// Resolves user-facing request text for child coordination threads (write path only).
enum ExchangeChildCoordinationRequestText: Sendable {

    struct Resolution: Sendable, Hashable {
        var text: String
        var source: String
    }

    /// First user `requestCaptured` turn — detail preferred over summary.
    static func capturedRequesterText(from turns: [ExchangeTurn]) -> String? {
        if let userTurn = turns.first(where: { $0.kind == .requestCaptured && $0.actor == .user }) {
            return displayText(from: userTurn)
        }
        guard let turn = turns.first(where: { $0.kind == .requestCaptured }) else {
            return nil
        }
        return displayText(from: turn)
    }

    /// Latest user `requestCaptured` turn — used for umbrella child coordination on reused workbenches.
    static func latestCapturedRequesterText(from turns: [ExchangeTurn]) -> String? {
        let userTurns = turns.filter { $0.kind == .requestCaptured && $0.actor == .user }
        if let latestUser = userTurns.max(by: { $0.createdAt < $1.createdAt }) {
            return displayText(from: latestUser)
        }
        guard let latest = turns.filter({ $0.kind == .requestCaptured }).max(by: { $0.createdAt < $1.createdAt }) else {
            return nil
        }
        return displayText(from: latest)
    }

    /// True when `text` matches internal discovery keyword rails (not a human request sentence).
    static func isLikelyKeywordRail(
        _ text: String,
        interpretation: ExchangeThread.InterpretationSnapshot?
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let interpretation, !interpretation.discoveryKeywords.isEmpty else { return false }

        let normalized = trimmed.lowercased()
        let joined = interpretation.discoveryKeywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !joined.isEmpty else { return false }

        if normalized == joined { return true }

        let textTokens = Set(
            normalized.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        )
        let keywordTokens = Set(
            joined.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        )
        guard !keywordTokens.isEmpty, textTokens.count >= 3 else { return false }

        if textTokens == keywordTokens { return true }

        let hasSentencePunctuation = trimmed.contains(where: { ".!?,".contains($0) })
        if !hasSentencePunctuation, textTokens.isSubset(of: keywordTokens) {
            return true
        }

        return false
    }

    /// True when text looks like post-discovery selection or found-path copy, not a user request.
    static func isDiscoveryOrSelectionSummary(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        let selectionPrefixes = [
            "found a likely path",
            "found a likely public profile path",
            "found a likely offer path",
            "found strong",
            "found paths",
            "review the found path",
            "review search results",
            "continue on this found path"
        ]
        if selectionPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        if normalized.hasPrefix("found a likely path through ") {
            return true
        }

        return false
    }

    /// Picks child request text from umbrella turns / thread context (never prefers keyword rails or selection copy).
    static func resolveChildRequestCapturedText(
        umbrellaTurns: [ExchangeTurn],
        umbrellaThread: ExchangeThread,
        requestUserSummary: String? = nil,
        explicitChildRequestText: String? = nil
    ) -> Resolution {
        if let explicit = trimmedNonEmpty(explicitChildRequestText),
           !umbrellaThread.looksLikeInternalSearchQuery(explicit),
           !isDiscoveryOrSelectionSummary(explicit) {
            return Resolution(text: explicit, source: "explicitChildRequestText")
        }

        if let stored = trimmedNonEmpty(umbrellaThread.metadata[ExchangeThread.originalRequesterTextMetadataKey]),
           !umbrellaThread.looksLikeInternalSearchQuery(stored),
           !isDiscoveryOrSelectionSummary(stored) {
            return Resolution(text: stored, source: "originalRequesterText")
        }

        if let captured = latestCapturedRequesterText(from: umbrellaTurns),
           !captured.isEmpty,
           !umbrellaThread.looksLikeInternalSearchQuery(captured),
           !isDiscoveryOrSelectionSummary(captured) {
            return Resolution(text: captured, source: "umbrellaLatestRequestCaptured")
        }

        if let captured = capturedRequesterText(from: umbrellaTurns),
           !captured.isEmpty,
           !umbrellaThread.looksLikeInternalSearchQuery(captured),
           !isDiscoveryOrSelectionSummary(captured) {
            return Resolution(text: captured, source: "umbrellaRequestCaptured")
        }

        let primary = umbrellaThread.primarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty,
           !isLikelyKeywordRail(primary, interpretation: umbrellaThread.interpretation),
           !isDiscoveryOrSelectionSummary(primary) {
            return Resolution(text: primary, source: "primarySearchText")
        }

        if let summary = trimmedNonEmpty(requestUserSummary),
           !umbrellaThread.looksLikeInternalSearchQuery(summary),
           !summary.lowercased().hasPrefix("i understood this as"),
           !isDiscoveryOrSelectionSummary(summary) {
            return Resolution(text: summary, source: "requestUserSummary")
        }

        if let interpretationSummary = trimmedNonEmpty(umbrellaThread.interpretation?.userSummary),
           !interpretationSummary.lowercased().hasPrefix("i understood this as"),
           !umbrellaThread.looksLikeInternalSearchQuery(interpretationSummary),
           !isDiscoveryOrSelectionSummary(interpretationSummary) {
            return Resolution(text: interpretationSummary, source: "interpretationUserSummary")
        }

        if let visible = trimmedNonEmpty(umbrellaThread.visibleSummary),
           !umbrellaThread.looksLikeInternalSearchQuery(visible),
           !isDiscoveryOrSelectionSummary(visible) {
            #if DEBUG
            Swift.print(
                "[ChildSearchQuerySource] source=visibleSummaryFallback " +
                "threadID=\(umbrellaThread.id.uuidString) " +
                "visibleSummary=\(String(visible.prefix(120)))"
            )
            #endif
            return Resolution(text: visible, source: "visibleSummaryFallback")
        }

        if let humanized = humanizedIntentFallback(from: umbrellaThread) {
            return Resolution(text: humanized, source: "humanizedIntent")
        }

        return Resolution(text: "New request", source: "fallbackGeneric")
    }

    /// Maps durable resolution source labels to child search query log tokens.
    static func childSearchQueryLogSource(for resolutionSource: String) -> String {
        switch resolutionSource {
        case "originalRequesterText":
            return "originalRequesterText"
        case "umbrellaLatestRequestCaptured", "umbrellaRequestCaptured", "explicitChildRequestText", "requestUserSummary":
            return "requestCaptured"
        case "primarySearchText":
            return "primarySearchText"
        case "visibleSummaryFallback":
            return "visibleSummaryFallback"
        default:
            return "childRequestText"
        }
    }

    // MARK: - Internals

    private static func displayText(from turn: ExchangeTurn) -> String? {
        let detail = turn.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return detail
        }
        let summary = turn.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private static func humanizedIntentFallback(from thread: ExchangeThread) -> String? {
        let candidates: [String?] = [
            thread.intent.objective,
            thread.intent.title
        ]
        for raw in candidates {
            guard let trimmed = trimmedNonEmpty(raw) else { continue }
            if trimmed.lowercased().hasPrefix("i understood this as") { continue }
            if thread.looksLikeInternalSearchQuery(trimmed) { continue }
            if isDiscoveryOrSelectionSummary(trimmed) { continue }
            return trimmed
        }
        return nil
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
