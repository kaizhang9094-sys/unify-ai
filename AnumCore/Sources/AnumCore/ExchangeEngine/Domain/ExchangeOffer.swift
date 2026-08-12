import Foundation

/// Durable public offering owned by a secretary node.
///
/// Design intent:
/// - node-owned, not marketplace-owned
/// - compact and publishable
/// - attachable to discovery, fit, and thread selection
/// - distinct from the broader public node profile
///
/// Important:
/// - `ExchangePublicNodeProfile` answers: who this node is publicly,
///   how it is reachable, and what broad posture it exposes
/// - `ExchangeOffer` answers: what this node is actively offering
/// - this should remain lightweight and legible, not become a giant catalog type
public struct ExchangeOffer: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = String

    public var id: ID
    public var nodeID: String

    /// Owning public profile basis.
    ///
    /// Offers should generally hang off a public seller surface rather than
    /// float independently as marketplace-style records.
    public var publicProfileID: ExchangePublicNodeProfile.ID?

    public var title: String
    public var summary: String?

    /// Coarse primary category.
    ///
    /// Example:
    /// - roofing
    /// - battery recycling
    /// - wholesale electronics
    /// - scheduling help
    public var category: String?

    /// Lightweight public tags for discovery and fit.
    public var tags: [String]

    /// Coarse region/place tags for routing and locality matching.
    public var regionTags: [String]

    /// Seller-declared service areas (authoritative for locality matching).
    /// `regionTags` is a wire-compatible projection of display names.
    public var serviceAreas: [ExchangeDeclaredServiceArea]

    /// Server-enriched canonical place IDs (additive; empty for legacy payloads).
    public var canonicalRegionIDs: [String]

    /// Broader region hierarchy IDs from the server (additive).
    public var parentRegionIDs: [String]

    /// Human / lexical region aliases from the server (additive).
    public var regionAliases: [String]

    /// Public semantic surface for this offer specifically.
    ///
    /// Keep this narrower than the broader public node profile semantic surface.
    public var semantic: SemanticSurface

    /// Fulfillment and commercial posture of the offer.
    public var fulfillment: Fulfillment

    /// Current operating state of this offer.
    public var status: Status

    /// Discovery visibility for this offer.
    public var visibility: Visibility

    public var createdAt: Date
    public var updatedAt: Date

    /// Optional HTTPS URL pointing to this offer's primary public image.
    /// Binary image data is never stored here — only a public URL reference.
    /// nil means no image has been published for this offer.
    public var primaryImageURL: String?

    /// Additional public offer images after ``primaryImageURL``, ordered, URL strings only.
    /// With ``primaryImageURL`` set, at most four extras (five images total). With no primary, up to five URLs may live here alone; use ``displayHeroImageURL`` / ``normalizedPublicOfferImageURLs()`` for presentation order.
    public var galleryImageURLs: [String]

    /// Small future-safe metadata only.
    public var metadata: [String: String]

    /// v1.5: structured public commercial copy (pricing posture, policies, intake, FAQ, automation bounds).
    public var commercialFacts: CommercialFacts
    /// Optional outward-facing contact details for this specific offer.
    /// Published only for active, outward-visible offers.
    public var contactInfo: ContactInfo?

    public init(
        id: ID,
        nodeID: String,
        publicProfileID: ExchangePublicNodeProfile.ID? = nil,
        title: String,
        summary: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        regionTags: [String] = [],
        serviceAreas: [ExchangeDeclaredServiceArea] = [],
        canonicalRegionIDs: [String] = [],
        parentRegionIDs: [String] = [],
        regionAliases: [String] = [],
        semantic: SemanticSurface = .init(),
        fulfillment: Fulfillment = .init(),
        status: Status = .draft,
        visibility: Visibility = .publicDiscoverable,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        primaryImageURL: String? = nil,
        galleryImageURLs: [String] = [],
        metadata: [String: String] = [:],
        commercialFacts: CommercialFacts = .empty,
        contactInfo: ContactInfo? = nil
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.publicProfileID = publicProfileID?.exchangeNilIfBlank
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary?.exchangeNilIfBlank
        self.category = category?.exchangeNilIfBlank
        self.tags = Self.normalizedTerms(tags)
        self.regionTags = Self.normalizedTerms(regionTags)
        self.serviceAreas = serviceAreas
        self.canonicalRegionIDs = Self.normalizedRegionTokens(canonicalRegionIDs)
        self.parentRegionIDs = Self.normalizedRegionTokens(parentRegionIDs)
        self.regionAliases = Self.normalizedRegionTokens(regionAliases)
        self.semantic = semantic.normalized()
        self.fulfillment = fulfillment.normalized()
        self.status = status
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        let trimmedPrimary = primaryImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).exchangeNilIfBlank
        self.primaryImageURL = trimmedPrimary
        self.galleryImageURLs = Self.normalizedGalleryStorage(primary: trimmedPrimary, gallery: galleryImageURLs)
        self.metadata = metadata
        self.commercialFacts = commercialFacts.normalized()
        if let normalizedContact = contactInfo?.normalized(), !normalizedContact.isEmpty {
            self.contactInfo = normalizedContact
        } else {
            self.contactInfo = nil
        }
        ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&self)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case nodeID
        case publicProfileID
        case title
        case summary
        case category
        case tags
        case regionTags
        case serviceAreas
        case canonicalRegionIDs
        case canonical_region_ids
        case parentRegionIDs
        case parent_region_ids
        case regionAliases
        case region_aliases
        case semantic
        case fulfillment
        case status
        case visibility
        case createdAt
        case updatedAt
        case primaryImageURL
        case galleryImageURLs
        case gallery_image_urls
        case metadata
        case commercialFacts
        case contactInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        nodeID = try container.decode(String.self, forKey: .nodeID)
        publicProfileID = try container.decodeIfPresent(String.self, forKey: .publicProfileID)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        tags = Self.normalizedTerms(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        regionTags = Self.normalizedTerms(try container.decodeIfPresent([String].self, forKey: .regionTags) ?? [])
        serviceAreas = try container.decodeIfPresent([ExchangeDeclaredServiceArea].self, forKey: .serviceAreas) ?? []
        if let ids = try container.decodeIfPresent([String].self, forKey: .canonicalRegionIDs) {
            canonicalRegionIDs = Self.normalizedRegionTokens(ids)
        } else if let ids = try container.decodeIfPresent([String].self, forKey: .canonical_region_ids) {
            canonicalRegionIDs = Self.normalizedRegionTokens(ids)
        } else {
            canonicalRegionIDs = []
        }
        if let ids = try container.decodeIfPresent([String].self, forKey: .parentRegionIDs) {
            parentRegionIDs = Self.normalizedRegionTokens(ids)
        } else if let ids = try container.decodeIfPresent([String].self, forKey: .parent_region_ids) {
            parentRegionIDs = Self.normalizedRegionTokens(ids)
        } else {
            parentRegionIDs = []
        }
        if let ids = try container.decodeIfPresent([String].self, forKey: .regionAliases) {
            regionAliases = Self.normalizedRegionTokens(ids)
        } else if let ids = try container.decodeIfPresent([String].self, forKey: .region_aliases) {
            regionAliases = Self.normalizedRegionTokens(ids)
        } else {
            regionAliases = []
        }
        semantic = try container.decodeIfPresent(SemanticSurface.self, forKey: .semantic) ?? SemanticSurface()
        fulfillment = try container.decodeIfPresent(Fulfillment.self, forKey: .fulfillment) ?? Fulfillment()
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .draft
        visibility = try container.decodeIfPresent(Visibility.self, forKey: .visibility) ?? .publicDiscoverable
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        let decodedPrimary = try container.decodeIfPresent(String.self, forKey: .primaryImageURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines).exchangeNilIfBlank
        primaryImageURL = decodedPrimary
        let rawGallery: [String]
        if let decodedGallery = try container.decodeIfPresent([String].self, forKey: .galleryImageURLs) {
            rawGallery = decodedGallery
        } else if let decodedSnake = try container.decodeIfPresent([String].self, forKey: .gallery_image_urls) {
            rawGallery = decodedSnake
        } else {
            rawGallery = []
        }
        galleryImageURLs = Self.normalizedGalleryStorage(primary: decodedPrimary, gallery: rawGallery)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        commercialFacts =
            try container.decodeIfPresent(CommercialFacts.self, forKey: .commercialFacts)?.normalized() ?? .empty
        if let decodedContact = try container.decodeIfPresent(ContactInfo.self, forKey: .contactInfo)?.normalized(),
           !decodedContact.isEmpty {
            contactInfo = decodedContact
        } else {
            contactInfo = nil
        }
        ExchangeDeclaredServiceAreaSupport.syncOfferLocationFields(&self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nodeID, forKey: .nodeID)
        try container.encodeIfPresent(publicProfileID, forKey: .publicProfileID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encode(regionTags, forKey: .regionTags)
        if !serviceAreas.isEmpty {
            try container.encode(serviceAreas, forKey: .serviceAreas)
        }
        try container.encode(canonicalRegionIDs, forKey: .canonicalRegionIDs)
        try container.encode(parentRegionIDs, forKey: .parentRegionIDs)
        try container.encode(regionAliases, forKey: .regionAliases)
        try container.encode(semantic, forKey: .semantic)
        try container.encode(fulfillment, forKey: .fulfillment)
        try container.encode(status, forKey: .status)
        try container.encode(visibility, forKey: .visibility)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(primaryImageURL, forKey: .primaryImageURL)
        if !galleryImageURLs.isEmpty {
            try container.encode(galleryImageURLs, forKey: .galleryImageURLs)
        }
        try container.encode(metadata, forKey: .metadata)
        try container.encode(commercialFacts, forKey: .commercialFacts)
        if let normalizedContact = contactInfo?.normalized(), !normalizedContact.isEmpty {
            try container.encode(normalizedContact, forKey: .contactInfo)
        }
    }
}

