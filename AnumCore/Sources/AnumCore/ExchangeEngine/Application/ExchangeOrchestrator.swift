import Foundation

#if DEBUG
private func secOrchLog(_ message: String) {
    print("[SEC][Orchestrator] \(message)")
}

private func discoveryUmbrellaLog(_ message: String) {
    print("[DiscoveryUmbrella] \(message)")
}

private func discoveryChildActivationLog(_ message: String) {
    print("[DiscoveryChildActivation] \(message)")
}
#else
private func secOrchLog(_ message: String) {}
private func discoveryUmbrellaLog(_ message: String) {}
private func discoveryChildActivationLog(_ message: String) {}
#endif

public struct ExchangeOrchestrator: Sendable {
    private let store: any ExchangeStore
    private let interpreter: ExchangeInterpreter
    private let postureModeler: ExchangePostureModeler
    private let expectationEngine: ExchangeExpectationEngine
    private let discoveryService: ExchangeDiscoveryService
    private let messageComposer: ExchangeMessageComposer
    private let approvalEngine: ExchangeApprovalEngine
    private let policyEngine: ExchangePolicyEngine
    private let threadEngine: ExchangeThreadEngine
    private let failureResolver: ExchangeFailureResolver
    private let summaryEngine: ExchangeSummaryEngine
    private let continuationCoordinator: ExchangeThreadContinuationCoordinator
    private let discoveryHeroProgressReporter: (any DiscoveryHeroProgressReporting)?
    private let requesterLocationProvider: (any ExchangeRequesterLocationProviding)?

    public init(
        store: any ExchangeStore,
        interpreter: ExchangeInterpreter,
        postureModeler: ExchangePostureModeler,
        expectationEngine: ExchangeExpectationEngine = .init(),
        discoveryService: ExchangeDiscoveryService,
        messageComposer: ExchangeMessageComposer,
        approvalEngine: ExchangeApprovalEngine,
        policyEngine: ExchangePolicyEngine,
        threadEngine: ExchangeThreadEngine,
        failureResolver: ExchangeFailureResolver,
        summaryEngine: ExchangeSummaryEngine,
        continuationCoordinator: ExchangeThreadContinuationCoordinator = .init(),
        discoveryHeroProgressReporter: (any DiscoveryHeroProgressReporting)? = nil,
        requesterLocationProvider: (any ExchangeRequesterLocationProviding)? = nil
    ) {
        self.store = store
        self.interpreter = interpreter
        self.postureModeler = postureModeler
        self.expectationEngine = expectationEngine
        self.discoveryService = discoveryService
        self.messageComposer = messageComposer
        self.approvalEngine = approvalEngine
        self.policyEngine = policyEngine
        self.threadEngine = threadEngine
        self.failureResolver = failureResolver
        self.summaryEngine = summaryEngine
        self.continuationCoordinator = continuationCoordinator
        self.discoveryHeroProgressReporter = discoveryHeroProgressReporter
        self.requesterLocationProvider = requesterLocationProvider
    }

