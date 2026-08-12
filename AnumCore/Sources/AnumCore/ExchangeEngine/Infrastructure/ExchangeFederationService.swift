import Foundation

public struct ExchangeFederationSendEligibility: Sendable, Hashable {
    public enum AccessMode: String, Sendable, Hashable {
        case unknown
        case direct
        case introPreferred
        case introRequired
        case closed
    }

    public enum PostureBlockReason: String, Sendable, Hashable {
        case notDiscoverable
        case notAcceptingInbound
        case accessClosed
        case introductionRequired
        case directContactNotAllowed
        case disclosureTooHigh
        case trustTooLow
        case categoryMismatch
        case mutualFitRequired
        case routeRequiredButMissing
    }

    public enum DisclosureCeiling: String, Sendable, Hashable {
        case unknown
        case minimal
        case balanced
        case open

        public init(_ level: ExchangeRelayEnvelope.Payload.DisclosureLevel) {
            switch level {
            case .minimal:
                self = .minimal
            case .balanced:
                self = .balanced
            case .open:
                self = .open
            }
        }

        public var asPayloadDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel? {
            switch self {
            case .unknown:
                return nil
            case .minimal:
                return .minimal
            case .balanced:
                return .balanced
            case .open:
                return .open
            }
        }
    }

    public var isEligible: Bool

    /// Human-readable explanation suitable for secretary/product surfaces.
    public var reason: String

    /// Whether this counterparty is discoverable in principle.
    public var isDiscoverable: Bool

    /// Whether this counterparty is routeable in principle.
    public var isRouteableInPrinciple: Bool

    /// Whether direct first contact is allowed in principle.
    public var allowsDirectContactInPrinciple: Bool

    /// Whether first contact should come via trusted introduction/path.
    public var requiresIntroductionInPrinciple: Bool

    /// Coarse public access mode if known.
    public var accessMode: AccessMode

    /// Recipient-side disclosure ceiling if known.
    public var disclosureCeiling: DisclosureCeiling

    /// Whether the current attempt respects disclosure rules.
    public var disclosureAllowed: Bool

    /// Whether sender-side approval is still required before queue/send.
    public var requiresApproval: Bool

    /// Whether sender trust appears below recipient floor.
    public var trustFloorMismatch: Bool

    /// Whether public posture appears to block this attempt.
    public var postureBlocked: Bool

    /// More specific posture-block reason when known.
    public var postureBlockReason: PostureBlockReason?

    /// Best resolved route if one exists.
    public var resolvedRoute: ExchangeRelayRoute?

    public init(
        isEligible: Bool,
        reason: String,
        isDiscoverable: Bool = true,
        isRouteableInPrinciple: Bool = true,
        allowsDirectContactInPrinciple: Bool = true,
        requiresIntroductionInPrinciple: Bool = false,
        accessMode: AccessMode = .unknown,
        disclosureCeiling: DisclosureCeiling = .unknown,
        disclosureAllowed: Bool = true,
        requiresApproval: Bool = true,
        trustFloorMismatch: Bool = false,
        postureBlocked: Bool = false,
        postureBlockReason: PostureBlockReason? = nil,
        resolvedRoute: ExchangeRelayRoute? = nil
    ) {
        self.isEligible = isEligible
        self.reason = reason
        self.isDiscoverable = isDiscoverable
        self.isRouteableInPrinciple = isRouteableInPrinciple
        self.allowsDirectContactInPrinciple = allowsDirectContactInPrinciple
        self.requiresIntroductionInPrinciple = requiresIntroductionInPrinciple
        self.accessMode = accessMode
        self.disclosureCeiling = disclosureCeiling
        self.disclosureAllowed = disclosureAllowed
        self.requiresApproval = requiresApproval
        self.trustFloorMismatch = trustFloorMismatch
        self.postureBlocked = postureBlocked
        self.postureBlockReason = postureBlockReason
        self.resolvedRoute = resolvedRoute
    }

