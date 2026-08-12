import Foundation

/// Public, consent-shaped coordination surface for a federated secretary node.
///
/// This is NOT the user's private memory or full identity model.
/// It is the small public surface another node may use to determine:
/// - whether this node is relevant
/// - whether this node is reachable
/// - how this node prefers to be approached
/// - what categories of requests this node is open to
///
/// Keep this compact, durable, and explainable.
///
/// Design intent:
/// - thin enough to publish or cache safely
/// - expressive enough to support consent-aware routing
/// - stable enough to avoid relying on raw LLM phrasing alone
public struct ExchangePublicNodeProfile: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = String

    public var id: ID
    public var nodeID: String
    public var counterpartyID: ExchangeCounterparty.ID?

    public var displayName: String?
    public var headline: String?
    public var summary: String?

    /// Whether this public profile is currently visible for discovery/routing.
    public var visibility: Visibility

    /// Coarse public interest surface.
    public var interests: [String]

    /// What this node publicly offers or can help with.
    public var offers: [String]

    /// What this node is open to receiving.
    ///
    /// Example:
    /// - local service requests
    /// - supplier introductions
    /// - movie recommendations
    /// - collaboration inquiries
    public var openTo: [String]

    /// What this node does not want to receive.
    ///
    /// Example:
    /// - cold sales outreach
    /// - political debate
    /// - dating requests
    /// - high-pressure negotiation
    public var excludedTopics: [String]

    /// Public activity / role tags.
    public var activityTags: [String]

    /// Coarse place / region tags.
    public var regionTags: [String]

    /// Server-enriched canonical place IDs (additive; empty for legacy payloads).
    public var canonicalRegionIDs: [String]

    /// Broader region hierarchy IDs from the server (additive).
    public var parentRegionIDs: [String]

    /// Human / lexical region aliases from the server (additive).
    public var regionAliases: [String]

    /// Public semantic surface for lightweight matching.
    public var semantic: SemanticSurface

    /// Reachability and consent posture.
    public var reachability: ReachabilityPolicy

    /// Preferred way this node likes first contact to feel.
    public var approach: ApproachPreferences

    /// Current coarse availability posture.
    public var availability: Availability

    public var createdAt: Date
    public var updatedAt: Date

    /// Optional HTTPS URL pointing to this node's primary public profile image.
    /// Binary image data is never stored here — only a public URL reference.
    /// nil means no image has been published.
    public var primaryImageURL: String?

    /// Small future-safe metadata only.
    public var metadata: [String: String]

    /// Public cosmetic supporter frame (presentation only; never ranking/retrieval).
    public var publicSupporterPresentation: ExchangeSupporterPresentation?

    public init(
        id: ID,
        nodeID: String,
        counterpartyID: ExchangeCounterparty.ID? = nil,
        displayName: String? = nil,
        headline: String? = nil,
        summary: String? = nil,
        visibility: Visibility = .discoverable,
        interests: [String] = [],
        offers: [String] = [],
        openTo: [String] = [],
        excludedTopics: [String] = [],
        activityTags: [String] = [],
        regionTags: [String] = [],
        canonicalRegionIDs: [String] = [],
        parentRegionIDs: [String] = [],
        regionAliases: [String] = [],
        semantic: SemanticSurface = .init(),
        reachability: ReachabilityPolicy = .init(),
        approach: ApproachPreferences = .init(),
        availability: Availability = .open,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        primaryImageURL: String? = nil,
        metadata: [String: String] = [:],
        publicSupporterPresentation: ExchangeSupporterPresentation? = nil
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.counterpartyID = counterpartyID?.exchangeNilIfBlank
        self.displayName = displayName?.exchangeNilIfBlank
        self.headline = headline?.exchangeNilIfBlank
        self.summary = summary?.exchangeNilIfBlank
        self.visibility = visibility
        self.interests = Self.normalizedTerms(interests)
        self.offers = Self.normalizedTerms(offers)
        self.openTo = Self.normalizedTerms(openTo)
        self.excludedTopics = Self.normalizedTerms(excludedTopics)
        self.activityTags = Self.normalizedTerms(activityTags)
        self.regionTags = Self.normalizedTerms(regionTags)
        self.canonicalRegionIDs = Self.normalizedRegionTokens(canonicalRegionIDs)
        self.parentRegionIDs = Self.normalizedRegionTokens(parentRegionIDs)
        self.regionAliases = Self.normalizedRegionTokens(regionAliases)
        self.semantic = semantic.normalized()
        self.reachability = reachability.normalized()
        self.approach = approach.normalized()
        self.availability = availability
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.primaryImageURL = primaryImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).exchangeNilIfBlank
        self.metadata = metadata
        self.publicSupporterPresentation = publicSupporterPresentation
    }
}

public extension ExchangePublicNodeProfile {
    enum Visibility: String, Codable, Sendable, CaseIterable, Hashable {
        /// Can appear in discovery and be considered for routing.
        case discoverable

        /// Hidden from broad discovery, but still usable via direct/trusted path.
        case limited

        /// Not discoverable and not routable except for already-established flows.
        case hidden
    }

