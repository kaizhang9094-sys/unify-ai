import Foundation

/// Push-aware foreground polling intervals for Secretary / Exchange surfaces.
/// Server remains relay-only; this policy only throttles client-side inbox pull cadence.
public struct ExchangeForegroundSyncPolicy: Sendable, Hashable {
    public enum RouteKind: String, Sendable, Hashable {
        /// Open DM or exchange thread detail — keep responsive.
        case activeConversation
        /// Inbound list / attention queue.
        case inboundList
        /// Dashboard, threads list, trust, profile, etc.
        case passiveWorkspace
    }

    /// Skip a passive poll tick when a recent push-triggered sync succeeded within this window.
    public var pushSyncGraceInterval: TimeInterval

    /// Skip a poll tick when any sync completed recently (avoids duplicate pulls after success).
    public var recentSyncGraceInterval: TimeInterval

    /// Skip automatic foreground recovery sync when a pass completed recently.
    public var automaticForegroundSyncGraceInterval: TimeInterval

    public init(
        pushSyncGraceInterval: TimeInterval = 90,
        recentSyncGraceInterval: TimeInterval = 30,
        automaticForegroundSyncGraceInterval: TimeInterval = 45
    ) {
        self.pushSyncGraceInterval = max(30, pushSyncGraceInterval)
        self.recentSyncGraceInterval = max(15, recentSyncGraceInterval)
        self.automaticForegroundSyncGraceInterval = max(
            self.recentSyncGraceInterval,
            automaticForegroundSyncGraceInterval
        )
    }

    public static let `default` = ExchangeForegroundSyncPolicy()

    public func routeKind(routeLabel: String) -> RouteKind {
        let label = routeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if label == "directMessage" || label.hasPrefix("thread(") {
            return .activeConversation
        }
        if label == "inbound" {
            return .inboundList
        }
        return .passiveWorkspace
    }

    public func recentPushSyncSucceeded(
        lastAt: Date?,
        succeeded: Bool,
        pushDeliveryEffective: Bool,
        now: Date
    ) -> Bool {
        guard pushDeliveryEffective, succeeded, let lastAt else { return false }
        return now.timeIntervalSince(lastAt) <= pushSyncGraceInterval
    }

    public func pollIntervalSeconds(
        routeKind: RouteKind,
        pushDeliveryEffective: Bool,
        recentPushSyncSucceeded: Bool
    ) -> Int {
        let pushBacked = pushDeliveryEffective && recentPushSyncSucceeded
        switch routeKind {
        case .activeConversation:
            return pushBacked ? 22 : 18
        case .inboundList:
            return pushBacked ? 120 : 90
        case .passiveWorkspace:
            return pushBacked ? 180 : 120
        }
    }

    public func shouldSkipPollDueToRecentSync(
        lastCompletedAt: Date?,
        now: Date
    ) -> Bool {
        guard let lastCompletedAt else { return false }
        return now.timeIntervalSince(lastCompletedAt) <= recentSyncGraceInterval
    }

    public func shouldSkipAutomaticForegroundSync(
        lastCompletedAt: Date?,
        now: Date
    ) -> Bool {
        guard let lastCompletedAt else { return false }
        return now.timeIntervalSince(lastCompletedAt) <= automaticForegroundSyncGraceInterval
    }

    public func shouldSkipPollDueToRecentPushSync(
        routeKind: RouteKind,
        lastPushSyncAt: Date?,
        lastPushSyncSucceeded: Bool,
        pushDeliveryEffective: Bool,
        now: Date
    ) -> Bool {
        guard routeKind != .activeConversation else { return false }
        return recentPushSyncSucceeded(
            lastAt: lastPushSyncAt,
            succeeded: lastPushSyncSucceeded,
            pushDeliveryEffective: pushDeliveryEffective,
            now: now
        )
    }

    public func jitterFraction(for routeKind: RouteKind) -> Double {
        switch routeKind {
        case .activeConversation:
            return 0.15
        case .inboundList:
            return 0.20
        case .passiveWorkspace:
            return 0.25
        }
    }

    public func pollIntervalBounds(
        routeKind: RouteKind,
        pushBacked: Bool
    ) -> (min: Int, max: Int) {
        switch routeKind {
        case .activeConversation:
            return pushBacked ? (18, 28) : (15, 24)
        case .inboundList:
            return pushBacked ? (95, 150) : (75, 120)
        case .passiveWorkspace:
            return pushBacked ? (140, 240) : (100, 180)
        }
    }

    public func jitteredPollIntervalSeconds(
        routeKind: RouteKind,
        pushDeliveryEffective: Bool,
        recentPushSyncSucceeded: Bool,
        stableSeed: UInt64
    ) -> Int {
        let pushBacked = pushDeliveryEffective && recentPushSyncSucceeded
        let base = pollIntervalSeconds(
            routeKind: routeKind,
            pushDeliveryEffective: pushDeliveryEffective,
            recentPushSyncSucceeded: recentPushSyncSucceeded
        )
        let fraction = jitterFraction(for: routeKind)
        let spread = max(1, Int((Double(base) * fraction).rounded()))
        let offset = Int(stableSeed % UInt64(spread * 2 + 1)) - spread
        let bounds = pollIntervalBounds(routeKind: routeKind, pushBacked: pushBacked)
        return min(bounds.max, max(bounds.min, base + offset))
    }

    public func jitteredInitialDelaySeconds(
        stableSeed: UInt64,
        baseSeconds: Int = 2
    ) -> Int {
        let clampedBase = max(1, baseSeconds)
        let spread = max(1, Int((Double(clampedBase) * 0.25).rounded()))
        let offset = Int(stableSeed % UInt64(spread * 2 + 1)) - spread
        return max(1, clampedBase + offset)
    }

    public static func stableSeed(from nodeID: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in nodeID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
