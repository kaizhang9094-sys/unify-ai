import Foundation

/// Canonical classification for inbound/outbound contact-signal (friend/contact request) envelopes.
/// Federation reconcile and Chat pending-request projection must share this logic.
public enum ExchangeContactSignalClassifier {
    public static let contactRequestAcceptedPayloadKind = "contact_request_accepted"

    // MARK: - Inbound inbox items

    /// Inbound `friend_request_accepted` / contact acceptance envelopes (not pending requests).
    public static func isInboundContactRequestAcceptance(_ item: ExchangeInboxItem) -> Bool {
        let kind = normalized(item.metadata["payload_kind"])
        if kind == contactRequestAcceptedPayloadKind
            || kind == ExchangeRelayEnvelope.Payload.Kind.friendRequestAccepted.rawValue {
            return true
        }
        if normalized(item.metadata["contact_request_outcome"]) == "accepted" {
            return true
        }
        if normalized(item.metadata["accepted"]) == "true",
           normalized(item.metadata["contact_request"]) == "true" {
            return true
        }
        return false
    }

    /// Pending inbound contact/friend request inbox items (contact-signal lane, not desk threads).
    public static func isInboundContactRequest(_ item: ExchangeInboxItem) -> Bool {
        if isInboundContactRequestAcceptance(item) {
            return false
        }
        return matchesContactSignalMetadata(item.metadata)
    }

    /// Legacy alias used by federation reconcile routing.
    public static func isInboundFriendOrContactRequestSignal(_ item: ExchangeInboxItem) -> Bool {
        isInboundContactRequest(item)
    }

    /// Legacy alias used by Chat pending-request projection.
    public static func isContactRequestInboxItem(_ item: ExchangeInboxItem) -> Bool {
        isInboundContactRequest(item)
    }

    // MARK: - Metadata / thread markers

    public static func matchesContactSignalMetadata(_ metadata: [String: String]) -> Bool {
        if normalized(metadata["conversation_surface"]) == ExchangeThreadLaneResolver.conversationSurfaceContact {
            return true
        }

        let payloadKind = normalized(metadata["payload_kind"])
        if payloadKind == ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue {
            return true
        }
        if payloadKind == "contact_request" {
            return true
        }

        if normalized(metadata["contact_request"]) == "true" {
            if normalized(metadata["conversation_kind"]) == "friend_request" {
                return true
            }
            if payloadKind == ExchangeRelayEnvelope.Payload.Kind.introduction.rawValue {
                return true
            }
            if normalized(metadata["introduction_request"]) == "true" {
                return true
            }
            if normalized(metadata["friend_request"]) == "true" {
                return true
            }
            // Legacy contact requests that only set contact_request without surface/kind.
            return true
        }

        if normalized(metadata["friend_request"]) == "true" {
            return true
        }

        if normalized(metadata["conversation_kind"]) == "friend_request" {
            return true
        }

        if normalized(metadata[ExchangeThreadLaneResolver.metadataKey])
            == ExchangeThreadLane.contactSignal.rawValue {
            return true
        }

        if normalized(metadata["contact_signal_lane"]) == "true" {
            return true
        }

        if normalized(metadata["contact_request_thread"]) == "true" {
            return true
        }

        return false
    }

    /// Threads that must not appear on the operational Secretary desk (Threads tab).
    public static func isContactSignalDeskThread(_ thread: ExchangeThread) -> Bool {
        if matchesContactSignalMetadata(thread.metadata) {
            return true
        }

        let inboundFirstContact =
            normalized(thread.metadata["inbound_first_contact"]) == "true"
        let contactSurface =
            normalized(thread.metadata[ExchangeThreadLaneResolver.conversationSurfaceMetadataKey])
            == ExchangeThreadLaneResolver.conversationSurfaceContact
        let contactLane =
            normalized(thread.metadata[ExchangeThreadLaneResolver.metadataKey])
            == ExchangeThreadLane.contactSignal.rawValue

        if inboundFirstContact, contactSurface || contactLane {
            return true
        }

        return false
    }

    // MARK: - Private

    private static func normalized(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
