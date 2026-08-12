import Foundation

/// Compact retrieval request built from interpretation/facets.
///
/// Important:
/// - ExchangeRetrievalQuery expresses retrieval routing and true hard constraints
/// - it must NOT encode ranking scores
/// - it must NOT redefine canonical routing enums
/// - matching / fit judgment happens later
public struct ExchangeRetrievalQuery: Sendable, Hashable, Codable {
    public enum ReachabilityRequirement: String, Sendable, Hashable, Codable, CaseIterable {
        case any
        case acceptingInboundOnly
        case routeableOnly
        case directOnly
        case introAllowed
    }

    public var queryText: String?
    public var semanticText: String?

    /// Semantic text used for vector embedding only (excludes generated template boilerplate).
    public var semanticEmbeddingText: String?

    /// Canonical routing signal for retrieval behavior.
    public var queryIntentClass: ExchangeIntent.QueryIntentClass

    /// Canonical preferred dominant surface for this query.
    public var surfacePreference: ExchangeIntent.SurfacePreference

    /// When non-empty, hard retrieval requires `document.surfaceType` to appear in this set.
    /// Populated by `ExchangeRetrievalQueryBuilder` from intent + surface preference.
    /// Leave `nil` or empty to resolve from `queryIntentClass` + `surfacePreference` via
    /// `resolvedLaneSurfaceAllowList` (used by `ExchangeRetrievalEngine`).
    public var allowedSurfaceTypes: [ExchangeRetrievalDocument.SurfaceType]?

    /// Field-aware term families.
    public var providerTerms: [String]
    public var capabilityTerms: [String]
    public var affinityTerms: [String]
    /// Legacy field; retrieval builder leaves this empty. Use `softRegionTerms` and typed
    /// `resolvedPlaces` / `hardRegionIDs` for location signal and hard gating.
    public var regionTerms: [String]
    public var queryEntities: [ExchangeQueryEntity]
    public var resolvedPlaces: [ExchangeResolvedPlace]
    public var hardRegionIDs: [String]
    public var softRegionTerms: [String]
    /// Prepared requester H3 anchor (pass-through for later ranking; unused in Phase 4A matching).
    public var requesterSpatialAnchor: ExchangeRequesterSpatialAnchor?
    public var commercialIntentTerms: [String]
    public var timeTerms: [String]

    /// Optional general lexical hints.
    public var keywords: [String]

    /// True hard constraints only.
    public var explicitHardConstraints: [ExchangeIntent.Constraint]

    /// Hard gating only when explicitly required.
    public var explicitRegionRequired: Bool
    public var explicitFulfillmentRequired: Bool

    /// Optional routing hints.
    public var targetKind: String?
    public var fulfillmentMode: String?

    /// Operational gating.
    public var reachabilityRequirement: ReachabilityRequirement
    public var visibilityAllowList: [String]
    public var availabilityAllowList: [String]

    public var limit: Int

    /// Canonical object text for embedding comparison during concrete commercial offer searches.
    public var queryObjectText: String?

    /// Structural semantic target compiled from interpretation facets (optional for legacy queries).
    public var semanticTarget: ExchangeSemanticTarget?

