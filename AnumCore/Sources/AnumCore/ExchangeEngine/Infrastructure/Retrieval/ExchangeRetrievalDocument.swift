import Foundation

/// Search/index document used by the retrieval layer.
///
/// Important:
/// - This is NOT a core domain entity.
/// - It is a flattened retrieval projection.
/// - One counterparty may yield multiple retrieval documents.
/// - Surface type matters and must be preserved explicitly.
public struct ExchangeRetrievalDocument: Sendable, Hashable, Identifiable, Codable {
    public typealias ID = String

    public enum EntityType: String, Sendable, Hashable, Codable, CaseIterable {
        case publicProfile
        case offer
    }

    public enum SurfaceType: Sendable, Hashable {
        case offer
        /// Generic public-profile retrieval row (federation directory wire value `publicProfile`).
        case publicProfile
        case publicProfileCapability
        case publicProfileSeeking
        case publicProfileAffinity
        /// Future or unrecognized `surfaceType` wire string — not a semantic public profile.
        case unknown(String)
    }

    public enum SourceKind: String, Sendable, Hashable, Codable, CaseIterable {
        case local
        case remote
    }

    /// Retrieval document provenance. Older documents omit this field.
    public enum DocKind: String, Sendable, Hashable, Codable, CaseIterable {
        case offerObject = "offer_object"
        case offerDetail = "offer_detail"
        case offerPackage = "offer_package"
        case offerFAQ = "offer_faq"
        case offer = "offer"
        case profileIntro = "profile_intro"
        case profileCapability = "profile_capability"
        case profileAbout = "profile_about"
        case profileAffinity = "profile_affinity"
        case profileSeeking = "profile_seeking"
    }

    public let id: ID

    /// Durable owning node / counterparty identity.
    public let counterpartyID: String
    public let nodeID: String?

    /// Public surface anchors.
    public let publicProfileID: String?
    public let offerID: String?

    public let entityType: EntityType
    public let surfaceType: SurfaceType
    public let sourceKind: SourceKind
    /// When present, identifies which retrieval lane produced this document.
    public let docKind: DocKind?
    /// Optional source field hint (for example `offer_object`).
    public let sourceField: String?

    /// Hard/operational posture metadata.
    public let visibility: String?
    public let availability: String?
    public let accessMode: String?
    public let acceptingInbound: Bool?
    public let routeableOnly: Bool?

    /// Retrieval-facing surface fields.
    public let title: String
    public let summary: String?
    public let category: String?
    public let tags: [String]
    public let regionTags: [String]
    public let canonicalRegionIDs: [String]
    public let regionAliases: [String]
    public let parentRegionIDs: [String]
    /// Declared provider service areas (optional H3 in `spatial`; never copied into lexical fields).
    public let serviceAreas: [ExchangeDeclaredServiceArea]

    /// Split searchable fields.
    public let primaryText: String
    public let secondaryText: String
    public let lexicalText: String
    public let semanticText: String
    /// When set, embedding and BM25 exclude raw display-language title/summary/lexical fields.
    public let canonicalEnglishRetrievalText: String?

    /// Surface-specific term families.
    public let providerTerms: [String]
    public let capabilityTerms: [String]
    public let affinityTerms: [String]
    public let filterTokens: [String]

    /// Optional embedding payload.
    public let embedding: [Float]?

    public let updatedAt: Date

