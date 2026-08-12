import Foundation

/// Boundary for discovering counterparties from a directory source,
/// and for publishing node-owned outward-facing surfaces to the thin federation layer.
///
/// This can later be backed by:
/// - local indexed directory
/// - remote network directory
/// - hybrid source ranking
///
/// Important:
/// This is a discovery / publication boundary only.
/// It should not send thread messages, mutate thread state, or own trust graph state.
///
/// Discovery should return path-aware, consent-aware candidates describing:
/// - who the counterparty is
/// - what their public posture allows
/// - whether they are discoverable
/// - whether they are routeable
/// - whether direct contact is allowed
/// - whether introduction is required
///
/// Publication supports two outward-facing projections:
/// 1. seller surface projection:
///    - public profile
///    - public offers
///    - outward posture / visibility / availability
/// 2. retrieval document projection:
///    - flattened retrieval docs
///    - embeddings included when available
///
/// It must never be treated as private node-state sync.
public protocol ExchangeDirectoryClient: Sendable {
    func search(_ request: ExchangeDirectorySearchRequest) async throws -> ExchangeDirectorySearchResponse

    func publishSellerSurface(
        _ request: ExchangeSellerSurfacePublishRequest
    ) async throws -> ExchangeSellerSurfacePublishResponse

    func unpublishSellerSurface(
        nodeID: String,
        publicProfileID: String
    ) async throws -> ExchangeSellerSurfaceUnpublishResponse

    func publishRetrievalDocuments(
        _ request: ExchangeRetrievalDocumentPublishRequest
    ) async throws -> ExchangeRetrievalDocumentPublishResponse

    /// Uploads an explicitly public image for a profile or offer, returning a public HTTPS URL.
    ///
    /// This is intentionally narrow:
    /// - The endpoint is expected to host only explicitly public, published media.
    /// - The local node owns what it publishes; the URL is referenced by
    ///   `ExchangePublicNodeProfile.primaryImageURL` or `ExchangeOffer.primaryImageURL`.
    /// - Implementations should throw a readable error on missing endpoint, non-2xx
    ///   responses, or missing `imageURL` in the response. Callers must remain compilable
    ///   and operational when this throws (text save/publish flow continues).
    ///
    /// - Parameters:
    ///   - data: Already-resized/compressed image bytes (JPEG/PNG/HEIC).
    ///   - mimeType: MIME type, e.g. "image/jpeg".
    ///   - nodeID: Owner node ID.
    ///   - role: Either "primaryProfile" or "primaryOffer".
    ///   - publicProfileID: Optional owning profile id.
    ///   - offerID: Optional owning offer id.
    /// - Returns: Public HTTPS URL string.
    func uploadPublicMedia(
        data: Data,
        mimeType: String,
        nodeID: String,
        role: String,
        publicProfileID: String?,
        offerID: String?
    ) async throws -> String

    /// Deletes remote public media for the authenticated node. Non-throwing for expected outcomes.
    func deletePublicMedia(storageKey: String, nodeID: String) async -> ExchangePublicMediaDeleteOutcome
}

public extension ExchangeDirectoryClient {
    /// Default implementation throws so existing test/mocks remain source-compatible.
    func uploadPublicMedia(
        data: Data,
        mimeType: String,
        nodeID: String,
        role: String,
        publicProfileID: String?,
        offerID: String?
    ) async throws -> String {
        throw ExchangeDirectoryClientError.backendFailure(
            reason: "Media upload is not supported by this directory client."
        )
    }

    func deletePublicMedia(storageKey: String, nodeID: String) async -> ExchangePublicMediaDeleteOutcome {
        .failed(reason: "Media delete is not supported by this directory client.")
    }
}

public struct ExchangeDirectorySearchRequest: Codable, Sendable, Hashable {
    public var threadID: ExchangeThread.ID?
    public var localNodeID: String?

    public var mode: ExchangeMode
    public var intentKind: ExchangeIntent.Kind

    public var targetDescription: String?
    public var queryText: String?
    public var tags: [String]

    /// Optional higher-level public intent cues for posture-aware discovery.
    public var openToTags: [String]
    public var offerTags: [String]
    public var excludedTags: [String]
    public var regionTags: [String]

    public var trustFloor: ExchangeCounterparty.TrustSnapshot.Level?
    public var statuses: [ExchangeCounterparty.Status]
    public var limit: Int

    /// Whether discovery should prefer already-trusted or trust-adjacent nodes first.
    public var trustPreference: TrustPreference

    /// Controls whether search should stay local, remote, or allow hybrid behavior.
    public var scope: Scope

    /// Technical routeability requirement.
    public var routeRequirement: RouteRequirement

    /// Whether discovery must respect recipient-side access posture.
    public var accessRequirement: AccessRequirement

    /// Whether discovery must respect a disclosure ceiling.
    public var disclosureRequirement: DisclosureRequirement
    
    public var queryEmbedding: [Float]?

    /// Optional federation directory debug: restrict recall to rows containing this token (non-production or `DIRECTORY_DEBUG_SEED_ONLY` on server).
    public var debugRecallToken: String?
    /// Optional shorthand for the For You dev seed recall token filter (`fydevdirectoryseed`).
    public var debugSeedOnly: Bool?

    /// Controls whether the federation server returns candidate doc embeddings for client-side reranking.
    public var retrievalResponseMode: RetrievalResponseMode?

