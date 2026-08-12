import Foundation

/// Builds ``ExchangeRetrievalQuery`` for For You client-side BM25 reranking from standing-interest fields only.
///
/// - Does not use ``ExchangeRetrievalQueryBuilder`` / ``ExchangeThread`` (thread discovery path).
/// - No synonym expansion or domain remapping: only literal strings and tag arrays passed through.
public enum ForYouRetrievalQueryBuilder: Sendable {

    /// Assembles a permissive retrieval query for lexical (BM25) scoring over directory candidates.
    public static func buildForDirectoryRerank(
        queryText: String,
        directoryTags: [String],
        openToTags: [String],
        regionTags: [String],
        interestTags: [String],
        roleTags: [String],
        candidateDocumentCount: Int
    ) -> ExchangeRetrievalQuery {
        let trimmedQuery = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, candidateDocumentCount)
        return ExchangeRetrievalQuery(
            queryText: trimmedQuery.isEmpty ? nil : trimmedQuery,
            semanticText: nil,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            allowedSurfaceTypes: nil,
            providerTerms: [],
            capabilityTerms: [],
            affinityTerms: [],
            regionTerms: [],
            queryEntities: [],
            resolvedPlaces: [],
            hardRegionIDs: [],
            softRegionTerms: regionTags,
            commercialIntentTerms: [],
            timeTerms: [],
            keywords: directoryTags + openToTags + interestTags + roleTags,
            explicitHardConstraints: [],
            explicitRegionRequired: false,
            explicitFulfillmentRequired: false,
            targetKind: nil,
            fulfillmentMode: nil,
            reachabilityRequirement: .any,
            visibilityAllowList: [],
            availabilityAllowList: [],
            limit: limit
        )
    }
}
