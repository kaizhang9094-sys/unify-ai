import Foundation

fileprivate actor ExchangeOutboxEnvelopeSendDeduper {
    static let shared = ExchangeOutboxEnvelopeSendDeduper()
    private var inFlightEnvelopeIDs = Set<String>()

    func tryAcquire(_ envelopeID: String) -> Bool {
        let trimmed = envelopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if inFlightEnvelopeIDs.contains(trimmed) {
            return false
        }
        inFlightEnvelopeIDs.insert(trimmed)
        return true
    }

    func release(_ envelopeID: String) {
        let trimmed = envelopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inFlightEnvelopeIDs.remove(trimmed)
    }
}

#if DEBUG
@inline(__always)
private func exchFedServiceLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeDefaultFederationService] \(message())")
}
@inline(__always)
private func refreshTraceFedLog(_ message: @autoclosure () -> String) {
    Swift.print("[RefreshTrace] \(message())")
}
#else
@inline(__always)
private func exchFedServiceLog(_ message: @autoclosure () -> String) {}
@inline(__always)
private func refreshTraceFedLog(_ message: @autoclosure () -> String) {}
#endif

public struct ExchangeDefaultFederationService: ExchangeFederationService, Sendable {
    private let store: any ExchangeStore
    private let policyEngine: ExchangePolicyEngine
    private let envelopeService: ExchangeEnvelopeService
    private let identityService: any ExchangeIdentityService
    private let relayClient: any ExchangeRelayClient
    private let runtimeMonitor: any ExchangeRuntimeActivityMonitor
    private let transportPolicy: ExchangeTransportPolicy
    private let continuationCoordinator: ExchangeThreadContinuationCoordinator
    private let threadEngine: ExchangeThreadEngine
    private let federationBaseURL: URL
    private let messageOpener: ExchangeMessageOpener

    public init(
        store: any ExchangeStore,
        policyEngine: ExchangePolicyEngine,
        envelopeService: ExchangeEnvelopeService,
        identityService: any ExchangeIdentityService,
        relayClient: any ExchangeRelayClient,
        runtimeMonitor: any ExchangeRuntimeActivityMonitor,
        transportPolicy: ExchangeTransportPolicy = .init(),
        continuationCoordinator: ExchangeThreadContinuationCoordinator = .init(),
        threadEngine: ExchangeThreadEngine = .init(),
        federationBaseURL: URL,
        messageOpener: ExchangeMessageOpener = ExchangeMessageOpener()
    ) {
        self.store = store
        self.policyEngine = policyEngine
        self.envelopeService = envelopeService
        self.identityService = identityService
        self.relayClient = relayClient
        self.runtimeMonitor = runtimeMonitor
        self.transportPolicy = transportPolicy
        self.continuationCoordinator = continuationCoordinator
        self.threadEngine = threadEngine
        self.federationBaseURL = federationBaseURL
        self.messageOpener = messageOpener
    }

    // MARK: - Eligibility / queueing

    public func evaluateSendEligibility(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        draft: ExchangeMessageDraft
    ) async throws -> ExchangeFederationSendEligibility {
        let hydratedProfile = try await resolvedExecutionPublicProfile(
            thread: thread,
            counterparty: counterparty
        )

        let targetExecutionID = targetExecutionID(
            thread: thread,
            counterparty: counterparty,
            publicProfile: hydratedProfile
        )
        #if DEBUG
        exchFedServiceLog(
            "queue/send target resolution | targetExecutionID=\(targetExecutionID) | selectedCounterpartyID=\(thread.selectedCounterpartyID ?? "nil") | selectedPublicProfileID=\(thread.selectedPublicProfileID ?? "nil") | selectedOfferID=\(thread.selectedOfferID ?? "nil") | profileNodeID=\(hydratedProfile?.nodeID ?? "nil")"
        )
        #endif

        let stableEnvelopeID = stableEnvelopeKey(
            threadID: thread.id,
            draftID: draft.id,
            targetExecutionID: targetExecutionID
        )
        let corr = outboundConversationCorrelation(
            thread: thread,
            idempotencyKey: stableEnvelopeID
        )
        #if DEBUG
        exchFedServiceLog(
            "[OutboundConversationCorrelation] source=\(corr.source) localThreadID=\(thread.id.uuidString) envelopeID=\(stableEnvelopeID) parentEnvelopeID=\(corr.parentEnvelopeID ?? "nil") conversationID=\(corr.conversationID) rootEnvelopeID=\(corr.rootEnvelopeID)"
        )
        #endif

        let existingOutbox = try await store.fetchOutboxItemByEnvelopeID(stableEnvelopeID)
        let deliveryState = existingOutbox?.deliveryState

        let policy = policyEngine.evaluate(
            thread: thread,
            selectedCounterparty: counterparty,
            publicProfile: hydratedProfile,
            draft: draft,
            deliveryState: deliveryState
        )

        guard policy.federationExecution.allowed else {
            return ExchangeFederationSendEligibility.fromCounterpartyDefaults(
                counterparty,
                reason: policy.federationExecution.rationale,
                isEligible: false,
                disclosureAllowed: true,
                requiresApproval: policy.approval.required,
                trustFloorMismatch: policy.recipientPosture.status == .trustTooLow,
                postureBlocked: postureStatusBlocksExecution(policy.recipientPosture.status),
                postureBlockReason: postureBlockReason(from: policy.recipientPosture.status),
                resolvedRoute: nil
            )
        }

        guard let executionPublicProfile = resolvedExecutionProfileForOutboundEnvelope(
            hydratedProfile: hydratedProfile,
            thread: thread,
            counterparty: counterparty
        ) else {
            return ExchangeFederationSendEligibility.fromCounterpartyDefaults(
                counterparty,
                reason: "No selected public execution surface is available for this thread.",
                isEligible: false,
                disclosureAllowed: true,
                requiresApproval: policy.approval.required,
                postureBlocked: true,
                postureBlockReason: .routeRequiredButMissing,
                resolvedRoute: nil
            )
        }

        if hydratedProfile == nil,
           ExchangePolicyEngine.isExistingInboundContinuationReplySend(thread: thread, counterparty: counterparty) {
            #if DEBUG
            exchFedServiceLog(
                "[OutboundRecipientResolution] mode=existingContinuation postureRequired=false targetNodeID=\(targetExecutionID) selectedCounterpartyID=\(thread.selectedCounterpartyID ?? counterparty.id) profileNodeID=\(executionPublicProfile.nodeID) decision=allow reason=existing_continuation_no_public_posture_required"
            )
            #endif
        }

        do {
            let built = try await envelopeService.buildEnvelope(
                thread: thread,
                counterparty: counterparty,
                publicProfile: executionPublicProfile,
                draft: draft,
                disclosureLevel: policy.disclosure.level,
                parentEnvelopeID: corr.parentEnvelopeID,
                idempotencyKey: stableEnvelopeID,
                now: Date()
            )

            return ExchangeFederationSendEligibility.fromCounterpartyDefaults(
                counterparty,
                reason: "Eligible for federation queueing.",
                isEligible: true,
                disclosureAllowed: true,
                requiresApproval: policy.approval.required,
                postureBlocked: false,
                postureBlockReason: nil,
                resolvedRoute: built.route
            )
        } catch let error as ExchangeEnvelopeServiceError {
            return ExchangeFederationSendEligibility.fromCounterpartyDefaults(
                counterparty,
                reason: envelopeEligibilityReason(error),
                isEligible: false,
                disclosureAllowed: !isDisclosureFailure(error),
                requiresApproval: policy.approval.required,
                postureBlocked: envelopeBlocksByPosture(error),
                postureBlockReason: postureBlockReason(from: error),
                resolvedRoute: nil
            )
        } catch let error as ExchangePrivateE2EESendBlockedError {
            return e2eeSendBlockedEligibility(from: error, counterparty: counterparty, policy: policy)
        } catch {
            return ExchangeFederationSendEligibility.fromCounterpartyDefaults(
                counterparty,
                reason: relayFailureReason(error),
                isEligible: false,
                disclosureAllowed: true,
                requiresApproval: policy.approval.required,
                postureBlocked: false,
                postureBlockReason: nil,
                resolvedRoute: nil
            )
        }
    }

    public func queueApprovedOutbound(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        draft: ExchangeMessageDraft,
        approval: ExchangeApproval,
        disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        priority: ExchangeDeliveryState.Priority,
        now: Date
    ) async throws -> ExchangeFederationQueueResult {
        guard draft.threadID == thread.id else {
            throw ExchangeFederationError.transportFailed(reason: "Draft does not belong to the provided thread.")
        }

        guard approval.threadID == thread.id else {
            throw ExchangeFederationError.transportFailed(reason: "Approval does not belong to the provided thread.")
        }

        if let approvalDraftID = approval.draftID, approvalDraftID != draft.id {
            throw ExchangeFederationError.transportFailed(reason: "Approval is not for the provided draft.")
        }

        guard approval.status == .approved else {
            throw ExchangeFederationError.approvalRequired
        }

        let queueThread = try await preflightApprovedOutboundQueueThread(
            thread: thread,
            draft: draft,
            approval: approval,
            now: now
        )

        let hydratedProfile = try await resolvedExecutionPublicProfile(
            thread: queueThread,
            counterparty: counterparty
        )

        let targetExecutionID = targetExecutionID(
            thread: queueThread,
            counterparty: counterparty,
            publicProfile: hydratedProfile
        )

        let baseStableEnvelopeID = stableEnvelopeKey(
            threadID: queueThread.id,
            draftID: draft.id,
            targetExecutionID: targetExecutionID
        )
        let corr = outboundConversationCorrelation(
            thread: queueThread,
            idempotencyKey: baseStableEnvelopeID
        )
        var threadWithCorrelation = queueThread
        var threadCorrelationChanged = false
        if threadWithCorrelation.metadata["conversation_id"]?.exchangeNilIfBlank == nil {
            threadWithCorrelation.metadata["conversation_id"] = corr.conversationID
            threadCorrelationChanged = true
        }
        if threadWithCorrelation.metadata["root_envelope_id"]?.exchangeNilIfBlank == nil {
            threadWithCorrelation.metadata["root_envelope_id"] = corr.rootEnvelopeID
            threadCorrelationChanged = true
        }
        if threadWithCorrelation.metadata["original_requester_envelope_id"]?.exchangeNilIfBlank == nil,
           let original = corr.originalRequesterEnvelopeID?.exchangeNilIfBlank {
            threadWithCorrelation.metadata["original_requester_envelope_id"] = original
            threadCorrelationChanged = true
        }
        if threadCorrelationChanged {
            threadWithCorrelation.updatedAt = now
            try await store.updateThread(threadWithCorrelation)
        }
        #if DEBUG
        exchFedServiceLog(
            "[OutboundConversationCorrelation] source=\(corr.source) localThreadID=\(queueThread.id.uuidString) envelopeID=\(baseStableEnvelopeID) parentEnvelopeID=\(corr.parentEnvelopeID ?? "nil") conversationID=\(corr.conversationID) rootEnvelopeID=\(corr.rootEnvelopeID)"
        )
        #endif

        var envelopeIDForQueue = baseStableEnvelopeID
        if let existing = try await store.fetchOutboxItemByEnvelopeID(baseStableEnvelopeID) {
            if isLiveOutboxItem(existing) {
                exchFedServiceLog(
                    "queueApprovedOutbound existingOutbox live -> idempotent return | threadID=\(queueThread.id.uuidString) | draftID=\(draft.id.uuidString) | outboxItemID=\(existing.id.uuidString) | envelopeID=\(existing.envelopeID) | phase=\(existing.deliveryState.phase.rawValue) | isActive=\(existing.isActive)"
                )
                return ExchangeFederationQueueResult(
                    outboxItem: existing,
                    auditRecords: []
                )
            }

            envelopeIDForQueue = "\(baseStableEnvelopeID)|retry-\(UUID().uuidString)"
            exchFedServiceLog(
                "queueApprovedOutbound existingOutbox terminal -> fresh retry key | threadID=\(queueThread.id.uuidString) | draftID=\(draft.id.uuidString) | oldOutboxItemID=\(existing.id.uuidString) | oldEnvelopeID=\(existing.envelopeID) | oldPhase=\(existing.deliveryState.phase.rawValue) | oldIsActive=\(existing.isActive) | newEnvelopeID=\(envelopeIDForQueue)"
            )
        }

        let policy = policyEngine.evaluate(
            thread: queueThread,
            selectedCounterparty: counterparty,
            publicProfile: hydratedProfile,
            draft: draft,
            deliveryState: nil
        )

        guard policy.federationExecution.allowed else {
            throw mapPolicyBlockToFederationError(
                policy: policy,
                counterparty: counterparty
            )
        }

        guard let executionPublicProfile = resolvedExecutionProfileForOutboundEnvelope(
            hydratedProfile: hydratedProfile,
            thread: queueThread,
            counterparty: counterparty
        ) else {
            throw ExchangeFederationError.transportFailed(
                reason: "No selected public execution surface is available for this thread."
            )
        }

        if hydratedProfile == nil,
           ExchangePolicyEngine.isExistingInboundContinuationReplySend(thread: queueThread, counterparty: counterparty) {
            #if DEBUG
            exchFedServiceLog(
                "[OutboundRecipientResolution] mode=existingContinuation postureRequired=false targetNodeID=\(targetExecutionID) selectedCounterpartyID=\(queueThread.selectedCounterpartyID ?? counterparty.id) profileNodeID=\(executionPublicProfile.nodeID) decision=allow reason=existing_continuation_no_public_posture_required"
            )
            #endif
        }

        let effectiveDisclosureLevel = disclosureLevel.clamped(to: policy.disclosure.level)

        let built: ExchangeEnvelopeService.BuiltEnvelope
        do {
            built = try await envelopeService.buildEnvelope(
                thread: queueThread,
                counterparty: counterparty,
                publicProfile: executionPublicProfile,
                draft: draft,
                disclosureLevel: effectiveDisclosureLevel,
                parentEnvelopeID: corr.parentEnvelopeID,
                idempotencyKey: envelopeIDForQueue,
                now: now
            )
        } catch let error as ExchangeEnvelopeServiceError {
            throw mapEnvelopeErrorToFederationError(
                error,
                counterpartyID: counterparty.id
            )
        } catch let error as ExchangePrivateE2EESendBlockedError {
            throw mapE2EESendBlockedToFederationError(error)
        }

        let outboxItem = ExchangeOutboxItem(
            createdAt: now,
            updatedAt: now,
            threadID: queueThread.id,
            draftID: draft.id,
            approvalID: approval.id,
            targetNodeID: targetExecutionID,
            envelopeID: envelopeIDForQueue,
            deliveryState: .init(
                phase: .queued,
                priority: priority,
                queuedAt: now,
                relayRouteSummary: built.route.summaryLine
            ),
            policy: .init(
                maxAttempts: transportPolicy.maxAttempts,
                allowsBackgroundRetry: true,
                cancelOnApprovalRevocation: policy.federationExecution.cancelOnApprovalRevocation,
                requiresVisibleAudit: policy.audit.required,
                expiresAt: approval.expiresAt
            ),
            payloadSummary: payloadSummary(for: draft),
            isActive: true,
            metadata: queueMetadata(
                thread: queueThread,
                counterparty: counterparty,
                publicProfile: executionPublicProfile,
                draftMetadata: draft.metadata,
                approvalMetadata: approval.metadata,
                route: built.route,
                disclosureLevel: effectiveDisclosureLevel,
                targetExecutionID: targetExecutionID,
                parentEnvelopeID: corr.parentEnvelopeID,
                conversationID: corr.conversationID,
                rootEnvelopeID: corr.rootEnvelopeID,
                originalRequesterEnvelopeID: corr.originalRequesterEnvelopeID
            )
        )
#if DEBUG
exchFedServiceLog(
    "queue/send routing | " +
    "targetExecutionID=\(targetExecutionID) | " +
    "routeKind=\(built.route.kind.rawValue) | " +
    "routeDestination=\(built.route.destination) | " +
    "outboxTargetNodeID=\(outboxItem.targetNodeID) | " +
    "publicProfileID=\(executionPublicProfile.id) | " +
    "publicProfileNodeID=\(executionPublicProfile.nodeID) | " +
    "counterpartyID=\(counterparty.id) | " +
    "counterpartyIdentityNodeID=\(counterparty.identity?.nodeID ?? "nil")"
)
#endif

        let audit = ExchangeAuditRecord.outboundQueued(
            threadID: queueThread.id,
            outboxItemID: outboxItem.id,
            envelopeID: outboxItem.envelopeID,
            relatedNodeID: targetExecutionID,
            relatedDisplayName: counterparty.displayName,
            createdAt: now
        )

        try await store.performTransaction {
            try await store.saveOutboxItem(outboxItem)
            if policy.audit.required {
                try await store.appendAuditRecord(audit)
            }
        }
        refreshTraceFedLog(
            "[SendQueued] thread=\(thread.id.uuidString) draft=\(draft.id.uuidString) outboxItem=\(outboxItem.id.uuidString) envelopeID=\(outboxItem.envelopeID) trigger=queueApprovedOutbound time=\(now)"
        )

        return ExchangeFederationQueueResult(
            outboxItem: outboxItem,
            auditRecords: policy.audit.required ? [audit] : []
        )
    }

    // MARK: - Cancellation / flush

    public func cancelOutbound(
        outboxItemID: ExchangeOutboxItem.ID,
        reason: String?,
        now: Date
    ) async throws -> ExchangeFederationCancellationResult {
        let existing = try await store.requireOutboxItem(id: outboxItemID)
        let displayName = try await counterpartyDisplayName(for: existing.targetNodeID)

        let updated: ExchangeOutboxItem
        let audit: ExchangeAuditRecord

        if existing.canBeCancelledLocally {
            updated = existing.cancellingBeforeSend(
                note: reason,
                at: now
            )

            audit = ExchangeAuditRecord.outboundCancelled(
                threadID: existing.threadID,
                outboxItemID: updated.id,
                envelopeID: updated.envelopeID,
                relatedNodeID: updated.targetNodeID,
                relatedDisplayName: displayName,
                detail: reason ?? "Cancelled before send.",
                externalEffect: .none,
                createdAt: now
            )
        } else {
            let lateEffect: ExchangeFailure.ExternalEffect =
                existing.deliveryState.externalEffect.changedAnythingExternally
                ? existing.deliveryState.externalEffect
                : .attemptedButNotConfirmed

            updated = existing.markingTooLateToCancel(
                note: reason ?? "Cancellation was requested after outward delivery work may have begun.",
                at: now
            )

            audit = ExchangeAuditRecord.outboundCancelled(
                threadID: existing.threadID,
                outboxItemID: updated.id,
                envelopeID: updated.envelopeID,
                relatedNodeID: updated.targetNodeID,
                relatedDisplayName: displayName,
                detail: reason ?? "Too late to guarantee cancellation.",
                externalEffect: lateEffect,
                createdAt: now
            )
        }

        try await store.performTransaction {
            try await store.saveOutboxItem(updated)
            try await store.appendAuditRecord(audit)
        }

        return ExchangeFederationCancellationResult(
            outboxItem: updated,
            auditRecord: audit
        )
    }

    public func flushOutbox(now: Date) async throws -> ExchangeFederationFlushResult {
        let candidates = try await store.listOutboxItems(
            filter: .init(activeOnly: true)
        ).sorted(by: outboxOrdering)

        let runtimeRaw = await runtimeMonitor.snapshot()
        let runtime = ExchangeTransportPolicy.RuntimeSnapshot(
            allowsBackgroundWork: runtimeRaw.allowsBackgroundWork,
            isLowPowerModeEnabled: runtimeRaw.isLowPowerModeEnabled,
            isGenerating: runtimeRaw.isGenerating,
            isThermalHigh: runtimeRaw.isThermalHigh,
            isThermalCritical: runtimeRaw.isThermalCritical
        )

        var result = ExchangeFederationFlushResult()
        var confirmedThreadIDs: Set<UUID> = []

        for item in candidates {
            if let expiresAt = item.policy.expiresAt, expiresAt < now {
                let failed = item.failingTerminally(
                    errorCode: "expired",
                    note: "The approval or delivery window expired before send.",
                    externalEffect: .none,
                    at: now
                )

                let audit = ExchangeAuditRecord.failed(
                    direction: .outbound,
                    threadID: item.threadID,
                    envelopeID: item.envelopeID,
                    outboxItemID: item.id,
                    summary: "Outbound delivery expired.",
                    detail: "This queued send expired before execution.",
                    externalEffect: .none,
                    relatedNodeID: item.targetNodeID,
                    relatedDisplayName: try await counterpartyDisplayName(for: item.targetNodeID),
                    createdAt: now
                )

                try await store.performTransaction {
                    try await store.saveOutboxItem(failed)
                    try await store.appendAuditRecord(audit)
                }

                result.failed += 1
                continue
            }

            if let deferredUntil = item.deliveryState.deferredUntil, deferredUntil > now {
                result.untouched += 1
                continue
            }

            let evaluation = transportPolicy.evaluate(
                workClass: .approvedUserSend,
                deliveryPriority: item.deliveryState.priority,
                runtime: runtime,
                attemptCount: item.deliveryState.attemptCount
            )

            switch evaluation.decision {
            case .block:
                let blocked = item.updatingDeliveryState(
                    item.deliveryState.markingBlocked(
                        note: evaluation.reason,
                        at: now
                    ),
                    at: now
                )

                let audit = ExchangeAuditRecord(
                    createdAt: now,
                    threadID: item.threadID,
                    direction: .localOnly,
                    category: .blockedByPolicy,
                    actor: .system,
                    envelopeID: item.envelopeID,
                    outboxItemID: item.id,
                    summary: "Outbound delivery is blocked.",
                    detail: evaluation.reason,
                    externalEffect: .none,
                    relatedNodeID: item.targetNodeID,
                    relatedDisplayName: try await counterpartyDisplayName(for: item.targetNodeID)
                )

                try await store.performTransaction {
                    try await store.saveOutboxItem(blocked)
                    try await store.appendAuditRecord(audit)
                }

                result.untouched += 1

            case .deferred:
                let deferredDate = evaluation.retryAfterSeconds.map { now.addingTimeInterval(TimeInterval($0)) }
                let deferred = item.updatingDeliveryState(
                    item.deliveryState.deferring(
                        until: deferredDate,
                        note: evaluation.reason,
                        at: now
                    ),
                    at: now
                )

                let audit = ExchangeAuditRecord(
                    createdAt: now,
                    threadID: item.threadID,
                    direction: .localOnly,
                    category: .deferred,
                    actor: .system,
                    envelopeID: item.envelopeID,
                    outboxItemID: item.id,
                    summary: "Outbound delivery was deferred.",
                    detail: evaluation.reason,
                    externalEffect: .none,
                    relatedNodeID: item.targetNodeID,
                    relatedDisplayName: try await counterpartyDisplayName(for: item.targetNodeID)
                )

                try await store.performTransaction {
                    try await store.saveOutboxItem(deferred)
                    try await store.appendAuditRecord(audit)
                }

                result.deferred += 1

            case .runNow:
                guard let thread = try await store.fetchThread(id: item.threadID) else {
                    result.untouched += 1
                    continue
                }

                let draft = try await store.fetchDraft(id: item.draftID)
                if DirectMessageLegacyExchangeOutbox.shouldQuarantineExchangeOutboxForDmRelayOwnedSend(
                    thread: thread,
                    draft: draft,
                    item: item
                ) {
                    let failed = item.failingTerminally(
                        errorCode: "dm_manual_v2_superseded",
                        note: "Superseded by DirectMessageSendV2 relay-direct path; exchange outbox must not retry.",
                        externalEffect: .none,
                        at: now
                    )

                    let audit = ExchangeAuditRecord.failed(
                        direction: .outbound,
                        threadID: item.threadID,
                        envelopeID: item.envelopeID,
                        outboxItemID: item.id,
                        summary: "Direct-message relay-direct path superseded this exchange outbox row.",
                        detail: "This queued outbound belonged to a direct_message_thread manual-DM lane that is owned by DirectMessageSendV2; exchange flush must not retry it.",
                        externalEffect: .none,
                        relatedNodeID: item.targetNodeID,
                        relatedDisplayName: try await counterpartyDisplayName(for: item.targetNodeID),
                        createdAt: now
                    )

                    try await store.performTransaction {
                        try await store.saveOutboxItem(failed)
                        try await store.appendAuditRecord(audit)
                    }

                    #if DEBUG
                    Swift.print(
                        "[OutboxFlush][skipDirectMessageThread] threadID=\(item.threadID.uuidString) " +
                            "outboxID=\(item.id.uuidString) reason=dm_v2_owns_send"
                    )
                    #endif

                    result.attempted += 1
                    result.failed += 1
                    continue
                }

                if thread.metadata["contact_request_thread"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true" {
                    let failed = item.failingTerminally(
                        errorCode: "contact_request_legacy_superseded",
                        note: "Superseded by contact-signal send path.",
                        externalEffect: .none,
                        at: now
                    )

                    let audit = ExchangeAuditRecord.failed(
                        direction: .outbound,
                        threadID: item.threadID,
                        envelopeID: item.envelopeID,
                        outboxItemID: item.id,
                        summary: "Legacy contact-request exchange outbox item skipped.",
                        detail: "This row belonged to the pre-contact-signal send path and was quarantined so it no longer blocks federation flush.",
                        externalEffect: .none,
                        relatedNodeID: item.targetNodeID,
                        relatedDisplayName: try await counterpartyDisplayName(for: item.targetNodeID),
                        createdAt: now
                    )

                    try await store.performTransaction {
                        try await store.saveOutboxItem(failed)
                        try await store.appendAuditRecord(audit)
                    }

                    #if DEBUG
                    Swift.print(
                        "[ContactRequestSend][legacyExchangeOutboxIgnored] threadID=\(item.threadID.uuidString) outboxID=\(item.id.uuidString)"
                    )
                    #endif

                    result.attempted += 1
                    result.failed += 1
                    continue
                }

                let (sendOutcome, confirmedThreadID): (SendOutcome, UUID?)
                do {
                    (sendOutcome, confirmedThreadID) = try await sendOutboxItem(item, now: now)
                } catch let error as ExchangeThreadEngineError {
                    if case .invalidTransition = error {
                        let failed = item.failingTerminally(
                            errorCode: "approved_outbox_thread_state_unaligned",
                            note: error.localizedDescription,
                            externalEffect: .none,
                            at: now
                        )
                        let audit = ExchangeAuditRecord.failed(
                            direction: .outbound,
                            threadID: item.threadID,
                            envelopeID: item.envelopeID,
                            outboxItemID: item.id,
                            summary: "Approved outbound quarantined during flush.",
                            detail: error.localizedDescription,
                            externalEffect: .none,
                            relatedNodeID: item.targetNodeID,
                            relatedDisplayName: try await counterpartyDisplayName(for: item.targetNodeID),
                            createdAt: now
                        )
                        try await store.performTransaction {
                            try await store.saveOutboxItem(failed)
                            try await store.appendAuditRecord(audit)
                        }
                        result.attempted += 1
                        result.failed += 1
                        continue
                    }
                    throw error
                }
                if let confirmedThreadID {
                    confirmedThreadIDs.insert(confirmedThreadID)
                }
                switch sendOutcome {
                case .sent:
                    result.attempted += 1
                case .acknowledged:
                    result.attempted += 1
                    result.acknowledged += 1
                case .deferred:
                    result.deferred += 1
                case .failed:
                    result.attempted += 1
                    result.failed += 1
                case .untouched:
                    result.untouched += 1
                }
            }
        }

        result.outboundRelayConfirmedThreadIDs = Array(confirmedThreadIDs).sorted {
            $0.uuidString < $1.uuidString
        }
        return result
    }