    public func handleUserRequest(
        _ userText: String,
        existingThreadID: ExchangeThread.ID? = nil,
        progressContext: DiscoveryHeroProgressContext? = nil,
        now: Date = Date()
    ) async throws -> Response {
        let requestStart = CFAbsoluteTimeGetCurrent()
        secOrchLog("handleUserRequest BEGIN | existingThreadID=\(existingThreadID?.uuidString ?? "nil") | text='\(userText)'")

        DiscoveryHeroProgressNotifier.report(
            discoveryHeroProgressReporter,
            context: progressContext,
            stage: .understandingRequest,
            threadID: existingThreadID
        )

        let existingThread = try await loadExistingThread(id: existingThreadID)
        secOrchLog("existingThread loaded | id=\(existingThread?.id.uuidString ?? "nil") | state=\(existingThread.map { "\($0.state)" } ?? "nil")")

        let entrySurface: ExchangeInterpreter.InterpretationEntrySurface =
            existingThread == nil ? .searchComposer : .threadContinuation

        let interpretation = await interpreter.interpret(
            userText: userText,
            threadContext: existingThread.map {
                .init(
                    threadID: $0.id,
                    modeHint: $0.mode,
                    priorIntentTitle: $0.intent.title,
                    selectedCounterpartyID: $0.selectedCounterpartyID
                )
            },
            entrySurface: entrySurface
        )

        switch interpretation {
        case .needsClarification(let failure, let draftIntent, _, _):
            secOrchLog("interpret result = needsClarification | failure=\(failure.summary) | draftIntent=\(draftIntent?.title ?? "nil")")
        case .interpreted(let request):
            secOrchLog(
                "interpret result = interpreted | " +
                "title=\(request.intent.title) | " +
                "mode=\(request.intent.mode) | " +
                "shouldDiscover=\(request.shouldDiscover) | " +
                "shouldDraft=\(request.shouldDraft) | " +
                "semanticTags=\(request.semanticTags.joined(separator: ",")) | " +
                "discoveryKeywords=\(request.discoveryKeywords.joined(separator: ",")) | " +
                "targetTags=\(request.targetTags.joined(separator: ","))"
            )
        }

        do {
            let response: Response

            switch interpretation {
            case .needsClarification(
                let failure,
                let draftIntent,
                let draftPosture,
                let draftFacets
            ):
                if isTransientSearchIntentExtractorFailure(failure) {
                    secOrchLog(
                        "transient search-intent failure returned inline without persistence | reason=\(failure.reasonCode ?? "nil")"
                    )
                    response = buildTransientSearchIntentExtractorFailureResponse(
                        userText: userText,
                        failure: failure,
                        now: now
                    )
                } else {
                    response = try await handleClarificationNeeded(
                        existingThread: existingThread,
                        userText: userText,
                        failure: failure,
                        draftIntent: draftIntent,
                        draftFacets: draftFacets,
                        draftPosture: draftPosture,
                        now: now
                    )
                }

            case .interpreted(let request):
                response = try await handleInterpretedRequest(
                    existingThread: existingThread,
                    userText: userText,
                    request: request,
                    progressContext: progressContext,
                    now: now
                )
            }

            let totalMs = Int((CFAbsoluteTimeGetCurrent() - requestStart) * 1000)
            secOrchLog(
                "handleUserRequest END | thread=\(response.thread.id) | state=\(response.thread.state) | action=\(response.handoff.latestAction?.rawValue ?? "nil") | transientNonPersistent=\(response.isTransientNonPersistent) | total=\(totalMs)ms"
            )
            return response
        } catch {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - requestStart) * 1000)
            secOrchLog("handleUserRequest ERROR | total=\(totalMs)ms | err=\(error)")
            throw error
        }
    }
    
    public func refreshSearch(
        threadID: ExchangeThread.ID,
        now: Date = Date()
    ) async throws -> Response {
        let start = CFAbsoluteTimeGetCurrent()
        secOrchLog("refreshSearch BEGIN | threadID=\(threadID.uuidString)")

        let existingThread = try await store.requireThread(id: threadID)

        let refreshMutation = try threadEngine.refreshSearch(
            thread: existingThread,
            querySummary: searchQuerySummary(for: existingThread),
            now: now
        )

        try await store.performTransaction {
            try await persist(mutation: refreshMutation)
        }

        var turns = refreshMutation.turns

        let searchMutation = try threadEngine.startSearch(
            thread: refreshMutation.thread,
            querySummary: searchQuerySummary(for: refreshMutation.thread),
            now: now
        )

        try await store.performTransaction {
            try await persist(mutation: searchMutation)
        }
        turns.append(contentsOf: searchMutation.turns)

        let discovery = try await discoveryService.discoverAndRank(
            thread: searchMutation.thread
        )

        let response = try await buildDiscoveryResponse(
            userText: refreshMutation.thread.humanRequesterText,
            requestUserSummary: refreshMutation.thread.interpretation?.userSummary,
            baseTurns: turns,
            searchThread: searchMutation.thread,
            discovery: discovery,
            now: now
        )

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        secOrchLog(
            "refreshSearch END | thread=\(response.thread.id.uuidString) | state=\(response.thread.state.phaseTitle) | total=\(elapsedMs)ms"
        )

        return response
    }

    public func answerClarification(
        threadID: ExchangeThread.ID,
        answer: String,
        now: Date = Date()
    ) async throws -> Response {
        let start = CFAbsoluteTimeGetCurrent()
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        secOrchLog("answerClarification BEGIN | threadID=\(threadID) | answer='\(trimmedAnswer)'")

        let existingThread = try await store.requireThread(id: threadID)

        let answerMutation = try threadEngine.recordClarificationAnswer(
            thread: existingThread,
            answer: trimmedAnswer,
            now: now
        )

        try await store.performTransaction {
            try await persist(mutation: answerMutation)
        }

        let answeredThread = answerMutation.thread

        Task.detached(priority: .userInitiated) { [self] in
            await continueClarificationAnswerInBackground(
                threadID: answeredThread.id,
                answerText: trimmedAnswer,
                now: now
            )
        }

        let immediateResponse = try await buildThreadOnlyResponse(
            thread: answeredThread,
            summaryOverride: "Clarification received. Continuing with discovery.",
            handoffAction: .clarificationAnswered,
            federationReason: "Clarification was accepted locally and discovery is continuing."
        )

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        secOrchLog(
            "answerClarification EARLY_RETURN | thread=\(immediateResponse.thread.id) | state=\(immediateResponse.thread.state) | total=\(elapsedMs)ms"
        )

        return immediateResponse
    }

    /// Legacy inbound continuation handler (deterministic heuristic + drafts/approvals via `continuationCoordinator`).
    ///
    /// - Important: Live relay reconcile uses `ExchangeDefaultFederationService` + `ExchangeFacade`
    ///   (`reconcileInbox` → Second Half / agency); **do not wire new callers here**. Prefer letting
    ///   federation + Second Half evaluate inbound envelopes; this path duplicates older behavior and
    ///   risks diverging from the canonical pipeline when enabled.
    public func handleInboundMessage(
        threadID: ExchangeThread.ID,
        summary: String,
        body: String,
        now: Date = Date()
    ) async throws -> Response {
        secOrchLog("handleInboundMessage BEGIN | threadID=\(threadID) | summary='\(summary)'")
        let existingThread = try await store.requireThread(id: threadID)
        let evaluation = continuationCoordinator.evaluateInbound(
            thread: existingThread,
            summary: summary,
            body: body
        )
        secOrchLog("handleInboundMessage evaluation | action=\(String(describing: evaluation.decision.action)) | summary=\(evaluation.decision.summary)")

        let updatedThread = existingThread.settingExpectation(
            evaluation.expectation,
            at: now
        )

        try await store.performTransaction {
            try await store.updateThread(updatedThread)
        }

        let thread = updatedThread

        switch evaluation.decision.action {
        case .wait:
            secOrchLog("handleInboundMessage -> wait | thread=\(thread.id) | state=\(thread.state)")
            return try await buildThreadOnlyResponse(
                thread: thread,
                summaryOverride: evaluation.decision.summary,
                handoffAction: .inboundWait,
                federationReason: evaluation.decision.rationale
            )

        case .resolved:
            let mutation = try threadEngine.markResolved(
                thread: thread,
                summary: evaluation.decision.summary,
                now: now
            )

            try await store.performTransaction {
                try await persist(mutation: mutation)
            }

            secOrchLog("handleInboundMessage -> resolved | thread=\(mutation.thread.id) | state=\(mutation.thread.state)")
            return try await buildResponse(
                thread: mutation.thread,
                turns: mutation.turns,
                approvals: [],
                drafts: [],
                matches: [],
                counterparties: [],
                artifacts: [],
                handoff: .init(
                    selectedCounterpartyID: mutation.thread.selectedCounterpartyID,
                    selectedCounterparty: try await loadSelectedCounterparty(for: mutation.thread),
                    latestDraftID: nil,
                    latestDraft: nil,
                    latestApprovalID: nil,
                    latestApproval: nil,
                    latestAction: .inboundResolved,
                    federationExecutionEligible: false,
                    federationExecutionReason: evaluation.decision.rationale
                )
            )

        case .needsUserInput, .needsClarification:
            secOrchLog("handleInboundMessage -> clarification | currentState=\(thread.state)")
            let resolution = failureResolver.resolve(
                .init(
                    kind: .understanding,
                    summary: evaluation.decision.summary,
                    detail: evaluation.inbound.summary,
                    externalEffect: .changed(description: "An inbound message was received and interpreted."),
                    recommendation: .clarify(
                        question: evaluation.inbound.extractedQuestion
                        ?? evaluation.decision.rationale
                        ?? evaluation.decision.summary
                    ),
                    reasonCode: evaluation.decision.action == .needsUserInput
                        ? "inbound_requires_user_input"
                        : "inbound_requires_clarification"
                )
            )

            let mutation = try threadEngine.askForClarification(
                thread: thread,
                failure: resolution.failure,
                now: now
            )

            try await store.performTransaction {
                try await persist(mutation: mutation)
            }

            secOrchLog("handleInboundMessage clarification persisted | thread=\(mutation.thread.id) | state=\(mutation.thread.state)")
            return try await buildResponse(
                thread: mutation.thread,
                turns: mutation.turns,
                approvals: [],
                drafts: [],
                matches: [],
                counterparties: [],
                artifacts: [],
                handoff: .init(
                    selectedCounterpartyID: mutation.thread.selectedCounterpartyID,
                    selectedCounterparty: try await loadSelectedCounterparty(for: mutation.thread),
                    latestDraftID: nil,
                    latestDraft: nil,
                    latestApprovalID: nil,
                    latestApproval: nil,
                    latestAction: .continuationNeedsUserInput,
                    federationExecutionEligible: false,
                    federationExecutionReason: evaluation.decision.rationale
                )
            )

        case .failedLegibly:
            let resolution = failureResolver.resolve(
                .init(
                    kind: .system,
                    summary: evaluation.decision.summary,
                    detail: evaluation.inbound.summary,
                    externalEffect: .changed(description: "An inbound message was received but continuation stopped."),
                    recommendation: .reviewMismatch(
                        evaluation.decision.rationale ?? evaluation.decision.summary
                    ),
                    reasonCode: "inbound_failed_legibly"
                )
            )

            let mutation = try threadEngine.markFailure(
                thread: thread,
                failure: resolution.failure,
                mappedState: resolution.mappedState,
                now: now
            )

            try await store.performTransaction {
                try await persist(mutation: mutation)
            }

            secOrchLog("handleInboundMessage failed legibly | thread=\(mutation.thread.id) | state=\(mutation.thread.state)")
            return try await buildResponse(
                thread: mutation.thread,
                turns: mutation.turns,
                approvals: [],
                drafts: [],
                matches: [],
                counterparties: [],
                artifacts: [],
                handoff: .init(
                    selectedCounterpartyID: mutation.thread.selectedCounterpartyID,
                    selectedCounterparty: try await loadSelectedCounterparty(for: mutation.thread),
                    latestDraftID: nil,
                    latestDraft: nil,
                    latestApprovalID: nil,
                    latestApproval: nil,
                    latestAction: .continuationFailedLegibly,
                    federationExecutionEligible: false,
                    federationExecutionReason: evaluation.decision.rationale
                )
            )

        case .continueWithDraft, .requestApprovalForReply:
            guard let selectedCounterparty = try await loadSelectedCounterparty(for: thread) else {
                secOrchLog("handleInboundMessage missing selected counterparty | thread=\(thread.id)")
                let resolution = failureResolver.resolve(
                    .init(
                        kind: .system,
                        summary: "Inbound continuation could not proceed because no selected counterparty exists on the thread.",
                        detail: evaluation.inbound.summary,
                        externalEffect: .changed(description: "An inbound message was received but reply preparation could not continue."),
                        recommendation: .reviewMismatch("Re-select a counterparty before continuing this thread."),
                        reasonCode: "missing_selected_counterparty_for_inbound_continuation"
                    )
                )

                let mutation = try threadEngine.markFailure(
                    thread: thread,
                    failure: resolution.failure,
                    mappedState: resolution.mappedState,
                    now: now
                )

                try await store.performTransaction {
                    try await persist(mutation: mutation)
                }

                return try await buildResponse(
                    thread: mutation.thread,
                    turns: mutation.turns,
                    approvals: [],
                    drafts: [],
                    matches: [],
                    counterparties: [],
                    artifacts: [],
                    handoff: .init(
                        selectedCounterpartyID: mutation.thread.selectedCounterpartyID,
                        selectedCounterparty: nil,
                        latestDraftID: nil,
                        latestDraft: nil,
                        latestApprovalID: nil,
                        latestApproval: nil,
                        latestAction: .continuationFailedLegibly,
                        federationExecutionEligible: false,
                        federationExecutionReason: "No selected counterparty exists for reply continuation."
                    )
                )
            }

            let existingDrafts = try await store.listDrafts(threadID: thread.id)

            let composition = await messageComposer.compose(
                thread: thread,
                counterparty: selectedCounterparty,
                existingDrafts: existingDrafts,
                preferredKind: evaluation.decision.suggestedDraftKind,
                now: now
            )
            secOrchLog("handleInboundMessage compose | draftID=\(composition.draft.id) | approvalRequired=\(composition.approvalRequired) | superseded=\(composition.supersededDrafts.count)")

            try await store.performTransaction {
                for superseded in composition.supersededDrafts {
                    try await store.saveDraft(superseded)
                }
                try await store.saveDraft(composition.draft)
            }

            let policy = policyEngine.evaluate(
                thread: thread,
                selectedCounterparty: selectedCounterparty,
                draft: composition.draft,
                deliveryState: nil
            )
            secOrchLog("handleInboundMessage policy | approvalRequired=\(policy.approval.required) | federationAllowed=\(policy.federationExecution.allowed)")

            let mustRequestApproval =
                evaluation.decision.action == .requestApprovalForReply ||
                evaluation.decision.requiresApproval ||
                composition.approvalRequired ||
                policy.approval.required

            if mustRequestApproval {
                let approval = approvalEngine.createApproval(
                    thread: thread,
                    draft: composition.draft,
                    kind: composition.draft.kind == .followUp
                        ? .followUpSend
                        : .outboundSend,
                    expiresAt: nil,
                    now: now
                )

                let mutation = try threadEngine.requestApproval(
                    thread: thread,
                    approval: approval,
                    now: now
                )

                try await store.performTransaction {
                    try await store.saveApproval(approval)
                    try await persist(mutation: mutation)
                }

                secOrchLog("handleInboundMessage approval requested | thread=\(mutation.thread.id) | state=\(mutation.thread.state)")
                return try await buildResponse(
                    thread: mutation.thread,
                    turns: mutation.turns,
                    approvals: [approval],
                    drafts: [composition.draft],
                    matches: [],
                    counterparties: [selectedCounterparty],
                    artifacts: [],
                    handoff: .init(
                        selectedCounterpartyID: selectedCounterparty.id,
                        selectedCounterparty: selectedCounterparty,
                        latestDraftID: composition.draft.id,
                        latestDraft: composition.draft,
                        latestApprovalID: approval.id,
                        latestApproval: approval,
                        latestAction: .continuationApprovalRequested,
                        federationExecutionEligible: false,
                        federationExecutionReason: evaluation.decision.rationale ?? policy.approval.rationale
                    )
                )
            }

            let mutation = try persistPreparedDraftMutation(
                thread: thread,
                draft: composition.draft,
                now: now
            )

            try await store.performTransaction {
                try await persist(mutation: mutation)
            }

            secOrchLog("handleInboundMessage draft prepared | thread=\(mutation.thread.id) | state=\(mutation.thread.state)")
            return try await buildResponse(
                thread: mutation.thread,
                turns: mutation.turns,
                approvals: [],
                drafts: [composition.draft],
                matches: [],
                counterparties: [selectedCounterparty],
                artifacts: [],
                handoff: .init(
                    selectedCounterpartyID: selectedCounterparty.id,
                    selectedCounterparty: selectedCounterparty,
                    latestDraftID: composition.draft.id,
                    latestDraft: composition.draft,
                    latestApprovalID: nil,
                    latestApproval: nil,
                    latestAction: .continuationDraftPrepared,
                    federationExecutionEligible: policy.federationExecution.allowed,
                    federationExecutionReason: evaluation.decision.rationale ?? policy.federationExecution.rationale
                )
            )
        }
    }

    public func approve(
        threadID: ExchangeThread.ID,
        approvalID: ExchangeApproval.ID,
        note: String? = nil,
        now: Date = Date()
    ) async throws -> Response {
        let approveStart = CFAbsoluteTimeGetCurrent()
        secOrchLog("approve BEGIN | thread=\(threadID) | approval=\(approvalID)")

        let thread = try await store.requireThread(id: threadID)
        let approval = try await store.requireApproval(id: approvalID)

        let resolvedApproval = approvalEngine.resolveApproval(
            approval,
            decision: .approve,
            now: now,
            note: note
        )

        let approvedDraft: ExchangeMessageDraft?
        if let draftID = resolvedApproval.draftID {
            approvedDraft = try await store.fetchDraft(id: draftID)
        } else {
            approvedDraft = nil
        }

        let selectedCounterpartyForPolicy = try await loadSelectedCounterparty(for: thread)
        let previewThread = thread.settingApproval(
            .init(
                status: .approved,
                requestedAt: resolvedApproval.createdAt,
                decidedAt: resolvedApproval.decidedAt ?? now,
                requestedDraftID: resolvedApproval.draftID,
                note: resolvedApproval.decisionNote
            ),
            at: now
        )
        let policyPreview = policyEngine.evaluate(
            thread: previewThread,
            selectedCounterparty: selectedCounterpartyForPolicy,
            draft: approvedDraft,
            deliveryState: nil
        )
        let sendableDraft = ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(
            in: approvedDraft.map { [$0] } ?? [],
            thread: previewThread
        )
        let shouldEnterSendingPipeline = policyPreview.federationExecution.allowed && sendableDraft

        let mutation: ExchangeThreadEngine.ThreadMutation
        if shouldEnterSendingPipeline {
            mutation = try threadEngine.grantApproval(
                thread: thread,
                approval: resolvedApproval,
                now: now
            )
        } else {
            mutation = try threadEngine.grantApprovalCoordinationHold(
                thread: thread,
                approval: resolvedApproval,
                coordinationNote: policyPreview.federationExecution.rationale,
                now: now
            )
        }

        try await store.performTransaction {
            try await store.saveApproval(resolvedApproval)
            try await persist(mutation: mutation)
        }

        let selectedCounterparty = try await loadSelectedCounterparty(for: mutation.thread)

        let policy = policyEngine.evaluate(
            thread: mutation.thread,
            selectedCounterparty: selectedCounterparty,
            draft: approvedDraft,
            deliveryState: nil
        )

        let latestTurn = mutation.turns.last
        let summary = summaryEngine.threadSummary(
            thread: mutation.thread,
            latestTurn: latestTurn
        )

        let approveMs = Int((CFAbsoluteTimeGetCurrent() - approveStart) * 1000)
        secOrchLog("approve END | thread=\(mutation.thread.id) | state=\(mutation.thread.state) | federationAllowed=\(policy.federationExecution.allowed) | total=\(approveMs)ms")

        return Response(
            thread: mutation.thread,
            turns: mutation.turns,
            approvals: [resolvedApproval],
            drafts: approvedDraft.map { [$0] } ?? [],
            matches: [],
            counterparties: selectedCounterparty.map { [$0] } ?? [],
            artifacts: [],
            summary: summary,
            handoff: .init(
                selectedCounterpartyID: selectedCounterparty?.id,
                selectedCounterparty: selectedCounterparty,
                latestDraftID: approvedDraft?.id,
                latestDraft: approvedDraft,
                latestApprovalID: resolvedApproval.id,
                latestApproval: resolvedApproval,
                latestAction: .approvalGranted,
                federationExecutionEligible: policy.federationExecution.allowed,
                federationExecutionReason: policy.federationExecution.rationale
            )
        )
    }

    public func reject(
        threadID: ExchangeThread.ID,
        approvalID: ExchangeApproval.ID,
        note: String? = nil,
        now: Date = Date()
    ) async throws -> Response {
        let rejectStart = CFAbsoluteTimeGetCurrent()
        secOrchLog("reject BEGIN | thread=\(threadID) | approval=\(approvalID)")

        let thread = try await store.requireThread(id: threadID)
        let approval = try await store.requireApproval(id: approvalID)

        let resolvedApproval = approvalEngine.resolveApproval(
            approval,
            decision: .reject,
            now: now,
            note: note
        )

        let mutation = try threadEngine.rejectApproval(
            thread: thread,
            approval: resolvedApproval,
            now: now
        )

        try await store.performTransaction {
            try await store.saveApproval(resolvedApproval)
            try await persist(mutation: mutation)
        }

        let latestTurn = mutation.turns.last
        let summary = summaryEngine.threadSummary(
            thread: mutation.thread,
            latestTurn: latestTurn
        )

        let rejectMs = Int((CFAbsoluteTimeGetCurrent() - rejectStart) * 1000)
        secOrchLog("reject END | thread=\(mutation.thread.id) | state=\(mutation.thread.state) | total=\(rejectMs)ms")

        return Response(
            thread: mutation.thread,
            turns: mutation.turns,
            approvals: [resolvedApproval],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: summary,
            handoff: .init(
                selectedCounterpartyID: mutation.thread.selectedCounterpartyID,
                selectedCounterparty: nil,
                latestDraftID: resolvedApproval.draftID,
                latestDraft: nil,
                latestApprovalID: resolvedApproval.id,
                latestApproval: resolvedApproval,
                latestAction: .approvalRejected,
                federationExecutionEligible: false,
                federationExecutionReason: "Approval was rejected."
            )
        )
    }

    public func markOutboundConfirmed(
        threadID: ExchangeThread.ID,
        externalReference: String? = nil,
        now: Date = Date()
    ) async throws -> Response {
        let confirmStart = CFAbsoluteTimeGetCurrent()
        secOrchLog("markOutboundConfirmed BEGIN | thread=\(threadID) | externalReference=\(externalReference ?? "nil")")

        let thread = try await store.requireThread(id: threadID)

        let mutation = try threadEngine.markSendConfirmed(
            thread: thread,
            externalReference: externalReference,
            now: now
        )

        let updatedDraft: ExchangeMessageDraft?
        if let latestApproval = try await store.fetchLatestApproval(threadID: threadID),
           let draftID = latestApproval.draftID,
           let draft = try await store.fetchDraft(id: draftID) {
            updatedDraft = draft.markingSent(
                externalReference: externalReference,
                at: now
            )
        } else {
            updatedDraft = nil
        }

        try await store.performTransaction {
            try await persist(mutation: mutation)
            if let updatedDraft = updatedDraft {
                try await store.saveDraft(updatedDraft)
            }
        }

        let selectedCounterparty = try await loadSelectedCounterparty(for: mutation.thread)

        let latestTurn = mutation.turns.last
        let summary = summaryEngine.threadSummary(
            thread: mutation.thread,
            latestTurn: latestTurn
        )

        let confirmMs = Int((CFAbsoluteTimeGetCurrent() - confirmStart) * 1000)
        secOrchLog("markOutboundConfirmed END | thread=\(mutation.thread.id) | state=\(mutation.thread.state) | total=\(confirmMs)ms")

        return Response(
            thread: mutation.thread,
            turns: mutation.turns,
            approvals: [],
            drafts: updatedDraft.map { [$0] } ?? [],
            matches: [],
            counterparties: selectedCounterparty.map { [$0] } ?? [],
            artifacts: [],
            summary: summary,
            handoff: .init(
                selectedCounterpartyID: selectedCounterparty?.id,
                selectedCounterparty: selectedCounterparty,
                latestDraftID: updatedDraft?.id,
                latestDraft: updatedDraft,
                latestApprovalID: nil,
                latestApproval: nil,
                latestAction: .outboundConfirmed,
                federationExecutionEligible: false,
                federationExecutionReason: "Outbound delivery has already been confirmed."
            )
        )
    }
}