    public init(
        threadID: ExchangeThread.ID? = nil,
        localNodeID: String? = nil,
        mode: ExchangeMode,
        intentKind: ExchangeIntent.Kind,
        targetDescription: String? = nil,
        queryText: String? = nil,
        queryEmbedding: [Float]? = nil,
        tags: [String] = [],
        openToTags: [String] = [],
        offerTags: [String] = [],
        excludedTags: [String] = [],
        regionTags: [String] = [],
        trustFloor: ExchangeCounterparty.TrustSnapshot.Level? = nil,
        statuses: [ExchangeCounterparty.Status] = [.active],
        limit: Int = 12,
        trustPreference: TrustPreference = .neutral,
        scope: Scope = .hybridAllowed,
        routeRequirement: RouteRequirement = .any,
        accessRequirement: AccessRequirement = .discoverableOnly,
        disclosureRequirement: DisclosureRequirement = .any,
        debugRecallToken: String? = nil,
        debugSeedOnly: Bool? = nil,
        retrievalResponseMode: RetrievalResponseMode? = nil
    ) {
        self.threadID = threadID
        self.localNodeID = localNodeID?.nilIfBlank
        self.mode = mode
        self.intentKind = intentKind
        self.targetDescription = targetDescription?.nilIfBlank
        self.queryText = queryText?.nilIfBlank
        self.queryEmbedding = queryEmbedding?.isEmpty == true ? nil : queryEmbedding
        self.tags = Self.normalizeTags(tags)
        self.openToTags = Self.normalizeTags(openToTags)
        self.offerTags = Self.normalizeTags(offerTags)
        self.excludedTags = Self.normalizeTags(excludedTags)
        self.regionTags = Self.normalizeTags(regionTags)
        self.trustFloor = trustFloor
        self.statuses = statuses
        self.limit = max(1, limit)
        self.trustPreference = trustPreference
        self.scope = scope
        self.routeRequirement = routeRequirement
        self.accessRequirement = accessRequirement
        self.disclosureRequirement = disclosureRequirement
        self.debugRecallToken = debugRecallToken?.nilIfBlank
        self.debugSeedOnly = debugSeedOnly
        self.retrievalResponseMode = retrievalResponseMode
    }

    public enum RetrievalResponseMode: String, Codable, Sendable, CaseIterable, Hashable {
        /// Server may strip embeddings; node-level preview only.
        case preview
        /// Server returns candidate retrieval docs/hits with embeddings for client final ranking.
        case clientRerank
    }

    public enum TrustPreference: String, Codable, Sendable, CaseIterable, Hashable {
        case neutral
        case preferTrusted
        case requireTrustedOrTrustAdjacent
    }

    public enum Scope: String, Codable, Sendable, CaseIterable, Hashable {
        case localOnly
        case remoteOnly
        case hybridAllowed
    }

    public enum RouteRequirement: String, Codable, Sendable, CaseIterable, Hashable {
        case any
        case federationCapableOnly
        case routeableOnly
    }

    public enum AccessRequirement: String, Codable, Sendable, CaseIterable, Hashable {
        /// Return anything discoverable, even if direct contact is not allowed.
        case discoverableOnly

        /// Return only candidates that are routeable in principle.
        case routeableOnly

        /// Return only candidates that allow direct first contact in principle.
        case directContactAllowedOnly

        /// Return only candidates that require introduction / trusted path.
        case introductionRequiredOnly
    }

    public enum DisclosureRequirement: String, Codable, Sendable, CaseIterable, Hashable {
        case any
        case minimalOrLower
        case balancedOrLower
        case openAllowed
    }
}

public struct ExchangeDirectorySearchResponse: Codable, Sendable, Hashable {
    public var matches: [ExchangeDirectoryMatch]
    public var source: Source
    public var summary: String?
    public var searchedAt: Date

    /// Whether the source applied trust-aware ranking.
    public var trustAwareRankingApplied: Bool

    public init(
        matches: [ExchangeDirectoryMatch],
        source: Source,
        summary: String? = nil,
        searchedAt: Date = Date(),
        trustAwareRankingApplied: Bool = false
    ) {
        self.matches = matches
        self.source = source
        self.summary = summary?.nilIfBlank
        self.searchedAt = searchedAt
        self.trustAwareRankingApplied = trustAwareRankingApplied
    }

    public enum Source: String, Codable, Sendable, CaseIterable, Hashable {
        case local
        case remote
        case hybrid
    }
}

/// Outward-facing seller surface projection sent from a node to federation.
/// This is intentionally public-only and must never contain private node state.
public struct ExchangePublishedSellerSurfacePayload: Codable, Sendable, Hashable {
    public struct IndexedProviderSurfaceProjection: Codable, Sendable, Hashable {
        public struct RegionEvidence: Codable, Sendable, Hashable {
            public var regionTags: [String]
            public var canonicalRegionIDs: [String]
            public var parentRegionIDs: [String]
            public var regionAliases: [String]
            public var serviceAreaNotes: [String]

            public init(
                regionTags: [String] = [],
                canonicalRegionIDs: [String] = [],
                parentRegionIDs: [String] = [],
                regionAliases: [String] = [],
                serviceAreaNotes: [String] = []
            ) {
                self.regionTags = regionTags
                self.canonicalRegionIDs = canonicalRegionIDs
                self.parentRegionIDs = parentRegionIDs
                self.regionAliases = regionAliases
                self.serviceAreaNotes = serviceAreaNotes
            }
        }

        public struct ReachabilitySummary: Codable, Sendable, Hashable {
            public var accessMode: String
            public var acceptingInbound: Bool
            public var disclosureCeiling: String
            public var routeableOnly: Bool
            public var intentCategoryPolicy: String