// MARK: - v1.5 Commercial facts (public seller surface)

public extension ExchangeOffer {
    /// Structured service areas when present; otherwise legacy `regionTags` hydration.
    var effectiveServiceAreas: [ExchangeDeclaredServiceArea] {
        if !serviceAreas.isEmpty {
            return serviceAreas
        }
        return ExchangeDeclaredServiceAreaSupport.hydrate(fromRegionTags: regionTags)
    }

    struct ContactInfo: Codable, Sendable, Hashable {
        public enum PreferredMethod: String, Codable, Sendable, CaseIterable, Hashable {
            case email
            case phone
            case website
            case message
            case any
        }

        public var contactName: String?
        public var businessName: String?
        public var email: String?
        public var phone: String?
        public var website: String?
        public var preferredContactMethod: PreferredMethod?
        public var availabilityNote: String?
        public var serviceAddressOrArea: String?

        public init(
            contactName: String? = nil,
            businessName: String? = nil,
            email: String? = nil,
            phone: String? = nil,
            website: String? = nil,
            preferredContactMethod: PreferredMethod? = nil,
            availabilityNote: String? = nil,
            serviceAddressOrArea: String? = nil
        ) {
            self.contactName = contactName?.exchangeNilIfBlank
            self.businessName = businessName?.exchangeNilIfBlank
            self.email = email?.exchangeNilIfBlank
            self.phone = phone?.exchangeNilIfBlank
            self.website = website?.exchangeNilIfBlank
            self.preferredContactMethod = preferredContactMethod
            self.availabilityNote = availabilityNote?.exchangeNilIfBlank
            self.serviceAddressOrArea = serviceAddressOrArea?.exchangeNilIfBlank
        }