    public init(
        id: ID,
        counterpartyID: String,
        nodeID: String? = nil,
        publicProfileID: String? = nil,
        offerID: String? = nil,
        entityType: EntityType,
        surfaceType: SurfaceType,
        sourceKind: SourceKind,
        docKind: DocKind? = nil,
        sourceField: String? = nil,
        visibility: String? = nil,
        availability: String? = nil,
        accessMode: String? = nil,
        acceptingInbound: Bool? = nil,
        routeableOnly: Bool? = nil,
        title: String,
        summary: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        regionTags: [String] = [],
        canonicalRegionIDs: [String] = [],
        regionAliases: [String] = [],
        parentRegionIDs: [String] = [],
        serviceAreas: [ExchangeDeclaredServiceArea] = [],
        primaryText: String = "",
        secondaryText: String = "",
        lexicalText: String,
        semanticText: String = "",
        canonicalEnglishRetrievalText: String? = nil,
        providerTerms: [String] = [],
        capabilityTerms: [String] = [],
        affinityTerms: [String] = [],
        filterTokens: [String] = [],
        embedding: [Float]? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id.exchangeTrimmedNonEmpty ?? UUID().uuidString
        self.counterpartyID = counterpartyID.exchangeTrimmedNonEmpty ?? counterpartyID
        self.nodeID = nodeID?.exchangeTrimmedNonEmpty
        self.publicProfileID = publicProfileID?.exchangeTrimmedNonEmpty
        self.offerID = offerID?.exchangeTrimmedNonEmpty
        self.entityType = entityType
        self.surfaceType = surfaceType
        self.sourceKind = sourceKind
        self.docKind = docKind
        self.sourceField = sourceField?.exchangeTrimmedNonEmpty
        self.visibility = visibility?.exchangeTrimmedNonEmpty?.lowercased()
        self.availability = availability?.exchangeTrimmedNonEmpty?.lowercased()
        self.accessMode = accessMode?.exchangeTrimmedNonEmpty?.lowercased()
        self.acceptingInbound = acceptingInbound
        self.routeableOnly = routeableOnly
        self.title = title.exchangeTrimmedNonEmpty ?? "Untitled"
        self.summary = summary?.exchangeTrimmedNonEmpty
        self.category = category?.exchangeTrimmedNonEmpty?.lowercased()
        self.tags = Self.normalizeTerms(tags)
        self.regionTags = Self.normalizeTerms(regionTags)
        self.canonicalRegionIDs = Self.normalizeTerms(canonicalRegionIDs)
        self.regionAliases = Self.normalizeTerms(regionAliases)
        self.parentRegionIDs = Self.normalizeTerms(parentRegionIDs)
        self.serviceAreas = serviceAreas
        self.primaryText = Self.normalizeWhitespace(primaryText)
        self.secondaryText = Self.normalizeWhitespace(secondaryText)
        self.lexicalText = Self.normalizeWhitespace(lexicalText)
        self.semanticText = Self.normalizeWhitespace(semanticText)
        self.canonicalEnglishRetrievalText = canonicalEnglishRetrievalText?.exchangeTrimmedNonEmpty
        self.providerTerms = Self.normalizeTerms(providerTerms)
        self.capabilityTerms = Self.normalizeTerms(capabilityTerms)
        self.affinityTerms = Self.normalizeTerms(affinityTerms)
        self.filterTokens = Self.normalizeTerms(filterTokens)
        self.embedding = embedding
        self.updatedAt = updatedAt
    }
}

extension ExchangeRetrievalDocument.SurfaceType {
    /// Federation / local store wire string. Unknown surfaces round-trip the original wire value.
    public var rawValue: String {
        switch self {
        case .offer:
            return "offer"
        case .publicProfile:
            return "publicProfile"
        case .publicProfileCapability:
            return "publicProfileCapability"
        case .publicProfileSeeking:
            return "publicProfileSeeking"
        case .publicProfileAffinity:
            return "publicProfileAffinity"
        case .unknown(let wire):
            return wire
        }
    }

    /// Decodes directory `surfaceType` JSON. Unrecognized non-empty values become ``unknown(_:)`` (DEBUG-logged).
    public static func decodingWire(_ raw: String) -> Self {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "offer":
            return .offer
        case "publicProfile":
            return .publicProfile
        case "publicProfileCapability":
            return .publicProfileCapability
        case "publicProfileSeeking":
            return .publicProfileSeeking
        case "publicProfileAffinity":
            return .publicProfileAffinity
        default:
            #if DEBUG
            if !trimmed.isEmpty {
                Swift.print("[ExchangeRetrievalDocument] unknown surfaceType wire=\(trimmed)")
            }
            #endif
            return .unknown(trimmed)
        }
    }
}

