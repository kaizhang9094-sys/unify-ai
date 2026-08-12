import CryptoKit
import Foundation

// MARK: - Standing interest (For You directory query; public profile only)

/// Cached public-safe standing interest for the profile-led For You directory rail.
/// Phase 2A: heuristic or future LLM output — never local offers, constitution, or thread data.
public struct ForYouStandingInterest: Codable, Sendable, Hashable {
    public var queryText: String
    /// English-only directory embedding carrier when `queryText` is not English.
    public var canonicalEnglishQuery: String?
    public var searchTags: [String]
    public var lookingForTags: [String]
    public var interestTags: [String]
    public var roleTags: [String]
    public var regionTags: [String]
    public var excludedTags: [String]
    public var confidence: Double
    public var generatedAt: Date
    public var sourceProfileFingerprint: String
    public var debugSummary: String?

    public init(
        queryText: String,
        canonicalEnglishQuery: String? = nil,
        searchTags: [String],
        lookingForTags: [String],
        interestTags: [String],
        roleTags: [String],
        regionTags: [String],
        excludedTags: [String],
        confidence: Double,
        generatedAt: Date,
        sourceProfileFingerprint: String,
        debugSummary: String? = nil
    ) {
        self.queryText = queryText
        self.canonicalEnglishQuery = canonicalEnglishQuery
        self.searchTags = searchTags
        self.lookingForTags = lookingForTags
        self.interestTags = interestTags
        self.roleTags = roleTags
        self.regionTags = regionTags
        self.excludedTags = excludedTags
        self.confidence = confidence
        self.generatedAt = generatedAt
        self.sourceProfileFingerprint = sourceProfileFingerprint
        self.debugSummary = debugSummary
    }

    /// Tags sent as directory `tags`: search + interest + role buckets, deduped.
    public var directoryTags: [String] {
        ForYouStandingInterestNormalizer.dedupePreservingOrder(
            searchTags + interestTags + roleTags,
            maxCount: ForYouStandingInterestNormalizer.maxDirectoryTagCount,
            maxTokenLength: ForYouStandingInterestNormalizer.maxTagLength
        )
    }
}

// MARK: - Normalization

public enum ForYouStandingInterestNormalizer {
    public static let maxTagLength = 64
    public static let maxDirectoryTagCount = 48
    public static let maxBucketTagCount = 32