        public var isEmpty: Bool {
            contactName == nil &&
                businessName == nil &&
                email == nil &&
                phone == nil &&
                website == nil &&
                preferredContactMethod == nil &&
                availabilityNote == nil &&
                serviceAddressOrArea == nil
        }

        public func normalized() -> ContactInfo {
            let normalizedWebsite: String? = {
                guard let raw = website?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                    return nil
                }
                if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
                    return raw
                }
                return "https://\(raw)"
            }()

            return ContactInfo(
                contactName: contactName,
                businessName: businessName,
                email: email?.lowercased(),
                phone: phone,
                website: normalizedWebsite,
                preferredContactMethod: preferredContactMethod,
                availabilityNote: availabilityNote,
                serviceAddressOrArea: serviceAddressOrArea
            )
        }
    }


    /// Structured commercial copy for buyer review and deterministic agency — no private deal terms.
    struct CommercialFacts: Sendable, Hashable {
        public var priceDisplay: String?
        public var priceMin: Decimal?
        public var priceMax: Decimal?
        public var currency: String?
        public var priceUnit: String?

        public var packages: [PackageOption]
        public var serviceAreaNote: String?
        public var availabilityNote: String?
        public var minimumEngagement: String?
        public var cancellationPolicy: String?
        public var refundPolicy: String?
        public var warrantyPolicy: String?
        public var requiredBuyerInputs: [String]
        public var faqs: [FAQ]
        public var autoAnswerPolicy: AutoAnswerPolicy

        public init(
            priceDisplay: String? = nil,
            priceMin: Decimal? = nil,
            priceMax: Decimal? = nil,
            currency: String? = nil,
            priceUnit: String? = nil,
            packages: [PackageOption] = [],
            serviceAreaNote: String? = nil,
            availabilityNote: String? = nil,
            minimumEngagement: String? = nil,
            cancellationPolicy: String? = nil,
            refundPolicy: String? = nil,
            warrantyPolicy: String? = nil,
            requiredBuyerInputs: [String] = [],
            faqs: [FAQ] = [],
            autoAnswerPolicy: AutoAnswerPolicy = .conservativeDefaults
        ) {
            self.priceDisplay = priceDisplay?.exchangeNilIfBlank
            self.priceMin = priceMin
            self.priceMax = priceMax
            self.currency = currency?.exchangeNilIfBlank
            self.priceUnit = priceUnit?.exchangeNilIfBlank
            self.packages = packages
            self.serviceAreaNote = serviceAreaNote?.exchangeNilIfBlank
            self.availabilityNote = availabilityNote?.exchangeNilIfBlank
            self.minimumEngagement = minimumEngagement?.exchangeNilIfBlank
            self.cancellationPolicy = cancellationPolicy?.exchangeNilIfBlank
            self.refundPolicy = refundPolicy?.exchangeNilIfBlank
            self.warrantyPolicy = warrantyPolicy?.exchangeNilIfBlank
            self.requiredBuyerInputs = Self.trimmedList(requiredBuyerInputs)
            self.faqs = faqs
            self.autoAnswerPolicy = autoAnswerPolicy
        }

        /// Empty snapshot — decodes from missing JSON.
        public static let empty = CommercialFacts()

        /// Whether any v1.5 seller-authored commercial content is present (omit from wire when false).
        public var hasPublishedCommercialSurface: Bool {
            priceDisplay != nil ||
                priceMin != nil ||
                priceMax != nil ||
                currency != nil ||
                priceUnit != nil ||
                !packages.isEmpty ||
                serviceAreaNote != nil ||
                availabilityNote != nil ||
                minimumEngagement != nil ||
                cancellationPolicy != nil ||
                refundPolicy != nil ||
                warrantyPolicy != nil ||
                !requiredBuyerInputs.isEmpty ||
                !faqs.isEmpty
        }

        public var hasAnyPublicPriceSignal: Bool {
            if priceDisplay != nil { return true }
            if priceMin != nil || priceMax != nil { return true }
            return packages.contains { $0.priceDisplay != nil }
        }

        /// Lines folded into `ExchangeOffer.searchableText` (retrieval / discovery).
        public var searchablePieces: [String] {
            var lines: [String] = []
            if let priceDisplay { lines.append(priceDisplay) }
            if let priceMin { lines.append("min \(priceDisplayValue(priceMin))") }
            if let priceMax { lines.append("max \(priceDisplayValue(priceMax))") }
            if let currency { lines.append(currency) }
            if let priceUnit { lines.append(priceUnit) }
            for pkg in packages {
                var s = pkg.title
                if let u = pkg.summary { s += " \(u)" }
                if let pd = pkg.priceDisplay { s += " \(pd)" }
                lines.append(s)
            }
            if let serviceAreaNote { lines.append(serviceAreaNote) }
            if let availabilityNote { lines.append(availabilityNote) }
            if let minimumEngagement { lines.append(minimumEngagement) }
            if let cancellationPolicy { lines.append(cancellationPolicy) }
            if let refundPolicy { lines.append(refundPolicy) }
            if let warrantyPolicy { lines.append(warrantyPolicy) }
            lines.append(contentsOf: requiredBuyerInputs)
            for f in faqs {
                lines.append("\(f.question) \(f.answer)")
            }
            return lines
        }

        private func priceDisplayValue(_ d: Decimal) -> String {
            (d as NSDecimalNumber).stringValue
        }

        /// Compact read-model lines for UI (thread situation, previews). No private deal terms.
        public func surfaceSkimLines(maxCount: Int = 16) -> [String] {
            var lines: [String] = []

            if let priceDisplay {
                lines.append("Price: \(priceDisplay)")
            }
            if priceMin != nil || priceMax != nil {
                let a = priceMin.map { "min \(priceDisplayValue($0))" }
                let b = priceMax.map { "max \(priceDisplayValue($0))" }
                let range = [a, b].compactMap { $0 }.joined(separator: " · ")
                if !range.isEmpty {
                    lines.append("Price range: \(range)")
                }
            }
            if let currency { lines.append("Currency: \(currency)") }
            if let priceUnit { lines.append("Price unit: \(priceUnit)") }

            for pkg in packages {
                var s = "Package: \(pkg.title)"
                if let u = pkg.summary, !u.isEmpty { s += " — \(u)" }
                if let pd = pkg.priceDisplay { s += " (\(pd))" }
                lines.append(s)
            }

            if let serviceAreaNote {
                lines.append("Service area: \(serviceAreaNote)")
            }
            if let availabilityNote {
                lines.append("Availability: \(availabilityNote)")
            }
            if let minimumEngagement {
                lines.append("Minimum engagement: \(minimumEngagement)")
            }
            if let cancellationPolicy {
                lines.append("Cancellation policy: \(cancellationPolicy)")
            }
            if let refundPolicy {
                lines.append("Refund policy: \(refundPolicy)")
            }
            if let warrantyPolicy {
                lines.append("Warranty policy: \(warrantyPolicy)")
            }
            for input in requiredBuyerInputs {
                lines.append("Required buyer input: \(input)")
            }
            for f in faqs {
                lines.append("FAQ: Q: \(f.question) / A: \(f.answer)")
            }

            let resolved = resolvedAutoAnswerPolicy()
            lines.append(
                "FAQ auto-answer allowed: \(resolved.canAnswerFAQs ? "yes" : "no")"
            )

            return Array(lines.prefix(maxCount))
        }

        func normalized() -> CommercialFacts {
            CommercialFacts(
                priceDisplay: priceDisplay,
                priceMin: priceMin,
                priceMax: priceMax,
                currency: currency,
                priceUnit: priceUnit,
                packages: packages,
                serviceAreaNote: serviceAreaNote,
                availabilityNote: availabilityNote,
                minimumEngagement: minimumEngagement,
                cancellationPolicy: cancellationPolicy,
                refundPolicy: refundPolicy,
                warrantyPolicy: warrantyPolicy,
                requiredBuyerInputs: requiredBuyerInputs,
                faqs: faqs,
                autoAnswerPolicy: autoAnswerPolicy
            )
        }

        /// Effective automation bounds: stored policy + seller-published content (conservative defaults).
        public func resolvedAutoAnswerPolicy() -> AutoAnswerPolicy {
            let hasPolicyText =
                !(cancellationPolicy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !(refundPolicy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !(warrantyPolicy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let hasPrice =
                hasAnyPublicPriceSignal
            let hasAvailabilityText =
                !(availabilityNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            return AutoAnswerPolicy(
                canAnswerPricing: hasPrice && autoAnswerPolicy.canAnswerPricing,
                canAnswerAvailability: hasAvailabilityText && autoAnswerPolicy.canAnswerAvailability,
                canAnswerPolicies: hasPolicyText && autoAnswerPolicy.canAnswerPolicies,
                canAnswerServiceArea: autoAnswerPolicy.canAnswerServiceArea,
                canAnswerFAQs: !faqs.isEmpty && autoAnswerPolicy.canAnswerFAQs,
                requiresApprovalForCustomQuote: autoAnswerPolicy.requiresApprovalForCustomQuote
            )
        }

        /// Permission-only automation bounds from seller toggles.
        /// Keep separate from `resolvedAutoAnswerPolicy()` so answerability can evaluate evidence independently.
        public func permissionOnlyAutoAnswerPolicy() -> AutoAnswerPolicy {
            autoAnswerPolicy
        }

        public var hasAvailabilityEvidence: Bool {
            !(availabilityNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        public var hasPolicyEvidence: Bool {
            !(cancellationPolicy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !(refundPolicy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !(warrantyPolicy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        public var hasFAQEvidence: Bool {
            !faqs.isEmpty
        }

        private static func trimmedList(_ rows: [String]) -> [String] {
            rows
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    struct PackageOption: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var summary: String?
        public var priceDisplay: String?

        public init(
            id: String = UUID().uuidString,
            title: String,
            summary: String? = nil,
            priceDisplay: String? = nil
        ) {
            self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.summary = summary?.exchangeNilIfBlank
            self.priceDisplay = priceDisplay?.exchangeNilIfBlank
        }
    }

    struct FAQ: Codable, Sendable, Hashable {
        public var question: String
        public var answer: String

        public init(question: String, answer: String) {
            self.question = question.trimmingCharacters(in: .whitespacesAndNewlines)
            self.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    struct AutoAnswerPolicy: Codable, Sendable, Hashable {
        public var canAnswerPricing: Bool
        public var canAnswerAvailability: Bool
        public var canAnswerPolicies: Bool
        public var canAnswerServiceArea: Bool
        public var canAnswerFAQs: Bool
        public var requiresApprovalForCustomQuote: Bool

        public init(
            canAnswerPricing: Bool = false,
            canAnswerAvailability: Bool = false,
            canAnswerPolicies: Bool = true,
            canAnswerServiceArea: Bool = true,
            canAnswerFAQs: Bool = true,
            requiresApprovalForCustomQuote: Bool = true
        ) {
            self.canAnswerPricing = canAnswerPricing
            self.canAnswerAvailability = canAnswerAvailability
            self.canAnswerPolicies = canAnswerPolicies
            self.canAnswerServiceArea = canAnswerServiceArea
            self.canAnswerFAQs = canAnswerFAQs
            self.requiresApprovalForCustomQuote = requiresApprovalForCustomQuote
        }

        public static let conservativeDefaults = AutoAnswerPolicy()
    }
}

extension ExchangeOffer.CommercialFacts: Codable {
    private enum CodingKeys: String, CodingKey {
        case priceDisplay
        case priceMin
        case priceMax
        case currency
        case priceUnit
        case packages
        case serviceAreaNote
        case availabilityNote
        case minimumEngagement
        case cancellationPolicy
        case refundPolicy
        case warrantyPolicy
        case requiredBuyerInputs
        case faqs
        case autoAnswerPolicy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let pd = try c.decodeIfPresent(String.self, forKey: .priceDisplay)
        let pmin = try c.decodeIfPresent(Decimal.self, forKey: .priceMin)
        let pmax = try c.decodeIfPresent(Decimal.self, forKey: .priceMax)
        let cur = try c.decodeIfPresent(String.self, forKey: .currency)
        let unit = try c.decodeIfPresent(String.self, forKey: .priceUnit)
        let pkgs = try c.decodeIfPresent([ExchangeOffer.PackageOption].self, forKey: .packages) ?? []
        let san = try c.decodeIfPresent(String.self, forKey: .serviceAreaNote)
        let an = try c.decodeIfPresent(String.self, forKey: .availabilityNote)
        let me = try c.decodeIfPresent(String.self, forKey: .minimumEngagement)
        let cp = try c.decodeIfPresent(String.self, forKey: .cancellationPolicy)
        let rp = try c.decodeIfPresent(String.self, forKey: .refundPolicy)
        let wp = try c.decodeIfPresent(String.self, forKey: .warrantyPolicy)
        let req = try c.decodeIfPresent([String].self, forKey: .requiredBuyerInputs) ?? []
        let fq = try c.decodeIfPresent([ExchangeOffer.FAQ].self, forKey: .faqs) ?? []
        let ap = try c.decodeIfPresent(ExchangeOffer.AutoAnswerPolicy.self, forKey: .autoAnswerPolicy)
            ?? .conservativeDefaults
        self.init(
            priceDisplay: pd,
            priceMin: pmin,
            priceMax: pmax,
            currency: cur,
            priceUnit: unit,
            packages: pkgs,
            serviceAreaNote: san,
            availabilityNote: an,
            minimumEngagement: me,
            cancellationPolicy: cp,
            refundPolicy: rp,
            warrantyPolicy: wp,
            requiredBuyerInputs: req,
            faqs: fq,
            autoAnswerPolicy: ap
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(priceDisplay, forKey: .priceDisplay)
        try c.encodeIfPresent(priceMin, forKey: .priceMin)
        try c.encodeIfPresent(priceMax, forKey: .priceMax)
        try c.encodeIfPresent(currency, forKey: .currency)
        try c.encodeIfPresent(priceUnit, forKey: .priceUnit)
        try c.encode(packages, forKey: .packages)
        try c.encodeIfPresent(serviceAreaNote, forKey: .serviceAreaNote)
        try c.encodeIfPresent(availabilityNote, forKey: .availabilityNote)
        try c.encodeIfPresent(minimumEngagement, forKey: .minimumEngagement)
        try c.encodeIfPresent(cancellationPolicy, forKey: .cancellationPolicy)
        try c.encodeIfPresent(refundPolicy, forKey: .refundPolicy)
        try c.encodeIfPresent(warrantyPolicy, forKey: .warrantyPolicy)
        try c.encode(requiredBuyerInputs, forKey: .requiredBuyerInputs)
        try c.encode(faqs, forKey: .faqs)
        try c.encode(autoAnswerPolicy, forKey: .autoAnswerPolicy)
    }
}

public extension ExchangeOffer {
    enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case draft
        case active
        case paused
        case archived
    }

    enum Visibility: String, Codable, Sendable, CaseIterable, Hashable {
        /// Discoverable in normal public search/routing.
        case publicDiscoverable

        /// Not broad-discoverable, but usable through direct/trusted/path-based contexts.
        case limitedSurface

        /// Not discoverable or routable as a fresh public surface.
        case hidden
    }

    struct SemanticSurface: Codable, Sendable, Hashable {
        public var domains: [String]
        public var serviceKinds: [String]
        public var audienceKinds: [AudienceKind]
        public var fulfillmentModes: [FulfillmentMode]
        public var notes: String?

        public init(
            domains: [String] = [],
            serviceKinds: [String] = [],
            audienceKinds: [AudienceKind] = [],
            fulfillmentModes: [FulfillmentMode] = [],
            notes: String? = nil
        ) {
            self.domains = Self.normalizedTerms(domains)
            self.serviceKinds = Self.normalizedTerms(serviceKinds)
            self.audienceKinds = Array(Set(audienceKinds)).sorted { $0.rawValue < $1.rawValue }
            self.fulfillmentModes = Array(Set(fulfillmentModes)).sorted { $0.rawValue < $1.rawValue }
            self.notes = notes?.exchangeNilIfBlank
        }

        public enum AudienceKind: String, Codable, Sendable, CaseIterable, Hashable {
            case person
            case provider
            case business
            case organization
            case group
            case secretaryNode
            case unknown
        }

        public enum FulfillmentMode: String, Codable, Sendable, CaseIterable, Hashable {
            case localOnly
            case localPreferred
            case remoteFriendly
            case shippable
            case digitalDelivery
            case inPerson
        }

        public var searchableTerms: [String] {
            Self.normalizedTerms(
                domains +
                serviceKinds +
                audienceKinds.map(\.rawValue) +
                fulfillmentModes.map(\.rawValue)
            )
        }

        public func normalized() -> SemanticSurface {
            SemanticSurface(
                domains: domains,
                serviceKinds: serviceKinds,
                audienceKinds: audienceKinds,
                fulfillmentModes: fulfillmentModes,
                notes: notes
            )
        }

        private static func normalizedTerms(_ values: [String]) -> [String] {
            ExchangeOffer.normalizedTerms(values)
        }
    }

    struct Fulfillment: Codable, Sendable, Hashable {
        public enum PricingMode: String, Codable, Sendable, CaseIterable, Hashable {
            case fixed
            case quoteRequired
            case custom
            case undisclosed
        }

        public enum CommitmentMode: String, Codable, Sendable, CaseIterable, Hashable {
            case exploratory
            case active
            case approvalRequired
        }

        public var pricingMode: PricingMode
        public var commitmentMode: CommitmentMode
        public var remoteFriendly: Bool
        public var leadTimeNote: String?
        public var capacityNote: String?

        public init(
            pricingMode: PricingMode = .quoteRequired,
            commitmentMode: CommitmentMode = .exploratory,
            remoteFriendly: Bool = false,
            leadTimeNote: String? = nil,
            capacityNote: String? = nil
        ) {
            self.pricingMode = pricingMode
            self.commitmentMode = commitmentMode
            self.remoteFriendly = remoteFriendly
            self.leadTimeNote = leadTimeNote?.exchangeNilIfBlank
            self.capacityNote = capacityNote?.exchangeNilIfBlank
        }

        public func normalized() -> Fulfillment {
            Fulfillment(
                pricingMode: pricingMode,
                commitmentMode: commitmentMode,
                remoteFriendly: remoteFriendly,
                leadTimeNote: leadTimeNote,
                capacityNote: capacityNote
            )
        }
    }
}

public extension ExchangeOffer {
    /// Maximum HTTPS image URLs per offer across hero + gallery (product cap).
    static let maxPublicOfferImageCount = 5

    /// Hero URL for cards: explicit primary, else first gallery entry.
    var displayHeroImageURL: String? {
        if let primaryImageURL, !primaryImageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return primaryImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return galleryImageURLs.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deduped, ordered hero-first list (at most ``ExchangeOffer.maxPublicOfferImageCount`` entries).
    func normalizedPublicOfferImageURLs(maxCount: Int = ExchangeOffer.maxPublicOfferImageCount) -> [String] {
        Self.limitedOrderedOfferImageURLs(
            primaryImageURL: primaryImageURL,
            galleryImageURLs: galleryImageURLs,
            maxCount: maxCount
        )
    }

    static func limitedOrderedOfferImageURLs(
        primaryImageURL: String?,
        galleryImageURLs: [String],
        maxCount: Int = ExchangeOffer.maxPublicOfferImageCount
    ) -> [String] {
        let cap = min(max(maxCount, 1), maxPublicOfferImageCount)
        var out: [String] = []
        var seen = Set<String>()
        func append(_ raw: String?) {
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).exchangeNilIfBlank else { return }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return }
            out.append(trimmed)
        }
        append(primaryImageURL)
        for g in galleryImageURLs {
            append(g)
            if out.count >= cap { return out }
        }
        return out
    }

    /// Normalized ``galleryImageURLs`` storage: excludes primary, dedupes, enforces hero + extras ≤ 5.
    static func normalizedGalleryStorage(primary: String?, gallery: [String]) -> [String] {
        let primaryTrimmed = primary?.trimmingCharacters(in: .whitespacesAndNewlines).exchangeNilIfBlank
        let primaryKey = primaryTrimmed?.lowercased()
        let maxExtras = primaryKey == nil ? maxPublicOfferImageCount : maxPublicOfferImageCount - 1
        var out: [String] = []
        var seen = Set<String>()
        if let primaryKey { seen.insert(primaryKey) }
        for raw in gallery {
            guard let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).exchangeNilIfBlank else { continue }
            let k = t.lowercased()
            guard seen.insert(k).inserted else { continue }
            out.append(t)
            if out.count >= maxExtras { break }
        }
        return out
    }

    var isBroadlyDiscoverable: Bool {
        visibility == .publicDiscoverable && status == .active
    }

    var isRouteableInPrinciple: Bool {
        switch status {
        case .draft, .archived:
            return false
        case .active:
            return visibility != .hidden
        case .paused:
            return false
        }
    }

    var searchableText: String {
        var pieces: [String?] = [
            title,
            summary,
            category,
            tags.joined(separator: " "),
            regionTags.joined(separator: " "),
            semantic.searchableTerms.joined(separator: " "),
            semantic.notes,
            fulfillment.leadTimeNote,
            fulfillment.capacityNote
        ]
        for line in commercialFacts.searchablePieces {
            pieces.append(line)
        }
        return pieces
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var coordinationTokens: [String] {
        Self.normalizedTerms(
            tags +
            regionTags +
            semantic.searchableTerms +
            [category].compactMap { $0 }
        )
    }

    var summaryLine: String {
        if let category, !category.isEmpty {
            return "\(title) · \(category)"
        }
        return title
    }

    func updatingStatus(
        _ status: Status,
        at date: Date = Date()
    ) -> ExchangeOffer {
        var copy = self
        copy.status = status
        copy.updatedAt = date
        return copy
    }

    func updatingVisibility(
        _ visibility: Visibility,
        at date: Date = Date()
    ) -> ExchangeOffer {
        var copy = self
        copy.visibility = visibility
        copy.updatedAt = date
        return copy
    }

    func updatingSemantic(
        _ semantic: SemanticSurface,
        at date: Date = Date()
    ) -> ExchangeOffer {
        var copy = self
        copy.semantic = semantic.normalized()
        copy.updatedAt = date
        return copy
    }

    func updatingFulfillment(
        _ fulfillment: Fulfillment,
        at date: Date = Date()
    ) -> ExchangeOffer {
        var copy = self
        copy.fulfillment = fulfillment.normalized()
        copy.updatedAt = date
        return copy
    }

    func updatingCommercialFacts(
        _ commercialFacts: CommercialFacts,
        at date: Date = Date()
    ) -> ExchangeOffer {
        var copy = self
        copy.commercialFacts = commercialFacts.normalized()
        copy.updatedAt = date
        return copy
    }

    func updatingContactInfo(
        _ contactInfo: ContactInfo?,
        at date: Date = Date()
    ) -> ExchangeOffer {
        var copy = self
        if let normalizedContact = contactInfo?.normalized(), !normalizedContact.isEmpty {
            copy.contactInfo = normalizedContact
        } else {
            copy.contactInfo = nil
        }
        copy.updatedAt = date
        return copy
    }

    /// Short lines for thread situation / skimmed commercial surface.
    var commercialSurfaceSkimLines: [String] {
        commercialFacts.surfaceSkimLines()
    }
}

private extension ExchangeOffer {
    static func normalizedTerms(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                    }
                    .filter {
                        !$0.isEmpty &&
                        !$0.isSemanticStopWord &&
                        $0.count <= 100
                    }
            )
        )
        .sorted()
    }

    static func normalizedRegionTokens(_ values: [String]) -> [String] {
        Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty && $0.count <= 200 }
            )
        )
        .sorted()
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isSemanticStopWord: Bool {
        [
            "the", "a", "an", "for", "to", "with", "and", "or", "of", "in", "on",
            "my", "me", "our", "their", "service", "services", "business", "company"
        ].contains(self)
    }
}
