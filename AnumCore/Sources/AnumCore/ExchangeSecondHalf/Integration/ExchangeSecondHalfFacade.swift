import Foundation

#if DEBUG
@inline(__always)
private func exchSecondHalfFacadeLog(_ message: @autoclosure () -> String) {
    Swift.print("[ExchangeSecondHalfFacade] \(message())")
}
#else
@inline(__always)
private func exchSecondHalfFacadeLog(_ message: @autoclosure () -> String) {}
#endif

/// Public façade for the new second-half subsystem.
///
/// This is the single integration surface the app layer should call.
/// It keeps the rest of the app from depending directly on engine/orchestration internals.
public struct ExchangeSecondHalfFacade: Sendable {
    private let coordinator: ExchangeSecondHalfCoordinator
    private let threadAdapter: ExchangeSecondHalfThreadAdapter
    private let storeAdapter: any ExchangeSecondHalfStoreAdapter
    private let federationAdapter: any ExchangeSecondHalfFederationAdapter
    private let uiAdapter: ExchangeSecondHalfUIAdapter
    private let operatingMemoryStore: any ExchangeOperatingMemoryStore
    private let styleStore: any ExchangeSecretaryStyleStore
    private let localNodeIDProvider: (@Sendable () async throws -> String?)?
    private let priorsStore: any ExchangeThreadPriorsStore
    private let operatingMemoryAssembler: ExchangeOperatingMemoryAssembler
    /// When set, published seller offer/profile rows hydrate operating memory when saved memory is empty.
    private let exchangeStore: (any ExchangeStore)?
    /// Optional copy-only composer (P1 mock / P2 on-device); never affects deterministic pause authority.
    private let closureComposer: (any ExchangeRequesterClosureComposing)?
    private let closureCopyValidator: ExchangeRequesterClosureCopyValidator
    private let closureComposeTimeoutSeconds: Double
    private let preferAsyncCoordinatorEvaluation: Bool

    public init(
        coordinator: ExchangeSecondHalfCoordinator = .init(),
        threadAdapter: ExchangeSecondHalfThreadAdapter = .init(),
        storeAdapter: (any ExchangeSecondHalfStoreAdapter)? = nil,
        federationAdapter: any ExchangeSecondHalfFederationAdapter = ExchangeDefaultSecondHalfFederationAdapter(),
        uiAdapter: ExchangeSecondHalfUIAdapter = .init(),
        operatingMemoryStore: any ExchangeOperatingMemoryStore = ExchangeDefaultOperatingMemoryStore(),
        styleStore: any ExchangeSecretaryStyleStore = ExchangeDefaultSecretaryStyleStore(),
        localNodeIDProvider: (@Sendable () async throws -> String?)? = nil,
        priorsStore: (any ExchangeThreadPriorsStore)? = nil,
        operatingMemoryAssembler: ExchangeOperatingMemoryAssembler = .init(),
        exchangeStore: (any ExchangeStore)? = nil,
        closureComposer: (any ExchangeRequesterClosureComposing)? = nil,
        closureCopyValidator: ExchangeRequesterClosureCopyValidator = ExchangeRequesterClosureCopyValidator(),
        closureComposeTimeoutSeconds: Double = 2.5,
        preferAsyncCoordinatorEvaluation: Bool = false
    ) {
        self.coordinator = coordinator
        self.threadAdapter = threadAdapter
        self.storeAdapter = storeAdapter ?? ExchangeDefaultSecondHalfStoreAdapter(exchangeStore: exchangeStore)
        self.federationAdapter = federationAdapter
        self.uiAdapter = uiAdapter
        self.operatingMemoryStore = operatingMemoryStore
        self.styleStore = styleStore
        self.localNodeIDProvider = localNodeIDProvider
        if let priorsStore {
            self.priorsStore = priorsStore
        } else if let exchangeStore {
            self.priorsStore = ExchangeStoreBackedThreadPriorsStore(exchangeStore: exchangeStore)
        } else {
            self.priorsStore = ExchangeDefaultThreadPriorsStore()
        }
        self.operatingMemoryAssembler = operatingMemoryAssembler
        self.exchangeStore = exchangeStore
        self.closureComposer = closureComposer
        self.closureCopyValidator = closureCopyValidator
        self.closureComposeTimeoutSeconds = closureComposeTimeoutSeconds
        self.preferAsyncCoordinatorEvaluation = preferAsyncCoordinatorEvaluation
    }

