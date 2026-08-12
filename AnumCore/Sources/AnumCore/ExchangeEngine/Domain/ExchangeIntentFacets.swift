import Foundation

/// Compact retrieval-facing facets extracted from a user's request.
///
/// This is not a giant semantic blob.
/// It is the routing bundle that retrieval/discovery can use directly.
///
/// Design goals:
/// - preserve explicit user signal
/// - distinguish provider/professional vs affinity/social intent
/// - support domain-correct hard gating
/// - stay cheap to construct and cheap to log
/// - consume canonical enums from ExchangeIntent rather than redefining them
public struct ExchangeIntentFacets: Codable, Sendable, Hashable {
    /// Canonical semantic requester-search intent used to compile legacy string rails.
    /// When absent (older persisted threads), legacy fields remain the compatibility source.
    public var searchIntent: ExchangeCanonicalSearchIntent?

    public var targetKind: TargetKind
    public var marketType: MarketType
    public var fulfillmentMode: FulfillmentMode
    public var riskLevel: RiskLevel

    public var prefersLocalFirst: Bool
    public var allowsRemoteOrShipped: Bool
    public var allowsAutonomousClarification: Bool

    /// Lightweight retrieval-routing signals.
    /// Canonical ownership lives in ExchangeIntent.
    public var queryIntentClass: ExchangeIntent.QueryIntentClass
    public var surfacePreference: ExchangeIntent.SurfacePreference

    /// Broad human-readable descriptors.
    public var targetRole: String?
    public var activity: String?
    public var serviceCategory: String?
    public var productCategory: String?

    public var locationText: String?
    public var placeName: String?
    /// Canonical request-side location need (gazetteer-optional).
    public var locationRequirement: ExchangeLocationRequirement?
    /// Optional H3 spatial anchor for requester (device GPS or explicit query); not projected to regionTags.
    public var requesterSpatialAnchor: ExchangeRequesterSpatialAnchor?
    public var timeText: String?
    public var timePreference: TimePreference?

    /// Retrieval terms split by semantic job.
    /// These are routing aids, not semantic truth.
    public var providerTerms: [String]
    public var capabilityTerms: [String]
    public var affinityTerms: [String]
    /// Interpreter region hints (may be noisy). Retrieval treats these as soft evidence only;
    /// hard place gating uses `hardRegionIDs` / resolved places from `ExchangeRetrievalQueryBuilder`.
    public var regionTerms: [String]

    /// Keyword rails.
    public var primaryKeywords: [String]
    public var secondaryKeywords: [String]

    /// True hard / soft constraints.
    public var hardRequirements: [Requirement]
    public var softPreferences: [Requirement]

    /// Explicit retrieval flags.
    public var explicitRegionRequired: Bool
    public var explicitProfessionalNeed: Bool
    public var explicitAffinityNeed: Bool

    /// Pass 1 typed query entities and place-resolution containers.
    public var queryEntities: [ExchangeQueryEntity]
    public var resolvedPlaces: [ExchangeResolvedPlace]
    public var softLocationTerms: [String]
    public var hardRegionIDs: [String]

    public var notes: String?