public extension ExchangeOrchestrator {
    struct CanonicalDiscoverySelection: Sendable, Hashable {
        public enum Source: String, Sendable, Hashable {
            case bestMatch
            case selectedMatch
        }

        public var counterpartyID: ExchangeCounterparty.ID?
        public var publicProfileID: ExchangePublicNodeProfile.ID?
        public var offerID: ExchangeOffer.ID?
        public var source: Source
        public var primaryCoordinationChildThreadID: ExchangeThread.ID?
        public var primaryCoordinationChildOfferID: ExchangeOffer.ID?

        public init(
            counterpartyID: ExchangeCounterparty.ID? = nil,
            publicProfileID: ExchangePublicNodeProfile.ID? = nil,
            offerID: ExchangeOffer.ID? = nil,
            source: Source,
            primaryCoordinationChildThreadID: ExchangeThread.ID? = nil,
            primaryCoordinationChildOfferID: ExchangeOffer.ID? = nil
        ) {
            self.counterpartyID = counterpartyID
            self.publicProfileID = publicProfileID
            self.offerID = offerID
            self.source = source
            self.primaryCoordinationChildThreadID = primaryCoordinationChildThreadID
            self.primaryCoordinationChildOfferID = primaryCoordinationChildOfferID
        }
    }

    struct Response: Sendable {
        public var thread: ExchangeThread
        public var turns: [ExchangeTurn]
        public var approvals: [ExchangeApproval]
        public var drafts: [ExchangeMessageDraft]
        public var matches: [ExchangeMatch]
        public var counterparties: [ExchangeCounterparty]
        public var artifacts: [ExchangeArtifact]
        public var summary: String
        public var handoff: Handoff
        /// When true, no store mutation occurred and callers must not run second-half / notification side effects.
        public var isTransientNonPersistent: Bool
        /// Discovery best-match anchor from `ExchangeDiscoveryService.selectBestMatch` (audit/diagnostics).
        public var canonicalDiscoverySelection: CanonicalDiscoverySelection?
        /// Child coordination threads activated during discovery; facade runs second-half per id.
        public var coordinationChildThreadIDs: [ExchangeThread.ID]

        public init(
            thread: ExchangeThread,
            turns: [ExchangeTurn],
            approvals: [ExchangeApproval],
            drafts: [ExchangeMessageDraft],
            matches: [ExchangeMatch],
            counterparties: [ExchangeCounterparty],
            artifacts: [ExchangeArtifact],
            summary: String,
            handoff: Handoff = .init(),
            isTransientNonPersistent: Bool = false,
            coordinationChildThreadIDs: [ExchangeThread.ID] = [],
            canonicalDiscoverySelection: CanonicalDiscoverySelection? = nil
        ) {
            self.thread = thread
            self.turns = turns
            self.approvals = approvals
            self.drafts = drafts
            self.matches = matches
            self.counterparties = counterparties
            self.artifacts = artifacts
            self.summary = summary
            self.handoff = handoff
            self.isTransientNonPersistent = isTransientNonPersistent
            self.coordinationChildThreadIDs = coordinationChildThreadIDs
            self.canonicalDiscoverySelection = canonicalDiscoverySelection
        }
    }

    struct Handoff: Sendable {
        public var selectedCounterpartyID: ExchangeCounterparty.ID?
        public var selectedCounterparty: ExchangeCounterparty?

        public var selectedPublicProfileID: ExchangePublicNodeProfile.ID?
        public var selectedOfferID: ExchangeOffer.ID?

        public var latestMatchID: ExchangeMatch.ID?
        public var latestMatch: ExchangeMatch?

        public var latestDraftID: ExchangeMessageDraft.ID?
        public var latestDraft: ExchangeMessageDraft?

        public var latestApprovalID: ExchangeApproval.ID?
        public var latestApproval: ExchangeApproval?

        public var latestAction: Action?
        public var federationExecutionEligible: Bool
        public var federationExecutionReason: String?
        public var workTrace: [WorkTraceItem]

        public init(
            selectedCounterpartyID: ExchangeCounterparty.ID? = nil,
            selectedCounterparty: ExchangeCounterparty? = nil,
            selectedPublicProfileID: ExchangePublicNodeProfile.ID? = nil,
            selectedOfferID: ExchangeOffer.ID? = nil,
            latestMatchID: ExchangeMatch.ID? = nil,
            latestMatch: ExchangeMatch? = nil,
            latestDraftID: ExchangeMessageDraft.ID? = nil,
            latestDraft: ExchangeMessageDraft? = nil,
            latestApprovalID: ExchangeApproval.ID? = nil,
            latestApproval: ExchangeApproval? = nil,
            latestAction: Action? = nil,
            federationExecutionEligible: Bool = false,
            federationExecutionReason: String? = nil,
            workTrace: [WorkTraceItem] = []
        ) {
            self.selectedCounterpartyID = selectedCounterpartyID
            self.selectedCounterparty = selectedCounterparty
            self.selectedPublicProfileID = selectedPublicProfileID
            self.selectedOfferID = selectedOfferID
            self.latestMatchID = latestMatchID
            self.latestMatch = latestMatch
            self.latestDraftID = latestDraftID
            self.latestDraft = latestDraft
            self.latestApprovalID = latestApprovalID
            self.latestApproval = latestApproval
            self.latestAction = latestAction
            self.federationExecutionEligible = federationExecutionEligible
            self.federationExecutionReason = federationExecutionReason
            self.workTrace = workTrace
        }

        public enum Action: String, Sendable, Hashable {
            case clarificationRequired
            case clarificationAnswered
            case draftPrepared
            case approvalRequested
            case approvalGranted
            case approvalRejected
            case outboundConfirmed
            case discoveryFailed
            case weakMatchesFound
            case noAdvanceableMatch
            case matchSelected
            case inboundWait
            case inboundResolved
            case continuationDraftPrepared
            case continuationApprovalRequested
            case continuationNeedsUserInput
            case continuationFailedLegibly
        }
    }

    struct WorkTraceItem: Codable, Sendable, Hashable, Identifiable {
        public let id: UUID
        public let stage: Stage
        public let message: String

        public init(
            id: UUID = UUID(),
            stage: Stage,
            message: String
        ) {
            self.id = id
            self.stage = stage
            self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public enum Stage: String, Codable, Sendable, Hashable {
            case understandingRequest
            case askingClarification
            case identifyingTarget
            case searchingLocalCandidates
            case rankingLikelyFits
            case selectingBestMatch
            case preparingDraft
            case preparingReplyDraft
            case draftReady
            case awaitingApproval
            case approvalGranted
            case approvalRejected
            case readyToSend
            case sent
            case waitingForReply
            case reviewingInbound
            case evaluatingContinuation
            case waiting
            case resolved
            case blocked
            case stopped
        }
    }
}

private extension ExchangeOrchestrator {
    func loadExistingThread(id: ExchangeThread.ID?) async throws -> ExchangeThread? {
        guard let id else { return nil }
        return try await store.fetchThread(id: id)
    }
    
