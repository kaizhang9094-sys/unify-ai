import Foundation

/// A potential or confirmed external participant in an exchange thread.
///
/// A counterparty may be:
/// - a person
/// - a business
/// - a service provider
/// - a group
/// - another secretary node acting on behalf of a human
///
/// This type is intentionally identity-centric and lightweight.
/// It should not be overloaded with large profiles, volatile UI state,
/// or full trust-graph detail.
///
/// Important:
/// A counterparty is not the same thing as the node's full public consent surface.
/// Public openness / reachability / offer posture should live in
/// `ExchangePublicNodeProfile`.
public struct ExchangeCounterparty: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = String

    public var id: ID
    public var createdAt: Date
    public var updatedAt: Date

    public var kind: Kind
    public var displayName: String
    public var handle: String?
    public var bio: String?

    /// Where this counterparty record was discovered or introduced from.
    public var source: Source

    /// Optional federation / node identity metadata.
    public var identity: Identity?

    /// Optional linked public node posture / reachability surface.
    ///
    /// This is the consent-shaped public coordination layer:
    /// - what this node is open to
    /// - what it offers
    /// - how it prefers to be approached
    /// - whether direct contact is allowed
    ///
    /// Keep this compact; do not confuse it with private memory or trust graph state.
    public var publicProfile: ExchangePublicNodeProfile?

    /// Coarse location or market context.
    public var location: Location?

    /// Discovery-visible tags such as:
    /// - roofing
    /// - industrial
    /// - hamilton
    /// - robotics
    public var tags: [String]

    /// Structured capability labels or service offerings.
    ///
    /// These remain useful as compact entity-level capabilities, but should not
    /// replace the node's public openness / reachability posture.
    public var capabilities: [Capability]

    /// Durable semantic profile used by discovery and fit.
    ///
    /// This is the structured entity layer that should help discovery remain
    /// legible, but it is not the same thing as consent or reachability.
    public var semantic: SemanticProfile

    /// Coarse, derived trust summary suitable for discovery and ranking.
    /// This is not the trust graph itself.
    public var trust: TrustSnapshot

    /// Small contact surfaces or routing handles.
    ///
    /// Important:
    /// A route existing here does NOT automatically imply that direct contact is
    /// allowed. Use `publicProfile?.reachability` when available.
    public var contactRoutes: [ContactRoute]

    /// Whether this record is currently eligible for discovery/use.
    ///
    /// This is a coarse local/entity status only.
    /// It should not override a richer public node posture if one is present.
    public var status: Status

    /// Small future-safe metadata only.
    public var metadata: [String: String]

    public init(
        id: ID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        kind: Kind,
        displayName: String,
        handle: String? = nil,
        bio: String? = nil,
        source: Source,
        identity: Identity? = nil,
        publicProfile: ExchangePublicNodeProfile? = nil,
        location: Location? = nil,
        tags: [String] = [],
        capabilities: [Capability] = [],
        semantic: SemanticProfile = .empty,
        trust: TrustSnapshot = .unverified,
        contactRoutes: [ContactRoute] = [],
        status: Status = .active,
        metadata: [String: String] = [:]
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kind = kind
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.handle = handle?.exchangeNilIfBlank
        self.bio = bio?.exchangeNilIfBlank
        self.source = source
        self.identity = identity
        self.publicProfile = publicProfile
        self.location = location
        self.tags = Self.normalizedTags(tags)
        self.capabilities = capabilities
        self.semantic = semantic.normalized()
        self.trust = trust
        self.contactRoutes = contactRoutes
        self.status = status
        self.metadata = metadata
    }
}