    public init(
        searchIntent: ExchangeCanonicalSearchIntent? = nil,
        targetKind: TargetKind = .unknown,
        marketType: MarketType = .unknown,
        fulfillmentMode: FulfillmentMode = .unknown,
        riskLevel: RiskLevel = .moderate,
        prefersLocalFirst: Bool = false,
        allowsRemoteOrShipped: Bool = false,
        allowsAutonomousClarification: Bool = false,
        queryIntentClass: ExchangeIntent.QueryIntentClass = .generalDiscovery,
        surfacePreference: ExchangeIntent.SurfacePreference = .mixed,
        targetRole: String? = nil,
        activity: String? = nil,
        serviceCategory: String? = nil,
        productCategory: String? = nil,
        locationText: String? = nil,
        placeName: String? = nil,
        locationRequirement: ExchangeLocationRequirement? = nil,
        requesterSpatialAnchor: ExchangeRequesterSpatialAnchor? = nil,
        timeText: String? = nil,
        timePreference: TimePreference? = nil,
        providerTerms: [String] = [],
        capabilityTerms: [String] = [],
        affinityTerms: [String] = [],
        regionTerms: [String] = [],
        primaryKeywords: [String] = [],
        secondaryKeywords: [String] = [],
        hardRequirements: [Requirement] = [],
        softPreferences: [Requirement] = [],
        explicitRegionRequired: Bool = false,
        explicitProfessionalNeed: Bool = false,
        explicitAffinityNeed: Bool = false,
        queryEntities: [ExchangeQueryEntity] = [],
        resolvedPlaces: [ExchangeResolvedPlace] = [],
        softLocationTerms: [String] = [],
        hardRegionIDs: [String] = [],
        notes: String? = nil
    ) {
        #if DEBUG
        let englishBeforeSanitize = searchIntent?.canonicalEnglishSearchText
        #endif
        self.searchIntent = searchIntent?.sanitized()
        #if DEBUG
        if let englishBeforeSanitize,
           !ExchangeIntentFacets.normalizeWhitespace(englishBeforeSanitize).isEmpty,
           self.searchIntent?.canonicalEnglishSearchText == nil {
            print(
                "[ExchangeIntentFacets] canonicalEnglishSearchText lost during sanitization " +
                "beforeLength=\(englishBeforeSanitize.count)"
            )
        }
        #endif
        self.targetKind = targetKind
        self.marketType = marketType
        self.fulfillmentMode = fulfillmentMode
        self.riskLevel = riskLevel
        self.prefersLocalFirst = prefersLocalFirst
        self.allowsRemoteOrShipped = allowsRemoteOrShipped
        self.allowsAutonomousClarification = allowsAutonomousClarification
        self.queryIntentClass = queryIntentClass
        self.surfacePreference = surfacePreference
        self.targetRole = Self.cleanOptionalField(targetRole, maxLength: 160)
        self.activity = Self.cleanOptionalField(activity, maxLength: 160)
        self.serviceCategory = Self.cleanOptionalField(serviceCategory, maxLength: 160)
        self.productCategory = Self.cleanOptionalField(productCategory, maxLength: 160)
        self.locationText = Self.cleanOptionalField(locationText, maxLength: 160)
        self.placeName = Self.cleanOptionalField(placeName, maxLength: 160)
        self.locationRequirement = locationRequirement
        self.requesterSpatialAnchor = requesterSpatialAnchor
        self.timeText = Self.cleanOptionalField(timeText, maxLength: 160)
        self.timePreference = timePreference
        self.providerTerms = Self.sanitizeKeywords(providerTerms, maxCount: 24, maxLength: 120)
        self.capabilityTerms = Self.sanitizeKeywords(capabilityTerms, maxCount: 24, maxLength: 120)
        self.affinityTerms = Self.sanitizeKeywords(affinityTerms, maxCount: 24, maxLength: 120)
        self.regionTerms = Self.sanitizeKeywords(regionTerms, maxCount: 12, maxLength: 120)
        self.primaryKeywords = Self.sanitizeKeywords(primaryKeywords, maxCount: 24, maxLength: 120)
        self.secondaryKeywords = Self.sanitizeKeywords(secondaryKeywords, maxCount: 24, maxLength: 120)
        self.hardRequirements = Self.sanitizeRequirements(hardRequirements, maxCount: 24)
        self.softPreferences = Self.sanitizeRequirements(softPreferences, maxCount: 24)
        self.explicitRegionRequired = explicitRegionRequired
        self.explicitProfessionalNeed = explicitProfessionalNeed
        self.explicitAffinityNeed = explicitAffinityNeed
        self.queryEntities = Self.sanitizeEntities(queryEntities, maxCount: 32)
        self.resolvedPlaces = Self.sanitizeResolvedPlaces(resolvedPlaces, maxCount: 16)
        self.softLocationTerms = Self.sanitizeKeywords(softLocationTerms, maxCount: 16, maxLength: 120)
        self.hardRegionIDs = Self.sanitizeKeywords(hardRegionIDs, maxCount: 16, maxLength: 120)
        self.notes = Self.cleanOptionalField(notes, maxLength: 500)
    }
}

