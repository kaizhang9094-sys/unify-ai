import Foundation

/// Deterministic per-slice text for retrieval document construction (no synonym expansion).
public struct ExchangeIndexedProviderRetrievalSlices: Sendable, Hashable, Codable {
    public var identityBlocks: [String]
    /// Publisher intro slice: display name and headline only.
    public var introBlocks: [String]
    /// Publisher about slice: summary, background, approach, activity/exclusion context.
    public var aboutBlocks: [String]
    public var capabilityBlocks: [String]
    public var seekingBlocks: [String]
    public var affinityBlocks: [String]
    public var regionBlocks: [String]
    public var seekingTerms: [String]

    public init(
        identityBlocks: [String] = [],
        introBlocks: [String] = [],
        aboutBlocks: [String] = [],
        capabilityBlocks: [String] = [],
        seekingBlocks: [String] = [],
        affinityBlocks: [String] = [],
        regionBlocks: [String] = [],
        seekingTerms: [String] = []
    ) {
        self.identityBlocks = identityBlocks
        self.introBlocks = introBlocks
        self.aboutBlocks = aboutBlocks
        self.capabilityBlocks = capabilityBlocks
        self.seekingBlocks = seekingBlocks
        self.affinityBlocks = affinityBlocks
        self.regionBlocks = regionBlocks
        self.seekingTerms = seekingTerms
    }

    enum CodingKeys: String, CodingKey {
        case identityBlocks
        case introBlocks
        case aboutBlocks
        case capabilityBlocks
        case seekingBlocks
        case affinityBlocks
        case regionBlocks
        case seekingTerms
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identityBlocks = try c.decodeIfPresent([String].self, forKey: .identityBlocks) ?? []
        introBlocks = try c.decodeIfPresent([String].self, forKey: .introBlocks) ?? []
        aboutBlocks = try c.decodeIfPresent([String].self, forKey: .aboutBlocks) ?? []
        capabilityBlocks = try c.decodeIfPresent([String].self, forKey: .capabilityBlocks) ?? []
        seekingBlocks = try c.decodeIfPresent([String].self, forKey: .seekingBlocks) ?? []
        affinityBlocks = try c.decodeIfPresent([String].self, forKey: .affinityBlocks) ?? []
        regionBlocks = try c.decodeIfPresent([String].self, forKey: .regionBlocks) ?? []
        seekingTerms = try c.decodeIfPresent([String].self, forKey: .seekingTerms) ?? []
    }
}

/// Descriptive package slice for publisher-side `offer_package` docs (no price).
public struct ExchangeIndexedOfferPackageSlice: Codable, Sendable, Hashable {
    public var stableKey: String
    public var title: String
    public var summary: String?
    public var descriptiveText: String