public extension ExchangeCounterparty {
    enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
        case person
        case provider
        case business
        case organization
        case group
        case secretaryNode
        case unknown
    }

    enum Status: String, Codable, Sendable, CaseIterable, Hashable {
        case active
        case paused
        case unavailable
        case blocked
    }

    enum Source: Codable, Sendable, Hashable {
        case localDirectory
        case relayNetwork
        case trustedIntroduction
        case imported(label: String)
        case manualEntry

        public var summaryLine: String {
            switch self {
            case .localDirectory:
                return "Local directory"
            case .relayNetwork:
                return "Relay network"
            case .trustedIntroduction:
                return "Trusted introduction"
            case .imported(let label):
                let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "Imported" : "Imported: \(text)"
            case .manualEntry:
                return "Manual entry"
            }
        }
    }

    struct Identity: Codable, Sendable, Hashable {
        /// Stable node identifier when the counterparty is represented on the
        /// federation layer.
        public var nodeID: String?

        /// Public key identifier used for verification or signed exchange.
        public var publicKeyID: String?

        public var verification: Verification

        public init(
            nodeID: String? = nil,
            publicKeyID: String? = nil,
            verification: Verification = .unverified
        ) {
            self.nodeID = nodeID?.exchangeNilIfBlank
            self.publicKeyID = publicKeyID?.exchangeNilIfBlank
            self.verification = verification
        }

        public enum Verification: String, Codable, Sendable, CaseIterable, Hashable {
            case unverified
            case selfAsserted
            case cryptographicallyVerified
        }
    }

    struct Location: Codable, Sendable, Hashable {
        public var city: String?
        public var region: String?
        public var country: String?
        public var remoteFriendly: Bool

        public init(
            city: String? = nil,
            region: String? = nil,
            country: String? = nil,
            remoteFriendly: Bool = false
        ) {
            self.city = city?.exchangeNilIfBlank
            self.region = region?.exchangeNilIfBlank
            self.country = country?.exchangeNilIfBlank
            self.remoteFriendly = remoteFriendly
        }

        public var summaryLine: String {
            let parts = [city, region, country].compactMap { $0 }
            if parts.isEmpty {
                return remoteFriendly ? "Remote-friendly" : "Location unknown"
            }
            let base = parts.joined(separator: ", ")
            return remoteFriendly ? "\(base) · Remote-friendly" : base
        }
    }

    struct Capability: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var label: String
        public var category: String?
        public var notes: String?

        public init(
            id: UUID = UUID(),
            label: String,
            category: String? = nil,
            notes: String? = nil
        ) {
            self.id = id
            self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            self.category = category?.exchangeNilIfBlank
            self.notes = notes?.exchangeNilIfBlank
        }
    }

    /// Structured semantic layer for discovery and fit.
    ///
    /// Keep this compact. It should make matching more legible, not become a
    /// giant parallel ontology.
    ///
    /// Important:
    /// This is entity semantics, not public openness policy.
    struct SemanticProfile: Codable, Sendable, Hashable {
        public var roles: [String]
        public var activities: [String]
        public var serviceCategories: [String]
        public var productCategories: [String]
        public var marketTags: [String]
        public var placeTags: [String]
        public var timeTags: [String]
        public var fulfillmentModes: [FulfillmentMode]
        public var audienceKinds: [AudienceKind]
        public var notes: String?

        public init(
            roles: [String] = [],
            activities: [String] = [],
            serviceCategories: [String] = [],
            productCategories: [String] = [],
            marketTags: [String] = [],
            placeTags: [String] = [],
            timeTags: [String] = [],
            fulfillmentModes: [FulfillmentMode] = [],
            audienceKinds: [AudienceKind] = [],
            notes: String? = nil
        ) {
            self.roles = Self.normalizedTerms(roles)
            self.activities = Self.normalizedTerms(activities)
            self.serviceCategories = Self.normalizedTerms(serviceCategories)
            self.productCategories = Self.normalizedTerms(productCategories)
            self.marketTags = Self.normalizedTerms(marketTags)
            self.placeTags = Self.normalizedTerms(placeTags)
            self.timeTags = Self.normalizedTerms(timeTags)
            self.fulfillmentModes = Array(Set(fulfillmentModes)).sorted { $0.rawValue < $1.rawValue }
            self.audienceKinds = Array(Set(audienceKinds)).sorted { $0.rawValue < $1.rawValue }
            self.notes = notes?.exchangeNilIfBlank
        }

        public enum FulfillmentMode: String, Codable, Sendable, CaseIterable, Hashable {
            case localOnly
            case localPreferred
            case remoteFriendly
            case shippable
            case digitalDelivery
            case inPerson
        }

        public enum AudienceKind: String, Codable, Sendable, CaseIterable, Hashable {
            case person
            case provider
            case business
            case organization
            case group
            case secretaryNode
        }

        public static let empty = SemanticProfile()

        public var isMeaningful: Bool {
            !roles.isEmpty ||
            !activities.isEmpty ||
            !serviceCategories.isEmpty ||
            !productCategories.isEmpty ||
            !marketTags.isEmpty ||
            !placeTags.isEmpty ||
            !timeTags.isEmpty ||
            !fulfillmentModes.isEmpty ||
            !audienceKinds.isEmpty ||
            notes != nil
        }

        public var searchableTerms: [String] {
            Self.normalizedTerms(
                roles +
                activities +
                serviceCategories +
                productCategories +
                marketTags +
                placeTags +
                timeTags +
                fulfillmentModes.map(\.rawValue) +
                audienceKinds.map(\.rawValue)
            )
        }

        public func normalized() -> SemanticProfile {
            SemanticProfile(
                roles: roles,
                activities: activities,
                serviceCategories: serviceCategories,
                productCategories: productCategories,
                marketTags: marketTags,
                placeTags: placeTags,
                timeTags: timeTags,
                fulfillmentModes: fulfillmentModes,
                audienceKinds: audienceKinds,
                notes: notes
            )
        }

        private static func normalizedTerms(_ values: [String]) -> [String] {
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
                            $0.count <= 80
                        }
                )
            )
            .sorted()
        }
    }

    /// Coarse trust projection suitable for display and lightweight ranking.
    ///
    /// Detailed trust reasoning should live in the trust graph layer.
    struct TrustSnapshot: Codable, Sendable, Hashable {
        public var level: Level
        public var summary: String?
        public var completedThreads: Int
        public var successfulThreads: Int

        public init(
            level: Level,
            summary: String? = nil,
            completedThreads: Int = 0,
            successfulThreads: Int = 0
        ) {
            self.level = level
            self.summary = summary?.exchangeNilIfBlank
            self.completedThreads = max(0, completedThreads)
            self.successfulThreads = max(0, successfulThreads)
        }

        public enum Level: String, Codable, Sendable, CaseIterable, Hashable {
            case unverified
            case low
            case moderate
            case high
        }

        public static let unverified = TrustSnapshot(level: .unverified)

        public var successRate: Double? {
            guard completedThreads > 0 else { return nil }
            return Double(successfulThreads) / Double(completedThreads)
        }
    }

    struct ContactRoute: Codable, Sendable, Hashable, Identifiable {
        public var id: UUID
        public var kind: Kind
        public var value: String
        public var isPreferred: Bool

        public init(
            id: UUID = UUID(),
            kind: Kind,
            value: String,
            isPreferred: Bool = false
        ) {
            self.id = id
            self.kind = kind
            self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            self.isPreferred = isPreferred
        }

        public enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
            case exchangeNode
            case relayAddress
            case email
            case phone
            case username
            case other
        }
    }
}