    public init(
        queryText: String? = nil,
        semanticText: String? = nil,
        semanticEmbeddingText: String? = nil,
        queryIntentClass: ExchangeIntent.QueryIntentClass = .generalDiscovery,
        surfacePreference: ExchangeIntent.SurfacePreference = .mixed,
        allowedSurfaceTypes: [ExchangeRetrievalDocument.SurfaceType]? = nil,
        providerTerms: [String] = [],
        capabilityTerms: [String] = [],
        affinityTerms: [String] = [],
        regionTerms: [String] = [],
        queryEntities: [ExchangeQueryEntity] = [],
        resolvedPlaces: [ExchangeResolvedPlace] = [],
        hardRegionIDs: [String] = [],
        softRegionTerms: [String] = [],
        requesterSpatialAnchor: ExchangeRequesterSpatialAnchor? = nil,
        commercialIntentTerms: [String] = [],
        timeTerms: [String] = [],
        keywords: [String] = [],
        explicitHardConstraints: [ExchangeIntent.Constraint] = [],
        explicitRegionRequired: Bool = false,
        explicitFulfillmentRequired: Bool = false,
        targetKind: String? = nil,
        fulfillmentMode: String? = nil,
        reachabilityRequirement: ReachabilityRequirement = .any,
        visibilityAllowList: [String] = [],
        availabilityAllowList: [String] = [],
        limit: Int = 24,
        queryObjectText: String? = nil,
        semanticTarget: ExchangeSemanticTarget? = nil
    ) {
        self.queryText = queryText?.exchangeTrimmedNonEmpty
        self.semanticText = semanticText?.exchangeTrimmedNonEmpty
        self.semanticEmbeddingText = semanticEmbeddingText?.exchangeTrimmedNonEmpty
        self.queryIntentClass = queryIntentClass
        self.surfacePreference = surfacePreference
        self.allowedSurfaceTypes = allowedSurfaceTypes
        self.providerTerms = Self.normalizeTerms(providerTerms)
        self.capabilityTerms = Self.normalizeTerms(capabilityTerms)
        self.affinityTerms = Self.normalizeTerms(affinityTerms)
        self.regionTerms = Self.normalizeTerms(regionTerms)
        self.queryEntities = Self.normalizeEntities(queryEntities)
        self.resolvedPlaces = Self.normalizeResolvedPlaces(resolvedPlaces)
        self.hardRegionIDs = Self.normalizeTerms(hardRegionIDs)
        self.softRegionTerms = Self.normalizeTerms(softRegionTerms)
        self.requesterSpatialAnchor = requesterSpatialAnchor
        self.commercialIntentTerms = Self.normalizeTerms(commercialIntentTerms)
        self.timeTerms = Self.normalizeTerms(timeTerms)
        self.keywords = Self.normalizeTerms(keywords)
        self.explicitHardConstraints = Self.normalizeConstraints(explicitHardConstraints)
        self.explicitRegionRequired = explicitRegionRequired
        self.explicitFulfillmentRequired = explicitFulfillmentRequired
        self.targetKind = targetKind?.exchangeTrimmedNonEmpty?.lowercased()
        self.fulfillmentMode = fulfillmentMode?.exchangeTrimmedNonEmpty?.lowercased()
        self.reachabilityRequirement = reachabilityRequirement
        self.visibilityAllowList = Self.normalizeTerms(visibilityAllowList)
        self.availabilityAllowList = Self.normalizeTerms(availabilityAllowList)
        self.limit = max(1, limit)
        self.queryObjectText = queryObjectText?.exchangeTrimmedNonEmpty
        self.semanticTarget = semanticTarget
    }
}

public extension ExchangeRetrievalQuery {
    /// Effective surface allow-list for lane hard gating: explicit non-empty `allowedSurfaceTypes`,
    /// otherwise policy derived from `queryIntentClass` + `surfacePreference`.
    var resolvedLaneSurfaceAllowList: [ExchangeRetrievalDocument.SurfaceType]? {
        if let explicit = allowedSurfaceTypes, !explicit.isEmpty {
            return explicit
        }
        return Self.derivedLaneAllowedSurfaceTypes(
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference
        )
    }