    enum Availability: String, Codable, Sendable, CaseIterable, Hashable {
        case open
        case limited
        case paused
        case unavailable
    }

    struct SemanticSurface: Codable, Sendable, Hashable {
        public var domains: [String]
        public var intentKinds: [String]
        public var audienceKinds: [AudienceKind]
        public var fulfillmentModes: [FulfillmentMode]
        public var notes: String?

        public init(
            domains: [String] = [],
            intentKinds: [String] = [],
            audienceKinds: [AudienceKind] = [],
            fulfillmentModes: [FulfillmentMode] = [],
            notes: String? = nil
        ) {
            self.domains = Self.normalizedTerms(domains)
            self.intentKinds = Self.normalizedTerms(intentKinds)
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
                intentKinds +
                audienceKinds.map(\.rawValue) +
                fulfillmentModes.map(\.rawValue)
            )
        }

        public func normalized() -> SemanticSurface {
            SemanticSurface(
                domains: domains,
                intentKinds: intentKinds,
                audienceKinds: audienceKinds,
                fulfillmentModes: fulfillmentModes,
                notes: notes
            )
        }

        private static func normalizedTerms(_ values: [String]) -> [String] {
            ExchangePublicNodeProfile.normalizedTerms(values)
        }
    }

    struct ReachabilityPolicy: Codable, Sendable, Hashable {
        public enum AccessMode: String, Codable, Sendable, CaseIterable, Hashable {
            /// Direct first contact is allowed when other filters pass.
            case direct

            /// Direct may be allowed, but introduction/trusted paths are preferred.
            case introPreferred

            /// New contact should arrive through a trusted introduction/path.
            case introRequired

            /// No new inbound contact allowed.
            case closed
        }

        public enum DisclosureCeiling: String, Codable, Sendable, CaseIterable, Hashable {
            case minimal
            case balanced
            case open
        }

        public enum IntentCategoryPolicy: String, Codable, Sendable, CaseIterable, Hashable {
            /// Treat category/openTo/offer terms as soft hints. Best default for early federation.
            case permissive

            /// Legacy broad mode. Kept for backwards compatibility.
            case broad

            /// Require semantic/category fit before allowing routing.
            case matchedCategoriesOnly

            /// Require the request to match explicitly listed categories only.
            case listedCategoriesOnly
        }

        public var accessMode: AccessMode
        
        /// Hard operational override for inbound coordination.
        ///
        /// This does not define the preferred contact posture.
        /// It only determines whether any new inbound coordination should be
        /// accepted right now, regardless of access mode.
        public var acceptingInbound: Bool

        /// Optional coarse allowed modes, e.g. transactional / cooperative / relational.
        public var allowedModes: [String]

        /// Optional allowed intent kinds, usually aligned to ExchangeIntent.Kind raw values.
        public var allowedIntentKinds: [String]

        /// Optional allowed audience kinds.
        public var allowedAudienceKinds: [SemanticSurface.AudienceKind]

        /// Sender must meet at least this trust floor, if specified.
        public var minimumTrustLevel: ExchangeCounterparty.TrustSnapshot.Level?

        /// Whether a sender must have a strong semantic/category fit.
        public var requiresCategoryMatch: Bool

        /// Whether a sender must have mutual/trust-adjacent relevance.
        public var requiresMutualFit: Bool

        /// Whether discovery should treat openTo/offers as strict filter or broad hint.
        public var intentCategoryPolicy: IntentCategoryPolicy

        /// Maximum allowed disclosure for first-hop/public routing.
        public var disclosureCeiling: DisclosureCeiling

        /// Whether this node is routable only if a relay/route exists.
        public var routeableOnly: Bool

        public init(
            accessMode: AccessMode = .direct,
            acceptingInbound: Bool = true,
            allowedModes: [String] = [],
            allowedIntentKinds: [String] = [],
            allowedAudienceKinds: [SemanticSurface.AudienceKind] = [],
            minimumTrustLevel: ExchangeCounterparty.TrustSnapshot.Level? = nil,
            requiresCategoryMatch: Bool = false,
            requiresMutualFit: Bool = false,
            intentCategoryPolicy: IntentCategoryPolicy = .permissive,
            disclosureCeiling: DisclosureCeiling = .balanced,
            routeableOnly: Bool = false
        ) {
            self.accessMode = accessMode
            self.acceptingInbound = acceptingInbound
            self.allowedModes = Self.normalizedTerms(allowedModes)
            self.allowedIntentKinds = Self.normalizedTerms(allowedIntentKinds)
            self.allowedAudienceKinds = Array(Set(allowedAudienceKinds)).sorted { $0.rawValue < $1.rawValue }
            self.minimumTrustLevel = minimumTrustLevel
            self.requiresCategoryMatch = requiresCategoryMatch
            self.requiresMutualFit = requiresMutualFit
            self.intentCategoryPolicy = intentCategoryPolicy
            self.disclosureCeiling = disclosureCeiling
            self.routeableOnly = routeableOnly
        }

        public func normalized() -> ReachabilityPolicy {
            ReachabilityPolicy(
                accessMode: accessMode,
                acceptingInbound: acceptingInbound,
                allowedModes: allowedModes,
                allowedIntentKinds: allowedIntentKinds,
                allowedAudienceKinds: allowedAudienceKinds,
                minimumTrustLevel: minimumTrustLevel,
                requiresCategoryMatch: requiresCategoryMatch,
                requiresMutualFit: requiresMutualFit,
                intentCategoryPolicy: intentCategoryPolicy,
                disclosureCeiling: disclosureCeiling,
                routeableOnly: routeableOnly
            )
        }

        private static func normalizedTerms(_ values: [String]) -> [String] {
            ExchangePublicNodeProfile.normalizedTerms(values)
        }
    }

    struct ApproachPreferences: Codable, Sendable, Hashable {
        public enum Style: String, Codable, Sendable, CaseIterable, Hashable {
            case direct
            case warm
            case concise
            case formal
            case lowPressure
        }

        public enum FirstContactKind: String, Codable, Sendable, CaseIterable, Hashable {
            case introduction
            case inquiry
            case quoteRequest
            case followUp
            case other
        }

        public var preferredStyle: Style?
        public var preferredFirstContactKinds: [FirstContactKind]
        public var note: String?

        public init(
            preferredStyle: Style? = nil,
            preferredFirstContactKinds: [FirstContactKind] = [],
            note: String? = nil
        ) {
            self.preferredStyle = preferredStyle
            self.preferredFirstContactKinds = Array(Set(preferredFirstContactKinds)).sorted { $0.rawValue < $1.rawValue }
            self.note = note?.exchangeNilIfBlank
        }

        public func normalized() -> ApproachPreferences {
            ApproachPreferences(
                preferredStyle: preferredStyle,
                preferredFirstContactKinds: preferredFirstContactKinds,
                note: note
            )
        }
    }
}

