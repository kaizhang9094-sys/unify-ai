import Foundation

#if DEBUG
@inline(__always)
private func exchSyncLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSyncEngine] \(message())")
}
@inline(__always)
private func refreshTraceSyncLog(_ message: @autoclosure () -> String) {
    Swift.print("[RefreshTrace] \(message())")
}
#else
@inline(__always)
private func exchSyncLog(_ message: @autoclosure () -> String) {}
@inline(__always)
private func refreshTraceSyncLog(_ message: @autoclosure () -> String) {}
#endif

public actor ExchangeSyncEngine: Sendable {
    public enum Trigger: String, Sendable, Hashable {
        case appLaunch
        case appBecameActive
        case manualRefresh
        case afterOutboundQueued
        case afterApprovalGranted
        /// Best-effort lightweight inbox/outbox sync only (foreground policy still applies — no discovery/LLM here).
        case silentPush
        /// Timer-driven inbox pull while Secretary workspace is visible (not an app-resume event).
        case foregroundInboxPoll
    }

    public enum Phase: String, Sendable, Hashable {
        case idle
        case inboundFetch
        case inboundIngest
        case inboundReconcile
        case inboundAck
        case outboundFlush
        case failed
    }

    public struct Status: Sendable, Hashable {
        public var phase: Phase
        public var isRunning: Bool
        public var lastTrigger: Trigger?
        public var startedAt: Date?
        public var lastCompletedAt: Date?
        public var lastErrorSummary: String?

        public init(
            phase: Phase = .idle,
            isRunning: Bool = false,
            lastTrigger: Trigger? = nil,
            startedAt: Date? = nil,
            lastCompletedAt: Date? = nil,
            lastErrorSummary: String? = nil
        ) {
            self.phase = phase
            self.isRunning = isRunning
            self.lastTrigger = lastTrigger
            self.startedAt = startedAt
            self.lastCompletedAt = lastCompletedAt
            self.lastErrorSummary = lastErrorSummary
        }
    }

    private let store: any ExchangeStore
    private let syncStateStore: any ExchangeSyncStateStore
    private let facade: ExchangeFacade
    private let relayClient: any ExchangeRelayClient
    private let runtimeMonitor: any ExchangeRuntimeActivityMonitor
    private let policy: ExchangeSyncPolicy

    private var status = Status()
    private var currentRunID: UUID?
    private var pendingRunRequested = false
    private var pendingTriggers: Set<Trigger> = []

    /// Increments only after a **successful** inbound fetch + outbound flush pass (relay pulled and checkpoint advanced).
    private var successfulRelayFetchSequence: UInt64 = 0
    private var lastSuccessfulRelayInboundItemCount: Int = 0
    private var lastSuccessfulRelayInboundPagesFetched: Int = 0

    /// Waiters for `await runPass` callers that coalesced behind an in-flight pass; resumed when `runPassLoop` exits.
    private var runPassCompletionWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        store: any ExchangeStore,
        syncStateStore: any ExchangeSyncStateStore,
        facade: ExchangeFacade,
        relayClient: any ExchangeRelayClient,
        runtimeMonitor: any ExchangeRuntimeActivityMonitor,
        policy: ExchangeSyncPolicy = .default
    ) {
        self.store = store
        self.syncStateStore = syncStateStore
        self.facade = facade
        self.relayClient = relayClient
        self.runtimeMonitor = runtimeMonitor
        self.policy = policy
    }

    public func currentStatus() -> Status {
        status
    }

    /// True when a prior sync failure scheduled `backoffUntil` in durable sync state.
    public func isBackoffActive(now: Date = Date()) async -> Bool {
        guard let syncState = try? await loadSyncState(now: now) else { return false }
        guard let backoffUntil = syncState.backoffUntil else { return false }
        return backoffUntil > now
    }

    /// Snapshot after the last **successful** relay inbox pass (for foreground polling / diagnostics).
    public func lastSuccessfulRelayFetchSnapshot() -> (sequence: UInt64, itemCount: Int, pagesFetched: Int) {
        (
            successfulRelayFetchSequence,
            lastSuccessfulRelayInboundItemCount,
            lastSuccessfulRelayInboundPagesFetched
        )
    }

    public func runPass(
        trigger: Trigger,
        now: Date = Date()
    ) async {
        if currentRunID != nil || status.isRunning {
            pendingRunRequested = true
            pendingTriggers.insert(trigger)
            refreshTraceSyncLog(
                "[FlushStart] runID=coalesced trigger=\(trigger.rawValue) queuedCount=coalesced checkpoint=n/a time=\(now)"
            )
            exchSyncLog("runPass coalesced trigger=\(trigger.rawValue)")
            #if DEBUG
            Swift.print(
                "[ExchangeSyncRunPass] event=coalesced_wait trigger=\(trigger.rawValue) activeRunID=\(currentRunID?.uuidString ?? "nil")"
            )
            #endif
            await withCheckedContinuation { continuation in
                runPassCompletionWaiters.append(continuation)
            }
            return
        }
        await runPassLoop(startingTrigger: trigger, now: now)
    }

    private func resumeRunPassCompletionWaiters() {
        guard !runPassCompletionWaiters.isEmpty else { return }
        let waiters = runPassCompletionWaiters
        runPassCompletionWaiters.removeAll()
        for continuation in waiters {
            continuation.resume()
        }
    }
}