    public static func trimToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func capToken(_ raw: String, maxLength: Int = maxTagLength) -> String {
        let t = trimToken(raw)
        guard t.count > maxLength else { return t }
        return String(t.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Dedupe case-insensitively; preserve first-seen order; cap count.
    public static func dedupePreservingOrder(
        _ raw: [String],
        maxCount: Int,
        maxTokenLength: Int = maxTagLength
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in raw {
            let capped = capToken(r, maxLength: maxTokenLength)
            guard capped.count >= 2 else { continue }
            let key = capped.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(capped)
            if out.count >= maxCount { break }
        }
        return out
    }

    public static func normalizeTagBucket(_ raw: [String]) -> [String] {
        dedupePreservingOrder(raw, maxCount: maxBucketTagCount, maxTokenLength: maxTagLength)
    }

    public static func conciseQueryText(
        headline: String?,
        summary: String?,
        interests: [String],
        openTo: [String],
        maxLength: Int = 720
    ) -> String {
        var parts: [String] = []
        if let h = headline?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            parts.append(h)
        }
        if let s = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            parts.append(s)
        }
        if !interests.isEmpty {
            parts.append(interests.map { trimToken($0) }.filter { !$0.isEmpty }.joined(separator: ", "))
        }
        if !openTo.isEmpty {
            parts.append(openTo.map { trimToken($0) }.filter { !$0.isEmpty }.joined(separator: ", "))
        }
        var joined = parts.joined(separator: ". ").trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.count > maxLength {
            joined = String(joined.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return joined
    }
}

// MARK: - Profile fingerprint (deterministic, no timestamps)

public enum ForYouStandingInterestProfileFingerprint {
    /// Stable fingerprint from public profile fields only. Array fields are sorted for order-insensitive equality.
    public static func make(for profile: ExchangePublicNodeProfile) -> String {
        let headline = profile.headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = profile.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let interests = profile.interests.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()
        let openTo = profile.openTo.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()
        let activity = profile.activityTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()
        let regions = profile.regionTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()
        let domains = profile.semantic.domains.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()
        let intents = profile.semantic.intentKinds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()
        let excluded = profile.excludedTopics.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()

        let canonical =
            [
                "h:\(headline)",
                "s:\(summary)",
                "i:\(interests.joined(separator: "\u{1f}"))",
                "o:\(openTo.joined(separator: "\u{1f}"))",
                "a:\(activity.joined(separator: "\u{1f}"))",
                "r:\(regions.joined(separator: "\u{1f}"))",
                "d:\(domains.joined(separator: "\u{1f}"))",
                "k:\(intents.joined(separator: "\u{1f}"))",
                "x:\(excluded.joined(separator: "\u{1f}"))"
            ]
            .joined(separator: "\u{1e}")

        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Persist validation / normalization

public enum ForYouStandingInterestSanitizer {
    public static let maxPersistQueryChars = 720

    /// True when the public profile has any non-empty discovery-relevant field.
    public static func profileHasPublicDiscoverySignal(_ profile: ExchangePublicNodeProfile) -> Bool {
        if let h = profile.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty { return true }
        if let s = profile.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return true }
        if profile.interests.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if profile.openTo.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if profile.activityTags.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if profile.regionTags.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if profile.semantic.domains.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if profile.semantic.intentKinds.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        if profile.excludedTopics.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        return false
    }

    /// True when headline/summary look emoji-heavy or contain long digit runs (directory query should not mirror raw prose).
    public static func isNoisyPublicProse(_ profile: ExchangePublicNodeProfile) -> Bool {
        let parts = [profile.headline, profile.summary]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let blob = parts.joined(separator: " ")
        guard !blob.isEmpty else { return false }
        let emojiScalars = blob.unicodeScalars.filter(\.properties.isEmoji).count
        if emojiScalars >= 2 { return true }
        return longestDigitRun(in: blob) >= 6
    }

    /// Final directory `queryText`: blends model `queryText` with deduped discovery tags when both exist.
    public static func directorySearchQueryText(
        from interest: ForYouStandingInterest,
        profile: ExchangePublicNodeProfile
    ) -> String {
        if let english = interest.canonicalEnglishQuery?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !english.isEmpty {
            return String(english.prefix(maxPersistQueryChars))
        }

        let trimmed = interest.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagLine = combinedDiscoveryTagLine(for: interest)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if interest.debugSummary == "heuristic profile fallback",
           isNoisyPublicProse(profile),
           !tagLine.isEmpty {
            return String(tagLine.prefix(maxPersistQueryChars))
        }
        if trimmed.isEmpty, !tagLine.isEmpty {
            return String(tagLine.prefix(maxPersistQueryChars))
        }
        if !trimmed.isEmpty, !tagLine.isEmpty {
            let combined = trimmed + ". " + tagLine
            return String(combined.prefix(maxPersistQueryChars))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(trimmed.prefix(maxPersistQueryChars))
    }

    /// Deduped `directoryTags` + `lookingForTags` for directory query blending (excludes `excludedTags`).
    private static func combinedDiscoveryTagLine(for interest: ForYouStandingInterest) -> String {
        let raw = interest.directoryTags + interest.lookingForTags
        let parts = ForYouStandingInterestNormalizer.dedupePreservingOrder(
            raw,
            maxCount: ForYouStandingInterestNormalizer.maxDirectoryTagCount
                + ForYouStandingInterestNormalizer.maxBucketTagCount,
            maxTokenLength: ForYouStandingInterestNormalizer.maxTagLength
        )
        return parts
            .map { ForYouStandingInterestNormalizer.trimToken($0) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Model `lookingForTags` order first, then literal `profile.openTo` entries not already present.
    private static func mergeLookingForTagsModelThenProfile(
        modelTags: [String],
        profileOpenTo: [String]
    ) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for t in modelTags {
            let c = ForYouStandingInterestNormalizer.capToken(ForYouStandingInterestNormalizer.trimToken(t))
            guard c.count >= 2 else { continue }
            let key = c.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(c)
        }
        for t in profileOpenTo {
            let c = ForYouStandingInterestNormalizer.capToken(ForYouStandingInterestNormalizer.trimToken(t))
            guard c.count >= 2 else { continue }
            let key = c.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(c)
        }
        return out
    }

    private static func longestDigitRun(in text: String) -> Int {
        var best = 0
        var cur = 0
        for ch in text {
            if ch.isNumber {
                cur += 1
                best = max(best, cur)
            } else {
                cur = 0
            }
        }
        return best
    }

    /// Re-normalize and verify fingerprint before writing to cache. Returns `nil` if the value must not be persisted.
    public static func sanitizedForPersist(
        _ raw: ForYouStandingInterest,
        profile: ExchangePublicNodeProfile,
        expectedFingerprint: String,
        now: Date = Date()
    ) -> ForYouStandingInterest? {
        guard profileHasPublicDiscoverySignal(profile) else { return nil }
        let current = ForYouStandingInterestProfileFingerprint.make(for: profile)
        guard current == expectedFingerprint else { return nil }
        guard raw.sourceProfileFingerprint == expectedFingerprint else { return nil }

        var qt = ForYouStandingInterestNormalizer.trimToken(raw.queryText)
        if qt.count > maxPersistQueryChars {
            qt = String(qt.prefix(maxPersistQueryChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let searchTags = ForYouStandingInterestNormalizer.normalizeTagBucket(raw.searchTags)
        let mergedLookingRaw = mergeLookingForTagsModelThenProfile(
            modelTags: raw.lookingForTags,
            profileOpenTo: profile.openTo
        )
        let lookingForTags = ForYouStandingInterestNormalizer.normalizeTagBucket(mergedLookingRaw)
        let interestTags = ForYouStandingInterestNormalizer.normalizeTagBucket(raw.interestTags)
        let roleTags = ForYouStandingInterestNormalizer.normalizeTagBucket(raw.roleTags)
        let regionTags = ForYouStandingInterestNormalizer.normalizeTagBucket(raw.regionTags)
        let excludedTags = ForYouStandingInterestNormalizer.normalizeTagBucket(raw.excludedTags)

        let confidence = min(1, max(0, raw.confidence))

        let rebuilt = ForYouStandingInterest(
            queryText: qt,
            searchTags: searchTags,
            lookingForTags: lookingForTags,
            interestTags: interestTags,
            roleTags: roleTags,
            regionTags: regionTags,
            excludedTags: excludedTags,
            confidence: confidence,
            generatedAt: now,
            sourceProfileFingerprint: expectedFingerprint,
            debugSummary: raw.debugSummary.map { String($0.prefix(200)) }
        )

        guard shouldPersist(rebuilt) else { return nil }
        return rebuilt
    }

    private static func shouldPersist(_ interest: ForYouStandingInterest) -> Bool {
        let qt = interest.queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !qt.isEmpty { return true }
        if !interest.directoryTags.isEmpty { return true }
        if !interest.lookingForTags.isEmpty { return true }
        if !interest.regionTags.isEmpty { return true }
        if !interest.excludedTags.isEmpty { return true }
        return false
    }
}
