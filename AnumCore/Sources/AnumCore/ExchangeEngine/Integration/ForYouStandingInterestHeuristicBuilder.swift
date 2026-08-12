import Foundation

/// Deterministic heuristic standing interest from `ExchangePublicNodeProfile` only (Phase 2A — no LLM).
public enum ForYouStandingInterestHeuristicBuilder {
    public static let heuristicConfidence = 0.45

    public static func build(from profile: ExchangePublicNodeProfile, now: Date = Date()) -> ForYouStandingInterest {
        let interests = profile.interests
        let openTo = profile.openTo
        let activity = profile.activityTags
        let regions = profile.regionTags
        let domains = profile.semantic.domains
        let intents = profile.semantic.intentKinds
        let excluded = profile.excludedTopics

        let queryText = ForYouStandingInterestNormalizer.conciseQueryText(
            headline: profile.headline,
            summary: profile.summary,
            interests: interests,
            openTo: openTo
        )

        let searchTags = ForYouStandingInterestNormalizer.normalizeTagBucket(
            activity + domains + intents + interests + openTo
        )

        let lookingForTags = ForYouStandingInterestNormalizer.normalizeTagBucket(openTo)

        let interestTags = ForYouStandingInterestNormalizer.normalizeTagBucket(interests)

        let roleTags = ForYouStandingInterestNormalizer.normalizeTagBucket(activity + domains + intents)

        let regionTags = ForYouStandingInterestNormalizer.normalizeTagBucket(regions)

        let excludedTags = ForYouStandingInterestNormalizer.normalizeTagBucket(excluded)

        let fingerprint = ForYouStandingInterestProfileFingerprint.make(for: profile)

        return ForYouStandingInterest(
            queryText: queryText,
            searchTags: searchTags,
            lookingForTags: lookingForTags,
            interestTags: interestTags,
            roleTags: roleTags,
            regionTags: regionTags,
            excludedTags: excludedTags,
            confidence: heuristicConfidence,
            generatedAt: now,
            sourceProfileFingerprint: fingerprint,
            debugSummary: "heuristic profile fallback"
        )
    }
}
