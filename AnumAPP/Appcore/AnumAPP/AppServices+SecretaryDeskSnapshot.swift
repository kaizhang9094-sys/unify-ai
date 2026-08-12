import Foundation
import AnumCore

extension AppServices {
    /// Echo reasons that should not rerun heavy desk assembly right after a recent commit.
    private static let deskSnapshotCoalesceEchoReasons: Set<String> = [
        "workspaceMount",
        SecretaryRefreshReason.appLaunch.rawValue,
        SecretaryRefreshReason.federationSync.rawValue,
        SecretaryRefreshReason.appForeground.rawValue,
        SecretaryRefreshReason.manual.rawValue,
    ]

    /// Short window for duplicate non-force refreshes during cold open.
    private static let deskSnapshotColdStartCoalesceInterval: TimeInterval = 20

    /// Kicks a coalesced desk snapshot refresh (returns immediately; work runs on the main actor).
    @MainActor
    func refreshSecretaryDeskSnapshot(
        reason: String,
        force: Bool = false,
        preferredThreadID: ExchangeThread.ID? = nil
    ) {
        enqueueSecretaryDeskSnapshotRefresh(
            reason: reason,
            force: force,
            preferredThreadID: preferredThreadID
        )
    }

    /// Enqueues refresh and awaits until the in-flight pass (and any real or skipped tail) finishes.
    @MainActor
    func refreshSecretaryDeskSnapshotAwaiting(
        reason: String,
        force: Bool = false,
        preferredThreadID: ExchangeThread.ID? = nil
    ) async {
        enqueueSecretaryDeskSnapshotRefresh(
            reason: reason,
            force: force,
            preferredThreadID: preferredThreadID
        )

        while let task = secretaryDeskSnapshotRefreshTask {
            await task.value
        }
    }

    /// Used by debounced `requestSecretaryRefresh` before scheduling heavy desk assembly.
    @MainActor
    func deskSnapshotSkipCauseIfRedundant(reason: String, force: Bool = false) async -> String? {
        await shouldSkipRedundantDeskSnapshotRefresh(reason: reason, force: force)
    }

    /// Records pending refresh state and starts the coalesced `@MainActor` task when needed.
    @MainActor
    private func enqueueSecretaryDeskSnapshotRefresh(
        reason: String,
        force: Bool,
        preferredThreadID: ExchangeThread.ID?
    ) {
        if let preferredThreadID {
            secretaryDeskPreferredThreadID = preferredThreadID
        }

        if force {
            secretaryDeskSnapshotPendingForce = true
        }

        let inFlight = secretaryDeskSnapshotRefreshTask != nil
        let hasSnapshot = secretaryDeskSnapshot != nil

        #if DEBUG
        print(
            "[DeskSnapshotCoalesce] enqueue reason=\(reason) force=\(force) " +
            "inFlight=\(inFlight) hasSnapshot=\(hasSnapshot) " +
            "pendingForce=\(secretaryDeskSnapshotPendingForce)"
        )
        #endif

        if inFlight {
            mergeSecretaryDeskSnapshotTailCandidate(reason: reason, force: force)
            return
        }

        secretaryDeskSnapshotPendingReason = reason
        if force {
            secretaryDeskSnapshotPendingForce = true
        }

        if !force,
           let skipCause = deskSnapshotSkipCauseIfRedundantSynchronously(reason: reason) {
            #if DEBUG
            print(
                "[DeskSnapshotCoalesce] skipBeforeRun reason=\(reason) cause=\(skipCause) " +
                "generation=\(secretaryDeskSnapshot?.generation ?? 0)"
            )
            #endif
            clearSecretaryDeskSnapshotQueueState()
            return
        }

        startSecretaryDeskSnapshotRefreshTask()
    }

    @MainActor
    private func mergeSecretaryDeskSnapshotTailCandidate(reason: String, force: Bool) {
        if force {
            secretaryDeskSnapshotTailCandidateForce = true
        }
        secretaryDeskSnapshotTailCandidateReason = reason
        #if DEBUG
        print(
            "[DeskSnapshotCoalesce] mergeTailCandidate reason=\(reason) " +
            "tailForce=\(secretaryDeskSnapshotTailCandidateForce)"
        )
        #endif
    }

