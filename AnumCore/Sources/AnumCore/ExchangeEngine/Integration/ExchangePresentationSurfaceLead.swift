import Foundation

/// Presentation-only lead for inbox rows, thread hero URLs, and opportunity headlines.
///
/// Driven strictly by stored selection anchors on the thread, not by whether a resolved
/// ``ExchangeOffer`` exists for hydration (profile-led nodes may still have offers in store).
public enum ExchangePresentationSurfaceLead: Sendable, Equatable {
    case offerLed
    case profileLed
    case ambiguous

    public static func resolve(
        selectedOfferID: String?,
        selectedPublicProfileID: String?
    ) -> ExchangePresentationSurfaceLead {
        let offerTrimmed = selectedOfferID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !offerTrimmed.isEmpty { return .offerLed }

        let profileTrimmed = selectedPublicProfileID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !profileTrimmed.isEmpty { return .profileLed }

        return .ambiguous
    }
}
