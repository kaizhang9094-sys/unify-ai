import Foundation

// MARK: - Neutral surface / strength / policy enums

public enum ExchangeSemanticSurfaceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case offer
    case offerObject
    case capability
    case affinity
    case seeking
    case profile
    case mixed
    case unknown
}

public enum ExchangeSemanticProofStrength: String, Codable, Sendable, Hashable, CaseIterable {
    /// Strong embedding or high-overlap direct hit aligned with the target need.
    case exact
    /// Direct offer/service document or proven object embedding above the minimum floor.
    case concrete
    /// Related surface with meaningful lexical overlap but not a direct commercial anchor.
    case compatible
    /// Profile-bridge / inherited recall without independent concrete support.
    case weakRecall

    public var selectionPriority: Int {
        switch self {
        case .exact: return 4
        case .concrete: return 3
        case .compatible: return 2
        case .weakRecall: return 1
        }
    }

    public var satisfiesConcretePolicy: Bool {
        switch self {
        case .exact, .concrete, .compatible:
            return true
        case .weakRecall:
            return false
        }
    }
}

public enum ExchangeMinimumProofPolicy: String, Codable, Sendable, Hashable, CaseIterable {
    /// Broad recall; weak overlap may advance when other gates pass.
    case recallOnly
    /// Provider / service / hire-style targets need a concrete offer or capability surface proof.
    case concreteOfferOrCapabilityRequired
    /// Transactional object targets need a concrete offer or object-embedding proof.
    case concreteSurfaceRequired

    public var requiresConcreteProof: Bool {
        switch self {
        case .recallOnly:
            return false
        case .concreteOfferOrCapabilityRequired, .concreteSurfaceRequired:
            return true
        }
    }
}

public enum ExchangeSemanticProofChannel: String, Codable, Sendable, Hashable, CaseIterable {
    case objectEmbedding
    case directOfferDocument
    case capabilitySurface
    case affinitySurface
    case inheritedOffer
    case providerProfile
}

// MARK: - Query target

public struct ExchangeSemanticTarget: Codable, Sendable, Hashable {
    public struct CarrierText: Codable, Sendable, Hashable {
        public var rawUserText: String?
        public var semanticText: String?
        public var semanticEmbeddingText: String?
        public var objectQueryText: String?
        public var canonicalEnglishSearchText: String?

        public init(
            rawUserText: String? = nil,
            semanticText: String? = nil,
            semanticEmbeddingText: String? = nil,
            objectQueryText: String? = nil,
            canonicalEnglishSearchText: String? = nil
        ) {
            self.rawUserText = ExchangeSemanticTarget.trimmedNonEmpty(rawUserText)
            self.semanticText = ExchangeSemanticTarget.trimmedNonEmpty(semanticText)
            self.semanticEmbeddingText = ExchangeSemanticTarget.trimmedNonEmpty(semanticEmbeddingText)
            self.objectQueryText = ExchangeSemanticTarget.trimmedNonEmpty(objectQueryText)
            self.canonicalEnglishSearchText = ExchangeSemanticTarget.trimmedNonEmpty(canonicalEnglishSearchText)
        }
    }

    public var objectType: String?
    /// Resolved need phrase (objectType when present, otherwise canonical semantic concept).
    public var need: String?
    public var transactionIntent: ExchangeIntentFacets.TransactionIntent?
    public var domainCategory: ExchangeIntentFacets.DomainCategory?
    public var queryIntentClass: ExchangeIntent.QueryIntentClass
    public var surfacePreference: ExchangeIntent.SurfacePreference
    public var carrier: CarrierText
    public var providerTerms: [String]
    public var capabilityTerms: [String]
    public var affinityTerms: [String]
    public var semanticConcepts: [String]
    public var minimumProofPolicy: ExchangeMinimumProofPolicy
    public var acceptableProofChannels: Set<ExchangeSemanticProofChannel>

