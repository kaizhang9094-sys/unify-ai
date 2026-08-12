import Foundation

// MARK: - Build input

public enum ExchangeProviderDisplaySourceSurface: String, Sendable, Hashable, Codable {
    case forYouFreshDiscovery
    case forYouCachedHydration
}

public enum ExchangeProviderDisplaySurface: String, Sendable, Hashable {
    case forYouRail
    case forYouSheet
}

public struct ExchangeProviderDisplayBuildInput: Sendable, Hashable {
    public var sourceSurface: ExchangeProviderDisplaySourceSurface
    public var publicProfile: ExchangePublicNodeProfile?
    public var surfacedOffer: ExchangeOffer?
    public var counterparty: ExchangeCounterparty?
    public var matchInference: ExchangeMatchInferenceSlice?
    public var surfaceLead: ExchangePresentationSurfaceLead?
    public var policy: ExchangeProviderDisplayPolicy
    /// Optional reachability context for badges (not shown as raw enums).
    public var contactPosture: ExchangeProviderDisplayContactPosture?

    public init(
        sourceSurface: ExchangeProviderDisplaySourceSurface,
        publicProfile: ExchangePublicNodeProfile? = nil,
        surfacedOffer: ExchangeOffer? = nil,
        counterparty: ExchangeCounterparty? = nil,
        matchInference: ExchangeMatchInferenceSlice? = nil,
        surfaceLead: ExchangePresentationSurfaceLead? = nil,
        policy: ExchangeProviderDisplayPolicy,
        contactPosture: ExchangeProviderDisplayContactPosture? = nil
    ) {
        self.sourceSurface = sourceSurface
        self.publicProfile = publicProfile
        self.surfacedOffer = surfacedOffer
        self.counterparty = counterparty
        self.matchInference = matchInference
        self.surfaceLead = surfaceLead
        self.policy = policy
        self.contactPosture = contactPosture
    }
}

public struct ExchangeProviderDisplayContactPosture: Sendable, Hashable {
    public var acceptingInbound: Bool
    public var requiresIntroduction: Bool
    public var allowsDirectContact: Bool
    public var isRoutable: Bool

    public init(
        acceptingInbound: Bool,
        requiresIntroduction: Bool,
        allowsDirectContact: Bool,
        isRoutable: Bool
    ) {
        self.acceptingInbound = acceptingInbound
        self.requiresIntroduction = requiresIntroduction
        self.allowsDirectContact = allowsDirectContact
        self.isRoutable = isRoutable
    }
}

// MARK: - Inference (internal only; not rendered when allowInference is false)

public struct ExchangeMatchInferenceSlice: Sendable, Hashable {
    public var score: Double?
    public var strength: ExchangeProviderDisplayStrength?
    public var reasons: [String]
    public var cautions: [String]
    public var recommendation: String?
    public var matchedTerms: [String]
    public var fitPercent: Int?

    public init(
        score: Double? = nil,
        strength: ExchangeProviderDisplayStrength? = nil,
        reasons: [String] = [],
        cautions: [String] = [],
        recommendation: String? = nil,
        matchedTerms: [String] = [],
        fitPercent: Int? = nil
    ) {
        self.score = score
        self.strength = strength
        self.reasons = reasons
        self.cautions = cautions
        self.recommendation = recommendation
        self.matchedTerms = matchedTerms
        self.fitPercent = fitPercent
    }
}

public enum ExchangeProviderDisplayStrength: String, Sendable, Hashable {
    case weak
    case moderate
    case strong
}

// MARK: - Policy

public struct ExchangeProviderDisplayPolicy: Sendable, Hashable {
    public var surface: ExchangeProviderDisplaySurface
    public var maxBadges: Int
    public var maxPreviewLines: Int
    public var maxProfileLines: Int
    public var maxOfferLines: Int
    public var maxCommercialLines: Int
    public var maxNeedsConfirmationLines: Int
    public var allowInference: Bool
    public var allowCommercialFacts: Bool
    public var showSourceLabels: Bool
    public var allowDiagnostics: Bool

    public init(
        surface: ExchangeProviderDisplaySurface,
        maxBadges: Int = 3,
        maxPreviewLines: Int = 2,
        maxProfileLines: Int = 4,
        maxOfferLines: Int = 3,
        maxCommercialLines: Int = 6,
        maxNeedsConfirmationLines: Int = 3,
        allowInference: Bool = false,
        allowCommercialFacts: Bool = true,
        showSourceLabels: Bool = false,
        allowDiagnostics: Bool = true
    ) {
        self.surface = surface
        self.maxBadges = max(0, maxBadges)
        self.maxPreviewLines = max(0, maxPreviewLines)
        self.maxProfileLines = max(0, maxProfileLines)
        self.maxOfferLines = max(0, maxOfferLines)
        self.maxCommercialLines = max(0, maxCommercialLines)
        self.maxNeedsConfirmationLines = max(0, maxNeedsConfirmationLines)
        self.allowInference = allowInference
        self.allowCommercialFacts = allowCommercialFacts
        self.showSourceLabels = showSourceLabels
        self.allowDiagnostics = allowDiagnostics
    }

