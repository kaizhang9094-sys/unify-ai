import Foundation

/// Target-term vocabulary and compatibility scoring for semantic proof calibration.
///
/// Vector/object embedding similarity is recall only. Proof requires overlap with
/// LLM/canonical semantic target terms, not broad query scaffolding.
enum ExchangeSemanticTargetProofTerms {
    struct Vocabulary: Sendable, Hashable {
        var targetTerms: Set<String>
        var genericTerms: Set<String>

        var logLabel: String {
            targetTerms.sorted().joined(separator: ",")
        }
    }

    struct Compatibility: Sendable, Hashable {
        var targetOverlap: Int
        var genericOverlap: Int

        var hasMeaningfulTargetOverlap: Bool {
            targetOverlap >= minimumMeaningfulTargetOverlap
        }
    }

    static let minimumMeaningfulTargetOverlap = 1

    static func vocabulary(for target: ExchangeSemanticTarget) -> Vocabulary {
        var targetSeed: [String] = []
        targetSeed.reserveCapacity(24)

        if let objectType = target.objectType {
            targetSeed.append(objectType)
        }
        if let need = target.need, need != target.objectType {
            targetSeed.append(need)
        }
        targetSeed.append(contentsOf: target.semanticConcepts)
        targetSeed.append(contentsOf: target.capabilityTerms)

        for term in target.providerTerms {
            guard !isGenericProviderActorTerm(term) else { continue }
            targetSeed.append(term)
        }

        let targetTerms = tokenSet(from: targetSeed, excludingGeneric: true)
        let genericTerms = genericRecallTerms(for: target)

        return Vocabulary(targetTerms: targetTerms, genericTerms: genericTerms)
    }

    static func compatibility(
        vocabulary: Vocabulary,
        surfaceTokens: Set<String>
    ) -> Compatibility {
        let targetOverlap = vocabulary.targetTerms.intersection(surfaceTokens).count
        let genericOverlap = vocabulary.genericTerms.intersection(surfaceTokens).count
        return Compatibility(targetOverlap: targetOverlap, genericOverlap: genericOverlap)
    }

    static func offerSurfaceTokens(
        offer: ExchangeOffer,
        document: ExchangeRetrievalDocument
    ) -> Set<String> {
        var values: [String] = []
        values.append(offer.title)
        if let summary = offer.summary { values.append(summary) }
        if let category = offer.category { values.append(category) }
        values.append(contentsOf: offer.tags)
        values.append(contentsOf: offer.regionTags)
        values.append(contentsOf: offer.semantic.searchableTerms)
        if let note = offer.semantic.notes { values.append(note) }

        values.append(document.title)
        if let summary = document.summary { values.append(summary) }
        if let category = document.category { values.append(category) }
        values.append(contentsOf: document.tags)
        values.append(document.lexicalText)
        values.append(document.semanticText)
        if !document.primaryText.isEmpty { values.append(document.primaryText) }

        return tokenSet(from: values, excludingGeneric: false)
    }

    static func profileSurfaceTokens(
        document: ExchangeRetrievalDocument,
        publicProfile: ExchangePublicNodeProfile?
    ) -> Set<String> {
        var values: [String] = []
        if let profile = publicProfile {
            if let displayName = profile.displayName { values.append(displayName) }
            if let headline = profile.headline { values.append(headline) }
            if let summary = profile.summary { values.append(summary) }
            values.append(contentsOf: profile.offers)
            values.append(contentsOf: profile.openTo)
            values.append(contentsOf: profile.activityTags)
            values.append(contentsOf: profile.interests)
            values.append(contentsOf: profile.semantic.searchableTerms)
        }

        values.append(document.title)
        values.append(document.lexicalText)
        values.append(document.semanticText)
        values.append(contentsOf: document.tags)

        return tokenSet(from: values, excludingGeneric: false)
    }

    // MARK: - Token helpers

    private static func genericRecallTerms(for target: ExchangeSemanticTarget) -> Set<String> {
        var values: [String] = []
        values.append(contentsOf: structuralGenericTerms)
        if let raw = target.carrier.rawUserText { values.append(raw) }
        if let semantic = target.carrier.semanticText { values.append(semantic) }
        return tokenSet(from: values, excludingGeneric: false)
    }

    private static func tokenSet(from values: [String], excludingGeneric: Bool) -> Set<String> {
        var tokens = Set<String>()
        tokens.reserveCapacity(values.count * 2)

        for value in values {
            for token in tokenize(value) {
                if excludingGeneric, isStructuralGenericToken(token) { continue }
                if excludingGeneric, isGenericProviderActorTerm(token) { continue }
                tokens.insert(token)
            }
        }
        return tokens
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .split { character in
                !(character.isLetter || character.isNumber)
            }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private static func isGenericProviderActorTerm(_ raw: String) -> Bool {
        let tokens = tokenize(raw)
        guard tokens.count == 1 else { return false }
        return genericProviderActorTerms.contains(tokens[0])
    }

    private static func isStructuralGenericToken(_ token: String) -> Bool {
        structuralGenericTerms.contains(token)
    }

    /// Broad recall / scaffolding tokens that must not satisfy semantic proof.
    private static let structuralGenericTerms: Set<String> = [
        "a", "an", "the", "and", "or", "for", "to", "at", "in", "on", "by", "from", "with",
        "find", "me", "my", "i", "we", "you", "someone", "somebody", "anyone", "person", "people",
        "provider", "providers", "seller", "sellers", "vendor", "vendors", "business", "company",
        "service", "services", "general", "hire", "hired", "hiring", "buy", "buying", "get",
        "getting", "need", "needs", "needed", "want", "wants", "wanted", "looking", "look",
        "search", "searching", "tomorrow", "today", "tonight", "weekend", "week", "under", "over",
        "near", "nearby", "local", "available", "availability", "around", "within", "budget",
        "price", "cost", "cheap", "best", "good", "great", "please", "help", "can", "could",
        "would", "should", "who", "what", "where", "when", "how", "much", "any", "some",
        "offer", "offers", "listing", "listings", "item", "items", "product", "products",
        "professional", "contractor", "contractors", "expert", "experts", "specialist", "specialists",
    ]

    /// Provider-rail actor words kept out of target proof terms unless carried by objectType/need/concepts.
    private static let genericProviderActorTerms: Set<String> = [
        "provider", "providers", "seller", "sellers", "vendor", "vendors", "business", "company",
        "professional", "contractor", "contractors", "someone", "somebody", "person", "people",
        "expert", "experts", "specialist", "specialists", "agency", "agencies",
    ]
}