    public static func fromCounterpartyDefaults(
        _ counterparty: ExchangeCounterparty,
        reason: String,
        isEligible: Bool,
        disclosureAllowed: Bool = true,
        requiresApproval: Bool = true,
        trustFloorMismatch: Bool = false,
        postureBlocked: Bool = false,
        postureBlockReason: PostureBlockReason? = nil,
        resolvedRoute: ExchangeRelayRoute? = nil
    ) -> ExchangeFederationSendEligibility {
        let publicProfile = counterparty.publicProfile

        let accessMode: AccessMode
        if let publicProfile {
            switch publicProfile.reachability.accessMode {
            case .direct:
                accessMode = .direct
            case .introPreferred:
                accessMode = .introPreferred
            case .introRequired:
                accessMode = .introRequired
            case .closed:
                accessMode = .closed
            }
        } else {
            accessMode = .unknown
        }

        let disclosureCeiling: DisclosureCeiling
        if let publicProfile {
            disclosureCeiling = DisclosureCeiling(
                publicProfile.reachability.disclosureCeiling.asPayloadDisclosureLevel
                ?? .balanced
            )
        } else {
            disclosureCeiling = .unknown
        }

        return ExchangeFederationSendEligibility(
            isEligible: isEligible,
            reason: reason,
            isDiscoverable: counterparty.isDiscoverable,
            isRouteableInPrinciple: counterparty.isRoutableInPrinciple,
            allowsDirectContactInPrinciple: counterparty.allowsDirectContactInPrinciple,
            requiresIntroductionInPrinciple: counterparty.requiresIntroductionInPrinciple,
            accessMode: accessMode,
            disclosureCeiling: disclosureCeiling,
            disclosureAllowed: disclosureAllowed,
            requiresApproval: requiresApproval,
            trustFloorMismatch: trustFloorMismatch,
            postureBlocked: postureBlocked,
            postureBlockReason: postureBlockReason,
            resolvedRoute: resolvedRoute
        )
    }
}

public struct ExchangeFederationQueueResult: Sendable, Hashable {
    public var outboxItem: ExchangeOutboxItem
    public var auditRecords: [ExchangeAuditRecord]

    public init(
        outboxItem: ExchangeOutboxItem,
        auditRecords: [ExchangeAuditRecord]
    ) {
        self.outboxItem = outboxItem
        self.auditRecords = auditRecords
    }
}

public struct ExchangeFederationCancellationResult: Sendable, Hashable {
    public var outboxItem: ExchangeOutboxItem
    public var auditRecord: ExchangeAuditRecord

    public init(
        outboxItem: ExchangeOutboxItem,
        auditRecord: ExchangeAuditRecord
    ) {
        self.outboxItem = outboxItem
        self.auditRecord = auditRecord
    }
}

public struct ExchangeFederationFlushResult: Sendable, Hashable {
    public var attempted: Int
    public var acknowledged: Int
    public var deferred: Int
    public var failed: Int
    public var untouched: Int
    /// Thread IDs whose outbound relay send completed and local thread+draft transitions were persisted.
    /// Consumed by `ExchangeFacade.flushOutbox` to run second-half projection after delivery confirmation.
    public var outboundRelayConfirmedThreadIDs: [UUID]

    public init(
        attempted: Int = 0,
        acknowledged: Int = 0,
        deferred: Int = 0,
        failed: Int = 0,
        untouched: Int = 0,
        outboundRelayConfirmedThreadIDs: [UUID] = []
    ) {
        self.attempted = max(0, attempted)
        self.acknowledged = max(0, acknowledged)
        self.deferred = max(0, deferred)
        self.failed = max(0, failed)
        self.untouched = max(0, untouched)
        self.outboundRelayConfirmedThreadIDs = outboundRelayConfirmedThreadIDs
    }
}

public struct ExchangeFederationReceiveResult: Sendable, Hashable {
    public var inboxItem: ExchangeInboxItem
    public var auditRecord: ExchangeAuditRecord?

    public init(
        inboxItem: ExchangeInboxItem,
        auditRecord: ExchangeAuditRecord?
    ) {
        self.inboxItem = inboxItem
        self.auditRecord = auditRecord
    }
}

public struct ExchangeFederationReconcileResult: Sendable, Hashable {
    public var reconciledCount: Int
    public var deferredCount: Int
    public var rejectedCount: Int
    /// Thread IDs that were updated or newly created during this reconcile pass.
    /// Used by the facade to trigger second-half re-evaluation for inbound threads.
    public var reconciledThreadIDs: [ExchangeThread.ID]
    /// Stable envelope IDs that were durably reconciled into local thread state.
    /// Used by sync to ACK only successfully reconciled inbound items.
    public var reconciledEnvelopeIDs: [String]
    /// Subset of reconciled thread IDs eligible for positive trust evidence updates.
    /// Unverified or suspicious inbound should not be included.
    public var trustEligibleThreadIDs: [ExchangeThread.ID]

