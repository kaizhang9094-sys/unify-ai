import Foundation

/// Task / need phrases extracted from canonical search intent for retrieval ranking (not hard gates).
enum ExchangeCanonicalSearchIntentTaskPhrases: Sendable {
    static let defaultMaxPhrases = 2

    /// Top task-like phrases: semantic concepts first, then broad recall (deduped).
    static func topTaskPhrases(
        from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        maxCount: Int = defaultMaxPhrases
    ) -> [String] {
        let capped = max(0, min(maxCount, defaultMaxPhrases))
        guard capped > 0 else { return [] }

        var selected: [String] = []
        var seen = Set<String>()

        for phrase in orderedCandidates(from: searchIntent) {
            guard isTaskLikePhrase(phrase, searchIntent: searchIntent) else { continue }
            let key = normalizedKey(phrase)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            selected.append(presentablePhrase(phrase))
            if selected.count >= capped { break }
        }

        return selected
    }

    /// Semantic task phrases not already present in broad recall (directory tag seeding).
    static func directoryTagsMissingFromBroadRecall(
        from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> [String] {
        let broadKeys = Set(
            searchIntent.broadRecallTokens.map { normalizedKey($0) }.filter { !$0.isEmpty }
        )
        return topTaskPhrases(from: searchIntent).filter { !broadKeys.contains(normalizedKey($0)) }
    }

    /// Provider-facing clarification for a single task/need phrase (gap reducer).
    static func providerServiceGapQuestion(
        taskPhrase: String,
        domainCategory: ExchangeIntentFacets.DomainCategory
    ) -> String {
        let phrase = presentablePhrase(taskPhrase)
        let lower = phrase.lowercased()
        switch domainCategory {
        case .professionalService:
            if lower.contains("practice")
                || lower.contains("lesson")
                || lower.contains("training")
                || lower.contains("tutor") {
                return "Do you offer \(phrase)?"
            }
            return "Do you provide \(phrase)?"
        case .homeService, .product, .general, .realEstate:
            return "Do you handle \(phraseForHandleVerb(phrase))?"
        }
    }

    /// Inserts the primary task phrase into a broad query sentence before place / closing punctuation.
    static func taskClauseForBroadQuery(
        phrases: [String],
        domainCategory: ExchangeIntentFacets.DomainCategory
    ) -> String {
        guard let primary = phrases.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !primary.isEmpty else {
            return ""
        }

        switch domainCategory {
        case .homeService, .professionalService, .product, .general:
            return " for \(primary)"
        case .realEstate:
            return ""
        }
    }

    // MARK: - Candidates

    private static func orderedCandidates(
        from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> [String] {
        var raw: [String] = []
        raw.append(contentsOf: searchIntent.semanticConcepts)
        raw.append(contentsOf: searchIntent.broadRecallTokens)

        var seen = Set<String>()
        var ordered: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = normalizedKey(trimmed)
            guard seen.insert(key).inserted else { continue }
            ordered.append(trimmed)
        }

        return ordered
    }

    // MARK: - Filters

    private static func isTaskLikePhrase(
        _ raw: String,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isClauseJoinedFragment(trimmed) else { return false }

        let words = wordCount(trimmed)
        guard words <= 5 else { return false }
        if words == 0 { return false }
        if words == 1, !isUsefulSingleWordTask(trimmed, searchIntent: searchIntent) { return false }

        guard !isSimilarToObjectType(trimmed, objectType: searchIntent.objectType) else { return false }
        guard !isPlacePhrase(trimmed, searchIntent: searchIntent) else { return false }
        guard !isTimePhrase(trimmed, searchIntent: searchIntent) else { return false }
        guard !isCommercialOrBudgetPhrase(trimmed, searchIntent: searchIntent) else { return false }

        return true
    }

    private static func isUsefulSingleWordTask(
        _ phrase: String,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        let lower = phrase.lowercased()
        guard lower.count >= 5 else { return false }
        guard !isTimePhrase(phrase, searchIntent: searchIntent) else { return false }
        guard !isCommercialOrBudgetPhrase(phrase, searchIntent: searchIntent) else { return false }
        return true
    }

    private static func isSimilarToObjectType(_ phrase: String, objectType: String?) -> Bool {
        let objectTrimmed = objectType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !objectTrimmed.isEmpty else { return false }
        let phraseKey = normalizedKey(phrase)
        let objectKey = normalizedKey(objectTrimmed)
        guard !phraseKey.isEmpty, !objectKey.isEmpty else { return false }
        if phraseKey == objectKey { return true }

        let phraseTokens = Set(tokenize(phraseKey))
        let objectTokens = Set(tokenize(objectKey))
        guard !phraseTokens.isEmpty, !objectTokens.isEmpty else { return false }

        if phraseTokens == objectTokens { return true }
        if phraseTokens.isSubset(of: objectTokens), phraseTokens.count <= objectTokens.count { return true }
        return false
    }

    private static func isPlacePhrase(
        _ phrase: String,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        let phraseKey = normalizedKey(phrase)
        guard !phraseKey.isEmpty else { return false }

        let phraseTokens = tokenize(phraseKey)

        for place in searchIntent.places {
            var shards: [String] = [place.normalizedText]
            shards.append(contentsOf: place.aliases)
            if let id = place.canonicalID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                shards.append(id)
            }

            for shard in shards {
                let placeKey = normalizedKey(shard)
                guard !placeKey.isEmpty else { continue }

                if phraseKey == placeKey {
                    return true
                }

                let placeTokens = tokenize(placeKey)
                if !phraseTokens.isEmpty,
                   !placeTokens.isEmpty,
                   phraseTokens.allSatisfy({ placeTokens.contains($0) }),
                   wordCount(phrase) <= 3 {
                    return true
                }
            }
        }

        return false
    }