    // MARK: - Inbound receive / reconcile

    public func receiveEnvelope(
        _ envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?,
        receivedAt: Date
    ) async throws -> ExchangeFederationReceiveResult {
        let stableEnvelopeID = stableEnvelopeID(from: envelope)
        let resolvedInboundText = await resolveInboundMessageText(for: envelope)
        let cleanedInboundBody = ExchangeUserFacingCopySanitizer.cleanReceivedFederationBody(resolvedInboundText.body)
        let localNodeID = try await identityService.localIdentity().nodeID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recipientNodeID = recipientNodeID(from: envelope)
        let parentEnvelopeID = envelope.ordering.parentEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let conversationID = envelope.metadata["conversation_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #if DEBUG
        refreshTraceFedLog(
            "[ReceivedBodyClean] envelopeID=\(stableEnvelopeID) threadID=\(envelope.threadID.uuidString) originalLen=\(envelope.payload.body.count) cleanLen=\(cleanedInboundBody.cleaned.count) removedInternalScaffold=\(cleanedInboundBody.removedInternalScaffold) bodyPrefix=\(textPreview(cleanedInboundBody.cleaned, limit: 120))"
        )
        #endif

        if !localNodeID.isEmpty {
            if envelope.sender.nodeID.trimmingCharacters(in: .whitespacesAndNewlines) == localNodeID {
                refreshTraceFedLog(
                    "[InboundSelfEchoIgnored] reason=self_sender envelopeID=\(stableEnvelopeID) senderNodeID=\(envelope.sender.nodeID) recipientNodeID=\(recipientNodeID ?? "nil") localNodeID=\(localNodeID) threadID=\(envelope.threadID.uuidString) parentEnvelopeID=\(parentEnvelopeID) conversationID=\(conversationID)"
                )
                return try await persistIgnoredInboundEnvelope(
                    stableEnvelopeID: stableEnvelopeID,
                    envelope: envelope,
                    route: route,
                    receivedAt: receivedAt,
                    localNodeID: localNodeID,
                    reason: "self_sender",
                    cleanedBody: cleanedInboundBody.cleaned
                )
            }
            if let recipientNodeID, !recipientNodeID.isEmpty, recipientNodeID != localNodeID {
                refreshTraceFedLog(
                    "[InboundSelfEchoIgnored] reason=recipient_mismatch envelopeID=\(stableEnvelopeID) senderNodeID=\(envelope.sender.nodeID) recipientNodeID=\(recipientNodeID) localNodeID=\(localNodeID) threadID=\(envelope.threadID.uuidString) parentEnvelopeID=\(parentEnvelopeID) conversationID=\(conversationID)"
                )
                return try await persistIgnoredInboundEnvelope(
                    stableEnvelopeID: stableEnvelopeID,
                    envelope: envelope,
                    route: route,
                    receivedAt: receivedAt,
                    localNodeID: localNodeID,
                    reason: "recipient_mismatch",
                    cleanedBody: cleanedInboundBody.cleaned
                )
            }
            if try await store.fetchOutboxItemByEnvelopeID(stableEnvelopeID) != nil {
                refreshTraceFedLog(
                    "[InboundSelfEchoIgnored] reason=matches_local_outbox envelopeID=\(stableEnvelopeID) senderNodeID=\(envelope.sender.nodeID) recipientNodeID=\(recipientNodeID ?? "nil") localNodeID=\(localNodeID) threadID=\(envelope.threadID.uuidString) parentEnvelopeID=\(parentEnvelopeID) conversationID=\(conversationID)"
                )
                return try await persistIgnoredInboundEnvelope(
                    stableEnvelopeID: stableEnvelopeID,
                    envelope: envelope,
                    route: route,
                    receivedAt: receivedAt,
                    localNodeID: localNodeID,
                    reason: "matches_local_outbox",
                    cleanedBody: cleanedInboundBody.cleaned
                )
            }
        }

        if let existing = try await store.fetchInboxItemByEnvelopeID(stableEnvelopeID) {
            let audit = ExchangeAuditRecord(
                createdAt: receivedAt,
                threadID: existing.threadID,
                direction: .inbound,
                category: .duplicateIgnored,
                actor: .system,
                envelopeID: stableEnvelopeID,
                inboxItemID: existing.id,
                summary: "Ignored a duplicate inbound envelope.",
                detail: "An envelope with the same stable identifier was already received.",
                externalEffect: .none,
                relatedNodeID: existing.senderNodeID,
                relatedDisplayName: existing.senderDisplayName
            )

            try await store.appendAuditRecord(audit)

            return ExchangeFederationReceiveResult(
                inboxItem: existing,
                auditRecord: audit
            )
        }

        let compatibility = try await compatibilityForInboundEnvelope(envelope)
        let authenticity = await inboundAuthenticityFlags(for: envelope)
        let processingState: ExchangeInboxItem.ProcessingState = compatibility.isProcessable ? .received : .rejected

        let inboxItem = ExchangeInboxItem(
            receivedAt: receivedAt,
            updatedAt: receivedAt,
            envelopeID: stableEnvelopeID,
            threadID: nil,
            senderNodeID: envelope.sender.nodeID,
            senderDisplayName: envelope.sender.displayName,
            ordering: .init(
                sequenceNumber: envelope.ordering.sequenceNumber,
                parentEnvelopeID: envelope.ordering.parentEnvelopeID,
                senderTimestamp: envelope.createdAt
            ),
            compatibility: compatibility,
            processingState: processingState,
            visibleSummary: inboundSummary(
                for: envelope,
                resolvedBody: resolvedInboundText.body,
                resolvedSubject: resolvedInboundText.subject
            ),
            metadata: {
                var metadata = inboundMetadata(
                    envelope: envelope,
                    cleanedBody: cleanedInboundBody.cleaned,
                    decryptedSubject: resolvedInboundText.subject,
                    bodySanitizedFromInternalScaffold: cleanedInboundBody.removedInternalScaffold,
                    compatibility: compatibility,
                    authenticity: authenticity,
                    route: route
                )
                if !resolvedInboundText.attachments.isEmpty {
                    DirectMessageAttachmentMetadata.apply(
                        descriptors: resolvedInboundText.attachments,
                        to: &metadata
                    )
                }
                return metadata
            }()
        )

        let audit: ExchangeAuditRecord = compatibility.isProcessable
            ? .inboundReceived(
                inboxItemID: inboxItem.id,
                envelopeID: stableEnvelopeID,
                threadID: nil,
                relatedNodeID: inboxItem.senderNodeID,
                relatedDisplayName: inboxItem.senderDisplayName,
                summary: "Received an inbound federation message.",
                createdAt: receivedAt
            )
            : .failed(
                direction: .inbound,
                category: .incompatible,
                threadID: nil,
                envelopeID: stableEnvelopeID,
                inboxItemID: inboxItem.id,
                summary: "Received an inbound envelope that could not be processed.",
                detail: compatibilityFailureDetail(compatibility),
                externalEffect: .changed(description: "An inbound envelope arrived but could not be processed."),
                relatedNodeID: inboxItem.senderNodeID,
                relatedDisplayName: inboxItem.senderDisplayName,
                createdAt: receivedAt
            )

        try await store.performTransaction {
            try await store.saveInboxItem(inboxItem)
            try await store.appendAuditRecord(audit)
        }
        refreshTraceFedLog(
            "[InboxSyncResult] runID=federation-receive rawCount=1 mappedCount=1 envelopeIDs=\(stableEnvelopeID) nextCheckpoint=unchanged time=\(receivedAt)"
        )

        #if DEBUG
        exchFedServiceLog(
            "[DMRoute][inboundMetadata] inboxItemID=\(inboxItem.id.uuidString) envelopeID=\(stableEnvelopeID) " +
                "conversation_surface=\(inboxItem.metadata["conversation_surface"] ?? "nil") " +
                "senderNodeID=\(inboxItem.senderNodeID ?? "nil")"
        )
        let parentForLog = inboxItem.ordering.parentEnvelopeID ?? "nil"
        exchFedServiceLog(
            "receiveEnvelope.savedItem | inboxItemID=\(inboxItem.id.uuidString) | " +
                "envelopeID=\(stableEnvelopeID) | processingState=\(inboxItem.processingState.rawValue) | " +
                "compatibility=\(compatibilityMetadataValue(inboxItem.compatibility)) | " +
                "senderNodeID=\(inboxItem.senderNodeID ?? "nil") | parentEnvelopeID=\(parentForLog) | " +
                "threadID=\(inboxItem.threadID?.uuidString ?? "nil")"
        )
        if let reloaded = try? await store.fetchInboxItem(id: inboxItem.id) {
            exchFedServiceLog(
                "receiveEnvelope.postSaveVerify | fetchOK=1 | processingState=\(reloaded.processingState.rawValue) | " +
                    "threadID=\(reloaded.threadID?.uuidString ?? "nil")"
            )
        } else {
            exchFedServiceLog("receiveEnvelope.postSaveVerify | fetchOK=0")
        }
        #endif

        return ExchangeFederationReceiveResult(
            inboxItem: inboxItem,
            auditRecord: audit
        )
    }

    public func reconcileInbox(now: Date) async throws -> ExchangeFederationReconcileResult {
        try await repairVersionRejectedInboxItems(now: now)

        let items = try await store.listInboxItems(
            filter: .init(
                processingStates: [.received, .deferred, .awaitingOrderingGapResolution],
                processableOnly: false
            )
        )

        #if DEBUG
        exchFedServiceLog("reconcileInbox.listed | count=\(items.count)")
        for listed in items {
            let p = listed.ordering.parentEnvelopeID ?? "nil"
            exchFedServiceLog(
                "reconcileInbox.item | id=\(listed.id.uuidString) | envelopeID=\(listed.envelopeID) | " +
                    "processingState=\(listed.processingState.rawValue) | " +
                    "compatibility=\(compatibilityMetadataValue(listed.compatibility)) | " +
                    "threadID=\(listed.threadID?.uuidString ?? "nil") | parentEnvelopeID=\(p)"
            )
        }
        #endif

        let runtimeRaw = await runtimeMonitor.snapshot()
        let runtime = ExchangeTransportPolicy.RuntimeSnapshot(
            allowsBackgroundWork: runtimeRaw.allowsBackgroundWork,
            isLowPowerModeEnabled: runtimeRaw.isLowPowerModeEnabled,
            isGenerating: runtimeRaw.isGenerating,
            isThermalHigh: runtimeRaw.isThermalHigh,
            isThermalCritical: runtimeRaw.isThermalCritical
        )

        let evaluation = transportPolicy.evaluate(
            workClass: .inboundReceive,
            deliveryPriority: .normal,
            runtime: runtime,
            attemptCount: 0
        )

        guard evaluation.decision == .runNow else {
            var deferredCount = 0

            #if DEBUG
            exchFedServiceLog(
                "reconcileInbox.transportDeferred | decision=\(evaluation.decision.rawValue) | " +
                    "reason=\(evaluation.reason) | items=\(items.count)"
            )
            #endif

            for item in items where item.processingState == .received {
                let deferred = item.markingDeferred(at: now)
                try await store.saveInboxItem(deferred)
                deferredCount += 1
            }

            return ExchangeFederationReconcileResult(
                reconciledCount: 0,
                deferredCount: deferredCount,
                rejectedCount: 0
            )
        }

        var reconciledCount = 0
        var deferredCount = 0
        var rejectedCount = 0
        var reconciledThreadIDs: [ExchangeThread.ID] = []
        var reconciledEnvelopeIDs: [String] = []
        var trustEligibleThreadIDs: [ExchangeThread.ID] = []
        let localNodeID = (try? await identityService.localIdentity().nodeID.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""

        for item in items {
            var currentItem = item
            let senderTrimmed = currentItem.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let recipientMetadata = currentItem.metadata["recipient_node_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isLocalOutboxEcho = (try await store.fetchOutboxItemByEnvelopeID(currentItem.envelopeID)) != nil
            let isSelfSender = !localNodeID.isEmpty && !senderTrimmed.isEmpty && senderTrimmed == localNodeID
            let isRecipientMismatch = !localNodeID.isEmpty && !recipientMetadata.isEmpty && recipientMetadata != localNodeID
            if isSelfSender || isRecipientMismatch || isLocalOutboxEcho {
                let reason: String
                if isSelfSender {
                    reason = "self_sender"
                } else if isRecipientMismatch {
                    reason = "recipient_mismatch"
                } else {
                    reason = "local_outbox_echo"
                }
                currentItem.metadata["ignored_reason"] = reason
                let ignored = currentItem.markingDuplicateIgnored(at: now)
                try await store.saveInboxItem(ignored)
                refreshTraceFedLog(
                    "[InboundTurnSuppressed] reason=\(reason) inboxItemID=\(ignored.id.uuidString) envelopeID=\(ignored.envelopeID) threadID=\(ignored.threadID?.uuidString ?? "nil") senderNodeID=\(senderTrimmed) localNodeID=\(localNodeID)"
                )
                continue
            }

            if !item.compatibility.isProcessable {
                #if DEBUG
                exchFedServiceLog(
                    "reconcileInbox.branch | rejectedIncompatible | inboxItemID=\(item.id.uuidString) | " +
                        "envelopeID=\(item.envelopeID)"
                )
                #endif
                let rejected = item.rejecting(at: now)
                let audit = ExchangeAuditRecord.failed(
                    direction: .inbound,
                    category: .incompatible,
                    threadID: rejected.threadID,
                    envelopeID: rejected.envelopeID,
                    inboxItemID: rejected.id,
                    summary: "Rejected an incompatible inbound envelope.",
                    detail: compatibilityFailureDetail(rejected.compatibility),
                    externalEffect: .changed(description: "An inbound envelope arrived but was rejected."),
                    relatedNodeID: rejected.senderNodeID,
                    relatedDisplayName: rejected.senderDisplayName,
                    createdAt: now
                )

                try await store.performTransaction {
                    try await store.saveInboxItem(rejected)
                    try await store.appendAuditRecord(audit)
                }

                rejectedCount += 1
                continue
            }

            let routesAsDirectMessageSurface = Self.routesIncomingItemAsDirectMessageSurface(item)
            if routesAsDirectMessageSurface {
                let orderParentSnap = item.ordering.parentEnvelopeID?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let metaParentSnap = item.metadata["parent_envelope_id"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let parentPresent = (!orderParentSnap.isEmpty || !metaParentSnap.isEmpty) ? "yes" : "no"
                #if DEBUG
                exchFedServiceLog(
                    "[DMRoute][surfaceFirst] inboxItemID=\(item.id.uuidString) surface=direct_message " +
                        "parentPresent=\(parentPresent) decision=dm_router"
                )
                #endif

                if senderTrimmed.isEmpty {
                    let deferred = item.markingDeferred(at: now)
                    let audit = ExchangeAuditRecord(
                        createdAt: now,
                        threadID: nil,
                        direction: .localOnly,
                        category: .deferred,
                        actor: .system,
                        envelopeID: item.envelopeID,
                        inboxItemID: item.id,
                        summary: "Deferred inbound direct message (missing sender node id).",
                        detail: "conversation_surface=direct_message requires senderNodeID for DM routing.",
                        externalEffect: .none,
                        relatedNodeID: item.senderNodeID,
                        relatedDisplayName: item.senderDisplayName
                    )
                    try await store.performTransaction {
                        try await store.saveInboxItem(deferred)
                        try await store.appendAuditRecord(audit)
                    }
                    deferredCount += 1
                    continue
                }

                try await ensureMinimalCounterpartyFromInboundDirectMessageIfNeeded(
                    item: item,
                    now: now
                )
            }

            if !routesAsDirectMessageSurface,
               let parentEnvelopeID = item.ordering.parentEnvelopeID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !parentEnvelopeID.isEmpty {
                let parentInInbox = try await store.fetchInboxItemByEnvelopeID(parentEnvelopeID) != nil
                let parentInOutbox = try await store.fetchOutboxItemByEnvelopeID(parentEnvelopeID) != nil
                if !parentInInbox && !parentInOutbox {
                    #if DEBUG
                    exchFedServiceLog(
                        "reconcileInbox.branch | awaitingOrderingGap | inboxItemID=\(item.id.uuidString) | " +
                            "parentEnvelopeID=\(parentEnvelopeID)"
                    )
                    #endif
                    let waiting = item.markingAwaitingOrderingGapResolution(at: now)
                    try await store.saveInboxItem(waiting)
                    deferredCount += 1
                    continue
                }
            }

            if !routesAsDirectMessageSurface,
               let parentEnvelopeID = item.ordering.parentEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !parentEnvelopeID.isEmpty,
               let outbox = try await store.fetchOutboxItemByEnvelopeID(parentEnvelopeID),
               let parentThread = try await store.fetchThread(id: outbox.threadID) {
                let senderNodeID = item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let expectedCounterpartyID = parentThread.selectedCounterpartyID?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let expectedTargetNodeID = outbox.targetNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
                let expected = !expectedCounterpartyID.isEmpty
                    ? expectedCounterpartyID
                    : expectedTargetNodeID

                if !expected.isEmpty, !senderNodeID.isEmpty, senderNodeID != expected {
                    currentItem.metadata["suspicious_parent_thread_binding"] = "true"
                    currentItem.metadata["suspicious_parent_envelope_id"] = parentEnvelopeID
                    currentItem.metadata["suspicious_expected_sender"] = expected
                    currentItem.metadata["suspicious_actual_sender"] = senderNodeID
                    currentItem.metadata["inbound_auth_caution"] = "parent_thread_binding_sender_mismatch"
                    let deferred = currentItem.markingDeferred(at: now)
                    let audit = ExchangeAuditRecord(
                        createdAt: now,
                        threadID: nil,
                        direction: .localOnly,
                        category: .deferred,
                        actor: .system,
                        envelopeID: item.envelopeID,
                        inboxItemID: item.id,
                        summary: "Deferred inbound reconciliation due to sender mismatch.",
                        detail: "Inbound sender did not match the expected thread counterparty for parent envelope binding.",
                        externalEffect: .none,
                        relatedNodeID: item.senderNodeID,
                        relatedDisplayName: item.senderDisplayName
                    )
                    try await store.performTransaction {
                        try await store.saveInboxItem(deferred)
                        try await store.appendAuditRecord(audit)
                    }
                    deferredCount += 1
                    continue
                }
            }

            var resolvedFromFirstContactThreadCreation = false
            let resolvedThread: ExchangeThread

            if let found = try await resolveThreadForInboxItem(item) {
                #if DEBUG
                exchFedServiceLog(
                    "reconcileInbox.branch | resolvedExistingThread | inboxItemID=\(item.id.uuidString) | " +
                        "threadID=\(found.id.uuidString)"
                )
                let traced = try await resolveThreadForInboxItemTracing(item)
                ExchangeBilateralConversationDebugTrace.logInboxReceive(
                    item: item,
                    resolvedThread: found,
                    createdThreadID: nil,
                    existingThreadID: found.id,
                    matchReason: traced.reason
                )
                #else
                exchFedServiceLog(
                    "reconcileInbox.branch | resolvedExistingThread | inboxItemID=\(item.id.uuidString) | " +
                        "threadID=\(found.id.uuidString)"
                )
                #endif
                resolvedThread = found
            } else if routesAsDirectMessageSurface {
                #if DEBUG
                exchFedServiceLog(
                    "reconcileInbox.branch | directMessageSurfaceUnresolved | inboxItemID=\(item.id.uuidString) | " +
                        "envelopeID=\(item.envelopeID)"
                )
                ExchangeBilateralConversationDebugTrace.logInboxReceive(
                    item: item,
                    resolvedThread: nil,
                    createdThreadID: nil,
                    existingThreadID: nil,
                    matchReason: "deferred_unresolved",
                    deferredReason: "conversation_surface=direct_message thread resolution failed"
                )
                #endif
                let deferred = item.markingDeferred(at: now)
                let audit = ExchangeAuditRecord(
                    createdAt: now,
                    threadID: nil,
                    direction: .localOnly,
                    category: .deferred,
                    actor: .system,
                    envelopeID: item.envelopeID,
                    inboxItemID: item.id,
                    summary: "Deferred inbound direct message (thread resolution failed).",
                    detail: "conversation_surface=direct_message but no DM thread could be resolved or created.",
                    externalEffect: .none,
                    relatedNodeID: item.senderNodeID,
                    relatedDisplayName: item.senderDisplayName
                )
                try await store.performTransaction {
                    try await store.saveInboxItem(deferred)
                    try await store.appendAuditRecord(audit)
                }
                deferredCount += 1
                continue
            } else if ExchangeContactSignalClassifier.isInboundContactRequest(currentItem) {
                let senderContact = currentItem.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if senderContact.isEmpty {
                    let deferred = currentItem.markingDeferred(at: now)
                    let audit = ExchangeAuditRecord(
                        createdAt: now,
                        threadID: nil,
                        direction: .localOnly,
                        category: .deferred,
                        actor: .system,
                        envelopeID: currentItem.envelopeID,
                        inboxItemID: currentItem.id,
                        summary: "Deferred inbound contact request (missing sender node id).",
                        detail: "Contact request signal requires senderNodeID for counterparty routing.",
                        externalEffect: .none,
                        relatedNodeID: currentItem.senderNodeID,
                        relatedDisplayName: currentItem.senderDisplayName
                    )
                    try await store.performTransaction {
                        try await store.saveInboxItem(deferred)
                        try await store.appendAuditRecord(audit)
                    }
                    deferredCount += 1
                    continue
                }

                let localNodeID = (try? await identityService.localIdentity().nodeID)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !localNodeID.isEmpty,
                   let edge = try? await store.fetchTrustEdge(
                        sourceNodeID: localNodeID,
                        targetNodeID: senderContact
                   ),
                   edge.revokedAt == nil {
                    var archivedCopy = currentItem
                    archivedCopy.threadID = nil
                    archivedCopy.updatedAt = now
                    let archivedItem = archivedCopy.archiving(at: now)
                    try await store.performTransaction {
                        try await store.saveInboxItem(archivedItem)
                    }
                    #if DEBUG
                    exchFedServiceLog(
                        "[ContactRequestRoute][suppressConnected] inboxItemID=\(currentItem.id.uuidString) sender=\(senderContact)"
                    )
                    #endif
                    reconciledCount += 1
                    continue
                }

                try await ensureMinimalInboundSenderCounterpartyShellIfNeeded(
                    item: currentItem,
                    now: now,
                    debugReason: "inbound_contact_request"
                )

                var contactCopy = currentItem
                contactCopy.threadID = nil
                contactCopy.metadata["contact_request_reconciled_without_thread"] = "true"
                contactCopy.updatedAt = now
                let reconciledContact = contactCopy.reconcilingIntoThread(at: now)
                let contactAudit = ExchangeAuditRecord(
                    createdAt: now,
                    threadID: nil,
                    direction: .inbound,
                    category: .reconciledIntoThread,
                    actor: .system,
                    envelopeID: reconciledContact.envelopeID,
                    inboxItemID: reconciledContact.id,
                    summary: "Reconciled inbound contact request.",
                    detail: "Stored contact signal without creating an exchange work thread.",
                    externalEffect: .changed(description: "Contact request arrived and was recorded."),
                    relatedNodeID: reconciledContact.senderNodeID,
                    relatedDisplayName: reconciledContact.senderDisplayName
                )

                try await store.performTransaction {
                    try await store.saveInboxItem(reconciledContact)
                    try await store.appendAuditRecord(contactAudit)
                }

                reconciledCount += 1
                #if DEBUG
                let surf = reconciledContact.metadata["conversation_surface"] ?? "nil"
                let ck = reconciledContact.metadata["conversation_kind"] ?? "nil"
                let pkLog = reconciledContact.metadata["payload_kind"] ?? "nil"
                exchFedServiceLog(
                    "[ContactRequestRoute][received] inboxItemID=\(reconciledContact.id.uuidString) surface=\(surf) kind=\(ck) payload_kind=\(pkLog) sender=\(reconciledContact.senderNodeID ?? "nil")"
                )
                #endif
                continue
            } else if Self.isParentlessForFirstContactInboxItem(item) {
                // First-contact inbound: no parent envelope, no existing thread.
                // Create a new inbound thread for this sender and continue
                // into normal reconciliation. Approval gates are not bypassed.
                do {
                    let (newThread, newCounterparty) = try await makeInboundThreadForNewContact(
                        item,
                        now: now
                    )

                    currentItem.threadID = newThread.id
                    currentItem.updatedAt = now
                    let itemToSave = currentItem

                    try await store.performTransaction {
                        try await store.createThread(newThread)
                        if let cp = newCounterparty {
                            try await store.upsertCounterparties([cp])
                        }
                        try await store.saveInboxItem(itemToSave)
                    }

                    #if DEBUG
                    exchFedServiceLog(
                        "reconcileInbox.branch | firstContactCreated | inboxItemID=\(item.id.uuidString) | " +
                            "newThreadID=\(newThread.id.uuidString) | " +
                            "selectedCounterpartyID=\(newThread.selectedCounterpartyID ?? "nil") | " +
                            "state=\(ExchangeTransition.ExchangeStateKey(newThread.state).rawValue)"
                    )
                    ExchangeBilateralConversationDebugTrace.logInboxReceive(
                        item: itemToSave,
                        resolvedThread: newThread,
                        createdThreadID: newThread.id,
                        existingThreadID: nil,
                        matchReason: "firstContactCreated"
                    )
                    if let verifyThread = try? await store.fetchThread(id: newThread.id) {
                        exchFedServiceLog(
                            "reconcileInbox.postSaveVerify.thread | id=\(verifyThread.id.uuidString) | " +
                                "state=\(ExchangeTransition.ExchangeStateKey(verifyThread.state).rawValue)"
                        )
                    }
                    if let verifyItem = try? await store.fetchInboxItem(id: itemToSave.id) {
                        exchFedServiceLog(
                            "reconcileInbox.postSaveVerify.inboxItem | threadID=\(verifyItem.threadID?.uuidString ?? "nil") | " +
                                "processingState=\(verifyItem.processingState.rawValue)"
                        )
                    }
                    #endif

                    resolvedThread = newThread
                    resolvedFromFirstContactThreadCreation = true
                } catch {
                    exchFedServiceLog(
                        "reconcileInbox.newThread.failed | " +
                        "inboxItemID=\(item.id) | error=\(error)"
                    )
                    let deferred = item.markingDeferred(at: now)
                    try? await store.saveInboxItem(deferred)
                    deferredCount += 1
                    continue
                }
            } else {
                #if DEBUG
                exchFedServiceLog(
                    "reconcileInbox.branch | noThreadResolved | inboxItemID=\(item.id.uuidString) | " +
                        "parentEnvelopeID=\(item.ordering.parentEnvelopeID ?? "nil")"
                )
                #endif
                // Has a parentEnvelopeID but no matching outbox item or thread yet.
                // Standard deferred behavior: ordering gap or reply to unknown context.
                let deferred = item.markingDeferred(at: now)

                let audit = ExchangeAuditRecord(
                    createdAt: now,
                    threadID: nil,
                    direction: .localOnly,
                    category: .deferred,
                    actor: .system,
                    envelopeID: item.envelopeID,
                    inboxItemID: item.id,
                    summary: "Deferred inbound reconciliation.",
                    detail: "No thread could be resolved for this inbound envelope yet.",
                    externalEffect: .none,
                    relatedNodeID: item.senderNodeID,
                    relatedDisplayName: item.senderDisplayName
                )

                try await store.performTransaction {
                    try await store.saveInboxItem(deferred)
                    try await store.appendAuditRecord(audit)
                }

                deferredCount += 1
                continue
            }

            #if DEBUG
            if resolvedFromFirstContactThreadCreation {
                let subj = currentItem.metadata["subject_preview"] ?? ""
                exchFedServiceLog(
                    "[InboundNewThreadCreated] envelope=\(currentItem.envelopeID) thread=\(resolvedThread.id.uuidString) title=\(resolvedThread.intent.title) reason=correlationMissParentlessFirstContact parentless=true subject=\(subj)"
                )
            }
            #endif

            let inboundSummary = item.metadata["subject_preview"] ?? item.visibleSummary
            let inboundBody = item.metadata["body_preview"] ?? item.visibleSummary

            let continuation = continuationCoordinator.evaluateInbound(
                thread: resolvedThread,
                summary: inboundSummary,
                body: inboundBody
            )

            let resolvedCounterparty = try await resolveCounterpartyForInboxItem(
                item,
                thread: resolvedThread
            )

            let threadUpdate = try await applyInboundContinuation(
                continuation,
                to: resolvedThread,
                counterparty: resolvedCounterparty,
                now: now
            )
            var updatedThread = threadUpdate.thread
            let isSuspiciousBinding = currentItem.metadata["suspicious_parent_thread_binding"] == "true"
            let isUnverifiedInbound = currentItem.metadata["inbound_auth_unverified"] == "true"
            if isSuspiciousBinding || isUnverifiedInbound {
                updatedThread.metadata["inbound_requires_verified_context_hold"] = "true"
                updatedThread.metadata["inbound_auth_caution"] = currentItem.metadata["inbound_auth_caution"] ?? "unverified_inbound"
                updatedThread.metadata["inbound_auth_status"] = currentItem.metadata["inbound_auth_status"] ?? "unverified"
                updatedThread.updatedAt = now
            }

            let reconciled = currentItem.reconcilingIntoThread(at: now)
            let senderNodeID = reconciled.senderNodeID
            let senderDisplayName = reconciled.senderDisplayName
            let envelopeID = reconciled.envelopeID
            let inboxItemID = reconciled.id

            let anchorDate = reconciled.receivedAt
            let threadMarkedInbound = patchThreadWithInboundAnchors(
                updatedThread,
                inboxMetadata: reconciled.metadata,
                envelopeID: reconciled.envelopeID,
                now: now
            )
                .markingLastInboundEnvelope(
                    reconciled.envelopeID,
                    at: anchorDate
                )

            let audit = ExchangeAuditRecord(
                createdAt: now,
                threadID: threadUpdate.thread.id,
                direction: .inbound,
                category: .reconciledIntoThread,
                actor: .secretary,
                envelopeID: envelopeID,
                inboxItemID: inboxItemID,
                summary: "Reconciled an inbound federation envelope.",
                detail: continuation.decision.summary,
                externalEffect: .changed(description: "An inbound envelope was accepted into local exchange state."),
                relatedNodeID: senderNodeID,
                relatedDisplayName: senderDisplayName,
                metadata: Self.anchorMismatchAuditMetadata(from: threadMarkedInbound)
            )

            let draftsToSave = threadUpdate.draftsToSave
            let approvalsToSave = threadUpdate.approvalsToSave

            var mutableTurnsToSave = threadUpdate.turns

            let inboundReplyTurnForDMRouteLog: ExchangeTurn?
            if let inboundTurn = try await makeReconciledInboundTurnIfNeeded(
                item: reconciled,
                thread: threadMarkedInbound,
                pendingTurns: mutableTurnsToSave
            ) {
                mutableTurnsToSave.append(inboundTurn)
                inboundReplyTurnForDMRouteLog = inboundTurn
            } else {
                inboundReplyTurnForDMRouteLog = nil
            }

            let turnsToSave = mutableTurnsToSave
            let threadPersistFinal = threadMarkedInbound

            #if DEBUG
            if !resolvedFromFirstContactThreadCreation {
                let turnStr = turnsToSave.last?.id.uuidString ?? "none"
                exchFedServiceLog(
                    "[InboundReplyMerged] envelope=\(currentItem.envelopeID) thread=\(resolvedThread.id.uuidString) turn=\(turnStr)"
                )
            }
            #endif

            #if DEBUG
            if Self.routesIncomingItemAsDirectMessageSurface(reconciled),
               let inboundLog = inboundReplyTurnForDMRouteLog {
                exchFedServiceLog(
                    "[DMRoute][appendTurn] inboxItemID=\(inboxItemID.uuidString) threadID=\(threadPersistFinal.id.uuidString) " +
                        "turnID=\(inboundLog.id.uuidString) kind=\(inboundLog.kind.rawValue)"
                )
            }
            #endif

            try await store.performTransaction {
                try await store.saveInboxItem(reconciled)
                try await store.updateThread(threadPersistFinal)

                for draft in draftsToSave {
                    try await store.saveDraft(draft)
                }

                for approval in approvalsToSave {
                    try await store.saveApproval(approval)
                }

                for turn in turnsToSave {
                    try await store.appendTurn(turn)
                }

                try await store.appendAuditRecord(audit)
            }

            reconciledThreadIDs.append(threadPersistFinal.id)
            reconciledEnvelopeIDs.append(reconciled.envelopeID)
            if !isSuspiciousBinding, !isUnverifiedInbound {
                trustEligibleThreadIDs.append(threadUpdate.thread.id)
            }
            reconciledCount += 1
            #if DEBUG
            if Self.routesIncomingItemAsDirectMessageSurface(reconciled) {
                exchFedServiceLog(
                    "[DMRoute][reconciled] inboxItemID=\(reconciled.id.uuidString) threadID=\(threadPersistFinal.id.uuidString)"
                )
                let senderTrimmed = reconciled.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let sender = senderTrimmed.isEmpty ? "nil" : senderTrimmed
                exchFedServiceLog(
                    "[DMReceiveLive][reconciled] inboxItemID=\(reconciled.id.uuidString) threadID=\(threadPersistFinal.id.uuidString) sender=\(sender)"
                )
            }
            #endif
        }

        let reconciledThreadIDList = reconciledThreadIDs.map(\.uuidString).joined(separator: ",")
        refreshTraceFedLog(
            "[ReconcileResult] runID=federation-reconcile reconciled=\(reconciledCount) deferred=\(deferredCount) rejected=\(rejectedCount) threadIDs=\(reconciledThreadIDList) time=\(now)"
        )
        return ExchangeFederationReconcileResult(
            reconciledCount: reconciledCount,
            deferredCount: deferredCount,
            rejectedCount: rejectedCount,
            reconciledThreadIDs: reconciledThreadIDs,
            reconciledEnvelopeIDs: reconciledEnvelopeIDs,
            trustEligibleThreadIDs: trustEligibleThreadIDs
        )
    }

    public func recentAudit(
        threadID: ExchangeThread.ID?,
        limit: Int
    ) async throws -> [ExchangeAuditRecord] {
        try await store.listAuditRecords(
            filter: .init(
                threadID: threadID,
                limit: limit
            )
        )
    }
}

private extension ExchangeDefaultFederationService {
    /// Ordering parent normalized to empty means first-contact inbound path.
    static func isParentlessForFirstContactInboxItem(_ item: ExchangeInboxItem) -> Bool {
        let orderParent = item.ordering.parentEnvelopeID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !orderParent.isEmpty { return false }
        let metaParent = item.metadata["parent_envelope_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return metaParent.isEmpty
    }

    enum SendOutcome {
        case sent
        case acknowledged
        case deferred
        case failed
        case untouched
    }

    struct ThreadUpdate {
        let thread: ExchangeThread
        let turns: [ExchangeTurn]
        let draftsToSave: [ExchangeMessageDraft]
        let approvalsToSave: [ExchangeApproval]
    }

    // MARK: - Execution basis helpers

    func targetExecutionID(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile?
    ) -> String {
        if let profileNodeID = publicProfile?.nodeID.exchangeNilIfBlank {
            return profileNodeID
        }

        if let selectedProfileID = thread.selectedPublicProfileID?.exchangeNilIfBlank,
           let attached = counterparty.publicProfile,
           attached.id == selectedProfileID,
           let attachedNodeID = attached.nodeID.exchangeNilIfBlank {
            return attachedNodeID
        }

        return counterparty.identity?.nodeID?.exchangeNilIfBlank ?? counterparty.id
    }

    func resolvedExecutionPublicProfile(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty
    ) async throws -> ExchangePublicNodeProfile? {
        if let selectedPublicProfileID = thread.selectedPublicProfileID?.exchangeNilIfBlank {
            if let attached = counterparty.publicProfile,
               attached.id == selectedPublicProfileID {
                return attached
            }

            if let fetched = try await fetchPublicProfile(
                id: selectedPublicProfileID,
                counterpartyID: counterparty.id
            ) {
                return fetched
            }

            return nil
        }

        return counterparty.publicProfile
    }

    func fetchPublicProfile(
        id: String,
        counterpartyID: ExchangeCounterparty.ID
    ) async throws -> ExchangePublicNodeProfile? {
        if let counterparty = try await store.fetchCounterparty(id: counterpartyID),
           let profile = counterparty.publicProfile,
           profile.id == id {
            return profile
        }
        return nil
    }

    /// Hydrated seller/public profile when available; otherwise a **minimal synthetic** execution basis
    /// for inbound thread **continuations** only (see `ExchangePolicyEngine.isExistingInboundContinuationReplySend`).
    func resolvedExecutionProfileForOutboundEnvelope(
        hydratedProfile: ExchangePublicNodeProfile?,
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty
    ) -> ExchangePublicNodeProfile? {
        if let hydratedProfile { return hydratedProfile }
        guard ExchangePolicyEngine.isExistingInboundContinuationReplySend(thread: thread, counterparty: counterparty) else {
            return nil
        }
        return syntheticContinuationPublicProfile(thread: thread, counterparty: counterparty)
    }

    func syntheticContinuationPublicProfile(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty
    ) -> ExchangePublicNodeProfile {
        let trimmedSelectedProfile = thread.selectedPublicProfileID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let id: String
        if !trimmedSelectedProfile.isEmpty {
            id = trimmedSelectedProfile
        } else if let pp = counterparty.publicProfile {
            let attached = pp.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !attached.isEmpty {
                id = attached
            } else {
                id = "inbound-continuation-\(counterparty.id)"
            }
        } else {
            id = "inbound-continuation-\(counterparty.id)"
        }
        let nodeID = (counterparty.identity?.nodeID ?? counterparty.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ExchangePublicNodeProfile(
            id: id,
            nodeID: nodeID,
            counterpartyID: counterparty.id,
            displayName: counterparty.displayName,
            reachability: ExchangePublicNodeProfile.ReachabilityPolicy(
                accessMode: .direct,
                acceptingInbound: true,
                intentCategoryPolicy: .permissive,
                disclosureCeiling: .balanced
            ),
            metadata: ["synthetic_continuation_execution_basis": "true"]
        )
    }

    // MARK: - Policy / error mapping

    func mapPolicyBlockToFederationError(
        policy: ExchangePolicyEngine.DecisionSet,
        counterparty: ExchangeCounterparty
    ) -> ExchangeFederationError {
        switch policy.recipientPosture.status {
        case .unknown:
            if threadApprovalStillRequired(policy: policy) {
                return .approvalRequired
            }
            return .runtimeBlocked(reason: policy.federationExecution.rationale)

        case .allowedDirect, .allowedIntroPreferred, .allowedViaIntroduction:
            if threadApprovalStillRequired(policy: policy) {
                return .approvalRequired
            }
            return .runtimeBlocked(reason: policy.federationExecution.rationale)

        case .introRequired:
            return .introductionRequired(counterpartyID: counterparty.id)

        case .trustTooLow:
            return .trustFloorMismatch(
                required: counterparty.publicProfile?.reachability.minimumTrustLevel,
                actual: counterparty.trust.level
            )

        case .categoryMismatch:
            return .postureBlocked(reason: "Recipient public profile categories do not match this request.")

        case .mutualFitRequired:
            return .postureBlocked(reason: "Recipient requires stronger mutual or trusted fit before contact.")

        case .modeNotAllowed:
            return .postureBlocked(reason: "Recipient public profile does not allow this coordination mode.")

        case .intentKindNotAllowed:
            return .postureBlocked(reason: "Recipient public profile does not allow this kind of request.")

        case .audienceNotAllowed:
            return .postureBlocked(reason: "Recipient public profile does not allow this audience kind.")

        case .closed:
            return .postureBlocked(reason: "Recipient is closed to new contact.")

        case .notAcceptingInbound:
            return .postureBlocked(reason: "Recipient is not currently accepting inbound coordination.")
        }
    }

    func threadApprovalStillRequired(
        policy: ExchangePolicyEngine.DecisionSet
    ) -> Bool {
        policy.approval.required && !policy.advancement.allowed
    }

    func postureStatusBlocksExecution(
        _ status: ExchangePolicyEngine.RecipientPostureDecision.Status
    ) -> Bool {
        switch status {
        case .unknown, .allowedDirect, .allowedIntroPreferred, .allowedViaIntroduction:
            return false
        case .introRequired,
             .trustTooLow,
             .categoryMismatch,
             .mutualFitRequired,
             .modeNotAllowed,
             .intentKindNotAllowed,
             .audienceNotAllowed,
             .closed,
             .notAcceptingInbound:
            return true
        }
    }

    func postureBlockReason(
        from status: ExchangePolicyEngine.RecipientPostureDecision.Status
    ) -> ExchangeFederationSendEligibility.PostureBlockReason? {
        switch status {
        case .unknown:
            return nil
        case .allowedDirect, .allowedIntroPreferred, .allowedViaIntroduction:
            return nil
        case .introRequired:
            return .introductionRequired
        case .trustTooLow:
            return .trustTooLow
        case .categoryMismatch:
            return .categoryMismatch
        case .mutualFitRequired:
            return .mutualFitRequired
        case .modeNotAllowed, .intentKindNotAllowed, .audienceNotAllowed:
            return .categoryMismatch
        case .closed:
            return .accessClosed
        case .notAcceptingInbound:
            return .notAcceptingInbound
        }
    }

    func postureBlockReason(
        from error: ExchangeEnvelopeServiceError
    ) -> ExchangeFederationSendEligibility.PostureBlockReason? {
        switch error {
        case .missingRecipientRoute:
            return .routeRequiredButMissing
        case .routeNotAllowedByPosture:
            return .directContactNotAllowed
        case .introductionRequired:
            return .introductionRequired
        case .contactClosed:
            return .accessClosed
        case .contactNotAcceptingInbound:
            return .notAcceptingInbound
        case .executionBasisMismatch:
            return .categoryMismatch
        }
    }

    func mapE2EESendBlockedToFederationError(
        _ error: ExchangePrivateE2EESendBlockedError
    ) -> ExchangeFederationError {
        ExchangeFederationPrivateTextE2EE.logSendBlocked(reason: error.blockedReason)
        return .e2eeSendBlocked(internalReason: error.blockedReason)
    }

    func e2eeSendBlockedEligibility(
        from error: ExchangePrivateE2EESendBlockedError,
        counterparty: ExchangeCounterparty,
        policy: ExchangePolicyEngine.DecisionSet
    ) -> ExchangeFederationSendEligibility {
        ExchangeFederationPrivateTextE2EE.logSendBlocked(reason: error.blockedReason)
        return ExchangeFederationSendEligibility.fromCounterpartyDefaults(
            counterparty,
            reason: ExchangePrivateE2EESendBlockedError.userFacingMessage,
            isEligible: false,
            disclosureAllowed: true,
            requiresApproval: policy.approval.required,
            postureBlocked: false,
            postureBlockReason: nil,
            resolvedRoute: nil
        )
    }

    func terminalFailOutboxForE2EESendBlocked(
        item: ExchangeOutboxItem,
        thread: ExchangeThread,
        draft: ExchangeMessageDraft,
        executionPublicProfile: ExchangePublicNodeProfile?,
        error: ExchangePrivateE2EESendBlockedError,
        now: Date
    ) async throws -> (SendOutcome, outboundRelayConfirmedThreadID: UUID?) {
        let internalReason = error.blockedReason
        ExchangeFederationPrivateTextE2EE.logSendBlocked(reason: internalReason)

        var failed = item.failingTerminally(
            errorCode: ExchangePrivateE2EESendBlockedError.errorCode,
            note: ExchangePrivateE2EESendBlockedError.userFacingMessage,
            externalEffect: .none,
            at: now
        )
        failed.metadata["e2ee_blocked_reason"] = internalReason

        let audit = ExchangeAuditRecord.failed(
            direction: .outbound,
            threadID: failed.threadID,
            envelopeID: failed.envelopeID,
            outboxItemID: failed.id,
            summary: "Outbound delivery could not be encrypted securely.",
            detail: "\(ExchangePrivateE2EESendBlockedError.errorCode) reason=\(internalReason)",
            externalEffect: .none,
            relatedNodeID: failed.targetNodeID,
            relatedDisplayName: try await counterpartyDisplayName(for: failed.targetNodeID),
            createdAt: now
        )

        let terminalFailed = failed
        try await store.performTransaction {
            try await store.saveOutboxItem(terminalFailed)
            try await store.appendAuditRecord(audit)
        }

        logSendOutboxFailure(
            branch: "e2ee_send_blocked",
            thread: thread,
            draft: draft,
            outboxItem: failed,
            publicProfile: executionPublicProfile,
            selectedCounterpartyID: thread.selectedCounterpartyID,
            selectedPublicProfileID: thread.selectedPublicProfileID,
            errorCode: ExchangePrivateE2EESendBlockedError.errorCode,
            note: failed.deliveryState.note,
            rationale: internalReason
        )

        return (.failed, nil)
    }

    func mapEnvelopeErrorToFederationError(
        _ error: ExchangeEnvelopeServiceError,
        counterpartyID: ExchangeCounterparty.ID
    ) -> ExchangeFederationError {
        switch error {
        case .missingRecipientRoute:
            return .noResolvedRoute(counterpartyID: counterpartyID)
        case .routeNotAllowedByPosture:
            return .postureBlocked(reason: envelopeEligibilityReason(error))
        case .introductionRequired:
            return .introductionRequired(counterpartyID: counterpartyID)
        case .contactClosed, .contactNotAcceptingInbound:
            return .postureBlocked(reason: envelopeEligibilityReason(error))
        case .executionBasisMismatch(let reason):
            return .runtimeBlocked(reason: reason)
        }
    }

    // MARK: - Inbound continuation (bounded interpretation; no drafts/approvals)

    /// Applies heuristic inbound interpretation (`ExchangeThreadContinuationCoordinator`) **without**
    /// composing drafts or approvals. Reply drafting is owned exclusively by Second Half / agency
    /// (`ExchangeFacade.reconcileInbox` → `runSecondHalfAfterThreadMutation`).
    func applyInboundContinuation(
        _ evaluation: ExchangeThreadContinuationCoordinator.Evaluation,
        to thread: ExchangeThread,
        counterparty: ExchangeCounterparty?,
        now: Date
    ) async throws -> ThreadUpdate {
        _ = counterparty // Reserved for locality / future auditing; drafts are suppressed.

        let expectationThread = thread.settingExpectation(
            evaluation.expectation,
            at: now
        )

        logInboundLegacyContinuationSuppressed(
            threadID: expectationThread.id,
            decisionRaw: evaluation.decision.action.rawValue,
            suppressedDrafting: suppressedDraftBranches.contains(evaluation.decision.action),
            suppressedTerminalResolution: suppressedTerminalBranches.contains(evaluation.decision.action)
        )

        let updatedThread = applyingSuppressedLegacyContinuationRecording(
            to: expectationThread,
            evaluation: evaluation,
            now: now
        )

        return ThreadUpdate(
            thread: updatedThread,
            turns: [],
            draftsToSave: [],
            approvalsToSave: []
        )
    }

    /// Persist a single visible inbound turn after item->thread reconciliation.
    /// Idempotent across repeated reconcile runs via source inbox/envelope markers.
    func makeReconciledInboundTurnIfNeeded(
        item: ExchangeInboxItem,
        thread: ExchangeThread,
        pendingTurns: [ExchangeTurn]
    ) async throws -> ExchangeTurn? {
        let localNodeID = (try? await identityService.localIdentity().nodeID.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        let senderNodeID = item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let recipientNodeID = item.metadata["recipient_node_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localOutboxEcho = (try await store.fetchOutboxItemByEnvelopeID(item.envelopeID)) != nil
        if (!localNodeID.isEmpty && !senderNodeID.isEmpty && senderNodeID == localNodeID)
            || (!localNodeID.isEmpty && !recipientNodeID.isEmpty && recipientNodeID != localNodeID)
            || localOutboxEcho {
            let reason: String
            if !localNodeID.isEmpty && !senderNodeID.isEmpty && senderNodeID == localNodeID {
                reason = "self_sender"
            } else if !localNodeID.isEmpty && !recipientNodeID.isEmpty && recipientNodeID != localNodeID {
                reason = "recipient_mismatch"
            } else {
                reason = "local_outbox_echo"
            }
            refreshTraceFedLog(
                "[InboundTurnSuppressed] reason=\(reason) inboxItemID=\(item.id.uuidString) envelopeID=\(item.envelopeID) threadID=\(thread.id.uuidString) senderNodeID=\(senderNodeID) localNodeID=\(localNodeID)"
            )
            #if DEBUG
            ExchangeBilateralConversationDebugTrace.logInboundTurnPersisted(
                thread: thread,
                envelopeID: item.envelopeID,
                turnID: nil,
                turnKind: nil,
                bodyLength: nil,
                suppressedReason: reason
            )
            #endif
            return nil
        }

        let inboxID = item.id.uuidString
        let envelopeID = item.envelopeID.trimmingCharacters(in: .whitespacesAndNewlines)

        func isSameInboundSource(_ turn: ExchangeTurn) -> Bool {
            if turn.metadata["source_inbox_item_id"] == inboxID { return true }
            if !envelopeID.isEmpty && turn.metadata["source_envelope_id"] == envelopeID { return true }
            if !envelopeID.isEmpty && turn.externalReference == envelopeID { return true }
            return false
        }

        if pendingTurns.contains(where: isSameInboundSource) {
            #if DEBUG
            ExchangeBilateralConversationDebugTrace.logInboundTurnPersisted(
                thread: thread,
                envelopeID: item.envelopeID,
                turnID: nil,
                turnKind: nil,
                bodyLength: nil,
                suppressedReason: "duplicate_pending"
            )
            #endif
            return nil
        }

        let existingTurns = try await store.listTurns(
            threadID: thread.id,
            limit: nil,
            ascending: true
        )
        if existingTurns.contains(where: isSameInboundSource) {
            #if DEBUG
            ExchangeBilateralConversationDebugTrace.logInboundTurnPersisted(
                thread: thread,
                envelopeID: item.envelopeID,
                turnID: nil,
                turnKind: nil,
                bodyLength: nil,
                suppressedReason: "duplicate_existing"
            )
            #endif
            return nil
        }

        let subjectPreviewRaw = item.metadata["subject_preview"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyPreviewRaw = item.metadata["body_preview"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleSummaryRaw = item.visibleSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectPreview = subjectPreviewRaw.map { ExchangeUserFacingCopySanitizer.cleanReceivedFederationBody($0).cleaned }
        let bodyPreview = bodyPreviewRaw.map { ExchangeUserFacingCopySanitizer.cleanReceivedFederationBody($0).cleaned }
        let visibleSummary = ExchangeUserFacingCopySanitizer.cleanReceivedFederationBody(visibleSummaryRaw).cleaned

        let summary = firstNonBlankInboundText(
            subjectPreview,
            bodyPreview,
            visibleSummary
        ) ?? "Inbound message received."

        let detail = firstNonBlankInboundText(
            bodyPreview,
            subjectPreview,
            visibleSummary
        )
        #if DEBUG
        let originalForLog = detail ?? summary
        let cleanedForLog = ExchangeUserFacingCopySanitizer.cleanReceivedFederationBody(originalForLog)
        refreshTraceFedLog(
            "[ReceivedBodyClean] envelopeID=\(envelopeID) threadID=\(thread.id.uuidString) originalLen=\(originalForLog.count) cleanLen=\(cleanedForLog.cleaned.count) removedInternalScaffold=\(cleanedForLog.removedInternalScaffold) bodyPrefix=\(textPreview(cleanedForLog.cleaned, limit: 120))"
        )
        #endif

        var metadata: [String: String] = [
            "source": "federation_reconcile_inbound",
            "source_inbox_item_id": inboxID,
            "source_envelope_id": envelopeID,
            "payload_kind": item.metadata["payload_kind"] ?? "message"
        ]

        if let parentEnvelopeID = item.ordering.parentEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !parentEnvelopeID.isEmpty {
            metadata["source_parent_envelope_id"] = parentEnvelopeID
        }
        if let senderNodeID = item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !senderNodeID.isEmpty {
            metadata["source_sender_node_id"] = senderNodeID
        }

        for key in DirectMessageAttachmentMetadata.federationMetadataKeys {
            guard let raw = item.metadata[key] else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            metadata[key] = trimmed
        }

        let turn = ExchangeTurn(
            threadID: thread.id,
            createdAt: item.ordering.senderTimestamp ?? item.receivedAt,
            actor: .counterparty,
            kind: .replyReceived,
            summary: textPreview(summary, limit: 280),
            detail: detail.map { textPreview($0, limit: 1200) },
            visibility: .userVisible,
            externalReference: envelopeID.isEmpty ? nil : envelopeID,
            metadata: metadata
        )
        #if DEBUG
        let persistedBodyLength = (detail ?? summary).count
        ExchangeBilateralConversationDebugTrace.logInboundTurnPersisted(
            thread: thread,
            envelopeID: item.envelopeID,
            turnID: turn.id,
            turnKind: turn.kind.rawValue,
            bodyLength: persistedBodyLength,
            suppressedReason: nil
        )
        #endif
        return turn
    }

    func firstNonBlankInboundText(_ values: String?...) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private var suppressedDraftBranches: Set<ExchangeContinuationDecision.Action> {
        [.continueWithDraft, .requestApprovalForReply]
    }

    private var suppressedTerminalBranches: Set<ExchangeContinuationDecision.Action> {
        [.resolved]
    }

    private func applyingSuppressedLegacyContinuationRecording(
        to thread: ExchangeThread,
        evaluation: ExchangeThreadContinuationCoordinator.Evaluation,
        now: Date
    ) -> ExchangeThread {
        let visible = evaluation.decision.summary
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var md = thread.metadata
        md["legacyContinuationDecision"] = evaluation.decision.action.rawValue
        md["legacyContinuationSuppressed"] = "true"

        let ib = evaluation.inbound.summary
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if ib.isEmpty == false {
            if ib.count <= 560 {
                md["legacyContinuationInboundSummary"] = ib
            } else {
                md["legacyContinuationInboundSummary"] = String(ib.prefix(557)) + "…"
            }
        }

        if let ratt = evaluation.decision.rationale?.trimmingCharacters(in: .whitespacesAndNewlines),
           ratt.isEmpty == false {
            if ratt.count <= 560 {
                md["legacyContinuationRationale"] = ratt
            } else {
                md["legacyContinuationRationale"] = String(ratt.prefix(557)) + "…"
            }
        }

        md["legacyContinuationRecordedAt"] = isoInstantString(now)

        var copy = thread
        copy.metadata = md
        copy.updatedAt = now

        if visible.isEmpty {
            return copy
        }

        return copy.withUpdatedState(
            copy.state,
            at: now,
            visibleSummary: visible
        )
    }

    private func isoInstantString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// Breadcrumb when legacy heuristic decisions are recorded without drafting (Second Half/agency owns replies).
    /// Printed only when `ExchangeDefaultFederationService` debug logging is compiled in.
    private func logInboundLegacyContinuationSuppressed(
        threadID: ExchangeThread.ID,
        decisionRaw: String,
        suppressedDrafting: Bool,
        suppressedTerminalResolution: Bool
    ) {
        exchFedServiceLog(
            "legacyContinuationSuppressed | threadID=\(threadID.uuidString) | " +
                "decision=\(decisionRaw) | " +
                "suppressedDrafting=\(suppressedDrafting) | suppressedTerminalResolved=\(suppressedTerminalResolution) | " +
                "reason=modern_second_half_agency_owns_inbound_reply"
        )
    }

    // MARK: - conversation_surface routing (Phase 1)

    private enum InboundConversationCorrelationPolicy: Equatable {
        case legacy
        /// Exchange desk; excludes DM containers. Optional counterparty filter when sender id is known.
        case exchangeSurface(senderNodeID: String?)
        case directMessageSurface(senderNodeID: String)
    }

    private static let conversationSurfaceMetadataKey = "conversation_surface"
    private static let conversationSurfaceDirectMessageValue = "direct_message"
    private static let conversationSurfaceExchangeThreadValue = "exchange_thread"
    private static let conversationSurfaceContactValue = "contact"
    private static let conversationSurfaceSocialConnectionValue = "social_connection"

    private static func normalizedInboundConversationSurface(_ item: ExchangeInboxItem) -> String? {
        let raw = item.metadata[Self.conversationSurfaceMetadataKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if raw == Self.conversationSurfaceDirectMessageValue { return Self.conversationSurfaceDirectMessageValue }
        if raw == Self.conversationSurfaceExchangeThreadValue { return Self.conversationSurfaceExchangeThreadValue }
        if raw == Self.conversationSurfaceContactValue { return Self.conversationSurfaceContactValue }
        if raw == Self.conversationSurfaceSocialConnectionValue { return Self.conversationSurfaceSocialConnectionValue }
        return nil
    }

    /// Phase 1 surface-first routing: `conversation_surface=direct_message` uses the DM resolver only,
    /// not exchange ordering-gap / parent-outbox / first-contact inbound thread creation.
    private static func routesIncomingItemAsDirectMessageSurface(_ item: ExchangeInboxItem) -> Bool {
        Self.normalizedInboundConversationSurface(item) == Self.conversationSurfaceDirectMessageValue
    }

    /// Phase 1: upsert a minimal `ExchangeCounterparty` for inbound DM routing/open (no trust edge).
    func ensureMinimalCounterpartyFromInboundDirectMessageIfNeeded(
        item: ExchangeInboxItem,
        now: Date
    ) async throws {
        guard Self.routesIncomingItemAsDirectMessageSurface(item) else { return }
        try await ensureMinimalInboundSenderCounterpartyShellIfNeeded(
            item: item,
            now: now,
            debugReason: "inbound_direct_message"
        )
    }

    /// Upserts a minimal counterparty for the inbound sender when missing (no trust edge).
    func ensureMinimalInboundSenderCounterpartyShellIfNeeded(
        item: ExchangeInboxItem,
        now: Date,
        debugReason: String
    ) async throws {
        let sender = item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sender.isEmpty else { return }
        if try await store.fetchCounterparty(id: sender) != nil {
            #if DEBUG
            exchFedServiceLog(
                "[InboundCounterpartyShell][exists] senderNodeID=\(sender) reason=\(debugReason)"
            )
            #endif
            return
        }
        let created = ExchangeRemoteDiscoveryCacheMetadata.tagInboundDMCounterparty(
            ExchangeCounterparty(
                id: sender,
                createdAt: now,
                updatedAt: now,
                kind: .secretaryNode,
                displayName: item.senderDisplayName ?? sender,
                source: .relayNetwork,
                identity: .init(
                    nodeID: sender,
                    publicKeyID: nil,
                    verification: .unverified
                ),
                trust: .unverified,
                status: .active
            ),
            now: now
        )
        try await store.upsertCounterparties([created])
        #if DEBUG
        exchFedServiceLog(
            "[InboundCounterpartyShell][created] senderNodeID=\(sender) reason=\(debugReason)"
        )
        #endif
    }

    private static func deterministicLatestThread(from candidates: [ExchangeThread]) -> ExchangeThread? {
        candidates.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// DM-only inbound container: durable DM flag, not an inbound-first-contact row, counterparty is remote sender.
    private static func isInboundDirectMessageSurfaceContainer(
        thread: ExchangeThread,
        senderNodeID: String
    ) -> Bool {
        let trimmedSender = senderNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSender.isEmpty else { return false }
        guard thread.metadata["direct_message_thread"] == "true" else { return false }
        guard thread.metadata["inbound_thread"] != "true" else { return false }
        guard thread.metadata["archived"] != "true" else { return false }
        let sel = thread.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard sel == trimmedSender else { return false }
        guard thread.intent.kind == .message else { return false }
        return true
    }

    private static func applyConversationCorrelationPolicy(
        threads: [ExchangeThread],
        policy: InboundConversationCorrelationPolicy
    ) -> [ExchangeThread] {
        switch policy {
        case .legacy:
            return threads
        case .exchangeSurface(let sender):
            var out = threads.filter { $0.metadata["direct_message_thread"] != "true" }
            let trimmed = sender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                out = out.filter { t in
                    let sel = t.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return sel == trimmed
                }
            }
            return out
        case .directMessageSurface(let sender):
            return threads.filter { Self.isInboundDirectMessageSurfaceContainer(thread: $0, senderNodeID: sender) }
        }
    }

    #if DEBUG
    private static func logInboundResolveThreadRoutingExit(
        item: ExchangeInboxItem,
        matched: ExchangeThread?,
        matchReason: String
    ) {
        let inboxShort = String(item.id.uuidString.prefix(8))
        let senderFull = item.senderNodeID ?? ""
        let senderShort = senderFull.isEmpty ? "nil" : String(senderFull.prefix(8))
        let payloadKind = item.metadata["payload_kind"] ?? "nil"
        let surface = item.metadata[Self.conversationSurfaceMetadataKey] ?? "nil"
        let orderParent = item.ordering.parentEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let metaParent = item.metadata["parent_envelope_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parentPresent = (!orderParent.isEmpty || !metaParent.isEmpty) ? "yes" : "no"
        let threadShort = matched.map { String($0.id.uuidString.prefix(8)) } ?? "nil"
        let isDM = matched.map { $0.metadata["direct_message_thread"] == "true" ? "true" : "false" } ?? "nil"
        let isInbound = matched.map { $0.metadata["inbound_thread"] == "true" ? "true" : "false" } ?? "nil"
        exchFedServiceLog(
            "[InboundResolveExit] inbox=\(inboxShort) sender=\(senderShort) payload_kind=\(payloadKind) conversation_surface=\(surface) parentPresent=\(parentPresent) thread=\(threadShort) reason=\(matchReason) dm=\(isDM) inbound=\(isInbound)"
        )
    }
    #endif

    func resolveThreadForInboxItem(
        _ item: ExchangeInboxItem
    ) async throws -> ExchangeThread? {
        let resolved = try await resolveThreadForInboxItemTracing(item)
        #if DEBUG
        let t = resolved.thread
        let dmFlag = t.map { $0.metadata["direct_message_thread"] == "true" ? "true" : "false" } ?? "nil"
        let inboundFlag = t.map { $0.metadata["inbound_thread"] == "true" ? "true" : "false" } ?? "nil"
        exchFedServiceLog(
            "[DMRoute][resolveResult] inboxItemID=\(item.id.uuidString) result=\(t != nil ? "thread" : "nil") " +
                "threadID=\(t?.id.uuidString ?? "nil") reason=\(resolved.reason) dmFlag=\(dmFlag) inboundFlag=\(inboundFlag)"
        )
        Self.logInboundResolveThreadRoutingExit(
            item: item,
            matched: resolved.thread,
            matchReason: resolved.reason
        )
        #endif
        return resolved.thread
    }

    private func resolveThreadForInboxItemTracing(
        _ item: ExchangeInboxItem
    ) async throws -> (thread: ExchangeThread?, reason: String) {
        func logCorrelation(
            matched: ExchangeThread?,
            source: String,
            decision: String
        ) {
            #if DEBUG
            let parent = item.ordering.parentEnvelopeID ?? item.metadata["parent_envelope_id"] ?? "nil"
            let conversationID = item.metadata["conversation_id"] ?? "nil"
            let rootEnvelopeID = item.metadata["root_envelope_id"] ?? "nil"
            let originalReq = item.metadata["original_requester_envelope_id"] ?? "nil"
            let result = matched != nil ? "matchedExisting" : "unresolved"
            exchFedServiceLog(
                "[InboundThreadCorrelation] envelope=\(item.envelopeID) result=\(result) reason=\(source) thread=\(matched?.id.uuidString ?? "nil") parentEnvelopeID=\(parent) conversationID=\(conversationID) rootEnvelopeID=\(rootEnvelopeID) originalRequesterEnvelopeID=\(originalReq) decision=\(decision)"
            )
            if let matched {
                exchFedServiceLog(
                    "[InboundThreadCorrelationHit] source=\(source) envelope=\(item.envelopeID) thread=\(matched.id.uuidString)"
                )
            }
            #endif
        }

        func logCorrelationMiss(_ item: ExchangeInboxItem, reason: String) {
            #if DEBUG
            let keys = item.metadata.keys.sorted().joined(separator: ",")
            exchFedServiceLog(
                "[InboundThreadCorrelationMiss] reason=\(reason) envelope=\(item.envelopeID) metadataKeys=\(keys) conversationID=\(item.metadata["conversation_id"] ?? "nil") rootEnvelopeID=\(item.metadata["root_envelope_id"] ?? "nil") originalRequesterEnvelopeID=\(item.metadata["original_requester_envelope_id"] ?? "nil") parentEnvelopeID=\(item.ordering.parentEnvelopeID ?? item.metadata["parent_envelope_id"] ?? "nil") selectedOfferID=\(item.metadata["selected_offer_id"] ?? item.metadata["matched_offer_id"] ?? "nil") publicProfileID=\(item.metadata["public_profile_id"] ?? item.metadata["selected_public_profile_id"] ?? "nil") sender=\(item.senderNodeID ?? "nil") recipient=\(item.metadata["recipient_node_id"] ?? "nil")"
            )
            #endif
        }

        #if DEBUG
        do {
            let parentSnap = item.ordering.parentEnvelopeID ?? item.metadata["parent_envelope_id"] ?? "nil"
            exchFedServiceLog(
                "[InboundThreadCorrelationAttempt] threadID=\(item.threadID?.uuidString ?? "nil") envelope=\(item.envelopeID) " +
                    "conversation=\(item.metadata["conversation_id"] ?? "nil") root=\(item.metadata["root_envelope_id"] ?? "nil") " +
                    "original=\(item.metadata["original_requester_envelope_id"] ?? "nil") parent=\(parentSnap)"
            )
        }
        #endif

        #if DEBUG
        do {
            let sNorm = Self.normalizedInboundConversationSurface(item) ?? "nil"
            let snd = item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let par = item.ordering.parentEnvelopeID ?? item.metadata["parent_envelope_id"] ?? "nil"
            let willEnterDM =
                Self.normalizedInboundConversationSurface(item) == Self.conversationSurfaceDirectMessageValue
                && !snd.isEmpty
            exchFedServiceLog(
                "[DMRoute][resolveEnter] inboxItemID=\(item.id.uuidString) surface=\(sNorm) " +
                    "willEnterDMBranch=\(willEnterDM) senderNodeID=\(snd) parentEnvelopeID=\(par)"
            )
        }
        #endif

        if ExchangeContactSignalClassifier.isInboundContactRequest(item) {
            logCorrelationMiss(item, reason: "contact_signal_suppress_thread_resolution")
            logCorrelation(matched: nil, source: "contactSignal", decision: "skipThread")
            return (nil, "contact_signal_suppress_thread_resolution")
        }

        if Self.normalizedInboundConversationSurface(item) == Self.conversationSurfaceDirectMessageValue {
            let senderRaw = item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if senderRaw.isEmpty {
                logCorrelationMiss(item, reason: "direct_message_missing_sender")
                logCorrelation(matched: nil, source: "directMessageSurface", decision: "defer")
                return (nil, "direct_message_missing_sender")
            }
            return try await resolveDirectMessageConversationSurfaceInboxThread(
                item,
                senderNodeID: senderRaw,
                logCorrelation: logCorrelation
            )
        }

        if let threadID = item.threadID {
            #if DEBUG
            exchFedServiceLog(
                "reconcileInbox.branch | continuationByThreadID | inboxItemID=\(item.id.uuidString) | " +
                    "threadID=\(threadID.uuidString)"
            )
            #endif
            let resolved = try await store.fetchThread(id: threadID)
            logCorrelation(matched: resolved, source: "directThreadID", decision: resolved == nil ? "defer" : "append")
            return (resolved, "directThreadID")
        }

        let orderParent = item.ordering.parentEnvelopeID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metaParent = item.metadata["parent_envelope_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parentEnvelopeID = [orderParent, metaParent]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        if let parentEnvelopeID,
           let outbox = try await store.fetchOutboxItemByEnvelopeID(parentEnvelopeID),
           let resolved = try await store.fetchThread(id: outbox.threadID) {
            let skipExchangeParentIntoDM =
                Self.normalizedInboundConversationSurface(item) == Self.conversationSurfaceExchangeThreadValue
                && resolved.metadata["direct_message_thread"] == "true"
            if !skipExchangeParentIntoDM {
                #if DEBUG
                exchFedServiceLog(
                    "reconcileInbox.branch | continuationByParentEnvelope | inboxItemID=\(item.id.uuidString) | " +
                        "threadID=\(outbox.threadID.uuidString)"
                )
                #endif
                logCorrelation(matched: resolved, source: "parentEnvelopeIDOutbox", decision: "append")
                return (resolved, "parentEnvelopeIDOutbox")
            }
        }

        let correlationPolicy: InboundConversationCorrelationPolicy = {
            if Self.normalizedInboundConversationSurface(item) == Self.conversationSurfaceExchangeThreadValue {
                let trimmedSid = item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let sid: String? = trimmedSid.isEmpty ? nil : trimmedSid
                return .exchangeSurface(senderNodeID: sid)
            }
            return .legacy
        }()

        if let correlated = try await findThreadByInboundConversationCorrelation(item, policy: correlationPolicy) {
            logCorrelation(matched: correlated.thread, source: correlated.source, decision: "append")
            return (correlated.thread, correlated.source)
        }

        if let transactional = try await findTransactionalSupplierReplyContinuationThread(for: item) {
            logCorrelation(matched: transactional, source: "transactionalAwaitingSupplierReply", decision: "append")
            return (transactional, "transactionalAwaitingSupplierReply")
        }

        if Self.isParentlessForFirstContactInboxItem(item) {
            if let continued = try await findExistingInboundContinuationThread(for: item) {
                #if DEBUG
                exchFedServiceLog(
                    "reconcileInbox.branch | continuationByCounterpartyOfferProfile | " +
                        "inboxItemID=\(item.id.uuidString) | threadID=\(continued.id.uuidString)"
                )
                #endif
                logCorrelation(matched: continued, source: "counterpartyOfferProfile", decision: "append")
                return (continued, "counterpartyOfferProfile")
            }
        }

        logCorrelationMiss(item, reason: "noMatchingThreadOrAnchor")
        logCorrelation(matched: nil, source: "noCorrelationAnchors", decision: "createNew")
        #if DEBUG
        exchFedServiceLog(
            "[InboundThreadCorrelation] envelope=\(item.envelopeID) result=createNew reason=noCorrelationAnchors thread=nil"
        )
        #endif
        return (nil, "noCorrelationAnchors")
    }

    private func resolveDirectMessageConversationSurfaceInboxThread(
        _ item: ExchangeInboxItem,
        senderNodeID: String,
        logCorrelation: (ExchangeThread?, String, String) -> Void
    ) async throws -> (thread: ExchangeThread?, reason: String) {
        if let threadID = item.threadID,
           let resolved = try await store.fetchThread(id: threadID),
           Self.isInboundDirectMessageSurfaceContainer(thread: resolved, senderNodeID: senderNodeID) {
            logCorrelation(resolved, "directThreadIDValidatedDM", "append")
            return (resolved, "directThreadIDValidatedDM")
        }

        let orderParent = item.ordering.parentEnvelopeID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let metaParent = item.metadata["parent_envelope_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parentEnvelopeID = [orderParent, metaParent]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        if let parentEnvelopeID,
           let outbox = try await store.fetchOutboxItemByEnvelopeID(parentEnvelopeID),
           let resolved = try await store.fetchThread(id: outbox.threadID),
           Self.isInboundDirectMessageSurfaceContainer(thread: resolved, senderNodeID: senderNodeID) {
            #if DEBUG
            exchFedServiceLog(
                "reconcileInbox.branch | dmSurfaceParentEnvelope | inboxItemID=\(item.id.uuidString) | " +
                    "threadID=\(outbox.threadID.uuidString)"
            )
            #endif
            logCorrelation(resolved, "parentEnvelopeIDOutboxDM", "append")
            return (resolved, "parentEnvelopeIDOutboxDM")
        }

        #if DEBUG
        if let pid = parentEnvelopeID, !pid.isEmpty {
            var logIgnoredParent = true
            if let outbox = try await store.fetchOutboxItemByEnvelopeID(pid),
               let parentThread = try await store.fetchThread(id: outbox.threadID),
               Self.isInboundDirectMessageSurfaceContainer(thread: parentThread, senderNodeID: senderNodeID) {
                logIgnoredParent = false
            }
            if logIgnoredParent {
                exchFedServiceLog(
                    "[DMRoute][ignoredParent] inboxItemID=\(item.id.uuidString) parentEnvelopeID=\(pid) " +
                        "reason=parent_not_direct_message_thread_or_missing"
                )
            }
        }
        #endif

        if let correlated = try await findThreadByInboundConversationCorrelation(
            item,
            policy: .directMessageSurface(senderNodeID: senderNodeID)
        ) {
            logCorrelation(correlated.thread, correlated.source, "append")
            return (correlated.thread, correlated.source)
        }

        if let existing = try await findDirectMessageThreadForSenderMatchingOpenOrCreateRules(senderNodeID: senderNodeID) {
            logCorrelation(existing, "existingDirectMessageThreadScan", "append")
            return (existing, "existingDirectMessageThreadScan")
        }

        let now = Date()
        let created = try await createDirectMessageThreadForInboundSenderIfNeeded(
            senderNodeID: senderNodeID,
            item: item,
            now: now
        )
        logCorrelation(created, "createdDirectMessageThreadInboundSurface", "append")
        return (created, "createdDirectMessageThreadInboundSurface")
    }

    private func findDirectMessageThreadForSenderMatchingOpenOrCreateRules(
        senderNodeID: String
    ) async throws -> ExchangeThread? {
        let trimmed = senderNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let threadItems = try await store.listThreads(filter: ExchangeThreadFilter(limit: 500))
        for candidate in threadItems.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let selectedCounterparty = candidate.selectedCounterpartyID?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard selectedCounterparty == trimmed else { continue }
            guard Self.isInboundDirectMessageSurfaceContainer(thread: candidate, senderNodeID: trimmed) else { continue }
            return candidate
        }
        return nil
    }

    private func createDirectMessageThreadForInboundSenderIfNeeded(
        senderNodeID: String,
        item: ExchangeInboxItem,
        now: Date
    ) async throws -> ExchangeThread {
        let trimmed = senderNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExchangeStoreError.storageFailure(reason: "Inbound DM surface requires sender node id.")
        }

        let counterparty: ExchangeCounterparty
        if let existing = try await store.fetchCounterparty(id: trimmed) {
            counterparty = existing
        } else {
            let created = ExchangeCounterparty(
                id: trimmed,
                createdAt: now,
                updatedAt: now,
                kind: .secretaryNode,
                displayName: item.senderDisplayName ?? trimmed,
                source: .relayNetwork,
                identity: .init(
                    nodeID: trimmed,
                    publicKeyID: nil,
                    verification: .unverified
                ),
                trust: .unverified,
                status: .active
            )
            try await store.upsertCounterparties([created])
            counterparty = created
        }

        let hintProfile = Self.firstNonEmptyMetadataValue(
            keys: ["selected_public_profile_id", "public_profile_id", "matched_profile_id"],
            in: item.metadata
        )
        let hintTrimmed = hintProfile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var selectedPublicProfileID: String?
        if !hintTrimmed.isEmpty,
           let verified = try await fetchPublicProfile(id: hintTrimmed, counterpartyID: trimmed) {
            selectedPublicProfileID = verified.id
        } else {
            let attachedTrimmed = counterparty.publicProfile?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !attachedTrimmed.isEmpty {
                selectedPublicProfileID = attachedTrimmed
            }
        }

        let cleanedName = item.senderDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = cleanedName.isEmpty ? "Message" : "Message \(cleanedName)"
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: title,
            objective: "Direct message to trusted contact",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
        let mutation = threadEngine.beginThread(
            userText: "Direct message opened.",
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(privacy: .balanced),
            now: now
        )

        var newThread = mutation.thread
        newThread.selectedOfferID = nil
        newThread.selectedCounterpartyID = trimmed
        if let pid = selectedPublicProfileID {
            newThread.selectedPublicProfileID = pid
        }
        newThread.metadata["direct_message_thread"] = "true"
        ExchangeThreadLaneResolver.applyLane(.directMessage, to: &newThread.metadata)

        let threadToCreate = newThread
        let turnsToAppend = mutation.turns
        try await store.performTransaction {
            try await store.createThread(threadToCreate)
            for turn in turnsToAppend {
                try await store.appendTurn(turn)
            }
        }

        let persisted = try await store.requireThread(id: threadToCreate.id)
        #if DEBUG
        exchFedServiceLog(
            "[DMRoute][createDMThread] senderNodeID=\(trimmed) result=created threadID=\(persisted.id.uuidString) " +
                "reason=inbound_surface_create"
        )
        exchFedServiceLog(
            "[DMRoute][createdThread] inboxItemID=\(item.id.uuidString) threadID=\(persisted.id.uuidString) sender=\(trimmed)"
        )
        #endif
        return persisted
    }

    /// Requester-originated threads only (`inbound_thread` absent): supplier replied without resolvable parent/conversation anchors.
    private func findTransactionalSupplierReplyContinuationThread(
        for item: ExchangeInboxItem
    ) async throws -> ExchangeThread? {
        let senderID = item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !senderID.isEmpty else { return nil }

        let envOffer = Self.firstNonEmptyMetadataValue(
            keys: ["selected_offer_id", "matched_offer_id"],
            in: item.metadata
        )
        let envProfile = Self.firstNonEmptyMetadataValue(
            keys: ["selected_public_profile_id", "public_profile_id", "matched_profile_id"],
            in: item.metadata
        )

        let threads = try await store.listThreads(filter: .init(limit: 500))

        func isArchived(_ t: ExchangeThread) -> Bool {
            t.metadata["archived"] == "true"
        }

        func isInboundDedicatedThread(_ t: ExchangeThread) -> Bool {
            t.metadata["inbound_thread"] == "true"
        }

        func isDirectMessageDedicatedThread(_ t: ExchangeThread) -> Bool {
            t.metadata["direct_message_thread"] == "true"
        }

        func isContinuationEligibleState(_ t: ExchangeThread) -> Bool {
            switch t.state {
            case .awaitingResponse, .matchFound:
                return true
            default:
                return false
            }
        }

        func counterpartyMatches(_ t: ExchangeThread) -> Bool {
            let sel = t.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return sel == senderID
        }

        var narrowed = threads.filter { t in
            !isArchived(t) && !isInboundDedicatedThread(t) && !isDirectMessageDedicatedThread(t)
                && counterpartyMatches(t) && isContinuationEligibleState(t)
        }

        let offerTrimmed = envOffer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profileTrimmed = envProfile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasOffer = !offerTrimmed.isEmpty
        let hasProfile = !profileTrimmed.isEmpty

        if hasOffer {
            narrowed = narrowed.filter { t in
                guard let o = t.selectedOfferID?.trimmingCharacters(in: .whitespacesAndNewlines), !o.isEmpty else {
                    return false
                }
                return o.caseInsensitiveCompare(offerTrimmed) == .orderedSame
            }
        }
        if hasProfile {
            narrowed = narrowed.filter { t in
                guard let p = t.selectedPublicProfileID?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else {
                    return false
                }
                return p.caseInsensitiveCompare(profileTrimmed) == .orderedSame
            }
        }

        guard !narrowed.isEmpty else { return nil }

        if narrowed.count > 1, !hasOffer, !hasProfile {
            let awaitingOnly = narrowed.filter {
                if case .awaitingResponse = $0.state { return true }
                return false
            }
            if awaitingOnly.count == 1, let only = awaitingOnly.first {
                #if DEBUG
                exchFedServiceLog(
                    "[InboundThreadCorrelation] envelope=\(item.envelopeID) result=matchedExisting reason=singleAwaitingResponseAmongTransactional sender=\(senderID) thread=\(only.id.uuidString)"
                )
                #endif
                return only
            }
            #if DEBUG
            exchFedServiceLog(
                "[InboundThreadCorrelationMiss] envelope=\(item.envelopeID) reason=ambiguousTransactionalContinuation sender=\(senderID) candidates=\(narrowed.count) offer=\(hasOffer) profile=\(hasProfile)"
            )
            #endif
            return nil
        }

        guard let best = narrowed.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        #if DEBUG
        exchFedServiceLog(
            "[InboundThreadCorrelation] envelope=\(item.envelopeID) result=matchedExisting reason=transactionalAwaitingSupplierReply thread=\(best.id.uuidString)"
        )
        #endif
        return best
    }

    private func findThreadByInboundConversationCorrelation(
        _ item: ExchangeInboxItem,
        policy: InboundConversationCorrelationPolicy
    ) async throws -> (thread: ExchangeThread, source: String)? {
        let conversationID = item.metadata["conversation_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootEnvelopeID = item.metadata["root_envelope_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalRequesterEnvelopeID = item.metadata["original_requester_envelope_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        for candidate in [conversationID, rootEnvelopeID, originalRequesterEnvelopeID].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if let outbox = try await store.fetchOutboxItemByEnvelopeID(candidate),
               let thread = try await store.fetchThread(id: outbox.threadID) {
                let filtered = Self.applyConversationCorrelationPolicy(threads: [thread], policy: policy)
                guard let allowed = filtered.first else { continue }
                let source: String
                if candidate == conversationID {
                    source = "conversationIDOutbox"
                } else if candidate == rootEnvelopeID {
                    source = "rootEnvelopeIDOutbox"
                } else {
                    source = "originalRequesterEnvelopeIDOutbox"
                }
                return (allowed, source)
            }
        }

        let threads = try await store.listThreads(filter: .init(limit: 500))

        func metaPick(metadataKey: String, expected: String, source: String) -> (ExchangeThread, String)? {
            let matches = threads.filter { t in
                let metaVal = t.metadata[metadataKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return metaVal == expected
            }
            let filtered = Self.applyConversationCorrelationPolicy(threads: matches, policy: policy)
            guard let best = Self.deterministicLatestThread(from: filtered) else { return nil }
            return (best, source)
        }

        if let conversationID, !conversationID.isEmpty,
           let hit = metaPick(metadataKey: "conversation_id", expected: conversationID, source: "conversationIDThreadMeta") {
            return hit
        }
        if let rootEnvelopeID, !rootEnvelopeID.isEmpty,
           let hit = metaPick(metadataKey: "root_envelope_id", expected: rootEnvelopeID, source: "rootEnvelopeIDThreadMeta") {
            return hit
        }
        if let originalRequesterEnvelopeID, !originalRequesterEnvelopeID.isEmpty,
           let hit = metaPick(
                metadataKey: "original_requester_envelope_id",
                expected: originalRequesterEnvelopeID,
                source: "originalRequesterEnvelopeIDThreadMeta"
           ) {
            return hit
        }
        return nil
    }

    /// Reuses an existing provider inbound thread when the relay omits `threadID` / `parentEnvelopeID` but
    /// the sender, offer, and public profile context match a thread we already have.
    func findExistingInboundContinuationThread(
        for item: ExchangeInboxItem
    ) async throws -> ExchangeThread? {
        let senderID = item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !senderID.isEmpty else { return nil }

        let envOffer = Self.firstNonEmptyMetadataValue(
            keys: ["selected_offer_id", "matched_offer_id"],
            in: item.metadata
        )
        let envProfile = Self.firstNonEmptyMetadataValue(
            keys: ["selected_public_profile_id", "public_profile_id", "matched_profile_id"],
            in: item.metadata
        )

        let threads = try await store.listThreads(filter: .init(limit: 500))

        func isArchived(_ t: ExchangeThread) -> Bool {
            t.metadata["archived"] == "true"
        }

        func isInboundThread(_ t: ExchangeThread) -> Bool {
            t.metadata["inbound_thread"] == "true"
        }

        func counterpartyMatches(_ t: ExchangeThread) -> Bool {
            let sel = t.selectedCounterpartyID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return sel == senderID
        }

        let baseInbound = threads.filter { t in
            !isArchived(t) && isInboundThread(t) && counterpartyMatches(t)
        }

        let offerTrimmed = envOffer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profileTrimmed = envProfile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasOffer = !offerTrimmed.isEmpty
        let hasProfile = !profileTrimmed.isEmpty

        if !hasOffer && !hasProfile {
            guard baseInbound.count == 1, let only = baseInbound.first else {
                #if DEBUG
                if baseInbound.count > 1 {
                    exchFedServiceLog(
                        "findExistingInboundContinuationThread | ambiguous counterpartyOnly | " +
                            "sender=\(senderID) | candidates=\(baseInbound.count)"
                    )
                }
                #endif
                return nil
            }
            return only
        }

        var narrowed = baseInbound
        if hasOffer {
            narrowed = narrowed.filter { t in
                guard let o = t.selectedOfferID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !o.isEmpty else {
                    return false
                }
                return o.caseInsensitiveCompare(offerTrimmed) == .orderedSame
            }
        }
        if hasProfile {
            narrowed = narrowed.filter { t in
                guard let p = t.selectedPublicProfileID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !p.isEmpty else {
                    return false
                }
                return p.caseInsensitiveCompare(profileTrimmed) == .orderedSame
            }
        }

        guard let best = narrowed.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        return best
    }

    func resolveCounterpartyForInboxItem(
        _ item: ExchangeInboxItem,
        thread: ExchangeThread
    ) async throws -> ExchangeCounterparty? {
        let senderID = item.senderNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !senderID.isEmpty,
           let sender = try await store.fetchCounterparty(id: senderID) {
            return sender
        }

        if let selectedID = thread.selectedCounterpartyID,
           let selected = try await store.fetchCounterparty(id: selectedID) {
            return selected
        }

        return nil
    }

    // MARK: - Inbound First-Contact Thread Creation

    func makeInboundThreadForNewContact(
        _ item: ExchangeInboxItem,
        now: Date
    ) async throws -> (thread: ExchangeThread, counterparty: ExchangeCounterparty?) {
        if ExchangeContactSignalClassifier.isInboundContactRequest(item) {
            #if DEBUG
            exchFedServiceLog(
                "[ContactRequestRoute][misrouteBlocked] inboxItemID=\(item.id.uuidString) " +
                    "reason=contact_signal_must_not_create_desk_thread"
            )
            #endif
            throw ExchangeStoreError.storageFailure(
                reason: "Contact-signal inbound items must not create exchange desk threads."
            )
        }

        let senderDisplay = item.senderDisplayName
            ?? item.senderNodeID
            ?? "Unknown sender"

        let subjectPreviewRaw = item.metadata["subject_preview"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bodyPreviewRaw = item.metadata["body_preview"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subjectPreview = ExchangeUserFacingCopySanitizer.cleanReceivedFederationBody(subjectPreviewRaw).cleaned
        let bodyPreview = ExchangeUserFacingCopySanitizer.cleanReceivedFederationBody(bodyPreviewRaw).cleaned

        // Map payload_kind to a thread mode. An introduction payload suggests
        // a relational mode; everything else defaults to transactional.
        let payloadKind = item.metadata["payload_kind"] ?? ""
        let mode: ExchangeMode =
            (payloadKind == "introduction" || payloadKind == ExchangeRelayEnvelope.Payload.Kind.friendRequest.rawValue)
            ? .relational
            : .transactional

        let intentTitle = subjectPreview.isEmpty ? "Response received" : subjectPreview
        let intentObjective = bodyPreview.isEmpty
            ? "Review and respond to the inbound message."
            : bodyPreview

        let intent = ExchangeIntent(
            kind: .message,
            mode: mode,
            queryIntentClass: .directOutreach,
            title: intentTitle,
            objective: intentObjective,
            readiness: .ready
        )

        let selectedOfferIDRaw = Self.firstNonEmptyMetadataValue(
            keys: ["selected_offer_id", "matched_offer_id"],
            in: item.metadata
        )

        let selectedPublicProfileID = Self.firstNonEmptyMetadataValue(
            keys: ["selected_public_profile_id", "public_profile_id", "matched_profile_id"],
            in: item.metadata
        )

        let inboundLane = ExchangeThreadLaneResolver.laneFromInboundEnvelopeMetadata(item.metadata)
        let selectedOfferID: String? = ExchangeThreadLaneResolver.clearsCommercialOfferAnchor(for: inboundLane)
            ? nil
            : selectedOfferIDRaw

        var threadMetadata: [String: String] = [
            "inbound_thread": "true",
            "inbound_first_contact": "true",
            // Durable origin: first-contact inbox path only; continuation reuses existing thread metadata.
            "thread_origin": "inbound_receive",
            "first_inbound_sender_node_id": item.senderNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "inbound_sender_node": item.senderNodeID ?? "",
            "inbound_envelope": item.envelopeID,
            "conversation_id": Self.firstNonEmptyMetadataValue(keys: ["conversation_id", "root_envelope_id"], in: item.metadata) ?? item.envelopeID,
            "root_envelope_id": Self.firstNonEmptyMetadataValue(keys: ["root_envelope_id", "original_requester_envelope_id"], in: item.metadata) ?? item.envelopeID,
            "original_requester_envelope_id": Self.firstNonEmptyMetadataValue(keys: ["original_requester_envelope_id", "root_envelope_id"], in: item.metadata) ?? item.envelopeID
        ]
        ExchangeThreadLaneResolver.applyLane(inboundLane, to: &threadMetadata)
        if inboundLane == .directMessage {
            threadMetadata["direct_message_thread"] = "true"
        }

        let thread = ExchangeThread(
            createdAt: now,
            updatedAt: now,
            mode: mode,
            intent: intent,
            posture: .default,
            state: .matchFound(.init(
                foundAt: now,
                candidateCount: 1,
                summary: "Inbound message received from \(senderDisplay).",
                selectedCounterpartyID: item.senderNodeID,
                selectedPublicProfileID: selectedPublicProfileID,
                selectedOfferID: selectedOfferID
            )),
            selectedCounterpartyID: item.senderNodeID,
            selectedPublicProfileID: selectedPublicProfileID,
            selectedOfferID: selectedOfferID,
            candidateCounterpartyIDs: item.senderNodeID.map { [$0] } ?? [],
            visibleSummary: ExchangeUserFacingCopySanitizer.sanitizeOrFallback(
                intentTitle,
                field: .subtitle,
                fallback: "Response received"
            ),
            metadata: threadMetadata
        )

        // Upsert the sender as a local counterparty record if we have a nodeID
        // and no existing record is present. This gives the continuation
        // coordinator a counterparty reference for reply drafting.
        let counterparty: ExchangeCounterparty?
        if let senderNodeID = item.senderNodeID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !senderNodeID.isEmpty {
            if let existing = try await store.fetchCounterparty(id: senderNodeID) {
                counterparty = existing
            } else {
                counterparty = ExchangeCounterparty(
                    id: senderNodeID,
                    createdAt: now,
                    updatedAt: now,
                    kind: .secretaryNode,
                    displayName: item.senderDisplayName ?? senderNodeID,
                    source: .relayNetwork,
                    identity: .init(
                        nodeID: senderNodeID,
                        publicKeyID: nil,
                        verification: .unverified
                    ),
                    trust: .unverified,
                    status: .active
                )
            }
        } else {
            counterparty = nil
        }

        #if DEBUG
        exchFedServiceLog(
            "makeInboundThreadForNewContact | threadID=\(thread.id.uuidString) | " +
                "selectedCounterpartyID=\(thread.selectedCounterpartyID ?? "nil") | " +
                "state=\(ExchangeTransition.ExchangeStateKey(thread.state).rawValue) | " +
                "counterpartyUpsert=\(counterparty != nil)"
        )
        #endif

        return (thread, counterparty)
    }

    // MARK: - Send path

    func sendOutboxItem(
        _ queued: ExchangeOutboxItem,
        now: Date
    ) async throws -> (SendOutcome, outboundRelayConfirmedThreadID: UUID?) {

        guard let freshest = try await store.fetchOutboxItem(id: queued.id) else {
            return (.failed, nil)
        }

        switch freshest.deliveryState.phase {
        case .sending:
            #if DEBUG
            exchFedServiceLog(
                "[OutboxDedup] action=skip reason=inFlight envelopeID=\(freshest.envelopeID)"
            )
            #endif
            return (.untouched, nil)
        case .sent, .acknowledged:
            #if DEBUG
            exchFedServiceLog(
                "[OutboxDedup] action=skip reason=alreadySent envelopeID=\(freshest.envelopeID)"
            )
            #endif
            return (.untouched, nil)
        default:
            break
        }

        let acquired = await ExchangeOutboxEnvelopeSendDeduper.shared.tryAcquire(freshest.envelopeID)
        guard acquired else {
            #if DEBUG
            exchFedServiceLog(
                "[OutboxDedup] action=skip reason=inFlightConcurrent envelopeID=\(freshest.envelopeID)"
            )
            #endif
            return (.untouched, nil)
        }

        defer {
            Task {
                await ExchangeOutboxEnvelopeSendDeduper.shared.release(freshest.envelopeID)
            }
        }

        let item = freshest

        var thread = try await store.requireThread(id: item.threadID)
        let draft = try await store.requireDraft(id: item.draftID)

        guard let counterparty = try await resolvedCounterpartyForOutbox(item) else {
            let failed = item.failingTerminally(
                errorCode: "missing_counterparty",
                note: "The target counterparty could not be resolved for this queued send.",
                externalEffect: .none,
                at: now
            )

            let audit = ExchangeAuditRecord.failed(
                direction: .outbound,
                threadID: failed.threadID,
                envelopeID: failed.envelopeID,
                outboxItemID: failed.id,
                summary: "Queued send is missing a target counterparty.",
                detail: "The target counterparty could not be resolved for this queued send.",
                externalEffect: .none,
                relatedNodeID: failed.targetNodeID,
                relatedDisplayName: nil,
                createdAt: now
            )

            try await store.performTransaction {
                try await store.saveOutboxItem(failed)
                try await store.appendAuditRecord(audit)
            }

            logSendOutboxFailure(
                branch: "missing_counterparty",
                thread: thread,
                draft: draft,
                outboxItem: failed,
                publicProfile: nil,
                selectedCounterpartyID: thread.selectedCounterpartyID,
                selectedPublicProfileID: thread.selectedPublicProfileID,
                errorCode: failed.deliveryState.lastErrorCode,
                note: failed.deliveryState.note,
                rationale: "The target counterparty could not be resolved for this queued send."
            )

            return (.failed, nil)
        }

        let hydratedProfile = try await resolvedExecutionPublicProfile(
            thread: thread,
            counterparty: counterparty
        )

        let disclosureLevel = disclosureLevel(from: item.metadata["disclosure_level"])
        let routeHint = relayRoute(from: item.metadata)
        let parentEnvelopeID = item.metadata["parent_envelope_id"]?.exchangeNilIfBlank

        // Critical fix:
        // This function is already executing an existing queued outbox item.
        // Passing item.deliveryState into ExchangePolicyEngine makes `.queued`
        // block itself with: "A transport item already exists for this draft."
        //
        // Queue-time duplicate prevention already happened in queueApprovedOutbound.
        // Send-time policy should still check sender policy and recipient posture,
        // but must not treat the current outbox item as a duplicate transport item.
        let policy = policyEngine.evaluate(
            thread: thread,
            selectedCounterparty: counterparty,
            publicProfile: hydratedProfile,
            draft: draft,
            deliveryState: nil
        )

        guard policy.senderPolicy.allowsExternalAction else {
            let failed = item.failingTerminally(
                errorCode: "sender_policy_blocked",
                note: policy.senderPolicy.rationale,
                externalEffect: .none,
                at: now
            )

            let audit = ExchangeAuditRecord.failed(
                direction: .outbound,
                threadID: failed.threadID,
                envelopeID: failed.envelopeID,
                outboxItemID: failed.id,
                summary: "Outbound delivery is not allowed by sender policy.",
                detail: policy.senderPolicy.rationale,
                externalEffect: .none,
                relatedNodeID: failed.targetNodeID,
                relatedDisplayName: try await counterpartyDisplayName(for: failed.targetNodeID),
                createdAt: now
            )

            try await store.performTransaction {
                try await store.saveOutboxItem(failed)
                try await store.appendAuditRecord(audit)
            }

            logSendOutboxFailure(
                branch: "sender_policy_blocked",
                thread: thread,
                draft: draft,
                outboxItem: failed,
                publicProfile: hydratedProfile,
                selectedCounterpartyID: thread.selectedCounterpartyID,
                selectedPublicProfileID: thread.selectedPublicProfileID,
                errorCode: failed.deliveryState.lastErrorCode,
                note: failed.deliveryState.note,
                rationale: policy.senderPolicy.rationale
            )

            return (.failed, nil)
        }

        guard policy.recipientPosture.allowed else {
            let failed = item.failingTerminally(
                errorCode: "recipient_posture_blocked",
                note: policy.recipientPosture.rationale,
                externalEffect: .none,
                at: now
            )

            let audit = ExchangeAuditRecord.failed(
                direction: .outbound,
                threadID: failed.threadID,
                envelopeID: failed.envelopeID,
                outboxItemID: failed.id,
                summary: "Outbound delivery is not allowed by recipient posture.",
                detail: policy.recipientPosture.rationale,
                externalEffect: .none,
                relatedNodeID: failed.targetNodeID,
                relatedDisplayName: try await counterpartyDisplayName(for: failed.targetNodeID),
                createdAt: now
            )

            try await store.performTransaction {
                try await store.saveOutboxItem(failed)
                try await store.appendAuditRecord(audit)
            }

            logSendOutboxFailure(
                branch: "recipient_posture_blocked_\(policy.recipientPosture.status.rawValue)",
                thread: thread,
                draft: draft,
                outboxItem: failed,
                publicProfile: hydratedProfile,
                selectedCounterpartyID: thread.selectedCounterpartyID,
                selectedPublicProfileID: thread.selectedPublicProfileID,
                errorCode: failed.deliveryState.lastErrorCode,
                note: failed.deliveryState.note,
                rationale: policy.recipientPosture.rationale
            )

            return (.failed, nil)
        }

        guard let executionPublicProfile = resolvedExecutionProfileForOutboundEnvelope(
            hydratedProfile: hydratedProfile,
            thread: thread,
            counterparty: counterparty
        ) else {
            let failed = item.failingTerminally(
                errorCode: "no_public_profile",
                note: "No selected public execution surface is available for this queued send.",
                externalEffect: .none,
                at: now
            )

            let audit = ExchangeAuditRecord.failed(
                direction: .outbound,
                threadID: failed.threadID,
                envelopeID: failed.envelopeID,
                outboxItemID: failed.id,
                summary: "Outbound delivery is missing a selected public execution surface.",
                detail: "No selected public execution surface is available for this queued send.",
                externalEffect: .none,
                relatedNodeID: failed.targetNodeID,
                relatedDisplayName: try await counterpartyDisplayName(for: failed.targetNodeID),
                createdAt: now
            )

            try await store.performTransaction {
                try await store.saveOutboxItem(failed)
                try await store.appendAuditRecord(audit)
            }

            logSendOutboxFailure(
                branch: "no_public_profile",
                thread: thread,
                draft: draft,
                outboxItem: failed,
                publicProfile: nil,
                selectedCounterpartyID: thread.selectedCounterpartyID,
                selectedPublicProfileID: thread.selectedPublicProfileID,
                errorCode: failed.deliveryState.lastErrorCode,
                note: failed.deliveryState.note,
                rationale: "No selected public execution surface is available for this queued send."
            )

            return (.failed, nil)
        }

        if hydratedProfile == nil,
           ExchangePolicyEngine.isExistingInboundContinuationReplySend(thread: thread, counterparty: counterparty) {
            let tid = item.targetNodeID
            #if DEBUG
            exchFedServiceLog(
                "[OutboundRecipientResolution] mode=existingContinuation postureRequired=false targetNodeID=\(tid) selectedCounterpartyID=\(thread.selectedCounterpartyID ?? counterparty.id) profileNodeID=\(executionPublicProfile.nodeID) decision=allow reason=existing_continuation_no_public_posture_required"
            )
            #endif
        }

        let lane = ExchangeThreadLaneResolver.lane(for: thread)
        if !ApprovedOutboundAlignment.isExchangeSendableLane(lane),
           item.approvalID != nil {
            return try await quarantineApprovedOutboxItem(
                item: item,
                thread: thread,
                errorCode: "lane_not_exchange_sendable",
                note: "Approved exchange outbox is not sendable on this thread lane.",
                now: now
            )
        }

        switch try await ensureSendingPhaseForApprovedOutbound(
            thread: thread,
            outboxItem: item,
            draft: draft,
            now: now
        ) {
        case .ready(let aligned), .unchanged(let aligned):
            thread = aligned
        case .quarantined(let reason, let errorCode):
            return try await quarantineApprovedOutboxItem(
                item: item,
                thread: thread,
                errorCode: errorCode,
                note: reason,
                now: now
            )
        }

        let built: ExchangeEnvelopeService.BuiltEnvelope
        do {
            built = try await envelopeService.buildEnvelope(
                thread: thread,
                counterparty: counterparty,
                publicProfile: executionPublicProfile,
                draft: draft,
                disclosureLevel: disclosureLevel,
                parentEnvelopeID: parentEnvelopeID,
                idempotencyKey: item.envelopeID,
                routeHint: routeHint,
                now: now
            )
        } catch let error as ExchangeEnvelopeServiceError {
            let failed = item.failingTerminally(
                errorCode: envelopeFailureCode(error),
                note: envelopeEligibilityReason(error),
                externalEffect: .none,
                at: now
            )

            let audit = ExchangeAuditRecord.failed(
                direction: .outbound,
                threadID: failed.threadID,
                envelopeID: failed.envelopeID,
                outboxItemID: failed.id,
                summary: "Outbound delivery is not allowed by recipient posture or routing state.",
                detail: envelopeEligibilityReason(error),
                externalEffect: .none,
                relatedNodeID: failed.targetNodeID,
                relatedDisplayName: try await counterpartyDisplayName(for: failed.targetNodeID),
                createdAt: now
            )

            try await store.performTransaction {
                try await store.saveOutboxItem(failed)
                try await store.appendAuditRecord(audit)
            }

            logSendOutboxFailure(
                branch: "envelope_build_failed",
                thread: thread,
                draft: draft,
                outboxItem: failed,
                publicProfile: executionPublicProfile,
                selectedCounterpartyID: thread.selectedCounterpartyID,
                selectedPublicProfileID: thread.selectedPublicProfileID,
                errorCode: envelopeFailureCode(error),
                note: failed.deliveryState.note,
                rationale: envelopeEligibilityReason(error)
            )

            return (.failed, nil)
        } catch let error as ExchangePrivateE2EESendBlockedError {
            return try await terminalFailOutboxForE2EESendBlocked(
                item: item,
                thread: thread,
                draft: draft,
                executionPublicProfile: executionPublicProfile,
                error: error,
                now: now
            )
        }

        let inFlight = item.updatingDeliveryState(
            item.deliveryState.beginningSend(
                routeSummary: built.route.summaryLine,
                at: now
            ),
            at: now
        )

        let startAudit = ExchangeAuditRecord(
            createdAt: now,
            threadID: item.threadID,
            direction: .outbound,
            category: .sendStarted,
            actor: .secretary,
            envelopeID: item.envelopeID,
            outboxItemID: item.id,
            summary: "Started outbound delivery.",
            detail: built.route.summaryLine,
            externalEffect: .none,
            relatedNodeID: item.targetNodeID,
            relatedDisplayName: try await counterpartyDisplayName(for: item.targetNodeID)
        )

        try await store.performTransaction {
            try await store.saveOutboxItem(inFlight)
            try await store.appendAuditRecord(startAudit)
        }

#if DEBUG
exchFedServiceLog(
    "sendOutboxItem route dispatch | " +
    "targetExecutionID=\(item.targetNodeID) | " +
    "protocolVersion=\(built.envelope.protocolVersion) | " +
    "routeKind=\(built.route.kind.rawValue) | " +
    "routeDestination=\(built.route.destination) | " +
    "outboxTargetNodeID=\(inFlight.targetNodeID) | " +
    "publicProfileID=\(executionPublicProfile.id) | " +
    "publicProfileNodeID=\(executionPublicProfile.nodeID) | " +
    "counterpartyID=\(counterparty.id) | " +
    "counterpartyIdentityNodeID=\(counterparty.identity?.nodeID ?? "nil")"
)
#endif

        do {
            let sendResult = try await relayClient.send(
                built.envelope,
                route: built.route
            )

            switch sendResult.status {
            case .accepted, .queued:
                let stamp = sendResult.acceptedAt ?? now
                let trimmedRef =
                    sendResult.externalReference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let confirmationReference = trimmedRef.isEmpty ? item.envelopeID : trimmedRef

                let displayNameForAudit = try await counterpartyDisplayName(for: item.targetNodeID)

                let relayConfirmedThreadID: UUID
                do {
                    (_, relayConfirmedThreadID) = try await finalizeSuccessfulRelayOutbound(
                        draftID: item.draftID,
                        inFlight: inFlight,
                        confirmationReference: confirmationReference,
                        relayNote: sendResult.note,
                        stampedAt: stamp,
                        counterpartyDisplayName: displayNameForAudit
                    )
                } catch {
                    exchFedServiceLog(
                        "finalizeSuccessfulRelayOutbound failed | envelopeID=\(item.envelopeID) | error=\(error)"
                    )
                    throw error
                }

                exchFedServiceLog(
                    "sendOutboxItem success | status=\(sendResult.status) | threadID=\(item.threadID.uuidString) | draftID=\(item.draftID.uuidString) | outboxItemID=\(item.id.uuidString) | envelopeID=\(item.envelopeID) | targetNodeID=\(item.targetNodeID) | relayConfirmedThreadID=\(relayConfirmedThreadID.uuidString)"
                )
                refreshTraceFedLog(
                    "[RelaySendAccepted] envelopeID=\(item.envelopeID) recipient=\(item.targetNodeID) status=\(sendResult.status) time=\(Date())"
                )
                #if DEBUG
                let envelopeMeta = built.envelope.metadata
                ExchangeBilateralConversationDebugTrace.logFederationSend(
                    envelopeID: item.envelopeID,
                    outboxID: item.id,
                    sourceThreadID: item.threadID,
                    routeKey: built.route.routeKey,
                    targetNodeID: item.targetNodeID,
                    parentEnvelopeID: parentEnvelopeID,
                    conversationID: envelopeMeta["conversation_id"],
                    rootEnvelopeID: envelopeMeta["root_envelope_id"],
                    originalRequesterEnvelopeID: envelopeMeta["original_requester_envelope_id"],
                    conversationSurface: envelopeMeta["conversation_surface"],
                    sendResult: String(describing: sendResult.status)
                )
                if draft.metadata["second_half_auto_response"] == "true"
                    || draft.metadata["second_half_action"] == ExchangeSecondHalfAction.autoRespond.rawValue {
                    let flushedInline = ExchangeBilateralConversationDebugTrace.activeFlushPassID == nil
                    ExchangeBilateralConversationDebugTrace.logProviderAutoReplySend(
                        threadID: item.threadID,
                        draftID: draft.id,
                        outboxID: item.id,
                        envelopeID: item.envelopeID,
                        parentEnvelopeID: parentEnvelopeID,
                        conversationID: envelopeMeta["conversation_id"],
                        routeKey: built.route.routeKey,
                        queued: false,
                        flushedInline: flushedInline,
                        flushPassID: ExchangeBilateralConversationDebugTrace.activeFlushPassID
                    )
                }
                #endif

                switch sendResult.status {
                case .accepted:
                    return (.acknowledged, relayConfirmedThreadID)
                case .queued:
                    return (.sent, relayConfirmedThreadID)
                default:
                    return (.sent, relayConfirmedThreadID)
                }

            case .rejected:
                let failed = inFlight.failingTerminally(
                    errorCode: "relay_rejected",
                    note: sendResult.note ?? "Relay rejected the envelope.",
                    externalEffect: .none,
                    at: now
                )

                let audit = ExchangeAuditRecord.failed(
                    direction: .outbound,
                    threadID: failed.threadID,
                    envelopeID: failed.envelopeID,
                    outboxItemID: failed.id,
                    summary: "Relay rejected the outbound envelope.",
                    detail: sendResult.note,
                    externalEffect: .none,
                    relatedNodeID: failed.targetNodeID,
                    relatedDisplayName: try await counterpartyDisplayName(for: failed.targetNodeID),
                    createdAt: now
                )

                try await store.performTransaction {
                    try await store.saveOutboxItem(failed)
                    try await store.appendAuditRecord(audit)
                }

                logSendOutboxFailure(
                    branch: "relay_rejected",
                    thread: thread,
                    draft: draft,
                    outboxItem: failed,
                    publicProfile: executionPublicProfile,
                    selectedCounterpartyID: thread.selectedCounterpartyID,
                    selectedPublicProfileID: thread.selectedPublicProfileID,
                    errorCode: failed.deliveryState.lastErrorCode,
                    note: failed.deliveryState.note,
                    rationale: sendResult.note
                )

                return (.failed, nil)

            case .incompatible:
                let incompatible = inFlight
                    .updatingDeliveryState(
                        inFlight.deliveryState.markingIncompatible(
                            errorCode: "incompatible",
                            note: sendResult.note ?? "Remote side reported incompatible federation data.",
                            at: now
                        ),
                        at: now
                    )
                    .deactivating(at: now)

                let audit = ExchangeAuditRecord.failed(
                    direction: .outbound,
                    category: .incompatible,
                    threadID: incompatible.threadID,
                    envelopeID: incompatible.envelopeID,
                    outboxItemID: incompatible.id,
                    summary: "Outbound envelope was incompatible with the remote side.",
                    detail: sendResult.note,
                    externalEffect: .none,
                    relatedNodeID: incompatible.targetNodeID,
                    relatedDisplayName: try await counterpartyDisplayName(for: incompatible.targetNodeID),
                    createdAt: now
                )

                try await store.performTransaction {
                    try await store.saveOutboxItem(incompatible)
                    try await store.appendAuditRecord(audit)
                }

                logSendOutboxFailure(
                    branch: "incompatible",
                    thread: thread,
                    draft: draft,
                    outboxItem: incompatible,
                    publicProfile: executionPublicProfile,
                    selectedCounterpartyID: thread.selectedCounterpartyID,
                    selectedPublicProfileID: thread.selectedPublicProfileID,
                    errorCode: incompatible.deliveryState.lastErrorCode,
                    note: incompatible.deliveryState.note,
                    rationale: sendResult.note
                )

                return (.failed, nil)

            case .unknown:
                let deferred = inFlight.updatingDeliveryState(
                    inFlight.deliveryState.deferring(
                        until: now.addingTimeInterval(TimeInterval(transportPolicy.retryDelay(for: item.deliveryState.priority))),
                        note: sendResult.note ?? "Transport returned an unknown state.",
                        at: now
                    ),
                    at: now
                )

                let audit = ExchangeAuditRecord(
                    createdAt: now,
                    threadID: deferred.threadID,
                    direction: .localOnly,
                    category: .deferred,
                    actor: .system,
                    envelopeID: deferred.envelopeID,
                    outboxItemID: deferred.id,
                    summary: "Deferred outbound delivery after unknown transport result.",
                    detail: sendResult.note,
                    externalEffect: .none,
                    relatedNodeID: deferred.targetNodeID,
                    relatedDisplayName: try await counterpartyDisplayName(for: deferred.targetNodeID)
                )

                try await store.performTransaction {
                    try await store.saveOutboxItem(deferred)
                    try await store.appendAuditRecord(audit)
                }

                return (.deferred, nil)
            }
        } catch {
            let note = relayFailureReason(error)
            #if DEBUG
            ExchangeBilateralConversationDebugTrace.logFederationSend(
                envelopeID: inFlight.envelopeID,
                outboxID: inFlight.id,
                sourceThreadID: inFlight.threadID,
                routeKey: inFlight.metadata["route_key"] ?? built.route.routeKey,
                targetNodeID: inFlight.targetNodeID,
                parentEnvelopeID: parentEnvelopeID,
                conversationID: built.envelope.metadata["conversation_id"],
                rootEnvelopeID: built.envelope.metadata["root_envelope_id"],
                originalRequesterEnvelopeID: built.envelope.metadata["original_requester_envelope_id"],
                conversationSurface: built.envelope.metadata["conversation_surface"],
                sendResult: nil,
                error: note
            )
            #endif
            let exceeded = inFlight.deliveryState.attemptCount >= inFlight.policy.maxAttempts

            let nextState: ExchangeOutboxItem
            if exceeded {
                nextState = inFlight.failingTerminally(
                    errorCode: relayFailureCode(error),
                    note: note,
                    externalEffect: .none,
                    at: now
                )
            } else {
                let retryDelay = relayRetryDelaySeconds(for: error, priority: item.deliveryState.priority)
                nextState = inFlight.updatingDeliveryState(
                    inFlight.deliveryState.deferring(
                        until: now.addingTimeInterval(retryDelay),
                        note: note,
                        at: now
                    ),
                    at: now
                )
            }

            let audit = ExchangeAuditRecord.failed(
                direction: .outbound,
                threadID: nextState.threadID,
                envelopeID: nextState.envelopeID,
                outboxItemID: nextState.id,
                summary: exceeded
                    ? "Outbound delivery failed after exhausting retries."
                    : "Outbound delivery attempt failed and will be retried.",
                detail: note,
                externalEffect: .none,
                relatedNodeID: nextState.targetNodeID,
                relatedDisplayName: try await counterpartyDisplayName(for: nextState.targetNodeID),
                createdAt: now
            )

            try await store.performTransaction {
                try await store.saveOutboxItem(nextState)
                try await store.appendAuditRecord(audit)
            }

            logSendOutboxFailure(
                branch: "relay_send_catch",
                thread: thread,
                draft: draft,
                outboxItem: nextState,
                publicProfile: executionPublicProfile,
                selectedCounterpartyID: thread.selectedCounterpartyID,
                selectedPublicProfileID: thread.selectedPublicProfileID,
                errorCode: relayFailureCode(error),
                note: nextState.deliveryState.note,
                rationale: relayFailureReason(error)
            )

            return exceeded ? (.failed, nil) : (.deferred, nil)
        }
    }

    func logSendOutboxFailure(
        branch: String,
        thread: ExchangeThread,
        draft: ExchangeMessageDraft,
        outboxItem: ExchangeOutboxItem,
        publicProfile: ExchangePublicNodeProfile?,
        selectedCounterpartyID: String?,
        selectedPublicProfileID: String?,
        errorCode: String?,
        note: String?,
        rationale: String?
    ) {
        exchFedServiceLog(
            "sendOutboxItem failure | branch=\(branch) | threadID=\(thread.id.uuidString) | draftID=\(draft.id.uuidString) | outboxItemID=\(outboxItem.id.uuidString) | envelopeID=\(outboxItem.envelopeID) | targetNodeID=\(outboxItem.targetNodeID) | selectedCounterpartyID=\(selectedCounterpartyID ?? "nil") | selectedPublicProfileID=\(selectedPublicProfileID ?? "nil") | publicProfileID=\(publicProfile?.id ?? "nil") | publicProfileNodeID=\(publicProfile?.nodeID ?? "nil") | deliveryPhase=\(outboxItem.deliveryState.phase.rawValue) | errorCode=\(errorCode ?? "nil") | note=\(note ?? "nil") | rationale=\(rationale ?? "nil")"
        )
    }

    enum ApprovedOutboundEnsureResult: Sendable {
        case ready(ExchangeThread)
        case unchanged(ExchangeThread)
        case quarantined(reason: String, errorCode: String)
    }

    func resolvedApprovedOutboundApproval(
        for outboxItem: ExchangeOutboxItem
    ) async throws -> ExchangeApproval? {
        guard let approvalID = outboxItem.approvalID else { return nil }
        return try await store.fetchApproval(id: approvalID)
    }

    func preflightApprovedOutboundQueueThread(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft,
        approval: ExchangeApproval,
        now: Date
    ) async throws -> ExchangeThread {
        let lane = ExchangeThreadLaneResolver.lane(for: thread)
        guard ApprovedOutboundAlignment.isExchangeSendableLane(lane) else {
            logOutboxAlignment(
                thread: thread,
                outboxID: nil,
                approvalStatus: approval.status.rawValue,
                action: .quarantine,
                reason: "lane_not_exchange_sendable"
            )
            throw ExchangeFederationError.transportFailed(reason: "lane_not_exchange_sendable")
        }

        if case .matchCandidatesWeak = thread.state {
            guard ApprovedOutboundAlignment.hasRecipientAnchor(for: thread),
                  ApprovedOutboundAlignment.hasRenderableDraftBody(draft) else {
                logOutboxAlignment(
                    thread: thread,
                    outboxID: nil,
                    approvalStatus: approval.status.rawValue,
                    action: .quarantine,
                    reason: "cannot_queue_from_weak_match_state"
                )
                throw ExchangeFederationError.transportFailed(reason: "cannot_queue_from_weak_match_state")
            }

            if let aligned = try await alignThreadForApprovedOutboundSend(
                thread: thread,
                approval: approval,
                draft: draft,
                now: now
            ) {
                return aligned
            }

            if !ApprovedOutboundAlignment.isLegalGrantApproval(from: thread.state) {
                logOutboxAlignment(
                    thread: thread,
                    outboxID: nil,
                    approvalStatus: approval.status.rawValue,
                    action: .quarantine,
                    reason: "cannot_queue_from_weak_match_state"
                )
                throw ExchangeFederationError.transportFailed(reason: "cannot_queue_from_weak_match_state")
            }
        }

        return thread
    }

    func quarantineApprovedOutboxItem(
        item: ExchangeOutboxItem,
        thread: ExchangeThread,
        errorCode: String,
        note: String,
        now: Date
    ) async throws -> (SendOutcome, outboundRelayConfirmedThreadID: UUID?) {
        let failed = item.failingTerminally(
            errorCode: errorCode,
            note: note,
            externalEffect: .none,
            at: now
        )

        let audit = ExchangeAuditRecord.failed(
            direction: .outbound,
            threadID: failed.threadID,
            envelopeID: failed.envelopeID,
            outboxItemID: failed.id,
            summary: "Approved outbound quarantined during flush.",
            detail: note,
            externalEffect: .none,
            relatedNodeID: failed.targetNodeID,
            relatedDisplayName: try await counterpartyDisplayName(for: failed.targetNodeID),
            createdAt: now
        )

        try await store.performTransaction {
            try await store.saveOutboxItem(failed)
            try await store.appendAuditRecord(audit)
        }

        logOutboxAlignment(
            thread: thread,
            outboxID: item.id,
            approvalStatus: "approved",
            action: .quarantine,
            reason: errorCode
        )

        return (.failed, nil)
    }

    func logOutboxAlignment(
        thread: ExchangeThread,
        outboxID: ExchangeOutboxItem.ID?,
        approvalStatus: String,
        action: ApprovedOutboundAlignment.Action,
        reason: String
    ) {
        let lane = ExchangeThreadLaneResolver.lane(for: thread)
        let outboxLabel = outboxID.map { ApprovedOutboundAlignment.shortID($0) } ?? "nil"
        exchFedServiceLog(
            "[OutboxAlignment] thread=\(ApprovedOutboundAlignment.shortID(thread.id)) " +
            "outbox=\(outboxLabel) state=\(thread.state.phaseTitle) lane=\(lane.rawValue) " +
            "approval=\(approvalStatus) action=\(action.rawValue) reason=\(reason)"
        )
    }

    func logOutboxLegalize(
        threadID: ExchangeThread.ID,
        step: ApprovedOutboundAlignment.LegalizeStep,
        result: String
    ) {
        exchFedServiceLog(
            "[OutboxAlignment] legalize step=\(step.rawValue) result=\(result) " +
            "thread=\(ApprovedOutboundAlignment.shortID(threadID))"
        )
    }

    /// When an approval exists locally as `.approved` but the thread was never advanced to `.sending`
    /// (some autonomous paths approve out-of-band), align with legal transitions before relay send.
    func ensureSendingPhaseForApprovedOutbound(
        thread: ExchangeThread,
        outboxItem: ExchangeOutboxItem,
        draft: ExchangeMessageDraft,
        now: Date
    ) async throws -> ApprovedOutboundEnsureResult {
        if case .sending = thread.state {
            return .unchanged(thread)
        }

        guard let approvalID = outboxItem.approvalID else {
            return .unchanged(thread)
        }

        guard let approval = try await store.fetchApproval(id: approvalID),
              approval.status == .approved
        else {
            return .unchanged(thread)
        }

        let lane = ExchangeThreadLaneResolver.lane(for: thread)
        guard ApprovedOutboundAlignment.isExchangeSendableLane(lane) else {
            return .quarantined(
                reason: "Approved exchange outbox is not sendable on this thread lane.",
                errorCode: "lane_not_exchange_sendable"
            )
        }

        if ApprovedOutboundAlignment.isLegalGrantApproval(from: thread.state) {
            logOutboxAlignment(
                thread: thread,
                outboxID: outboxItem.id,
                approvalStatus: approval.status.rawValue,
                action: .grant,
                reason: "legal_grant_from_current_state"
            )
            do {
                let grantMutation = try threadEngine.grantApproval(
                    thread: thread,
                    approval: approval,
                    now: now
                )
                try await persistThreadMutation(grantMutation)
                return .ready(grantMutation.thread)
            } catch let error as ExchangeThreadEngineError {
                if case .invalidTransition = error {
                    return .quarantined(
                        reason: error.localizedDescription,
                        errorCode: "approved_outbox_thread_state_unaligned"
                    )
                }
                throw error
            }
        }

        if case .matchCandidatesWeak = thread.state {
            guard ApprovedOutboundAlignment.hasRecipientAnchor(for: thread),
                  ApprovedOutboundAlignment.hasRenderableDraftBody(draft) else {
                return .quarantined(
                    reason: "Cannot send approved outbound from weak match without recipient anchor and draft.",
                    errorCode: "cannot_send_from_weak_match_state"
                )
            }

            logOutboxAlignment(
                thread: thread,
                outboxID: outboxItem.id,
                approvalStatus: approval.status.rawValue,
                action: .align,
                reason: "weak_match_alignment_required"
            )

            do {
                if let aligned = try await alignThreadForApprovedOutboundSend(
                    thread: thread,
                    approval: approval,
                    draft: draft,
                    now: now
                ) {
                    return .ready(aligned)
                }
            } catch let error as ExchangeThreadEngineError {
                if case .invalidTransition = error {
                    return .quarantined(
                        reason: error.localizedDescription,
                        errorCode: "approved_outbox_thread_state_unaligned"
                    )
                }
                throw error
            }

            return .quarantined(
                reason: "Approved outbound could not be legally aligned from weak match state.",
                errorCode: "approved_outbox_thread_state_unaligned"
            )
        }

        return .quarantined(
            reason: "Approved outbound thread state is not send-ready.",
            errorCode: "approved_outbox_thread_state_unaligned"
        )
    }

    func alignThreadForApprovedOutboundSend(
        thread: ExchangeThread,
        approval: ExchangeApproval,
        draft: ExchangeMessageDraft,
        now: Date
    ) async throws -> ExchangeThread? {
        var current = thread
        var collectedTurns: [ExchangeTurn] = []

        func absorb(_ mutation: ExchangeThreadEngine.ThreadMutation) {
            current = mutation.thread
            collectedTurns.append(contentsOf: mutation.turns)
        }

        if ApprovedOutboundAlignment.isLegalGrantApproval(from: current.state) {
            absorb(try threadEngine.grantApproval(thread: current, approval: approval, now: now))
            try await persistAlignedThread(current, turns: collectedTurns)
            logOutboxLegalize(threadID: current.id, step: .approvalGranted, result: "ok")
            return current
        }

        if case .matchCandidatesWeak = current.state {
            if ApprovedOutboundAlignment.isLegalDraftPrepared(from: current.state, draftID: draft.id) {
                absorb(try threadEngine.markDraftPrepared(thread: current, draft: draft, now: now))
                logOutboxLegalize(threadID: current.id, step: .draftPrepared, result: "ok")
            } else if let counterpartyID = resolvedAlignmentCounterpartyID(thread: current, draft: draft),
                      ApprovedOutboundAlignment.isLegalCandidateAccepted(
                          from: current.state,
                          thread: current,
                          selectedCounterpartyID: counterpartyID
                      ) {
                absorb(
                    try threadEngine.recordSelectedMatch(
                        thread: current,
                        selectedCounterpartyID: counterpartyID,
                        selectedPublicProfileID: current.selectedPublicProfileID,
                        selectedOfferID: current.selectedOfferID,
                        candidateIDs: current.candidateCounterpartyIDs,
                        summary: current.visibleSummary ?? "Aligned for approved outbound.",
                        nextStep: "Preparing approved outbound send.",
                        now: now
                    )
                )
                logOutboxLegalize(threadID: current.id, step: .candidateAccepted, result: "ok")
            } else {
                logOutboxLegalize(threadID: current.id, step: .draftPrepared, result: "fail")
                return nil
            }
        }

        guard ApprovedOutboundAlignment.isLegalGrantApproval(from: current.state) else {
            logOutboxLegalize(threadID: current.id, step: .approvalGranted, result: "fail")
            return nil
        }

        absorb(try threadEngine.grantApproval(thread: current, approval: approval, now: now))
        try await persistAlignedThread(current, turns: collectedTurns)
        logOutboxLegalize(threadID: current.id, step: .approvalGranted, result: "ok")
        return current
    }

    func resolvedAlignmentCounterpartyID(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft
    ) -> String? {
        let fromThread = thread.selectedCounterpartyID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromThread, !fromThread.isEmpty { return fromThread }

        let fromDraft = draft.targetCounterpartyID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromDraft, !fromDraft.isEmpty { return fromDraft }

        let candidate = thread.candidateCounterpartyIDs.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return candidate.isEmpty ? nil : candidate
    }

    func persistThreadMutation(_ mutation: ExchangeThreadEngine.ThreadMutation) async throws {
        try await persistAlignedThread(mutation.thread, turns: mutation.turns)
    }

    func persistAlignedThread(_ thread: ExchangeThread, turns: [ExchangeTurn]) async throws {
        try await store.performTransaction {
            try await store.updateThread(thread)
            for turn in turns {
                try await store.appendTurn(turn)
            }
        }
    }

    /// Mirrors `ExchangeOrchestrator.markOutboundConfirmed`: thread → `awaitingResponse`, draft `.sent`,
    /// outbox completed (acknowledged, inactive) so flush will not re-transmit.
    func finalizeSuccessfulRelayOutbound(
        draftID: ExchangeMessageDraft.ID,
        inFlight: ExchangeOutboxItem,
        confirmationReference: String,
        relayNote: String?,
        stampedAt: Date,
        counterpartyDisplayName: String?
    ) async throws -> (finalizedOutbox: ExchangeOutboxItem, threadID: UUID) {
        if let existing = try await store.fetchOutboxItem(id: inFlight.id),
           existing.deliveryState.phase == .acknowledged {
            #if DEBUG
            refreshTraceFedLog(
                "[SendConfirmedDedup] action=skip envelopeID=\(existing.envelopeID) outboxItemID=\(existing.id.uuidString)"
            )
            #endif
            return (existing, inFlight.threadID)
        }

        let thread = try await store.requireThread(id: inFlight.threadID)
        let draft = try await store.requireDraft(id: draftID)

        let draftSent = draft.markingSent(
            externalReference: confirmationReference,
            at: stampedAt
        )

        let mutation = try threadEngine.markSendConfirmed(
            thread: thread,
            externalReference: confirmationReference,
            now: stampedAt
        )

        let afterSent = inFlight.updatingDeliveryState(
            inFlight.deliveryState.markingSent(
                externalReference: confirmationReference,
                externalEffect: .changed(description: "Relay accepted outbound coordination."),
                note: relayNote,
                at: stampedAt
            ),
            at: stampedAt
        )

        let finalized = afterSent.markingAcknowledged(
            externalReference: confirmationReference,
            note: relayNote ?? "Relay accepted outbound send.",
            at: stampedAt
        )

        let sentAudit = ExchangeAuditRecord.outboundSent(
            threadID: inFlight.threadID,
            outboxItemID: inFlight.id,
            envelopeID: inFlight.envelopeID,
            relatedNodeID: inFlight.targetNodeID,
            relatedDisplayName: counterpartyDisplayName,
            externalEffect: .changed(description: "Relay accepted outbound send."),
            createdAt: stampedAt
        )

        try await store.performTransaction {
            try await store.updateThread(mutation.thread)
            for turn in mutation.turns {
                try await store.appendTurn(turn)
            }
            try await store.saveDraft(draftSent)
            try await store.saveOutboxItem(finalized)
            try await store.appendAuditRecord(sentAudit)
        }

        return (finalized, mutation.thread.id)
    }

    func resolvedCounterpartyForOutbox(
        _ item: ExchangeOutboxItem
    ) async throws -> ExchangeCounterparty? {
        let thread = try await store.fetchThread(id: item.threadID)

        if let selectedCounterpartyID = thread?.selectedCounterpartyID,
           let selected = try await store.fetchCounterparty(id: selectedCounterpartyID) {
            return selected
        }

        if let direct = try await store.fetchCounterparty(id: item.targetNodeID) {
            return direct
        }

        if let storedCounterpartyID = item.metadata["counterparty_id"]?.exchangeNilIfBlank,
           let stored = try await store.fetchCounterparty(id: storedCounterpartyID) {
            return stored
        }

        return nil
    }

    // MARK: - Envelope compatibility / metadata helpers

    func compatibilityForInboundEnvelope(
        _ envelope: ExchangeRelayEnvelope
    ) async throws -> ExchangeInboxItem.Compatibility {
        let localIdentity = try await identityService.localIdentity()

        let incomingProtocol = envelope.protocolVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let supportedProtocols = localIdentity.supportedProtocolVersions.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        exchFedServiceLog(
            "compatibility.protocolCheck | incoming=\(incomingProtocol) | " +
                "supported=\(supportedProtocols.joined(separator: ","))"
        )

        let protocolIsSupported = ExchangeProtocolVersion.isSupported(
            incoming: incomingProtocol,
            supported: supportedProtocols
        )

        guard protocolIsSupported else {
            exchFedServiceLog(
                "compatibility.reject.unsupportedVersion | incoming=\(incomingProtocol) | supported=\(supportedProtocols.joined(separator: ","))"
            )
            return .unsupportedVersion(version: envelope.protocolVersion)
        }

        let verification = try await identityService.verifyEnvelopeSignature(
            envelope,
            expectedKeyID: envelope.sender.publicKeyID
        )

        switch verification {
        case .valid:
            return .supported

        case .missingSignature:
            // Bootstrap / private-network unsigned relay compatibility.
            // The bootstrapped HTTP relay does not attach signatures on behalf of
            // senders, so envelopes arrive with signature == nil. When the sender
            // has also declared no publicKeyID there is no key claim to verify
            // against, so we accept the envelope for reconciliation with
            // `inbound_auth_*` metadata — not as verified cryptographic identity.
            //
            // If a publicKeyID was declared but the signature is absent, reject it:
            // the key claim implies signature intent was present.
            if envelope.sender.publicKeyID == nil {
                return .supported
            }
            return .invalidSignature

        case .missingSenderKey, .keyMismatch, .invalidSignature:
            return .invalidSignature

        case .unsupportedSignatureVersion(let value):
            return .unsupportedVersion(version: value)

        case .malformed(let reason):
            return .malformed(reason: reason)
        }
    }

    func repairVersionRejectedInboxItems(now: Date) async throws {
        let localIdentity = try await identityService.localIdentity()
        let supported = localIdentity.supportedProtocolVersions

        let rejected = try await store.listInboxItems(
            filter: .init(
                processingStates: [.rejected],
                processableOnly: false
            )
        )

        var repairedCount = 0
        for item in rejected {
            guard case .unsupportedVersion = item.compatibility else { continue }
            let incoming = item.metadata["protocol_version"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !incoming.isEmpty else { continue }
            guard ExchangeProtocolVersion.isSupported(incoming: incoming, supported: supported) else { continue }

            var repaired = item
            repaired.compatibility = .supported
            repaired.processingState = .received
            repaired.updatedAt = now
            repaired.metadata["version_repair_applied"] = "true"
            repaired.metadata["version_repair_at"] = isoInstantString(now)
            repaired.metadata["version_repair_reason"] = "supported_protocol_migration"

            try await store.saveInboxItem(repaired)
            repairedCount += 1

            exchFedServiceLog(
                "reconcileInbox.versionRepair | inboxItemID=\(item.id.uuidString) | " +
                    "envelopeID=\(item.envelopeID) | incoming=\(incoming)"
            )
        }

        if repairedCount > 0 {
            exchFedServiceLog(
                "reconcileInbox.versionRepair.done | repaired=\(repairedCount)"
            )
        }
    }

    func envelopeEligibilityReason(
        _ error: ExchangeEnvelopeServiceError
    ) -> String {
        switch error {
        case .missingRecipientRoute:
            return "No resolvable route exists for this counterparty."
        case .routeNotAllowedByPosture:
            return "A route exists, but it is not allowed by the recipient's public posture."
        case .introductionRequired:
            return "This counterparty accepts contact only through an introduction or trusted path."
        case .contactClosed:
            return "This counterparty is currently closed to direct federation contact."
        case .contactNotAcceptingInbound:
            return "This counterparty is not currently accepting new inbound coordination."
        case .executionBasisMismatch(let reason):
            return reason
        }
    }

    func envelopeFailureCode(
        _ error: ExchangeEnvelopeServiceError
    ) -> String {
        switch error {
        case .missingRecipientRoute:
            return "no_route"
        case .routeNotAllowedByPosture:
            return "route_not_allowed_by_posture"
        case .introductionRequired:
            return "intro_required"
        case .contactClosed:
            return "contact_closed"
        case .contactNotAcceptingInbound:
            return "not_accepting_inbound"
        case .executionBasisMismatch:
            return "execution_basis_mismatch"
        }
    }

    func isDisclosureFailure(
        _ error: ExchangeEnvelopeServiceError
    ) -> Bool {
        false
    }

    func envelopeBlocksByPosture(
        _ error: ExchangeEnvelopeServiceError
    ) -> Bool {
        switch error {
        case .missingRecipientRoute:
            return false
        case .routeNotAllowedByPosture,
             .introductionRequired,
             .contactClosed,
             .contactNotAcceptingInbound:
            return true
        case .executionBasisMismatch:
            return false
        }
    }

    func stableEnvelopeID(
        from envelope: ExchangeRelayEnvelope
    ) -> String {
        if let key = envelope.ordering.idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }
        return envelope.id.uuidString
    }

    func stableEnvelopeKey(
        threadID: ExchangeThread.ID,
        draftID: ExchangeMessageDraft.ID,
        targetExecutionID: String
    ) -> String {
        "\(threadID.uuidString)|\(draftID.uuidString)|\(targetExecutionID)"
    }

    func isLiveOutboxItem(_ item: ExchangeOutboxItem) -> Bool {
        item.isActive && !item.deliveryState.phase.isTerminal
    }

    func payloadSummary(for draft: ExchangeMessageDraft) -> String {
        if let subject = draft.subject?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subject.isEmpty {
            return subject
        }

        let trimmed = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 {
            return trimmed
        }
        return String(trimmed.prefix(80)) + "…"
    }

    func inboundSummary(
        for envelope: ExchangeRelayEnvelope,
        resolvedBody: String? = nil,
        resolvedSubject: String? = nil
    ) -> String {
        if let subject = resolvedSubject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? envelope.payload.subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            return subject
        }

        let bodyText = resolvedBody ?? envelope.payload.body
        let trimmed = ExchangeUserFacingCopySanitizer
            .cleanReceivedFederationBody(bodyText)
            .cleaned
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 {
            return trimmed
        }
        return String(trimmed.prefix(80)) + "…"
    }

    func recipientNodeID(from envelope: ExchangeRelayEnvelope) -> String? {
        switch envelope.recipient.route {
        case .node(let id):
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .relayAddress, .email, .other:
            if let explicit = envelope.metadata["recipient_node_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !explicit.isEmpty {
                return explicit
            }
            return nil
        }
    }

    func persistIgnoredInboundEnvelope(
        stableEnvelopeID: String,
        envelope: ExchangeRelayEnvelope,
        route: ExchangeRelayRoute?,
        receivedAt: Date,
        localNodeID: String,
        reason: String,
        cleanedBody: String
    ) async throws -> ExchangeFederationReceiveResult {
        if let existing = try await store.fetchInboxItemByEnvelopeID(stableEnvelopeID) {
            let ignored = existing.markingDuplicateIgnored(at: receivedAt)
            try await store.saveInboxItem(ignored)
            return ExchangeFederationReceiveResult(inboxItem: ignored, auditRecord: nil)
        }

        let recipientNode = recipientNodeID(from: envelope)
        var metadata = inboundMetadata(
            envelope: envelope,
            cleanedBody: cleanedBody,
            bodySanitizedFromInternalScaffold: false,
            compatibility: .supported,
            authenticity: (status: "ignored", isUnverified: false, caution: nil),
            route: route
        )
        metadata["ignored_reason"] = reason
        metadata["ignored_local_node_id"] = localNodeID
        if let recipientNode, !recipientNode.isEmpty {
            metadata["recipient_node_id"] = recipientNode
        }
        let ignored = ExchangeInboxItem(
            receivedAt: receivedAt,
            updatedAt: receivedAt,
            envelopeID: stableEnvelopeID,
            threadID: nil,
            senderNodeID: envelope.sender.nodeID,
            senderDisplayName: envelope.sender.displayName,
            ordering: .init(
                sequenceNumber: envelope.ordering.sequenceNumber,
                parentEnvelopeID: envelope.ordering.parentEnvelopeID,
                senderTimestamp: envelope.createdAt
            ),
            compatibility: .supported,
            processingState: .duplicateIgnored,
            visibleSummary: inboundSummary(for: envelope, resolvedBody: cleanedBody),
            metadata: metadata
        )
        try await store.saveInboxItem(ignored)

        let audit = ExchangeAuditRecord(
            createdAt: receivedAt,
            threadID: nil,
            direction: .inbound,
            category: .duplicateIgnored,
            actor: .system,
            envelopeID: stableEnvelopeID,
            inboxItemID: ignored.id,
            summary: "Ignored inbound self-echo or mismatch envelope.",
            detail: "Ignored inbound envelope due to \(reason).",
            externalEffect: .none,
            relatedNodeID: envelope.sender.nodeID,
            relatedDisplayName: envelope.sender.displayName
        )
        try await store.appendAuditRecord(audit)
        return ExchangeFederationReceiveResult(inboxItem: ignored, auditRecord: audit)
    }

    func inboundMetadata(
        envelope: ExchangeRelayEnvelope,
        cleanedBody: String,
        decryptedSubject: String? = nil,
        bodySanitizedFromInternalScaffold: Bool,
        compatibility: ExchangeInboxItem.Compatibility,
        authenticity: (status: String, isUnverified: Bool, caution: String?),
        route: ExchangeRelayRoute?
    ) -> [String: String] {
        var metadata: [String: String] = [
            "protocol_version": envelope.protocolVersion,
            "payload_kind": envelope.payload.kind.rawValue,
            "disclosure_level": envelope.payload.disclosureLevel.rawValue,
            "body_preview": textPreview(cleanedBody, limit: 500),
            "inbound_auth_status": authenticity.status,
            "inbound_auth_unverified": authenticity.isUnverified ? "true" : "false",
            "inbound_compatibility": compatibilityMetadataValue(compatibility)
        ]
        if bodySanitizedFromInternalScaffold {
            metadata["body_sanitized_from_internal_scaffold"] = "true"
        }
        #if DEBUG
        if bodySanitizedFromInternalScaffold {
            metadata["raw_received_body_debug"] = textPreview(envelope.payload.body, limit: 1200)
        }
        #endif

        if let caution = authenticity.caution?.trimmingCharacters(in: .whitespacesAndNewlines),
           !caution.isEmpty {
            metadata["inbound_auth_caution"] = caution
        }

        if let subject = decryptedSubject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? envelope.payload.subject?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            metadata["subject_preview"] = subject
        }
        if let recipientNodeID = recipientNodeID(from: envelope),
           !recipientNodeID.isEmpty {
            metadata["recipient_node_id"] = recipientNodeID
        }

        if let route {
            metadata["route_kind"] = route.kind.rawValue
            metadata["route_destination"] = route.destination
        }

        if let parent = envelope.ordering.parentEnvelopeID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !parent.isEmpty {
            metadata["parent_envelope_id"] = parent
        }

        Self.mergeAllowlistedInboundEnvelopeAnchorMetadata(
            from: envelope.metadata,
            into: &metadata
        )

        return metadata
    }

    /// Copies only safe routing/anchor keys from the sender envelope into inbox metadata.
    private static let inboundEnvelopeAnchorMetadataAllowlist: [String] = [
        "selected_offer_id",
        "selected_public_profile_id",
        "public_profile_id",
        "selected_counterparty_id",
        "counterparty_id",
        "matched_offer_id",
        "matched_profile_id",
        "conversation_id",
        "conversation_surface",
        "conversation_kind",
        "root_envelope_id",
        "original_requester_envelope_id",
        "parent_envelope_id",
        "source_envelope_id",
        "reply_to_envelope_id",
        "contact_request",
        "introduction_request",
        "target_node_id",
        "sender_display_name",
        "dm_attachment_count",
        "dm_has_attachments",
        "dm_attachments_json",
        "dm_attachments_encrypted"
    ]

    static func mergeAllowlistedInboundEnvelopeAnchorMetadata(
        from envelopeMetadata: [String: String],
        into metadata: inout [String: String]
    ) {
        for key in inboundEnvelopeAnchorMetadataAllowlist {
            guard let raw = envelopeMetadata[key] else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            metadata[key] = trimmed
        }
    }

    static func firstNonEmptyMetadataValue(
        keys: [String],
        in metadata: [String: String]
    ) -> String? {
        for key in keys {
            guard let raw = metadata[key] else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return trimmed
        }
        return nil
    }

    func patchThreadWithInboundAnchors(
        _ thread: ExchangeThread,
        inboxMetadata: [String: String],
        envelopeID: String,
        now: Date
    ) -> ExchangeThread {
        var copy = thread

        if let inboundOffer = Self.firstNonEmptyMetadataValue(
            keys: ["selected_offer_id", "matched_offer_id"],
            in: inboxMetadata
        ) {
            if let existing = copy.selectedOfferID?.exchangeNilIfBlank {
                if existing.caseInsensitiveCompare(inboundOffer) != .orderedSame {
                    copy.metadata["inbound_anchor_offer_mismatch"] = "true"
                    copy.metadata["inbound_anchor_offer_inbound_suffix"] =
                        Self.clippedAnchorDiagnosticSuffix(inboundOffer)
                    copy.metadata["inbound_anchor_offer_thread_suffix"] =
                        Self.clippedAnchorDiagnosticSuffix(existing)
                    copy.updatedAt = now
                    #if DEBUG
                    exchFedServiceLog(
                        "reconcileInboundAnchor.offer.mismatch | thread=\(copy.id.uuidString) | " +
                            "envelopeID=\(envelopeID) | threadSuffix=\(Self.clippedAnchorDiagnosticSuffix(existing)) | " +
                            "inboundSuffix=\(Self.clippedAnchorDiagnosticSuffix(inboundOffer))"
                    )
                    #endif
                } else {
                    #if DEBUG
                    exchFedServiceLog(
                        "reconcileInboundAnchor.offer.unchanged | thread=\(copy.id.uuidString) | " +
                            "envelopeID=\(envelopeID) | offerID=\(inboundOffer)"
                    )
                    #endif
                }
            } else {
                copy.selectedOfferID = inboundOffer
                copy.updatedAt = now
                #if DEBUG
                exchFedServiceLog(
                    "reconcileInboundAnchor.offer.applied | thread=\(copy.id.uuidString) | " +
                        "envelopeID=\(envelopeID) | offerID=\(inboundOffer)"
                )
                #endif
            }
        }

        if let inboundProfile = Self.firstNonEmptyMetadataValue(
            keys: ["selected_public_profile_id", "public_profile_id", "matched_profile_id"],
            in: inboxMetadata
        ) {
            if let existing = copy.selectedPublicProfileID?.exchangeNilIfBlank {
                if existing.caseInsensitiveCompare(inboundProfile) != .orderedSame {
                    copy.metadata["inbound_anchor_profile_mismatch"] = "true"
                    copy.metadata["inbound_anchor_profile_inbound_suffix"] =
                        Self.clippedAnchorDiagnosticSuffix(inboundProfile)
                    copy.metadata["inbound_anchor_profile_thread_suffix"] =
                        Self.clippedAnchorDiagnosticSuffix(existing)
                    copy.updatedAt = now
                    #if DEBUG
                    exchFedServiceLog(
                        "reconcileInboundAnchor.profile.mismatch | thread=\(copy.id.uuidString) | " +
                            "envelopeID=\(envelopeID) | threadSuffix=\(Self.clippedAnchorDiagnosticSuffix(existing)) | " +
                            "inboundSuffix=\(Self.clippedAnchorDiagnosticSuffix(inboundProfile))"
                    )
                    #endif
                } else {
                    #if DEBUG
                    exchFedServiceLog(
                        "reconcileInboundAnchor.profile.unchanged | thread=\(copy.id.uuidString) | " +
                            "envelopeID=\(envelopeID) | profileID=\(inboundProfile)"
                    )
                    #endif
                }
            } else {
                copy.selectedPublicProfileID = inboundProfile
                copy.updatedAt = now
                #if DEBUG
                exchFedServiceLog(
                    "reconcileInboundAnchor.profile.applied | thread=\(copy.id.uuidString) | " +
                        "envelopeID=\(envelopeID) | profileID=\(inboundProfile)"
                )
                #endif
            }
        }

        if let conversationID = Self.firstNonEmptyMetadataValue(
            keys: ["conversation_id"],
            in: inboxMetadata
        ) {
            copy.metadata["conversation_id"] = conversationID
            copy.updatedAt = now
        }
        if let rootEnvelopeID = Self.firstNonEmptyMetadataValue(
            keys: ["root_envelope_id", "original_requester_envelope_id", "parent_envelope_id"],
            in: inboxMetadata
        ) {
            copy.metadata["root_envelope_id"] = rootEnvelopeID
            copy.updatedAt = now
        }
        if let originalRequesterEnvelopeID = Self.firstNonEmptyMetadataValue(
            keys: ["original_requester_envelope_id", "root_envelope_id"],
            in: inboxMetadata
        ) {
            copy.metadata["original_requester_envelope_id"] = originalRequesterEnvelopeID
            copy.updatedAt = now
        }

        return copy
    }

    /// Short hash-like suffix for anchor mismatch diagnostics (avoid persisting full remote ids).
    private static func clippedAnchorDiagnosticSuffix(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 8 { return trimmed }
        return String(trimmed.suffix(8))
    }

    /// Reconcile audit enrichment for inbound anchor disagreement (thread anchors are authoritative).
    private static func anchorMismatchAuditMetadata(from thread: ExchangeThread) -> [String: String] {
        var out: [String: String] = [:]
        if thread.metadata["inbound_anchor_offer_mismatch"] == "true" {
            out["anchor_offer_mismatch"] = "true"
            if let s = thread.metadata["inbound_anchor_offer_inbound_suffix"]?.exchangeNilIfBlank {
                out["inbound_offer_suffix"] = s
            }
            if let s = thread.metadata["inbound_anchor_offer_thread_suffix"]?.exchangeNilIfBlank {
                out["thread_offer_suffix"] = s
            }
        }
        if thread.metadata["inbound_anchor_profile_mismatch"] == "true" {
            out["anchor_profile_mismatch"] = "true"
            if let s = thread.metadata["inbound_anchor_profile_inbound_suffix"]?.exchangeNilIfBlank {
                out["inbound_profile_suffix"] = s
            }
            if let s = thread.metadata["inbound_anchor_profile_thread_suffix"]?.exchangeNilIfBlank {
                out["thread_profile_suffix"] = s
            }
        }
        return out
    }

    func inboundAuthenticityFlags(
        for envelope: ExchangeRelayEnvelope
    ) async -> (status: String, isUnverified: Bool, caution: String?) {
        do {
            let verification = try await identityService.verifyEnvelopeSignature(
                envelope,
                expectedKeyID: envelope.sender.publicKeyID
            )
            switch verification {
            case .valid:
                return ("verified", false, nil)
            case .missingSignature:
                if envelope.sender.publicKeyID == nil {
                    return ("unverified_unsigned_bootstrap_compat", true, "missing_signature_no_sender_key_bootstrap_compat")
                }
                return ("unverified_missing_signature", true, "missing_signature")
            case .missingSenderKey:
                return ("unverified_missing_sender_key", true, "missing_sender_key")
            case .keyMismatch:
                return ("unverified_key_mismatch", true, "sender_key_mismatch")
            case .invalidSignature:
                return ("unverified_invalid_signature", true, "invalid_signature")
            case .unsupportedSignatureVersion(let value):
                let suffix = value?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return (
                    "unverified_unsupported_signature_version",
                    true,
                    suffix.isEmpty ? "unsupported_signature_version" : "unsupported_signature_version_\(suffix)"
                )
            case .malformed:
                return ("unverified_malformed_signature", true, "malformed_signature")
            }
        } catch {
            return ("unverified_signature_check_error", true, "signature_check_error")
        }
    }

    func compatibilityMetadataValue(
        _ compatibility: ExchangeInboxItem.Compatibility
    ) -> String {
        switch compatibility {
        case .supported:
            return "supported"
        case .unsupportedVersion:
            return "unsupported_version"
        case .unsupportedPayload:
            return "unsupported_payload"
        case .invalidSignature:
            return "invalid_signature"
        case .malformed:
            return "malformed"
        }
    }

    func compatibilityFailureDetail(
        _ compatibility: ExchangeInboxItem.Compatibility
    ) -> String {
        switch compatibility {
        case .supported:
            return "Supported."
        case .unsupportedVersion(let version):
            if let version, !version.isEmpty {
                return "Unsupported protocol version \(version)."
            }
            return "Unsupported protocol version."
        case .unsupportedPayload(let kind):
            if let kind, !kind.isEmpty {
                return "Unsupported payload kind \(kind)."
            }
            return "Unsupported payload."
        case .invalidSignature:
            return "Envelope signature validation failed."
        case .malformed(let reason):
            return reason
        }
    }

    func disclosureLevel(
        from rawValue: String?
    ) -> ExchangeRelayEnvelope.Payload.DisclosureLevel {
        guard let rawValue,
              let value = ExchangeRelayEnvelope.Payload.DisclosureLevel(rawValue: rawValue) else {
            return .balanced
        }
        return value
    }

    func relayRoute(
        from metadata: [String: String]
    ) -> ExchangeRelayRoute? {
        guard let kindRaw = metadata["route_kind"],
              let kind = ExchangeRelayRoute.Kind(rawValue: kindRaw),
              let destination = metadata["route_destination"],
              !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return ExchangeRelayRoute(
            routeKey: "\(kind.rawValue):\(destination)",
            kind: kind,
            destination: destination,
            protocolVersion: metadata["protocol_version"] ?? ExchangeProtocolVersion.current
        )
    }

    func counterpartyDisplayName(
        for counterpartyID: String
    ) async throws -> String? {
        try await store.fetchCounterparty(id: counterpartyID)?.displayName
    }

    func relayFailureReason(_ error: Error) -> String {
        if let error = error as? ExchangeRelayClientError {
            switch error {
            case .unavailable(let reason):
                return reason
            case .unauthorized(let reason):
                return reason
            case .invalidEnvelope(let reason):
                return reason
            case .invalidSyncRequest(let reason):
                return reason
            case .rejected(let reason):
                return reason
            case .incompatibleVersion(let version):
                if let version, !version.isEmpty {
                    return "Incompatible relay version \(version)."
                }
                return "Incompatible relay version."
            case .transportFailure(let reason):
                return reason
            case .rateLimited(let reason, _):
                return reason
            }
        }

        if let error = error as? ExchangeFederationError {
            switch error {
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

        if error is ExchangePrivateE2EESendBlockedError {
            return ExchangePrivateE2EESendBlockedError.userFacingMessage
        }

        return String(describing: error)
    }

    func relayFailureCode(_ error: Error) -> String {
        if let error = error as? ExchangeRelayClientError {
            switch error {
            case .unavailable:
                return "relay_unavailable"
            case .unauthorized:
                return "relay_unauthorized"
            case .invalidEnvelope:
                return "invalid_envelope"
            case .invalidSyncRequest:
                return "invalid_sync_request"
            case .rejected:
                return "relay_rejected"
            case .incompatibleVersion:
                return "incompatible_version"
            case .transportFailure:
                return "transport_failure"
            case .rateLimited:
                return "rate_limited"
            }
        }

        if let error = error as? ExchangeFederationError {
            switch error {
            case .e2eeSendBlocked:
                return ExchangePrivateE2EESendBlockedError.errorCode
            default:
                break
            }
        }

        if error is ExchangePrivateE2EESendBlockedError {
            return ExchangePrivateE2EESendBlockedError.errorCode
        }

        return "unknown_error"
    }

    func relayRetryDelaySeconds(
        for error: Error,
        priority: ExchangeDeliveryState.Priority
    ) -> TimeInterval {
        if let relayError = error as? ExchangeRelayClientError,
           case .rateLimited(_, let retryAfterSeconds) = relayError {
            return TimeInterval(
                max(1, retryAfterSeconds ?? FederationHTTPErrorMessage.defaultRateLimitFallbackSeconds)
            )
        }
        return TimeInterval(transportPolicy.retryDelay(for: priority))
    }

    func outboxOrdering(
        _ lhs: ExchangeOutboxItem,
        _ rhs: ExchangeOutboxItem
    ) -> Bool {
        if lhs.deliveryState.priority.schedulerRank != rhs.deliveryState.priority.schedulerRank {
            return lhs.deliveryState.priority.schedulerRank > rhs.deliveryState.priority.schedulerRank
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func textPreview(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit))
    }

    func queueMetadata(
        thread: ExchangeThread,
        counterparty: ExchangeCounterparty,
        publicProfile: ExchangePublicNodeProfile,
        draftMetadata: [String: String],
        approvalMetadata: [String: String],
        route: ExchangeRelayRoute,
        disclosureLevel: ExchangeRelayEnvelope.Payload.DisclosureLevel,
        targetExecutionID: String,
        parentEnvelopeID: String?,
        conversationID: String?,
        rootEnvelopeID: String?,
        originalRequesterEnvelopeID: String?
    ) -> [String: String] {
        var metadata: [String: String] = [
            "route_kind": route.kind.rawValue,
            "route_destination": route.destination,
            "protocol_version": route.protocolVersion,
            "disclosure_level": disclosureLevel.rawValue,
            "public_profile_id": publicProfile.id,
            "public_profile_node_id": publicProfile.nodeID,
            "counterparty_id": counterparty.id,
            "target_execution_id": targetExecutionID,
            "visibility": publicProfile.visibility.rawValue,
            "availability": publicProfile.availability.rawValue,
            "accepting_inbound": publicProfile.reachability.acceptingInbound ? "true" : "false",
            "access_mode": publicProfile.reachability.accessMode.rawValue,
            "routeable_only": publicProfile.reachability.routeableOnly ? "true" : "false",
            "disclosure_ceiling": publicProfile.reachability.disclosureCeiling.rawValue
        ]

        if let selectedCounterpartyID = thread.selectedCounterpartyID?.exchangeNilIfBlank {
            metadata["selected_counterparty_id"] = selectedCounterpartyID
        }

        if let selectedPublicProfileID = thread.selectedPublicProfileID?.exchangeNilIfBlank {
            metadata["selected_public_profile_id"] = selectedPublicProfileID
        }

        if let selectedOfferID = thread.selectedOfferID?.exchangeNilIfBlank {
            metadata["selected_offer_id"] = selectedOfferID
        }

        if let selectedMatchRationale = thread.selectedMatchRationale?.exchangeNilIfBlank {
            metadata["selected_match_rationale"] = selectedMatchRationale
        }

        if let parentEnvelopeID = parentEnvelopeID?.exchangeNilIfBlank {
            metadata["parent_envelope_id"] = parentEnvelopeID
        }
        if let conversationID = conversationID?.exchangeNilIfBlank {
            metadata["conversation_id"] = conversationID
        }
        if let rootEnvelopeID = rootEnvelopeID?.exchangeNilIfBlank {
            metadata["root_envelope_id"] = rootEnvelopeID
        }
        if let originalRequesterEnvelopeID = originalRequesterEnvelopeID?.exchangeNilIfBlank {
            metadata["original_requester_envelope_id"] = originalRequesterEnvelopeID
        }

        for key in [
            "payload_kind",
            "contact_request",
            "introduction_request",
            "target_node_id",
            "sender_display_name",
            "conversation_surface",
            "conversation_kind",
            "trusted_node_manual_message",
            "dm_manual_v2"
        ] + DirectMessageAttachmentMetadata.federationMetadataKeys {
            if let value = draftMetadata[key]?.exchangeNilIfBlank {
                metadata[key] = value
                continue
            }
            if let value = approvalMetadata[key]?.exchangeNilIfBlank {
                metadata[key] = value
            }
        }

        return metadata
    }

    func outboundConversationCorrelation(
        thread: ExchangeThread,
        idempotencyKey: String
    ) -> (
        source: String,
        parentEnvelopeID: String?,
        conversationID: String,
        rootEnvelopeID: String,
        originalRequesterEnvelopeID: String?
    ) {
        let parent = thread.lastInboundEnvelopeID?.exchangeNilIfBlank
        let existingConversation = thread.metadata["conversation_id"]?.exchangeNilIfBlank
        let existingRoot = thread.metadata["root_envelope_id"]?.exchangeNilIfBlank
        let existingOriginal = thread.metadata["original_requester_envelope_id"]?.exchangeNilIfBlank

        let source = parent != nil ? "reply" : "initialInquiry"
        let root = existingRoot ?? existingOriginal ?? parent ?? idempotencyKey
        let conversation = existingConversation ?? root
        let originalRequester = existingOriginal ?? root
        return (source, parent, conversation, root, originalRequester)
    }

    func resolveInboundMessageText(for envelope: ExchangeRelayEnvelope) async -> ResolvedInboundMessageText {
        guard envelope.payload.encryption != nil else {
            return ResolvedInboundMessageText(
                body: envelope.payload.body,
                subject: envelope.payload.subject
            )
        }

        guard ExchangeFederationPrivateTextE2EE.isPrivateRelayEnvelope(envelope) else {
            ExchangeFederationPrivateTextE2EE.logReceive(
                encryptionPresent: true,
                decrypted: false,
                surface: ExchangeFederationPrivateTextE2EE.inboundConversationSurface(envelope),
                reason: "notEligible"
            )
            return ResolvedInboundMessageText(
                body: envelope.payload.body,
                subject: envelope.payload.subject
            )
        }

        let surface = ExchangeFederationPrivateTextE2EE.inboundConversationSurface(envelope)
        guard let encryption = envelope.payload.encryption else {
            return ResolvedInboundMessageText(
                body: envelope.payload.body,
                subject: envelope.payload.subject
            )
        }

        let localEncryptionMaterial: NodeEncryptionMaterial
        do {
            localEncryptionMaterial = try NodeIdentityVault.shared.loadOrCreateEncryptionMaterial()
        } catch {
            ExchangeFederationPrivateTextE2EE.logReceive(
                encryptionPresent: true,
                decrypted: false,
                surface: surface,
                reason: "missingLocalEncryptionKey"
            )
            return ResolvedInboundMessageText(
                body: ExchangeFederationPrivateTextE2EE.decryptFailurePlaceholder,
                subject: nil
            )
        }

        let senderNodeID = envelope.sender.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        var senderSigningPublicKey: String?
        if !senderNodeID.isEmpty {
            let keysClient = ExchangeHTTPDirectoryClient(baseURL: federationBaseURL)
            if let keys = try? await keysClient.fetchNodePublicKeys(nodeID: senderNodeID) {
                senderSigningPublicKey = keys.signingPublicKey
            }
        }

        do {
            let opened = try messageOpener.openDMText(
                encryption: encryption,
                senderSigningPublicKeyBase64: senderSigningPublicKey,
                localEncryptionMaterial: localEncryptionMaterial
            )
            ExchangeFederationPrivateTextE2EE.logReceive(
                encryptionPresent: true,
                decrypted: true,
                surface: surface,
                reason: nil
            )
            let attachments = DirectMessageAttachmentMetadata.localDescriptors(from: opened.attachments)
            if !attachments.isEmpty {
                ExchangeFederationAttachmentE2EE.logReceive(metadataPresent: true)
            }
            return ResolvedInboundMessageText(
                body: opened.body,
                subject: opened.subject,
                attachments: attachments
            )
        } catch {
            ExchangeFederationPrivateTextE2EE.logReceive(
                encryptionPresent: true,
                decrypted: false,
                surface: surface,
                reason: inboundDecryptFailureReason(error)
            )
            return ResolvedInboundMessageText(
                body: ExchangeFederationPrivateTextE2EE.decryptFailurePlaceholder,
                subject: nil
            )
        }
    }

    func inboundDecryptFailureReason(_ error: Error) -> String {
        guard let openerError = error as? ExchangeMessageOpenerError else {
            return "decryptError"
        }
        switch openerError {
        case .unsupportedScheme: return "unsupportedScheme"
        case .invalidCiphertext: return "invalidCiphertext"
        case .invalidEphemeralKey: return "invalidEphemeralKey"
        case .invalidSignature: return "invalidSignature"
        case .signatureVerificationFailed: return "signatureVerificationFailed"
        case .missingSenderSigningKey: return "missingSenderSigningKey"
        case .recipientKeyMismatch: return "recipientKeyMismatch"
        case .openingFailed: return "openingFailed"
        }
    }
}

private struct ResolvedInboundMessageText: Sendable {
    let body: String
    let subject: String?
    let attachments: [DirectMessageAttachmentDescriptor]

    init(
        body: String,
        subject: String?,
        attachments: [DirectMessageAttachmentDescriptor] = []
    ) {
        self.body = body
        self.subject = subject
        self.attachments = attachments
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Test seams (AnumCoreTests)

extension ExchangeDefaultFederationService {
    /// Test seam: mirrors canonical contact-signal classifier used for inbound routing.
    internal static func contactRequestContract_isInboundFriendOrContactRequestSignal(
        _ item: ExchangeInboxItem
    ) -> Bool {
        ExchangeContactSignalClassifier.isInboundContactRequest(item)
    }
}

private extension ExchangeRelayEnvelope.Payload.DisclosureLevel {
    func clamped(to policyLevel: Self) -> Self {
        switch (self, policyLevel) {
        case (_, .minimal):
            return .minimal
        case (.open, .balanced):
            return .balanced
        default:
            return self
        }
    }
}

private extension String {
    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