private extension ExchangeSyncEngine {
    func runPassLoop(
        startingTrigger: Trigger,
        now: Date
    ) async {
        var trigger = startingTrigger
        var timestamp = now
        var bypassMinimumInterval = false
        var lastStartedRunID: UUID?

        defer {
            #if DEBUG
            let drained = !pendingRunRequested && pendingTriggers.isEmpty
            Swift.print(
                "[ExchangeSyncRunPass] event=complete runID=\(lastStartedRunID?.uuidString ?? "nil") pendingDrained=\(drained)"
            )
            #endif
            resumeRunPassCompletionWaiters()
        }

        while true {
            guard await canStartRun(
                trigger: trigger,
                now: timestamp,
                bypassMinimumInterval: bypassMinimumInterval
            ) else {
                exchSyncLog(
                    "runPass not started trigger=\(trigger.rawValue) " +
                    "(canStartRun false — see prior skip line for reason)"
                )
                if pendingRunRequested, let next = dequeuePendingTrigger() {
                    trigger = next
                    timestamp = Date()
                    bypassMinimumInterval = true
                    continue
                }
                return
            }

        let runID = UUID()
        lastStartedRunID = runID
        currentRunID = runID
        status = Status(
            phase: .inboundFetch,
            isRunning: true,
            lastTrigger: trigger,
            startedAt: now,
            lastCompletedAt: status.lastCompletedAt,
            lastErrorSummary: nil
        )

        #if DEBUG
        Swift.print(
            "[ExchangeSyncRunPass] event=start trigger=\(trigger.rawValue) runID=\(runID.uuidString)"
        )
        #endif
        exchSyncLog("run begin trigger=\(trigger.rawValue) runID=\(runID.uuidString)")
        refreshTraceSyncLog(
            "[InboxSyncStart] runID=\(runID.uuidString) trigger=\(trigger.rawValue) nodeID=local checkpoint=loading time=\(timestamp)"
        )

        do {
            var syncState = try await loadSyncState(now: timestamp)
            syncState = syncState.beginningRun(runID: runID, now: timestamp)
            try await syncStateStore.saveSyncState(syncState)

            let inboundCheckpointBefore = syncState.inboundCheckpoint
            refreshTraceSyncLog(
                "[InboxSyncStart] runID=\(runID.uuidString) trigger=\(trigger.rawValue) nodeID=local checkpoint=\(inboundCheckpointBefore ?? "nil") time=\(timestamp)"
            )

            status.phase = .inboundFetch
            let inboundFetched = try await syncInbound(
                from: inboundCheckpointBefore,
                now: timestamp,
                trigger: trigger
            )
            exchSyncLog(
                "paginated inbound complete items=\(inboundFetched.items.count) " +
                "pages=\(inboundFetched.pagesFetched) " +
                "nextCheckpoint=\(inboundFetched.nextCheckpoint ?? "nil")"
            )
            let inboundEnvelopeIDs = inboundFetched.items.map { $0.envelope.stableEnvelopeID }.joined(separator: ",")
            refreshTraceSyncLog(
                "[InboxSyncResult] runID=\(runID.uuidString) rawCount=\(inboundFetched.items.count) mappedCount=\(inboundFetched.items.count) envelopeIDs=\(inboundEnvelopeIDs) nextCheckpoint=\(inboundFetched.nextCheckpoint ?? inboundCheckpointBefore ?? "nil") time=\(Date())"
            )
            #if DEBUG
            Swift.print(
                "[DMReceiveLive][syncResult] trigger=\(trigger.rawValue) rawCount=\(inboundFetched.items.count) " +
                    "mappedCount=\(inboundFetched.items.count) envelopeIDs=\(inboundEnvelopeIDs)"
            )
            #endif

            status.phase = .outboundFlush
            refreshTraceSyncLog(
                "[FlushStart] runID=\(runID.uuidString) trigger=\(trigger.rawValue) queuedCount=unknown checkpoint=\(inboundCheckpointBefore ?? "nil") time=\(Date())"
            )
            #if DEBUG
            ExchangeBilateralConversationDebugTrace.activeFlushPassID = runID.uuidString
            defer { ExchangeBilateralConversationDebugTrace.activeFlushPassID = nil }
            #endif
            let flushResult = try await facade.flushOutbox(now: timestamp)
            exchSyncLog(
                "flush complete attempted=\(flushResult.attempted) " +
                "acknowledged=\(flushResult.acknowledged) " +
                "failed=\(flushResult.failed) deferred=\(flushResult.deferred) untouched=\(flushResult.untouched)"
            )
            refreshTraceSyncLog(
                "[FlushResult] runID=\(runID.uuidString) attempted=\(flushResult.attempted) acknowledged=\(flushResult.acknowledged) failed=\(flushResult.failed) deferred=\(flushResult.deferred) envelopeIDs=see-relay-send-logs time=\(Date())"
            )

            syncState = try await loadSyncState(now: timestamp)
            syncState = syncState
                .recordingSuccess(
                    inboundCheckpoint: inboundFetched.nextCheckpoint ?? inboundCheckpointBefore,
                    inboundSyncedAt: inboundFetched.didFetchAnything ? timestamp : syncState.lastInboundSyncAt,
                    outboundFlushedAt: timestamp,
                    reconciledAt: timestamp,
                    now: timestamp
                )
                .endingRun(now: timestamp)

            try await syncStateStore.saveSyncState(syncState)

            status = Status(
                phase: .idle,
                isRunning: false,
                lastTrigger: trigger,
                startedAt: nil,
                lastCompletedAt: timestamp,
                lastErrorSummary: nil
            )
            currentRunID = nil

            exchSyncLog(
                "run success trigger=\(trigger.rawValue) " +
                "fetched=\(inboundFetched.items.count) " +
                "nextCheckpoint=\(inboundFetched.nextCheckpoint ?? "nil")"
            )

            successfulRelayFetchSequence += 1
            lastSuccessfulRelayInboundItemCount = inboundFetched.items.count
            lastSuccessfulRelayInboundPagesFetched = inboundFetched.pagesFetched
        } catch {
            let failureSummary = failureSummary(for: error)
            let failureDomain = failureDomain(for: error)

            do {
                var syncState = try await loadSyncState(now: timestamp)
                let nextFailureCount = syncState.consecutiveFailureCount + 1
                let backoff = backoffUntilDate(
                    for: error,
                    failureCount: nextFailureCount,
                    now: timestamp
                )

                syncState = syncState
                    .recordingFailure(
                        summary: failureSummary,
                        domain: failureDomain,
                        backoffUntil: backoff,
                        now: timestamp
                    )
                    .endingRun(now: timestamp)

                try await syncStateStore.saveSyncState(syncState)
            } catch {
                exchSyncLog("failed to persist sync failure state: \(error)")
            }

            status = Status(
                phase: .failed,
                isRunning: false,
                lastTrigger: trigger,
                startedAt: nil,
                lastCompletedAt: timestamp,
                lastErrorSummary: failureSummary
            )
            currentRunID = nil

            exchSyncLog("run failed trigger=\(trigger.rawValue) error=\(failureSummary)")
        }

            guard pendingRunRequested, let next = dequeuePendingTrigger() else {
                return
            }
            trigger = next
            timestamp = Date()
            bypassMinimumInterval = true
        }
    }
}

