import Foundation

/// Aggregated trust-facing view of a node.
///
/// This is not the raw federation protocol object.
/// It is a derived profile useful for:
/// - discovery ranking inputs
/// - trusted contact UI
/// - explainable trust badges
/// - future friend-of-friend or network trust summaries
///
/// Keep this as a derived read model, not the trust engine itself.
public struct ExchangeTrustedNodeProfile: Codable, Sendable, Hashable, Identifiable {
    public typealias ID = String

    public var id: ID
    public var nodeID: String
    public var counterpartyID: ExchangeCounterparty.ID?

    public var localTrust: LocalTrust?
    public var networkTrust: NetworkTrust
    public var scopedTrust: [ScopedTrust]

    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(
        id: ID,
        nodeID: String,
        counterpartyID: ExchangeCounterparty.ID? = nil,
        localTrust: LocalTrust? = nil,
        networkTrust: NetworkTrust = .init(),
        scopedTrust: [ScopedTrust] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.counterpartyID = counterpartyID
        self.localTrust = localTrust
        self.networkTrust = networkTrust
        self.scopedTrust = scopedTrust.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.scope.rawValue < rhs.scope.rawValue
        }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

public extension ExchangeTrustedNodeProfile {
    struct LocalTrust: Codable, Sendable, Hashable {
        public var relationshipType: ExchangeTrustEdge.RelationshipType
        public var trustLevel: ExchangeTrustEdge.TrustLevel
        public var scopes: Set<ExchangeTrustEdge.TrustScope>
        public var propagation: ExchangeTrustEdge.Propagation
        public var isMutual: Bool
        public var lastConfirmedAt: Date?
        public var note: String?

        public init(
            relationshipType: ExchangeTrustEdge.RelationshipType,
            trustLevel: ExchangeTrustEdge.TrustLevel,
            scopes: Set<ExchangeTrustEdge.TrustScope>,
            propagation: ExchangeTrustEdge.Propagation,
            isMutual: Bool = false,
            lastConfirmedAt: Date? = nil,
            note: String? = nil
        ) {
            self.relationshipType = relationshipType
            self.trustLevel = trustLevel
            self.scopes = scopes
            self.propagation = propagation
            self.isMutual = isMutual
            self.lastConfirmedAt = lastConfirmedAt
            self.note = note?.exchangeNilIfBlank
        }
    }

    struct NetworkTrust: Codable, Sendable, Hashable {
        public var trustedByCount: Int
        public var trustedByHighTrustCount: Int
        public var trustedByYourTrustedCount: Int
        public var mutualTrustCount: Int
        public var lastObservedAt: Date?

        public init(
            trustedByCount: Int = 0,
            trustedByHighTrustCount: Int = 0,
            trustedByYourTrustedCount: Int = 0,
            mutualTrustCount: Int = 0,
            lastObservedAt: Date? = nil
        ) {
            self.trustedByCount = max(0, trustedByCount)
            self.trustedByHighTrustCount = max(0, trustedByHighTrustCount)
            self.trustedByYourTrustedCount = max(0, trustedByYourTrustedCount)
            self.mutualTrustCount = max(0, mutualTrustCount)
            self.lastObservedAt = lastObservedAt
        }
    }

    struct ScopedTrust: Codable, Sendable, Hashable {
        public var scope: ExchangeTrustEdge.TrustScope
        public var count: Int
        public var weightedCount: Double

        public init(
            scope: ExchangeTrustEdge.TrustScope,
            count: Int,
            weightedCount: Double
        ) {
            self.scope = scope
            self.count = max(0, count)
            self.weightedCount = max(0, weightedCount)
        }
    }
}

public extension ExchangeTrustedNodeProfile {
    var isLocallyTrusted: Bool {
        localTrust != nil
    }

    var isMutual: Bool {
        localTrust?.isMutual == true || networkTrust.mutualTrustCount > 0
    }

    var trustedBySummary: String {
        let count = networkTrust.trustedByCount
        switch count {
        case 0:
            return "No network trust signal yet."
        case 1:
            return "Trusted by 1 node."
        default:
            return "Trusted by \(count) nodes."
        }
    }

    var trustedByYourTrustedSummary: String? {
        let count = networkTrust.trustedByYourTrustedCount
        guard count > 0 else { return nil }

        if count == 1 {
            return "Trusted by 1 of your trusted nodes."
        }
        return "Trusted by \(count) of your trusted nodes."
    }

    /// Lightweight, explainable trust signal summary for display/debugging.
    ///
    /// This is not the final discovery ranking score.
    var trustSignalSummary: String {
        var parts: [String] = []

        if let localTrust {
            parts.append("Local trust: \(localTrust.trustLevel.rawValue)")
            if localTrust.isMutual {
                parts.append("mutual")
            }
        } else {
            parts.append("No direct local trust")
        }

        if networkTrust.trustedByYourTrustedCount > 0 {
            parts.append("trusted by \(networkTrust.trustedByYourTrustedCount) of your trusted nodes")
        } else if networkTrust.trustedByCount > 0 {
            parts.append("trusted by \(networkTrust.trustedByCount) network nodes")
        }

        return parts.joined(separator: " · ")
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
