import Foundation

/// Durable structured operating memory record.
///
/// Keeps role-scoped second-half operating memory in a durable record shape.
public struct ExchangeOperatingMemoryRecord: Codable, Hashable, Sendable {
    public var ownerID: UUID
    public var ownerScope: OwnerScope
    public var role: ExchangeSecondHalfRole
    public var savedAt: Date
    public var memory: ExchangeStructuredOperatingMemory

    public enum OwnerScope: String, Codable, CaseIterable, Hashable, Sendable {
        case thread
        case node
    }

    public init(
        ownerID: UUID,
        ownerScope: OwnerScope,
        role: ExchangeSecondHalfRole,
        savedAt: Date = Date(),
        memory: ExchangeStructuredOperatingMemory
    ) {
        self.ownerID = ownerID
        self.ownerScope = ownerScope
        self.role = role
        self.savedAt = savedAt
        self.memory = memory
    }
}

public extension ExchangeOperatingMemoryRecord {
    static func threadScoped(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        memory: ExchangeStructuredOperatingMemory,
        savedAt: Date = Date()
    ) -> ExchangeOperatingMemoryRecord {
        ExchangeOperatingMemoryRecord(
            ownerID: threadID,
            ownerScope: .thread,
            role: role,
            savedAt: savedAt,
            memory: memory
        )
    }

    static func nodeScoped(
        nodeID: UUID,
        role: ExchangeSecondHalfRole,
        memory: ExchangeStructuredOperatingMemory,
        savedAt: Date = Date()
    ) -> ExchangeOperatingMemoryRecord {
        ExchangeOperatingMemoryRecord(
            ownerID: nodeID,
            ownerScope: .node,
            role: role,
            savedAt: savedAt,
            memory: memory
        )
    }
}
