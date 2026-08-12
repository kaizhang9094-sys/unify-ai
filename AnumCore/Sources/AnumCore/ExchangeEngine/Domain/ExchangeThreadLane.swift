import Foundation

/// Durable coordination lane for an exchange thread.
///
/// Stored in `ExchangeThread.metadata["thread_lane"]` until a first-class schema field exists.
public enum ExchangeThreadLane: String, Codable, Sendable, Equatable, CaseIterable {
    case commercialInquiry
    case socialConnection
    case directMessage
    case contactSignal
    case unknown
}

public enum ExchangeThreadLaneResolver {
    public static let metadataKey = "thread_lane"
    public static let conversationSurfaceMetadataKey = "conversation_surface"

    public static let conversationSurfaceDirectMessage = "direct_message"
    public static let conversationSurfaceContact = "contact"
    public static let conversationSurfaceSocialConnection = "social_connection"
    public static let conversationSurfaceExchangeThread = "exchange_thread"

    // MARK: - Resolve

    public static func lane(for thread: ExchangeThread) -> ExchangeThreadLane {
        lane(for: thread.intent, metadata: thread.metadata)
    }

    public static func lane(
        for intent: ExchangeIntent,
        metadata: [String: String] = [:]
    ) -> ExchangeThreadLane {
        if isTruthy(metadata["direct_message_thread"]) {
            return .directMessage
        }
        if isTruthy(metadata["contact_request_thread"]) {
            return .contactSignal
        }

        if let parsed = parseStoredLane(metadata[metadataKey]) {
            return parsed
        }

        let surface = normalizedConversationSurface(metadata[conversationSurfaceMetadataKey])
        if surface == conversationSurfaceDirectMessage { return .directMessage }
        if surface == conversationSurfaceContact { return .contactSignal }
        if surface == conversationSurfaceSocialConnection { return .socialConnection }
        if surface == conversationSurfaceExchangeThread { return .commercialInquiry }

        return laneFromQueryIntentClass(intent.queryIntentClass)
    }

    public static func laneFromInboundEnvelopeMetadata(_ metadata: [String: String]) -> ExchangeThreadLane {
        if ExchangeContactSignalClassifier.matchesContactSignalMetadata(metadata) {
            return .contactSignal
        }
        if isTruthy(metadata["direct_message_thread"]) {
            return .directMessage
        }

        if let parsed = parseStoredLane(metadata[metadataKey]) {
            return parsed
        }

        switch normalizedConversationSurface(metadata[conversationSurfaceMetadataKey]) {
        case conversationSurfaceDirectMessage:
            return .directMessage
        case conversationSurfaceContact:
            return .contactSignal
        case conversationSurfaceSocialConnection:
            return .socialConnection
        case conversationSurfaceExchangeThread:
            return .commercialInquiry
        default:
            return .unknown
        }
    }

    // MARK: - Apply

    public static func applyLane(_ lane: ExchangeThreadLane, to metadata: inout [String: String]) {
        metadata[metadataKey] = lane.rawValue
        metadata[conversationSurfaceMetadataKey] = conversationSurface(for: lane)
    }

    public static func conversationSurface(for lane: ExchangeThreadLane) -> String {
        switch lane {
        case .directMessage:
            return conversationSurfaceDirectMessage
        case .contactSignal:
            return conversationSurfaceContact
        case .socialConnection:
            return conversationSurfaceSocialConnection
        case .commercialInquiry:
            return conversationSurfaceExchangeThread
        case .unknown:
            return conversationSurfaceExchangeThread
        }
    }

    // MARK: - Gating

    public static func skipsSecondHalfMutation(for lane: ExchangeThreadLane) -> Bool {
        switch lane {
        case .directMessage, .socialConnection, .contactSignal:
            return true
        case .commercialInquiry, .unknown:
            return false
        }
    }

    public static func skipsCommercialProviderSecondHalf(for lane: ExchangeThreadLane) -> Bool {
        switch lane {
        case .directMessage, .socialConnection, .contactSignal:
            return true
        case .commercialInquiry, .unknown:
            return false
        }
    }

    public static func displayLabel(for lane: ExchangeThreadLane) -> String? {
        switch lane {
        case .socialConnection:
            return "Profile connection"
        case .directMessage, .contactSignal, .commercialInquiry, .unknown:
            return nil
        }
    }

    public static func clearsCommercialOfferAnchor(for lane: ExchangeThreadLane) -> Bool {
        lane == .socialConnection
    }

    /// Mirrors exchange second-half role inference; canonical lane gates commercial provider flow.
    public static func inferSecondHalfRole(for thread: ExchangeThread) -> ExchangeSecondHalfRole {
        let lane = lane(for: thread)
        if skipsCommercialProviderSecondHalf(for: lane) {
            return .requester
        }
        if thread.lastInboundEnvelopeID != nil {
            return .provider
        }
        return .requester
    }

    public static func isSecondHalfMutationSkipped(for thread: ExchangeThread) -> Bool {
        skipsSecondHalfMutation(for: lane(for: thread))
    }

    // MARK: - Private

    private static func laneFromQueryIntentClass(
        _ queryIntentClass: ExchangeIntent.QueryIntentClass
    ) -> ExchangeThreadLane {
        switch queryIntentClass {
        case .providerSearch, .offerSearch, .capabilitySearch, .collaborationSearch:
            return .commercialInquiry
        case .socialAffinitySearch, .relationshipSearch:
            return .socialConnection
        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return .unknown
        }
    }

    private static func parseStoredLane(_ raw: String?) -> ExchangeThreadLane? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return ExchangeThreadLane(rawValue: trimmed)
    }

    private static func normalizedConversationSurface(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isTruthy(_ raw: String?) -> Bool {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }
}