    public init(
        reconciledCount: Int = 0,
        deferredCount: Int = 0,
        rejectedCount: Int = 0,
        reconciledThreadIDs: [ExchangeThread.ID] = [],
        reconciledEnvelopeIDs: [String] = [],
        trustEligibleThreadIDs: [ExchangeThread.ID] = []
    ) {
        self.reconciledCount = max(0, reconciledCount)
        self.deferredCount = max(0, deferredCount)
        self.rejectedCount = max(0, rejectedCount)
        self.reconciledThreadIDs = reconciledThreadIDs
        self.reconciledEnvelopeIDs = reconciledEnvelopeIDs
        self.trustEligibleThreadIDs = trustEligibleThreadIDs
    }
}

/// Top-level federation boundary for Exchange.
///
/// This boundary should be legible in product terms, not just transport terms.
/// It should answer:
/// - is this counterparty reachable?
/// - is direct contact allowed?
/// - does this require introduction?
/// - is disclosure level acceptable?
/// - is sender approval still required?
public protocol ExchangeFederationService: Sendable {
    func evaluateSendEligibility(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        draft: ExchangeMessageDraft
    ) async throws -> ExchangeFederationSendEligibility

    func queueApprovedOutbound(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        draft: ExchangeMessageDraft,
        approval: ExchangeApproval,
        disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        priority: ExchangeDeliveryState.Priority,
        now: Date
    ) async throws -> ExchangeFederationQueueResult

    func cancelOutbound(
        outboxItemID: ExchangeOutboxItem.ID,
        reason: String?,
        now: Date
    ) async throws -> ExchangeFederationCancellationResult

    func flushOutbox(now: Date) async throws -> ExchangeFederationFlushResult

    func receiveEnvelope(
        _ envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?,
        receivedAt: Date
    ) async throws -> ExchangeFederationReceiveResult

    func reconcileInbox(now: Date) async throws -> ExchangeFederationReconcileResult

    func recentAudit(
        threadID: ExchangeThread.ID?,
        limit: Int
    ) async throws -> [ExchangeAuditRecord]
}

public enum ExchangeFederationError: Error, Sendable, Hashable {
    case noResolvedRoute(counterpartyID: ExchangeCounterparty.ID)
    case approvalRequired
    case disclosureNotAllowed(reason: String)
    case postureBlocked(reason: String)
    case trustFloorMismatch(required: ExchangeCounterparty.TrustSnapshot.Level?, actual: ExchangeCounterparty.TrustSnapshot.Level)
    case introductionRequired(counterpartyID: ExchangeCounterparty.ID)
    case queueNotFound(ExchangeOutboxItem.ID)
    case incompatibleEnvelope(reason: String)
    case runtimeBlocked(reason: String)
    case transportFailed(reason: String)
    case e2eeSendBlocked(internalReason: String)
}

extension ExchangeFederationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noResolvedRoute(let counterpartyID):
            return "No resolved route for counterparty \(counterpartyID)."
        case .approvalRequired:
            return "Approval is still required."
        case .disclosureNotAllowed(let reason):
            return reason
        case .postureBlocked(let reason):
            return reason
        case .trustFloorMismatch(let required, let actual):
            if let required {
                return "Trust floor mismatch. Required \(required.rawValue), actual \(actual.rawValue)."
            }
            return "Trust floor mismatch. Actual \(actual.rawValue)."
        case .introductionRequired(let counterpartyID):
            return "Introduction is required before contacting counterparty \(counterpartyID)."
        case .queueNotFound:
            return "Outbox item was not found."
        case .incompatibleEnvelope(let reason):
            return reason
        case .runtimeBlocked(let reason):
            return reason
        case .transportFailed(let reason):
            return reason
        case .e2eeSendBlocked:
            return ExchangePrivateE2EESendBlockedError.userFacingMessage
        }
    }
}

private extension ExchangePublicNodeProfile.ReachabilityPolicy.DisclosureCeiling {
    var asPayloadDisclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel? {
        switch self {
        case .minimal:
            return .minimal
        case .balanced:
            return .balanced
        case .open:
            return .open
        }
    }
}
