import Foundation

/// Provenance and lane control for concrete commercial offer-object retrieval.
///
/// Semantic matching is embedding-to-embedding only (`queryObjectText` ↔ `offer_object` doc).
/// This helper must not tokenize raw query meaning, maintain lexical blocklists, or encode product taxonomies.
public enum ExchangeOfferObjectLane: Sendable {
    /// Minimum cosine similarity required before an `offer_object` doc may attach an offer.
    public static let minimumObjectEvidenceScore: Double = 0.20

    /// Reserved for future near-tie co-proof; 4E proves only the top sibling scorer per node.
    public static let siblingCompetitionMargin: Double = 0.0

    /// Reserved for future ambiguous sibling bands; 4E does not co-prove near ties.
    public static let siblingAmbiguityEpsilon: Double = 0.02

    // MARK: - Lane activation

    public static func isObjectLaneActive(thread: ExchangeThread) -> Bool {
        guard let facets = thread.facets else { return false }
        return isObjectLaneActive(
            queryIntentClass: facets.queryIntentClass,
            surfacePreference: facets.surfacePreference,
            searchIntent: facets.searchIntent
        )
    }

    public static func isObjectLaneActive(
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference = .offer,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    ) -> Bool {
        guard queryIntentClass == .offerSearch else { return false }
        guard surfacePreference == .offer else { return false }
        guard let si = searchIntent else { return false }
        guard si.domainCategory == .product else { return false }
        guard queryObjectText(from: si) != nil else { return false }
        guard !isServiceConstrainedProductObjectSearch(searchIntent: si) else { return false }

        switch si.transactionIntent {
        case .buy, .forSale:
            return true
        case .rent, .hire, .book, .inquire, .none:
            return false
        }
    }

    /// Product-object offer-search shape before purchase transaction normalization.
    public static func isProductObjectOfferSearchShape(
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    ) -> Bool {
        guard queryIntentClass == .offerSearch else { return false }
        guard surfacePreference == .offer else { return false }
        guard let si = searchIntent else { return false }
        guard queryObjectText(from: si) != nil else { return false }
        guard !isServiceConstrainedProductObjectSearch(searchIntent: si) else { return false }

        switch si.domainCategory {
        case .product, .general:
            return true
        case .homeService, .professionalService, .realEstate:
            return false
        }
    }