            public init(
                accessMode: String,
                acceptingInbound: Bool,
                disclosureCeiling: String,
                routeableOnly: Bool,
                intentCategoryPolicy: String
            ) {
                self.accessMode = accessMode.trimmingCharacters(in: .whitespacesAndNewlines)
                self.acceptingInbound = acceptingInbound
                self.disclosureCeiling = disclosureCeiling.trimmingCharacters(in: .whitespacesAndNewlines)
                self.routeableOnly = routeableOnly
                self.intentCategoryPolicy = intentCategoryPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        public struct CommercialConstraint: Codable, Sendable, Hashable {
            public var text: String
            public var isHard: Bool

            public init(text: String, isHard: Bool = false) {
                self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.isHard = isHard
            }
        }

        public struct TimeAvailabilityConstraint: Codable, Sendable, Hashable {
            public var text: String
            public var isHard: Bool

            public init(text: String, isHard: Bool = false) {
                self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.isHard = isHard
            }
        }

        public var schemaVersion: Int
        public var semanticConcepts: [String]
        public var broadRecallTokens: [String]
        public var hardConstraints: [String]
        public var softPreferences: [String]
        public var commercialConstraints: [CommercialConstraint]
        public var timeAvailabilityConstraints: [TimeAvailabilityConstraint]
        public var sourceTextBlocks: [String]
        public var regions: RegionEvidence
        public var reachability: ReachabilitySummary?
        public var updatedAt: Date?

        public init(
            schemaVersion: Int,
            semanticConcepts: [String] = [],
            broadRecallTokens: [String] = [],
            hardConstraints: [String] = [],
            softPreferences: [String] = [],
            commercialConstraints: [CommercialConstraint] = [],
            timeAvailabilityConstraints: [TimeAvailabilityConstraint] = [],
            sourceTextBlocks: [String] = [],
            regions: RegionEvidence = .init(),
            reachability: ReachabilitySummary? = nil,
            updatedAt: Date? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.semanticConcepts = semanticConcepts
            self.broadRecallTokens = broadRecallTokens
            self.hardConstraints = hardConstraints
            self.softPreferences = softPreferences
            self.commercialConstraints = commercialConstraints
            self.timeAvailabilityConstraints = timeAvailabilityConstraints
            self.sourceTextBlocks = sourceTextBlocks
            self.regions = regions
            self.reachability = reachability
            self.updatedAt = updatedAt
        }
    }

    public struct IndexedOfferSurfaceProjection: Codable, Sendable, Hashable {
        public struct CommercialConstraint: Codable, Sendable, Hashable {
            public var text: String
            public var isHard: Bool

            public init(text: String, isHard: Bool = false) {
                self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.isHard = isHard
            }
        }

        public struct TimeAvailabilityConstraint: Codable, Sendable, Hashable {
            public var text: String
            public var isHard: Bool

            public init(text: String, isHard: Bool = false) {
                self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.isHard = isHard
            }
        }

        public struct FulfillmentSummary: Codable, Sendable, Hashable {
            public var pricingMode: String
            public var commitmentMode: String
            public var remoteFriendly: Bool
            public var leadTimeNote: String?
            public var capacityNote: String?
            public var serviceAreaNote: String?

            public init(
                pricingMode: String,
                commitmentMode: String,
                remoteFriendly: Bool,
                leadTimeNote: String? = nil,
                capacityNote: String? = nil,
                serviceAreaNote: String? = nil
            ) {
                self.pricingMode = pricingMode.trimmingCharacters(in: .whitespacesAndNewlines)
                self.commitmentMode = commitmentMode.trimmingCharacters(in: .whitespacesAndNewlines)
                self.remoteFriendly = remoteFriendly
                self.leadTimeNote = leadTimeNote?.nilIfBlank
                self.capacityNote = capacityNote?.nilIfBlank
                self.serviceAreaNote = serviceAreaNote?.nilIfBlank
            }
        }

        public var offerID: String
        public var schemaVersion: Int
        public var semanticConcepts: [String]
        public var broadRecallTokens: [String]
        public var hardConstraints: [String]
        public var softPreferences: [String]
        public var commercialConstraints: [CommercialConstraint]
        public var timeAvailabilityConstraints: [TimeAvailabilityConstraint]
        public var fulfillment: FulfillmentSummary?
        public var sourceTextBlocks: [String]
        public var visibility: String?
        public var status: String?
        public var updatedAt: Date?

        public init(
            offerID: String,
            schemaVersion: Int,
            semanticConcepts: [String] = [],
            broadRecallTokens: [String] = [],
            hardConstraints: [String] = [],
            softPreferences: [String] = [],
            commercialConstraints: [CommercialConstraint] = [],
            timeAvailabilityConstraints: [TimeAvailabilityConstraint] = [],
            fulfillment: FulfillmentSummary? = nil,
            sourceTextBlocks: [String] = [],
            visibility: String? = nil,
            status: String? = nil,
            updatedAt: Date? = nil
        ) {
            self.offerID = offerID.trimmingCharacters(in: .whitespacesAndNewlines)
            self.schemaVersion = schemaVersion
            self.semanticConcepts = semanticConcepts
            self.broadRecallTokens = broadRecallTokens
            self.hardConstraints = hardConstraints
            self.softPreferences = softPreferences
            self.commercialConstraints = commercialConstraints
            self.timeAvailabilityConstraints = timeAvailabilityConstraints
            self.fulfillment = fulfillment
            self.sourceTextBlocks = sourceTextBlocks
            self.visibility = visibility?.nilIfBlank
            self.status = status?.nilIfBlank
            self.updatedAt = updatedAt
        }
    }

    public struct PublishedOffer: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var summary: String?
        public var category: String?
        public var tags: [String]
        public var regionTags: [String]
        public var visibility: String
        public var semantic: [String: [String]]
        public var fulfillment: [String: String]
        /// Optional HTTPS URL for this offer's primary public image.
        public var primaryImageURL: String?
        /// Additional offer image URLs after ``primaryImageURL`` (deduped, max four when primary is set).
        public var galleryImageURLs: [String]
        /// v1.5 structured commercial surface (optional for older publishers).
        public var commercialFacts: ExchangeOffer.CommercialFacts?
        /// v1.6 structured offer contact info (optional and public-only).
        public var contactInfo: ExchangeOffer.ContactInfo?
        /// Declared service areas with optional H3 footprints (omitted on wire when empty).
        public var serviceAreas: [ExchangeDeclaredServiceArea]