public extension ExchangeCounterparty {
    /// Coarse entity-level discoverability.
    ///
    /// If a public profile is present, discovery should prefer using
    /// `publicProfile.isDiscoverable`.
    var isDiscoverable: Bool {
        if let publicProfile {
            return publicProfile.isDiscoverable
        }

        switch status {
        case .active:
            return true
        case .paused, .unavailable, .blocked:
            return false
        }
    }

    /// Whether this node can, in principle, be routed to.
    ///
    /// Important:
    /// This does not imply direct contact is allowed.
    var isRoutableInPrinciple: Bool {
        if let publicProfile {
            return publicProfile.isRoutableInPrinciple && hasAnyRoute
        }
        return hasAnyRoute && status == .active
    }

    /// Whether direct contact is allowed in principle by the public profile.
    ///
    /// If no public profile exists, this falls back conservatively to route
    /// existence plus active status.
    var allowsDirectContactInPrinciple: Bool {
        if let publicProfile {
            return publicProfile.allowsDirectContactInPrinciple && hasAnyRoute
        }
        return hasAnyRoute && status == .active
    }

    /// Whether a public posture indicates that a trusted introduction/path is
    /// required before first contact.
    var requiresIntroductionInPrinciple: Bool {
        publicProfile?.requiresIntroductionInPrinciple ?? false
    }