    @MainActor
    private func clearSecretaryDeskSnapshotQueueState() {
        secretaryDeskSnapshotPendingReason = nil
        secretaryDeskSnapshotPendingForce = false
        secretaryDeskSnapshotTailCandidateReason = nil
        secretaryDeskSnapshotTailCandidateForce = false
    }

    /// Sync preflight for enqueue when no actor hop is required (snapshot + recent-finish rules only).
    @MainActor
    private func deskSnapshotSkipCauseIfRedundantSynchronously(reason: String) -> String? {
        if secretaryDeskSnapshot == nil { return nil }

        if reason == SecretaryRefreshReason.appLaunch.rawValue {
            return "deskAlreadyHydrated generation=\(secretaryDeskSnapshot?.generation ?? 0)"
        }

        if let lastFinished = secretaryDeskSnapshotLastRefreshFinishedAt,
           Date().timeIntervalSince(lastFinished) < Self.deskSnapshotColdStartCoalesceInterval,
           Self.deskSnapshotCoalesceEchoReasons.contains(reason) {
            return "recentRefreshFinish lastReason=\(secretaryDeskSnapshotLastRefreshReason ?? "?") " +
                "ageMs=\(Int(Date().timeIntervalSince(lastFinished) * 1000))"
        }

        return nil
    }

    @MainActor
    private func startSecretaryDeskSnapshotRefreshTask() {
        guard secretaryDeskSnapshotRefreshTask == nil else { return }

        secretaryDeskSnapshotRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.secretaryDeskSnapshotRefreshTask = nil
                self.clearSecretaryDeskSnapshotQueueState()
            }