        public init(
            id: String,
            title: String,
            summary: String? = nil,
            category: String? = nil,
            tags: [String] = [],
            regionTags: [String] = [],
            visibility: String,
            semantic: [String: [String]] = [:],
            fulfillment: [String: String] = [:],
            primaryImageURL: String? = nil,
            galleryImageURLs: [String] = [],
            commercialFacts: ExchangeOffer.CommercialFacts? = nil,
            contactInfo: ExchangeOffer.ContactInfo? = nil,
            serviceAreas: [ExchangeDeclaredServiceArea] = []
        ) {
            self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.summary = summary?.nilIfBlank
            self.category = category?.nilIfBlank
            self.tags = Self.normalizeTags(tags)
            self.regionTags = Self.normalizeTags(regionTags)
            self.visibility = visibility.trimmingCharacters(in: .whitespacesAndNewlines)
            self.semantic = semantic
            self.fulfillment = fulfillment
            self.primaryImageURL = primaryImageURL?.nilIfBlank
            self.galleryImageURLs = ExchangeOffer.normalizedGalleryStorage(
                primary: self.primaryImageURL,
                gallery: galleryImageURLs
            )
            self.commercialFacts = commercialFacts
            self.contactInfo = contactInfo
            self.serviceAreas = serviceAreas
        }

        private static func normalizeTags(_ values: [String]) -> [String] {
            Array(
                Set(
                    values
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        .filter { !$0.isEmpty }
                )
            ).sorted()
        }
    }

    public struct PublicProfileProjection: Codable, Sendable, Hashable {
        public struct Reachability: Codable, Sendable, Hashable {
            public var acceptingInbound: Bool
            public var accessMode: String
            public var disclosureCeiling: String
            public var routeableOnly: Bool
            public var intentCategoryPolicy: String

            public init(
                acceptingInbound: Bool,
                accessMode: String,
                disclosureCeiling: String,
                routeableOnly: Bool,
                intentCategoryPolicy: String = ExchangePublicNodeProfile.ReachabilityPolicy.IntentCategoryPolicy.broad.rawValue
            ) {
                self.acceptingInbound = acceptingInbound
                self.accessMode = accessMode.trimmingCharacters(in: .whitespacesAndNewlines)
                self.disclosureCeiling = disclosureCeiling.trimmingCharacters(in: .whitespacesAndNewlines)
                self.routeableOnly = routeableOnly

                let trimmedPolicy = intentCategoryPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
                self.intentCategoryPolicy = trimmedPolicy.isEmpty
                    ? ExchangePublicNodeProfile.ReachabilityPolicy.IntentCategoryPolicy.broad.rawValue
                    : trimmedPolicy
            }
        }

        public var id: String
        public var displayName: String?
        public var headline: String?
        public var summary: String?
        public var visibility: String
        public var availability: String
        public var interests: [String]
        public var offers: [String]
        public var openTo: [String]
        public var excludedTopics: [String]
        public var activityTags: [String]
        public var regionTags: [String]
        public var semantic: [String: [String]]
        public var reachability: Reachability
        /// Optional HTTPS URL for this profile's primary public image.
        public var primaryImageURL: String?
        /// Public cosmetic supporter frame (presentation only).
        public var publicSupporterPresentation: ExchangeSupporterPresentation?

        public init(
            id: String,
            displayName: String? = nil,
            headline: String? = nil,
            summary: String? = nil,
            visibility: String,
            availability: String,
            interests: [String] = [],
            offers: [String] = [],
            openTo: [String] = [],
            excludedTopics: [String] = [],
            activityTags: [String] = [],
            regionTags: [String] = [],
            semantic: [String: [String]] = [:],
            reachability: Reachability,
            primaryImageURL: String? = nil,
            publicSupporterPresentation: ExchangeSupporterPresentation? = nil
        ) {
            self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
            self.displayName = displayName?.nilIfBlank
            self.headline = headline?.nilIfBlank
            self.summary = summary?.nilIfBlank
            self.visibility = visibility.trimmingCharacters(in: .whitespacesAndNewlines)
            self.availability = availability.trimmingCharacters(in: .whitespacesAndNewlines)
            self.interests = Self.normalizeTags(interests)
            self.offers = Self.normalizeTags(offers)
            self.openTo = Self.normalizeTags(openTo)
            self.excludedTopics = Self.normalizeTags(excludedTopics)
            self.activityTags = Self.normalizeTags(activityTags)
            self.regionTags = Self.normalizeTags(regionTags)
            self.semantic = semantic
            self.reachability = reachability
            self.primaryImageURL = primaryImageURL?.nilIfBlank
            self.publicSupporterPresentation = publicSupporterPresentation
        }

        private static func normalizeTags(_ values: [String]) -> [String] {
            Array(
                Set(
                    values
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        .filter { !$0.isEmpty }
                )
            ).sorted()
        }
    }

    public var nodeID: String
    public var displayName: String?
    public var publicProfile: PublicProfileProjection
    public var offers: [PublishedOffer]
    public var indexedSurfaceVersion: Int?
    public var indexedProviderSurface: IndexedProviderSurfaceProjection?
    public var indexedOffers: [IndexedOfferSurfaceProjection]?
    public var publishedAt: Date
    public var fingerprint: String?

