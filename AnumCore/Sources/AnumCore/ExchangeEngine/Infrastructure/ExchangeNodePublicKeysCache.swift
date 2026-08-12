import Foundation

/// In-memory TTL cache for GET /v1/nodes/:nodeID/keys (positive + short negative).
actor ExchangeNodePublicKeysCache {
    static let shared = ExchangeNodePublicKeysCache()

    static let positiveTTL: TimeInterval = 10 * 60
    static let negativeTTL: TimeInterval = 45

    private struct PositiveEntry {
        let keys: ExchangeNodePublicKeys
        let expiresAt: Date
    }

    private struct NegativeEntry {
        let expiresAt: Date
    }

    private var positiveByNodeID: [String: PositiveEntry] = [:]
    private var negativeByNodeID: [String: NegativeEntry] = [:]

    func cachedKeys(nodeID: String, now: Date = Date()) -> ExchangeNodePublicKeys? {
        let normalized = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        guard let entry = positiveByNodeID[normalized] else {
            return nil
        }

        if entry.expiresAt <= now {
            positiveByNodeID.removeValue(forKey: normalized)
            print("[publicKeyCache] expired nodeID=\(normalized)")
            return nil
        }

        print("[publicKeyCache] hit nodeID=\(normalized)")
        return entry.keys
    }

    func isNegativeCached(nodeID: String, now: Date = Date()) -> Bool {
        let normalized = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        guard let entry = negativeByNodeID[normalized] else {
            return false
        }

        if entry.expiresAt <= now {
            negativeByNodeID.removeValue(forKey: normalized)
            return false
        }

        print("[publicKeyCache] hit negative nodeID=\(normalized)")
        return true
    }

    func store(keys: ExchangeNodePublicKeys, now: Date = Date()) {
        let normalized = keys.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        positiveByNodeID[normalized] = PositiveEntry(
            keys: keys,
            expiresAt: now.addingTimeInterval(Self.positiveTTL)
        )
        negativeByNodeID.removeValue(forKey: normalized)
        print("[publicKeyCache] store nodeID=\(normalized)")
    }

    func storeNegative(nodeID: String, now: Date = Date()) {
        let normalized = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        negativeByNodeID[normalized] = NegativeEntry(
            expiresAt: now.addingTimeInterval(Self.negativeTTL)
        )
        positiveByNodeID.removeValue(forKey: normalized)
        print("[publicKeyCache] storeNegative nodeID=\(normalized)")
    }

    func invalidate(nodeID: String) {
        let normalized = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        positiveByNodeID.removeValue(forKey: normalized)
        negativeByNodeID.removeValue(forKey: normalized)
    }
}
