import Foundation

/// Conservative negative guard for generic human actor nouns (`person`, `someone`, …).
///
/// Prevents actor referents from becoming retrieval object carriers or semantic-proof objects.
/// Does not infer or split open-world commercial objects from need phrases.
public enum ExchangeActorNounNormalization: Sendable {
    public struct Result: Sendable, Equatable {
        public var searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
        public var applied: Bool
        public var rawObject: String?
        public var retrievalObjectText: String?

        public init(
            searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
            applied: Bool,
            rawObject: String? = nil,
            retrievalObjectText: String? = nil
        ) {
            self.searchIntent = searchIntent
            self.applied = applied
            self.rawObject = rawObject
            self.retrievalObjectText = retrievalObjectText
        }
    }

    /// Generic human referents — not provider roles like `cleaner` or `seller`.
    private static let genericActorNouns: Set<String> = [
        "person", "people", "someone", "somebody", "anyone", "anybody",
        "individual", "individuals", "human", "humans", "whoever",
    ]

    private static let tokenPunctuation = CharacterSet.punctuationCharacters

    public static func isGenericActorNoun(_ objectType: String?) -> Bool {
        guard let token = normalizedToken(objectType) else { return false }
        return genericActorNouns.contains(token)
    }

    /// Canonical retrieval object carrier. Never returns a generic actor noun.
    public static func resolvedRetrievalObjectText(
        from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> String? {
        if let object = trimmedToken(searchIntent.objectType),
           !isGenericActorNoun(object) {
            return sanitizedPhrase(object)
        }

        guard requiresActorNounGuard(from: searchIntent) else {
            return nil
        }

        if let concept = bestNonGenericSemanticConcept(from: searchIntent.semanticConcepts) {
            return sanitizedPhrase(concept)
        }

        if let english = trimmedToken(searchIntent.canonicalEnglishSearchText),
           let meaningful = meaningfulContentPhrase(from: english) {
            return sanitizedPhrase(meaningful)
        }

        if let raw = trimmedToken(searchIntent.rawUserText),
           let meaningful = meaningfulContentPhrase(from: raw) {
            return sanitizedPhrase(meaningful)
        }

        return nil
    }

    public static func normalize(
        _ searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        source: String = "liveInterpretation"
    ) -> Result {
        guard isGenericActorNoun(searchIntent.objectType) else {
            return Result(searchIntent: searchIntent, applied: false)
        }

        guard let rawObject = trimmedToken(searchIntent.objectType) else {
            return Result(searchIntent: searchIntent, applied: false)
        }

        var copy = searchIntent
        copy.objectType = promotedConcreteObjectType(from: searchIntent)
        copy.semanticConcepts = sanitizedSemanticConcepts(
            original: searchIntent.semanticConcepts,
            rawObject: rawObject
        )

        let retrievalObjectText = resolvedRetrievalObjectText(from: copy)

        logNormalization(
            rawObject: rawObject,
            objectTypeAfter: copy.objectType,
            retrievalObjectText: retrievalObjectText,
            applied: true,
            source: source
        )

        return Result(
            searchIntent: copy,
            applied: true,
            rawObject: rawObject,
            retrievalObjectText: retrievalObjectText
        )
    }

    // MARK: - Semantic concept hygiene

    static func sanitizedSemanticConcepts(
        original: [String],
        rawObject: String
    ) -> [String] {
        let rawObjectLower = rawObject.lowercased()
        var seen = Set<String>()
        var output: [String] = []

        for concept in original {
            guard let text = trimmedToken(concept) else { continue }
            let lower = text.lowercased()
            if lower == rawObjectLower {
                continue
            }
            if isGenericActorNoun(text) {
                continue
            }
            if seen.contains(lower) {
                continue
            }
            seen.insert(lower)
            output.append(text)
        }
        return output
    }

    static func bestNonGenericSemanticConcept(from concepts: [String]) -> String? {
        let candidates = concepts
            .compactMap { trimmedToken($0) }
            .filter { !isGenericActorNoun($0) }

        guard !candidates.isEmpty else { return nil }

        return candidates.max(by: { semanticConceptRetrievalScore($0) < semanticConceptRetrievalScore($1) })
    }

    private static func semanticConceptRetrievalScore(_ phrase: String) -> Int {
        let tokens = tokenize(phrase)
        guard !tokens.isEmpty else { return Int.min }

        var score = tokens.count * 10
        if tokens.count >= 2 {
            score += 100
        }
        if tokens.count == 1, tokens[0] == "provider" {
            score -= 50
        }
        return score
    }

    /// Promote a single-token concrete object only when it was already extracted elsewhere.
    private static func promotedConcreteObjectType(
        from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> String? {
        let singleTokenConcepts = searchIntent.semanticConcepts
            .compactMap { trimmedToken($0) }
            .filter { concept in
                guard !isGenericActorNoun(concept) else { return false }
                return tokenize(concept).count == 1
            }

        let multiTokenConcepts = searchIntent.semanticConcepts
            .compactMap { trimmedToken($0) }
            .filter { tokenize($0).count >= 2 }

        guard multiTokenConcepts.isEmpty else { return nil }
        guard singleTokenConcepts.count == 1 else { return nil }

        let candidate = singleTokenConcepts[0]
        guard normalizedToken(candidate) != "provider" else { return nil }
        return candidate
    }

    private static func requiresActorNounGuard(
        from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        if isGenericActorNoun(searchIntent.objectType) {
            return true
        }
        guard searchIntent.objectType == nil else {
            return false
        }
        return searchIntent.semanticConcepts.contains { concept in
            guard let text = trimmedToken(concept), !isGenericActorNoun(text) else {
                return false
            }
            return tokenize(text).count >= 2
        }
    }

    private static let queryScaffoldingTokens: Set<String> = [
        "find", "me", "a", "an", "the", "who", "to", "for", "with", "some", "please", "need", "want",
        "looking", "look", "help", "get", "can", "you", "i", "am", "is", "are", "my", "in", "on", "at",
    ]

    private static func meaningfulContentTokens(from phrase: String) -> [String] {
        tokenize(phrase).filter { token in
            !queryScaffoldingTokens.contains(token) && !isGenericActorNoun(token)
        }
    }

    private static func meaningfulContentPhrase(from phrase: String) -> String? {
        let tokens = meaningfulContentTokens(from: phrase)
        guard !tokens.isEmpty else { return nil }
        return tokens.joined(separator: " ")
    }

    private static func sanitizedPhrase(_ phrase: String) -> String? {
        guard let trimmed = trimmedToken(phrase) else { return nil }
        let stripped = trimmed.trimmingCharacters(in: tokenPunctuation)
        return stripped.isEmpty ? nil : stripped
    }

    private static func tokenize(_ phrase: String) -> [String] {
        phrase
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .compactMap { normalizedToken($0) }
    }

    private static func normalizedToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let stripped = trimmed.trimmingCharacters(in: tokenPunctuation)
        return stripped.isEmpty ? nil : stripped.lowercased()
    }

    private static func trimmedToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func logNormalization(
        rawObject: String,
        objectTypeAfter: String?,
        retrievalObjectText: String?,
        applied: Bool,
        source: String
    ) {
        let retrievalLabel = retrievalObjectText ?? "nil"
        let objectAfterLabel = objectTypeAfter ?? "nil"
        let message =
            "[ActorNounNormalization] rawObject=\(rawObject) objectTypeAfter=\(objectAfterLabel) " +
            "retrievalObjectText=\(retrievalLabel) applied=\(applied) source=\(source)"
        #if DEBUG
        print(message)
        #endif
    }
}