    public init(
        nodeID: String,
        displayName: String? = nil,
        publicProfile: PublicProfileProjection,
        offers: [PublishedOffer],
        indexedSurfaceVersion: Int? = nil,
        indexedProviderSurface: IndexedProviderSurfaceProjection? = nil,
        indexedOffers: [IndexedOfferSurfaceProjection]? = nil,
        publishedAt: Date,
        fingerprint: String? = nil
    ) {
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName?.nilIfBlank
        self.publicProfile = publicProfile
        self.offers = offers
        self.indexedSurfaceVersion = indexedSurfaceVersion
        self.indexedProviderSurface = indexedProviderSurface
        self.indexedOffers = indexedOffers
        self.publishedAt = publishedAt
        self.fingerprint = fingerprint?.nilIfBlank
    }
}

extension ExchangePublishedSellerSurfacePayload.PublishedOffer {
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case category
        case tags
        case regionTags
        case visibility
        case semantic
        case fulfillment
        case primaryImageURL
        case galleryImageURLs
        case commercialFacts
        case contactInfo
        case serviceAreas
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        regionTags = try container.decodeIfPresent([String].self, forKey: .regionTags) ?? []
        visibility = try container.decode(String.self, forKey: .visibility)
        semantic = try container.decodeIfPresent([String: [String]].self, forKey: .semantic) ?? [:]
        fulfillment = try container.decodeIfPresent([String: String].self, forKey: .fulfillment) ?? [:]
        primaryImageURL = try container.decodeIfPresent(String.self, forKey: .primaryImageURL)
        galleryImageURLs = try container.decodeIfPresent([String].self, forKey: .galleryImageURLs) ?? []
        commercialFacts = try container.decodeIfPresent(ExchangeOffer.CommercialFacts.self, forKey: .commercialFacts)
        contactInfo = try container.decodeIfPresent(ExchangeOffer.ContactInfo.self, forKey: .contactInfo)
        serviceAreas = try container.decodeIfPresent([ExchangeDeclaredServiceArea].self, forKey: .serviceAreas) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encode(regionTags, forKey: .regionTags)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(semantic, forKey: .semantic)
        try container.encode(fulfillment, forKey: .fulfillment)
        try container.encodeIfPresent(primaryImageURL, forKey: .primaryImageURL)
        try container.encode(galleryImageURLs, forKey: .galleryImageURLs)
        try container.encodeIfPresent(commercialFacts, forKey: .commercialFacts)
        try container.encodeIfPresent(contactInfo, forKey: .contactInfo)
        if !serviceAreas.isEmpty {
            try container.encode(serviceAreas, forKey: .serviceAreas)
        }
    }
}

public struct ExchangeSellerSurfacePublishRequest: Codable, Sendable, Hashable {
    public var nodeID: String
    public var displayName: String?
    public var surface: ExchangePublishedSellerSurfacePayload

    public init(
        nodeID: String,
        displayName: String? = nil,
        surface: ExchangePublishedSellerSurfacePayload
    ) {
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName?.nilIfBlank
        self.surface = surface
    }
}

public struct ExchangeSellerSurfacePublishResponse: Codable, Sendable, Hashable {
    public var ok: Bool
    public var remoteProfileID: String
    public var remoteOfferIDs: [String]
    public var publishedAt: Date
    public var note: String?

