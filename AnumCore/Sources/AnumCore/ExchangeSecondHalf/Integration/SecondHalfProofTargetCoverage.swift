import Foundation

/// Deterministic normalized-target coverage checks for automatic second-half proof gating.
enum SecondHalfProofTargetCoverage: Sendable {
    struct Result: Sendable, Equatable {
        var covered: Bool
        var normalizedTarget: String?
        var concreteTargetTokens: [String]

        init(covered: Bool, normalizedTarget: String? = nil, concreteTargetTokens: [String] = []) {
            self.covered = covered
            self.normalizedTarget = normalizedTarget
            self.concreteTargetTokens = concreteTargetTokens
        }
    }

    private static let genericActionTokens: Set<String> = [
        "repair", "fix", "service", "help", "work", "job", "provider", "seller", "person", "someone",
        "hire", "buy", "sell", "deliver",
    ]

    private static let genericActorTokens: Set<String> = [
        "person", "people", "someone", "somebody", "anyone", "anybody", "individual", "individuals",
        "human", "humans", "whoever", "provider", "providers", "seller", "sellers",
    ]

    static func normalizedRetrievalTarget(from thread: ExchangeThread) -> String? {
        if let searchIntent = thread.facets?.searchIntent,
           let queryObject = ExchangeOfferObjectLane.queryObjectText(from: searchIntent) {
            return trimmed(queryObject)
        }

        let semanticTarget = ExchangeSemanticTarget.from(thread: thread)
        if let semanticText = trimmed(semanticTarget.carrier.semanticText) {
            return semanticText
        }
        if let need = trimmed(semanticTarget.need) {
            return need
        }
        if let concept = semanticTarget.semanticConcepts.compactMap({ trimmed($0) }).first {
            return concept
        }
        if let english = trimmed(semanticTarget.carrier.canonicalEnglishSearchText) {
            return english
        }
        return trimmed(semanticTarget.carrier.rawUserText)
    }

    static func offerSurfaceTokens(from offer: ExchangeOffer) -> Set<String> {
        var values: [String] = []
        values.append(offer.title)
        if let summary = offer.summary { values.append(summary) }
        if let category = offer.category { values.append(category) }
        values.append(contentsOf: offer.tags)
        values.append(contentsOf: offer.regionTags)
        values.append(contentsOf: offer.semantic.searchableTerms)
        if let note = offer.semantic.notes { values.append(note) }
        values.append(contentsOf: offer.semantic.serviceKinds)
        return tokenSet(from: values)
    }

    static func coversNormalizedTarget(
        policyThread: ExchangeThread,
        proof: ExchangeCandidateSemanticProof,
        selectedOfferID: String,
        offerSurfaceTokens: Set<String>?
    ) -> Result {
        let normalizedTarget = normalizedRetrievalTarget(from: policyThread)
        let concreteTokens = concreteTargetTokens(from: normalizedTarget)

        guard let normalizedTarget, !normalizedTarget.isEmpty else {
            return Result(covered: true, normalizedTarget: normalizedTarget, concreteTargetTokens: concreteTokens)
        }

        if concreteTokens.isEmpty {
            let fallbackTokens = tokenize(normalizedTarget).filter { !isGenericActionOrActorToken($0) }
            if fallbackTokens.isEmpty {
                return Result(covered: true, normalizedTarget: normalizedTarget, concreteTargetTokens: [])
            }
            let covered = tokenOverlapEvidence(
                requiredTokens: fallbackTokens,
                hadActionAndConcrete: false,
                offerSurfaceTokens: offerSurfaceTokens,
                proof: proof,
                selectedOfferID: selectedOfferID
            )
            return Result(covered: covered, normalizedTarget: normalizedTarget, concreteTargetTokens: fallbackTokens)
        }

        let allTokens = tokenize(normalizedTarget)
        let hadActionAndConcrete = allTokens.contains(where: isGenericActionOrActorToken(_:))
            && !concreteTokens.isEmpty

        let covered = tokenOverlapEvidence(
            requiredTokens: concreteTokens,
            hadActionAndConcrete: hadActionAndConcrete,
            offerSurfaceTokens: offerSurfaceTokens,
            proof: proof,
            selectedOfferID: selectedOfferID
        )
        return Result(covered: covered, normalizedTarget: normalizedTarget, concreteTargetTokens: concreteTokens)
    }

