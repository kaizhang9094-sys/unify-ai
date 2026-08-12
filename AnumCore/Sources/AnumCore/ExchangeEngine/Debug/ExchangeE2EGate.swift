import Foundation

#if DEBUG

/// Identifies how an Exchange E2E / smoke run was requested.
public enum ExchangeE2ETrigger: Sendable, Equatable {
    case manualButton(source: String)
    case appLaunch
    case viewAppear
    case foregroundResume
    case refresh
    case unknown

    public var logLabel: String {
        switch self {
        case .manualButton(let source):
            return "manualButton source=\(source)"
        case .appLaunch:
            return "appLaunch"
        case .viewAppear:
            return "viewAppear"
        case .foregroundResume:
            return "foregroundResume"
        case .refresh:
            return "refresh"
        case .unknown:
            return "unknown"
        }
    }
}

/// Controls how much of the Exchange path an E2E run may exercise.
public enum ExchangeE2EMode: String, Sendable, Hashable, CaseIterable, Codable {
    case retrievalOnly
    case discoveryOnly
    case discoveryAndSecondHalf

    public var includesDiscoveryAutoSecondHalf: Bool {
        self == .discoveryAndSecondHalf
    }

    public var includesManualSecondHalfCapture: Bool {
        self == .discoveryAndSecondHalf
    }
}

public enum ExchangeE2EGate {
    public static func shouldRun(trigger: ExchangeE2ETrigger) -> Bool {
        if case .manualButton = trigger { return true }
        return false
    }

    public static func manualSource(from trigger: ExchangeE2ETrigger) -> String? {
        guard case .manualButton(let source) = trigger else { return nil }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func logBlocked(trigger: ExchangeE2ETrigger) {
        print("[E2E][Gate] blocked trigger=\(trigger.logLabel) reason=manual_button_required")
    }

    public static func logAllowed(source: String) {
        print("[E2E][Gate] allowed trigger=manualButton source=\(source)")
    }

    public static func logRunStart(source: String, mode: ExchangeE2EMode) {
        print("[E2E][Run] start source=\(source) mode=\(mode.rawValue)")
    }

    public static func logRunDone(source: String, result: String) {
        print("[E2E][Run] done source=\(source) result=\(result)")
    }

    /// Logs blocked when legacy launch env flags are still set; does not start any E2E work.
    public static func logBlockedLaunchAutomationIfConfigured() {
        if ExchangeRetrievalE2EGate.isLaunchAutomationEnabled {
            logBlocked(trigger: .appLaunch)
        }
        if ExchangeAppSearchSmokeGate.isLaunchAutomationEnabled {
            logBlocked(trigger: .appLaunch)
        }
    }
}

/// Task-local scope for active DEBUG E2E runs so production discovery can stay unchanged outside E2E.
public enum ExchangeE2EActiveRun {
    @TaskLocal private static var activeMode: ExchangeE2EMode?

    public static var currentMode: ExchangeE2EMode? { activeMode }

    public static var shouldSuppressDiscoveryAutoSecondHalf: Bool {
        guard let mode = activeMode else { return false }
        return !mode.includesDiscoveryAutoSecondHalf
    }

    public static func withMode<T>(
        _ mode: ExchangeE2EMode,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $activeMode.withValue(mode, operation: operation)
    }
}

#endif