    public init(
        ok: Bool,
        remoteProfileID: String,
        remoteOfferIDs: [String],
        publishedAt: Date,
        note: String? = nil
    ) {
        self.ok = ok
        self.remoteProfileID = remoteProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.remoteOfferIDs = Array(
            Set(
                remoteOfferIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
        self.publishedAt = publishedAt
        self.note = note?.nilIfBlank
    }
}

public struct ExchangeSellerSurfaceUnpublishResponse: Codable, Sendable, Hashable {
    public var ok: Bool
    public var nodeID: String
    public var publicProfileID: String
    public var unpublishedAt: Date
    public var note: String?

    public init(
        ok: Bool,
        nodeID: String,
        publicProfileID: String,
        unpublishedAt: Date,
        note: String? = nil
    ) {
        self.ok = ok
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.publicProfileID = publicProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.unpublishedAt = unpublishedAt
        self.note = note?.nilIfBlank
    }
}

/// Retrieval document publication sent from a node to federation.
///
/// This is retrieval infrastructure projection only.
/// It should contain already-built retrieval documents, including embeddings when available.
/// It must not be treated as private runtime state sync.
public struct ExchangeRetrievalDocumentPublishRequest: Codable, Sendable, Hashable {
    public var nodeID: String
    public var sourceKind: ExchangeRetrievalDocument.SourceKind
    public var documents: [ExchangeRetrievalDocument]
    public var replaceAll: Bool
    public var publishedAt: Date

    public init(
        nodeID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind,
        documents: [ExchangeRetrievalDocument],
        replaceAll: Bool = true,
        publishedAt: Date = Date()
    ) {
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceKind = sourceKind
        self.documents = documents
        self.replaceAll = replaceAll
        self.publishedAt = publishedAt
    }
}

public struct ExchangeRetrievalDocumentPublishResponse: Codable, Sendable, Hashable {
    public var ok: Bool
    public var nodeID: String
    public var sourceKind: ExchangeRetrievalDocument.SourceKind
    public var acceptedDocumentCount: Int
    public var publishedAt: Date
    public var note: String?

    public init(
        ok: Bool,
        nodeID: String,
        sourceKind: ExchangeRetrievalDocument.SourceKind,
        acceptedDocumentCount: Int,
        publishedAt: Date,
        note: String? = nil
    ) {
        self.ok = ok
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceKind = sourceKind
        self.acceptedDocumentCount = max(0, acceptedDocumentCount)
        self.publishedAt = publishedAt
        self.note = note?.nilIfBlank
    }
}

/// Federation directory search vector lane metadata (no raw embeddings).
public struct ExchangeDirectoryVectorSignals: Codable, Sendable, Hashable {
    public var queryEmbeddingDims: Int?
    public var vectorSimilarity: Double?
    public var vectorScore: Double?
    public var vectorRank: Int?
    public var vectorHitCount: Int
    public var embeddingAvailable: Bool
    public var bestVectorRetrievalDocID: String?
    public var bestVectorSurfaceType: String?
    public var vectorSource: String?

    enum CodingKeys: String, CodingKey {
        case queryEmbeddingDims
        case queryEmbeddingDimsSnake = "query_embedding_dims"
        case vectorSimilarity
        case vectorSimilaritySnake = "vector_similarity"
        case vectorScore
        case vectorScoreSnake = "vector_score"
        case vectorRank
        case vectorRankSnake = "vector_rank"
        case vectorHitCount
        case vectorHitCountSnake = "vector_hit_count"
        case embeddingAvailable
        case embeddingAvailableSnake = "embedding_available"
        case bestVectorRetrievalDocID
        case bestVectorRetrievalDocIDSnake = "best_vector_retrieval_doc_id"
        case bestVectorSurfaceType
        case bestVectorSurfaceTypeSnake = "best_vector_surface_type"
        case vectorSource
        case vectorSourceSnake = "vector_source"
    }

    public init(
        queryEmbeddingDims: Int? = nil,
        vectorSimilarity: Double? = nil,
        vectorScore: Double? = nil,
        vectorRank: Int? = nil,
        vectorHitCount: Int = 0,
        embeddingAvailable: Bool = false,
        bestVectorRetrievalDocID: String? = nil,
        bestVectorSurfaceType: String? = nil,
        vectorSource: String? = nil
    ) {
        self.queryEmbeddingDims = queryEmbeddingDims
        self.vectorSimilarity = vectorSimilarity
        self.vectorScore = vectorScore
        self.vectorRank = vectorRank
        self.vectorHitCount = vectorHitCount
        self.embeddingAvailable = embeddingAvailable
        self.bestVectorRetrievalDocID = bestVectorRetrievalDocID?.nilIfBlank
        self.bestVectorSurfaceType = bestVectorSurfaceType?.nilIfBlank
        self.vectorSource = vectorSource?.nilIfBlank
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        queryEmbeddingDims = try c.decodeIfPresent(Int.self, forKey: .queryEmbeddingDims)
            ?? c.decodeIfPresent(Int.self, forKey: .queryEmbeddingDimsSnake)
        vectorSimilarity = try c.decodeIfPresent(Double.self, forKey: .vectorSimilarity)
            ?? c.decodeIfPresent(Double.self, forKey: .vectorSimilaritySnake)
        vectorScore = try c.decodeIfPresent(Double.self, forKey: .vectorScore)
            ?? c.decodeIfPresent(Double.self, forKey: .vectorScoreSnake)
        vectorRank = try c.decodeIfPresent(Int.self, forKey: .vectorRank)
            ?? c.decodeIfPresent(Int.self, forKey: .vectorRankSnake)
        vectorHitCount = try c.decodeIfPresent(Int.self, forKey: .vectorHitCount)
            ?? c.decodeIfPresent(Int.self, forKey: .vectorHitCountSnake)
            ?? 0
        embeddingAvailable = try c.decodeIfPresent(Bool.self, forKey: .embeddingAvailable)
            ?? c.decodeIfPresent(Bool.self, forKey: .embeddingAvailableSnake)
            ?? false
        let bestDoc = try c.decodeIfPresent(String.self, forKey: .bestVectorRetrievalDocID)
            ?? c.decodeIfPresent(String.self, forKey: .bestVectorRetrievalDocIDSnake)
        bestVectorRetrievalDocID = bestDoc?.nilIfBlank
        let bestSurf = try c.decodeIfPresent(String.self, forKey: .bestVectorSurfaceType)
            ?? c.decodeIfPresent(String.self, forKey: .bestVectorSurfaceTypeSnake)
        bestVectorSurfaceType = bestSurf?.nilIfBlank
        let src = try c.decodeIfPresent(String.self, forKey: .vectorSource)
            ?? c.decodeIfPresent(String.self, forKey: .vectorSourceSnake)
        vectorSource = src?.nilIfBlank
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(queryEmbeddingDims, forKey: .queryEmbeddingDims)
        try c.encodeIfPresent(vectorSimilarity, forKey: .vectorSimilarity)
        try c.encodeIfPresent(vectorScore, forKey: .vectorScore)
        try c.encodeIfPresent(vectorRank, forKey: .vectorRank)
        try c.encode(vectorHitCount, forKey: .vectorHitCount)
        try c.encode(embeddingAvailable, forKey: .embeddingAvailable)
        try c.encodeIfPresent(bestVectorRetrievalDocID, forKey: .bestVectorRetrievalDocID)
        try c.encodeIfPresent(bestVectorSurfaceType, forKey: .bestVectorSurfaceType)
        try c.encodeIfPresent(vectorSource, forKey: .vectorSource)
    }
}

/// Per-document retrieval hit metadata from federation directory search (Phase 3B+).
public struct ExchangeDirectoryRetrievalHit: Codable, Sendable, Hashable {
    public var retrievalDocID: String?
    public var nodeID: String?
    public var docKind: ExchangeRetrievalDocument.DocKind?
    public var sourceField: String?
    public var surfaceType: String?
    public var entityType: String?
    public var offerID: String?
    public var publicProfileID: String?
    public var title: String?
    public var lexicalScore: Double?
    public var vectorSimilarity: Double?
    public var retrievalScore: Double?
    public var matchedTerms: [String]
    /// Candidate document embedding when the server is in client rerank mode.
    public var embedding: [Float]?

    enum CodingKeys: String, CodingKey {
        case retrievalDocID
        case nodeID
        case docKind
        case sourceField
        case surfaceType
        case entityType
        case offerID
        case publicProfileID
        case title
        case lexicalScore
        case vectorSimilarity
        case retrievalScore
        case matchedTerms
        case embedding
    }

    public init(
        retrievalDocID: String? = nil,
        nodeID: String? = nil,
        docKind: ExchangeRetrievalDocument.DocKind? = nil,
        sourceField: String? = nil,
        surfaceType: String? = nil,
        entityType: String? = nil,
        offerID: String? = nil,
        publicProfileID: String? = nil,
        title: String? = nil,
        lexicalScore: Double? = nil,
        vectorSimilarity: Double? = nil,
        retrievalScore: Double? = nil,
        matchedTerms: [String] = [],
        embedding: [Float]? = nil
    ) {
        self.retrievalDocID = retrievalDocID?.nilIfBlank
        self.nodeID = nodeID?.nilIfBlank
        self.docKind = docKind
        self.sourceField = sourceField?.nilIfBlank
        self.surfaceType = surfaceType?.nilIfBlank
        self.entityType = entityType?.nilIfBlank
        self.offerID = offerID?.nilIfBlank
        self.publicProfileID = publicProfileID?.nilIfBlank
        self.title = title?.nilIfBlank
        self.lexicalScore = lexicalScore
        self.vectorSimilarity = vectorSimilarity
        self.retrievalScore = retrievalScore
        self.matchedTerms = matchedTerms
        self.embedding = embedding?.isEmpty == true ? nil : embedding
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        retrievalDocID = try container.decodeIfPresent(String.self, forKey: .retrievalDocID)?.nilIfBlank
        nodeID = try container.decodeIfPresent(String.self, forKey: .nodeID)?.nilIfBlank
        if let rawKind = try container.decodeIfPresent(String.self, forKey: .docKind)?.nilIfBlank {
            docKind = ExchangeRetrievalDocument.DocKind(rawValue: rawKind)
        } else {
            docKind = nil
        }
        sourceField = try container.decodeIfPresent(String.self, forKey: .sourceField)?.nilIfBlank
        surfaceType = try container.decodeIfPresent(String.self, forKey: .surfaceType)?.nilIfBlank
        entityType = try container.decodeIfPresent(String.self, forKey: .entityType)?.nilIfBlank
        offerID = try container.decodeIfPresent(String.self, forKey: .offerID)?.nilIfBlank
        publicProfileID = try container.decodeIfPresent(String.self, forKey: .publicProfileID)?.nilIfBlank
        title = try container.decodeIfPresent(String.self, forKey: .title)?.nilIfBlank
        lexicalScore = try container.decodeIfPresent(Double.self, forKey: .lexicalScore)
        vectorSimilarity = try container.decodeIfPresent(Double.self, forKey: .vectorSimilarity)
        retrievalScore = try container.decodeIfPresent(Double.self, forKey: .retrievalScore)
        matchedTerms = try container.decodeIfPresent([String].self, forKey: .matchedTerms) ?? []
        embedding = try container.decodeIfPresent([Float].self, forKey: .embedding)
        if embedding?.isEmpty == true {
            embedding = nil
        }
    }
}

/// Consent-aware directory result.
///
/// This wraps the entity record with public posture and reachability preview,
/// so discovery can return a path candidate rather than just an entity hit.
public struct ExchangeDirectoryMatch: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = String

    public var id: ID
    public var counterparty: ExchangeCounterparty
    public var publicProfile: ExchangePublicNodeProfile?
    public var offers: [ExchangeOffer]

    /// Retrieval documents returned by the directory source.
    ///
    /// Important:
    /// - For remote federation search, these are the original public retrieval
    ///   documents pushed by the publishing node/server.
    /// - They may already contain embeddings.
    /// - Local retrieval ingestion should preserve them instead of rebuilding
    ///   fresh unembedded documents from only profile/offers.
    public var retrievalDocuments: [ExchangeRetrievalDocument]

    public var reachability: ReachabilityPreview
    public var matchReason: String?
    public var matchedTerms: [String]
    public var score: Double?
    /// Server-provided vector lane metadata (no raw embeddings). Omitted on older directory payloads.
    public var vectorSignals: ExchangeDirectoryVectorSignals?
    /// Per-document retrieval hits when the directory backend provides them.
    public var retrievalHits: [ExchangeDirectoryRetrievalHit]
    /// Offer IDs proven only by retrieval document hits, not all hydrated offers.
    public var candidateOfferIDsFromDocs: [String]

    public init(
        id: ID? = nil,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile? = nil,
        offers: [ExchangeOffer] = [],
        retrievalDocuments: [ExchangeRetrievalDocument] = [],
        reachability: ReachabilityPreview,
        matchReason: String? = nil,
        matchedTerms: [String] = [],
        score: Double? = nil,
        vectorSignals: ExchangeDirectoryVectorSignals? = nil,
        retrievalHits: [ExchangeDirectoryRetrievalHit] = [],
        candidateOfferIDsFromDocs: [String] = []
    ) {
        self.id = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? counterparty.id
        self.counterparty = counterparty
        self.publicProfile = publicProfile
        self.offers = offers
        self.retrievalDocuments = Self.normalizedRetrievalDocuments(retrievalDocuments)
        self.reachability = reachability
        self.matchReason = matchReason?.nilIfBlank
        self.matchedTerms = Self.normalizeTerms(matchedTerms)
        self.score = score
        self.vectorSignals = vectorSignals
        self.retrievalHits = retrievalHits
        self.candidateOfferIDsFromDocs = Self.normalizeTerms(candidateOfferIDsFromDocs)
    }
}

public extension ExchangeDirectoryMatch {
    struct ReachabilityPreview: Codable, Sendable, Hashable {
        public enum AccessMode: String, Codable, Sendable, CaseIterable, Hashable {
            case unknown
            case direct
            case introPreferred
            case introRequired
            case closed
        }