public extension ExchangePublicNodeProfile.ReachabilityPolicy {
    /// Reachability-only slice: inbound accepted and access mode is not closed.
    var isRoutableInPrinciple: Bool {
        acceptingInbound && accessMode != .closed
    }

    /// Direct or intro-preferred access when routable under this policy.
    var allowsDirectContactInPrinciple: Bool {
        isRoutableInPrinciple &&
        (accessMode == .direct || accessMode == .introPreferred)
    }

    /// Introduction-mediated contact is required.
    var requiresIntroductionInPrinciple: Bool {
        accessMode == .introRequired
    }
}

public extension ExchangePublicNodeProfile {
    var isDiscoverable: Bool {
        visibility == .discoverable && availability != .unavailable
    }

    var isRoutableInPrinciple: Bool {
        reachability.isRoutableInPrinciple && availability != .unavailable
    }

    var allowsDirectContactInPrinciple: Bool {
        isRoutableInPrinciple &&
        (reachability.accessMode == .direct || reachability.accessMode == .introPreferred)
    }

    var requiresIntroductionInPrinciple: Bool {
        reachability.requiresIntroductionInPrinciple
    }

    var searchableText: String {
        [
            displayName,
            headline,
            summary,
            interests.joined(separator: " "),
            offers.joined(separator: " "),
            openTo.joined(separator: " "),
            excludedTopics.joined(separator: " "),
            activityTags.joined(separator: " "),
            regionTags.joined(separator: " "),
            semantic.searchableTerms.joined(separator: " "),
            semantic.notes,
            approach.note
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    var coordinationTokens: [String] {
        Self.normalizedTerms(
            interests +
            offers +
            openTo +
            excludedTopics +
            activityTags +
            regionTags +
            semantic.searchableTerms +
            reachability.allowedModes +
            reachability.allowedIntentKinds
        )
    }

    var summaryLine: String {
        if let headline, !headline.isEmpty {
            return headline
        }

        let offer = offers.first
        let openness = openTo.first

        switch (offer, openness) {
        case let (offer?, openness?):
            return "Offers \(offer) · Open to \(openness)"
        case let (offer?, nil):
            return "Offers \(offer)"
        case let (nil, openness?):
            return "Open to \(openness)"
        case (nil, nil):
            switch reachability.accessMode {
            case .direct: return "Direct contact allowed"
            case .introPreferred: return "Introduction preferred"
            case .introRequired: return "Introduction required"
            case .closed: return "Closed to new contact"
            }
        }
    }

    func updatingReachability(
        _ reachability: ReachabilityPolicy,
        at date: Date = Date()
    ) -> ExchangePublicNodeProfile {
        var copy = self
        copy.reachability = reachability.normalized()
        copy.updatedAt = date
        return copy
    }

    func updatingAvailability(
        _ availability: Availability,
        at date: Date = Date()
    ) -> ExchangePublicNodeProfile {
        var copy = self
        copy.availability = availability
        copy.updatedAt = date
        return copy
    }

    func updatingSemantic(
        _ semantic: SemanticSurface,
        at date: Date = Date()
    ) -> ExchangePublicNodeProfile {
        var copy = self
        copy.semantic = semantic.normalized()
        copy.updatedAt = date
        return copy
    }
}

private extension ExchangePublicNodeProfile {
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

    /// Region IDs and aliases: trim, lowercase, dedupe; do not apply semantic stop-word filtering.
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