    var bestDisplayLine: String {
        if let handle, !handle.isEmpty {
            return "\(displayName) (\(handle))"
        }
        return displayName
    }

    var preferredRoute: ContactRoute? {
        if let preferred = contactRoutes.first(where: { $0.isPreferred }) {
            return preferred
        }
        return contactRoutes.first
    }

    var hasAnyRoute: Bool {
        identity?.nodeID != nil ||
        contactRoutes.contains(where: { route in
            switch route.kind {
            case .exchangeNode, .relayAddress, .email, .phone, .username, .other:
                return !route.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        })
    }

    var isFederated: Bool {
        identity?.nodeID != nil ||
        contactRoutes.contains(where: { $0.kind == .exchangeNode || $0.kind == .relayAddress })
    }

    /// Discovery/search text for this entity record.
    ///
    /// When a public profile exists, include its public searchable surface so
    /// search can reason over openness/offers without making counterparty itself
    /// the canonical consent object.
    var searchableText: String {
        [
            displayName,
            handle,
            bio,
            location?.summaryLine,
            tags.joined(separator: " "),
            capabilities.map(\.label).joined(separator: " "),
            capabilities.compactMap(\.category).joined(separator: " "),
            capabilities.compactMap(\.notes).joined(separator: " "),
            semantic.searchableTerms.joined(separator: " "),
            semantic.notes,
            publicProfile?.searchableText
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    var semanticTokens: [String] {
        Self.normalizedTags(
            semantic.searchableTerms +
            tags +
            capabilities.map(\.label) +
            capabilities.compactMap(\.category) +
            (publicProfile?.coordinationTokens ?? [])
        )
    }

    func supportsAudienceKind(_ value: SemanticProfile.AudienceKind) -> Bool {
        semantic.audienceKinds.contains(value)
    }

    func supportsFulfillmentMode(_ value: SemanticProfile.FulfillmentMode) -> Bool {
        semantic.fulfillmentModes.contains(value)
    }

    func updatingStatus(
        _ status: Status,
        at date: Date = Date()
    ) -> ExchangeCounterparty {
        var copy = self
        copy.status = status
        copy.updatedAt = date
        return copy
    }

    func updatingTrust(
        _ trust: TrustSnapshot,
        at date: Date = Date()
    ) -> ExchangeCounterparty {
        var copy = self
        copy.trust = trust
        copy.updatedAt = date
        return copy
    }

    func updatingSemantic(
        _ semantic: SemanticProfile,
        at date: Date = Date()
    ) -> ExchangeCounterparty {
        var copy = self
        copy.semantic = semantic.normalized()
        copy.updatedAt = date
        return copy
    }

    func updatingPublicProfile(
        _ publicProfile: ExchangePublicNodeProfile?,
        at date: Date = Date()
    ) -> ExchangeCounterparty {
        var copy = self
        copy.publicProfile = publicProfile
        copy.updatedAt = date
        return copy
    }
}

private extension ExchangeCounterparty {
    static func normalizedTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags
                    .map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                    }
                    .filter {
                        !$0.isEmpty &&
                        !$0.isSemanticStopWord
                    }
            )
        )
        .sorted()
    }
}

public extension ExchangeCounterparty {
    /// Human-facing label from the linked public node surface when present.
    ///
    /// Discovery may seed `displayName` with coarse node identifiers; opportunity UI should
    /// prefer explicit public profile naming when it exists.
    var publicCoordinationHeadline: String? {
        if let name = publicProfile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let headline = publicProfile?.headline?.trimmingCharacters(in: .whitespacesAndNewlines),
           !headline.isEmpty {
            return headline
        }
        return nil
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
