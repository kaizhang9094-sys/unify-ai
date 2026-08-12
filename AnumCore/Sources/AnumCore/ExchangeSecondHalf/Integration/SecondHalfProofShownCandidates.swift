import Foundation

/// Resolves Discovery-activated coordination child offers for second-half proof gating.
enum SecondHalfProofShownCandidates: Sendable {
    struct Resolution: Sendable, Equatable {
        var offerIDs: Set<String>
        var orderedOfferIDs: [String]

        init(offerIDs: Set<String>, orderedOfferIDs: [String]) {
            self.offerIDs = offerIDs
            self.orderedOfferIDs = orderedOfferIDs
        }
    }

    /// Offer IDs for persisted activated coordination paths under an umbrella workbench.
    static func activatedOfferIDs(
        umbrellaThread: ExchangeThread,
        umbrellaMatches: [ExchangeMatch],
        activatedChildThreads: [ExchangeThread]
    ) -> Resolution {
        let sorted = activatedChildThreads
            .filter { $0.threadRole == .candidateCoordination && !$0.isArchived }
            .sorted { lhs, rhs in
                let leftRank = lhs.sourceRank ?? Int.max
                let rightRank = rhs.sourceRank ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.updatedAt > rhs.updatedAt
            }

        var ordered: [String] = []
        var seen = Set<String>()
        for child in sorted {
            guard let offerID = resolveOfferID(
                for: child,
                umbrellaMatches: umbrellaMatches,
                umbrellaThread: umbrellaThread
            ), seen.insert(offerID).inserted else {
                continue
            }
            ordered.append(offerID)
        }

        return Resolution(offerIDs: seen, orderedOfferIDs: ordered)
    }

    static func isShownSelectedOffer(
        selectedOfferID: String,
        resolution: Resolution
    ) -> Bool {
        resolution.offerIDs.contains(selectedOfferID)
    }

    static func resolveOfferID(
        for child: ExchangeThread,
        umbrellaMatches: [ExchangeMatch],
        umbrellaThread: ExchangeThread
    ) -> String? {
        if let fromChild = trimmed(child.selectedOfferID) {
            return fromChild
        }
        if let sourceMatchID = child.sourceMatchID,
           let match = umbrellaMatches.first(where: { $0.id == sourceMatchID }) {
            return ExchangeOfferObjectLane.resolveSelectedOfferID(from: match, thread: umbrellaThread)
                ?? trimmed(match.offerID)
                ?? trimmed(match.matchedOfferIDs.first)
        }
        return nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
