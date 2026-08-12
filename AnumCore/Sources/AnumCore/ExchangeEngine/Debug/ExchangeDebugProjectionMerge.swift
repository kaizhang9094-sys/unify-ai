import Foundation

#if DEBUG

enum ExchangeDebugProjectionMerge {
    static func mergeMatchedOfferIDs(
        into matchedOffersByNode: inout [String: [String]],
        nodeID: String?,
        offerID: String?,
        matchedOfferIDs: [String] = []
    ) {
        guard let nodeID, !nodeID.isEmpty else { return }

        var offerIDs: [String] = []
        if let offerID, !offerID.isEmpty {
            offerIDs.append(offerID)
        }
        offerIDs.append(contentsOf: matchedOfferIDs.filter { !$0.isEmpty })

        var seenInput = Set<String>()
        offerIDs = offerIDs.filter { seenInput.insert($0).inserted }

        guard !offerIDs.isEmpty else {
            if matchedOffersByNode[nodeID] == nil {
                matchedOffersByNode[nodeID] = []
            }
            return
        }

        var existing = matchedOffersByNode[nodeID] ?? []
        var existingSet = Set(existing)

        for offerID in offerIDs {
            if existingSet.insert(offerID).inserted {
                existing.append(offerID)
            } else {
                print("[ProjectionDedup] duplicate offerID=\(offerID) nodeID=\(nodeID) policy=keepExistingOffer")
            }
        }

        matchedOffersByNode[nodeID] = existing
    }

    static func keepFirstByID<T>(
        _ items: [T],
        id: (T) -> String?
    ) -> [String: T] {
        var result: [String: T] = [:]

        for item in items {
            guard let key = id(item), !key.isEmpty else { continue }

            if result[key] != nil {
                print("[ProjectionDedup] duplicate id=\(key) policy=keepFirst")
                continue
            }

            result[key] = item
        }

        return result
    }

    /// Keeps projected offer IDs from the highest-scoring match per node (no sibling-offer union).
    static func aggregateProjectedOffersByNode(from matches: [ExchangeMatch]) -> [String: [String]] {
        let sorted = matches.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.createdAt > rhs.createdAt
        }

        var result: [String: [String]] = [:]
        var seenNodes = Set<String>()

        for match in sorted {
            let nodeID = match.counterpartyID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nodeID.isEmpty, !seenNodes.contains(nodeID) else { continue }
            seenNodes.insert(nodeID)

            var offerIDs: [String] = []
            if let primary = match.offerID?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
                offerIDs.append(primary)
            }
            for offerID in match.matchedOfferIDs {
                let trimmed = offerID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if !offerIDs.contains(trimmed) {
                    offerIDs.append(trimmed)
                }
            }
            result[nodeID] = offerIDs
        }

        return result
    }
}

#endif