    public init(
        objectType: String? = nil,
        need: String? = nil,
        transactionIntent: ExchangeIntentFacets.TransactionIntent? = nil,
        domainCategory: ExchangeIntentFacets.DomainCategory? = nil,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference,
        carrier: CarrierText = .init(),
        providerTerms: [String] = [],
        capabilityTerms: [String] = [],
        affinityTerms: [String] = [],
        semanticConcepts: [String] = [],
        minimumProofPolicy: ExchangeMinimumProofPolicy = .recallOnly,
        acceptableProofChannels: Set<ExchangeSemanticProofChannel> = Set(ExchangeSemanticProofChannel.allCases)
    ) {
        self.objectType = Self.trimmedNonEmpty(objectType)
        self.need = Self.trimmedNonEmpty(need)
        self.transactionIntent = transactionIntent
        self.domainCategory = domainCategory
        self.queryIntentClass = queryIntentClass
        self.surfacePreference = surfacePreference
        self.carrier = carrier
        self.providerTerms = Self.normalizedTerms(providerTerms)
        self.capabilityTerms = Self.normalizedTerms(capabilityTerms)
        self.affinityTerms = Self.normalizedTerms(affinityTerms)
        self.semanticConcepts = Self.normalizedTerms(semanticConcepts)
        self.minimumProofPolicy = minimumProofPolicy
        self.acceptableProofChannels = acceptableProofChannels
    }

    public static func from(facets: ExchangeIntentFacets) -> ExchangeSemanticTarget {
        let si = facets.searchIntent
        let objectType = si.flatMap { trimmedNonEmpty($0.objectType) }
        let need = resolveNeed(facets: facets, searchIntent: si)
        let policy = resolveMinimumProofPolicy(facets: facets, need: need, searchIntent: si)
        let channels = resolveAcceptableProofChannels(
            policy: policy,
            queryIntentClass: facets.queryIntentClass,
            surfacePreference: facets.surfacePreference
        )
        let carrier = resolveCarrier(facets: facets, searchIntent: si)

        return ExchangeSemanticTarget(
            objectType: objectType,
            need: need,
            transactionIntent: si?.transactionIntent,
            domainCategory: si?.domainCategory,
            queryIntentClass: facets.queryIntentClass,
            surfacePreference: facets.surfacePreference,
            carrier: carrier,
            providerTerms: facets.providerTerms,
            capabilityTerms: facets.capabilityTerms,
            affinityTerms: facets.affinityTerms,
            semanticConcepts: si?.semanticConcepts ?? [],
            minimumProofPolicy: policy,
            acceptableProofChannels: channels
        )
    }

    public static func from(thread: ExchangeThread) -> ExchangeSemanticTarget {
        if let facets = thread.facets {
            return from(facets: facets)
        }
        return ExchangeSemanticTarget(
            queryIntentClass: thread.intent.queryIntentClass,
            surfacePreference: thread.intent.surfacePreference,
            carrier: .init(rawUserText: thread.primarySearchText)
        )
    }

    // MARK: - Derivation helpers

    private static func resolveNeed(
        facets: ExchangeIntentFacets,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    ) -> String? {
        if let objectType = searchIntent.flatMap({ trimmedNonEmpty($0.objectType) }) {
            return objectType
        }
        if let firstConcept = searchIntent?.semanticConcepts.compactMap({ trimmedNonEmpty($0) }).first {
            return firstConcept
        }
        if let role = trimmedNonEmpty(facets.targetRole) {
            return role
        }
        if let activity = trimmedNonEmpty(facets.activity) {
            return activity
        }
        if let service = trimmedNonEmpty(facets.serviceCategory) {
            return service
        }
        if let product = trimmedNonEmpty(facets.productCategory) {
            return product
        }
        if let term = facets.capabilityTerms.compactMap({ trimmedNonEmpty($0) }).first {
            return term
        }
        if let term = facets.providerTerms.compactMap({ trimmedNonEmpty($0) }).first {
            return term
        }
        return nil
    }

