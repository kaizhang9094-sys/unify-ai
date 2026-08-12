import Foundation

/// Visibility markers for Exchange objects and events.
///
/// Keep visibility separate from workflow state and domain semantics.
/// A value may be user-visible, approval-gated, failure-shaped, and externally
/// confirmed at the same time, so this must be composable rather than a
/// single-choice enum.
public struct ExchangeVisibility: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Safe and intended to be shown directly in user-facing UI.
    public static let userVisible = ExchangeVisibility(rawValue: 1 << 0)

    /// Exists for internal orchestration, bookkeeping, or diagnostics.
    public static let internalOnly = ExchangeVisibility(rawValue: 1 << 1)

    /// Requires explicit approval or review before it should be surfaced as action.
    public static let approvalRequired = ExchangeVisibility(rawValue: 1 << 2)

    /// Represents a confirmed external action or externally meaningful state.
    public static let externallyConfirmed = ExchangeVisibility(rawValue: 1 << 3)

    /// Represents a user-legible failure explanation.
    public static let failureVisible = ExchangeVisibility(rawValue: 1 << 4)
}

public extension ExchangeVisibility {
    static let `default`: ExchangeVisibility = [.userVisible]

    var isVisibleToUserByDefault: Bool {
        contains(.userVisible) || contains(.approvalRequired) || contains(.failureVisible) || contains(.externallyConfirmed)
    }

    var isSensitive: Bool {
        contains(.internalOnly) || contains(.approvalRequired)
    }

    var isInternalOnly: Bool {
        self == [.internalOnly]
    }
}
