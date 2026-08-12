import Foundation

#if DEBUG

public enum ExchangeProjectionDedup {
    public static func mergeMatchedOfferIDs(
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

    public static func keepFirstByID<T>(
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

    public static func aggregateProjectedOffersByNode(
        nodeID: String?,
        offerID: String?,
        matchedOfferIDs: [String] = []
    ) -> [String: [String]] {
        guard let nodeID, !nodeID.isEmpty else { return [:] }
        var aggregated: [String: [String]] = [:]
        mergeMatchedOfferIDs(
            into: &aggregated,
            nodeID: nodeID,
            offerID: offerID,
            matchedOfferIDs: matchedOfferIDs
        )
        return aggregated
    }
}

#endif
