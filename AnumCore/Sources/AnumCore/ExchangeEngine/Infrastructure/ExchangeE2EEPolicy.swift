import Foundation

/// Policy for federation private text end-to-end encryption.
public enum ExchangeE2EEPolicy {
    /// Eligible private relay text envelopes require E2EE when the recipient encryption key is available.
    /// Plaintext fallback is allowed only when the recipient has no published encryption key.
    /// Key-fetch failures and crypto/seal failures block send instead of falling back to plaintext.
    public static var privateTextEncryptionEnabled: Bool { true }

    /// Backward-compatible alias for Phase 2 call sites.
    public static var dmTextEncryptionEnabled: Bool { privateTextEncryptionEnabled }
}