extension ExchangeSyncEngine {
    struct InboundFetchResult: Sendable {
        var items: [ExchangeRelayInboundItem]
        var nextCheckpoint: String?
        var didFetchAnything: Bool
        var pagesFetched: Int
    }

    struct AckResult: Sendable {
        var attempted: Int
        var succeeded: Int
        var failed: Int

        init(
            attempted: Int = 0,
            succeeded: Int = 0,
            failed: Int = 0
        ) {
            self.attempted = attempted
            self.succeeded = succeeded
            self.failed = failed
        }
    }

    func canStartRun(
        trigger: Trigger,
        now: Date,
        bypassMinimumInterval: Bool = false
    ) async -> Bool {
        guard currentRunID == nil, !status.isRunning else {
            exchSyncLog("skip run: already running")
            return false
        }

        let runtime = await runtimeMonitor.snapshot()

        if policy.blocksWhenThermalCritical && runtime.isThermalCritical {
            exchSyncLog("skip run: thermal critical")
            return false
        }

        if !policy.allowsSyncWhileGenerating && runtime.isGenerating {
            exchSyncLog("skip run: generation in progress")
            return false
        }

        if policy.defersWhenLowPowerModeEnabled && runtime.isLowPowerModeEnabled {
            exchSyncLog("skip run: low power mode enabled")
            return false
        }

        do {
            let syncState = try await loadSyncState(now: now)

            if let backoffUntil = syncState.backoffUntil, backoffUntil > now {
                exchSyncLog("skip run: backoff active until \(backoffUntil)")
                return false
            }

            if !bypassMinimumInterval {
                let minimumInterval = policy.minimumInterval(for: trigger)
                if minimumInterval > 0,
                   let lastAttemptAt = syncState.lastAttemptAt,
                   now.timeIntervalSince(lastAttemptAt) < minimumInterval {
                    let elapsed = now.timeIntervalSince(lastAttemptAt)
                    exchSyncLog(
                        "skip run: minimum interval not reached for \(trigger.rawValue) " +
                        "elapsed=\(elapsed)s required=\(minimumInterval)s"
                    )
                    return false
                }
            }
        } catch {
            exchSyncLog("warning: could not load sync state before run: \(error)")
        }

        return true
    }