    private static func isTimePhrase(
        _ phrase: String,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        let lower = phrase.lowercased()
        if matchesTimeNeedle(lower) { return true }

        for constraint in searchIntent.timeConstraints {
            let text = constraint.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !text.isEmpty else { continue }
            if lower == text || lower.contains(text) || text.contains(lower) { return true }
        }
        return false
    }

    private static func isCommercialOrBudgetPhrase(
        _ phrase: String,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        let lower = phrase.lowercased()
        if matchesCommercialNeedle(lower) { return true }

        for constraint in searchIntent.commercialConstraints {
            let value = constraint.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = constraint.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !value.isEmpty, (lower == value || lower.contains(value)) { return true }
            if !key.isEmpty, lower == key { return true }
        }
        return false
    }

    private static func matchesTimeNeedle(_ lower: String) -> Bool {
        let exact: Set<String> = [
            "today", "tomorrow", "tonight", "morning", "afternoon", "evening",
            "weekend", "weekday", "weekdays"
        ]
        if exact.contains(lower) { return true }

        let substrings = [
            "next week", "this week", " am", " pm", "a.m.", "p.m.",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "下周", "明天", "今天", "今晚", "上午", "下午"
        ]
        if substrings.contains(where: { lower.contains($0) }) { return true }

        if lower.range(of: #"\b\d{1,2}(:\d{2})?\s*(am|pm)\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\b\d{4}[-/]\d{1,2}\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func matchesCommercialNeedle(_ lower: String) -> Bool {
        if lower.range(of: #"\$\s*\d"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"\b\d+\s*(k|m|usd|cad)\b"#, options: .regularExpression) != nil { return true }

        let needles = [
            "under ", "over ", "budget", "dollars", "price range", "financing", "mortgage",
            "vendor take", "vtb", "cheap", "expensive", "affordable", "quote", "payment"
        ]
        return needles.contains { lower.contains($0) }
    }

    private static func isClauseJoinedFragment(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.contains(", and ") { return true }
        if lower.contains(" and ") && lower.contains(",") { return true }
        if lower.contains(" who ") || lower.contains(" with ") || lower.contains(" offers ") { return true }
        let words = wordCount(value)
        return words > 5 && (lower.contains(" and ") || lower.contains(","))
    }

    // MARK: - Formatting

    private static func phraseForHandleVerb(_ phrase: String) -> String {
        let parts = phrase.split(separator: " ").map(String.init)
        guard let last = parts.last else { return phrase }
        let head = parts.dropLast()
        let tail = pluralizedServiceTail(last)
        guard !head.isEmpty else { return tail }
        return (head + [tail]).joined(separator: " ")
    }

    private static func pluralizedServiceTail(_ word: String) -> String {
        let lower = word.lowercased()
        if lower.hasSuffix("s") { return word }
        if lower.hasSuffix("repair") || lower.hasSuffix("remodel") || lower.hasSuffix("install") {
            return word + "s"
        }
        return word
    }

    private static func presentablePhrase(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(trimmed.prefix(96))
    }

    private static func normalizedKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func wordCount(_ raw: String) -> Int {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .count
    }

    private static func tokenize(_ raw: String) -> [String] {
        raw
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
