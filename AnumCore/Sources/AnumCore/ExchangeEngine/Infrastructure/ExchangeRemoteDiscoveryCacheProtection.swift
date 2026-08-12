import Foundation

/// Reference sets used to avoid pruning durable relationship or user-owned discovery cache rows.
public struct ExchangeRemoteDiscoveryCacheProtectionContext: Sendable, Hashable {
    public var protectedCounterpartyIDs: Set<String>
    public var protectedProfileIDs: Set<String>
    public var protectedOfferIDs: Set<String>
    public var ownedProfileIDs: Set<String>

    public init(
        protectedCounterpartyIDs: Set<String> = [],
        protectedProfileIDs: Set<String> = [],
        protectedOfferIDs: Set<String> = [],
        ownedProfileIDs: Set<String> = []
    ) {
        self.protectedCounterpartyIDs = protectedCounterpartyIDs
        self.protectedProfileIDs = protectedProfileIDs
        self.protectedOfferIDs = protectedOfferIDs
        self.ownedProfileIDs = ownedProfileIDs
    }

    public func isCounterpartyProtected(_ id: String) -> Bool {
        protectedCounterpartyIDs.contains(id)
    }

    public func isProfileProtected(_ id: String) -> Bool {
        protectedProfileIDs.contains(id) || ownedProfileIDs.contains(id)
    }

    public func isOfferProtected(_ id: String) -> Bool {
        protectedOfferIDs.contains(id)
    }
}

public enum ExchangeRemoteDiscoveryCacheProtection {
    public static let activeMatchStatuses: Set<ExchangeMatch.Status> = [
        .candidate,
        .shortlisted,
        .selected
    ]

    public static let durableMetadataPattern = "%\"\(ExchangeRemoteDiscoveryCacheMetadata.cacheDurabilityKey)\":\"\(ExchangeRemoteDiscoveryCacheMetadata.CacheDurability.durable.rawValue)\"%"

    public static func isLegacyDurableCounterpartySource(_ source: ExchangeCounterparty.Source) -> Bool {
        switch source {
        case .manualEntry, .trustedIntroduction:
            return true
        case .localDirectory, .relayNetwork, .imported:
            return false
        }
    }
}