    func dequeuePendingTrigger() -> Trigger? {
        guard pendingRunRequested else { return nil }
        let trigger = pendingTriggers.first ?? .manualRefresh
        pendingTriggers.removeAll()
        pendingRunRequested = false
        exchSyncLog("runPass dequeued coalesced trigger=\(trigger.rawValue)")
        return trigger
    }

    func loadSyncState(now: Date) async throws -> ExchangeSyncState {
        if let existing = try await syncStateStore.fetchSyncState(id: ExchangeSyncState.primaryID) {
            return existing
        }

        let initial = ExchangeSyncState.initial(now: now)
        try await syncStateStore.saveSyncState(initial)
        return initial
    }

    func syncInbound(
        from checkpoint: String?,
        now: Date,
        trigger: Trigger
    ) async throws -> InboundFetchResult {
        exchSyncLog("syncInbound begin checkpoint=\(checkpoint ?? "nil")")

        let maxPagesPerRun = 10
        var allItems: [ExchangeRelayInboundItem] = []
        allItems.reserveCapacity(policy.maxInboundBatchSize * maxPagesPerRun)

        var pageCursor = checkpoint
        var didFetchAnything = false
        var pagesFetched = 0
        var lastNextCursor: String?

        for pageIndex in 0..<maxPagesPerRun {
            let request = ExchangeRelayInboxSyncRequest(
                cursor: pageCursor,
                limit: policy.maxInboundBatchSize,
                nodeID: nil
            )

            let response = try await relayClient.syncInbox(request: request)
            pagesFetched += 1

            exchSyncLog(
                "syncInbound page=\(pageIndex) rawCount=\(response.receipts.count) " +
                "nextCursor=\(response.nextCursor ?? "nil") " +
                "hasMore=\(response.hasMore)"
            )

            if response.receipts.isEmpty {
                lastNextCursor = response.nextCursor
                refreshTraceSyncLog(
                    "[InboxSyncResult] runID=\(currentRunID?.uuidString ?? "unknown") rawCount=0 mappedCount=0 envelopeIDs= nextCheckpoint=\(response.nextCursor ?? pageCursor ?? "nil") time=\(Date())"
                )
                return InboundFetchResult(
                    items: allItems,
                    nextCheckpoint: response.nextCursor ?? pageCursor,
                    didFetchAnything: didFetchAnything,
                    pagesFetched: pagesFetched
                )
            }

            status.phase = .inboundIngest

            var pageItems: [ExchangeRelayInboundItem] = []
            pageItems.reserveCapacity(response.receipts.count)
            var ignoredEnvelopeIDs: Set<String> = []

            for item in response.receipts {
                let receiveResult = try await facade.receiveEnvelope(
                    item.envelope,
                    route: item.route,
                    receivedAt: item.receivedAt
                )
                if receiveResult.inboxItem.processingState == .duplicateIgnored {
                    ignoredEnvelopeIDs.insert(item.envelope.stableEnvelopeID.trimmingCharacters(in: .whitespacesAndNewlines))
                }

                pageItems.append(item)
                allItems.append(item)

                exchSyncLog(
                    "syncInbound ingested receiptID=\(item.receiptID) " +
                    "envelopeID=\(item.envelope.stableEnvelopeID) " +
                    "receivedAt=\(item.receivedAt)"
                )
            }

            didFetchAnything = true

            status.phase = .inboundReconcile
            facade.setActiveInboundReconcileTrigger(trigger)
            let reconcileResult = try await facade.reconcileInbox(now: now)
            exchSyncLog(
                "syncInbound reconcile page=\(pageIndex) reconciled=\(reconcileResult.reconciledCount) " +
                "deferred=\(reconcileResult.deferredCount) rejected=\(reconcileResult.rejectedCount)"
            )
            let reconciledThreadIDs = reconcileResult.reconciledThreadIDs.map(\.uuidString).joined(separator: ",")
            refreshTraceSyncLog(
                "[ReconcileResult] runID=\(currentRunID?.uuidString ?? "unknown") reconciled=\(reconcileResult.reconciledCount) deferred=\(reconcileResult.deferredCount) rejected=\(reconcileResult.rejectedCount) threadIDs=\(reconciledThreadIDs) time=\(Date())"
            )

            let reconciledEnvelopeIDs = Set(
                reconcileResult.reconciledEnvelopeIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            )
            let ackableItems = pageItems.filter { item in
                let stableID = item.envelope.stableEnvelopeID.trimmingCharacters(in: .whitespacesAndNewlines)
                return !stableID.isEmpty
                    && (reconciledEnvelopeIDs.contains(stableID) || ignoredEnvelopeIDs.contains(stableID))
            }

            status.phase = .inboundAck
            let ackResult = try await acknowledgeProcessedInbound(
                for: ackableItems,
                now: now
            )
            exchSyncLog(
                "syncInbound ack page=\(pageIndex) attempted=\(ackResult.attempted) " +
                "succeeded=\(ackResult.succeeded) failed=\(ackResult.failed)"
            )

            lastNextCursor = response.nextCursor

            let nextTrimmed = response.nextCursor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasNonBlankNext = !nextTrimmed.isEmpty
            let shouldContinue = response.hasMore && hasNonBlankNext
            if !shouldContinue {
                return InboundFetchResult(
                    items: allItems,
                    nextCheckpoint: response.nextCursor ?? pageCursor,
                    didFetchAnything: didFetchAnything,
                    pagesFetched: pagesFetched
                )
            }

            let next = nextTrimmed

            if next == pageCursor {
                exchSyncLog("syncInbound pagination stall nextCursor equals checkpoint")
                return InboundFetchResult(
                    items: allItems,
                    nextCheckpoint: next,
                    didFetchAnything: didFetchAnything,
                    pagesFetched: pagesFetched
                )
            }

            let previous = pageCursor
            pageCursor = next
            if pageCursor == previous {
                exchSyncLog("syncInbound pagination stall checkpoint unchanged after advance")
                return InboundFetchResult(
                    items: allItems,
                    nextCheckpoint: next,
                    didFetchAnything: didFetchAnything,
                    pagesFetched: pagesFetched
                )
            }
        }

        return InboundFetchResult(
            items: allItems,
            nextCheckpoint: lastNextCursor ?? pageCursor,
            didFetchAnything: didFetchAnything,
            pagesFetched: pagesFetched
        )
    }