    static func concreteTargetTokens(from normalizedTarget: String?) -> [String] {
        guard let normalizedTarget, !normalizedTarget.isEmpty else { return [] }
        let tokens = tokenize(normalizedTarget)
        let concrete = tokens.filter { !isGenericActionOrActorToken($0) }
        return orderedUnique(concrete)
    }

    private static func tokenOverlapEvidence(
        requiredTokens: [String],
        hadActionAndConcrete: Bool,
        offerSurfaceTokens: Set<String>?,
        proof: ExchangeCandidateSemanticProof,
        selectedOfferID: String
    ) -> Bool {
        guard !requiredTokens.isEmpty else { return true }

        let required = Set(requiredTokens)

        if let offerSurfaceTokens, !offerSurfaceTokens.isEmpty {
            if requiredTokensMatchSurface(required, offerSurfaceTokens) {
                return true
            }
            if hadActionAndConcrete {
                return false
            }
        }

        guard let attachment = primaryOfferAttachment(proof: proof, selectedOfferID: selectedOfferID) else {
            return false
        }

        if hadActionAndConcrete {
            return attachment.targetOverlap >= 2
                && attachment.targetOverlap > attachment.genericOverlap
        }

        let requiredCount = requiredTokens.count
        if requiredCount >= 2 {
            return attachment.targetOverlap >= requiredCount
                && attachment.targetOverlap > attachment.genericOverlap
        }

        return attachment.targetOverlap >= 1
            && attachment.targetOverlap > attachment.genericOverlap
            && attachment.genericOverlap == 0
    }

    static func primaryOfferAttachment(
        proof: ExchangeCandidateSemanticProof,
        selectedOfferID: String
    ) -> ExchangeCandidateSemanticProof.OfferAttachment? {
        if let direct = proof.offerAttachments.first(where: { $0.offerID == selectedOfferID }) {
            return direct
        }
        if let primary = proof.summary.primaryOfferID,
           let attachment = proof.offerAttachments.first(where: { $0.offerID == primary }) {
            return attachment
        }
        return proof.offerAttachments.first
    }

    private static func requiredTokensMatchSurface(
        _ required: Set<String>,
        _ surfaceTokens: Set<String>
    ) -> Bool {
        for token in required {
            if !expandedTokenFamilies(for: token).isDisjoint(with: surfaceTokens) {
                return true
            }
        }
        return false
    }

    /// Lightweight role/service equivalence for concrete target coverage (e.g. cleaner ↔ cleaning).
    private static func expandedTokenFamilies(for token: String) -> Set<String> {
        var family: Set<String> = [token]

        if token.hasSuffix("er"), token.count > 4 {
            let stem = String(token.dropLast(2))
            if stem.count >= 3 {
                family.insert(stem)
                family.insert(stem + "ing")
            }
        }

        if token.hasSuffix("ing"), token.count > 5 {
            let stem = String(token.dropLast(3))
            if stem.count >= 3 {
                family.insert(stem)
                family.insert(stem + "er")
            }
        }

        return Set(family.filter { $0.count >= 2 })
    }

    private static func isGenericActionOrActorToken(_ token: String) -> Bool {
        genericActionTokens.contains(token) || genericActorTokens.contains(token)
    }

    private static func tokenSet(from values: [String]) -> Set<String> {
        var tokens = Set<String>()
        for value in values {
            for token in tokenize(value) {
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

    private static func orderedUnique(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for token in tokens where seen.insert(token).inserted {
            output.append(token)
        }
        return output
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