    public func evaluateThread(
        _ snapshot: ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot,
        policy: ExchangeSecondHalfPolicy = .default
    ) async throws -> ExchangeSecondHalfCoordinator.Result {
        exchSecondHalfFacadeLog(
            "evaluateThread enter thread=\(snapshot.threadID.uuidString) role=\(snapshot.role.rawValue)"
        )

        let style = try await loadSecretaryStyleProfile(for: snapshot)
        let assembledMemory = try await assembledOperatingMemory(for: snapshot)

        var mergedSnapshot = snapshot
        let storedPriors = try await priorsStore.loadPriors(forThreadID: snapshot.threadID, role: snapshot.role)
        if let storedPriors {
            mergedSnapshot = merge(snapshot: snapshot, priors: storedPriors)
        }

        let context = threadAdapter.makeExecutionContext(
            from: mergedSnapshot,
            styleProfile: style,
            operatingMemory: assembledMemory
        )

        var result: ExchangeSecondHalfCoordinator.Result
        if preferAsyncCoordinatorEvaluation {
            result = await coordinator.evaluateAsync(
                context: context,
                policy: policy
            )
        } else {
            result = coordinator.evaluate(
                context: context,
                policy: policy
            )
        }

        if snapshot.role == .requester,
           let composer = closureComposer,
           let pause = result.requesterPauseFrame,
           pause.pauseReason != .completed
        {
            let input = makeClosureComposerInput(
                snapshot: mergedSnapshot,
                result: result,
                pause: pause,
                style: style
            )
            if let raw = await ExchangeRequesterClosureComposeSupport.composeWithTimeout(
                composer: composer,
                input: input,
                timeoutSeconds: closureComposeTimeoutSeconds
            ),
               let validated = closureCopyValidator.validate(raw, against: pause)
            {
                result.requesterClosureComposedCopy = validated
            }
        }

        try await persist(result: result, threadID: snapshot.threadID, role: snapshot.role, existingPriors: storedPriors)

        exchSecondHalfFacadeLog(
            "evaluateThread exit nextState=\(result.nextState.rawValue) action=\(result.plan.selectedAction.rawValue)"
        )

        return result
    }

    /// Same seller-surface + thread/node memory fusion used by evaluation (Pass 2 agency grounding).
    ///
    /// Note: `ExchangeFacade` may apply a compare-specific delta filter when embedding OSM next to hydrated profile/offer facts so prompts are not double-filled.
    public func assembledOperatingMemory(
        for snapshot: ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot
    ) async throws -> ExchangeStructuredOperatingMemory {
        try await loadAssembledOperatingMemory(for: snapshot)
    }

    /// Loads style profile for coordinator execution contexts (prefers thread, then node, then defaults).
    public func secretaryStyleProfile(
        for snapshot: ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot
    ) async throws -> ExchangeSecretaryStyleProfile {
        try await loadSecretaryStyleProfile(for: snapshot)
    }

    public func handleInboundInquiry(
        _ snapshot: ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot,
        inquiry: ExchangeInboundInquiry,
        policy: ExchangeSecondHalfPolicy = .default
    ) async throws -> ExchangeSecondHalfCoordinator.Result {
        var updated = snapshot
        updated.inquiry = inquiry
        return try await evaluateThread(updated, policy: policy)
    }