    func persistDiscoveryEntities(
        counterparties: [ExchangeCounterparty],
        publicProfiles: [ExchangePublicNodeProfile],
        offers: [ExchangeOffer],
        now: Date = Date()
    ) async throws {
        let uniqueCounterparties = Array(
            Dictionary(
                counterparties.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values
        )
        .map { ExchangeRemoteDiscoveryCacheMetadata.tagDiscoveryCounterparty($0, now: now) }

        let uniqueProfiles = Array(
            Dictionary(
                publicProfiles.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values
        )
        .map { profile -> ExchangePublicNodeProfile in
            var tagged = profile
            ExchangeRemoteDiscoveryCacheMetadata.tagDiscoveryProfile(&tagged, now: now)
            return tagged
        }

        let uniqueOffers = Array(
            Dictionary(
                offers.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values
        )
        .map { offer -> ExchangeOffer in
            var tagged = offer
            ExchangeRemoteDiscoveryCacheMetadata.tagDiscoveryOffer(&tagged, now: now)
            return tagged
        }

        if !uniqueCounterparties.isEmpty {
            #if DEBUG
            for counterparty in uniqueCounterparties {
                secOrchLog(
                    "counterparty upsert | counterpartyID=\(counterparty.id) | identityNodeID=\(counterparty.identity?.nodeID ?? "nil") | publicProfileID=\(counterparty.publicProfile?.id ?? "nil") | publicProfileNodeID=\(counterparty.publicProfile?.nodeID ?? "nil")"
                )
            }
            #endif
            try await store.upsertCounterparties(uniqueCounterparties)
        }

        if !uniqueProfiles.isEmpty {
            try await store.savePublicProfiles(uniqueProfiles)
        }

        if !uniqueOffers.isEmpty {
            try await store.saveOffers(uniqueOffers)
        }
    }
    
    func selectedProfileID(
        from match: ExchangeMatch
    ) -> ExchangePublicNodeProfile.ID? {
        match.publicProfileID
    }

    func selectedOfferID(
        from match: ExchangeMatch,
        thread: ExchangeThread? = nil
    ) -> ExchangeOffer.ID? {
        if let thread {
            return ExchangeOfferObjectLane.resolveSelectedOfferID(from: match, thread: thread)
        }
        if !match.provenObjectOfferIDs.isEmpty {
            return ExchangeOfferObjectLane.resolveSelectedOfferID(
                provenObjectOfferIDs: Set(match.provenObjectOfferIDs),
                objectEvidenceScoreByOfferID: match.objectEvidenceScoreByOfferID,
                preferredOfferID: match.offerID
            )
        }
        return match.offerID ?? match.matchedOfferIDs.first
    }

    func makeCanonicalDiscoverySelection(
        from match: ExchangeMatch?,
        thread: ExchangeThread,
        source: CanonicalDiscoverySelection.Source,
        primaryCoordinationChildThreadID: ExchangeThread.ID? = nil,
        primaryChildSourceMatch: ExchangeMatch? = nil
    ) -> CanonicalDiscoverySelection? {
        guard let match else { return nil }
        let offerID = selectedOfferID(from: match, thread: thread)
        let primaryChildOfferID = primaryChildSourceMatch.flatMap {
            selectedOfferID(from: $0, thread: thread)
        }
        return CanonicalDiscoverySelection(
            counterpartyID: match.counterpartyID,
            publicProfileID: match.publicProfileID,
            offerID: offerID,
            source: source,
            primaryCoordinationChildThreadID: primaryCoordinationChildThreadID,
            primaryCoordinationChildOfferID: primaryChildOfferID
        )
    }

    func canonicalDiscoverySelectionSnapshot(
        from selection: CanonicalDiscoverySelection?
    ) -> ExchangeCanonicalDiscoverySelectionSnapshot? {
        guard let selection else { return nil }
        return ExchangeCanonicalDiscoverySelectionSnapshot(
            counterpartyID: selection.counterpartyID,
            publicProfileID: selection.publicProfileID,
            offerID: selection.offerID,
            source: selection.source.rawValue,
            primaryCoordinationChildOfferID: selection.primaryCoordinationChildOfferID
        )
    }
    
    func persistPreparedDraftMutation(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft,
        now: Date
    ) throws -> ExchangeThreadEngine.ThreadMutation {
        switch thread.state {
        case .draftReady:
            return try threadEngine.replacePreparedDraft(
                thread: thread,
                draft: draft,
                now: now
            )

        default:
            return try threadEngine.markDraftPrepared(
                thread: thread,
                draft: draft,
                now: now
            )
        }
    }

    func loadSelectedCounterparty(
        for thread: ExchangeThread
    ) async throws -> ExchangeCounterparty? {
        guard let selectedID = thread.selectedCounterpartyID else { return nil }
        return try await store.fetchCounterparty(id: selectedID)
    }

    func interpretationSnapshot(
        from request: ExchangeInterpreter.InterpretedRequest
    ) -> ExchangeThread.InterpretationSnapshot {
        .from(request)
    }

    func starterWorkTrace(
        interpretation: ExchangeThread.InterpretationSnapshot,
        intent: ExchangeIntent,
        now: Date
    ) -> ExchangeThread.WorkTraceSnapshot {
        ExchangeThread.WorkTraceSnapshot
            .starter(headline: "Starting secretary work.", at: now)
            .appendingStep(
                key: "understanding_request",
                title: "Understanding request",
                detail: interpretation.userSummary ?? intent.summaryLine,
                activating: true,
                at: now
            )
    }

    func projectedHandoffWorkTrace(
        from thread: ExchangeThread
    ) -> [WorkTraceItem] {
        guard let trace = thread.workTrace else { return [] }

        return trace.steps
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map { step in
                WorkTraceItem(
                    stage: handoffStage(for: step.key, step: step, traceStatus: trace.status),
                    message: {
                        if let detail = step.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return "\(step.title) · \(detail)"
                        }
                        return step.title
                    }()
                )
            }
    }

    func handoffStage(
        for key: String,
        step: ExchangeThread.WorkTraceSnapshot.Step,
        traceStatus: ExchangeThread.WorkTraceSnapshot.Status
    ) -> WorkTraceItem.Stage {
        switch key {
        case "understanding_request":
            return .understandingRequest
        case "asking_clarification":
            return .askingClarification
        case "identifying_target":
            return .identifyingTarget
        case "searching_local_candidates":
            return .searchingLocalCandidates
        case "ranking_likely_fits":
            return .rankingLikelyFits
        case "selecting_best_match":
            return .selectingBestMatch
        case "preparing_outreach_draft":
            return step.isComplete ? .draftReady : .preparingDraft
        case "awaiting_approval":
            return .awaitingApproval
        case "ready_to_send":
            return .readyToSend
        case "waiting_for_reply":
            return .waitingForReply
        default:
            switch traceStatus {
            case .blocked:
                return .blocked
            case .completed:
                return .resolved
            case .idle, .running:
                return .understandingRequest
            }
        }
    }

    func clarificationInterpretationSnapshot(
        userText: String,
        failure: ExchangeFailure,
        draftIntent: ExchangeIntent?,
        draftFacets: ExchangeIntentFacets?,
        existingThread: ExchangeThread?
    ) -> ExchangeThread.InterpretationSnapshot {
        let summary = failure.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let question: String? = {
            if case .clarify(let q) = failure.recommendedNextStep {
                let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let fallback = failure.recommendedNextStep.summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? nil : fallback
        }()

        let semanticTags: [String] = {
            if let existing = existingThread?.interpretation?.semanticTags, !existing.isEmpty {
                return existing
            }

            var values: [String] = ["clarification"]

            if let kind = draftIntent?.kind.rawValue {
                values.append(kind)
            }

            if let targetRole = draftFacets?.targetRole {
                values.append(targetRole)
            }
            if let activity = draftFacets?.activity {
                values.append(activity)
            }
            if let serviceCategory = draftFacets?.serviceCategory {
                values.append(serviceCategory)
            }
            if let productCategory = draftFacets?.productCategory {
                values.append(productCategory)
            }
            if let placeName = draftFacets?.placeName {
                values.append(placeName)
            }

            return normalizeTerms(values, maxCount: 12)
        }()

        let discoveryKeywords: [String] = {
            if let existing = existingThread?.interpretation?.discoveryKeywords, !existing.isEmpty {
                return existing
            }

            var values: [String] = []
            if let searchable = draftFacets?.searchableText, !searchable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                values.append(searchable)
            } else if let target = draftIntent?.targetDescription, !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                values.append(target)
            } else if !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                values.append(userText)
            }

            return normalizeTerms(values.flatMap(tokenize), maxCount: 12)
        }()

        let targetTags: [String] = {
            if let existing = existingThread?.interpretation?.targetTags, !existing.isEmpty {
                return existing
            }

            var values: [String] = []

            if let targetRole = draftFacets?.targetRole { values.append(targetRole) }
            if let serviceCategory = draftFacets?.serviceCategory { values.append(serviceCategory) }
            if let productCategory = draftFacets?.productCategory { values.append(productCategory) }
            if let activity = draftFacets?.activity { values.append(activity) }
            if let placeName = draftFacets?.placeName { values.append(placeName) }
            if let locationText = draftFacets?.locationText { values.append(contentsOf: tokenize(locationText)) }
            if let target = draftIntent?.targetDescription { values.append(contentsOf: tokenize(target)) }

            return normalizeTerms(values, maxCount: 10)
        }()

        return ExchangeThread.InterpretationSnapshot(
            semanticTags: semanticTags,
            discoveryKeywords: discoveryKeywords,
            targetTags: targetTags,
            userSummary: summary.isEmpty ? nil : summary,
            userQuestion: question,
            userNextStep: "Clarify the missing detail before discovery or drafting can continue.",
            needsClarification: true,
            shouldDiscover: false,
            shouldDraft: false
        )
    }

    func shouldDraftAfterDiscovery(
        userText: String,
        request: ExchangeInterpreter.InterpretedRequest
    ) -> Bool {
        if request.shouldDraft {
            return true
        }

        let lower = userText.lowercased()

        let explicitDraftPhrases = [
            "draft an outreach",
            "draft outreach",
            "draft a message",
            "draft an email",
            "prepare an outreach",
            "prepare an outreach draft",
            "prepare a message",
            "prepare an email",
            "write a message",
            "write an email",
            "reach out",
            "contact them",
            "send a message",
            "send an email"
        ]

        if explicitDraftPhrases.contains(where: { lower.contains($0) }) {
            return true
        }

        if request.intent.kind == .message ||
            request.intent.kind == .followUp ||
            request.intent.kind == .checkStatus {
            return true
        }

        return false
    }

    func searchQuerySummary(for thread: ExchangeThread) -> String? {
        let trimmedPrimary = thread.primarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrimary.isEmpty {
            return trimmedPrimary
        }

        if let target = thread.intent.targetDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !target.isEmpty {
            return target
        }

        let title = thread.intent.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }

        let objective = thread.intent.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        return objective.isEmpty ? nil : objective
    }

    func isTransientSearchIntentExtractorFailure(_ failure: ExchangeFailure) -> Bool {
        if failure.reasonCode == "search_intent_extractor_unavailable" {
            return true
        }
        if failure.summary == "Semantic search isn’t ready yet." {
            return true
        }
        return false
    }

    func buildTransientSearchIntentExtractorFailureResponse(
        userText: String,
        failure: ExchangeFailure,
        now: Date
    ) -> Response {
        let phantomThread = ExchangeThread(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .generalDiscovery,
                surfacePreference: .mixed,
                title: "Local search",
                objective: userText,
                readiness: .ready,
                interpretationNotes: "Transient inline response (no durable thread).",
                interpretationConfidence: 0.0,
                needsFullLLMInterpretation: false
            ),
            posture: .cautious,
            state: .resolved(
                .init(
                    resolvedAt: now,
                    summary: "No coordination thread was created (transient local search-intent failure)."
                )
            ),
            latestFailure: failure,
            visibleSummary: failure.summary,
            metadata: ["transient_inline_exchange_response": "true"]
        )