    private static func resolveMinimumProofPolicy(
        facets: ExchangeIntentFacets,
        need: String?,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    ) -> ExchangeMinimumProofPolicy {
        guard hasConcreteNeed(facets: facets, need: need, searchIntent: searchIntent) else {
            return .recallOnly
        }

        switch facets.queryIntentClass {
        case .offerSearch:
            return .concreteSurfaceRequired
        case .providerSearch, .capabilitySearch:
            return .concreteOfferOrCapabilityRequired
        case .collaborationSearch:
            if facets.surfacePreference == .capability || need != nil {
                return .concreteOfferOrCapabilityRequired
            }
            return .recallOnly
        case .socialAffinitySearch, .relationshipSearch:
            return .recallOnly
        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            if facets.surfacePreference == .offer, need != nil {
                return .concreteSurfaceRequired
            }
            if need != nil, searchIntent?.transactionIntent != nil {
                return .concreteOfferOrCapabilityRequired
            }
            return .recallOnly
        }
    }

    private static func hasConcreteNeed(
        facets: ExchangeIntentFacets,
        need: String?,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    ) -> Bool {
        if need != nil {
            return true
        }
        if let si = searchIntent {
            if !si.semanticConcepts.isEmpty,
               si.transactionIntent != nil || facets.queryIntentClass.isCommercialDiscovery {
                return true
            }
            switch si.domainCategory {
            case .homeService, .professionalService, .product, .realEstate:
                if si.transactionIntent != nil {
                    return true
                }
            case .general:
                break
            }
        }
        switch facets.queryIntentClass {
        case .providerSearch, .offerSearch:
            return !facets.providerTerms.isEmpty
                || !facets.capabilityTerms.isEmpty
                || !facets.primaryKeywords.isEmpty
        default:
            return false
        }
    }

    private static func resolveAcceptableProofChannels(
        policy: ExchangeMinimumProofPolicy,
        queryIntentClass: ExchangeIntent.QueryIntentClass,
        surfacePreference: ExchangeIntent.SurfacePreference
    ) -> Set<ExchangeSemanticProofChannel> {
        switch policy {
        case .recallOnly:
            return Set(ExchangeSemanticProofChannel.allCases)
        case .concreteSurfaceRequired:
            return [.objectEmbedding, .directOfferDocument]
        case .concreteOfferOrCapabilityRequired:
            var channels: Set<ExchangeSemanticProofChannel> = [
                .objectEmbedding,
                .directOfferDocument,
                .capabilitySurface,
            ]
            if queryIntentClass == .socialAffinitySearch || surfacePreference == .affinity {
                channels.insert(.affinitySurface)
            }
            return channels
        }
    }

    private static func resolveCarrier(
        facets: ExchangeIntentFacets,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
    ) -> CarrierText {
        CarrierText(
            rawUserText: searchIntent?.rawUserText,
            semanticText: facets.searchableText,
            objectQueryText: searchIntent.flatMap { trimmedNonEmpty($0.objectType) },
            canonicalEnglishSearchText: searchIntent?.canonicalEnglishSearchText
        )
    }

    private static func normalizedTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        output.reserveCapacity(terms.count)
        for raw in terms {
            guard let trimmed = trimmedNonEmpty(raw) else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }

    fileprivate static func trimmedNonEmpty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ExchangeIntent.QueryIntentClass {
    var isCommercialDiscovery: Bool {
        switch self {
        case .providerSearch, .offerSearch, .capabilitySearch, .collaborationSearch:
            return true
        case .socialAffinitySearch, .relationshipSearch, .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return false
        }
    }
}

// MARK: - Candidate proof

public struct ExchangeCandidateSemanticProof: Codable, Sendable, Hashable {
    public enum AttachmentReason: String, Codable, Sendable, Hashable, CaseIterable {
        case objectEmbeddingProven
        case directOfferDocumentHit
        case profileInheritedOffer
        case capabilitySurfaceBridge
        case affinitySurfaceBridge
        case unmatched
    }

    public struct OfferAttachment: Codable, Sendable, Hashable {
        public var offerID: String
        public var reason: AttachmentReason
        public var proofStrength: ExchangeSemanticProofStrength
        public var objectEvidenceScore: Double?
        public var lexicalOverlap: Int
        public var targetOverlap: Int
        public var genericOverlap: Int
        public var satisfiesMinimumProof: Bool

