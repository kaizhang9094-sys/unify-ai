import Foundation

public struct ExchangeTransportPolicy: Codable, Sendable, Hashable {
    public var maxConcurrentSends: Int
    public var maxAttempts: Int

    public var allowUrgentSendDuringGeneration: Bool
    public var allowUrgentSendDuringHighThermal: Bool
    public var allowBackgroundSyncDuringGeneration: Bool
    public var allowBackgroundSyncDuringHighThermal: Bool

    public var defaultRetryBackoffSeconds: Int
    public var urgentRetryBackoffSeconds: Int

    public init(
        maxConcurrentSends: Int = 1,
        maxAttempts: Int = 5,
        allowUrgentSendDuringGeneration: Bool = false,
        allowUrgentSendDuringHighThermal: Bool = true,
        allowBackgroundSyncDuringGeneration: Bool = false,
        allowBackgroundSyncDuringHighThermal: Bool = false,
        defaultRetryBackoffSeconds: Int = 45,
        urgentRetryBackoffSeconds: Int = 10
    ) {
        self.maxConcurrentSends = max(1, maxConcurrentSends)
        self.maxAttempts = max(1, maxAttempts)
        self.allowUrgentSendDuringGeneration = allowUrgentSendDuringGeneration
        self.allowUrgentSendDuringHighThermal = allowUrgentSendDuringHighThermal
        self.allowBackgroundSyncDuringGeneration = allowBackgroundSyncDuringGeneration
        self.allowBackgroundSyncDuringHighThermal = allowBackgroundSyncDuringHighThermal
        self.defaultRetryBackoffSeconds = max(1, defaultRetryBackoffSeconds)
        self.urgentRetryBackoffSeconds = max(1, urgentRetryBackoffSeconds)
    }
}

public extension ExchangeTransportPolicy {
    enum WorkClass: String, Codable, Sendable, CaseIterable, Hashable {
        case approvedUserSend
        case userRefresh
        case inboundAcknowledge
        case inboundReceive
        case backgroundSync
        case trustRefresh
        case maintenance

        public var precedence: Int {
            switch self {
            case .approvedUserSend: return 7
            case .userRefresh: return 6
            case .inboundAcknowledge: return 5
            case .inboundReceive: return 4
            case .backgroundSync: return 3
            case .trustRefresh: return 2
            case .maintenance: return 1
            }
        }
    }

    enum Decision: String, Codable, Sendable, CaseIterable, Hashable {
        case runNow
        case deferred
        case block
    }

    struct Evaluation: Codable, Sendable, Hashable {
        public var decision: Decision
        public var reason: String
        public var retryAfterSeconds: Int?

        public init(
            decision: Decision,
            reason: String,
            retryAfterSeconds: Int? = nil
        ) {
            self.decision = decision
            self.reason = reason
            self.retryAfterSeconds = retryAfterSeconds
        }
    }
}

public extension ExchangeTransportPolicy {
    struct RuntimeSnapshot: Sendable, Hashable {
        public var allowsBackgroundWork: Bool
        public var isLowPowerModeEnabled: Bool
        public var isGenerating: Bool
        public var isThermalHigh: Bool
        public var isThermalCritical: Bool

        public init(
            allowsBackgroundWork: Bool,
            isLowPowerModeEnabled: Bool,
            isGenerating: Bool,
            isThermalHigh: Bool,
            isThermalCritical: Bool
        ) {
            self.allowsBackgroundWork = allowsBackgroundWork
            self.isLowPowerModeEnabled = isLowPowerModeEnabled
            self.isGenerating = isGenerating
            self.isThermalHigh = isThermalHigh
            self.isThermalCritical = isThermalCritical
        }
    }

