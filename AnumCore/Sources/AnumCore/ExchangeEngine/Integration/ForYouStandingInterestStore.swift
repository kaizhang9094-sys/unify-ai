import Foundation

/// UserDefaults-backed cache for `ForYouStandingInterest` (per local node).
public struct ForYouStandingInterestStore {
    public static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    private func storageKey(nodeID: String) -> String {
        let trimmed = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        return "forYou.standingInterest.v2.\(trimmed)"
    }

    public func load(nodeID: String) -> ForYouStandingInterest? {
        let key = storageKey(nodeID: nodeID)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(ForYouStandingInterest.self, from: data)
    }

    public func save(_ interest: ForYouStandingInterest, nodeID: String) {
        let key = storageKey(nodeID: nodeID)
        guard let data = try? encoder.encode(interest) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear(nodeID: String) {
        defaults.removeObject(forKey: storageKey(nodeID: nodeID))
    }

    /// UserDefaults key used for `load` / `save` (diagnostics only).
    public func debugStorageKey(forNodeID nodeID: String) -> String {
        storageKey(nodeID: nodeID)
    }

    /// True when fingerprint matches the current profile and entry is within `maxAge` of `generatedAt`.
    public func isValid(
        _ interest: ForYouStandingInterest,
        for profile: ExchangePublicNodeProfile,
        maxAge: TimeInterval = Self.defaultMaxAge,
        now: Date = Date()
    ) -> Bool {
        guard maxAge > 0 else { return false }
        guard now.timeIntervalSince(interest.generatedAt) <= maxAge else { return false }
        let current = ForYouStandingInterestProfileFingerprint.make(for: profile)
        return interest.sourceProfileFingerprint == current
    }
}