        private enum CodingKeys: String, CodingKey {
            case offerID
            case reason
            case proofStrength
            case objectEvidenceScore
            case lexicalOverlap
            case targetOverlap
            case genericOverlap
            case satisfiesMinimumProof
        }

        public init(
            offerID: String,
            reason: AttachmentReason,
            proofStrength: ExchangeSemanticProofStrength,
            objectEvidenceScore: Double? = nil,
            lexicalOverlap: Int = 0,
            targetOverlap: Int = 0,
            genericOverlap: Int = 0,
            satisfiesMinimumProof: Bool = false
        ) {
            self.offerID = offerID
            self.reason = reason
            self.proofStrength = proofStrength
            self.objectEvidenceScore = objectEvidenceScore
            self.lexicalOverlap = lexicalOverlap
            self.targetOverlap = targetOverlap
            self.genericOverlap = genericOverlap
            self.satisfiesMinimumProof = satisfiesMinimumProof
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            offerID = try container.decode(String.self, forKey: .offerID)
            reason = try container.decode(AttachmentReason.self, forKey: .reason)
            proofStrength = try container.decode(ExchangeSemanticProofStrength.self, forKey: .proofStrength)
            objectEvidenceScore = try container.decodeIfPresent(Double.self, forKey: .objectEvidenceScore)
            lexicalOverlap = try container.decodeIfPresent(Int.self, forKey: .lexicalOverlap) ?? 0
            targetOverlap = try container.decodeIfPresent(Int.self, forKey: .targetOverlap) ?? 0
            genericOverlap = try container.decodeIfPresent(Int.self, forKey: .genericOverlap) ?? 0
            satisfiesMinimumProof = try container.decodeIfPresent(Bool.self, forKey: .satisfiesMinimumProof) ?? false
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(offerID, forKey: .offerID)
            try container.encode(reason, forKey: .reason)
            try container.encode(proofStrength, forKey: .proofStrength)
            try container.encodeIfPresent(objectEvidenceScore, forKey: .objectEvidenceScore)
            try container.encode(lexicalOverlap, forKey: .lexicalOverlap)
            try container.encode(targetOverlap, forKey: .targetOverlap)
            try container.encode(genericOverlap, forKey: .genericOverlap)
            try container.encode(satisfiesMinimumProof, forKey: .satisfiesMinimumProof)
        }
    }

    public struct SurfaceAttachment: Codable, Sendable, Hashable {
        public var surfaceKind: ExchangeSemanticSurfaceKind
        public var reason: AttachmentReason
        public var proofStrength: ExchangeSemanticProofStrength
        public var lexicalOverlap: Int
        public var satisfiesMinimumProof: Bool

        private enum CodingKeys: String, CodingKey {
            case surfaceKind
            case reason
            case proofStrength
            case lexicalOverlap
            case satisfiesMinimumProof
        }

        public init(
            surfaceKind: ExchangeSemanticSurfaceKind,
            reason: AttachmentReason,
            proofStrength: ExchangeSemanticProofStrength,
            lexicalOverlap: Int = 0,
            satisfiesMinimumProof: Bool = false
        ) {
            self.surfaceKind = surfaceKind
            self.reason = reason
            self.proofStrength = proofStrength
            self.lexicalOverlap = lexicalOverlap
            self.satisfiesMinimumProof = satisfiesMinimumProof
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            surfaceKind = try container.decode(ExchangeSemanticSurfaceKind.self, forKey: .surfaceKind)
            reason = try container.decode(AttachmentReason.self, forKey: .reason)
            proofStrength = try container.decode(ExchangeSemanticProofStrength.self, forKey: .proofStrength)
            lexicalOverlap = try container.decodeIfPresent(Int.self, forKey: .lexicalOverlap) ?? 0
            satisfiesMinimumProof = try container.decodeIfPresent(Bool.self, forKey: .satisfiesMinimumProof) ?? false
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(surfaceKind, forKey: .surfaceKind)
            try container.encode(reason, forKey: .reason)
            try container.encode(proofStrength, forKey: .proofStrength)
            try container.encode(lexicalOverlap, forKey: .lexicalOverlap)
            try container.encode(satisfiesMinimumProof, forKey: .satisfiesMinimumProof)
        }
    }

