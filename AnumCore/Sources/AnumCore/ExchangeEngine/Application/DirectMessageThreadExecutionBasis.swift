import Foundation

/// Aligns persisted ``ExchangeThread`` selection fields with the **trusted manual DM** execution
/// counterparty + public profile so ``ExchangeEnvelopeService/validateExecutionBasis`` is not
/// tripped by stale exchange / ForYou / opportunity anchors left on an otherwise DM-marked thread.
public enum DirectMessageThreadExecutionBasis: Sendable {
    /// Returns a thread snapshot with basis fields aligned to `counterparty` + `publicProfile`.
    /// Callers persist when `mutated` is true.
    public static func repairedThreadForTrustedManualSend(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        now: Date
    ) -> (
        thread: ExchangeThread,
        mutated: Bool,
        clearedSelectedPublicProfileID: String?,
        clearedSelectedOfferID: String?
    ) {
        let isDM = thread.metadata["direct_message_thread"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "true"
        guard isDM else {
            return (thread, false, nil, nil)
        }

        var t = thread
        var mutated = false
        var clearedProfile: String?
        var clearedOffer: String?

        let counterpartyID = counterparty.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileID = publicProfile.id.trimmingCharacters(in: .whitespacesAndNewlines)

        let selectedCP = t.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        if selectedCP != counterpartyID {
            t.selectedCounterpartyID = counterpartyID
            mutated = true
        }

        if let offer = t.selectedOfferID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            clearedOffer = offer
            t.selectedOfferID = nil
            mutated = true
        }

        let currentProfile = t.selectedPublicProfileID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        if currentProfile != profileID {
            if let currentProfile { clearedProfile = currentProfile }
            t.selectedPublicProfileID = profileID
            mutated = true
        }

        if t.metadata["conversation_surface"]?.trimmingCharacters(in: .whitespacesAndNewlines) != "direct_message" {
            t.metadata["conversation_surface"] = "direct_message"
            mutated = true
        }

        if mutated {
            t.updatedAt = now
        }

        return (t, mutated, clearedProfile, clearedOffer)
    }
}

private extension String {
    var nilIfBlank: String? {
        let s = trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
