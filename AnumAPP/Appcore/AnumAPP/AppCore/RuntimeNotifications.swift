import Foundation

// MARK: - Runtime user notices (central gate)

public enum RuntimeNoticeSeverity: String, Sendable, Hashable {
    case info
    case caution
    case critical
}

public enum RuntimeNoticeSource: String, Sendable, Hashable {
    case dispatchSourceWarning
    case dispatchSourceCritical
    case dispatchSourceNormal
    case iOSMemoryWarning
    case modelPrewarm
    case modelLoaded
    case modelLoadEstimate
    case modelAllocationFailed
    case diskSoftWarning
    case foregroundResume
}

public enum RuntimeNoticeMessageKind: String, Sendable, Hashable {
    case memorySlowdown
    case diskSpace
    case modelTooLarge
}

public enum RuntimeNoticeDecision: String, Sendable, Hashable {
    case show
    case suppress
    case logOnly
}

public struct RuntimeNoticeRequest: Sendable, Hashable {
    public let source: RuntimeNoticeSource
    public let messageKind: RuntimeNoticeMessageKind?
    public let customMessage: String?

    public init(
        source: RuntimeNoticeSource,
        messageKind: RuntimeNoticeMessageKind? = nil,
        customMessage: String? = nil
    ) {
        self.source = source
        self.messageKind = messageKind
        self.customMessage = customMessage
    }
}

public struct RuntimeNoticeEvaluation: Sendable, Hashable {
    public let decision: RuntimeNoticeDecision
    public let severity: RuntimeNoticeSeverity
    public let reason: String
    public let userMessage: String?
    public let messageKind: RuntimeNoticeMessageKind?
    public let source: RuntimeNoticeSource

    public init(
        decision: RuntimeNoticeDecision,
        severity: RuntimeNoticeSeverity,
        reason: String,
        userMessage: String?,
        messageKind: RuntimeNoticeMessageKind?,
        source: RuntimeNoticeSource
    ) {
        self.decision = decision
        self.severity = severity
        self.reason = reason
        self.userMessage = userMessage
        self.messageKind = messageKind
        self.source = source
    }
}

/// Single source of truth for user-facing memory/disk/runtime notices.
public struct RuntimeNoticePolicy: Sendable {
    public static let cautionDismissSuppressInterval: TimeInterval = 24 * 60 * 60
    public static let criticalThrottleInterval: TimeInterval = 10 * 60

    private static let dismissedCautionAtKey = "RuntimeNoticePolicy.dismissedCautionAt"

    private var shownCautionThisSession: Bool = false
    private var lastCriticalShownAt: Date?
    private let now: @Sendable () -> Date
    private let defaults: UserDefaults

    public init(
        now: @escaping @Sendable () -> Date = { Date() },
        defaults: UserDefaults = .standard
    ) {
        self.now = now
        self.defaults = defaults
    }

    public mutating func evaluate(_ request: RuntimeNoticeRequest) -> RuntimeNoticeEvaluation {
        let severity = Self.severity(for: request.source)
        let messageKind = resolvedMessageKind(request: request, severity: severity)

        switch severity {
        case .info:
            return RuntimeNoticeEvaluation(
                decision: .logOnly,
                severity: severity,
                reason: infoReason(for: request.source),
                userMessage: nil,
                messageKind: messageKind,
                source: request.source
            )

        case .caution:
            if shownCautionThisSession {
                return suppress(
                    request: request,
                    severity: severity,
                    messageKind: messageKind,
                    reason: "alreadyShownThisSession"
                )
            }
            if let dismissedAt = dismissedCautionAt,
               now().timeIntervalSince(dismissedAt) < Self.cautionDismissSuppressInterval {
                return suppress(
                    request: request,
                    severity: severity,
                    messageKind: messageKind,
                    reason: "dismissedWithin24h"
                )
            }
            let message = resolveMessage(request: request, messageKind: messageKind)
            return RuntimeNoticeEvaluation(
                decision: .show,
                severity: severity,
                reason: "firstCautionThisSession",
                userMessage: message,
                messageKind: messageKind,
                source: request.source
            )

        case .critical:
            guard Self.isCriticalEligible(request.source) else {
                return suppress(
                    request: request,
                    severity: severity,
                    messageKind: messageKind,
                    reason: "sourceNotCriticalEligible"
                )
            }
            if let lastShown = lastCriticalShownAt,
               now().timeIntervalSince(lastShown) < Self.criticalThrottleInterval {
                return suppress(
                    request: request,
                    severity: severity,
                    messageKind: messageKind,
                    reason: "criticalThrottled10m"
                )
            }
            let message = resolveMessage(request: request, messageKind: messageKind)
            return RuntimeNoticeEvaluation(
                decision: .show,
                severity: severity,
                reason: criticalShowReason(for: request.source),
                userMessage: message,
                messageKind: messageKind,
                source: request.source
            )
        }
    }

    public mutating func recordShown(_ evaluation: RuntimeNoticeEvaluation, at date: Date? = nil) {
        let stamp = date ?? now()
        switch evaluation.severity {
        case .caution:
            shownCautionThisSession = true
        case .critical:
            lastCriticalShownAt = stamp
        case .info:
            break
        }
    }

