import Foundation

/// Decides when a new discovery/search request should fork a fresh umbrella thread
/// instead of reusing an existing umbrella or terminal search workbench.
enum ExchangeUmbrellaSearchReusePolicy: Sendable {

    static func shouldForkNewUmbrellaSearch(
        existing: ExchangeThread,
        request: ExchangeInterpreter.InterpretedRequest
    ) -> Bool {
        guard request.shouldDiscover else { return false }
        guard isReuseCandidateThread(existing) else { return false }
        return isMateriallyDifferent(existing: existing, request: request)
    }

    private static func isReuseCandidateThread(_ thread: ExchangeThread) -> Bool {
        if thread.threadRole == .umbrellaSearch { return true }
        switch thread.state {
        case .noViableMatch, .matchCandidatesWeak:
            return true
        default:
            return false
        }
    }

    private static func isMateriallyDifferent(
        existing: ExchangeThread,
        request: ExchangeInterpreter.InterpretedRequest
    ) -> Bool {
        if existing.intent.queryIntentClass != request.intent.queryIntentClass {
            return true
        }

        let existingObjective = normalizedTokenSet(existing.intent.objective)
        let newObjective = normalizedTokenSet(request.intent.objective)
        if !existingObjective.isEmpty,
           !newObjective.isEmpty,
           existingObjective != newObjective {
            return true
        }

        let existingNeed = normalizedTokenSet(existing.intent.title)
        let newNeed = normalizedTokenSet(request.intent.title)
        if !existingNeed.isEmpty,
           !newNeed.isEmpty,
           existingNeed != newNeed {
            return true
        }

        let existingTarget = normalizedTokenSet(existing.intent.targetDescription ?? "")
        let newTarget = normalizedTokenSet(request.intent.targetDescription ?? "")
        if !existingTarget.isEmpty,
           !newTarget.isEmpty,
           existingTarget != newTarget {
            return true
        }

        let oldKeywords = normalizedKeywordSet(existing.interpretation?.discoveryKeywords ?? [])
        let newKeywords = normalizedKeywordSet(request.discoveryKeywords)
        if !oldKeywords.isEmpty,
           !newKeywords.isEmpty {
            let overlap = oldKeywords.intersection(newKeywords)
            let union = oldKeywords.union(newKeywords)
            if union.count >= 2 {
                let overlapRatio = Double(overlap.count) / Double(union.count)
                if overlapRatio < 0.34 {
                    return true
                }
            } else if oldKeywords != newKeywords {
                return true
            }
        }

        return false
    }

    private static func normalizedKeywordSet(_ keywords: [String]) -> Set<String> {
        Set(
            keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private static func normalizedTokenSet(_ text: String) -> Set<String> {
        Set(
            text
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { token in
                    token.count >= 2 && !stopTokens.contains(token)
                }
        )
    }

    private static let stopTokens: Set<String> = [
        "a", "an", "the", "me", "my", "i", "to", "for", "and", "or", "in", "on", "at", "of",
        "find", "get", "want", "need", "looking", "search", "buy", "someone", "somebody"
    ]
}