public extension ExchangeIntentFacets {
    /// Optional LLM-provided discovery route fields carried through canonical mapping.
    struct ExtractedSearchRoute: Codable, Sendable, Hashable {
        public var routeClassRaw: String?
        public var surfacePreferenceRaw: String?
        public var targetKindRaw: String?
        public var modeRaw: String?
        public var routeConfidence: Double?
        public var routeRationale: String?

        public init(
            routeClassRaw: String? = nil,
            surfacePreferenceRaw: String? = nil,
            targetKindRaw: String? = nil,
            modeRaw: String? = nil,
            routeConfidence: Double? = nil,
            routeRationale: String? = nil
        ) {
            self.routeClassRaw = routeClassRaw
            self.surfacePreferenceRaw = surfacePreferenceRaw
            self.targetKindRaw = targetKindRaw
            self.modeRaw = modeRaw
            self.routeConfidence = routeConfidence
            self.routeRationale = routeRationale
        }
    }

    struct ExchangeCanonicalSearchIntent: Codable, Sendable, Hashable {
        public var domainCategory: DomainCategory
        public var objectType: String?
        public var transactionIntent: TransactionIntent?
        public var places: [StructuredPlace]
        public var attributes: [StructuredAttribute]
        public var preferences: [StructuredPreference]
        public var timeConstraints: [StructuredTimeConstraint]
        public var commercialConstraints: [StructuredCommercialConstraint]
        public var broadRecallTokens: [String]
        public var semanticConcepts: [String]
        public var hardConstraints: [ExchangeIntent.Constraint]
        public var softPreferences: [ExchangeIntent.Constraint]
        public var clarificationGaps: [String]
        public var rawUserText: String
        /// When set, records how this canonical snapshot was produced (LLM vs heuristic fallback).
        public var extractionSource: SearchIntentExtractionSource?
        /// Optional calibrated confidence from flat-summary extraction (0...1). Legacy paths leave nil.
        public var extractionConfidence: Double?
        /// Optional surface hint resolved from flat-summary `surfacePreferenceHint` when confident.
        public var extractedSurfacePreference: ExchangeIntent.SurfacePreference?
        /// Optional LLM-provided discovery route (validated before application).
        public var extractedRoute: ExtractedSearchRoute?
        /// Normalized English search carrier for embedding/BM25 when the user request is not English.
        public var canonicalEnglishSearchText: String?

        public init(
            domainCategory: DomainCategory = .general,
            objectType: String? = nil,
            transactionIntent: TransactionIntent? = nil,
            places: [StructuredPlace] = [],
            attributes: [StructuredAttribute] = [],
            preferences: [StructuredPreference] = [],
            timeConstraints: [StructuredTimeConstraint] = [],
            commercialConstraints: [StructuredCommercialConstraint] = [],
            broadRecallTokens: [String] = [],
            semanticConcepts: [String] = [],
            hardConstraints: [ExchangeIntent.Constraint] = [],
            softPreferences: [ExchangeIntent.Constraint] = [],
            clarificationGaps: [String] = [],
            rawUserText: String = "",
            extractionSource: SearchIntentExtractionSource? = nil,
            extractionConfidence: Double? = nil,
            extractedSurfacePreference: ExchangeIntent.SurfacePreference? = nil,
            extractedRoute: ExtractedSearchRoute? = nil,
            canonicalEnglishSearchText: String? = nil
        ) {
            self.domainCategory = domainCategory
            self.objectType = objectType
            self.transactionIntent = transactionIntent
            self.places = places
            self.attributes = attributes
            self.preferences = preferences
            self.timeConstraints = timeConstraints
            self.commercialConstraints = commercialConstraints
            self.broadRecallTokens = broadRecallTokens
            self.semanticConcepts = semanticConcepts
            self.hardConstraints = hardConstraints
            self.softPreferences = softPreferences
            self.clarificationGaps = clarificationGaps
            self.rawUserText = rawUserText
            self.extractionSource = extractionSource
            self.extractionConfidence = extractionConfidence
            self.extractedSurfacePreference = extractedSurfacePreference
            self.extractedRoute = extractedRoute
            self.canonicalEnglishSearchText = canonicalEnglishSearchText
        }
    }