    public static func resolvedLiveInterpretationRoute(
        from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> (
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference,
        targetKind: ExchangeIntentFacets.TargetKind
    ) {
        let legacy = SearchIntentRouteValidator.legacyQuerySurfaceTargetRouting(from: canonical)
        let routing = SearchIntentRouteValidator.resolvedRouting(from: canonical, legacy: legacy)
        return (routing.queryClass, routing.surface, routing.targetKind)
    }

    public static func normalizeActorNounObjectForLiveInterpretation(
        _ searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        source: String = "liveInterpretation"
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        ExchangeActorNounNormalization.normalize(searchIntent, source: source).searchIntent
    }

    public static func normalizeProductObjectTransactionForLiveInterpretation(
        _ searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        source: String = "liveInterpretation"
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        let route = resolvedLiveInterpretationRoute(from: searchIntent)
        return normalizeProductObjectTransactionForLiveInterpretation(
            searchIntent,
            queryIntentClass: route.queryIntentClass,
            surfacePreference: route.surfacePreference,
            source: source
        )
    }

    public static func normalizeProductObjectTransactionForLiveInterpretation(
        _ searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference,
        source: String = "liveInterpretation"
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        var copy = searchIntent
        guard queryIntentClass == .offerSearch else { return copy }
        guard surfacePreference == .offer else { return copy }
        guard queryObjectText(from: copy) != nil else { return copy }

        switch copy.domainCategory {
        case .homeService, .professionalService, .realEstate:
            return copy
        case .product:
            break
        case .general:
            copy.domainCategory = .product
        }

        let transactionBefore = copy.transactionIntent?.rawValue ?? "nil"
        switch copy.transactionIntent {
        case .buy, .forSale:
            return copy
        case .rent, .hire, .book, .inquire, .none:
            copy.transactionIntent = .buy
        }

        #if DEBUG
        print(
            "[ObjectLaneCanonicalNormalize] objectType=\(copy.objectType ?? "nil") " +
            "domainCategory=\(copy.domainCategory.rawValue) " +
            "transactionBefore=\(transactionBefore) transactionAfter=buy source=\(source)"
        )
        #endif
        return copy
    }

    private static func isServiceConstrainedProductObjectSearch(
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> Bool {
        switch searchIntent.domainCategory {
        case .homeService, .professionalService, .realEstate:
            return true
        case .product, .general:
            return false
        }
    }

    /// Canonical object carrier for embedding comparison. Never derived from raw user query text.
    public static func queryObjectText(thread: ExchangeThread) -> String? {
        guard let si = thread.facets?.searchIntent else { return nil }
        return queryObjectText(from: si)
    }

    public static func queryObjectText(
        from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> String? {
        ExchangeActorNounNormalization.resolvedRetrievalObjectText(from: searchIntent)
    }

    // MARK: - Document provenance

    public static func isOfferObjectDocument(_ document: ExchangeRetrievalDocument) -> Bool {
        document.docKind == .offerObject
    }

    public static func canProveOfferObjectEvidence(_ document: ExchangeRetrievalDocument) -> Bool {
        isOfferObjectDocument(document)
    }

    public static func matchedOfferIDsFromOfferObjectHit(
        _ document: ExchangeRetrievalDocument
    ) -> [String] {
        guard isOfferObjectDocument(document),
              let offerID = trimmedNonEmpty(document.offerID) else {
            return []
        }
        return [offerID]
    }

    public static func canAttachOfferFromProvenance(
        document: ExchangeRetrievalDocument,
        objectEvidenceScore: Double?,
        competitiveProvenObjectOfferScores: [String: Double] = [:]
    ) -> Bool {
        guard canProveOfferObjectEvidence(document) else { return false }
        guard let offerID = trimmedNonEmpty(document.offerID),
              let score = objectEvidenceScore else {
            return false
        }
        guard score >= minimumObjectEvidenceScore else { return false }
        guard let provenScore = competitiveProvenObjectOfferScores[offerID] else {
            return false
        }
        return provenScore >= minimumObjectEvidenceScore
    }

    /// Per-node sibling competition among `offer_object` docs.
    ///
    /// Ranking may still use raw cosine scores; only competitively proven offer IDs may attach.
    public static func competitivelyProvenObjectOffers(
        documents: [ExchangeRetrievalDocument],
        objectEvidenceScoresByDocumentID: [String: Double]
    ) -> [String: Double] {
        var bestScoreByOfferIDByGroup: [String: [String: Double]] = [:]

        for document in documents {
            guard isOfferObjectDocument(document),
                  let offerID = trimmedNonEmpty(document.offerID),
                  let score = objectEvidenceScoresByDocumentID[document.id] else {
                continue
            }

            let groupKey = competitiveGroupKey(for: document)
            var offerScores = bestScoreByOfferIDByGroup[groupKey, default: [:]]
            offerScores[offerID] = max(offerScores[offerID] ?? score, score)
            bestScoreByOfferIDByGroup[groupKey] = offerScores
        }

        var provenOfferScores: [String: Double] = [:]
        provenOfferScores.reserveCapacity(bestScoreByOfferIDByGroup.count)

        for offerScores in bestScoreByOfferIDByGroup.values {
            let qualifying = offerScores.filter { $0.value >= minimumObjectEvidenceScore }
            guard let winner = qualifying.max(by: competitiveOfferOrdering) else {
                continue
            }
            provenOfferScores[winner.key] = winner.value
        }

        return provenOfferScores
    }

    // MARK: - Offer attachment policy

    public static func objectLaneMatchedOffers(
        from offers: [ExchangeOffer],
        provenObjectOfferIDs: Set<String>,
        objectEvidenceScoreByOfferID: [String: Double]
    ) -> [ExchangeOffer] {
        offers.filter { offer in
            guard provenObjectOfferIDs.contains(offer.id) else { return false }
            guard let score = objectEvidenceScoreByOfferID[offer.id] else { return false }
            return score >= minimumObjectEvidenceScore
        }
    }

    public static func applyObjectLaneOfferAttachmentPolicy(
        thread: ExchangeThread,
        offers: [ExchangeOffer],
        provenObjectOfferIDs: Set<String>,
        objectEvidenceScoreByOfferID: [String: Double]
    ) -> (
        matchedOffers: [ExchangeOffer],
        provenObjectOfferIDs: Set<String>,
        objectEvidenceScoreByOfferID: [String: Double]
    ) {
        guard isObjectLaneActive(thread: thread) else {
            return (offers, [], [:])
        }

        let matched = objectLaneMatchedOffers(
            from: offers,
            provenObjectOfferIDs: provenObjectOfferIDs,
            objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID
        )
        let matchedIDs = Set(matched.map(\.id))
        let matchedScores = objectEvidenceScoreByOfferID.filter { matchedIDs.contains($0.key) }
        return (matched, matchedIDs, matchedScores)
    }

    public static func provenanceFromRetrievalHit(
        document: ExchangeRetrievalDocument,
        objectEvidenceScore: Double?,
        matchedOffers: [ExchangeOffer],
        competitiveProvenObjectOfferScores: [String: Double] = [:]
    ) -> (provenObjectOfferIDs: Set<String>, objectEvidenceScoreByOfferID: [String: Double]) {
        guard canAttachOfferFromProvenance(
            document: document,
            objectEvidenceScore: objectEvidenceScore,
            competitiveProvenObjectOfferScores: competitiveProvenObjectOfferScores
        ) else {
            return ([], [:])
        }

        guard let offerID = trimmedNonEmpty(document.offerID),
              matchedOffers.contains(where: { $0.id == offerID }),
              let score = competitiveProvenObjectOfferScores[offerID] else {
            return ([], [:])
        }

        return ([offerID], [offerID: score])
    }

    // MARK: - Selection

    public static func resolveSelectedOfferID(
        provenObjectOfferIDs: Set<String>,
        objectEvidenceScoreByOfferID: [String: Double],
        preferredOfferID: String? = nil
    ) -> String? {
        guard !provenObjectOfferIDs.isEmpty else { return nil }

        let qualifying = objectEvidenceScoreByOfferID.filter { entry in
            provenObjectOfferIDs.contains(entry.key) && entry.value >= minimumObjectEvidenceScore
        }
        guard !qualifying.isEmpty else { return nil }

        if let preferred = trimmedNonEmpty(preferredOfferID),
           qualifying[preferred] != nil {
            return preferred
        }

        return qualifying.max(by: { $0.value < $1.value })?.key
    }

    public static func resolveSelectedOfferID(
        from match: ExchangeMatch,
        thread: ExchangeThread
    ) -> ExchangeOffer.ID? {
        guard isObjectLaneActive(thread: thread) else {
            return match.offerID ?? match.matchedOfferIDs.first
        }
        return resolveSelectedOfferID(
            provenObjectOfferIDs: Set(match.provenObjectOfferIDs),
            objectEvidenceScoreByOfferID: match.objectEvidenceScoreByOfferID,
            preferredOfferID: match.offerID
        )
    }

    // MARK: - Embedding helpers

    public static func offerObjectEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        ExchangeRetrievalDocumentEmbeddingPolicy.offerObjectEmbeddingText(from: document)
    }

    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return 0 }
        let normalizedLHS = l2Normalize(lhs)
        let normalizedRHS = l2Normalize(rhs)
        var sum: Float = 0
        for index in normalizedLHS.indices {
            sum += normalizedLHS[index] * normalizedRHS[index]
        }
        return Double(sum)
    }

