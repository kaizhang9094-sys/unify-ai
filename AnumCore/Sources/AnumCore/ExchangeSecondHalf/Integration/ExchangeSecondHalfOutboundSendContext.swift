import Foundation

/// Thread + optional latest draft facts used to derive whether a requester clarification
/// to a provider actually left the device (queued / sending / sent), vs purely local drafting.
///
/// This is intentionally read-only telemetry — it does **not** change autonomy policy or queue behavior.
public struct ExchangeSecondHalfOutboundSendContext: Sendable, Hashable {

    /// Optional thread metadata slice (normally `ExchangeThread.metadata`) for autonomy recording.
    public var autonomousMetadata: [String: String]

    /// Latest draft outbound markers when the caller already has `ExchangeMessageDraft` loaded.
    public var draftMetadata: [String: String]

    /// Delivery snapshot copied from thread when constructing this context (optional).
    public var deliverySnapshot: ExchangeThread.DeliverySnapshot?

    public init(
        thread: ExchangeThread,
        latestDraft: ExchangeMessageDraft? = nil
    ) {
        self.autonomousMetadata = thread.metadata
        self.draftMetadata = latestDraft?.metadata ?? [:]
        self.deliverySnapshot = thread.delivery
    }

    public init(
        autonomousMetadata: [String: String] = [:],
        draftMetadata: [String: String] = [:],
        deliverySnapshot: ExchangeThread.DeliverySnapshot? = nil
    ) {
        self.autonomousMetadata = autonomousMetadata
        self.draftMetadata = draftMetadata
        self.deliverySnapshot = deliverySnapshot
    }

    /// True when autonomy recording shows requester outbound was blocked by secretary mode/settings.
    public var requesterOutboundExplicitlyBlockedByRecording: Bool {
        let lane = autonomousMetadata["autonomous_send_lane"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = autonomousMetadata["autonomous_send_outcome"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if outcome == "disabledByUserSetting" {
            return true
        }
        if lane == "requester_outbound", autonomousMetadata["autonomous_send_allowed"] == "false" {
            return true
        }
        return false
    }

    /// Positive evidence something is or was externally moving for this clarification path.
    public func hasPositiveSendProofForRequesterProviderClarification() -> Bool {
        if let delivery = deliverySnapshot {
            switch delivery.status {
            case .readyToSend, .sending, .sent:
                return true
            case .notStarted, .pendingApproval, .failed:
                break
            }
        }

        if truthyMarker(draftMetadata["second_half_outbound_queued"]) {
            return true
        }

        if truthyMarker(draftMetadata["second_half_auto_response_queued"]) {
            return true
        }

        return false
    }
}

extension ExchangeSecondHalfOutboundSendContext {
    func truthyMarker(_ raw: String?) -> Bool {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !trimmed.isEmpty
        else { return false }

        switch trimmed {
        case "true", "1", "yes":
            return true
        default:
            return false
        }
    }
}
