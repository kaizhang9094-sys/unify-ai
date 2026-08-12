import Foundation

/// Optional hooks from `ExchangeSQLiteStore` into higher-level Secretary notification logic.
/// Wired during bootstrap so `ExchangeFacade` can react without passing through every call site.
public struct ExchangeSecretarySQLiteHooks: Sendable {
    public var onApprovalSaved: (@Sendable (ExchangeApproval) async -> Void)?
    public var onTurnAppended: (@Sendable (ExchangeTurn) async -> Void)?
    public var onOutboxItemSaved: (@Sendable (ExchangeOutboxItem) async -> Void)?
    public var onFailurePersisted: (@Sendable (_ threadID: ExchangeThread.ID?, _ failure: ExchangeFailure) async -> Void)?

    public init(
        onApprovalSaved: (@Sendable (ExchangeApproval) async -> Void)? = nil,
        onTurnAppended: (@Sendable (ExchangeTurn) async -> Void)? = nil,
        onOutboxItemSaved: (@Sendable (ExchangeOutboxItem) async -> Void)? = nil,
        onFailurePersisted: (@Sendable (_ threadID: ExchangeThread.ID?, _ failure: ExchangeFailure) async -> Void)? = nil
    ) {
        self.onApprovalSaved = onApprovalSaved
        self.onTurnAppended = onTurnAppended
        self.onOutboxItemSaved = onOutboxItemSaved
        self.onFailurePersisted = onFailurePersisted
    }

    public static let none = ExchangeSecretarySQLiteHooks()
}
