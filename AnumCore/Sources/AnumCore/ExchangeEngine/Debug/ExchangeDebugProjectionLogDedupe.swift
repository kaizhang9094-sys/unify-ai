import Foundation

#if DEBUG

/// Suppresses repeated DEBUG projection logs when list/detail refresh revisits unchanged rows.
public enum ExchangeDebugProjectionLogDedupe {
    private final class Store: @unchecked Sendable {
        let lock = NSLock()
        var opportunityKeys = Set<String>()
        var coordinationIndexKeys = Set<String>()
        var threadsViewFilterKeys = Set<String>()

        func remember(_ key: String, in bucket: Bucket) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let inserted: Bool
            switch bucket {
            case .opportunity:
                inserted = opportunityKeys.insert(key).inserted
            case .coordinationIndex:
                inserted = coordinationIndexKeys.insert(key).inserted
            case .threadsViewFilter:
                inserted = threadsViewFilterKeys.insert(key).inserted
            }
            return inserted
        }

        enum Bucket {
            case opportunity
            case coordinationIndex
            case threadsViewFilter
        }
    }

    private static let store = Store()

    public static func shouldLogOpportunityDisplay(
        threadID: String,
        selectedOfferID: String?,
        resolvedSurface: String,
        title: String?
    ) -> Bool {
        let key = [
            threadID,
            selectedOfferID ?? "nil",
            resolvedSurface,
            title ?? "nil",
        ].joined(separator: "|")
        return store.remember(key, in: .opportunity)
    }

    public static func shouldLogCoordinationThreadIndex(
        threadID: String,
        rawRole: String,
        parsedRole: String,
        parentThreadID: String?,
        rootThreadID: String?,
        archived: Bool,
        inclusion: String
    ) -> Bool {
        let key = [
            threadID,
            rawRole,
            parsedRole,
            parentThreadID ?? "nil",
            rootThreadID ?? "nil",
            archived ? "1" : "0",
            inclusion,
        ].joined(separator: "|")
        return store.remember(key, in: .coordinationIndex)
    }

    public static func shouldLogThreadsViewFilter(
        threadID: String,
        reason: String
    ) -> Bool {
        let key = [threadID, reason].joined(separator: "|")
        return store.remember(key, in: .threadsViewFilter)
    }
}

#endif