    enum DomainCategory: String, Codable, Sendable, CaseIterable, Hashable {
        case realEstate
        case homeService
        case professionalService
        case product
        case general
    }

    enum TransactionIntent: String, Codable, Sendable, CaseIterable, Hashable {
        case forSale
        case rent
        case hire
        case buy
        case book
        case inquire
    }

    struct StructuredPlace: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var canonicalID: String?
        public var normalizedText: String
        public var aliases: [String]
        public var confidence: Double
        public var isHard: Bool

        public init(
            id: UUID = UUID(),
            canonicalID: String? = nil,
            normalizedText: String,
            aliases: [String] = [],
            confidence: Double = 0.0,
            isHard: Bool = false
        ) {
            self.id = id
            self.canonicalID = canonicalID
            self.normalizedText = normalizedText
            self.aliases = aliases
            self.confidence = confidence
            self.isHard = isHard
        }
    }

    struct StructuredAttribute: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var key: String
        public var value: String
        public var numericValue: Double?

        public init(
            id: UUID = UUID(),
            key: String,
            value: String,
            numericValue: Double? = nil
        ) {
            self.id = id
            self.key = key
            self.value = value
            self.numericValue = numericValue
        }
    }

    struct StructuredPreference: Codable, Sendable, Hashable, Identifiable {
        public enum Strength: String, Codable, Sendable, CaseIterable, Hashable {
            case required
            case preferred
            case optional
        }

        public var id: UUID
        public var key: String
        public var value: String?
        public var strength: Strength

        public init(
            id: UUID = UUID(),
            key: String,
            value: String? = nil,
            strength: Strength = .preferred
        ) {
            self.id = id
            self.key = key
            self.value = value
            self.strength = strength
        }
    }

    struct StructuredTimeConstraint: Codable, Sendable, Hashable, Identifiable {
        public enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
            case immediate
            case day
            case range
            case specific
            case flexible
        }

        public var id: UUID
        public var kind: Kind
        public var text: String

        public init(
            id: UUID = UUID(),
            kind: Kind,
            text: String
        ) {
            self.id = id
            self.kind = kind
            self.text = text
        }
    }

    struct StructuredCommercialConstraint: Codable, Sendable, Hashable, Identifiable {
        public enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
            case financing
            case budget
            case paymentTerm
            case other
        }

        public var id: UUID
        public var kind: Kind
        public var key: String
        public var value: String
        public var isHard: Bool

        public init(
            id: UUID = UUID(),
            kind: Kind,
            key: String,
            value: String,
            isHard: Bool = false
        ) {
            self.id = id
            self.kind = kind
            self.key = key
            self.value = value
            self.isHard = isHard
        }
    }

    enum TargetKind: String, Codable, Sendable, CaseIterable, Hashable {
        case person
        case provider
        case business
        case organization
        case group
        case secretaryNode
        case unknown
    }

    enum MarketType: String, Codable, Sendable, CaseIterable, Hashable {
        case localService
        case physicalGoods
        case digitalService
        case informationRequest
        case relationshipLed
        case unknown
    }

    enum FulfillmentMode: String, Codable, Sendable, CaseIterable, Hashable {
        case localOnly
        case localPreferred
        case remoteFriendly
        case shippable
        case digitalDelivery
        case unknown
    }

    enum RiskLevel: String, Codable, Sendable, CaseIterable, Hashable {
        case low
        case moderate
        case high
    }

    enum TimePreference: String, Codable, Sendable, CaseIterable, Hashable {
        case immediate
        case today
        case tonight
        case thisWeek
        case weekend
        case nextWeek
        case flexible
    }

    struct Requirement: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var key: String
        public var value: String
        public var isHard: Bool

        public init(
            id: UUID = UUID(),
            key: String,
            value: String,
            isHard: Bool = true
        ) {
            self.id = id
            self.key = key
            self.value = value
            self.isHard = isHard
        }
    }
}

public extension ExchangeIntentFacets {
    static let empty = ExchangeIntentFacets()