    public mutating func recordDismissed(severity: RuntimeNoticeSeverity, at date: Date? = nil) {
        guard severity == .caution else { return }
        let stamp = date ?? now()
        defaults.set(stamp.timeIntervalSince1970, forKey: Self.dismissedCautionAtKey)
    }

    /// Foreground/background resume must not reset session throttling.
    @discardableResult
    public mutating func noteForegroundResume() -> RuntimeNoticeEvaluation {
        evaluate(RuntimeNoticeRequest(source: .foregroundResume))
    }

    public static func log(_ evaluation: RuntimeNoticeEvaluation) {
        print(
            "[MemoryNotice] source=\(evaluation.source.rawValue) " +
            "severity=\(evaluation.severity.rawValue) " +
            "decision=\(evaluation.decision.rawValue) " +
            "reason=\(evaluation.reason)"
        )
    }

    public static func severity(for source: RuntimeNoticeSource) -> RuntimeNoticeSeverity {
        switch source {
        case .dispatchSourceWarning,
             .dispatchSourceNormal,
             .modelPrewarm,
             .modelLoaded,
             .modelLoadEstimate,
             .foregroundResume:
            return .info

        case .diskSoftWarning:
            return .caution

        case .iOSMemoryWarning,
             .dispatchSourceCritical,
             .modelAllocationFailed:
            return .critical
        }
    }

    public static func isCriticalEligible(_ source: RuntimeNoticeSource) -> Bool {
        switch source {
        case .iOSMemoryWarning, .dispatchSourceCritical, .modelAllocationFailed:
            return true
        default:
            return false
        }
    }

    public static let modelTooLargeCautionMessage =
        "This model may run slower on this device. If the app feels sluggish, close other apps or switch to a smaller model."

    public static let memoryPressureCriticalMessage =
        "Memory is low on this device. Close other apps if Unify feels slow or unresponsive."

    public static let modelAllocationFailedMessage =
        "Unify could not load the model because memory is low. Close other apps and try again, or switch to a smaller model."

    private func resolvedMessageKind(
        request: RuntimeNoticeRequest,
        severity: RuntimeNoticeSeverity
    ) -> RuntimeNoticeMessageKind? {
        if let kind = request.messageKind {
            return kind
        }
        switch request.source {
        case .diskSoftWarning:
            return .diskSpace
        case .modelAllocationFailed, .modelLoadEstimate:
            return .modelTooLarge
        case .iOSMemoryWarning, .dispatchSourceCritical:
            return .memorySlowdown
        default:
            if severity == .caution {
                return .modelTooLarge
            }
            if severity == .critical {
                return .memorySlowdown
            }
            return nil
        }
    }

    private func resolveMessage(
        request: RuntimeNoticeRequest,
        messageKind: RuntimeNoticeMessageKind?
    ) -> String? {
        if let custom = request.customMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        switch messageKind {
        case .diskSpace:
            return nil
        case .modelTooLarge:
            if request.source == .modelAllocationFailed {
                return Self.modelAllocationFailedMessage
            }
            return Self.modelTooLargeCautionMessage
        case .memorySlowdown:
            return Self.memoryPressureCriticalMessage
        case .none:
            return nil
        }
    }

    private var dismissedCautionAt: Date? {
        let interval = defaults.double(forKey: Self.dismissedCautionAtKey)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func suppress(
        request: RuntimeNoticeRequest,
        severity: RuntimeNoticeSeverity,
        messageKind: RuntimeNoticeMessageKind?,
        reason: String
    ) -> RuntimeNoticeEvaluation {
        RuntimeNoticeEvaluation(
            decision: .suppress,
            severity: severity,
            reason: reason,
            userMessage: nil,
            messageKind: messageKind,
            source: request.source
        )
    }

    private func infoReason(for source: RuntimeNoticeSource) -> String {
        switch source {
        case .modelPrewarm:
            return "modelPrewarmLogOnly"
        case .modelLoaded:
            return "modelLoadedLogOnly"
        case .modelLoadEstimate:
            return "modelLoadEstimateLogOnly"
        case .foregroundResume:
            return "foregroundResumeNoBanner"
        case .dispatchSourceNormal:
            return "dispatchNormalClearsFlagOnly"
        case .dispatchSourceWarning:
            return "dispatchWarningLogOnly"
        default:
            return "logOnly"
        }
    }

    private func criticalShowReason(for source: RuntimeNoticeSource) -> String {
        switch source {
        case .iOSMemoryWarning:
            return "actualSystemWarning"
        case .dispatchSourceCritical:
            return "dispatchCritical"
        case .modelAllocationFailed:
            return "modelAllocationFailed"
        default:
            return "criticalEvent"
        }
    }
}

// MARK: - Legacy aliases

public typealias MemoryPressureNoticeSeverity = RuntimeNoticeSeverity
public typealias MemoryPressureNoticeDecision = RuntimeNoticeDecision
public typealias MemoryPressureNotificationPolicy = RuntimeNoticePolicy

/// Cross-cutting runtime notification names.
enum RuntimeNotifications {
    nonisolated static var llamaRuntimeStateInvalidatedName: Notification.Name {
        Notification.Name("llamaRuntimeStateInvalidated")
    }

    nonisolated static func postLlamaRuntimeStateInvalidated() {
        NotificationCenter.default.post(
            name: llamaRuntimeStateInvalidatedName,
            object: nil
        )
    }
}
