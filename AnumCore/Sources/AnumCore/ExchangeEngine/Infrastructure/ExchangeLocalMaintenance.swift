import Foundation

/// Explicit entry point for conservative local Exchange SQLite pruning.
///
/// Does not touch threads/turns/messages, companion data, Keychain identity, or remote data.
public enum ExchangeLocalMaintenance {
    public static func run(
        on store: ExchangeSQLiteStore,
        policy: ExchangeLocalMaintenancePolicy = .default,
        now: Date = Date(),
        reason: String = "manual"
    ) async throws -> ExchangeLocalMaintenanceResult {
        try await store.runLocalMaintenance(policy: policy, now: now, reason: reason)
    }
}
