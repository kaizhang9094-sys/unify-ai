import Foundation

/// Canonical delivery lifecycle for federation-backed exchange work.
///
/// This type exists so delivery truth is not scattered across:
/// - drafts
/// - thread state
/// - relay code
/// - ad-hoc UI flags
///
/// Important rule:
/// delivery state is about external coordination execution,
/// not the user's authored content.
public struct ExchangeDeliveryState: Codable, Sendable, Hashable {
    public var phase: Phase
    public var priority: Priority

    /// Human-legible reason or note explaining the current state.
    public var note: String?

    /// Whether any external effect may already have happened.
    /// This keeps cancellation and failure reporting honest.
    public var externalEffect: ExchangeFailure.ExternalEffect

    public var queuedAt: Date?
    public var firstAttemptAt: Date?
    public var lastAttemptAt: Date?
    public var sentAt: Date?
    public var acknowledgedAt: Date?
    public var cancelledAt: Date?
    public var failedAt: Date?
    public var deferredUntil: Date?

    public var attemptCount: Int
    public var lastErrorCode: String?
    public var lastExternalReference: String?
    public var relayRouteSummary: String?

    public init(
        phase: Phase = .queued,
        priority: Priority = .normal,
        note: String? = nil,
        externalEffect: ExchangeFailure.ExternalEffect = .none,
        queuedAt: Date? = nil,
        firstAttemptAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        sentAt: Date? = nil,
        acknowledgedAt: Date? = nil,
        cancelledAt: Date? = nil,
        failedAt: Date? = nil,
        deferredUntil: Date? = nil,
        attemptCount: Int = 0,
        lastErrorCode: String? = nil,
        lastExternalReference: String? = nil,
        relayRouteSummary: String? = nil
    ) {
        self.phase = phase
        self.priority = priority
        self.note = note?.exchangeNilIfBlank
        self.externalEffect = externalEffect
        self.queuedAt = queuedAt
        self.firstAttemptAt = firstAttemptAt
        self.lastAttemptAt = lastAttemptAt
        self.sentAt = sentAt
        self.acknowledgedAt = acknowledgedAt
        self.cancelledAt = cancelledAt
        self.failedAt = failedAt
        self.deferredUntil = deferredUntil
        self.attemptCount = max(0, attemptCount)
        self.lastErrorCode = lastErrorCode?.exchangeNilIfBlank
        self.lastExternalReference = lastExternalReference?.exchangeNilIfBlank
        self.relayRouteSummary = relayRouteSummary?.exchangeNilIfBlank
    }
}

public extension ExchangeDeliveryState {
    enum Phase: String, Codable, Sendable, CaseIterable, Hashable {
        /// Created and waiting for execution.
        case queued

        /// Waiting for a still-required approval or prerequisite.
        case blockedByPrerequisite

        /// Delayed due to runtime, thermal, network, or scheduling policy.
        case deferred

        /// In-flight send attempt.
        case sending

        /// Sent from local node, remote receipt not yet confirmed.
        case sent

        /// Explicitly acknowledged by remote side or relay.
        case acknowledged

        /// Failed before any confirmed completion.
        case failed

        /// Cancelled before any external effect occurred.
        case cancelledBeforeSend

        /// User attempted cancellation, but the send may already have left the device.
        case tooLateToCancel

        /// Received or built envelope could not be processed due to version or shape mismatch.
        case incompatible

        public var isTerminal: Bool {
            switch self {
            case .acknowledged, .failed, .cancelledBeforeSend, .tooLateToCancel, .incompatible:
                return true
            case .queued, .blockedByPrerequisite, .deferred, .sending, .sent:
                return false
            }
        }
    }

    enum Priority: String, Codable, Sendable, CaseIterable, Hashable {
        case background
        case normal
        case userInitiated
        case urgent

        public var schedulerRank: Int {
            switch self {
            case .urgent:
                return 4
            case .userInitiated:
                return 3
            case .normal:
                return 2
            case .background:
                return 1
            }
        }
    }
}

public extension ExchangeDeliveryState {
    var mayRetry: Bool {
        switch phase {
        case .failed, .deferred, .blockedByPrerequisite:
            return true
        case .queued, .sending, .sent, .acknowledged, .cancelledBeforeSend, .tooLateToCancel, .incompatible:
            return false
        }
    }

    var isExternallyMutable: Bool {
        switch phase {
        case .queued, .blockedByPrerequisite, .deferred:
            return false
        case .sending, .sent, .acknowledged, .tooLateToCancel:
            return true
        case .failed, .cancelledBeforeSend, .incompatible:
            return externalEffect.changedAnythingExternally
        }
    }

    var canCancelSafely: Bool {
        switch phase {
        case .queued, .blockedByPrerequisite, .deferred:
            return true
        case .sending, .sent, .acknowledged, .failed, .cancelledBeforeSend, .tooLateToCancel, .incompatible:
            return false
        }
    }

