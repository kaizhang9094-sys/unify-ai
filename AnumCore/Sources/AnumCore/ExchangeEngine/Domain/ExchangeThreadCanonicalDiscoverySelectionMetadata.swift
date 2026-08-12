import Foundation

public struct ExchangeCanonicalDiscoverySelectionSnapshot: Sendable, Hashable {
    public var counterpartyID: String?
    public var publicProfileID: String?
    public var offerID: String?
    public var source: String
    public var primaryCoordinationChildOfferID: String?

    public init(
        counterpartyID: String? = nil,
        publicProfileID: String? = nil,
        offerID: String? = nil,
        source: String,
        primaryCoordinationChildOfferID: String? = nil
    ) {
        self.counterpartyID = counterpartyID
        self.publicProfileID = publicProfileID
        self.offerID = offerID
        self.source = source
        self.primaryCoordinationChildOfferID = primaryCoordinationChildOfferID
    }
}

/// Durable discovery best-match anchor for UI projection when umbrella threads omit `selectedOfferID`.
public enum ExchangeThreadCanonicalDiscoverySelectionMetadata {
    public static let selectedOfferIDKey = "canonical_discovery_selected_offer_id"
    public static let selectedCounterpartyIDKey = "canonical_discovery_selected_counterparty_id"
    public static let selectedPublicProfileIDKey = "canonical_discovery_selected_public_profile_id"
    public static let selectionSourceKey = "canonical_discovery_selection_source"
    public static let primaryCoordinationChildOfferIDKey = "canonical_discovery_primary_child_offer_id"

    public static func selectedOfferID(from metadata: [String: String]) -> String? {
        normalized(metadata[selectedOfferIDKey])
    }

    public static func primaryCoordinationChildOfferID(from metadata: [String: String]) -> String? {
        normalized(metadata[primaryCoordinationChildOfferIDKey])
    }

    public static func selectedCounterpartyID(from metadata: [String: String]) -> String? {
        normalized(metadata[selectedCounterpartyIDKey])
    }

    public static func selectedPublicProfileID(from metadata: [String: String]) -> String? {
        normalized(metadata[selectedPublicProfileIDKey])
    }

    public static func selectionSource(from metadata: [String: String]) -> String? {
        normalized(metadata[selectionSourceKey])
    }

    public static func apply(
        _ selection: ExchangeCanonicalDiscoverySelectionSnapshot?,
        to metadata: inout [String: String]
    ) {
        guard let selection else {
            clear(from: &metadata)
            return
        }

        applyOptional(selection.offerID, key: selectedOfferIDKey, to: &metadata)
        applyOptional(selection.counterpartyID, key: selectedCounterpartyIDKey, to: &metadata)
        applyOptional(selection.publicProfileID, key: selectedPublicProfileIDKey, to: &metadata)
        applyOptional(
            selection.primaryCoordinationChildOfferID,
            key: primaryCoordinationChildOfferIDKey,
            to: &metadata
        )
        metadata[selectionSourceKey] = selection.source
    }

    public static func clear(from metadata: inout [String: String]) {
        metadata.removeValue(forKey: selectedOfferIDKey)
        metadata.removeValue(forKey: selectedCounterpartyIDKey)
        metadata.removeValue(forKey: selectedPublicProfileIDKey)
        metadata.removeValue(forKey: primaryCoordinationChildOfferIDKey)
        metadata.removeValue(forKey: selectionSourceKey)
    }

    private static func applyOptional(_ value: String?, key: String, to metadata: inout [String: String]) {
        if let normalized = normalized(value) {
            metadata[key] = normalized
        } else {
            metadata.removeValue(forKey: key)
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