    var hasMeaningfulStructure: Bool {
        searchIntent != nil ||
        targetKind != .unknown ||
        marketType != .unknown ||
        fulfillmentMode != .unknown ||
        targetRole != nil ||
        activity != nil ||
        serviceCategory != nil ||
        productCategory != nil ||
        locationText != nil ||
        placeName != nil ||
        timeText != nil ||
        !providerTerms.isEmpty ||
        !capabilityTerms.isEmpty ||
        !affinityTerms.isEmpty ||
        !regionTerms.isEmpty ||
        !queryEntities.isEmpty ||
        !resolvedPlaces.isEmpty ||
        !softLocationTerms.isEmpty ||
        !hardRegionIDs.isEmpty ||
        !primaryKeywords.isEmpty ||
        !secondaryKeywords.isEmpty ||
        !hardRequirements.isEmpty ||
        !softPreferences.isEmpty
    }

    var allKeywords: [String] {
        Self.sanitizeKeywords(
            providerTerms +
            capabilityTerms +
            affinityTerms +
            regionTerms +
            softLocationTerms +
            hardRegionIDs +
            queryEntities.map(\.normalizedText) +
            resolvedPlaces.map(\.normalizedText) +
            primaryKeywords +
            secondaryKeywords,
            maxCount: 64,
            maxLength: 120
        )
    }

    /// Main lexical query text for retrieval.
    var searchableText: String {
        allKeywords.joined(separator: " ")
    }

    var localBiasStrength: Double {
        if explicitRegionRequired { return 1.0 }
        if prefersLocalFirst && fulfillmentMode == .localOnly { return 1.0 }
        if prefersLocalFirst { return 0.8 }
        if marketType == .localService { return 0.7 }
        return 0.2
    }

    var remoteCompatibility: Double {
        if allowsRemoteOrShipped { return 1.0 }

        switch fulfillmentMode {
        case .remoteFriendly, .shippable, .digitalDelivery:
            return 1.0
        case .localPreferred:
            return 0.4
        case .localOnly:
            return 0.0
        case .unknown:
            return 0.3
        }
    }

    var preferredSurfaceTypes: [ExchangeIntent.SurfacePreference] {
        [surfacePreference]
    }

    func withNotes(_ value: String?) -> ExchangeIntentFacets {
        var copy = self
        copy.notes = Self.cleanOptionalField(value, maxLength: 500)
        return copy
    }
}

extension ExchangeIntentFacets {
    /// Whitespace normalization shared by facet sanitization and fit/retrieval helpers in this module.
    static func normalizeWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

private extension ExchangeIntentFacets {
    static func cleanOptionalField(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let cleaned = normalizeWhitespace(value)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maxLength))
    }

    static func sanitizeKeywords(
        _ values: [String],
        maxCount: Int,
        maxLength: Int
    ) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for raw in values {
            let cleaned = normalizeWhitespace(raw)
            guard !cleaned.isEmpty else { continue }

            let capped = String(cleaned.prefix(maxLength))
            let dedupeKey = capped.lowercased()

            guard !seen.contains(dedupeKey) else { continue }

            seen.insert(dedupeKey)
            output.append(capped)

            if output.count >= maxCount {
                break
            }
        }

        return output
    }

    static func sanitizeRequirements(
        _ values: [Requirement],
        maxCount: Int
    ) -> [Requirement] {
        var seen = Set<String>()
        var output: [Requirement] = []

        for item in values {
            let key = normalizeWhitespace(item.key)
            let value = normalizeWhitespace(item.value)

            guard !key.isEmpty, !value.isEmpty else { continue }

            let cappedKey = String(key.prefix(80))
            let cappedValue = String(value.prefix(200))
            let dedupeKey = "\(cappedKey.lowercased())|||\(cappedValue.lowercased())|||\(item.isHard)"

            guard !seen.contains(dedupeKey) else { continue }

            seen.insert(dedupeKey)
            output.append(
                Requirement(
                    id: item.id,
                    key: cappedKey,
                    value: cappedValue,
                    isHard: item.isHard
                )
            )

            if output.count >= maxCount {
                break
            }
        }

        return output
    }

    static func sanitizeEntities(
        _ values: [ExchangeQueryEntity],
        maxCount: Int
    ) -> [ExchangeQueryEntity] {
        var seen = Set<String>()
        var output: [ExchangeQueryEntity] = []

        for item in values {
            let normalized = normalizeWhitespace(item.normalizedText).lowercased()
            guard !normalized.isEmpty else { continue }
            let dedupe = "\(item.kind.rawValue)||\(normalized)"
            guard !seen.contains(dedupe) else { continue }
            seen.insert(dedupe)
            output.append(item)
            if output.count >= maxCount { break }
        }
        return output
    }

    static func sanitizeResolvedPlaces(
        _ values: [ExchangeResolvedPlace],
        maxCount: Int
    ) -> [ExchangeResolvedPlace] {
        var seen = Set<String>()
        var output: [ExchangeResolvedPlace] = []

        for item in values {
            let normalized = normalizeWhitespace(item.normalizedText).lowercased()
            guard !normalized.isEmpty else { continue }
            let dedupe = "\(item.canonicalID.lowercased())||\(normalized)"
            guard !seen.contains(dedupe) else { continue }
            seen.insert(dedupe)
            output.append(item)
            if output.count >= maxCount { break }
        }
        return output
    }
}

