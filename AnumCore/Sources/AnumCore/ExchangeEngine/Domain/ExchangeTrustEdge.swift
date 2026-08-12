import Foundation

/// Directional trust relationship from one node to another.
///
/// This is not a generic popularity signal.
/// It is a permissioned, scoped, revocable trust edge that can be used for:
/// - local trusted contacts
/// - discovery ranking
/// - disclosure defaults
/// - future federated trust aggregation
public struct ExchangeTrustEdge: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = UUID

    public var id: ID

    /// Federation/source node asserting trust.
    public var sourceNodeID: String

    /// Federation/target node being trusted.
    public var targetNodeID: String

    public var relationshipType: RelationshipType
    public var trustLevel: TrustLevel
    public var scopes: Set<TrustScope>

    /// Trust propagation policy, not UI visibility.
    public var propagation: Propagation

    public var sourceKind: SourceKind

    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastConfirmedAt: Date?
    public var revokedAt: Date?

    public var metadata: [String: String]

    public init(
        id: ID = UUID(),
        sourceNodeID: String,
        targetNodeID: String,
        relationshipType: RelationshipType,
        trustLevel: TrustLevel = .standard,
        scopes: Set<TrustScope> = [],
        propagation: Propagation = .privateOnly,
        sourceKind: SourceKind = .manual,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastConfirmedAt: Date? = nil,
        revokedAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID.exchangeTrimmed
        self.targetNodeID = targetNodeID.exchangeTrimmed
        self.relationshipType = relationshipType
        self.trustLevel = trustLevel
        self.scopes = scopes
        self.propagation = propagation
        self.sourceKind = sourceKind
        self.note = note?.exchangeNilIfBlank
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastConfirmedAt = lastConfirmedAt
        self.revokedAt = revokedAt
        self.metadata = metadata
    }
}

public extension ExchangeTrustEdge {
    enum RelationshipType: String, Codable, Sendable, CaseIterable, Hashable {
        case friend
        case family
        case colleague
        case client
        case provider
        case collaborator
        case knownContact
        case preferredNode
        case other
    }

    enum TrustLevel: String, Codable, Sendable, CaseIterable, Hashable {
        case low
        case standard
        case high
    }

    enum TrustScope: String, Codable, Sendable, CaseIterable, Hashable {
        case generalCommunication
        case planning
        case introductions
        case social
        case sourcing
        case negotiation
        case scheduling
        case logistics
        case sensitiveTopics
    }

    /// Defines how this edge may influence trust reasoning beyond the local node.
    enum Propagation: String, Codable, Sendable, CaseIterable, Hashable {
        /// Only visible and usable locally by this node.
        case privateOnly

        /// May influence trusted-path or friend-of-friend style reasoning indirectly.
        case trustedGraphOnly

        /// May contribute to aggregated network trust signals.
        case networkAggregatable
    }

    enum SourceKind: String, Codable, Sendable, CaseIterable, Hashable {
        case manual
        case importedContact
        case successfulExchange
        case repeatedSelection
        case mutualConnection
        case verifiedIdentity
        case systemObserved
    }
}

public extension ExchangeTrustEdge {
    var isActive: Bool {
        revokedAt == nil
    }

    var isMutualCandidate: Bool {
        relationshipType == .friend ||
        relationshipType == .family ||
        relationshipType == .collaborator
    }

    /// Whether this edge is eligible to influence discovery/ranking logic.
    ///
    /// Final trust computation still belongs to the trust engine.
    var canAffectDiscovery: Bool {
        guard isActive else { return false }

        switch propagation {
        case .privateOnly, .trustedGraphOnly, .networkAggregatable:
            return true
        }
    }

    var participatesInNetworkAggregation: Bool {
        isActive && propagation == .networkAggregatable
    }

    func confirming(
        at date: Date = Date()
    ) -> ExchangeTrustEdge {
        var copy = self
        copy.lastConfirmedAt = date
        copy.updatedAt = date

        if copy.revokedAt != nil {
            copy.revokedAt = nil
        }

        return copy
    }

    func updating(
        relationshipType: RelationshipType? = nil,
        trustLevel: TrustLevel? = nil,
        scopes: Set<TrustScope>? = nil,
        propagation: Propagation? = nil,
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeTrustEdge {
        var copy = self

        if let relationshipType {
            copy.relationshipType = relationshipType
        }
        if let trustLevel {
            copy.trustLevel = trustLevel
        }
        if let scopes {
            copy.scopes = scopes
        }
        if let propagation {
            copy.propagation = propagation
        }
        if let note {
            copy.note = note.exchangeNilIfBlank
        }

        copy.updatedAt = date
        return copy
    }

    func revoking(
        at date: Date = Date()
    ) -> ExchangeTrustEdge {
        var copy = self
        copy.revokedAt = date
        copy.updatedAt = date
        return copy
    }
}

private extension String {
    var exchangeTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var exchangeNilIfBlank: String? {
        let trimmed = exchangeTrimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}
