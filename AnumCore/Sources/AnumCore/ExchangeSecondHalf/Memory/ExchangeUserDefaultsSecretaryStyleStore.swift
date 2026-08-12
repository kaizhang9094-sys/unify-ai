import Foundation

/// UserDefaults-backed secretary style persistence for app-runtime durability.
///
/// Keeps the protocol surface unchanged while making style profiles survive restart.
public actor ExchangeUserDefaultsSecretaryStyleStore: ExchangeSecretaryStyleStore {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "exchange.secondhalf.secretary.style"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func loadStyleProfile(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeSecretaryStyleProfile? {
        try loadProfile(key: makeThreadKey(threadID: threadID, role: role))
    }

    public func loadStyleProfile(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeSecretaryStyleProfile? {
        try loadProfile(key: makeNodeKey(nodeID: nodeID, role: role))
    }

    public func saveStyleProfile(
        _ profile: ExchangeSecretaryStyleProfile,
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        try saveProfile(profile, key: makeThreadKey(threadID: threadID, role: role))
    }

    public func saveStyleProfile(
        _ profile: ExchangeSecretaryStyleProfile,
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        try saveProfile(profile, key: makeNodeKey(nodeID: nodeID, role: role))
    }

    public func clearStyleProfile(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        defaults.removeObject(forKey: makeThreadKey(threadID: threadID, role: role))
    }

    public func clearStyleProfile(
        forNodeID nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        defaults.removeObject(forKey: makeNodeKey(nodeID: nodeID, role: role))
    }
}

private extension ExchangeUserDefaultsSecretaryStyleStore {
    func makeThreadKey(
        threadID: UUID,
        role: ExchangeSecondHalfRole
    ) -> String {
        "\(keyPrefix).thread.\(threadID.uuidString.lowercased()).role.\(role.rawValue)"
    }

    func makeNodeKey(
        nodeID: UUID,
        role: ExchangeSecondHalfRole
    ) -> String {
        "\(keyPrefix).node.\(nodeID.uuidString.lowercased()).role.\(role.rawValue)"
    }

    func loadProfile(
        key: String
    ) throws -> ExchangeSecretaryStyleProfile? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try decoder.decode(ExchangeSecretaryStyleProfile.self, from: data)
    }

    func saveProfile(
        _ profile: ExchangeSecretaryStyleProfile,
        key: String
    ) throws {
        let data = try encoder.encode(profile)
        defaults.set(data, forKey: key)
    }
}
