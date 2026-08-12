import Foundation

/// Minimal metadata stamped on locally cached server-derived discovery entities.
///
/// Stored in each model's `metadata` dictionary and persisted via `metadata_json` columns.
public enum ExchangeRemoteDiscoveryCacheMetadata {
    public static let cacheSourceKey = "cacheSource"
    public static let lastSeenAtKey = "lastSeenAt"
    public static let cacheDurabilityKey = "cacheDurability"

    public enum CacheSource: String, Sendable, Hashable {
        case discovery
        case forYou
        case contactHydration
        case inboundDM
        case localOwned
    }

    public enum CacheDurability: String, Sendable, Hashable {
        case transient
        case durable
    }

    public static func isoTimestamp(_ date: Date) -> String {
        makeISOFormatter().string(from: date)
    }

    public static func parseLastSeenAt(from metadata: [String: String]) -> Date? {
        guard let raw = metadata[lastSeenAtKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return makeISOFormatter().date(from: raw)
    }

    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    public static func cacheSource(from metadata: [String: String]) -> CacheSource? {
        guard let raw = metadata[cacheSourceKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return CacheSource(rawValue: raw)
    }

    public static func isDurable(_ metadata: [String: String]) -> Bool {
        metadata[cacheDurabilityKey]?.trimmingCharacters(in: .whitespacesAndNewlines) == CacheDurability.durable.rawValue
    }

    public static func apply(
        to metadata: inout [String: String],
        source: CacheSource,
        durability: CacheDurability,
        now: Date
    ) {
        metadata[cacheSourceKey] = source.rawValue
        metadata[cacheDurabilityKey] = durability.rawValue
        metadata[lastSeenAtKey] = isoTimestamp(now)
    }

    public static func touchLastSeen(_ metadata: inout [String: String], now: Date) {
        metadata[lastSeenAtKey] = isoTimestamp(now)
    }

    public static func tagDiscoveryCounterparty(_ counterparty: ExchangeCounterparty, now: Date) -> ExchangeCounterparty {
        var copy = counterparty
        copy.updatedAt = now
        apply(to: &copy.metadata, source: .discovery, durability: .transient, now: now)
        if var profile = copy.publicProfile {
            tagDiscoveryProfile(&profile, now: now)
            copy.publicProfile = profile
        }
        return copy
    }

    public static func tagDiscoveryProfile(_ profile: inout ExchangePublicNodeProfile, now: Date) {
        profile.updatedAt = now
        apply(to: &profile.metadata, source: .discovery, durability: .transient, now: now)
    }

    public static func tagDiscoveryOffer(_ offer: inout ExchangeOffer, now: Date) {
        offer.updatedAt = now
        apply(to: &offer.metadata, source: .discovery, durability: .transient, now: now)
    }

    public static func tagForYouCounterparty(_ counterparty: ExchangeCounterparty, now: Date) -> ExchangeCounterparty {
        var copy = counterparty
        copy.updatedAt = now
        apply(to: &copy.metadata, source: .forYou, durability: .transient, now: now)
        if var profile = copy.publicProfile {
            tagForYouProfile(&profile, now: now)
            copy.publicProfile = profile
        }
        return copy
    }

    public static func tagForYouProfile(_ profile: inout ExchangePublicNodeProfile, now: Date) {
        profile.updatedAt = now
        apply(to: &profile.metadata, source: .forYou, durability: .transient, now: now)
    }

    public static func tagContactHydrationProfile(_ profile: inout ExchangePublicNodeProfile, now: Date) {
        profile.updatedAt = now
        apply(to: &profile.metadata, source: .contactHydration, durability: .durable, now: now)
    }

    public static func tagContactHydrationCounterparty(_ counterparty: ExchangeCounterparty, now: Date) -> ExchangeCounterparty {
        var copy = counterparty
        copy.updatedAt = now
        apply(to: &copy.metadata, source: .contactHydration, durability: .durable, now: now)
        return copy
    }

    public static func tagInboundDMCounterparty(_ counterparty: ExchangeCounterparty, now: Date) -> ExchangeCounterparty {
        var copy = counterparty
        copy.updatedAt = now
        apply(to: &copy.metadata, source: .inboundDM, durability: .durable, now: now)
        return copy
    }

    public static func tagLocalOwnedProfile(_ profile: inout ExchangePublicNodeProfile, now: Date) {
        profile.updatedAt = now
        apply(to: &profile.metadata, source: .localOwned, durability: .durable, now: now)
    }

    public static func tagLocalOwnedOffer(_ offer: inout ExchangeOffer, now: Date) {
        offer.updatedAt = now
        apply(to: &offer.metadata, source: .localOwned, durability: .durable, now: now)
    }
}