    public static func objectEvidenceScore(
        queryEmbedding: [Float],
        document: ExchangeRetrievalDocument
    ) -> Double? {
        guard isOfferObjectDocument(document),
              let documentEmbedding = document.embedding,
              !documentEmbedding.isEmpty,
              documentEmbedding.count == queryEmbedding.count else {
            return nil
        }
        return cosineSimilarity(queryEmbedding, documentEmbedding)
    }

    public static func rankOfferObjectDocuments(
        queryEmbedding: [Float],
        documents: [ExchangeRetrievalDocument],
        limit: Int
    ) -> [(documentID: String, score: Double)] {
        let cappedLimit = max(0, limit)
        guard cappedLimit > 0 else { return [] }

        return documents
            .filter(isOfferObjectDocument)
            .compactMap { document -> (documentID: String, score: Double)? in
                guard let score = objectEvidenceScore(
                    queryEmbedding: queryEmbedding,
                    document: document
                ) else {
                    return nil
                }
                return (document.id, score)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.documentID < $1.documentID
            }
            .prefix(cappedLimit)
            .map { $0 }
    }

    // MARK: - Private

    private static func competitiveGroupKey(for document: ExchangeRetrievalDocument) -> String {
        trimmedNonEmpty(document.nodeID) ?? document.counterpartyID
    }

    private static func competitiveOfferOrdering(
        lhs: (key: String, value: Double),
        rhs: (key: String, value: Double)
    ) -> Bool {
        if lhs.value != rhs.value {
            return lhs.value < rhs.value
        }
        return lhs.key > rhs.key
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func l2Normalize(_ vector: [Float]) -> [Float] {
        var sum: Float = 0
        for value in vector { sum += value * value }
        let norm = sqrt(sum)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
