import Foundation

public struct ExchangeSyncPolicy: Sendable, Hashable {
    public var maxInboundBatchSize: Int
    public var minSecondsBetweenLaunchRuns: TimeInterval
    public var minSecondsBetweenActiveRuns: TimeInterval
    public var minSecondsBetweenManualRuns: TimeInterval
    public var allowsSyncWhileGenerating: Bool
    public var blocksWhenThermalCritical: Bool
    public var defersWhenLowPowerModeEnabled: Bool
    public var baseBackoffSeconds: TimeInterval
    public var maxBackoffSeconds: TimeInterval

    public init(
        maxInboundBatchSize: Int = 100,
        minSecondsBetweenLaunchRuns: TimeInterval = 8,
        minSecondsBetweenActiveRuns: TimeInterval = 12,
        minSecondsBetweenManualRuns: TimeInterval = 0,
        allowsSyncWhileGenerating: Bool = false,
        blocksWhenThermalCritical: Bool = true,
        defersWhenLowPowerModeEnabled: Bool = false,
        baseBackoffSeconds: TimeInterval = 15,
        maxBackoffSeconds: TimeInterval = 300
    ) {
        self.maxInboundBatchSize = max(1, maxInboundBatchSize)
        self.minSecondsBetweenLaunchRuns = max(0, minSecondsBetweenLaunchRuns)
        self.minSecondsBetweenActiveRuns = max(0, minSecondsBetweenActiveRuns)
        self.minSecondsBetweenManualRuns = max(0, minSecondsBetweenManualRuns)
        self.allowsSyncWhileGenerating = allowsSyncWhileGenerating
        self.blocksWhenThermalCritical = blocksWhenThermalCritical
        self.defersWhenLowPowerModeEnabled = defersWhenLowPowerModeEnabled
        self.baseBackoffSeconds = max(1, baseBackoffSeconds)
        self.maxBackoffSeconds = max(self.baseBackoffSeconds, maxBackoffSeconds)
    }

    public static let `default` = ExchangeSyncPolicy()

    public func minimumInterval(for trigger: ExchangeSyncEngine.Trigger) -> TimeInterval {
        switch trigger {
        case .appLaunch:
            return minSecondsBetweenLaunchRuns
        case .appBecameActive:
            return minSecondsBetweenActiveRuns
        case .manualRefresh:
            return minSecondsBetweenManualRuns
        case .afterOutboundQueued:
            return 2
        case .afterApprovalGranted:
            return 1
        case .silentPush:
            return 0
        case .foregroundInboxPoll:
            return 0
        }
    }

    public func backoffInterval(for failureCount: Int) -> TimeInterval {
        let clamped = max(1, failureCount)
        let interval = baseBackoffSeconds * pow(2.0, Double(clamped - 1))
        return min(interval, maxBackoffSeconds)
    }
}