    /// Lane policy used by the retrieval engine and query builder.
    ///
    /// - `nil` means no surface lane hard gate (permissive).
    /// - `surfacePreference == .mixed` is always permissive (no gate).
    /// - `generalDiscovery` is permissive unless an explicit non-empty `allowedSurfaceTypes` is set.
    /// - Social / relationship (non-mixed): profile surfaces only (excludes offer rows).
    /// - Commercial provider/offer and structured capability/collaboration with `.offer` or `.capability`
    ///   preference: offer + capability surfaces only (excludes pure affinity profiles).
    /// - Commercial intent with `.affinity` preference remains permissive so explicit affinity routing is honored.
    static func derivedLaneAllowedSurfaceTypes(
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> [ExchangeRetrievalDocument.SurfaceType]? {
        if surfacePreference == .mixed {
            return nil
        }

        switch queryIntentClass {
        case .socialAffinitySearch, .relationshipSearch:
            return [.publicProfileAffinity, .publicProfileCapability, .publicProfileSeeking, .publicProfile]

        case .offerSearch, .providerSearch:
            switch surfacePreference {
            case .affinity:
                return nil
            case .offer, .capability:
                return [.offer, .publicProfileCapability, .publicProfileSeeking, .publicProfile]
            case .mixed:
                return nil
            }

        case .capabilitySearch, .collaborationSearch:
            switch surfacePreference {
            case .affinity:
                return nil
            case .offer, .capability:
                return [.offer, .publicProfileCapability, .publicProfileSeeking, .publicProfile]
            case .mixed:
                return nil
            }

        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return nil
        }
    }

    var normalizedQueryText: String {
        queryText ?? ""
    }

    var normalizedSemanticText: String {
        semanticText ?? queryText ?? ""
    }

    /// Text embedded for the main semantic vector lane (never includes generated template boilerplate).
    var normalizedSemanticEmbeddingText: String {
        if let semanticEmbeddingText, !semanticEmbeddingText.isEmpty {
            return semanticEmbeddingText
        }
        if let semanticText, !semanticText.isEmpty {
            return semanticText
        }
        return queryText ?? ""
    }

    var hasSemanticSignal: Bool {
        !normalizedSemanticEmbeddingText.isEmpty
    }

    var hasLexicalSignal: Bool {
        !normalizedQueryText.isEmpty ||
        !providerTerms.isEmpty ||
        !capabilityTerms.isEmpty ||
        !affinityTerms.isEmpty ||
        !keywords.isEmpty
    }

    var allPositiveTerms: [String] {
        Self.normalizeTerms(
            providerTerms +
            capabilityTerms +
            affinityTerms +
            regionTerms +
            hardRegionIDs +
            softRegionTerms +
            commercialIntentTerms +
            timeTerms +
            keywords +
            [targetKind, fulfillmentMode].compactMap { $0 } +
            explicitHardConstraints.map(\.value) +
            queryEntities.map(\.normalizedText) +
            resolvedPlaces.map(\.normalizedText)
        )
    }

    var dominantTerms: [String] {
        switch surfacePreference {
        case .offer:
            return Self.normalizeTerms(providerTerms + keywords + softRegionTerms + commercialIntentTerms + timeTerms)
        case .capability:
            return Self.normalizeTerms(capabilityTerms + keywords + softRegionTerms + commercialIntentTerms + timeTerms)
        case .affinity:
            return Self.normalizeTerms(affinityTerms + keywords + softRegionTerms + commercialIntentTerms + timeTerms)
        case .mixed:
            return allPositiveTerms
        }
    }

    func withLimit(_ limit: Int) -> ExchangeRetrievalQuery {
        var copy = self
        copy.limit = max(1, limit)
        return copy
    }
}

private extension ExchangeRetrievalQuery {
    static func normalizeTerms(_ values: [String]) -> [String] {
        Array(
            Set(
                values.compactMap {
                    $0
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .nilIfEmpty
                }
            )
        )
        .sorted()
    }

    static func normalizeConstraints(
        _ values: [ExchangeIntent.Constraint]
    ) -> [ExchangeIntent.Constraint] {
        var seen = Set<String>()
        var output: [ExchangeIntent.Constraint] = []

        for item in values {
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard !key.isEmpty, !value.isEmpty else { continue }

            let dedupe = "\(key)|||\(value)|||\(item.isHardConstraint)"
            guard !seen.contains(dedupe) else { continue }

            seen.insert(dedupe)
            output.append(
                ExchangeIntent.Constraint(
                    id: item.id,
                    key: String(item.key.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
                    value: String(item.value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
                    isHardConstraint: item.isHardConstraint
                )
            )
        }

        return output
    }

    static func normalizeEntities(_ values: [ExchangeQueryEntity]) -> [ExchangeQueryEntity] {
        var seen = Set<String>()
        var output: [ExchangeQueryEntity] = []

        for entity in values {
            let key = "\(entity.kind.rawValue)||\(entity.normalizedText)"
            guard !entity.normalizedText.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(entity)
        }

        return output
    }

    static func normalizeResolvedPlaces(_ values: [ExchangeResolvedPlace]) -> [ExchangeResolvedPlace] {
        var seen = Set<String>()
        var output: [ExchangeResolvedPlace] = []

        for place in values {
            let key = "\(place.canonicalID.lowercased())||\(place.normalizedText)"
            guard !place.normalizedText.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(place)
        }

        return output
    }
}

private extension String {
    var exchangeTrimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
