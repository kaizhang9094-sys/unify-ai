import Foundation

/// Production source-of-truth for parsing and normalizing numeric budget caps from search intent fields.
public enum ExchangeBudgetConstraintExtractor {
    private static let budgetCueWords = [
        "budget", "price", "cost", "under", "max", "$", "less than", "up to", "≤", "<="
    ]

    /// Extracts the highest-priority budget cap from canonical search intent fields.
    public static func extractBudgetMax(
        from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Int? {
        if let fromCommercial = budgetMaxFromCommercialConstraints(searchIntent.commercialConstraints) {
            return fromCommercial
        }
        if let fromHard = budgetMaxFromHardConstraints(searchIntent.hardConstraints) {
            return fromHard
        }
        if let english = searchIntent.canonicalEnglishSearchText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !english.isEmpty {
            return parseBudgetAmount(from: english, requireBudgetCue: true)
        }
        return nil
    }

    /// Returns a budget phrase suitable for `StructuredCommercialConstraint.value` when a numeric cap is parseable.
    public static func validatedBudgetConstraintValue(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard parseBudgetAmount(from: trimmed, requireBudgetCue: false) != nil else {
            return nil
        }
        return trimmed
    }

    /// Adds a `.budget` commercial constraint when inferable from hard constraints or English carrier text.
    public static func enrichCommercialConstraintsWithBudget(
        commercialConstraints: [ExchangeIntentFacets.StructuredCommercialConstraint],
        hardConstraints: [ExchangeIntent.Constraint],
        canonicalEnglishSearchText: String?
    ) -> [ExchangeIntentFacets.StructuredCommercialConstraint] {
        guard !commercialConstraints.contains(where: { $0.kind == .budget }) else {
            return commercialConstraints
        }

        for constraint in hardConstraints {
            let joined = "\(constraint.key) \(constraint.value)"
            guard containsBudgetCue(joined.lowercased()) else { continue }
            guard let phrase = budgetConstraintPhrase(from: joined, requireBudgetCue: true) else { continue }
            return commercialConstraints + [
                .init(
                    kind: .budget,
                    key: "budget",
                    value: phrase,
                    isHard: constraint.isHardConstraint
                )
            ]
        }

        if let english = canonicalEnglishSearchText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !english.isEmpty,
           let phrase = budgetConstraintPhrase(from: english, requireBudgetCue: true) {
            let isHard = hardConstraints.contains {
                $0.isHardConstraint && english.localizedCaseInsensitiveContains($0.value)
            }
            return commercialConstraints + [
                .init(
                    kind: .budget,
                    key: "budget",
                    value: phrase,
                    isHard: isHard
                )
            ]
        }

        return commercialConstraints
    }

    /// Parses a budget cap from free text using cue-proximity rules (never concatenates all digits in the string).
    public static func parseBudgetAmount(from text: String, requireBudgetCue: Bool) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if requireBudgetCue, !containsBudgetCue(lowered) {
            return nil
        }

        if let nearCue = firstBudgetAmountNearCue(in: trimmed) {
            return nearCue
        }

        if !requireBudgetCue {
            return standaloneBudgetAmount(in: trimmed)
        }

        return nil
    }

    public static func containsBudgetCue(_ loweredText: String) -> Bool {
        budgetCueWords.contains { loweredText.contains($0) }
    }

    private static func budgetConstraintPhrase(from text: String, requireBudgetCue: Bool) -> String? {
        guard parseBudgetAmount(from: text, requireBudgetCue: requireBudgetCue) != nil else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let matched = firstBudgetPhraseNearCue(in: trimmed) {
            return matched
        }
        if !requireBudgetCue, let standalone = standaloneBudgetPhrase(in: trimmed) {
            return standalone
        }
        return trimmed
    }

    private static func budgetMaxFromCommercialConstraints(
        _ constraints: [ExchangeIntentFacets.StructuredCommercialConstraint]
    ) -> Int? {
        for constraint in constraints where constraint.kind == .budget {
            if let value = parseBudgetAmount(from: constraint.value, requireBudgetCue: false) {
                return value
            }
            let keyValue = "\(constraint.key) \(constraint.value)"
            if let value = parseBudgetAmount(from: keyValue, requireBudgetCue: false) {
                return value
            }
        }
        for constraint in constraints {
            let keyValue = "\(constraint.key) \(constraint.value)".lowercased()
            guard containsBudgetCue(keyValue) else { continue }
            if let value = parseBudgetAmount(from: keyValue, requireBudgetCue: true) {
                return value
            }
        }
        return nil
    }

    private static func budgetMaxFromHardConstraints(
        _ constraints: [ExchangeIntent.Constraint]
    ) -> Int? {
        for constraint in constraints {
            let joined = "\(constraint.key) \(constraint.value)".lowercased()
            guard containsBudgetCue(joined) else { continue }
            if let value = parseBudgetAmount(from: joined, requireBudgetCue: true) {
                return value
            }
        }
        return nil
    }

    private static func firstBudgetAmountNearCue(in text: String) -> Int? {
        guard let capture = firstRegexCapture(pattern: budgetAmountPatterns, in: text) else {
            return nil
        }
        return normalizedBudgetInt(from: capture)
    }

    private static func firstBudgetPhraseNearCue(in text: String) -> String? {
        firstRegexMatchedPhrase(pattern: budgetAmountPatterns, in: text)
    }

    private static let budgetAmountPatterns = [
        #"(?i)(?:under|less\s+than|up\s+to|maximum|max(?:imum)?|budget(?:\s+is)?|price|cost)\s*(?:[\$£€]|usd\s*)?(\d[\d,]*(?:\.\d+)?)"#,
        #"(?i)(?:<=|≤)\s*(?:[\$£€])?(\d[\d,]*(?:\.\d+)?)"#,
        #"\$\s*(\d[\d,]*(?:\.\d+)?)"#
    ]

    private static func standaloneBudgetAmount(in text: String) -> Int? {
        guard let capture = firstRegexCapture(
            pattern: [#"^\s*(?:[\$£€]\s*)?(\d[\d,]*(?:\.\d+)?)\s*(?:dollars|usd)?\s*$"#],
            in: text,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        return normalizedBudgetInt(from: capture)
    }

    private static func standaloneBudgetPhrase(in text: String) -> String? {
        firstRegexMatchedPhrase(
            pattern: [#"^\s*((?:[\$£€]\s*)?\d[\d,]*(?:\.\d+)?)\s*(?:dollars|usd)?\s*$"#],
            in: text,
            options: [.caseInsensitive]
        )
    }

    private static func firstRegexCapture(
        pattern patterns: [String],
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = compileRegex(patterns: patterns, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func firstRegexMatchedPhrase(
        pattern patterns: [String],
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = compileRegex(patterns: patterns, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compileRegex(
        patterns: [String],
        options: NSRegularExpression.Options
    ) -> NSRegularExpression? {
        let combined = patterns.map { "(?:\($0))" }.joined(separator: "|")
        return try? NSRegularExpression(pattern: combined, options: options)
    }

    private static func normalizedBudgetInt(from capture: String) -> Int? {
        let cleaned = capture
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let whole = cleaned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? cleaned
        guard let value = Int(whole), value > 0 else {
            return nil
        }
        return value
    }
}
