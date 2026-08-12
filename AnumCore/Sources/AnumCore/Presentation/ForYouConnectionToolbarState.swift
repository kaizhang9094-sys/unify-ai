import Foundation

/// Friend/contact relationship label for the For You Details sheet toolbar.
/// Intentionally excludes `linkedThreadID` — thread existence is not connection state.
public enum ForYouConnectionToolbarState: Equatable, Sendable {
    case connect
    case pending
    case connected
}

public enum ForYouConnectionToolbarProjection {
    public static func resolve(
        isTrusted: Bool,
        isPending: Bool
    ) -> ForYouConnectionToolbarState {
        if isTrusted { return .connected }
        if isPending { return .pending }
        return .connect
    }
}