extension ExchangeRetrievalDocument.SurfaceType: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        self = Self.decodingWire(raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Codable
//
// Federation directory JSON historically could include `counterpartyID: null` on retrieval
// documents while `nodeID` is present. Decode coerces a non-empty counterparty identity so
// directory search decoding does not fail the entire response.
extension ExchangeRetrievalDocument {
    enum CodingKeys: String, CodingKey {
        case id
        case counterpartyID
        case nodeID
        case publicProfileID
        case offerID
        case entityType
        case surfaceType
        case sourceKind
        case docKind
        case sourceField
        case visibility
        case availability
        case accessMode
        case acceptingInbound
        case routeableOnly
        case title
        case summary
        case category
        case tags
        case regionTags
        case canonicalRegionIDs
        case regionAliases
        case parentRegionIDs
        case serviceAreas
        case primaryText
        case secondaryText
        case lexicalText
        case semanticText
        case canonicalEnglishRetrievalText
        case providerTerms
        case capabilityTerms
        case affinityTerms
        case filterTokens
        case embedding
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let nodeID = try c.decodeIfPresent(String.self, forKey: .nodeID)
        let counterpartyRaw = try c.decodeIfPresent(String.self, forKey: .counterpartyID)
        let resolvedCounterparty: String = {
            if let t = counterpartyRaw?.exchangeTrimmedNonEmpty { return t }
            if let t = nodeID?.exchangeTrimmedNonEmpty { return t }
            if let t = id.exchangeTrimmedNonEmpty { return t }
            return id
        }()

        let publicProfileID = try c.decodeIfPresent(String.self, forKey: .publicProfileID)
        let offerID = try c.decodeIfPresent(String.self, forKey: .offerID)

        let entityRaw = try c.decodeIfPresent(String.self, forKey: .entityType) ?? EntityType.publicProfile.rawValue
        let entityType = EntityType(rawValue: entityRaw) ?? .publicProfile

        let surfaceRaw = try c.decode(String.self, forKey: .surfaceType)
        let surfaceType = SurfaceType.decodingWire(surfaceRaw)

        let sourceRaw = try c.decodeIfPresent(String.self, forKey: .sourceKind) ?? SourceKind.remote.rawValue
        let sourceKind = SourceKind(rawValue: sourceRaw) ?? .remote

        let docKindRaw = try c.decodeIfPresent(String.self, forKey: .docKind)
        let docKind = docKindRaw.flatMap { DocKind(rawValue: $0) }
        let sourceField = try c.decodeIfPresent(String.self, forKey: .sourceField)

        let visibility = try c.decodeIfPresent(String.self, forKey: .visibility)
        let availability = try c.decodeIfPresent(String.self, forKey: .availability)
        let accessMode = try c.decodeIfPresent(String.self, forKey: .accessMode)
        let acceptingInbound = try c.decodeIfPresent(Bool.self, forKey: .acceptingInbound)
        let routeableOnly = try c.decodeIfPresent(Bool.self, forKey: .routeableOnly)

        let title = try c.decode(String.self, forKey: .title)
        let summary = try c.decodeIfPresent(String.self, forKey: .summary)
        let category = try c.decodeIfPresent(String.self, forKey: .category)
        let tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        let regionTags = try c.decodeIfPresent([String].self, forKey: .regionTags) ?? []
        let canonicalRegionIDs = try c.decodeIfPresent([String].self, forKey: .canonicalRegionIDs) ?? []
        let regionAliases = try c.decodeIfPresent([String].self, forKey: .regionAliases) ?? []
        let parentRegionIDs = try c.decodeIfPresent([String].self, forKey: .parentRegionIDs) ?? []
        let serviceAreas = try c.decodeIfPresent([ExchangeDeclaredServiceArea].self, forKey: .serviceAreas) ?? []

        let primaryText = try c.decodeIfPresent(String.self, forKey: .primaryText) ?? ""
        let secondaryText = try c.decodeIfPresent(String.self, forKey: .secondaryText) ?? ""
        let lexicalText = try c.decodeIfPresent(String.self, forKey: .lexicalText) ?? ""
        let semanticText = try c.decodeIfPresent(String.self, forKey: .semanticText) ?? ""
        let canonicalEnglishRetrievalText = try c.decodeIfPresent(String.self, forKey: .canonicalEnglishRetrievalText)

        let providerTerms = try c.decodeIfPresent([String].self, forKey: .providerTerms) ?? []
        let capabilityTerms = try c.decodeIfPresent([String].self, forKey: .capabilityTerms) ?? []
        let affinityTerms = try c.decodeIfPresent([String].self, forKey: .affinityTerms) ?? []
        let filterTokens = try c.decodeIfPresent([String].self, forKey: .filterTokens) ?? []

        let embedding = try c.decodeIfPresent([Float].self, forKey: .embedding)
        let updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        self.init(
            id: id,
            counterpartyID: resolvedCounterparty,
            nodeID: nodeID,
            publicProfileID: publicProfileID,
            offerID: offerID,
            entityType: entityType,
            surfaceType: surfaceType,
            sourceKind: sourceKind,
            docKind: docKind,
            sourceField: sourceField,
            visibility: visibility,
            availability: availability,
            accessMode: accessMode,
            acceptingInbound: acceptingInbound,
            routeableOnly: routeableOnly,
            title: title,
            summary: summary,
            category: category,
            tags: tags,
            regionTags: regionTags,
            canonicalRegionIDs: canonicalRegionIDs,
            regionAliases: regionAliases,
            parentRegionIDs: parentRegionIDs,
            serviceAreas: serviceAreas,
            primaryText: primaryText,
            secondaryText: secondaryText,
            lexicalText: lexicalText,
            semanticText: semanticText,
            canonicalEnglishRetrievalText: canonicalEnglishRetrievalText,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms,
            filterTokens: filterTokens,
            embedding: embedding,
            updatedAt: updatedAt
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(counterpartyID, forKey: .counterpartyID)
        try c.encodeIfPresent(nodeID, forKey: .nodeID)
        try c.encodeIfPresent(publicProfileID, forKey: .publicProfileID)
        try c.encodeIfPresent(offerID, forKey: .offerID)
        try c.encode(entityType.rawValue, forKey: .entityType)
        try c.encode(surfaceType.rawValue, forKey: .surfaceType)
        try c.encode(sourceKind.rawValue, forKey: .sourceKind)
        try c.encodeIfPresent(docKind?.rawValue, forKey: .docKind)
        try c.encodeIfPresent(sourceField, forKey: .sourceField)
        try c.encodeIfPresent(visibility, forKey: .visibility)
        try c.encodeIfPresent(availability, forKey: .availability)
        try c.encodeIfPresent(accessMode, forKey: .accessMode)
        try c.encodeIfPresent(acceptingInbound, forKey: .acceptingInbound)
        try c.encodeIfPresent(routeableOnly, forKey: .routeableOnly)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encode(tags, forKey: .tags)
        try c.encode(regionTags, forKey: .regionTags)
        try c.encode(canonicalRegionIDs, forKey: .canonicalRegionIDs)
        try c.encode(regionAliases, forKey: .regionAliases)
        try c.encode(parentRegionIDs, forKey: .parentRegionIDs)
        if !serviceAreas.isEmpty {
            try c.encode(serviceAreas, forKey: .serviceAreas)
        }
        try c.encode(primaryText, forKey: .primaryText)
        try c.encode(secondaryText, forKey: .secondaryText)
        try c.encode(lexicalText, forKey: .lexicalText)
        try c.encode(semanticText, forKey: .semanticText)
        try c.encodeIfPresent(canonicalEnglishRetrievalText, forKey: .canonicalEnglishRetrievalText)
        try c.encode(providerTerms, forKey: .providerTerms)
        try c.encode(capabilityTerms, forKey: .capabilityTerms)
        try c.encode(affinityTerms, forKey: .affinityTerms)
        try c.encode(filterTokens, forKey: .filterTokens)
        try c.encodeIfPresent(embedding, forKey: .embedding)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

public extension ExchangeRetrievalDocument {
    var primarySurfaceID: String? {
        offerID ?? publicProfileID
    }
    
    var ownerNodeID: String {
        nodeID ?? counterpartyID
    }

    var embeddingDimension: Int {
        embedding?.count ?? 0
    }

    var hasUsableEmbedding: Bool {
        embeddingDimension > 0
    }

    var documentText: String {
        [
            primaryText,
            secondaryText,
            lexicalText,
            semanticText,
            searchableText
        ]
        .compactMap { $0.exchangeTrimmedNonEmpty }
        .joined(separator: " ")
    }

    var isOfferObjectDocument: Bool {
        docKind == .offerObject
    }

    var isOfferDocument: Bool {
        surfaceType == .offer
    }

    var isCapabilityDocument: Bool {
        surfaceType == .publicProfileCapability
    }

    var isSeekingDocument: Bool {
        surfaceType == .publicProfileSeeking
    }

    var isAffinityDocument: Bool {
        surfaceType == .publicProfileAffinity
    }

    var isProfileDocument: Bool {
        entityType == .publicProfile
    }

    var hasEmbedding: Bool {
        guard let embedding else { return false }
        return !embedding.isEmpty
    }

    var searchableText: String {
        if usesEnglishOnlyRetrievalProjection {
            return englishOnlySearchableParts()
        }
        return [
            title,
            summary,
            category,
            primaryText,
            secondaryText,
            lexicalText,
            semanticText,
            tags.joined(separator: " "),
            regionTags.joined(separator: " "),
            regionAliases.joined(separator: " "),
            providerTerms.joined(separator: " "),
            capabilityTerms.joined(separator: " "),
            affinityTerms.joined(separator: " ")
        ]
        .compactMap { $0?.exchangeTrimmedNonEmpty }
        .joined(separator: " ")
    }

    private func englishOnlySearchableParts() -> String {
        let english = canonicalEnglishRetrievalText?.exchangeTrimmedNonEmpty ?? ""
        return [
            english,
            semanticText,
            category,
            tags.joined(separator: " "),
            regionTags.joined(separator: " "),
            regionAliases.joined(separator: " "),
            providerTerms.joined(separator: " "),
            capabilityTerms.joined(separator: " "),
            affinityTerms.joined(separator: " "),
            filterTokens.joined(separator: " ")
        ]
        .compactMap { $0?.exchangeTrimmedNonEmpty }
        .joined(separator: " ")
    }

    var allFilterTokens: [String] {
        Self.normalizeTerms(
            filterTokens +
            tags +
            regionTags +
            regionAliases +
            providerTerms +
            capabilityTerms +
            affinityTerms +
            [category].compactMap { $0 }
        )
    }

    var dominantTerms: [String] {
        switch surfaceType {
        case .offer:
            return Self.normalizeTerms(providerTerms + tags + [category].compactMap { $0 })
        case .publicProfile:
            return Self.normalizeTerms(
                capabilityTerms + affinityTerms + tags + [category].compactMap { $0 }
            )
        case .publicProfileCapability:
            return Self.normalizeTerms(capabilityTerms + tags)
        case .publicProfileSeeking:
            return Self.normalizeTerms(capabilityTerms + tags)
        case .publicProfileAffinity:
            return Self.normalizeTerms(affinityTerms + tags)
        case .unknown:
            return Self.normalizeTerms(
                capabilityTerms + affinityTerms + tags + [category].compactMap { $0 }
            )
        }
    }

    func updatingEmbedding(_ embedding: [Float]?) -> ExchangeRetrievalDocument {
        ExchangeRetrievalDocument(
            id: id,
            counterpartyID: counterpartyID,
            nodeID: nodeID,
            publicProfileID: publicProfileID,
            offerID: offerID,
            entityType: entityType,
            surfaceType: surfaceType,
            sourceKind: sourceKind,
            docKind: docKind,
            sourceField: sourceField,
            visibility: visibility,
            availability: availability,
            accessMode: accessMode,
            acceptingInbound: acceptingInbound,
            routeableOnly: routeableOnly,
            title: title,
            summary: summary,
            category: category,
            tags: tags,
            regionTags: regionTags,
            canonicalRegionIDs: canonicalRegionIDs,
            regionAliases: regionAliases,
            parentRegionIDs: parentRegionIDs,
            primaryText: primaryText,
            secondaryText: secondaryText,
            lexicalText: lexicalText,
            semanticText: semanticText,
            canonicalEnglishRetrievalText: canonicalEnglishRetrievalText,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms,
            filterTokens: filterTokens,
            embedding: embedding,
            updatedAt: updatedAt
        )
    }
}

private extension ExchangeRetrievalDocument {
    static func normalizeTerms(_ values: [String]) -> [String] {
        Array(
            Set(
                values.compactMap { $0.exchangeTrimmedNonEmpty?.lowercased() }
            )
        )
        .sorted()
    }

    static func normalizeWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

private extension String {
    var exchangeTrimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