    public struct Summary: Codable, Sendable, Hashable {
        public var primaryOfferID: String?
        public var maxProofStrength: ExchangeSemanticProofStrength
        public var satisfiesMinimumProof: Bool
        public var hasWeakRecallOnly: Bool

        private enum CodingKeys: String, CodingKey {
            case primaryOfferID
            case maxProofStrength
            case satisfiesMinimumProof
            case hasWeakRecallOnly
        }

        public init(
            primaryOfferID: String? = nil,
            maxProofStrength: ExchangeSemanticProofStrength = .weakRecall,
            satisfiesMinimumProof: Bool = false,
            hasWeakRecallOnly: Bool = true
        ) {
            if let primaryOfferID {
                let trimmed = primaryOfferID.trimmingCharacters(in: .whitespacesAndNewlines)
                self.primaryOfferID = trimmed.isEmpty ? nil : trimmed
            } else {
                self.primaryOfferID = nil
            }
            self.maxProofStrength = maxProofStrength
            self.satisfiesMinimumProof = satisfiesMinimumProof
            self.hasWeakRecallOnly = hasWeakRecallOnly
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            primaryOfferID = try container.decodeIfPresent(String.self, forKey: .primaryOfferID)
            maxProofStrength = try container.decodeIfPresent(
                ExchangeSemanticProofStrength.self,
                forKey: .maxProofStrength
            ) ?? .weakRecall
            satisfiesMinimumProof = try container.decodeIfPresent(Bool.self, forKey: .satisfiesMinimumProof) ?? false
            hasWeakRecallOnly = try container.decodeIfPresent(Bool.self, forKey: .hasWeakRecallOnly) ?? true
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(primaryOfferID, forKey: .primaryOfferID)
            try container.encode(maxProofStrength, forKey: .maxProofStrength)
            try container.encode(satisfiesMinimumProof, forKey: .satisfiesMinimumProof)
            try container.encode(hasWeakRecallOnly, forKey: .hasWeakRecallOnly)
        }
    }

    public var offerAttachments: [OfferAttachment]
    public var surfaceAttachment: SurfaceAttachment?
    public var summary: Summary

    private enum CodingKeys: String, CodingKey {
        case offerAttachments
        case surfaceAttachment
        case summary
        /// Legacy envelope keys persisted alongside proof before match-level fields existed.
        case provenObjectOfferIDs
        case objectEvidenceScoreByOfferID
    }

    public init(
        offerAttachments: [OfferAttachment] = [],
        surfaceAttachment: SurfaceAttachment? = nil,
        summary: Summary = .init()
    ) {
        self.offerAttachments = offerAttachments
        self.surfaceAttachment = surfaceAttachment
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offerAttachments = try container.decodeIfPresent([OfferAttachment].self, forKey: .offerAttachments) ?? []
        surfaceAttachment = try container.decodeIfPresent(SurfaceAttachment.self, forKey: .surfaceAttachment)
        summary = try container.decodeIfPresent(Summary.self, forKey: .summary) ?? .init()
        // Absorb legacy object-lane keys if present; canonical ownership is `ExchangeMatch`.
        _ = try container.decodeIfPresent([String].self, forKey: .provenObjectOfferIDs)
        _ = try container.decodeIfPresent([String: Double].self, forKey: .objectEvidenceScoreByOfferID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(offerAttachments, forKey: .offerAttachments)
        try container.encodeIfPresent(surfaceAttachment, forKey: .surfaceAttachment)
        try container.encode(summary, forKey: .summary)
    }

    public static let empty = ExchangeCandidateSemanticProof()

    public var isEmpty: Bool {
        offerAttachments.isEmpty && surfaceAttachment == nil
    }
}

public extension ExchangeIntentFacets {
    var semanticTarget: ExchangeSemanticTarget {
        ExchangeSemanticTarget.from(facets: self)
    }
}