    public init(
        stableKey: String,
        title: String,
        summary: String? = nil,
        descriptiveText: String
    ) {
        self.stableKey = stableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        self.descriptiveText = descriptiveText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// FAQ slice for publisher-side `offer_faq` docs.
public struct ExchangeIndexedOfferFAQSlice: Codable, Sendable, Hashable {
    public var stableKey: String
    public var question: String
    public var answer: String

    public init(stableKey: String, question: String, answer: String) {
        self.stableKey = stableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        self.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ExchangeIndexedProviderSurface: Codable, Sendable, Hashable, Identifiable {
    public typealias SchemaVersion = Int

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
        public var allowedModes: [String]
        public var allowedIntentKinds: [String]
        public var allowedAudienceKinds: [String]
        public var minimumTrustLevel: String?
        public var requiresCategoryMatch: Bool
        public var requiresMutualFit: Bool
        public var contactHints: [String]

        public init(
            accessMode: String,
            acceptingInbound: Bool,
            disclosureCeiling: String,
            routeableOnly: Bool,
            intentCategoryPolicy: String,
            allowedModes: [String] = [],
            allowedIntentKinds: [String] = [],
            allowedAudienceKinds: [String] = [],
            minimumTrustLevel: String? = nil,
            requiresCategoryMatch: Bool = false,
            requiresMutualFit: Bool = false,
            contactHints: [String] = []
        ) {
            self.accessMode = accessMode
            self.acceptingInbound = acceptingInbound
            self.disclosureCeiling = disclosureCeiling
            self.routeableOnly = routeableOnly
            self.intentCategoryPolicy = intentCategoryPolicy
            self.allowedModes = allowedModes
            self.allowedIntentKinds = allowedIntentKinds
            self.allowedAudienceKinds = allowedAudienceKinds
            self.minimumTrustLevel = minimumTrustLevel
            self.requiresCategoryMatch = requiresCategoryMatch
            self.requiresMutualFit = requiresMutualFit
            self.contactHints = contactHints
        }
    }

    public struct CommercialConstraint: Codable, Sendable, Hashable {
        public var text: String
        public var isHard: Bool

        public init(text: String, isHard: Bool = false) {
            self.text = text
            self.isHard = isHard
        }
    }

    public struct TimeAvailabilityConstraint: Codable, Sendable, Hashable {
        public var text: String
        public var isHard: Bool

        public init(text: String, isHard: Bool = false) {
            self.text = text
            self.isHard = isHard
        }
    }

    public var id: String
    public var publicProfileID: String
    public var nodeID: String
    public var displayName: String?
    public var headline: String?
    public var summary: String?
    public var visibility: String
    public var availability: String
    public var regions: RegionEvidence
    public var providerTerms: [String]
    public var capabilityTerms: [String]
    public var affinityTerms: [String]
    public var broadRecallTokens: [String]
    public var semanticConcepts: [String]
    public var hardConstraints: [String]
    public var softPreferences: [String]
    public var commercialConstraints: [CommercialConstraint]
    public var timeAvailabilityConstraints: [TimeAvailabilityConstraint]
    public var reachability: ReachabilitySummary
    public var offers: [ExchangeIndexedOfferSurface]
    public var sourceTextBlocks: [String]
    /// Normalized English retrieval carrier; excludes raw display language from embed/BM25 when set.
    public var canonicalEnglishRetrievalText: String?
    /// When set, retrieval documents use slice-specific text instead of reusing `sourceTextBlocks` everywhere.
    public var retrievalSlices: ExchangeIndexedProviderRetrievalSlices?
    public var updatedAt: Date
    public var schemaVersion: SchemaVersion

    public init(
        id: String,
        publicProfileID: String,
        nodeID: String,
        displayName: String? = nil,
        headline: String? = nil,
        summary: String? = nil,
        visibility: String,
        availability: String,
        regions: RegionEvidence = .init(),
        providerTerms: [String] = [],
        capabilityTerms: [String] = [],
        affinityTerms: [String] = [],
        broadRecallTokens: [String] = [],
        semanticConcepts: [String] = [],
        hardConstraints: [String] = [],
        softPreferences: [String] = [],
        commercialConstraints: [CommercialConstraint] = [],
        timeAvailabilityConstraints: [TimeAvailabilityConstraint] = [],
        reachability: ReachabilitySummary,
        offers: [ExchangeIndexedOfferSurface] = [],
        sourceTextBlocks: [String] = [],
        canonicalEnglishRetrievalText: String? = nil,
        retrievalSlices: ExchangeIndexedProviderRetrievalSlices? = nil,
        updatedAt: Date = Date(),
        schemaVersion: SchemaVersion = 1
    ) {
        self.id = id
        self.publicProfileID = publicProfileID
        self.nodeID = nodeID
        self.displayName = displayName
        self.headline = headline
        self.summary = summary
        self.visibility = visibility
        self.availability = availability
        self.regions = regions
        self.providerTerms = providerTerms
        self.capabilityTerms = capabilityTerms
        self.affinityTerms = affinityTerms
        self.broadRecallTokens = broadRecallTokens
        self.semanticConcepts = semanticConcepts
        self.hardConstraints = hardConstraints
        self.softPreferences = softPreferences
        self.commercialConstraints = commercialConstraints
        self.timeAvailabilityConstraints = timeAvailabilityConstraints
        self.reachability = reachability
        self.offers = offers
        self.sourceTextBlocks = sourceTextBlocks
        self.canonicalEnglishRetrievalText = canonicalEnglishRetrievalText
        self.retrievalSlices = retrievalSlices
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }
}

public struct ExchangeIndexedOfferSurface: Codable, Sendable, Hashable, Identifiable {
    public typealias SchemaVersion = Int

    public struct CommercialConstraint: Codable, Sendable, Hashable {
        public var text: String
        public var isHard: Bool

        public init(text: String, isHard: Bool = false) {
            self.text = text
            self.isHard = isHard
        }
    }

    public struct TimeAvailabilityConstraint: Codable, Sendable, Hashable {
        public var text: String
        public var isHard: Bool

        public init(text: String, isHard: Bool = false) {
            self.text = text
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
            self.pricingMode = pricingMode
            self.commitmentMode = commitmentMode
            self.remoteFriendly = remoteFriendly
            self.leadTimeNote = leadTimeNote
            self.capacityNote = capacityNote
            self.serviceAreaNote = serviceAreaNote
        }
    }

    public var id: String
    public var offerID: String
    public var title: String
    public var summary: String?
    public var category: String?
    public var freeTextCategory: String?
    public var providerTerms: [String]
    /// Offer-owned object identity only: title, category, tags, serviceKinds.
    public var objectIdentityTerms: [String]?
    public var capabilityTerms: [String]
    public var affinityTerms: [String]
    public var broadRecallTokens: [String]
    public var semanticConcepts: [String]
    /// Descriptive offer detail for `offer_detail` embedding (summary and semantic notes only).
    public var descriptiveDetailBlocks: [String]?
    public var packageSlices: [ExchangeIndexedOfferPackageSlice]
    public var faqSlices: [ExchangeIndexedOfferFAQSlice]
    public var hardConstraints: [String]
    public var softPreferences: [String]
    public var commercialConstraints: [CommercialConstraint]
    public var fulfillment: FulfillmentSummary
    public var timeAvailabilityConstraints: [TimeAvailabilityConstraint]
    public var contactOrPolicyText: [String]
    public var sourceTextBlocks: [String]
    public var canonicalEnglishRetrievalText: String?
    /// Declared service geography copied from the source offer for retrieval/H3 locality.
    public var serviceAreas: [ExchangeDeclaredServiceArea]
    public var visibility: String
    public var status: String
    public var updatedAt: Date
    public var schemaVersion: SchemaVersion

    public init(
        id: String,
        offerID: String,
        title: String,
        summary: String? = nil,
        category: String? = nil,
        freeTextCategory: String? = nil,
        providerTerms: [String] = [],
        objectIdentityTerms: [String]? = nil,
        capabilityTerms: [String] = [],
        affinityTerms: [String] = [],
        broadRecallTokens: [String] = [],
        semanticConcepts: [String] = [],
        descriptiveDetailBlocks: [String]? = nil,
        packageSlices: [ExchangeIndexedOfferPackageSlice] = [],
        faqSlices: [ExchangeIndexedOfferFAQSlice] = [],
        hardConstraints: [String] = [],
        softPreferences: [String] = [],
        commercialConstraints: [CommercialConstraint] = [],
        fulfillment: FulfillmentSummary,
        timeAvailabilityConstraints: [TimeAvailabilityConstraint] = [],
        contactOrPolicyText: [String] = [],
        sourceTextBlocks: [String] = [],
        canonicalEnglishRetrievalText: String? = nil,
        serviceAreas: [ExchangeDeclaredServiceArea] = [],
        visibility: String,
        status: String,
        updatedAt: Date = Date(),
        schemaVersion: SchemaVersion = 1
    ) {
        self.id = id
        self.offerID = offerID
        self.title = title
        self.summary = summary
        self.category = category
        self.freeTextCategory = freeTextCategory
        self.providerTerms = providerTerms
        self.objectIdentityTerms = objectIdentityTerms
        self.capabilityTerms = capabilityTerms
        self.affinityTerms = affinityTerms
        self.broadRecallTokens = broadRecallTokens
        self.semanticConcepts = semanticConcepts
        self.descriptiveDetailBlocks = descriptiveDetailBlocks
        self.packageSlices = packageSlices
        self.faqSlices = faqSlices
        self.hardConstraints = hardConstraints
        self.softPreferences = softPreferences
        self.commercialConstraints = commercialConstraints
        self.fulfillment = fulfillment
        self.timeAvailabilityConstraints = timeAvailabilityConstraints
        self.contactOrPolicyText = contactOrPolicyText
        self.sourceTextBlocks = sourceTextBlocks
        self.canonicalEnglishRetrievalText = canonicalEnglishRetrievalText
        self.serviceAreas = serviceAreas
        self.visibility = visibility
        self.status = status
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }
}
