import Foundation

/// Seller-declared geography where an offer is available (chip), not inferred from a gazetteer.
public struct ExchangeDeclaredServiceArea: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = String

    public enum Source: String, Codable, Sendable, Hashable {
        case sellerEntered
        case aiSuggestedSellerApproved
        case imported
        case legacyRegionTag
    }

    public var id: ID
    public var displayName: String
    public var normalizedName: String
    public var aliases: [String]
    public var source: Source
    public var acceptsRemote: Bool
    /// Optional H3 footprint; nil when text-only. Never projected into `regionTags`.
    public var spatial: ExchangeSpatialCoverage?

    public init(
        id: ID? = nil,
        displayName: String,
        normalizedName: String? = nil,
        aliases: [String] = [],
        source: Source = .sellerEntered,
        acceptsRemote: Bool? = nil,
        spatial: ExchangeSpatialCoverage? = nil
    ) {
        let trimmedDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizedName.map {
            ExchangeLocationNormalization.normalize($0, stripRegionalSuffixes: true)
        } ?? ExchangeLocationNormalization.normalize(trimmedDisplay, stripRegionalSuffixes: true)

        let resolvedID = id ?? (normalized.isEmpty ? trimmedDisplay : normalized)
        self.id = resolvedID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.displayName = trimmedDisplay
        self.normalizedName = normalized
        self.aliases = Self.sanitizeAliases(aliases, displayName: trimmedDisplay, normalizedName: normalized)
        self.source = source
        let remote = acceptsRemote ?? ExchangeLocationNormalization.isRemoteServiceAreaLabel(normalized)
        self.acceptsRemote = remote
        self.spatial = spatial.normalizedOptional()
    }

    public static func fromLegacyRegionTag(_ display: String) -> ExchangeDeclaredServiceArea? {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ExchangeDeclaredServiceArea(
            displayName: trimmed,
            source: .legacyRegionTag
        )
    }

    public static func fromSellerChip(_ display: String, aliases: [String] = []) -> ExchangeDeclaredServiceArea? {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ExchangeDeclaredServiceArea(
            displayName: trimmed,
            aliases: aliases,
            source: .sellerEntered
        )
    }

    private static func sanitizeAliases(
        _ values: [String],
        displayName: String,
        normalizedName: String
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        func append(_ raw: String) {
            let n = ExchangeLocationNormalization.normalize(raw, stripRegionalSuffixes: true)
            guard !n.isEmpty, n != normalizedName, !seen.contains(n) else { return }
            seen.insert(n)
            out.append(n)
        }

        for value in values {
            append(value)
        }

        if normalizedName == "gta" {
            append("greater toronto area")
        }

        _ = displayName
        return Array(out.prefix(12))
    }
}

public enum ExchangeDeclaredServiceAreaSupport {
    /// Builds structured areas from legacy comma-separated region tags.
    public static func hydrate(fromRegionTags regionTags: [String]) -> [ExchangeDeclaredServiceArea] {
        var seen = Set<String>()
        var out: [ExchangeDeclaredServiceArea] = []

        for raw in regionTags {
            guard let area = ExchangeDeclaredServiceArea.fromLegacyRegionTag(raw) else { continue }
            let key = area.normalizedName
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(area)
        }
        return out
    }

    /// Display names for wire-compatible `regionTags` (and directory search).
    public static func projectRegionTags(from serviceAreas: [ExchangeDeclaredServiceArea]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for area in serviceAreas {
            let display = area.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let key = display.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(display)
        }
        return out
    }

    /// All normalized tokens for retrieval lexical text (areas + aliases).
    public static func normalizedSearchTokens(from serviceAreas: [ExchangeDeclaredServiceArea]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        func append(_ raw: String) {
            let n = ExchangeLocationNormalization.normalize(raw, stripRegionalSuffixes: true)
            guard !n.isEmpty, !seen.contains(n) else { return }
            seen.insert(n)
            out.append(n)
        }

        for area in serviceAreas {
            append(area.normalizedName)
            append(area.displayName)
            for alias in area.aliases {
                append(alias)
            }
        }
        return out
    }

    /// Parses seller CSV/chip input into structured service areas.
    public static func parseSellerInput(_ csvOrChips: String) -> [ExchangeDeclaredServiceArea] {
        let segments = csvOrChips
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var out: [ExchangeDeclaredServiceArea] = []

        for segment in segments {
            guard let area = ExchangeDeclaredServiceArea.fromSellerChip(segment) else { continue }
            guard !seen.contains(area.normalizedName) else { continue }
            seen.insert(area.normalizedName)
            out.append(area)
        }
        return out
    }

    /// Ensures `serviceAreas` and projected `regionTags` stay aligned after edits.
    public static func syncOfferLocationFields(_ offer: inout ExchangeOffer) {
        if offer.serviceAreas.isEmpty, !offer.regionTags.isEmpty {
            offer.serviceAreas = hydrate(fromRegionTags: offer.regionTags)
        }
        if !offer.serviceAreas.isEmpty {
            offer.regionTags = projectRegionTags(from: offer.serviceAreas)
        }
    }
}