            while self.secretaryDeskSnapshotPendingReason != nil
                || self.secretaryDeskSnapshotTailCandidateReason != nil {
                let isTailPass = self.secretaryDeskSnapshotPendingReason == nil
                let runReason: String
                let runForce: Bool

                if let pendingReason = self.secretaryDeskSnapshotPendingReason {
                    runReason = pendingReason
                    runForce = self.secretaryDeskSnapshotPendingForce
                    self.secretaryDeskSnapshotPendingReason = nil
                    self.secretaryDeskSnapshotPendingForce = false
                } else if let tailReason = self.secretaryDeskSnapshotTailCandidateReason {
                    runReason = tailReason
                    runForce = self.secretaryDeskSnapshotTailCandidateForce
                    self.secretaryDeskSnapshotTailCandidateReason = nil
                    self.secretaryDeskSnapshotTailCandidateForce = false
                } else {
                    break
                }

                if runForce {
                    #if DEBUG
                    print("[DeskSnapshotCoalesce] run reason=\(runReason) force=true")
                    #endif
                    await self.performSecretaryDeskSnapshotRefresh(
                        reason: runReason,
                        force: true,
                        preferredThreadID: self.secretaryDeskPreferredThreadID
                    )
                    #if DEBUG
                    print(
                        "[DeskSnapshotCoalesce] finish reason=\(runReason) " +
                        "generation=\(self.secretaryDeskSnapshot?.generation ?? 0)"
                    )
                    #endif
                    continue
                }

                if let skipCause = await self.shouldSkipRedundantDeskSnapshotRefresh(
                    reason: runReason,
                    force: false
                ) {
                    #if DEBUG
                    if isTailPass {
                        print(
                            "[DeskSnapshotCoalesce] tailSkipped reason=\(runReason) cause=\(skipCause) " +
                            "generation=\(self.secretaryDeskSnapshot?.generation ?? 0)"
                        )
                    } else {
                        print(
                            "[DeskSnapshotCoalesce] skipBeforeRun reason=\(runReason) cause=\(skipCause) " +
                            "generation=\(self.secretaryDeskSnapshot?.generation ?? 0)"
                        )
                    }
                    #endif
                    continue
                }

                #if DEBUG
                print("[DeskSnapshotCoalesce] run reason=\(runReason) force=false")
                #endif
                await self.performSecretaryDeskSnapshotRefresh(
                    reason: runReason,
                    force: false,
                    preferredThreadID: self.secretaryDeskPreferredThreadID
                )
                #if DEBUG
                print(
                    "[DeskSnapshotCoalesce] finish reason=\(runReason) " +
                    "generation=\(self.secretaryDeskSnapshot?.generation ?? 0)"
                )
                #endif
            }
        }
    }

    @MainActor
    private func shouldSkipRedundantDeskSnapshotRefresh(
        reason: String,
        force: Bool
    ) async -> String? {
        if force { return nil }
        guard secretaryDeskSnapshot != nil else { return nil }

        if reason == SecretaryRefreshReason.appLaunch.rawValue {
            return "deskAlreadyHydrated generation=\(secretaryDeskSnapshot?.generation ?? 0)"
        }

        if let lastFinished = secretaryDeskSnapshotLastRefreshFinishedAt,
           Date().timeIntervalSince(lastFinished) < Self.deskSnapshotColdStartCoalesceInterval,
           Self.deskSnapshotCoalesceEchoReasons.contains(reason) {
            return "recentRefreshFinish lastReason=\(secretaryDeskSnapshotLastRefreshReason ?? "?") " +
                "ageMs=\(Int(Date().timeIntervalSince(lastFinished) * 1000))"
        }

        if reason == SecretaryRefreshReason.federationSync.rawValue {
            let syncCompletedAt = await exchangeSyncEngine.currentStatus().lastCompletedAt
            if syncCompletedAt == secretaryDeskSnapshotExchangeSyncCompletedAt {
                return "syncUnchangedSinceSnapshot watermark=\(String(describing: syncCompletedAt))"
            }
        }

        return nil
    }

    @MainActor
    fileprivate func performSecretaryDeskSnapshotRefresh(
        reason: String,
        force: Bool,
        preferredThreadID: ExchangeThread.ID?
    ) async {
        #if DEBUG
        print("[DeskSnapshotActor] refresh start reason=\(reason) force=\(force)")
        #endif

        secretaryDeskSnapshotGeneration &+= 1
        let generation = secretaryDeskSnapshotGeneration

        #if DEBUG
        SecretaryDeskStartupAudit.snapshotRefreshes += 1
        let wallStart = CFAbsoluteTimeGetCurrent()
        print("[SecretaryDeskSnapshot] refresh start reason=\(reason) force=\(force) generation=\(generation)")
        #endif

        do {
            #if DEBUG
            SecretaryDeskStartupAudit.listDeskThreadsCalls += 1
            #endif

            async let loadedThreads = exchangeFacade.listDeskThreads(limit: 20)
            async let loadedInbox = exchangeFacade.listInboxItems()
            async let loadedApprovals = exchangeFacade.listPendingApprovals(forDeskSnapshot: true)

            let threads = try await loadedThreads
            let inbox = try await loadedInbox
            let approvals = try await loadedApprovals

            guard !Task.isCancelled else { return }

            let snapshot = SecretaryDeskSnapshotBuilder.build(
                rawThreadItems: threads,
                rawInboxItems: inbox,
                pendingApprovals: approvals,
                preferredThreadID: preferredThreadID,
                generation: generation
            )

            commitSecretaryDeskSnapshot(snapshot)
            secretaryDeskSnapshotLastRefreshReason = reason
            secretaryDeskSnapshotLastRefreshFinishedAt = Date()
            secretaryDeskSnapshotExchangeSyncCompletedAt = await exchangeSyncEngine.currentStatus().lastCompletedAt

            #if DEBUG
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - wallStart) * 1000)
            print(
                "[SecretaryDeskSnapshot] refresh done generation=\(generation) " +
                "threads=\(snapshot.threadItems.count) inbox=\(snapshot.visibleInboxItems.count) " +
                "pending=\(snapshot.pendingApprovals.count) elapsed=\(elapsedMs)ms"
            )
            SecretaryDeskStartupAudit.logSummary()
            #endif
        } catch {
            #if DEBUG
            print("[SecretaryDeskSnapshot] refresh failed reason=\(reason) error=\(error)")
            #endif
        }
    }
}
