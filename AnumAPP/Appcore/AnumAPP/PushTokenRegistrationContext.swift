import Foundation

/// Federation push token registration identity: local node + APNs upload environment + device token.
struct PushTokenRegistrationContext: Equatable, Sendable {
    static let storageKey = "secretary.apns.lastRegisteredContext.v1"
    private static let separator = "|"

    let nodeID: String
    let environment: String
    let tokenHex: String

    init(nodeID: String, environment: String, tokenHex: String) {
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.environment = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tokenHex = tokenHex.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var serialized: String {
        "\(nodeID)\(Self.separator)\(environment)\(Self.separator)\(tokenHex)"
    }

    static func parse(_ raw: String) -> PushTokenRegistrationContext? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: Character(separator), omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        let nodeID = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let environment = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenHex = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nodeID.isEmpty, !environment.isEmpty, !tokenHex.isEmpty else { return nil }

        return PushTokenRegistrationContext(
            nodeID: nodeID,
            environment: environment,
            tokenHex: tokenHex
        )
    }

    static func read(from defaults: UserDefaults) -> PushTokenRegistrationContext? {
        guard let raw = defaults.string(forKey: storageKey) else { return nil }
        return parse(raw)
    }

    static func write(_ context: PushTokenRegistrationContext, to defaults: UserDefaults) {
        defaults.set(context.serialized, forKey: storageKey)
    }

    static func hasStoredContext(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: storageKey) != nil
    }

    /// Returns whether upload should be skipped for the current registration triple.
    static func shouldSkipUpload(
        current: PushTokenRegistrationContext,
        stored: PushTokenRegistrationContext?,
        legacyTokenHex: String?,
        hasStoredContextKey: Bool,
        registrationFailed: Bool,
        remoteRegistrationFailed: Bool
    ) -> (skip: Bool, skipReason: String?) {
        if registrationFailed || remoteRegistrationFailed {
            return (false, nil)
        }

        if !hasStoredContextKey {
            let legacy = legacyTokenHex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !legacy.isEmpty {
                return (false, nil)
            }
        }

        guard let stored, stored == current else {
            return (false, nil)
        }

        return (true, "alreadyRegistered")
    }
}

enum PushTokenUploadFlushReason: String, Sendable {
    case registerSuccess
    case startup
    case presence
    case permissionToggle
    case appActive
    case retry
    case unknown
}

#if DEBUG
enum PushTokenRegistrationContextTests {
    static func run() {
        let nodeA = "node-aaa"
        let nodeB = "node-bbb"
        let token = "abc123"
        let sandbox = "sandbox"
        let production = "production"

        let currentSandbox = PushTokenRegistrationContext(nodeID: nodeA, environment: sandbox, tokenHex: token)
        let storedSandbox = PushTokenRegistrationContext(nodeID: nodeA, environment: sandbox, tokenHex: token)
        let storedProduction = PushTokenRegistrationContext(nodeID: nodeA, environment: production, tokenHex: token)
        let storedOtherNode = PushTokenRegistrationContext(nodeID: nodeB, environment: sandbox, tokenHex: token)

        assert(
            shouldSkip(current: currentSandbox, stored: storedSandbox, legacy: token, hasKey: true) == (true, "alreadyRegistered")
        )
        assert(
            shouldSkip(current: currentSandbox, stored: storedProduction, legacy: token, hasKey: true) == (false, nil)
        )
        assert(
            shouldSkip(current: currentSandbox, stored: storedOtherNode, legacy: token, hasKey: true) == (false, nil)
        )
        assert(
            shouldSkip(current: currentSandbox, stored: nil, legacy: token, hasKey: false) == (false, nil)
        )
        assert(
            shouldSkip(current: currentSandbox, stored: storedSandbox, legacy: token, hasKey: true, failed: true) == (false, nil)
        )
    }

    private static func shouldSkip(
        current: PushTokenRegistrationContext,
        stored: PushTokenRegistrationContext?,
        legacy: String?,
        hasKey: Bool,
        failed: Bool = false
    ) -> (Bool, String?) {
        PushTokenRegistrationContext.shouldSkipUpload(
            current: current,
            stored: stored,
            legacyTokenHex: legacy,
            hasStoredContextKey: hasKey,
            registrationFailed: failed,
            remoteRegistrationFailed: false
        )
    }
}
#endif
