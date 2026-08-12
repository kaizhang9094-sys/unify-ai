import Foundation

/// Where an Inbound (Chats) row should open when the user taps it.
public enum ExchangeInboundConversationOpenRoute: String, Sendable, Equatable {
    case exchangeThread
    case directMessage
}

/// Explicit caller intent for inbound conversation open routing.
public enum ExchangeInboundConversationOpenIntent: String, Sendable, Equatable {
    case providerInquiry
    case directMessage
    case auto
}

/// UI surface that initiated an inbound conversation open.
public enum ExchangeInboundOpenSource: String, Sendable, Equatable {
    case chatTab
    case inboundInquiry
    case auto
}

public struct ExchangeInboundOpenRouteDecision: Sendable, Equatable {
    public var route: ExchangeInboundConversationOpenRoute
    public var reason: String

    public init(route: ExchangeInboundConversationOpenRoute, reason: String) {
        self.route = route
        self.reason = reason
    }
}

/// Classifies linked exchange threads for Inbound tap routing (provider desk vs DM).
public enum ExchangeInboundOpenRouting: Sendable {

    public static func routeDecision(
        threadMetadata: [String: String]
    ) -> ExchangeInboundOpenRouteDecision {
        routeDecision(threadMetadata: threadMetadata, intent: .auto)
    }

    public static func routeDecision(
        threadMetadata: [String: String],
        intent: ExchangeInboundConversationOpenIntent
    ) -> ExchangeInboundOpenRouteDecision {
        let isInbound = isTruthy(threadMetadata["inbound_thread"])
        let isDM = isTruthy(threadMetadata["direct_message_thread"])
        let surface = normalizedSurface(threadMetadata["conversation_surface"])

        switch intent {
        case .directMessage:
            if isDM {
                return ExchangeInboundOpenRouteDecision(
                    route: .directMessage,
                    reason: "direct_message_thread"
                )
            }
            return ExchangeInboundOpenRouteDecision(
                route: .directMessage,
                reason: "direct_message_intent_ignore_exchange_metadata"
            )

        case .providerInquiry:
            if isDM {
                return ExchangeInboundOpenRouteDecision(
                    route: .directMessage,
                    reason: "direct_message_thread"
                )
            }
            if isInbound {
                return ExchangeInboundOpenRouteDecision(
                    route: .exchangeThread,
                    reason: "inbound_provider_desk"
                )
            }
            if surface == "exchange_thread" {
                return ExchangeInboundOpenRouteDecision(
                    route: .exchangeThread,
                    reason: "conversation_surface_exchange_thread"
                )
            }
            return ExchangeInboundOpenRouteDecision(
                route: .directMessage,
                reason: "provider_inquiry_fallback_non_exchange"
            )

        case .auto:
            if isDM {
                return ExchangeInboundOpenRouteDecision(
                    route: .directMessage,
                    reason: "direct_message_thread"
                )
            }
            if isInbound {
                return ExchangeInboundOpenRouteDecision(
                    route: .exchangeThread,
                    reason: "inbound_provider_desk"
                )
            }
            if surface == "exchange_thread" {
                return ExchangeInboundOpenRouteDecision(
                    route: .exchangeThread,
                    reason: "conversation_surface_exchange_thread"
                )
            }
            return ExchangeInboundOpenRouteDecision(
                route: .directMessage,
                reason: "fallback_non_explicit_exchange_surface"
            )
        }
    }

    /// Provider inbound desks with a federated inbound envelope stay visible in Threads History
    /// even when coordination state has moved to `.resolved`.
    public static func shouldKeepProviderDeskInThreadsHistory(
        isInboundProviderDesk: Bool,
        hasFederatedInboundEnvelope: Bool,
        state: ExchangeState,
        hasFailure: Bool
    ) -> Bool {
        guard isInboundProviderDesk, hasFederatedInboundEnvelope else { return false }
        guard case .resolved = state, !hasFailure else { return false }
        return true
    }

    private static func isTruthy(_ raw: String?) -> Bool {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    private static func normalizedSurface(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
