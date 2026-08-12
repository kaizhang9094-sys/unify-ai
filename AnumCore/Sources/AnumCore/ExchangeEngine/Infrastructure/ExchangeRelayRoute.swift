import Foundation

/// Concrete transport route selected for a federation action.
///
/// This is intentionally separate from:
/// - counterparty profile
/// - contact routes
/// - trust edges
///
/// It answers:
/// "What exact route are we attempting to use right now?"
public struct ExchangeRelayRoute: Codable, Sendable, Hashable, Identifiable {
    public var id: String { routeKey }

    public var routeKey: String
    public var kind: Kind
    public var destination: String

    public var relayServer: String?
    public var protocolVersion: String

    /// Route preference, not scheduler urgency.
    public var priority: Priority

    public var expiresAt: Date?
    public var metadata: [String: String]

    public init(
        routeKey: String,
        kind: Kind,
        destination: String,
        relayServer: String? = nil,
        protocolVersion: String = ExchangeProtocolVersion.current,
        priority: Priority = .normal,
        expiresAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        let cleanedRouteKey = routeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedProtocolVersion = protocolVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        self.routeKey = cleanedRouteKey.isEmpty ? "\(kind.rawValue):\(cleanedDestination)" : cleanedRouteKey
        self.kind = kind
        self.destination = cleanedDestination
        self.relayServer = relayServer?.exchangeNilIfBlank
        self.protocolVersion = cleanedProtocolVersion.isEmpty ? ExchangeProtocolVersion.current : cleanedProtocolVersion
        self.priority = priority
        self.expiresAt = expiresAt
        self.metadata = metadata
    }
}

public extension ExchangeRelayRoute {
    enum Kind: String, Codable, Sendable, CaseIterable, Hashable {
        case node
        case relayMailbox
        case relayAddress
        case emailBridge
        case localLoopback
    }

    enum Priority: String, Codable, Sendable, CaseIterable, Hashable {
        case fallback
        case normal
        case preferred
    }
}

public extension ExchangeRelayRoute {
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    var canBeUsedNow: Bool {
        !routeKey.isEmpty &&
        !destination.isEmpty &&
        !protocolVersion.isEmpty &&
        !isExpired
    }

    var summaryLine: String {
        switch kind {
        case .node:
            return "Node route: \(destination)"
        case .relayMailbox:
            if let relayServer {
                return "Relay mailbox: \(destination) via \(relayServer)"
            }
            return "Relay mailbox: \(destination)"
        case .relayAddress:
            return "Relay address: \(destination)"
        case .emailBridge:
            return "Email bridge: \(destination)"
        case .localLoopback:
            return "Local loopback"
        }
    }

    static func localLoopback(
        destination: String = "loopback",
        protocolVersion: String = ExchangeProtocolVersion.current
    ) -> ExchangeRelayRoute {
        ExchangeRelayRoute(
            routeKey: "loopback:\(destination)",
            kind: .localLoopback,
            destination: destination,
            protocolVersion: protocolVersion,
            priority: .preferred
        )
    }

    static func node(
        _ nodeID: String,
        protocolVersion: String = ExchangeProtocolVersion.current,
        relayServer: String? = nil,
        priority: Priority = .preferred
    ) -> ExchangeRelayRoute {
        ExchangeRelayRoute(
            routeKey: "node:\(nodeID)",
            kind: .node,
            destination: nodeID,
            relayServer: relayServer,
            protocolVersion: protocolVersion,
            priority: priority
        )
    }

    static func relayMailbox(
        _ mailbox: String,
        relayServer: String? = nil,
        protocolVersion: String = ExchangeProtocolVersion.current,
        priority: Priority = .preferred
    ) -> ExchangeRelayRoute {
        ExchangeRelayRoute(
            routeKey: "relay-mailbox:\(mailbox)",
            kind: .relayMailbox,
            destination: mailbox,
            relayServer: relayServer,
            protocolVersion: protocolVersion,
            priority: priority
        )
    }

    static func relayAddress(
        _ address: String,
        relayServer: String? = nil,
        protocolVersion: String = ExchangeProtocolVersion.current,
        priority: Priority = .normal
    ) -> ExchangeRelayRoute {
        ExchangeRelayRoute(
            routeKey: "relay-address:\(address)",
            kind: .relayAddress,
            destination: address,
            relayServer: relayServer,
            protocolVersion: protocolVersion,
            priority: priority
        )
    }

    static func emailBridge(
        _ email: String,
        protocolVersion: String = ExchangeProtocolVersion.current,
        priority: Priority = .normal
    ) -> ExchangeRelayRoute {
        ExchangeRelayRoute(
            routeKey: "email:\(email)",
            kind: .emailBridge,
            destination: email,
            protocolVersion: protocolVersion,
            priority: priority
        )
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