    public func submitUserClarification(
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        clarification: String
    ) async throws {
        exchSecondHalfFacadeLog(
            "submitUserClarification thread=\(threadID.uuidString) role=\(role.rawValue)"
        )

        let existing = try await priorsStore.loadPriors(forThreadID: threadID, role: role) ?? .empty
        let updated = ExchangeThreadPriors(
            priorQuestionsAsked: existing.priorQuestionsAsked,
            priorAnswersReceived: existing.priorAnswersReceived + [clarification],
            currentConstraints: existing.currentConstraints,
            priorNonCommitments: existing.priorNonCommitments,
            lastKnownRecommendation: existing.lastKnownRecommendation,
            latestDelta: existing.latestDelta,
            threadStanceSnapshot: existing.threadStanceSnapshot
        )
        try await priorsStore.savePriors(updated, forThreadID: threadID, role: role)
    }

    public func approveCommitment(
        threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        exchSecondHalfFacadeLog(
            "approveCommitment thread=\(threadID.uuidString) role=\(role.rawValue)"
        )
        try await federationAdapter.sendDecisionUpdate(
            threadID: threadID,
            role: role,
            action: .accept
        )
    }

    public func decline(
        threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        exchSecondHalfFacadeLog(
            "decline thread=\(threadID.uuidString) role=\(role.rawValue)"
        )
        try await federationAdapter.sendDecisionUpdate(
            threadID: threadID,
            role: role,
            action: .decline
        )
    }

