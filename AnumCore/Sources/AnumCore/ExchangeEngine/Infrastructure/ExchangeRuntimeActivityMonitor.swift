import Foundation

/// Runtime activity boundary between:
/// - foreground model generation
/// - federation transport work
/// - background sync/maintenance
///
/// The interface is intentionally small.
/// Higher layers can update it from model lifecycle, app lifecycle,
/// battery state, and thermal state without coupling federation
/// to chat or UI internals.

public struct ExchangeRuntimeActivitySnapshot: Sendable, Hashable, Codable {
    public var isGenerating: Bool
    public var isThermalHigh: Bool
    public var isThermalCritical: Bool
    public var isLowPowerModeEnabled: Bool
    public var allowsBackgroundWork: Bool
    public var activeForegroundTask: ExchangeRuntimeForegroundTask?

    public init(
        isGenerating: Bool = false,
        isThermalHigh: Bool = false,
        isThermalCritical: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        allowsBackgroundWork: Bool = true,
        activeForegroundTask: ExchangeRuntimeForegroundTask? = nil
    ) {
        self.isGenerating = isGenerating
        self.isThermalHigh = isThermalHigh || isThermalCritical
        self.isThermalCritical = isThermalCritical
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.allowsBackgroundWork = allowsBackgroundWork
        self.activeForegroundTask = activeForegroundTask
    }

    public var isForegroundBusy: Bool {
        isGenerating || activeForegroundTask != nil
    }

    public var shouldAvoidBackgroundWork: Bool {
        !allowsBackgroundWork || isGenerating || isThermalCritical
    }
}

public enum ExchangeRuntimeForegroundTask: String, Sendable, Hashable, Codable {
    case modelGeneration
    case userSend
    case uiRefresh
    case unknown
}

public protocol ExchangeRuntimeActivityMonitor: Sendable {
    func snapshot() async -> ExchangeRuntimeActivitySnapshot
}

/// Minimal mutable implementation for app wiring.
///
/// Keep this isolated from chat/exchange internals.
/// Higher layers can update it based on model lifecycle and device state.
public actor ExchangeRuntimeActivityState: ExchangeRuntimeActivityMonitor {
    private var current: ExchangeRuntimeActivitySnapshot

    public init(initial: ExchangeRuntimeActivitySnapshot = .init()) {
        self.current = initial
    }

    public func snapshot() async -> ExchangeRuntimeActivitySnapshot {
        current
    }

    public func setGenerating(
        _ value: Bool,
        task: ExchangeRuntimeForegroundTask? = .modelGeneration
    ) {
        current.isGenerating = value
        current.activeForegroundTask = value ? (task ?? .modelGeneration) : nil
    }

    public func setForegroundTask(_ task: ExchangeRuntimeForegroundTask?) {
        current.activeForegroundTask = task
    }

    public func clearForegroundTask() {
        current.activeForegroundTask = nil
    }

    public func setThermalState(
        high: Bool,
        critical: Bool
    ) {
        current.isThermalCritical = critical
        current.isThermalHigh = high || critical
    }

    public func setLowPowerModeEnabled(_ value: Bool) {
        current.isLowPowerModeEnabled = value
    }

    public func setAllowsBackgroundWork(_ value: Bool) {
        current.allowsBackgroundWork = value
    }

    public func replaceSnapshot(_ snapshot: ExchangeRuntimeActivitySnapshot) {
        current = snapshot
    }

    public func reset() {
        current = .init()
    }
}
