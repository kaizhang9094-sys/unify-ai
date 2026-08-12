import Foundation
import CryptoKit
import Security

public struct NodeIdentity: Sendable, Hashable {
    public let nodeID: String
    public let publicKeyID: String
    public let publicKeyData: Data
}

/// X25519 key-agreement identity for federation message encryption (separate from Ed25519 signing).
public struct NodeEncryptionIdentity: Sendable, Hashable {
    public let encryptionKeyID: String
    public let publicKeyData: Data

    public var encryptionPublicKeyBase64: String {
        publicKeyData.base64EncodedString()
    }
}

public final class NodeIdentityVault: @unchecked Sendable {
    
    public static let shared = NodeIdentityVault()

    private let service = Bundle.main.bundleIdentifier ?? "com.unify.app"
    private let signingAccount = "stable-node-identity-ed25519-seed-v1"
    private let encryptionAccount = "stable-node-encryption-x25519-seed-v1"

    public init() {}

    public func loadOrCreateIdentity() throws -> NodeIdentity {
        let seed = try loadOrCreateSeed(account: signingAccount)
        return try signingIdentity(fromSeed: seed)
    }

    public func currentNodeID() throws -> String {
        try loadOrCreateIdentity().nodeID
    }

    public func loadOrCreateSigningMaterial() throws -> NodeSigningMaterial {
        let seed = try loadOrCreateSeed(account: signingAccount)
        let identity = try signingIdentity(fromSeed: seed)
        return NodeSigningMaterial(
            nodeID: identity.nodeID,
            publicKeyID: identity.publicKeyID,
            publicKeyData: identity.publicKeyData,
            seed: seed
        )
    }

    public func loadOrCreateEncryptionMaterial() throws -> NodeEncryptionMaterial {
        let seed = try loadOrCreateSeed(account: encryptionAccount)
        let identity = try encryptionIdentity(fromSeed: seed)
        return NodeEncryptionMaterial(
            encryptionKeyID: identity.encryptionKeyID,
            publicKeyData: identity.publicKeyData,
            seed: seed
        )
    }

    /// Destructively removes federation signing and encryption seeds from the Keychain.
    ///
    /// Does not delete local Companion/Secretary databases, transcripts, or remote published data.
    /// Call only from an explicit user-confirmed identity reset flow — never from routine local wipes.
    public func resetFederationIdentity() throws {
        try deleteSeedFromKeychain(account: signingAccount)
        try deleteSeedFromKeychain(account: encryptionAccount)
    }

    public func resetIdentityForDebugOnly() throws {
        #if DEBUG
        try resetFederationIdentity()
        #else
        throw NSError(
            domain: "NodeIdentityVault",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Identity reset is debug-only."]
        )
        #endif
    }
}

private extension NodeIdentityVault {
    func signingIdentity(fromSeed seed: Data) throws -> NodeIdentity {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let publicKey = privateKey.publicKey.rawRepresentation
        let nodeID = makeNodeID(from: publicKey)
        let publicKeyID = makeSigningPublicKeyID(from: nodeID)

        return NodeIdentity(
            nodeID: nodeID,
            publicKeyID: publicKeyID,
            publicKeyData: publicKey
        )
    }

    func encryptionIdentity(fromSeed seed: Data) throws -> NodeEncryptionIdentity {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: seed)
        let publicKey = privateKey.publicKey.rawRepresentation
        let encryptionKeyID = makeEncryptionKeyID(from: publicKey)
        return NodeEncryptionIdentity(
            encryptionKeyID: encryptionKeyID,
            publicKeyData: publicKey
        )
    }

    func loadOrCreateSeed(account: String) throws -> Data {
        if let existing = try loadSeedFromKeychain(account: account) {
            return existing
        }
        let created = try makeSeed()
        try saveSeedToKeychain(created, account: account)
        return created
    }

    func makeNodeID(from publicKey: Data) -> String {
        let hash = SHA256.hash(data: publicKey)
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        let short = String(hex.prefix(32))
        return "node-\(short)"
    }

    func makeSigningPublicKeyID(from nodeID: String) -> String {
        "key-" + String(nodeID.dropFirst("node-".count))
    }

    func makeEncryptionKeyID(from encryptionPublicKey: Data) -> String {
        let hash = SHA256.hash(data: encryptionPublicKey)
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        let short = String(hex.prefix(32))
        return "ekey-\(short)"
    }

    func makeSeed() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to generate node identity seed."]
            )
        }
        return Data(bytes)
    }

    func loadSeedFromKeychain(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw NSError(
                    domain: "NodeIdentityVault",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Keychain returned unexpected seed type."]
                )
            }
            return data

        case errSecItemNotFound:
            return nil

        default:
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to load node identity from Keychain."]
            )
        }
    }

    func saveSeedToKeychain(_ seed: Data, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: seed,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]

            let attributes: [CFString: Any] = [
                kSecValueData: seed,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw NSError(
                    domain: NSOSStatusErrorDomain,
                    code: Int(updateStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to update node identity in Keychain."]
                )
            }
            return
        }

        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to save node identity in Keychain."]
            )
        }
    }

    func deleteSeedFromKeychain(account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete node identity from Keychain."]
            )
        }
    }
}

public struct NodeSigningMaterial: Sendable, Hashable {
    public let nodeID: String
    public let publicKeyID: String
    public let publicKeyData: Data
    public let seed: Data
}

public struct NodeEncryptionMaterial: Sendable, Hashable {
    public let encryptionKeyID: String
    public let publicKeyData: Data
    public let seed: Data

    public var encryptionPublicKeyBase64: String {
        publicKeyData.base64EncodedString()
    }
}