    public func complete(
        threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws {
        exchSecondHalfFacadeLog(
            "complete thread=\(threadID.uuidString) role=\(role.rawValue)"
        )
        try await federationAdapter.sendDecisionUpdate(
            threadID: threadID,
            role: role,
            action: .complete
        )
    }

    /// Returns the role that was locked by the first successful `evaluateThread` call for
    /// this thread.  Once priors exist for a given role, that role should not change even
    /// if `lastInboundEnvelopeID` is later set (which would otherwise cause `inferSecondHalfRole`
    /// to flip from `.requester` to `.provider` on inbound reply).
    ///
    /// `.requester` is checked first so user-initiated threads keep their outbound role.
    /// Returns `nil` if no priors exist yet (new thread, first evaluation).
    public func loadFirstEstablishedRole(for threadID: UUID) async -> ExchangeSecondHalfRole? {
        if let priors = try? await priorsStore.loadPriors(forThreadID: threadID, role: .requester),
           priors.hasMeaningfulContext {
            return .requester
        }
        if let priors = try? await priorsStore.loadPriors(forThreadID: threadID, role: .provider),
           priors.hasMeaningfulContext {
            return .provider
        }
        return nil
    }

    public func getProjection(
        _ result: ExchangeSecondHalfCoordinator.Result,
        inquiry: ExchangeInboundInquiry? = nil,
        agencyAssessment: ExchangeAgencyAssessment? = nil,
        requesterSurfaceContext: ExchangeRequesterReviewSurfaceContext? = nil
    ) -> ExchangeSecondHalfProjection {
        ExchangeSecondHalfProjection(
            coordinatorResult: result,
            inquiry: inquiry,
            agencyAssessment: agencyAssessment,
            requesterSurfaceContext: requesterSurfaceContext
        )
    }

    public func getDisplayModel(
        _ result: ExchangeSecondHalfCoordinator.Result,
        inquiry: ExchangeInboundInquiry? = nil,
        agencyAssessment: ExchangeAgencyAssessment? = nil,
        requesterSurfaceContext: ExchangeRequesterReviewSurfaceContext? = nil,
        outboundSendContext: ExchangeSecondHalfOutboundSendContext? = nil
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel {
        let projection = getProjection(
            result,
            inquiry: inquiry,
            agencyAssessment: agencyAssessment,
            requesterSurfaceContext: requesterSurfaceContext
        )
        return uiAdapter.makeDisplayModel(from: projection, outboundSendContext: outboundSendContext)
    }

    public func refreshDisplayAfterRequesterOutboundSendBlocked(
        display: ExchangeSecondHalfUIAdapter.DisplayModel,
        thread: ExchangeThread,
        latestDraft: ExchangeMessageDraft?
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel {
        uiAdapter.refreshDisplayAfterRequesterOutboundSendBlocked(
            display: display,
            thread: thread,
            latestDraft: latestDraft
        )
    }

    /// Read-only projection from persisted thread second-half snapshot.
    /// Deterministic and side-effect free.
    public func getCachedDisplayModel(
        snapshot: ExchangeThread.SecondHalfSnapshot,
        thread: ExchangeThread,
        selectedCounterpartyName: String?,
        latestDraft: ExchangeMessageDraft? = nil
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel {
        uiAdapter.makeDisplayModel(
            from: snapshot,
            thread: thread,
            selectedCounterpartyName: selectedCounterpartyName,
            latestDraft: latestDraft
        )
    }

    public func loadSecondHalfAgencySnapshot(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole
    ) async throws -> ExchangeSecondHalfAgencySnapshot? {
        try await storeAdapter.loadSecondHalfRecord(forThreadID: threadID, role: role)?.agency
    }

    public func saveSecondHalfAgencySnapshot(
        forThreadID threadID: UUID,
        role: ExchangeSecondHalfRole,
        agency: ExchangeSecondHalfAgencySnapshot?
    ) async throws {
        guard var record = try await storeAdapter.loadSecondHalfRecord(forThreadID: threadID, role: role) else {
            return
        }
        record.agency = agency
        record.savedAt = Date()
        try await storeAdapter.saveSecondHalfRecord(record)
    }

    private func loadSecretaryStyleProfile(
        for snapshot: ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot
    ) async throws -> ExchangeSecretaryStyleProfile {
        let threadStyle = try await styleStore.loadStyleProfile(
            forThreadID: snapshot.threadID,
            role: snapshot.role
        )

        let nodeScopedID = ExchangeSecretaryStyleScopeID.nodeScopedUUID(
            from: try await localNodeIDProvider?()
        )
        let nodeStyle: ExchangeSecretaryStyleProfile?
        if let nodeScopedID {
            nodeStyle = try await styleStore.loadStyleProfile(
                forNodeID: nodeScopedID,
                role: snapshot.role
            )
        } else {
            nodeStyle = nil
        }

        return threadStyle ?? nodeStyle ?? .default
    }

    private func loadAssembledOperatingMemory(
        for snapshot: ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot
    ) async throws -> ExchangeStructuredOperatingMemory {

        let threadMemory = try await operatingMemoryStore.loadOperatingMemory(
            forThreadID: snapshot.threadID,
            role: snapshot.role
        )

        let nodeMemory = try await operatingMemoryStore.loadOperatingMemory(
            forNodeID: snapshot.threadID,
            role: snapshot.role
        )

        let preliminaryMemory = operatingMemoryAssembler.assemble(
            input: .init(
                role: snapshot.role,
                threadScoped: threadMemory,
                nodeScoped: nodeMemory,
                fallback: .empty
            )
        )

        let fallbackMemory: ExchangeStructuredOperatingMemory
        if preliminaryMemory.hasProviderFacts {
            fallbackMemory = .empty
        } else {
            fallbackMemory = await loadHydratedSellerSurfaceMemory(threadID: snapshot.threadID)
        }

        return operatingMemoryAssembler.assemble(
            input: .init(
                role: snapshot.role,
                threadScoped: threadMemory,
                nodeScoped: nodeMemory,
                fallback: fallbackMemory
            )
        )
    }

    private func persist(
        result: ExchangeSecondHalfCoordinator.Result,
        threadID: UUID,
        role: ExchangeSecondHalfRole,
        existingPriors: ExchangeThreadPriors? = nil
    ) async throws {
        let snapshot = ExchangeSecondHalfRecord(
            threadID: threadID,
            role: role,
            state: result.nextState,
            qualification: result.qualification,
            latestDecisionFrame: result.decisionFrame,
            latestDelta: result.delta,
            latestStance: result.stance,
            latestBoundary: result.boundary,
            latestPlan: result.plan,
            pendingDraft: result.draft,
            lastOutcome: nil
        )

        try await storeAdapter.saveSecondHalfRecord(snapshot)
        try await storeAdapter.saveStanceRecord(
            ExchangeThreadStanceRecord(threadID: threadID, role: role, stance: result.stance)
        )

        if let frame = result.decisionFrame {
            try await storeAdapter.saveDecisionFrameRecord(
                ExchangeDecisionFrameRecord(threadID: threadID, role: role, frame: frame)
            )
        }

        try await storeAdapter.saveDeltaRecord(
            ExchangeThreadDeltaRecord(threadID: threadID, role: role, delta: result.delta)
        )

        let priors = ExchangeThreadPriors(
            priorQuestionsAsked: existingPriors?.priorQuestionsAsked ?? [],
            priorAnswersReceived: existingPriors?.priorAnswersReceived ?? [],
            currentConstraints: [],
            priorNonCommitments: [],
            lastKnownRecommendation: result.decisionFrame?.recommendation,
            latestDelta: result.delta,
            threadStanceSnapshot: result.stance
        )
        try await priorsStore.savePriors(priors, forThreadID: threadID, role: role)
    }

    private func loadHydratedSellerSurfaceMemory(threadID: UUID) async -> ExchangeStructuredOperatingMemory {
        guard let exchangeStore else {
            return .empty
        }

        do {
            guard let thread = try await exchangeStore.fetchThread(id: threadID) else {
                return .empty
            }

            var publicProfile: ExchangePublicNodeProfile?
            var offer: ExchangeOffer?

            if let pid = thread.selectedPublicProfileID.flatMap({ trimNonBlank($0) }) {
                publicProfile = try await exchangeStore.fetchPublicProfile(id: pid)
            }

            if let oid = thread.selectedOfferID.flatMap({ trimNonBlank($0) }) {
                offer = try await exchangeStore.fetchOffer(id: oid)
            }

            if publicProfile == nil, let opid = offer?.publicProfileID.flatMap({ trimNonBlank($0) }) {
                publicProfile = try await exchangeStore.fetchPublicProfile(id: opid)
            }

            let hydrated = ExchangeSellerSurfaceOperatingMemoryHydrator.hydrate(
                publicProfile: publicProfile,
                offer: offer
            )
            guard hydrated.hasProviderFacts else {
                return .empty
            }

            exchSecondHalfFacadeLog(
                "loadHydratedSellerSurfaceMemory hydrated | thread=\(threadID.uuidString) " +
                    "offer=\(offer != nil) profile=\(publicProfile != nil)"
            )

            return hydrated
        } catch {
            #if DEBUG
            exchSecondHalfFacadeLog(
                "loadHydratedSellerSurfaceMemory failed | thread=\(threadID.uuidString) | \(error)"
            )
            #endif

            return .empty
        }
    }

    private func trimNonBlank(_ value: String) -> String? {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func requesterAskBlob(from snapshot: ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot) -> String {
        var parts: [String] = []
        if let ask = snapshot.inquiry?.requesterAsk.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty {
            parts.append(ask)
        }
        if let sm = snapshot.subjectMatter?.trimmingCharacters(in: .whitespacesAndNewlines), !sm.isEmpty {
            parts.append(sm)
        }
        let itemsJoined = snapshot.requestedItems.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !itemsJoined.isEmpty {
            parts.append(itemsJoined)
        }
        if let ci = snapshot.customInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !ci.isEmpty {
            parts.append(ci)
        }
        return parts.joined(separator: " ")
    }

    private func makeClosureComposerInput(
        snapshot: ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot,
        result: ExchangeSecondHalfCoordinator.Result,
        pause: ExchangeRequesterPauseFrame,
        style: ExchangeSecretaryStyleProfile
    ) -> ExchangeRequesterClosureComposerInput {
        let blob = requesterAskBlob(from: snapshot)
        let blobOut = blob.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Request" : blob
        return ExchangeRequesterClosureComposerInput(
            requesterAskBlob: blobOut,
            latestProviderReply: snapshot.latestCounterpartyReplyText,
            deterministicPause: pause,
            decisionFrame: result.decisionFrame,
            boundaryRequiresHumanApproval: result.boundary.requiresHumanApproval,
            boundaryReasonLine: result.boundary.requiresHumanApproval ? result.boundary.reason : nil,
            selectedOfferSummary: nil,
            selectedProfileSummary: nil,
            styleProfile: style,
            representationSupplement: nil
        )
    }

    private func merge(
        snapshot: ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot,
        priors: ExchangeThreadPriors
    ) -> ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot {
        ExchangeSecondHalfThreadAdapter.LegacyThreadSnapshot(
            threadID: snapshot.threadID,
            role: snapshot.role,
            state: snapshot.state,
            priorQuestionsAsked: priors.priorQuestionsAsked.isEmpty ? snapshot.priorQuestionsAsked : priors.priorQuestionsAsked,
            priorAnswersReceived: priors.priorAnswersReceived.isEmpty ? snapshot.priorAnswersReceived : priors.priorAnswersReceived,
            currentConstraints: priors.currentConstraints.isEmpty ? snapshot.currentConstraints : priors.currentConstraints,
            priorNonCommitments: priors.priorNonCommitments.isEmpty ? snapshot.priorNonCommitments : priors.priorNonCommitments,
            knownFacts: snapshot.knownFacts,
            unresolvedIssues: snapshot.unresolvedIssues,
            surfacedCandidateCount: snapshot.surfacedCandidateCount,
            clarificationRounds: snapshot.clarificationRounds,
            followUpAttempts: snapshot.followUpAttempts,
            autonomousRoundsSoFar: snapshot.autonomousRoundsSoFar,
            isTimeSensitive: snapshot.isTimeSensitive,
            isPriceSensitive: snapshot.isPriceSensitive,
            hasLowTrustSignals: snapshot.hasLowTrustSignals,
            hasComparableAlternatives: snapshot.hasComparableAlternatives,
            hasFreshProviderAnswer: snapshot.hasFreshProviderAnswer,
            counterpartyName: snapshot.counterpartyName,
            subjectMatter: snapshot.subjectMatter,
            requestedItems: snapshot.requestedItems,
            clarifiedFacts: snapshot.clarifiedFacts,
            inquiry: snapshot.inquiry,
            structuredQuery: snapshot.structuredQuery,
            isCustomPricing: snapshot.isCustomPricing,
            includesSensitiveDisclosure: snapshot.includesSensitiveDisclosure,
            includesScheduleCommitment: snapshot.includesScheduleCommitment,
            includesLegalCommercialCommitment: snapshot.includesLegalCommercialCommitment,
            isPolicyException: snapshot.isPolicyException,
            lastDecisionFrame: snapshot.lastDecisionFrame,
            latestDelta: priors.latestDelta ?? snapshot.latestDelta,
            lastKnownStance: priors.threadStanceSnapshot ?? snapshot.lastKnownStance,
            lastApprovedPosition: snapshot.lastApprovedPosition,
            previousRecommendation: priors.lastKnownRecommendation ?? snapshot.previousRecommendation,
            customInstructions: snapshot.customInstructions,
            latestCounterpartyReplyText: snapshot.latestCounterpartyReplyText,
            isThreadExplicitlyCompleted: snapshot.isThreadExplicitlyCompleted,
            selectedCounterpartyID: snapshot.selectedCounterpartyID,
            selectedPublicProfileID: snapshot.selectedPublicProfileID,
            selectedOfferID: snapshot.selectedOfferID,
            lastInboundEnvelopeID: snapshot.lastInboundEnvelopeID,
            providerCompareFirstStructuredPillarBypassPacket: snapshot.providerCompareFirstStructuredPillarBypassPacket,
            requestCapturedText: snapshot.requestCapturedText,
            isFirstExternalContact: snapshot.isFirstExternalContact
        )
    }
}