private extension ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
    func sanitized() -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        .init(
            domainCategory: domainCategory,
            objectType: ExchangeIntentFacets.normalizeWhitespace(objectType ?? "").isEmpty ? nil : String(ExchangeIntentFacets.normalizeWhitespace(objectType ?? "").prefix(120)),
            transactionIntent: transactionIntent,
            places: sanitizePlaces(places),
            attributes: sanitizeAttributes(attributes),
            preferences: sanitizePreferences(preferences),
            timeConstraints: sanitizeTimeConstraints(timeConstraints),
            commercialConstraints: sanitizeCommercial(commercialConstraints),
            broadRecallTokens: ExchangeIntentFacets.sanitizeKeywords(broadRecallTokens, maxCount: 48, maxLength: 120),
            semanticConcepts: ExchangeIntentFacets.sanitizeKeywords(semanticConcepts, maxCount: 24, maxLength: 120),
            hardConstraints: sanitizeConstraints(hardConstraints),
            softPreferences: sanitizeConstraints(softPreferences),
            clarificationGaps: ExchangeIntentFacets.sanitizeKeywords(clarificationGaps, maxCount: 16, maxLength: 180),
            rawUserText: String(ExchangeIntentFacets.normalizeWhitespace(rawUserText).prefix(500)),
            extractionSource: extractionSource,
            extractionConfidence: extractionConfidence.map { min(max($0, 0.0), 1.0) },
            extractedSurfacePreference: extractedSurfacePreference,
            extractedRoute: extractedRoute,
            canonicalEnglishSearchText: sanitizedCanonicalEnglishSearchText()
        )
    }

    private func sanitizedCanonicalEnglishSearchText() -> String? {
        guard let raw = canonicalEnglishSearchText else { return nil }
        let normalized = ExchangeIntentFacets.normalizeWhitespace(raw)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(500))
    }

    private func sanitizePlaces(_ values: [ExchangeIntentFacets.StructuredPlace]) -> [ExchangeIntentFacets.StructuredPlace] {
        var seen = Set<String>()
        var output: [ExchangeIntentFacets.StructuredPlace] = []
        for item in values {
            let normalized = ExchangeIntentFacets.normalizeWhitespace(item.normalizedText)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(
                .init(
                    id: item.id,
                    canonicalID: ExchangeIntentFacets.cleanOptionalField(item.canonicalID, maxLength: 120),
                    normalizedText: String(normalized.prefix(120)),
                    aliases: ExchangeIntentFacets.sanitizeKeywords(item.aliases, maxCount: 12, maxLength: 120),
                    confidence: min(max(item.confidence, 0.0), 1.0),
                    isHard: item.isHard
                )
            )
            if output.count >= 12 { break }
        }
        return output
    }

    private func sanitizeAttributes(_ values: [ExchangeIntentFacets.StructuredAttribute]) -> [ExchangeIntentFacets.StructuredAttribute] {
        var seen = Set<String>()
        var output: [ExchangeIntentFacets.StructuredAttribute] = []
        for item in values {
            let key = ExchangeIntentFacets.normalizeWhitespace(item.key).lowercased()
            let value = ExchangeIntentFacets.normalizeWhitespace(item.value)
            guard !key.isEmpty, !value.isEmpty else { continue }
            let dedupe = "\(key)||\(value.lowercased())"
            guard !seen.contains(dedupe) else { continue }
            seen.insert(dedupe)
            output.append(
                .init(
                    id: item.id,
                    key: String(key.prefix(80)),
                    value: String(value.prefix(120)),
                    numericValue: item.numericValue
                )
            )
            if output.count >= 16 { break }
        }
        return output
    }

    private func sanitizePreferences(_ values: [ExchangeIntentFacets.StructuredPreference]) -> [ExchangeIntentFacets.StructuredPreference] {
        var seen = Set<String>()
        var output: [ExchangeIntentFacets.StructuredPreference] = []
        for item in values {
            let key = ExchangeIntentFacets.normalizeWhitespace(item.key).lowercased()
            let value = ExchangeIntentFacets.cleanOptionalField(item.value, maxLength: 120)
            guard !key.isEmpty else { continue }
            let dedupe = "\(key)||\(value?.lowercased() ?? "")||\(item.strength.rawValue)"
            guard !seen.contains(dedupe) else { continue }
            seen.insert(dedupe)
            output.append(
                .init(
                    id: item.id,
                    key: String(key.prefix(80)),
                    value: value,
                    strength: item.strength
                )
            )
            if output.count >= 16 { break }
        }
        return output
    }

    private func sanitizeTimeConstraints(_ values: [ExchangeIntentFacets.StructuredTimeConstraint]) -> [ExchangeIntentFacets.StructuredTimeConstraint] {
        var seen = Set<String>()
        var output: [ExchangeIntentFacets.StructuredTimeConstraint] = []
        for item in values {
            let text = ExchangeIntentFacets.normalizeWhitespace(item.text)
            guard !text.isEmpty else { continue }
            let dedupe = "\(item.kind.rawValue)||\(text.lowercased())"
            guard !seen.contains(dedupe) else { continue }
            seen.insert(dedupe)
            output.append(.init(id: item.id, kind: item.kind, text: String(text.prefix(140))))
            if output.count >= 10 { break }
        }
        return output
    }

    private func sanitizeCommercial(_ values: [ExchangeIntentFacets.StructuredCommercialConstraint]) -> [ExchangeIntentFacets.StructuredCommercialConstraint] {
        var seen = Set<String>()
        var output: [ExchangeIntentFacets.StructuredCommercialConstraint] = []
        for item in values {
            let key = ExchangeIntentFacets.normalizeWhitespace(item.key).lowercased()
            let value = ExchangeIntentFacets.normalizeWhitespace(item.value)
            guard !key.isEmpty, !value.isEmpty else { continue }
            let dedupe = "\(item.kind.rawValue)||\(key)||\(value.lowercased())||\(item.isHard)"
            guard !seen.contains(dedupe) else { continue }
            seen.insert(dedupe)
            output.append(
                .init(
                    id: item.id,
                    kind: item.kind,
                    key: String(key.prefix(80)),
                    value: String(value.prefix(140)),
                    isHard: item.isHard
                )
            )
            if output.count >= 16 { break }
        }
        return output
    }

    private func sanitizeConstraints(_ values: [ExchangeIntent.Constraint]) -> [ExchangeIntent.Constraint] {
        var seen = Set<String>()
        var output: [ExchangeIntent.Constraint] = []
        for item in values {
            let key = ExchangeIntentFacets.normalizeWhitespace(item.key).lowercased()
            let value = ExchangeIntentFacets.normalizeWhitespace(item.value).lowercased()
            guard !key.isEmpty, !value.isEmpty else { continue }
            let dedupe = "\(key)||\(value)||\(item.isHardConstraint)"
            guard !seen.contains(dedupe) else { continue }
            seen.insert(dedupe)
            output.append(
                .init(
                    id: item.id,
                    key: String(key.prefix(80)),
                    value: String(value.prefix(180)),
                    isHardConstraint: item.isHardConstraint
                )
            )
            if output.count >= 24 { break }
        }
        return output
    }
}