    public static let forYouFreshDefault = ExchangeProviderDisplayPolicy(
        surface: .forYouRail,
        maxPreviewLines: 2,
        allowInference: false,
        allowCommercialFacts: true
    )

    public static let forYouCachedDefault = ExchangeProviderDisplayPolicy(
        surface: .forYouRail,
        maxPreviewLines: 2,
        allowInference: false,
        allowCommercialFacts: false
    )
}

// MARK: - Display atoms

public enum ExchangeDisplaySource: String, Sendable, Hashable, Codable {
    case providerProfile
    case providerOffer
    case commercialFact
    case appInferred
    case retrievalEvidence
    case missingFact
    case localPolicy
    case fallback
}

public enum ExchangeDisplaySourceGroup: String, Sendable, Hashable, Codable {
    case profile
    case offer
    case commercial
    case needsConfirmation
    case inference
    case fallback
}

public enum ExchangeDisplayLineImportance: String, Sendable, Hashable, Codable {
    case low
    case normal
    case high
}

public struct ExchangeDisplayLine: Sendable, Hashable, Codable {
    public var text: String
    public var source: ExchangeDisplaySource
    public var sourceGroup: ExchangeDisplaySourceGroup
    public var fieldKey: String?
    public var importance: ExchangeDisplayLineImportance

    public init(
        text: String,
        source: ExchangeDisplaySource,
        sourceGroup: ExchangeDisplaySourceGroup,
        fieldKey: String? = nil,
        importance: ExchangeDisplayLineImportance = .normal
    ) {
        self.text = text
        self.source = source
        self.sourceGroup = sourceGroup
        self.fieldKey = fieldKey
        self.importance = importance
    }
}

public struct ExchangeDisplayBadge: Sendable, Hashable, Codable {
    public var label: String
    public var source: ExchangeDisplaySource
    public var fieldKey: String?

    public init(label: String, source: ExchangeDisplaySource, fieldKey: String? = nil) {
        self.label = label
        self.source = source
        self.fieldKey = fieldKey
    }
}

public struct ExchangeDisplaySection: Sendable, Hashable, Codable {
    public var title: String
    public var sourceGroup: ExchangeDisplaySourceGroup
    public var lines: [ExchangeDisplayLine]

    public init(title: String, sourceGroup: ExchangeDisplaySourceGroup, lines: [ExchangeDisplayLine]) {
        self.title = title
        self.sourceGroup = sourceGroup
        self.lines = lines
    }
}

public struct ExchangeDisplayCompleteness: Sendable, Hashable, Codable {
    public var hasIdentity: Bool
    public var hasProfile: Bool
    public var hasOffer: Bool
    public var hasImage: Bool
    public var hasCommercialFacts: Bool
    public var hasPricing: Bool
    public var hasServiceArea: Bool
    public var hasAvailability: Bool
    public var isThinProfile: Bool
    public var isProfileOnlyHydrated: Bool

    public init(
        hasIdentity: Bool = false,
        hasProfile: Bool = false,
        hasOffer: Bool = false,
        hasImage: Bool = false,
        hasCommercialFacts: Bool = false,
        hasPricing: Bool = false,
        hasServiceArea: Bool = false,
        hasAvailability: Bool = false,
        isThinProfile: Bool = false,
        isProfileOnlyHydrated: Bool = false
    ) {
        self.hasIdentity = hasIdentity
        self.hasProfile = hasProfile
        self.hasOffer = hasOffer
        self.hasImage = hasImage
        self.hasCommercialFacts = hasCommercialFacts
        self.hasPricing = hasPricing
        self.hasServiceArea = hasServiceArea
        self.hasAvailability = hasAvailability
        self.isThinProfile = isThinProfile
        self.isProfileOnlyHydrated = isProfileOnlyHydrated
    }
}

public struct ExchangeProviderDisplayDiagnostics: Sendable, Hashable, Codable {
    public var sourceSurface: ExchangeProviderDisplaySourceSurface
    public var hadCanonicalProfile: Bool
    public var hadCanonicalOffer: Bool
    public var hadCommercialFacts: Bool
    public var usedLegacyAdapter: Bool
    public var missingReason: String?