        public enum DisclosureCeiling: String, Codable, Sendable, CaseIterable, Hashable {
            case unknown
            case minimal
            case balanced
            case open
        }

        public var isDiscoverable: Bool
        public var isRouteableInPrinciple: Bool
        public var allowsDirectContactInPrinciple: Bool
        public var requiresIntroductionInPrinciple: Bool

        public var accessMode: AccessMode
        public var disclosureCeiling: DisclosureCeiling

        /// Whether a technical route seems available from current directory knowledge.
        public var hasRouteHint: Bool

        public var summary: String?

        public init(
            isDiscoverable: Bool,
            isRouteableInPrinciple: Bool,
            allowsDirectContactInPrinciple: Bool,
            requiresIntroductionInPrinciple: Bool,
            accessMode: AccessMode = .unknown,
            disclosureCeiling: DisclosureCeiling = .unknown,
            hasRouteHint: Bool,
            summary: String? = nil
        ) {
            self.isDiscoverable = isDiscoverable
            self.isRouteableInPrinciple = isRouteableInPrinciple
            self.allowsDirectContactInPrinciple = allowsDirectContactInPrinciple
            self.requiresIntroductionInPrinciple = requiresIntroductionInPrinciple
            self.accessMode = accessMode
            self.disclosureCeiling = disclosureCeiling
            self.hasRouteHint = hasRouteHint
            self.summary = summary?.nilIfBlank
        }
    }

