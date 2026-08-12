import Foundation

/// Ordered image URL candidates for secretary thread list rows and pinned slots.
///
/// Ordering follows ``ExchangePresentationSurfaceLead`` so profile-led threads do not
/// lead with offer galleries when ``selectedOfferID`` is unset.
public enum ExchangeInboxItemSurfaceImageCandidates {
    /// Cap for how many distinct URLs we keep for async `AsyncImage` fallback chains.
    public static let maxCandidateCount = 12

    public static func build(
        resolvedOffer: ExchangeOffer?,
        resolvedPublicProfile: ExchangePublicNodeProfile?,
        counterpartyProfilePrimaryImageURL: String?,
        matchMetadata: [String: String],
        selectedOfferID: String? = nil,
        selectedPublicProfileID: String? = nil
    ) -> [String] {
        let lead = ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: selectedOfferID,
            selectedPublicProfileID: selectedPublicProfileID
        )

        var ordered: [String] = []

        switch lead {
        case .offerLed:
            let fromOffer = resolvedOffer?.normalizedPublicOfferImageURLs() ?? []
            ordered.append(contentsOf: fromOffer)
            if let primary = primaryImageURLOfferLed(
                resolvedOffer: resolvedOffer,
                resolvedPublicProfile: resolvedPublicProfile,
                counterpartyProfilePrimaryImageURL: counterpartyProfilePrimaryImageURL,
                matchMetadata: matchMetadata
            ) {
                ordered.append(primary)
            }
            ordered.append(contentsOf: matchMetadataGalleryImageURLs(matchMetadata))

        case .profileLed:
            ordered.append(contentsOf: profileLedPrimaryStack(
                resolvedOffer: resolvedOffer,
                resolvedPublicProfile: resolvedPublicProfile,
                counterpartyProfilePrimaryImageURL: counterpartyProfilePrimaryImageURL,
                matchMetadata: matchMetadata
            ))
            ordered.append(contentsOf: matchMetadataGalleryImageURLs(matchMetadata))
            ordered.append(contentsOf: resolvedOffer?.normalizedPublicOfferImageURLs() ?? [])
            if let lateOfferMeta = matchMetadataPrimaryImageURL(from: matchMetadata, keys: ["offer_image_url"]) {
                ordered.append(lateOfferMeta)
            }

        case .ambiguous:
            if let primary = primaryImageURLAmbiguous(
                resolvedOffer: resolvedOffer,
                resolvedPublicProfile: resolvedPublicProfile,
                counterpartyProfilePrimaryImageURL: counterpartyProfilePrimaryImageURL,
                matchMetadata: matchMetadata
            ) {
                ordered.append(primary)
            }
            ordered.append(contentsOf: resolvedOffer?.normalizedPublicOfferImageURLs() ?? [])
            ordered.append(contentsOf: matchMetadataGalleryImageURLs(matchMetadata))
        }

        let unique = dedupePreservingOrder(ordered)
        return Array(unique.prefix(maxCandidateCount))
    }

    /// Profile-led: profile primary, counterparty, then non-offer metadata keys, then offer hero as late URLs (handled after gallery in `build`).
    private static func profileLedPrimaryStack(
        resolvedOffer: ExchangeOffer?,
        resolvedPublicProfile: ExchangePublicNodeProfile?,
        counterpartyProfilePrimaryImageURL: String?,
        matchMetadata: [String: String]
    ) -> [String] {
        var out: [String] = []
        if let profile = resolvedPublicProfile,
           let p = Self.nonBlank(profile.primaryImageURL) {
            out.append(p)
        }
        if let cp = Self.nonBlank(counterpartyProfilePrimaryImageURL) {
            out.append(cp)
        }
        if let meta = matchMetadataPrimaryImageURL(from: matchMetadata, keys: ["primary_image_url", "image_url"]) {
            out.append(meta)
        }
        return out
    }

    private static func primaryImageURLOfferLed(
        resolvedOffer: ExchangeOffer?,
        resolvedPublicProfile: ExchangePublicNodeProfile?,
        counterpartyProfilePrimaryImageURL: String?,
        matchMetadata: [String: String]
    ) -> String? {
        if let offer = resolvedOffer,
           let o = Self.nonBlank(offer.displayHeroImageURL) {
            return o
        }
        if let profile = resolvedPublicProfile,
           let p = Self.nonBlank(profile.primaryImageURL) {
            return p
        }
        if let cp = Self.nonBlank(counterpartyProfilePrimaryImageURL) {
            return cp
        }
        return matchMetadataPrimaryImageURL(from: matchMetadata, keys: ["primary_image_url", "offer_image_url", "image_url"])
    }

    private static func primaryImageURLAmbiguous(
        resolvedOffer: ExchangeOffer?,
        resolvedPublicProfile: ExchangePublicNodeProfile?,
        counterpartyProfilePrimaryImageURL: String?,
        matchMetadata: [String: String]
    ) -> String? {
        if let offer = resolvedOffer,
           let o = Self.nonBlank(offer.displayHeroImageURL) {
            return o
        }
        if let profile = resolvedPublicProfile,
           let p = Self.nonBlank(profile.primaryImageURL) {
            return p
        }
        if let cp = Self.nonBlank(counterpartyProfilePrimaryImageURL) {
            return cp
        }
        return matchMetadataPrimaryImageURL(from: matchMetadata, keys: ["primary_image_url", "offer_image_url", "image_url"])
    }

    private static func matchMetadataPrimaryImageURL(from metadata: [String: String], keys: [String]) -> String? {
        for key in keys {
            guard let raw = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { continue }

            if raw.contains("://") || raw.hasPrefix("//") || raw.hasPrefix("file:") {
                return raw
            }
        }
        return nil
    }

    private static func matchMetadataGalleryImageURLs(_ metadata: [String: String]) -> [String] {
        var out: [String] = []
        for key in ["gallery_image_urls", "surfaced_offer_image_urls", "offer_gallery_urls"] {
            guard let raw = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }

            if let data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                for s in decoded {
                    if let t = Self.nonBlank(s) {
                        out.append(t)
                    }
                }
            }

            for part in raw.split(separator: ",") {
                if let t = Self.nonBlank(String(part)) {
                    out.append(t)
                }
            }
        }
        return out
    }

    private static func dedupePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for v in values {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }

    private static func nonBlank(_ raw: String?) -> String? {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
