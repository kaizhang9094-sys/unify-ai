import Foundation

public enum ExchangeLocalMaintenanceTable: String, Sendable, CaseIterable, Hashable {
    case outbox = "exchange_outbox_items"
    case inbox = "exchange_inbox_items"
    case staleInboxOpenRows = "exchange_inbox_items_open"
    case audit = "exchange_audit_records"
    case secretaryNotifications = "exchange_secretary_notifications"
    case discoveryMatches = "exchange_matches"
    case staleRemoteOffers = "exchange_offers"
    case staleRemotePublicProfiles = "exchange_public_profiles"
    case staleRemoteCounterparties = "exchange_counterparties"
}

/// Per-table deletion counts from a single explicit maintenance pass.
public struct ExchangeLocalMaintenanceResult: Sendable, Hashable {
    public let reason: String
    public let startedAt: Date
    public let completedAt: Date
    public let deletedCounts: [ExchangeLocalMaintenanceTable: Int]

    public init(
        reason: String,
        startedAt: Date,
        completedAt: Date,
        deletedCounts: [ExchangeLocalMaintenanceTable: Int]
    ) {
        self.reason = reason
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.deletedCounts = deletedCounts
    }

    public var totalDeleted: Int {
        deletedCounts.values.reduce(0, +)
    }

    public func deletedCount(for table: ExchangeLocalMaintenanceTable) -> Int {
        deletedCounts[table, default: 0]
    }
}