        return Response(
            thread: phantomThread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: failure.visibleExplanation,
            handoff: .init(
                federationExecutionEligible: false,
                federationExecutionReason: failure.summary
            ),
            isTransientNonPersistent: true
        )
    }

    func handleClarificationNeeded(
        existingThread: ExchangeThread?,
        userText: String,
        failure: ExchangeFailure,
        draftIntent: ExchangeIntent?,
        draftFacets: ExchangeIntentFacets?,
        draftPosture: ExchangePosture?,
        now: Date
    ) async throws -> Response {
        let clarificationStart = CFAbsoluteTimeGetCurrent()
        secOrchLog("handleClarificationNeeded BEGIN | existingThread=\(existingThread?.id.uuidString ?? "nil") | failure=\(failure.summary)")

        if let existingThread, existingThread.autonomousClarificationCount >= 1 {
            throw ExchangeThreadEngineError.invalidTransition(
                "This thread has already consumed its single clarification turn."
            )
        }

        let thread: ExchangeThread
        let turns: [ExchangeTurn]
        let interpretation = clarificationInterpretationSnapshot(
            userText: userText,
            failure: failure,
            draftIntent: draftIntent,
            draftFacets: draftFacets,
            existingThread: existingThread
        )

        if let existingThread {
            let refreshedThread: ExchangeThread
            if let draftIntent {
                let posture = draftPosture ?? existingThread.posture
                let facets = draftFacets ?? existingThread.facets
                let expectation = expectationEngine.buildExpectation(
                    intent: draftIntent,
                    posture: posture,
                    facets: facets
                )

                refreshedThread = existingThread.refreshingForReuse(
                    intent: draftIntent,
                    posture: posture,
                    facets: facets,
                    interpretation: interpretation,
                    workTrace: starterWorkTrace(
                        interpretation: interpretation,
                        intent: draftIntent,
                        now: now
                    ),
                    expectation: expectation,
                    at: now
                )
            } else {
                refreshedThread = existingThread
                    .settingInterpretation(interpretation, at: now)
                    .settingWorkTrace(
                        starterWorkTrace(
                            interpretation: interpretation,
                            intent: existingThread.intent,
                            now: now
                        ),
                        at: now
                    )
                    .withUpdatedState(
                        existingThread.state,
                        at: now,
                        visibleSummary: interpretation.userSummary
                    )
            }

            secOrchLog("clarification existing thread | thread=\(refreshedThread.id) | currentState=\(refreshedThread.state)")

            let mutation = try threadEngine.askForClarification(
                thread: refreshedThread,
                failure: failure,
                now: now
            )
            thread = mutation.thread
            turns = mutation.turns

            try await store.performTransaction {
                try await persist(mutation: mutation)
            }
        } else {
            secOrchLog("clarification new thread path")
            let mode = draftIntent?.mode ?? .transactional
            let intent = draftIntent ?? ExchangeIntent(
                kind: .other,
                mode: mode,
                queryIntentClass: draftFacets?.queryIntentClass ?? .generalDiscovery,
                surfacePreference: draftFacets?.surfacePreference ?? .mixed,
                title: "Exchange Request",
                objective: userText,
                readiness: .needsClarification,
                interpretationNotes: "Created conservatively while awaiting clarification."
            )
            let posture = draftPosture ?? .cautious
            let facets = draftFacets
            let expectation = expectationEngine.buildExpectation(
                intent: intent,
                posture: posture,
                facets: facets
            )

            let opened = threadEngine.beginThread(
                userText: userText,
                mode: mode,
                intent: intent,
                posture: posture,
                interpretation: interpretation,
                expectation: expectation,
                facets: facets,
                workTrace: starterWorkTrace(
                    interpretation: interpretation,
                    intent: intent,
                    now: now
                ),
                now: now
            )
            secOrchLog("new thread created before clarification | thread=\(opened.thread.id) | initialState=\(opened.thread.state)")

            let clarification = try threadEngine.askForClarification(
                thread: opened.thread,
                failure: failure,
                now: now
            )

            try await store.performTransaction {
                try await store.createThread(opened.thread)
                for turn in opened.turns {
                    try await store.appendTurn(turn)
                }
                try await persist(mutation: clarification)
            }

            thread = clarification.thread
            turns = opened.turns + clarification.turns
        }

        let summary = summaryEngine.threadSummary(
            thread: thread,
            latestTurn: turns.last
        )

        let clarificationMs = Int((CFAbsoluteTimeGetCurrent() - clarificationStart) * 1000)
        secOrchLog("handleClarificationNeeded END | thread=\(thread.id) | state=\(thread.state) | turns=\(turns.count) | total=\(clarificationMs)ms")

        return Response(
            thread: thread,
            turns: turns,
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: summary,
            handoff: .init(
                selectedCounterpartyID: thread.selectedCounterpartyID,
                selectedCounterparty: nil,
                latestDraftID: nil,
                latestDraft: nil,
                latestApprovalID: nil,
                latestApproval: nil,
                latestAction: .clarificationRequired,
                federationExecutionEligible: false,
                federationExecutionReason: "Clarification is required before any external coordination can proceed."
            )
        )
    }

    func handleInterpretedRequest(
        existingThread: ExchangeThread?,
        userText: String,
        request: ExchangeInterpreter.InterpretedRequest,
        progressContext: DiscoveryHeroProgressContext? = nil,
        now: Date
    ) async throws -> Response {
        let interpretedStart = CFAbsoluteTimeGetCurrent()
        secOrchLog("handleInterpretedRequest BEGIN | existingThread=\(existingThread?.id.uuidString ?? "nil") | title=\(request.intent.title) | shouldDiscover=\(request.shouldDiscover) | shouldDraft=\(request.shouldDraft)")

        let spatialOutcome = await ExchangeRequesterSpatialAnchorPreparer.prepare(
            facets: request.facets,
            userText: userText,
            shouldDiscover: request.shouldDiscover,
            locationProvider: requesterLocationProvider
        )
        var request = request
        request.facets = spatialOutcome.facets
        ExchangeNearMeLexicalSanitizer.sanitizeInterpretedRequest(&request)
        if let anchor = spatialOutcome.anchor {
            secOrchLog(
                "requesterSpatialAnchor prepared | source=\(anchor.source.rawValue) resolved=\(anchor.hasResolvedSpatial)"
            )
        } else if spatialOutcome.needsLocationClarification {
            secOrchLog("requesterSpatialAnchor missing | location clarification may be required")
        }
        let locationKind = request.facets.locationRequirement?.kind.rawValue ?? "nil"
        let spatialStatus = request.facets.locationRequirement?.spatial?.status.rawValue ?? "nil"
        secOrchLog(
            "after anchor prep | locationRequirement.kind=\(locationKind) spatial.status=\(spatialStatus) regionTerms=\(request.facets.regionTerms)"
        )

        let posture = request.posture
        let interpretation = interpretationSnapshot(from: request)

        let expectation = expectationEngine.buildExpectation(
            intent: request.intent,
            posture: posture,
            facets: request.facets
        )

        let baseThread: ExchangeThread
        var turns: [ExchangeTurn] = []

        let threadForReuse: ExchangeThread? = {
            guard let existingThread else { return nil }
            if ExchangeUmbrellaSearchReusePolicy.shouldForkNewUmbrellaSearch(
                existing: existingThread,
                request: request
            ) {
                secOrchLog(
                    "forking new umbrella search | existing=\(existingThread.id) " +
                    "state=\(existingThread.state) role=\(existingThread.threadRole.rawValue)"
                )
                return nil
            }
            return existingThread
        }()

        if let existingThread = threadForReuse {
            let refreshed = existingThread.refreshingForReuse(
                intent: request.intent,
                posture: posture,
                facets: request.facets,
                interpretation: interpretation,
                workTrace: starterWorkTrace(
                    interpretation: interpretation,
                    intent: request.intent,
                    now: now
                ),
                expectation: expectation,
                at: now
            )

            baseThread = refreshed.withUpdatedState(
                refreshed.state,
                at: now,
                visibleSummary: request.userSummary
            )

            try await store.performTransaction {
                try await store.updateThread(baseThread)
            }

            secOrchLog("reusing thread | thread=\(baseThread.id) | state=\(baseThread.state)")
        } else {
            let opened = threadEngine.beginThread(
                userText: userText,
                mode: request.intent.mode,
                intent: request.intent,
                posture: posture,
                interpretation: interpretation,
                expectation: expectation,
                facets: request.facets,
                workTrace: starterWorkTrace(
                    interpretation: interpretation,
                    intent: request.intent,
                    now: now
                ),
                now: now
            )

            baseThread = opened.thread.withUpdatedState(
                opened.thread.state,
                at: now,
                visibleSummary: request.userSummary
            )

            turns.append(contentsOf: opened.turns)

            try await store.performTransaction {
                try await store.createThread(baseThread)
                for turn in opened.turns {
                    try await store.appendTurn(turn)
                }
            }

            secOrchLog("new thread opened | thread=\(baseThread.id) | state=\(baseThread.state)")
        }

        DiscoveryHeroProgressNotifier.report(
            discoveryHeroProgressReporter,
            context: progressContext,
            stage: .understandingRequest,
            threadID: baseThread.id
        )

        let explicitDraftIntent = shouldDraftAfterDiscovery(
            userText: userText,
            request: request
        )

        let wantsDiscovery = request.shouldDiscover
        let wantsDraftNow = request.shouldDraft
        let wantsDraftAfterDiscovery = explicitDraftIntent

        let selectedCounterparty = try await loadSelectedCounterparty(for: baseThread)
        let hasSelectedCounterparty = selectedCounterparty != nil

        secOrchLog(
            "post-interpret branch | wantsDraftNow=\(wantsDraftNow) | wantsDiscovery=\(wantsDiscovery) | wantsDraftAfterDiscovery=\(wantsDraftAfterDiscovery) | hasSelectedCounterparty=\(hasSelectedCounterparty)"
        )

        if wantsDraftNow, let selectedCounterparty {
            let existingDrafts = try await store.listDrafts(threadID: baseThread.id)

            let composition = await messageComposer.compose(
                thread: baseThread,
                counterparty: selectedCounterparty,
                existingDrafts: existingDrafts,
                preferredKind: nil,
                now: now
            )
            secOrchLog("compose result | draftID=\(composition.draft.id) | approvalRequired=\(composition.approvalRequired) | superseded=\(composition.supersededDrafts.count)")

            try await store.performTransaction {
                for superseded in composition.supersededDrafts {
                    try await store.saveDraft(superseded)
                }
                try await store.saveDraft(composition.draft)
            }

            let postComposePolicy = policyEngine.evaluate(
                thread: baseThread,
                selectedCounterparty: selectedCounterparty,
                draft: composition.draft,
                deliveryState: nil
            )
            secOrchLog("policy after compose | approvalRequired=\(postComposePolicy.approval.required) | federationAllowed=\(postComposePolicy.federationExecution.allowed) | reason=\(postComposePolicy.federationExecution.rationale)")

            if !composition.approvalRequired && !postComposePolicy.approval.required {
                let preparedMutation = try persistPreparedDraftMutation(
                    thread: baseThread,
                    draft: composition.draft,
                    now: now
                )

                try await store.performTransaction {
                    try await persist(mutation: preparedMutation)
                }
                turns.append(contentsOf: preparedMutation.turns)

                let preparedThread = preparedMutation.thread
                let preparedSummary = summaryEngine.threadSummary(
                    thread: preparedThread,
                    latestTurn: preparedMutation.turns.last
                )

                let totalMs = Int((CFAbsoluteTimeGetCurrent() - interpretedStart) * 1000)
                secOrchLog("handleInterpretedRequest END | thread=\(preparedThread.id) | state=\(preparedThread.state) | action=draftPrepared | total=\(totalMs)ms")

                return Response(
                    thread: preparedThread,
                    turns: turns,
                    approvals: [],
                    drafts: [composition.draft],
                    matches: [],
                    counterparties: [selectedCounterparty],
                    artifacts: [],
                    summary: preparedSummary,
                    handoff: .init(
                        selectedCounterpartyID: selectedCounterparty.id,
                        selectedCounterparty: selectedCounterparty,
                        latestDraftID: composition.draft.id,
                        latestDraft: composition.draft,
                        latestApprovalID: nil,
                        latestApproval: nil,
                        latestAction: .draftPrepared,
                        federationExecutionEligible: postComposePolicy.federationExecution.allowed,
                        federationExecutionReason: postComposePolicy.federationExecution.rationale
                    )
                )
            }

            let approval = approvalEngine.createApproval(
                thread: baseThread,
                draft: composition.draft,
                kind: composition.draft.kind == .followUp
                    ? .followUpSend
                    : .outboundSend,
                expiresAt: nil,
                now: now
            )

            let approvalMutation = try threadEngine.requestApproval(
                thread: baseThread,
                approval: approval,
                now: now
            )

            try await store.performTransaction {
                try await store.saveApproval(approval)
                try await persist(mutation: approvalMutation)
            }
            turns.append(contentsOf: approvalMutation.turns)

            let approvalThread = approvalMutation.thread
            let approvalPolicy = policyEngine.evaluate(
                thread: approvalThread,
                selectedCounterparty: selectedCounterparty,
                draft: composition.draft,
                deliveryState: nil
            )

            let totalMs = Int((CFAbsoluteTimeGetCurrent() - interpretedStart) * 1000)
            secOrchLog("handleInterpretedRequest END | thread=\(approvalThread.id) | state=\(approvalThread.state) | action=approvalRequested | total=\(totalMs)ms")

            return Response(
                thread: approvalThread,
                turns: turns,
                approvals: [approval],
                drafts: [composition.draft],
                matches: [],
                counterparties: [selectedCounterparty],
                artifacts: [],
                summary: summaryEngine.threadSummary(
                    thread: approvalThread,
                    latestTurn: approvalMutation.turns.last
                ),
                handoff: .init(
                    selectedCounterpartyID: selectedCounterparty.id,
                    selectedCounterparty: selectedCounterparty,
                    latestDraftID: composition.draft.id,
                    latestDraft: composition.draft,
                    latestApprovalID: approval.id,
                    latestApproval: approval,
                    latestAction: .approvalRequested,
                    federationExecutionEligible: approvalPolicy.federationExecution.allowed,
                    federationExecutionReason: approvalPolicy.federationExecution.rationale
                )
            )
        }

        if !wantsDiscovery {
            secOrchLog("no discovery selected | thread=\(baseThread.id)")
            let response = try await buildThreadOnlyResponse(
                thread: baseThread,
                summaryOverride: request.userSummary ?? "The secretary understood the request, but no discovery step was selected.",
                handoffAction: nil,
                federationReason: request.userNextStep
            )
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - interpretedStart) * 1000)
            secOrchLog("handleInterpretedRequest END | thread=\(response.thread.id) | state=\(response.thread.state) | action=threadOnly | total=\(totalMs)ms")
            return response
        }

        secOrchLog("discovery starting | thread=\(baseThread.id) | query=\(searchQuerySummary(for: baseThread) ?? "nil")")
        let searchMutation = try threadEngine.startSearch(
            thread: baseThread,
            querySummary: searchQuerySummary(for: baseThread),
            now: now
        )

        try await store.performTransaction {
            try await persist(mutation: searchMutation)
        }
        turns.append(contentsOf: searchMutation.turns)

        DiscoveryHeroProgressNotifier.report(
            discoveryHeroProgressReporter,
            context: progressContext,
            stage: .searchingPublicNodes,
            threadID: searchMutation.thread.id
        )

        let discovery = try await discoveryService.discoverAndRank(
            thread: searchMutation.thread,
            progressContext: progressContext
        )
        secOrchLog("discovery finished | thread=\(searchMutation.thread.id)")

        DiscoveryHeroProgressNotifier.report(
            discoveryHeroProgressReporter,
            context: progressContext,
            stage: .finalizing,
            threadID: searchMutation.thread.id
        )

        return try await buildDiscoveryResponse(
            userText: userText,
            requestUserSummary: request.userSummary,
            baseTurns: turns,
            searchThread: searchMutation.thread,
            discovery: discovery,
            now: now
        )
    }

    func handleClarificationAnswered(
        existingThread: ExchangeThread,
        answerText: String,
        request: ExchangeInterpreter.InterpretedRequest,
        answerTurns: [ExchangeTurn],
        now: Date
    ) async throws -> Response {
        var forcedRequest = request
        forcedRequest.shouldDiscover = true
        forcedRequest.shouldDraft = false
        forcedRequest.userQuestion = nil

        if forcedRequest.userSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            forcedRequest.userSummary = "Clarification received. Continuing with search."
        }

        if forcedRequest.userNextStep?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            forcedRequest.userNextStep = "Continue with discovery."
        }

        let refreshedThread = try await store.requireThread(id: existingThread.id)

        let response = try await handleInterpretedRequest(
            existingThread: refreshedThread,
            userText: answerText,
            request: forcedRequest,
            now: now
        )

        return mergedClarificationResumeResponse(
            response: response,
            prependedTurns: answerTurns
        )
    }

    func mergedClarificationResumeResponse(
        response: Response,
        prependedTurns: [ExchangeTurn]
    ) -> Response {
        guard !prependedTurns.isEmpty else { return response }

        var merged = response
        merged.turns = prependedTurns + response.turns
        merged.handoff.latestAction = .clarificationAnswered
        return merged
    }

    func buildClarificationResumeText(
        thread: ExchangeThread,
        answer: String
    ) -> String {
        let priorRequest = [
            thread.intent.title,
            thread.intent.targetDescription,
            thread.intent.objective,
            thread.interpretation?.userSummary
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        if priorRequest.isEmpty {
            return "Clarification answer:\n\(answer)"
        }

        return """
        Original request:
        \(priorRequest)

        Clarification answer:
        \(answer)

        Reinterpret the request using the clarification and continue with discovery.
        """
    }

    func buildDiscoveryResponse(
        userText: String,
        requestUserSummary: String?,
        baseTurns: [ExchangeTurn],
        searchThread: ExchangeThread,
        discovery: ExchangeDiscoveryService.ResultSet,
        now: Date
    ) async throws -> Response {
        var turns = baseTurns

        switch discovery {
        case .none(let none):
            secOrchLog(
                "discovery outcome = none | summary=\(none.summary) | recommendation=\(none.recommendation)"
            )

            let noMatchMutation = try threadEngine.recordNoMatch(
                thread: searchThread,
                explanation: requestUserSummary ?? none.summary,
                nextStep: none.recommendation,
                now: now
            )

            try await store.performTransaction {
                try await persist(mutation: noMatchMutation)
            }
            turns.append(contentsOf: noMatchMutation.turns)

            return Response(
                thread: noMatchMutation.thread,
                turns: turns,
                approvals: [],
                drafts: [],
                matches: [],
                counterparties: [],
                artifacts: [],
                summary: summaryEngine.threadSummary(
                    thread: noMatchMutation.thread,
                    latestTurn: noMatchMutation.turns.last
                ),
                handoff: .init(
                    selectedCounterpartyID: nil,
                    selectedCounterparty: nil,
                    latestDraftID: nil,
                    latestDraft: nil,
                    latestApprovalID: nil,
                    latestApproval: nil,
                    latestAction: .discoveryFailed,
                    federationExecutionEligible: false,
                    federationExecutionReason: none.recommendation,
                    workTrace: projectedHandoffWorkTrace(from: noMatchMutation.thread)
                )
            )

        case .weak(let weak):
            secOrchLog(
                "discovery outcome = weak | counterparties=\(weak.counterparties.count) | matches=\(weak.matches.count) | recommendation=\(weak.recommendation)"
            )

            let weakProfiles = weak.candidates.compactMap { $0.candidate.publicProfile }
            let weakOffers = weak.candidates.flatMap { $0.candidate.matchedOffers }

            let weakMutation = try threadEngine.recordWeakMatches(
                thread: searchThread,
                candidateIDs: weak.counterparties.map { $0.id },
                explanation: weak.summary,
                suggestion: weak.recommendation,
                now: now
            )
            var weakThread = weakMutation.thread
            ExchangeThreadDiscoveryGradeMetadata.applyWeakGrade(to: &weakThread.metadata)
            ExchangeThreadDiscoveryGradeMetadata.logWrite(
                rootThreadID: weakThread.rootThreadID ?? weakThread.id,
                thread: weakThread,
                classifyGrade: .weak
            )

            let weakMutationWithGrade = ExchangeThreadEngine.ThreadMutation(
                thread: weakThread,
                turns: weakMutation.turns
            )

            try await store.performTransaction {
                try await persistDiscoveryEntities(
                    counterparties: weak.counterparties,
                    publicProfiles: weakProfiles,
                    offers: weakOffers
                )
                try await store.saveMatches(weak.matches)

                var weakForSave = weakMutationWithGrade
                ExchangeThreadDiscoveryGradeMetadata.applyWeakGrade(to: &weakForSave.thread.metadata)
                let beforeSaveMetadata = weakForSave.thread.metadata
                try await persist(mutation: weakForSave)

                #if DEBUG
                if let persisted = try await store.fetchThread(id: weakForSave.thread.id) {
                    ExchangeThreadDiscoveryGradeMetadata.logPersistVerify(
                        rootThreadID: weakForSave.thread.rootThreadID ?? weakForSave.thread.id,
                        beforeSaveKeys: beforeSaveMetadata,
                        afterFetchKeys: persisted.metadata
                    )
                }
                #endif
            }
            turns.append(contentsOf: weakMutationWithGrade.turns)

            return Response(
                thread: weakMutationWithGrade.thread,
                turns: turns,
                approvals: [],
                drafts: [],
                matches: weak.matches,
                counterparties: weak.counterparties,
                artifacts: [],
                summary: summaryEngine.threadSummary(
                    thread: weakMutationWithGrade.thread,
                    latestTurn: weakMutationWithGrade.turns.last
                ),
                handoff: .init(
                    selectedCounterpartyID: nil,
                    selectedCounterparty: nil,
                    latestDraftID: nil,
                    latestDraft: nil,
                    latestApprovalID: nil,
                    latestApproval: nil,
                    latestAction: .weakMatchesFound,
                    federationExecutionEligible: false,
                    federationExecutionReason: weak.recommendation,
                    workTrace: projectedHandoffWorkTrace(from: weakMutationWithGrade.thread)
                )
            )

        case .found(let found):
            secOrchLog(
                "discovery outcome = found | counterparties=\(found.counterparties.count) | matches=\(found.matches.count) | bestMatch=\(found.bestMatch?.counterpartyID ?? "nil")"
            )

            let foundProfiles = found.candidates.compactMap { $0.candidate.publicProfile }
            let foundOffers = found.candidates.flatMap { $0.candidate.matchedOffers }

            let childActivationPicks = topViableChildActivationCandidates(from: found.candidates)
            if !childActivationPicks.isEmpty {
                return try await finalizeFoundDiscoveryWithChildCoordination(
                    requestUserSummary: requestUserSummary,
                    baseTurns: turns,
                    searchThread: searchThread,
                    found: found,
                    foundProfiles: foundProfiles,
                    foundOffers: foundOffers,
                    childActivationPicks: childActivationPicks,
                    now: now
                )
            }

            guard let selectedMatch = found.bestMatch,
                  let selectedCounterparty = found.counterparties.first(where: { $0.id == selectedMatch.counterpartyID }) else {
                let resolution = failureResolver.resolve(
                    .init(
                        kind: .fit,
                        summary: "Candidates exist, but none are strong enough to advance yet.",
                        detail: "Discovery found candidates, but fit evaluation did not produce a strong enough match.",
                        externalEffect: .none,
                        recommendation: .reviewMismatch("Review the candidate quality and refine if needed."),
                        reasonCode: "no_advanceable_match"
                    )
                )

                let failureMutation = try threadEngine.markFailure(
                    thread: searchThread,
                    failure: resolution.failure,
                    mappedState: resolution.mappedState,
                    now: now
                )

                try await store.performTransaction {
                    try await persistDiscoveryEntities(
                        counterparties: found.counterparties,
                        publicProfiles: foundProfiles,
                        offers: foundOffers
                    )
                    try await store.saveMatches(found.matches)
                    try await persist(mutation: failureMutation)
                }
                turns.append(contentsOf: failureMutation.turns)

                return Response(
                    thread: failureMutation.thread,
                    turns: turns,
                    approvals: [],
                    drafts: [],
                    matches: found.matches,
                    counterparties: found.counterparties,
                    artifacts: [],
                    summary: summaryEngine.threadSummary(
                        thread: failureMutation.thread,
                        latestTurn: failureMutation.turns.last
                    ),
                    handoff: .init(
                        selectedCounterpartyID: nil,
                        selectedCounterparty: nil,
                        selectedPublicProfileID: nil,
                        selectedOfferID: nil,
                        latestMatchID: nil,
                        latestMatch: nil,
                        latestDraftID: nil,
                        latestDraft: nil,
                        latestApprovalID: nil,
                        latestApproval: nil,
                        latestAction: .noAdvanceableMatch,
                        federationExecutionEligible: false,
                        federationExecutionReason: "No strong enough match is ready to advance.",
                        workTrace: projectedHandoffWorkTrace(from: failureMutation.thread)
                    )
                )
            }

            let selectedPublicProfileID = selectedProfileID(from: selectedMatch)
            var selectedOfferID = selectedOfferID(from: selectedMatch, thread: searchThread)
            let matchLane = ExchangeThreadLaneResolver.lane(for: searchThread)
            if ExchangeThreadLaneResolver.clearsCommercialOfferAnchor(for: matchLane) {
                selectedOfferID = nil
            }
            #if DEBUG
            secOrchLog(
                "match/thread creation | selectedCounterpartyID=\(selectedCounterparty.id) | selectedPublicProfileID=\(selectedPublicProfileID ?? "nil") | selectedOfferID=\(selectedOfferID ?? "nil") | matchedOfferID=\(selectedMatch.offerID ?? selectedMatch.matchedOfferIDs.first ?? "nil")"
            )
            #endif

            let selectedName = selectedCounterparty.bestDisplayLine
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let selectedSummary: String = {
                if let selectedOfferID, !selectedOfferID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return selectedName.isEmpty
                        ? "Found a likely offer path and selected the strongest current match."
                        : "Found a likely offer path through \(selectedName)."
                }

                if let selectedPublicProfileID, !selectedPublicProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return selectedName.isEmpty
                        ? "Found a likely public profile path and selected the strongest current match."
                        : "Found a likely public profile path through \(selectedName)."
                }

                return selectedName.isEmpty
                    ? "Found a likely path and selected the strongest current match."
                    : "Found a likely path through \(selectedName)."
            }()

            let selectedMutation = try threadEngine.recordSelectedMatch(
                thread: searchThread,
                selectedCounterpartyID: selectedCounterparty.id,
                selectedPublicProfileID: selectedPublicProfileID,
                selectedOfferID: selectedOfferID,
                candidateIDs: found.counterparties.map(\.id),
                summary: selectedSummary,
                nextStep: "Review the found path.",
                now: now
            )

            var mutationToPersist = selectedMutation
            let canonicalSelection = makeCanonicalDiscoverySelection(
                from: selectedMatch,
                thread: searchThread,
                source: .selectedMatch
            )
            ExchangeThreadCanonicalDiscoverySelectionMetadata.apply(
                canonicalDiscoverySelectionSnapshot(from: canonicalSelection),
                to: &mutationToPersist.thread.metadata
            )
            let persistedMutation = mutationToPersist

            try await store.performTransaction {
                try await persistDiscoveryEntities(
                    counterparties: found.counterparties,
                    publicProfiles: foundProfiles,
                    offers: foundOffers
                )
                try await store.saveMatches(found.matches)
                try await persist(mutation: persistedMutation)
            }
            turns.append(contentsOf: persistedMutation.turns)

            return Response(
                thread: persistedMutation.thread,
                turns: turns,
                approvals: [],
                drafts: [],
                matches: found.matches,
                counterparties: found.counterparties,
                artifacts: [],
                summary: requestUserSummary ?? selectedSummary,
                handoff: .init(
                    selectedCounterpartyID: selectedCounterparty.id,
                    selectedCounterparty: selectedCounterparty,
                    selectedPublicProfileID: selectedPublicProfileID,
                    selectedOfferID: selectedOfferID,
                    latestMatchID: selectedMatch.id,
                    latestMatch: selectedMatch,
                    latestDraftID: nil,
                    latestDraft: nil,
                    latestApprovalID: nil,
                    latestApproval: nil,
                    latestAction: .matchSelected,
                    federationExecutionEligible: false,
                    federationExecutionReason: "A strong discovery match was selected.",
                    workTrace: projectedHandoffWorkTrace(from: persistedMutation.thread)
                ),
                canonicalDiscoverySelection: canonicalSelection
            )
        }
    }

    func persist(mutation: ExchangeThreadEngine.ThreadMutation) async throws {
        secOrchLog("persist mutation | thread=\(mutation.thread.id) | state=\(mutation.thread.state) | turns=\(mutation.turns.count)")
        try await store.updateThread(mutation.thread)
        for turn in mutation.turns {
            try await store.appendTurn(turn)
        }
    }
    
    func continueClarificationAnswerInBackground(
        threadID: ExchangeThread.ID,
        answerText: String,
        now: Date
    ) async {
        do {
            let currentThread = try await store.requireThread(id: threadID)
            let resumeText = buildClarificationResumeText(
                thread: currentThread,
                answer: answerText
            )

            let reinterpretedRequest = await interpreter.interpretClarificationAnswer(
                userText: resumeText,
                originalThread: currentThread,
                clarificationAnswer: answerText
            )

            _ = try await handleClarificationAnswered(
                existingThread: currentThread,
                answerText: answerText,
                request: reinterpretedRequest,
                answerTurns: [],
                now: now
            )

            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("secretaryWorkspaceShouldRefresh"),
                    object: nil,
                    userInfo: ["threadID": threadID.uuidString]
                )
            }

            secOrchLog("continueClarificationAnswerInBackground DONE | threadID=\(threadID)")
        } catch {
            secOrchLog("continueClarificationAnswerInBackground FAILED | threadID=\(threadID) | error=\(error)")

            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("secretaryWorkspaceShouldRefresh"),
                    object: nil,
                    userInfo: ["threadID": threadID.uuidString]
                )
            }
        }
    }

    func buildThreadOnlyResponse(
        thread: ExchangeThread,
        summaryOverride: String? = nil,
        handoffAction: Handoff.Action?,
        federationReason: String?
    ) async throws -> Response {
        let turns = try await store.listTurns(
            threadID: thread.id,
            limit: nil,
            ascending: true
        )

        let summary = summaryOverride ?? summaryEngine.threadSummary(
            thread: thread,
            latestTurn: turns.last
        )

        let selectedCounterparty = try await loadSelectedCounterparty(for: thread)

        return Response(
            thread: thread,
            turns: turns,
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: selectedCounterparty.map { [$0] } ?? [],
            artifacts: [],
            summary: summary,
            handoff: .init(
                selectedCounterpartyID: thread.selectedCounterpartyID,
                selectedCounterparty: selectedCounterparty,
                selectedPublicProfileID: thread.selectedPublicProfileID,
                selectedOfferID: thread.selectedOfferID,
                latestMatchID: nil,
                latestMatch: nil,
                latestDraftID: nil,
                latestDraft: nil,
                latestApprovalID: nil,
                latestApproval: nil,
                latestAction: handoffAction,
                federationExecutionEligible: false,
                federationExecutionReason: federationReason,
                workTrace: projectedHandoffWorkTrace(from: thread)
            )
        )
    }

    func buildResponse(
        thread: ExchangeThread,
        turns: [ExchangeTurn],
        approvals: [ExchangeApproval],
        drafts: [ExchangeMessageDraft],
        matches: [ExchangeMatch],
        counterparties: [ExchangeCounterparty],
        artifacts: [ExchangeArtifact],
        handoff: Handoff
    ) async throws -> Response {
        let summary = summaryEngine.threadSummary(
            thread: thread,
            latestTurn: turns.last
        )

        var projectedHandoff = handoff

        if projectedHandoff.selectedCounterpartyID == nil {
            projectedHandoff.selectedCounterpartyID = thread.selectedCounterpartyID
        }

        if projectedHandoff.selectedCounterparty == nil,
           let selectedID = projectedHandoff.selectedCounterpartyID {
            if let localCounterparty = counterparties.first(where: { $0.id == selectedID }) {
                projectedHandoff.selectedCounterparty = localCounterparty
            } else {
                projectedHandoff.selectedCounterparty = try await store.fetchCounterparty(id: selectedID)
            }
        }

        if projectedHandoff.selectedPublicProfileID == nil {
            projectedHandoff.selectedPublicProfileID = thread.selectedPublicProfileID
        }

        if projectedHandoff.selectedOfferID == nil {
            projectedHandoff.selectedOfferID = thread.selectedOfferID
        }

        if projectedHandoff.latestMatch == nil,
           let selectedCounterpartyID = projectedHandoff.selectedCounterpartyID {
            if let selectedMatch = matches.first(where: { $0.counterpartyID == selectedCounterpartyID }) {
                projectedHandoff.latestMatch = selectedMatch
            } else {
                projectedHandoff.latestMatch = matches.first
            }

            projectedHandoff.latestMatchID = projectedHandoff.latestMatch?.id
        }

        projectedHandoff.workTrace = projectedHandoffWorkTrace(from: thread)

        return Response(
            thread: thread,
            turns: turns,
            approvals: approvals,
            drafts: drafts,
            matches: matches,
            counterparties: counterparties,
            artifacts: artifacts,
            summary: summary,
            handoff: projectedHandoff
        )
    }

    static let discoveryChildActivationTopN = 3

    struct ChildActivationPick: Sendable {
        let sourceMatch: ExchangeMatch
        let sourceRank: Int
    }

    func topViableChildActivationCandidates(
        from rankedCandidates: [ExchangeDiscoveryService.RankedCandidate],
        maxCount: Int = discoveryChildActivationTopN
    ) -> [ChildActivationPick] {
        var seenCounterpartyIDs = Set<String>()
        var picks: [ChildActivationPick] = []

        for ranked in rankedCandidates {
            guard picks.count < maxCount else { break }
            guard ranked.isAdvanceable else { continue }
            guard ranked.match.strength != .weak else { continue }

            let counterpartyID = ranked.match.counterpartyID
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !counterpartyID.isEmpty else { continue }
            guard seenCounterpartyIDs.insert(counterpartyID).inserted else { continue }

            picks.append(
                ChildActivationPick(
                    sourceMatch: ranked.match,
                    sourceRank: picks.count + 1
                )
            )
        }

        return picks
    }

    func childCoordinationSelectionSummary(
        match: ExchangeMatch,
        counterparties: [ExchangeCounterparty]
    ) -> String {
        let selectedPublicProfileID = selectedProfileID(from: match)
        let selectedOfferID = selectedOfferID(from: match)
        let selectedCounterparty = counterparties.first(where: { $0.id == match.counterpartyID })
        let selectedName = selectedCounterparty?.bestDisplayLine
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let selectedOfferID,
           !selectedOfferID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedName.isEmpty
                ? "Found a likely offer path and selected the strongest current match."
                : "Found a likely offer path through \(selectedName)."
        }

        if let selectedPublicProfileID,
           !selectedPublicProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedName.isEmpty
                ? "Found a likely public profile path and selected the strongest current match."
                : "Found a likely public profile path through \(selectedName)."
        }

        return selectedName.isEmpty
            ? "Found a likely path and selected the strongest current match."
            : "Found a likely path through \(selectedName)."
    }

    func finalizeFoundDiscoveryWithChildCoordination(
        requestUserSummary: String?,
        baseTurns: [ExchangeTurn],
        searchThread: ExchangeThread,
        found: ExchangeDiscoveryService.Found,
        foundProfiles: [ExchangePublicNodeProfile],
        foundOffers: [ExchangeOffer],
        childActivationPicks: [ChildActivationPick],
        now: Date
    ) async throws -> Response {
        var turns = baseTurns

        var umbrellaThread = searchThread
        ExchangeThreadRoleResolver.applyUmbrellaSearchRole(
            rootThreadID: umbrellaThread.id,
            to: &umbrellaThread.metadata
        )

        var umbrellaMutation = try threadEngine.recordWeakMatches(
            thread: umbrellaThread,
            candidateIDs: found.counterparties.map(\.id),
            explanation: found.summary,
            suggestion: "Review search results or compare providers.",
            now: now
        )
        ExchangeThreadRoleResolver.applyUmbrellaSearchRole(
            rootThreadID: umbrellaMutation.thread.id,
            to: &umbrellaMutation.thread.metadata
        )

        let umbrellaThreadID = umbrellaMutation.thread.id
        let childRequestResolution = ExchangeChildCoordinationRequestText.resolveChildRequestCapturedText(
            umbrellaTurns: turns,
            umbrellaThread: umbrellaMutation.thread,
            requestUserSummary: requestUserSummary
        )
        let existingThreads = try await store.listThreads(
            filter: ExchangeThreadFilter(limit: 2_000)
        )
        let coordinationIndex = ExchangeCoordinationThreadIndex(threads: existingThreads)

        var childCreations: [ExchangeThreadEngine.ChildCoordinationThreadCreation] = []
        childCreations.reserveCapacity(childActivationPicks.count)
        var activatedChildThreadIDs: [ExchangeThread.ID] = []
        activatedChildThreadIDs.reserveCapacity(childActivationPicks.count)
        var newlyCreatedChildThreadIDs: [ExchangeThread.ID] = []
        var activeChildCount = coordinationIndex.childCount(parentID: umbrellaThreadID)

        for pick in childActivationPicks {
            let counterpartyID = pick.sourceMatch.counterpartyID
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let existingChild = coordinationIndex.existingChildThread(
                parentID: umbrellaThreadID,
                sourceMatchID: pick.sourceMatch.id,
                counterpartyID: counterpartyID
            ) {
                activatedChildThreadIDs.append(existingChild.id)
                let matchKind: String
                if existingChild.sourceMatchID == pick.sourceMatch.id {
                    matchKind = "sourceMatchID"
                } else {
                    matchKind = "counterpartyID"
                }
                discoveryChildActivationLog(
                    "action=reuseExistingChild " +
                    "umbrellaThreadID=\(umbrellaThreadID.uuidString) " +
                    "childThreadID=\(existingChild.id.uuidString) " +
                    "sourceMatchID=\(pick.sourceMatch.id.uuidString) " +
                    "existingSourceMatchID=\(existingChild.sourceMatchID?.uuidString ?? "nil") " +
                    "sourceRank=\(pick.sourceRank) " +
                    "counterpartyID=\(counterpartyID) " +
                    "matchKind=\(matchKind)"
                )
                continue
            }

            if activeChildCount >= Self.discoveryChildActivationTopN {
                discoveryChildActivationLog(
                    "action=skipDuplicateCounterparty " +
                    "umbrellaThreadID=\(umbrellaThreadID.uuidString) " +
                    "sourceMatchID=\(pick.sourceMatch.id.uuidString) " +
                    "sourceRank=\(pick.sourceRank) " +
                    "counterpartyID=\(counterpartyID) " +
                    "reason=topNCap existingChildCount=\(activeChildCount)"
                )
                continue
            }

            let selectionSummary = childCoordinationSelectionSummary(
                match: pick.sourceMatch,
                counterparties: found.counterparties
            )

            let creation = try threadEngine.beginChildCoordinationThread(
                from: umbrellaMutation.thread,
                sourceMatch: pick.sourceMatch,
                sourceRank: pick.sourceRank,
                originalRequesterText: childRequestResolution.text,
                originalRequesterTextSource: childRequestResolution.source,
                summary: selectionSummary,
                nextStep: "Review the found path.",
                now: now
            )
            childCreations.append(creation)
            activatedChildThreadIDs.append(creation.thread.id)
            newlyCreatedChildThreadIDs.append(creation.thread.id)
            activeChildCount += 1

            discoveryChildActivationLog(
                "action=createChild " +
                "umbrellaThreadID=\(umbrellaThreadID.uuidString) " +
                "childThreadID=\(creation.thread.id.uuidString) " +
                "sourceMatchID=\(pick.sourceMatch.id.uuidString) " +
                "sourceRank=\(pick.sourceRank) " +
                "counterpartyID=\(counterpartyID) " +
                "publicProfileID=\(pick.sourceMatch.publicProfileID ?? "nil") " +
                "offerID=\(pick.sourceMatch.offerID ?? "nil") " +
                "activationPolicy=topN"
            )
        }

        let childThreadIDs = activatedChildThreadIDs
        let persistedChildCreations = childCreations
        let umbrellaRootThreadID = umbrellaMutation.thread.rootThreadID ?? umbrellaMutation.thread.id

        var parentToPersist = umbrellaMutation
        ExchangeThreadRoleResolver.applyUmbrellaSearchRole(
            rootThreadID: parentToPersist.thread.id,
            to: &parentToPersist.thread.metadata
        )
        umbrellaMutation = parentToPersist

        let primaryChildPick = childActivationPicks.first
        let canonicalSelection = makeCanonicalDiscoverySelection(
            from: found.bestMatch,
            thread: umbrellaMutation.thread,
            source: .bestMatch,
            primaryCoordinationChildThreadID: activatedChildThreadIDs.first,
            primaryChildSourceMatch: primaryChildPick?.sourceMatch
        )
        ExchangeThreadCanonicalDiscoverySelectionMetadata.apply(
            canonicalDiscoverySelectionSnapshot(from: canonicalSelection),
            to: &parentToPersist.thread.metadata
        )

        ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
            classifyGrade: found.classifyGrade,
            activatedChildCount: childThreadIDs.count,
            to: &parentToPersist.thread.metadata
        )
        ExchangeThreadDiscoveryGradeMetadata.logWrite(
            rootThreadID: umbrellaRootThreadID,
            thread: parentToPersist.thread,
            classifyGrade: found.classifyGrade
        )

        let gradeContext = ExchangeUmbrellaDiscoveryGradeProjection.Context(
            activatedChildCount: childThreadIDs.count,
            strongestChildSourceRank: primaryChildPick?.sourceRank ?? (childThreadIDs.isEmpty ? nil : 1),
            strongestChildProofValid: ExchangeUmbrellaDiscoveryGradeProjection.isProofValidForProjection(
                match: primaryChildPick?.sourceMatch ?? found.bestMatch,
                thread: parentToPersist.thread
            )
        )
        let gradeResolution = ExchangeUmbrellaDiscoveryGradeProjection.resolve(
            thread: parentToPersist.thread,
            context: gradeContext
        )
        ExchangeUmbrellaDiscoveryGradeProjection.logDecision(
            rootThreadID: umbrellaRootThreadID,
            resolution: gradeResolution,
            context: gradeContext,
            strongestChildOfferID: primaryChildPick?.sourceMatch.offerID
        )

        umbrellaMutation = parentToPersist
        let parentMutationForPersist = parentToPersist
        let childPersistPayloads: [(thread: ExchangeThread, creation: ExchangeThreadEngine.ChildCoordinationThreadCreation)] =
            persistedChildCreations.map { creation in
                var childToPersist = creation.thread
                ExchangeThreadRoleResolver.applyCandidateCoordinationHierarchy(
                    parentThreadID: umbrellaThreadID,
                    rootThreadID: umbrellaRootThreadID,
                    sourceMatchID: creation.sourceMatchID,
                    sourceRank: creation.sourceRank,
                    to: &childToPersist.metadata
                )
                return (thread: childToPersist, creation: creation)
            }

        try await store.performTransaction {
            try await persistDiscoveryEntities(
                counterparties: found.counterparties,
                publicProfiles: foundProfiles,
                offers: foundOffers
            )
            try await store.saveMatches(found.matches)

            var umbrellaForSave = parentMutationForPersist
            ExchangeThreadDiscoveryGradeMetadata.applyFoundGrade(
                classifyGrade: found.classifyGrade,
                activatedChildCount: childThreadIDs.count,
                to: &umbrellaForSave.thread.metadata
            )
            let beforeSaveMetadata = umbrellaForSave.thread.metadata
            try await persist(mutation: umbrellaForSave)

            #if DEBUG
            if let persisted = try await store.fetchThread(id: umbrellaForSave.thread.id) {
                ExchangeThreadDiscoveryGradeMetadata.logPersistVerify(
                    rootThreadID: umbrellaRootThreadID,
                    beforeSaveKeys: beforeSaveMetadata,
                    afterFetchKeys: persisted.metadata
                )
            }
            #endif

            for payload in childPersistPayloads {
                if try await store.fetchThread(id: payload.thread.id) == nil {
                    try await store.createThread(payload.thread)
                } else {
                    try await store.updateThread(payload.thread)
                }
                for turn in payload.creation.turns {
                    try await store.appendTurn(turn)
                }
                try await store.saveMatches([payload.creation.childMatch])
            }
        }

        if let persistedUmbrella = try await store.fetchThread(id: parentMutationForPersist.thread.id) {
            umbrellaMutation = ExchangeThreadEngine.ThreadMutation(
                thread: persistedUmbrella,
                turns: umbrellaMutation.turns
            )
        }

        turns.append(contentsOf: umbrellaMutation.turns)

        discoveryUmbrellaLog(
            "umbrellaThreadID=\(umbrellaMutation.thread.id.uuidString) " +
            "resultCount=\(found.matches.count) " +
            "viableCount=\(childActivationPicks.count) " +
            "topN=\(Self.discoveryChildActivationTopN) " +
            "activatedChildCount=\(childThreadIDs.count) " +
            "reusedChildCount=\(childThreadIDs.count - newlyCreatedChildThreadIDs.count) " +
            "newChildCount=\(newlyCreatedChildThreadIDs.count)"
        )

        let activationSummary = requestUserSummary ?? found.summary

        return Response(
            thread: umbrellaMutation.thread,
            turns: turns,
            approvals: [],
            drafts: [],
            matches: found.matches,
            counterparties: found.counterparties,
            artifacts: [],
            summary: activationSummary,
            handoff: .init(
                selectedCounterpartyID: nil,
                selectedCounterparty: nil,
                selectedPublicProfileID: nil,
                selectedOfferID: nil,
                latestMatchID: nil,
                latestMatch: nil,
                latestDraftID: nil,
                latestDraft: nil,
                latestApprovalID: nil,
                latestApproval: nil,
                latestAction: .weakMatchesFound,
                federationExecutionEligible: false,
                federationExecutionReason:
                    "\(childThreadIDs.count) coordination path(s) activated from search results.",
                workTrace: projectedHandoffWorkTrace(from: umbrellaMutation.thread)
            ),
            coordinationChildThreadIDs: newlyCreatedChildThreadIDs,
            canonicalDiscoverySelection: canonicalSelection
        )
    }

    func normalizeTerms(_ values: [String], maxCount: Int) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            output.append(trimmed)
            if output.count >= maxCount {
                break
            }
        }

        return output
    }

    func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}
