import Foundation

/// Tables touched by a local hard-delete of one Exchange thread.
public enum ExchangeThreadLocalDeleteTable: String, Sendable, CaseIterable, Hashable {
    case audit = "exchange_audit_records"
    case inbox = "exchange_inbox_items"
    case secretaryNotifications = "exchange_secretary_notifications"
    case trustEvidence = "exchange_trust_evidence"
    case failures = "exchange_failures"
    case threads = "exchange_threads"
    /// Rows removed via `ON DELETE CASCADE` when the thread row is deleted.
    case turns = "exchange_turns"
    case drafts = "exchange_drafts"
    case approvals = "exchange_approvals"
    case outcomes = "exchange_outcomes"
    case matches = "exchange_matches"
    case artifacts = "exchange_artifacts"
    case outbox = "exchange_outbox_items"
}

/// Per-table row counts removed during `hardDeleteThreadLocally`.
public struct ExchangeThreadLocalDeleteReport: Sendable, Hashable {
    public let threadID: ExchangeThread.ID
    public let deletedCounts: [ExchangeThreadLocalDeleteTable: Int]

    public init(
        threadID: ExchangeThread.ID,
        deletedCounts: [ExchangeThreadLocalDeleteTable: Int]
    ) {
        self.threadID = threadID
        self.deletedCounts = deletedCounts
    }

    public var totalDeleted: Int {
        deletedCounts.values.reduce(0, +)
    }

    public func deletedCount(for table: ExchangeThreadLocalDeleteTable) -> Int {
        deletedCounts[table, default: 0]
    }
}