    static func fromCounterparty(
        _ counterparty: ExchangeCounterparty,
        offers: [ExchangeOffer] = [],
        retrievalDocuments: [ExchangeRetrievalDocument] = [],
        matchReason: String? = nil,
        matchedTerms: [String] = [],
        score: Double? = nil,
        vectorSignals: ExchangeDirectoryVectorSignals? = nil,
        retrievalHits: [ExchangeDirectoryRetrievalHit] = [],
        candidateOfferIDsFromDocs: [String] = []
    ) -> ExchangeDirectoryMatch {
        let profile = counterparty.publicProfile

        let accessMode: ReachabilityPreview.AccessMode
        if let profile {
            switch profile.reachability.accessMode {
            case .direct:
                accessMode = .direct
            case .introPreferred:
                accessMode = .introPreferred
            case .introRequired:
                accessMode = .introRequired
            case .closed:
                accessMode = .closed
            }
        } else {
            accessMode = .unknown
        }

        let disclosureCeiling: ReachabilityPreview.DisclosureCeiling
        if let profile {
            switch profile.reachability.disclosureCeiling {
            case .minimal:
                disclosureCeiling = .minimal
            case .balanced:
                disclosureCeiling = .balanced
            case .open:
                disclosureCeiling = .open
            }
        } else {
            disclosureCeiling = .unknown
        }

        let reachability = ReachabilityPreview(
            isDiscoverable: counterparty.isDiscoverable,
            isRouteableInPrinciple: counterparty.isRoutableInPrinciple,
            allowsDirectContactInPrinciple: counterparty.allowsDirectContactInPrinciple,
            requiresIntroductionInPrinciple: counterparty.requiresIntroductionInPrinciple,
            accessMode: accessMode,
            disclosureCeiling: disclosureCeiling,
            hasRouteHint: counterparty.hasAnyRoute,
            summary: profile?.summaryLine
        )

        return ExchangeDirectoryMatch(
            counterparty: counterparty,
            publicProfile: profile,
            offers: offers,
            retrievalDocuments: retrievalDocuments,
            reachability: reachability,
            matchReason: matchReason,
            matchedTerms: matchedTerms,
            score: score,
            vectorSignals: vectorSignals,
            retrievalHits: retrievalHits,
            candidateOfferIDsFromDocs: candidateOfferIDsFromDocs.isEmpty
                ? candidateOfferIDsFromDocsFromHits(retrievalHits)
                : candidateOfferIDsFromDocs
        )
    }

    private static func candidateOfferIDsFromDocsFromHits(
        _ hits: [ExchangeDirectoryRetrievalHit]
    ) -> [String] {
        Array(
            Set(
                hits.compactMap { $0.offerID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
            )
        ).sorted()
    }

    private static func normalizeTerms(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }
    
    private static func normalizedRetrievalDocuments(
        _ documents: [ExchangeRetrievalDocument]
    ) -> [ExchangeRetrievalDocument] {
        var byID: [String: ExchangeRetrievalDocument] = [:]

        for document in documents {
            let id = document.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            byID[id] = document
        }

        return byID.values.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.id < $1.id
        }
    }
}

public extension ExchangeDirectorySearchResponse {
    var resultCount: Int {
        matches.count
    }

    var offersByCounterpartyID: [String: [ExchangeOffer]] {
        var result: [String: [ExchangeOffer]] = [:]
        for match in matches {
            let nodeID = match.counterparty.id
            var offers = result[nodeID] ?? []
            var seenOfferIDs = Set(offers.map(\.id))
            for offer in match.offers {
                if seenOfferIDs.insert(offer.id).inserted {
                    offers.append(offer)
                }
            }
            result[nodeID] = offers
        }
        return result
    }

    /// Compatibility helper for older call sites while the rest of the codebase
    /// migrates from bare counterparties to richer directory matches.
    var counterparties: [ExchangeCounterparty] {
        matches.map(\.counterparty)
    }
}

public enum ExchangeDirectoryClientError: Error, Sendable, Hashable {
    case invalidRequest(reason: String)
    case unavailable(reason: String)
    case backendFailure(reason: String)
    case rateLimited(reason: String, retryAfterSeconds: Int?)
}

extension ExchangeDirectoryClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason):
            return reason
        case .unavailable(let reason):
            return reason
        case .backendFailure(let reason):
            return reason
        case .rateLimited(let reason, _):
            return reason
        }
    }

    public var failureReason: String? {
        switch self {
        case .invalidRequest(let reason):
            return reason
        case .unavailable(let reason):
            return reason
        case .backendFailure(let reason):
            return reason
        case .rateLimited(let reason, _):
            return reason
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidRequest:
            return "Check the request payload and try again."
        case .unavailable:
            return "Try again in a moment."
        case .backendFailure:
            return "Check the federation server response and client decoding."
        case .rateLimited:
            return "Wait briefly and try again."
        }
    }
}

private extension ExchangeDirectorySearchRequest {
    static func normalizeTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