    public init(
        sourceSurface: ExchangeProviderDisplaySourceSurface,
        hadCanonicalProfile: Bool,
        hadCanonicalOffer: Bool,
        hadCommercialFacts: Bool,
        usedLegacyAdapter: Bool = false,
        missingReason: String? = nil
    ) {
        self.sourceSurface = sourceSurface
        self.hadCanonicalProfile = hadCanonicalProfile
        self.hadCanonicalOffer = hadCanonicalOffer
        self.hadCommercialFacts = hadCommercialFacts
        self.usedLegacyAdapter = usedLegacyAdapter
        self.missingReason = missingReason
    }
}

// MARK: - Provider Details card (canonical provider-authored sections)

public struct ExchangeProviderDetailsCardBuildInput: Sendable, Hashable {
    public var profile: ExchangePublicNodeProfile?
    public var offer: ExchangeOffer?
    public var selectedOfferID: String?
    /// Hero / sheet title used to suppress duplicate offer-title rows.
    public var contextTitle: String?
    /// Phase 2A/2B: derived presentation mode gates canonical section emission.
    public var presentationContext: ExchangeProviderDetailsPresentationContext

    public init(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        selectedOfferID: String? = nil,
        contextTitle: String? = nil,
        presentationContext: ExchangeProviderDetailsPresentationContext = .unknown
    ) {
        self.profile = profile
        self.offer = offer
        self.selectedOfferID = selectedOfferID
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        self.contextTitle = contextTitle
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        self.presentationContext = presentationContext
    }
}

public struct ExchangeProviderDetailsCardPolicy: Sendable, Hashable {
    public var maxSections: Int
    public var maxLinesPerSection: Int
    public var maxPackages: Int
    public var maxFAQs: Int
    public var maxBuyerInputs: Int

    public init(
        maxSections: Int = 5,
        maxLinesPerSection: Int = 3,
        maxPackages: Int = 3,
        maxFAQs: Int = 2,
        maxBuyerInputs: Int = 2
    ) {
        self.maxSections = max(0, maxSections)
        self.maxLinesPerSection = max(0, maxLinesPerSection)
        self.maxPackages = max(0, maxPackages)
        self.maxFAQs = max(0, maxFAQs)
        self.maxBuyerInputs = max(0, maxBuyerInputs)
    }

    public static let `default` = ExchangeProviderDetailsCardPolicy()
}

public struct ExchangeProviderDetailsCardDisplay: Sendable, Hashable, Codable {
    public var sections: [ExchangeDisplaySection]
    public var completeness: ExchangeDisplayCompleteness
    /// Phase 3D: presentation mode for canonical build and ThreadView legacy fallback gating.
    public var presentationContext: ExchangeProviderDetailsPresentationContext

    public init(
        sections: [ExchangeDisplaySection] = [],
        completeness: ExchangeDisplayCompleteness = ExchangeDisplayCompleteness(),
        presentationContext: ExchangeProviderDetailsPresentationContext = .unknown
    ) {
        self.sections = sections
        self.completeness = completeness
        self.presentationContext = presentationContext
    }

    public var hasContent: Bool {
        sections.contains { !$0.lines.isEmpty }
    }
}

public struct ExchangeProviderDisplayCard: Sendable, Hashable, Codable {
    public var title: String
    public var subtitle: String?
    public var imageURL: String?
    public var galleryImageURLs: [String]
    public var badges: [ExchangeDisplayBadge]
    public var previewLines: [ExchangeDisplayLine]
    public var profileLines: [ExchangeDisplayLine]
    public var offerLines: [ExchangeDisplayLine]
    public var commercialLines: [ExchangeDisplayLine]
    public var needsConfirmationLines: [ExchangeDisplayLine]
    public var detailSections: [ExchangeDisplaySection]
    public var completeness: ExchangeDisplayCompleteness
    public var diagnostics: ExchangeProviderDisplayDiagnostics

    public init(
        title: String,
        subtitle: String? = nil,
        imageURL: String? = nil,
        galleryImageURLs: [String] = [],
        badges: [ExchangeDisplayBadge] = [],
        previewLines: [ExchangeDisplayLine] = [],
        profileLines: [ExchangeDisplayLine] = [],
        offerLines: [ExchangeDisplayLine] = [],
        commercialLines: [ExchangeDisplayLine] = [],
        needsConfirmationLines: [ExchangeDisplayLine] = [],
        detailSections: [ExchangeDisplaySection] = [],
        completeness: ExchangeDisplayCompleteness = ExchangeDisplayCompleteness(),
        diagnostics: ExchangeProviderDisplayDiagnostics
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.galleryImageURLs = galleryImageURLs
        self.badges = badges
        self.previewLines = previewLines
        self.profileLines = profileLines
        self.offerLines = offerLines
        self.commercialLines = commercialLines
        self.needsConfirmationLines = needsConfirmationLines
        self.detailSections = detailSections
        self.completeness = completeness
        self.diagnostics = diagnostics
    }
}
