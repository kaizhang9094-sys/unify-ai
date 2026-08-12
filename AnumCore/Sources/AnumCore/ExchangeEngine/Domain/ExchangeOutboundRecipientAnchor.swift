import Foundation

/// Durable routing surface for **requester-authored** external counterparty drafts.
///
/// Mirrors the second-half execution context’s recipient fields and adds federation
/// inbound context so provider-side threads can still compose legitimate responses.
public enum ExchangeOutboundRecipientAnchor: Sendable {
    private static func nonBlank(_ raw: String?) -> Bool {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return false
        }
        return true
    }

    /// True when the thread has enough durable selection or inbound routing to justify
    /// persisting or showing a user-facing **external** counterparty draft.
    public static func hasRecipientSurface(
        selectedCounterpartyID: String?,
        selectedPublicProfileID: String?,
        selectedOfferID: String?,
        lastInboundEnvelopeID: String?
    ) -> Bool {
        if nonBlank(selectedCounterpartyID) { return true }
        if nonBlank(selectedOfferID) { return true }
        if nonBlank(selectedPublicProfileID) { return true }
        if nonBlank(lastInboundEnvelopeID) { return true }
        return false
    }

    public static func hasRecipientSurface(for thread: ExchangeThread) -> Bool {
        hasRecipientSurface(
            selectedCounterpartyID: thread.selectedCounterpartyID,
            selectedPublicProfileID: thread.selectedPublicProfileID,
            selectedOfferID: thread.selectedOfferID,
            lastInboundEnvelopeID: thread.lastInboundEnvelopeID
        )
    }
}
