import Foundation
import CryptoKit

/// Canonical mapping from runtime node identity strings to the UUID node-scope key
/// required by second-half stores.
public enum ExchangeSecretaryStyleScopeID {
    public static func nodeScopedUUID(
        from rawNodeID: String?
    ) -> UUID? {
        guard let rawNodeID else { return nil }
        let trimmed = rawNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = UUID(uuidString: trimmed) {
            return direct
        }

        let digest = SHA256.hash(data: Data(trimmed.utf8))
        var bytes = Array(digest.prefix(16))

        // Set RFC4122 version/variant bits for stable UUID formatting.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
