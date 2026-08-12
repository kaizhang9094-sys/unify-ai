import Foundation

/// Structural role for umbrella search vs child coordination threads.
///
/// Stored in `ExchangeThread.metadata["thread_role"]` until first-class schema fields exist.
/// Orthogonal to `ExchangeThreadLane` (`thread_lane`), which gates commercial vs DM vs social flow.
public enum ExchangeThreadRole: String, Codable, Sendable, Equatable, CaseIterable {
    case standalone
    case umbrellaSearch
    case candidateCoordination
}

public enum ExchangeThreadRoleResolver {
    public static let threadRoleMetadataKey = "thread_role"
    public static let parentThreadIDMetadataKey = "parent_thread_id"
    public static let rootThreadIDMetadataKey = "root_thread_id"
    public static let sourceMatchIDMetadataKey = "source_match_id"
    public static let sourceRankMetadataKey = "source_rank"

    // MARK: - Resolve

    public static func role(for thread: ExchangeThread) -> ExchangeThreadRole {
        role(metadata: thread.metadata)
    }

    public static func role(metadata: [String: String]) -> ExchangeThreadRole {
        guard let parsed = parseStoredRole(metadata[threadRoleMetadataKey]) else {
            return .standalone
        }
        return parsed
    }

    public static func parentThreadID(for thread: ExchangeThread) -> ExchangeThread.ID? {
        parentThreadID(metadata: thread.metadata)
    }

    public static func parentThreadID(metadata: [String: String]) -> ExchangeThread.ID? {
        parseThreadID(metadata[parentThreadIDMetadataKey])
    }

    public static func rootThreadID(for thread: ExchangeThread) -> ExchangeThread.ID? {
        rootThreadID(metadata: thread.metadata)
    }

    public static func rootThreadID(metadata: [String: String]) -> ExchangeThread.ID? {
        parseThreadID(metadata[rootThreadIDMetadataKey])
    }

    public static func sourceMatchID(for thread: ExchangeThread) -> ExchangeMatch.ID? {
        sourceMatchID(metadata: thread.metadata)
    }

    public static func sourceMatchID(metadata: [String: String]) -> ExchangeMatch.ID? {
        parseMatchID(metadata[sourceMatchIDMetadataKey])
    }

    public static func sourceRank(for thread: ExchangeThread) -> Int? {
        sourceRank(metadata: thread.metadata)
    }

    public static func sourceRank(metadata: [String: String]) -> Int? {
        parseRank(metadata[sourceRankMetadataKey])
    }

    // MARK: - Apply

    public static func applyRole(_ role: ExchangeThreadRole, to metadata: inout [String: String]) {
        if role == .standalone {
            metadata.removeValue(forKey: threadRoleMetadataKey)
        } else {
            metadata[threadRoleMetadataKey] = role.rawValue
        }
    }

    public static func applyParentThreadID(_ id: ExchangeThread.ID?, to metadata: inout [String: String]) {
        applyUUID(id, key: parentThreadIDMetadataKey, to: &metadata)
    }

    public static func applyRootThreadID(_ id: ExchangeThread.ID?, to metadata: inout [String: String]) {
        applyUUID(id, key: rootThreadIDMetadataKey, to: &metadata)
    }

    public static func applySourceMatchID(_ id: ExchangeMatch.ID?, to metadata: inout [String: String]) {
        applyUUID(id, key: sourceMatchIDMetadataKey, to: &metadata)
    }

    public static func applySourceRank(_ rank: Int?, to metadata: inout [String: String]) {
        guard let rank, rank > 0 else {
            metadata.removeValue(forKey: sourceRankMetadataKey)
            return
        }
        metadata[sourceRankMetadataKey] = String(rank)
    }

    /// Applies umbrella/child hierarchy metadata for a coordination child thread.
    public static func applyCandidateCoordinationHierarchy(
        parentThreadID: ExchangeThread.ID,
        rootThreadID: ExchangeThread.ID,
        sourceMatchID: ExchangeMatch.ID?,
        sourceRank: Int?,
        to metadata: inout [String: String]
    ) {
        applyRole(.candidateCoordination, to: &metadata)
        applyParentThreadID(parentThreadID, to: &metadata)
        applyRootThreadID(rootThreadID, to: &metadata)
        applySourceMatchID(sourceMatchID, to: &metadata)
        applySourceRank(sourceRank, to: &metadata)
    }

    /// Applies umbrella search workbench metadata for a parent discovery thread.
    public static func applyUmbrellaSearchRole(
        rootThreadID: ExchangeThread.ID? = nil,
        to metadata: inout [String: String]
    ) {
        applyRole(.umbrellaSearch, to: &metadata)
        if let rootThreadID {
            applyRootThreadID(rootThreadID, to: &metadata)
        } else {
            metadata.removeValue(forKey: rootThreadIDMetadataKey)
        }
        metadata.removeValue(forKey: parentThreadIDMetadataKey)
        metadata.removeValue(forKey: sourceMatchIDMetadataKey)
        metadata.removeValue(forKey: sourceRankMetadataKey)
    }

    // MARK: - Private

    private static func parseStoredRole(_ raw: String?) -> ExchangeThreadRole? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return ExchangeThreadRole(rawValue: trimmed)
    }

    private static func parseThreadID(_ raw: String?) -> ExchangeThread.ID? {
        parseUUID(raw)
    }

    private static func parseMatchID(_ raw: String?) -> ExchangeMatch.ID? {
        parseUUID(raw)
    }

    private static func parseUUID(_ raw: String?) -> UUID? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return UUID(uuidString: trimmed)
    }

    private static func parseRank(_ raw: String?) -> Int? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private static func applyUUID(_ id: UUID?, key: String, to metadata: inout [String: String]) {
        if let id {
            metadata[key] = id.uuidString.lowercased()
        } else {
            metadata.removeValue(forKey: key)
        }
    }
}

// MARK: - ExchangeThread accessors

public extension ExchangeThread {
    /// Defaults to `.standalone` when `thread_role` metadata is missing or invalid.
    var threadRole: ExchangeThreadRole {
        get { ExchangeThreadRoleResolver.role(for: self) }
        set { ExchangeThreadRoleResolver.applyRole(newValue, to: &metadata) }
    }

    var parentThreadID: ExchangeThread.ID? {
        get { ExchangeThreadRoleResolver.parentThreadID(for: self) }
        set { ExchangeThreadRoleResolver.applyParentThreadID(newValue, to: &metadata) }
    }

    var rootThreadID: ExchangeThread.ID? {
        get { ExchangeThreadRoleResolver.rootThreadID(for: self) }
        set { ExchangeThreadRoleResolver.applyRootThreadID(newValue, to: &metadata) }
    }

    var sourceMatchID: ExchangeMatch.ID? {
        get { ExchangeThreadRoleResolver.sourceMatchID(for: self) }
        set { ExchangeThreadRoleResolver.applySourceMatchID(newValue, to: &metadata) }
    }

    var sourceRank: Int? {
        get { ExchangeThreadRoleResolver.sourceRank(for: self) }
        set { ExchangeThreadRoleResolver.applySourceRank(newValue, to: &metadata) }
    }

    /// Local History/desk hide flag (`metadata["archived"] == "true"`).
    var isArchived: Bool {
        metadata[ExchangeThreadArchiveMetadata.archivedKey] == "true"
    }
}

// MARK: - Archive metadata

public enum ExchangeThreadArchiveMetadata {
    public static let archivedKey = "archived"
    public static let archivedAtKey = "archived_at"
    public static let archivedByParentKey = "archived_by_parent"
}