    var visibleStatusLine: String {
        switch phase {
        case .queued:
            return "Queued for delivery."
        case .blockedByPrerequisite:
            return "Blocked until a prerequisite is satisfied."
        case .deferred:
            if let deferredUntil {
                return "Deferred until \(deferredUntil.formatted())."
            }
            return "Deferred by delivery policy."
        case .sending:
            return "Sending now."
        case .sent:
            return "Sent from this device. Confirmation is still pending."
        case .acknowledged:
            return "Delivery acknowledged."
        case .failed:
            return "Delivery failed before confirmation."
        case .cancelledBeforeSend:
            return "Cancelled before sending."
        case .tooLateToCancel:
            return "Cancellation was requested too late to guarantee prevention."
        case .incompatible:
            return "Could not process due to incompatible federation data."
        }
    }

    func markingBlocked(
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeDeliveryState {
        var copy = self
        copy.phase = .blockedByPrerequisite
        copy.note = note?.exchangeNilIfBlank ?? copy.note
        copy.deferredUntil = nil
        copy.failedAt = nil
        copy.cancelledAt = nil
        if copy.queuedAt == nil { copy.queuedAt = date }
        return copy
    }

    func deferring(
        until deferredUntil: Date? = nil,
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeDeliveryState {
        var copy = self
        copy.phase = .deferred
        copy.note = note?.exchangeNilIfBlank ?? copy.note
        copy.deferredUntil = deferredUntil
        copy.failedAt = nil
        copy.cancelledAt = nil
        if copy.queuedAt == nil { copy.queuedAt = date }
        return copy
    }

    func beginningSend(
        routeSummary: String?,
        at date: Date = Date()
    ) -> ExchangeDeliveryState {
        var copy = self
        copy.phase = .sending
        copy.firstAttemptAt = copy.firstAttemptAt ?? date
        copy.lastAttemptAt = date
        copy.attemptCount += 1
        copy.relayRouteSummary = routeSummary?.exchangeNilIfBlank ?? copy.relayRouteSummary
        copy.deferredUntil = nil
        copy.failedAt = nil
        copy.cancelledAt = nil
        if copy.queuedAt == nil { copy.queuedAt = date }
        return copy
    }

    func markingSent(
        externalReference: String? = nil,
        externalEffect: ExchangeFailure.ExternalEffect = .attemptedButNotConfirmed,
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeDeliveryState {
        var copy = self
        copy.phase = .sent
        copy.sentAt = date
        copy.lastAttemptAt = date
        copy.externalEffect = externalEffect
        copy.note = note?.exchangeNilIfBlank ?? copy.note
        copy.lastExternalReference = externalReference?.exchangeNilIfBlank ?? copy.lastExternalReference
        copy.failedAt = nil
        copy.cancelledAt = nil
        return copy
    }

    func acknowledging(
        externalReference: String? = nil,
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeDeliveryState {
        var copy = self
        copy.phase = .acknowledged
        copy.acknowledgedAt = date
        copy.sentAt = copy.sentAt ?? date
        copy.lastExternalReference = externalReference?.exchangeNilIfBlank ?? copy.lastExternalReference
        copy.note = note?.exchangeNilIfBlank ?? copy.note
        copy.failedAt = nil
        copy.cancelledAt = nil

        if case .none = copy.externalEffect {
            copy.externalEffect = .changed(description: "The external recipient acknowledged the delivery.")
        }

        return copy
    }

    func failing(
        errorCode: String? = nil,
        note: String? = nil,
        externalEffect: ExchangeFailure.ExternalEffect = .none,
        at date: Date = Date()
    ) -> ExchangeDeliveryState {
        var copy = self
        copy.phase = .failed
        copy.failedAt = date
        copy.lastAttemptAt = date
        copy.lastErrorCode = errorCode?.exchangeNilIfBlank ?? copy.lastErrorCode
        copy.note = note?.exchangeNilIfBlank ?? copy.note
        copy.externalEffect = externalEffect
        return copy
    }

    func cancellingBeforeSend(
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeDeliveryState {
        var copy = self
        copy.phase = .cancelledBeforeSend
        copy.cancelledAt = date
        copy.note = note?.exchangeNilIfBlank ?? copy.note
        copy.externalEffect = .none
        return copy
    }

    func markingTooLateToCancel(
        note: String? = nil,
        externalEffect: ExchangeFailure.ExternalEffect = .attemptedButNotConfirmed,
        at date: Date = Date()
    ) -> ExchangeDeliveryState {
        var copy = self
        copy.phase = .tooLateToCancel
        copy.cancelledAt = date
        copy.note = note?.exchangeNilIfBlank ?? copy.note
        copy.externalEffect = externalEffect
        return copy
    }

    func markingIncompatible(
        errorCode: String? = nil,
        note: String? = nil,
        at date: Date = Date()
    ) -> ExchangeDeliveryState {
        var copy = self
        copy.phase = .incompatible
        copy.failedAt = date
        copy.lastErrorCode = errorCode?.exchangeNilIfBlank ?? copy.lastErrorCode
        copy.note = note?.exchangeNilIfBlank ?? copy.note
        return copy
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