    func evaluate(
        workClass: WorkClass,
        deliveryPriority: ExchangeDeliveryState.Priority,
        runtime: RuntimeSnapshot,
        attemptCount: Int
    ) -> Evaluation {
        guard attemptCount < maxAttempts else {
            return .init(
                decision: .block,
                reason: "Maximum delivery attempts reached."
            )
        }

        if !runtime.allowsBackgroundWork,
           workClass.isBackgroundLike {
            return .init(
                decision: .deferred,
                reason: "Background work is currently disabled.",
                retryAfterSeconds: retryDelay(for: deliveryPriority)
            )
        }

        if runtime.isLowPowerModeEnabled,
           workClass.isBackgroundLike {
            return .init(
                decision: .deferred,
                reason: "Background work is deferred while Low Power Mode is enabled.",
                retryAfterSeconds: retryDelay(for: deliveryPriority)
            )
        }

        if runtime.isThermalCritical {
            switch workClass {
            case .approvedUserSend:
                if deliveryPriority == .urgent && allowUrgentSendDuringHighThermal {
                    return .init(
                        decision: .runNow,
                        reason: "Urgent approved send allowed under critical thermal pressure."
                    )
                }
                return .init(
                    decision: .deferred,
                    reason: "Device is under critical thermal pressure.",
                    retryAfterSeconds: retryDelay(for: deliveryPriority)
                )

            case .userRefresh, .inboundAcknowledge, .inboundReceive, .backgroundSync, .trustRefresh, .maintenance:
                return .init(
                    decision: .deferred,
                    reason: "Device is under critical thermal pressure.",
                    retryAfterSeconds: retryDelay(for: deliveryPriority)
                )
            }
        }

        if runtime.isGenerating {
            switch workClass {
            case .approvedUserSend:
                if deliveryPriority == .urgent && allowUrgentSendDuringGeneration {
                    return .init(
                        decision: .runNow,
                        reason: "Urgent approved send allowed during foreground generation."
                    )
                }
                return .init(
                    decision: .deferred,
                    reason: "Foreground model generation is active.",
                    retryAfterSeconds: retryDelay(for: deliveryPriority)
                )

            case .userRefresh:
                return .init(
                    decision: .deferred,
                    reason: "Foreground model generation is active.",
                    retryAfterSeconds: retryDelay(for: deliveryPriority)
                )

            case .inboundAcknowledge:
                return .init(
                    decision: .deferred,
                    reason: "Inbound federation work is deferred while generation is active.",
                    retryAfterSeconds: retryDelay(for: deliveryPriority)
                )

            case .inboundReceive:
                // Inbox reconciliation is local-first; deferring it during generation left trusted DMs invisible
                // until a later app restart when generation had stopped.
                return .init(
                    decision: .runNow,
                    reason: "Inbound inbox reconciliation permitted during generation (local work; DM visibility)."
                )

            case .backgroundSync, .trustRefresh, .maintenance:
                if allowBackgroundSyncDuringGeneration {
                    return .init(
                        decision: .runNow,
                        reason: "Background work allowed during generation by policy."
                    )
                }
                return .init(
                    decision: .deferred,
                    reason: "Background work is deferred while generation is active.",
                    retryAfterSeconds: retryDelay(for: deliveryPriority)
                )
            }
        }

        if runtime.isThermalHigh {
            switch workClass {
            case .approvedUserSend:
                if deliveryPriority == .urgent && allowUrgentSendDuringHighThermal {
                    return .init(
                        decision: .runNow,
                        reason: "Urgent send allowed under high thermal state."
                    )
                }
                return .init(
                    decision: .runNow,
                    reason: "Approved send allowed under high thermal state."
                )

            case .userRefresh, .inboundAcknowledge, .inboundReceive:
                return .init(
                    decision: .runNow,
                    reason: "Foreground exchange work allowed under high thermal state."
                )

            case .backgroundSync, .trustRefresh, .maintenance:
                if allowBackgroundSyncDuringHighThermal {
                    return .init(
                        decision: .runNow,
                        reason: "Background work allowed under high thermal state by policy."
                    )
                }
                return .init(
                    decision: .deferred,
                    reason: "Background work deferred under high thermal state.",
                    retryAfterSeconds: retryDelay(for: deliveryPriority)
                )
            }
        }

        return .init(
            decision: .runNow,
            reason: "Transport policy permits execution."
        )
    }

    func retryDelay(for priority: ExchangeDeliveryState.Priority) -> Int {
        switch priority {
        case .urgent, .userInitiated:
            return urgentRetryBackoffSeconds
        case .normal, .background:
            return defaultRetryBackoffSeconds
        }
    }
}

private extension ExchangeTransportPolicy.WorkClass {
    var isBackgroundLike: Bool {
        switch self {
        case .backgroundSync, .trustRefresh, .maintenance:
            return true
        case .approvedUserSend, .userRefresh, .inboundAcknowledge, .inboundReceive:
            return false
        }
    }
}