    func acknowledgeProcessedInbound(
        for items: [ExchangeRelayInboundItem],
        now: Date
    ) async throws -> AckResult {
        guard !items.isEmpty else {
            exchSyncLog("ack skip: no inbound items")
            return AckResult()
        }

        var acknowledgements: [ExchangeRelayInboxAcknowledgement] = []
        acknowledgements.reserveCapacity(items.count)

        for item in items {
            let receiptID = item.receiptID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !receiptID.isEmpty else {
                exchSyncLog(
                    "ack skip missing receiptID envelopeID=\(item.envelope.stableEnvelopeID)"
                )
                continue
            }

            acknowledgements.append(
                ExchangeRelayInboxAcknowledgement(
                    receiptID: receiptID,
                    envelopeID: item.externalReference ?? item.envelope.stableEnvelopeID,
                    acknowledgedAt: now,
                    result: item.compatibility.isProcessable ? .processed : .incompatible,
                    note: nil
                )
            )
        }

        guard !acknowledgements.isEmpty else {
            exchSyncLog("ack skip: nothing ackable after filtering")
            return AckResult()
        }

        let response = try await relayClient.acknowledgeInboxItems(acknowledgements)

        let attempted = acknowledgements.count
        let succeeded = response.acknowledgedReceiptIDs.count
        let failed = max(0, attempted - succeeded)

        exchSyncLog(
            "ack server response updatedCount=\(response.updatedCount) " +
            "acknowledged=\(response.acknowledgedReceiptIDs.count) " +
            "rejected=\(response.rejectedReceiptIDs.count)"
        )

        return AckResult(
            attempted: attempted,
            succeeded: succeeded,
            failed: failed
        )
    }

    func failureSummary(for error: Error) -> String {
        if let storeError = error as? ExchangeStoreError {
            return String(describing: storeError)
        }
        return String(describing: error)
    }

    func failureDomain(for error: Error) -> String {
        String(reflecting: type(of: error))
    }

    func backoffUntilDate(for error: Error, failureCount: Int, now: Date) -> Date {
        if let relayError = error as? ExchangeRelayClientError,
           case .rateLimited(_, let retryAfterSeconds) = relayError {
            let seconds = max(1, retryAfterSeconds ?? FederationHTTPErrorMessage.defaultRateLimitFallbackSeconds)
            return now.addingTimeInterval(TimeInterval(seconds))
        }

        return now.addingTimeInterval(policy.backoffInterval(for: failureCount))
    }
}
