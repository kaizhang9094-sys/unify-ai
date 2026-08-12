import Foundation

#if DEBUG
@inline(__always)
private func exchangeThreadDbg(_ message: @autoclosure () -> String) {
    Swift.print(message())
}

@inline(__always)
private func discoveryChildCreateLog(_ message: @autoclosure () -> String) {
    Swift.print(message())
}

@inline(__always)
private func childSearchQuerySourceLog(_ message: @autoclosure () -> String) {
    Swift.print(message())
}

@inline(__always)
private func childSelectionTurnLog(_ message: @autoclosure () -> String) {
    Swift.print(message())
}

@inline(__always)
private func childSearchQueryWarningLog(_ message: @autoclosure () -> String) {
    Swift.print(message())
}
#else
@inline(__always)
private func exchangeThreadDbg(_ message: @autoclosure () -> String) { }

@inline(__always)
private func discoveryChildCreateLog(_ message: @autoclosure () -> String) { }

@inline(__always)
private func childSearchQuerySourceLog(_ message: @autoclosure () -> String) { }

@inline(__always)
private func childSelectionTurnLog(_ message: @autoclosure () -> String) { }

@inline(__always)
private func childSearchQueryWarningLog(_ message: @autoclosure () -> String) { }
#endif

public struct ExchangeThreadEngine: Sendable {
    private let stateMachine: ExchangeStateMachine

    public init(stateMachine: ExchangeStateMachine = .init()) {
        self.stateMachine = stateMachine
    }

    public func beginThread(
        userText: String,
        mode: ExchangeMode,
        intent: ExchangeIntent,
        posture: ExchangePosture,
        interpretation: ExchangeThread.InterpretationSnapshot? = nil,
        expectation: ExchangeExpectation? = nil,
        facets: ExchangeIntentFacets? = nil,
        workTrace: ExchangeThread.WorkTraceSnapshot? = nil,
        now: Date = Date()
    ) -> ThreadMutation {
        let initialTrace =
            workTrace ??
            ExchangeThread.WorkTraceSnapshot
                .starter(headline: "Starting secretary work.", at: now)
                .appendingStep(
                    key: "understanding_request",
                    title: "Understanding request",
                    detail: interpretation?.userSummary ?? intent.summaryLine,
                    activating: true,
                    at: now
                )

        var threadMetadata: [String: String] = [:]
        let lane = ExchangeThreadLaneResolver.lane(for: intent, metadata: threadMetadata)
        ExchangeThreadLaneResolver.applyLane(lane, to: &threadMetadata)

        let trimmedUserText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUserText.isEmpty {
            threadMetadata[ExchangeThread.originalRequesterTextMetadataKey] = trimmedUserText
        }

        let thread = ExchangeThread(
            createdAt: now,
            updatedAt: now,
            mode: mode,
            intent: intent,
            posture: posture,
            facets: facets,
            interpretation: interpretation,
            workTrace: initialTrace,
            expectation: expectation,
            autonomousClarificationCount: 0,
            state: .drafting,
            visibleSummary: interpretation?.userSummary,
            metadata: threadMetadata
        )

        let turn = ExchangeTurn.requestCaptured(
            threadID: thread.id,
            summary: trimmedUserText.isEmpty ? intent.summaryLine : trimmedUserText,
            detail: nil,
            createdAt: now
        )

        exchangeThreadDbg(
            "[ExchangeThreadEngine] beginThread " +
            "thread=\(thread.id.uuidString) " +
            "mode=\(mode.rawValue) " +
            "intent=\(intent.kind.rawValue) " +
            "hasFacets=\(facets != nil) " +
            "hasInterpretation=\(interpretation != nil) " +
            "semanticTags=\(interpretation?.semanticTags.joined(separator: ",") ?? "-") " +
            "discoveryKeywords=\(interpretation?.discoveryKeywords.joined(separator: ",") ?? "-") " +
            "targetTags=\(interpretation?.targetTags.joined(separator: ",") ?? "-")"
        )

        return ThreadMutation(thread: thread, turns: [turn])
    }

    public func askForClarification(
        thread: ExchangeThread,
        failure: ExchangeFailure,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let question = clarificationQuestion(from: failure)

        exchangeThreadDbg(
            "[ExchangeThreadEngine] askForClarification " +
            "thread=\(thread.id.uuidString) " +
            "from=\(thread.state.phaseTitle) " +
            "question=\(question) " +
            "failureKind=\(failure.kind) " +
            "failureSummary=\(failure.summary)"
        )

        guard thread.autonomousClarificationCount < 1 else {
            throw ExchangeThreadEngineError.invalidTransition(
                "This thread has already consumed its single clarification turn."
            )
        }

        if case .needsClarification(let status) = thread.state {
            exchangeThreadDbg(
                "[ExchangeThreadEngine] askForClarification ALREADY_IN_NEEDS_CLARIFICATION " +
                "thread=\(thread.id.uuidString) " +
                "existingQuestion=\(status.question) " +
                "existingAttempts=\(status.attempts) " +
                "newQuestion=\(question)"
            )

            throw ExchangeThreadEngineError.invalidTransition(
                "Thread is already waiting on a clarification answer."
            )
        }

        let nextState = ExchangeState.needsClarification(
            .init(
                question: question,
                askedAt: now,
                attempts: 1
            )
        )

        let trace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingBlocked(
                headline: failure.summary,
                at: now
            )
            .appendingStep(
                key: "asking_clarification",
                title: "Asking clarification",
                detail: question,
                activating: true,
                at: now
            )

        let updated = try transition(
            thread: thread.settingWorkTrace(trace, at: now),
            to: nextState,
            trigger: .clarificationRequired,
            now: now,
            failure: failure,
            visibleSummary: failure.summary
        )

        let turn = ExchangeTurn.clarificationAsked(
            threadID: updated.id,
            question: question,
            createdAt: now
        )

        exchangeThreadDbg(
            "[ExchangeThreadEngine] askForClarification DONE " +
            "thread=\(updated.id.uuidString) " +
            "to=\(updated.state.phaseTitle)"
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func recordClarificationAnswer(
        thread: ExchangeThread,
        answer: String,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw ExchangeThreadEngineError.invalidTransition(
                "Clarification answer requires non-empty text."
            )
        }

        guard case .needsClarification = thread.state else {
            throw ExchangeThreadEngineError.invalidTransition(
                "Clarification answer can only be recorded while thread is in needsClarification."
            )
        }

        guard thread.autonomousClarificationCount < 1 else {
            throw ExchangeThreadEngineError.invalidTransition(
                "This thread has already consumed its single clarification turn."
            )
        }

        exchangeThreadDbg(
            "[ExchangeThreadEngine] recordClarificationAnswer " +
            "thread=\(thread.id.uuidString) " +
            "answer=\(trimmed)"
        )

        let trace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                key: "asking_clarification",
                headline: "Clarification received.",
                at: now
            )
            .appendingStep(
                key: "understanding_request",
                title: "Understanding request",
                detail: trimmed,
                activating: true,
                at: now
            )

        var updated = thread
            .incrementingAutonomousClarificationCount(at: now)
            .clearingFailure(at: now, keepOutcome: false)
            .settingWorkTrace(trace, at: now)
            .withUpdatedState(
                .drafting,
                at: now,
                visibleSummary: "Clarification received. Resuming work."
            )

        if var interpretation = updated.interpretation {
            interpretation.needsClarification = false
            interpretation.userQuestion = nil
            interpretation.userNextStep = "Continue with discovery."
            interpretation.userSummary = trimmed
            updated = updated.settingInterpretation(interpretation, at: now)
        }

        let turn = ExchangeTurn.clarificationAnswered(
            threadID: updated.id,
            answer: trimmed,
            createdAt: now
        )

        exchangeThreadDbg(
            "[ExchangeThreadEngine] recordClarificationAnswer DONE " +
            "thread=\(updated.id.uuidString) " +
            "to=\(updated.state.phaseTitle)"
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func recordAutonomousClarification(
        thread: ExchangeThread,
        question: String,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExchangeThreadEngineError.invalidTransition(
                "Autonomous clarification requires a non-empty question."
            )
        }

        guard thread.canUseAutonomousClarification else {
            throw ExchangeThreadEngineError.invalidTransition(
                "This thread cannot use another autonomous clarification turn."
            )
        }

        let nextState = ExchangeState.awaitingResponse(
            .init(
                since: now,
                lastOutboundAt: now,
                followUpSuggestedAt: nil
            )
        )

        var updated = thread.incrementingAutonomousClarificationCount(at: now)

        let trace = (updated.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .appendingStep(
                key: "asking_clarification",
                title: "Asking clarification",
                detail: trimmed,
                activating: false,
                at: now
            )
            .markingComplete(
                key: "asking_clarification",
                headline: "Clarification sent. Waiting for reply.",
                at: now
            )
            .appendingStep(
                key: "waiting_for_reply",
                title: "Waiting for reply",
                detail: nil,
                activating: true,
                at: now
            )

        updated = updated.settingWorkTrace(trace, at: now)

        updated = try transition(
            thread: updated,
            to: nextState,
            trigger: .sendConfirmed,
            now: now,
            visibleSummary: trimmed
        )

        let turn = ExchangeTurn.clarificationAsked(
            threadID: updated.id,
            question: trimmed,
            createdAt: now
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func startSearch(
        thread: ExchangeThread,
        querySummary: String?,
        now: Date = Date()
    ) throws -> ThreadMutation {
        exchangeThreadDbg(
            "[ExchangeThreadEngine] startSearch " +
            "thread=\(thread.id.uuidString) " +
            "from=\(thread.state.phaseTitle) " +
            "query=\(querySummary ?? "-")"
        )

        let nextState = ExchangeState.searching(
            .init(
                startedAt: now,
                scopeSummary: thread.intent.targetDescription,
                querySummary: querySummary,
                candidateCount: 0
            )
        )

        let trigger = Self.searchStartTrigger(for: thread)

        let trace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                key: "understanding_request",
                headline: thread.workTrace?.headline,
                at: now
            )
            .appendingStep(
                key: "identifying_target",
                title: "Identifying target",
                detail: thread.intent.targetDescription ?? thread.intent.summaryLine,
                activating: false,
                at: now
            )
            .appendingStep(
                key: "searching_local_candidates",
                title: "Searching local candidates",
                detail: querySummary ?? thread.primarySearchText,
                activating: true,
                at: now
            )

        var workingThread = thread.settingWorkTrace(trace, at: now)

        if thread.stateKey == .needsClarification || thread.stateKey == .noViableMatch {
            workingThread = workingThread.clearingFailure(at: now, keepOutcome: false)
        }

        let updated = try transition(
            thread: workingThread,
            to: nextState,
            trigger: trigger,
            now: now,
            visibleSummary: "Searching for candidates."
        )

        let queryText = querySummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let turn = ExchangeTurn(
            threadID: updated.id,
            createdAt: now,
            actor: .system,
            kind: .searchStarted,
            summary: queryText ?? "Search started.",
            detail: queryText,
            visibility: .userVisible
        )

        exchangeThreadDbg(
            "[ExchangeThreadEngine] startSearch DONE " +
            "thread=\(updated.id.uuidString) " +
            "to=\(updated.state.phaseTitle) " +
            "trigger=\(trigger.rawValue)"
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    /// Chooses the legal transition trigger for entering ``ExchangeState/searching``.
    private static func searchStartTrigger(for thread: ExchangeThread) -> ExchangeTransition.Trigger {
        switch thread.stateKey {
        case .needsClarification:
            return .clarificationAnswered
        case .noViableMatch:
            exchangeThreadDbg(
                "[ExchangeThreadEngine] startSearch trigger=retryRequested reason=retryFromNoViableMatch"
            )
            return .retryRequested
        default:
            return .searchStarted
        }
    }

    public func recordWeakMatches(
        thread: ExchangeThread,
        candidateIDs: [ExchangeCounterparty.ID],
        explanation: String,
        suggestion: String?,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let normalizedCandidateIDs = normalizedIDs(candidateIDs)

        guard !normalizedCandidateIDs.isEmpty else {
            throw ExchangeThreadEngineError.invalidTransition(
                "Weak matches requires at least one candidate. Use recordNoMatch(...) when no candidates exist."
            )
        }

        let nextState = ExchangeState.matchCandidatesWeak(
            .init(
                candidateCount: normalizedCandidateIDs.count,
                explanation: explanation,
                suggestedRefinement: suggestion
            )
        )

        let trace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                key: "searching_local_candidates",
                headline: "Search completed with weak results.",
                at: now
            )
            .appendingStep(
                key: "ranking_likely_fits",
                title: "Ranking likely fits",
                detail: "\(normalizedCandidateIDs.count) candidates found, but none are strong enough yet",
                activating: false,
                at: now
            )
            .markingComplete(
                key: "ranking_likely_fits",
                headline: explanation,
                at: now
            )

        var updated = try transition(
            thread: thread
                .clearingFailure(at: now, keepOutcome: false)
                .updatingCandidates(normalizedCandidateIDs, at: now)
                .settingWorkTrace(trace, at: now),
            to: nextState,
            trigger: .weakMatchesDetected,
            now: now,
            visibleSummary: explanation
        )

        updated = updated.settingOutcome(
            .init(status: .noViableMatch, summary: explanation, recordedAt: now),
            at: now
        )

        if var interpretation = updated.interpretation {
            interpretation.needsClarification = false
            interpretation.userQuestion = nil
            interpretation.userSummary = explanation
            interpretation.userNextStep = suggestion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? suggestion
                : "Review the search results or refresh the search."
            updated = updated.settingInterpretation(interpretation, at: now)
        }

        let turn = ExchangeTurn.weakMatchesObserved(
            threadID: updated.id,
            summary: explanation,
            detail: suggestion,
            createdAt: now
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func recordNoMatch(
        thread: ExchangeThread,
        explanation: String,
        nextStep: String?,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let nextState = ExchangeState.noViableMatch(
            .init(
                searchedAt: now,
                explanation: explanation,
                suggestedNextStep: nextStep
            )
        )

        let trace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                key: "searching_local_candidates",
                headline: "Search completed with no viable match.",
                at: now
            )

        var updated = try transition(
            thread: thread
                .clearingFailure(at: now, keepOutcome: false)
                .updatingCandidates([], at: now)
                .settingWorkTrace(trace, at: now),
            to: nextState,
            trigger: .noMatchesDetected,
            now: now,
            visibleSummary: explanation
        )

        updated = updated.settingOutcome(
            .init(status: .noViableMatch, summary: explanation, recordedAt: now),
            at: now
        )

        if var interpretation = updated.interpretation {
            interpretation.needsClarification = false
            interpretation.userQuestion = nil
            interpretation.userSummary = explanation
            interpretation.userNextStep = nextStep?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? nextStep
                : "Refresh the search or refine the request."
            updated = updated.settingInterpretation(interpretation, at: now)
        }

        let turn = ExchangeTurn.noViableMatchObserved(
            threadID: updated.id,
            summary: explanation,
            detail: nextStep,
            createdAt: now
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }
    
    public func refreshSearch(
        thread: ExchangeThread,
        querySummary: String?,
        now: Date = Date()
    ) throws -> ThreadMutation {
        exchangeThreadDbg(
            "[ExchangeThreadEngine] refreshSearch " +
            "thread=\(thread.id.uuidString) " +
            "from=\(thread.state.phaseTitle) " +
            "query=\(querySummary ?? "-")"
        )

        let refreshedSummary = "Refreshing search from the current request."

        let refreshTrace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                headline: "Previous search result cleared.",
                at: now
            )
            .appendingStep(
                key: "search_refresh_requested",
                title: "Refreshing search",
                detail: querySummary ?? thread.primarySearchText,
                activating: false,
                at: now
            )
            .markingComplete(
                key: "search_refresh_requested",
                headline: refreshedSummary,
                at: now
            )

        var updated = thread
            .clearingFailure(at: now, keepOutcome: false)
            .updatingCandidates([], at: now)
            .selectingCounterparty(id: "", at: now)
            .settingSelectedPublicProfileID(nil, at: now)
            .settingSelectedOfferID(nil, at: now)
            .settingSelectedMatchRationale(nil, at: now)
            .settingSelectedPath(nil, at: now)
            .settingOutcome(nil, at: now)
            .settingApproval(nil, at: now)
            .settingDelivery(nil, at: now)
            .settingWorkTrace(refreshTrace, at: now)
            .withUpdatedState(
                .drafting,
                at: now,
                visibleSummary: refreshedSummary
            )

        if var interpretation = updated.interpretation {
            interpretation.needsClarification = false
            interpretation.userQuestion = nil
            interpretation.userSummary = refreshedSummary
            interpretation.userNextStep = "Continue with discovery."
            updated = updated.settingInterpretation(interpretation, at: now)
        }

        let turn = ExchangeTurn(
            threadID: updated.id,
            createdAt: now,
            actor: .user,
            kind: .searchStarted,
            summary: "Search refreshed.",
            detail: querySummary ?? thread.primarySearchText,
            visibility: .userVisible
        )

        exchangeThreadDbg(
            "[ExchangeThreadEngine] refreshSearch DONE " +
            "thread=\(updated.id.uuidString) " +
            "to=\(updated.state.phaseTitle)"
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }
    
    public func recordSelectedMatch(
        thread: ExchangeThread,
        selectedCounterpartyID: ExchangeCounterparty.ID,
        selectedPublicProfileID: ExchangePublicNodeProfile.ID?,
        selectedOfferID: ExchangeOffer.ID?,
        candidateIDs: [ExchangeCounterparty.ID],
        summary: String,
        nextStep: String? = nil,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let normalizedCandidateIDs = normalizedIDs(candidateIDs + [selectedCounterpartyID])

        let cleanSelectedCounterpartyID = selectedCounterpartyID
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanSelectedCounterpartyID.isEmpty else {
            throw ExchangeThreadEngineError.invalidTransition(
                "Selected match requires a non-empty counterparty id."
            )
        }

        guard !normalizedCandidateIDs.isEmpty else {
            throw ExchangeThreadEngineError.invalidTransition(
                "Selected match requires at least one candidate."
            )
        }

        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Found a likely path."
            : summary.trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanNextStep = nextStep?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? nextStep?.trimmingCharacters(in: .whitespacesAndNewlines)
            : "Continue on this found path to prepare the next step."

        let cleanProfileID = selectedPublicProfileID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank

        let threadLane = ExchangeThreadLaneResolver.lane(for: thread)
        let cleanOfferID: String? = {
            guard !ExchangeThreadLaneResolver.clearsCommercialOfferAnchor(for: threadLane) else {
                return nil
            }
            return selectedOfferID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfBlank
        }()

        let nextState = ExchangeState.matchFound(
            .init(
                foundAt: now,
                candidateCount: normalizedCandidateIDs.count,
                summary: cleanSummary,
                nextStep: cleanNextStep,
                selectedCounterpartyID: cleanSelectedCounterpartyID,
                selectedPublicProfileID: cleanProfileID,
                selectedOfferID: cleanOfferID
            )
        )

        let selectionDetail: String = {
            if let cleanOfferID, !cleanOfferID.isEmpty {
                return "Selected strongest offer match: \(cleanOfferID)"
            }

            if let cleanProfileID, !cleanProfileID.isEmpty {
                return "Selected strongest public profile match: \(cleanProfileID)"
            }

            return "Selected strongest counterparty match: \(cleanSelectedCounterpartyID)"
        }()

        let trace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                key: "searching_local_candidates",
                headline: cleanSummary,
                at: now
            )
            .appendingStep(
                key: "selecting_best_match",
                title: "Selecting best match",
                detail: selectionDetail,
                activating: false,
                at: now
            )
            .markingComplete(
                key: "selecting_best_match",
                headline: cleanSummary,
                at: now
            )
            .appendingStep(
                key: "awaiting_continue_on_found_path",
                title: "Found path ready",
                detail: cleanNextStep,
                activating: true,
                at: now
            )

        var updated = try transition(
            thread: thread
                .clearingFailure(at: now, keepOutcome: false)
                .updatingCandidates(normalizedCandidateIDs, at: now)
                .selectingCounterparty(id: cleanSelectedCounterpartyID, at: now)
                .settingSelectedPublicProfileID(cleanProfileID, at: now)
                .settingSelectedOfferID(cleanOfferID, at: now)
                .settingSelectedMatchRationale(cleanSummary, at: now)
                .settingSelectedPath(nil, at: now)
                .settingOutcome(nil, at: now)
                .settingWorkTrace(trace, at: now),
            to: nextState,
            trigger: .candidateAccepted,
            now: now,
            visibleSummary: cleanSummary
        )

        if var interpretation = updated.interpretation {
            interpretation.needsClarification = false
            interpretation.userQuestion = nil
            interpretation.userSummary = cleanSummary
            interpretation.userNextStep = cleanNextStep
            updated = updated.settingInterpretation(interpretation, at: now)
        }

        let resolvedLane = ExchangeThreadLaneResolver.lane(for: updated)
        ExchangeThreadLaneResolver.applyLane(resolvedLane, to: &updated.metadata)

        let turn = ExchangeTurn.candidateSelected(
            threadID: updated.id,
            summary: cleanSummary,
            detail: cleanNextStep,
            createdAt: now
        )

        #if DEBUG
        childSelectionTurnLog(
            "[ChildSelectionTurn] " +
            "childThreadID=\(updated.id.uuidString) " +
            "selectedOfferID=\(cleanOfferID ?? "nil") " +
            "turnKind=\(turn.kind.rawValue) " +
            "summary=\(String(cleanSummary.prefix(120))) " +
            "visibleSummaryUpdated=true"
        )
        #endif

        exchangeThreadDbg(
            "[ExchangeThreadEngine] recordSelectedMatch DONE " +
            "thread=\(updated.id.uuidString) " +
            "state=\(updated.state.phaseTitle) " +
            "selectedCounterpartyID=\(cleanSelectedCounterpartyID) " +
            "selectedPublicProfileID=\(cleanProfileID ?? "-") " +
            "selectedOfferID=\(cleanOfferID ?? "-") " +
            "candidateCount=\(normalizedCandidateIDs.count) " +
            "nextStep=\(cleanNextStep ?? "-")"
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    /// Creates a child coordination thread from an umbrella search thread and one ranked match.
    ///
    /// Reuses `beginThread`, `startSearch`, and `recordSelectedMatch`. Does not queue outbound,
    /// approval, or second-half work. Caller must persist the returned thread, turns, and
    /// `childMatch` (via `saveMatches`) when ready.
    public func beginChildCoordinationThread(
        from umbrellaThread: ExchangeThread,
        sourceMatch: ExchangeMatch,
        sourceRank: Int,
        originalRequesterText: String,
        originalRequesterTextSource: String,
        summary: String? = nil,
        nextStep: String? = nil,
        now: Date = Date()
    ) throws -> ChildCoordinationThreadCreation {
        guard sourceRank > 0 else {
            throw ExchangeThreadEngineError.invalidTransition(
                "Child coordination requires a positive source rank."
            )
        }

        let counterpartyID = sourceMatch.counterpartyID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !counterpartyID.isEmpty else {
            throw ExchangeThreadEngineError.invalidTransition(
                "Child coordination requires a non-empty counterparty id on the source match."
            )
        }

        let rootThreadID = umbrellaThread.rootThreadID ?? umbrellaThread.id
        let selectionSummary = Self.childCoordinationSummary(
            sourceMatch: sourceMatch,
            override: summary
        )

        let trimmedRequester = originalRequesterText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let childRequestText: String = {
            if !trimmedRequester.isEmpty,
               !umbrellaThread.looksLikeInternalSearchQuery(trimmedRequester),
               !ExchangeChildCoordinationRequestText.isDiscoveryOrSelectionSummary(trimmedRequester) {
                return trimmedRequester
            }
            if let stored = umbrellaThread.metadata[ExchangeThread.originalRequesterTextMetadataKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !stored.isEmpty,
               !umbrellaThread.looksLikeInternalSearchQuery(stored),
               !ExchangeChildCoordinationRequestText.isDiscoveryOrSelectionSummary(stored) {
                return stored
            }
            if !trimmedRequester.isEmpty {
                return trimmedRequester
            }
            return "New request"
        }()
        let childRequestLogSource = ExchangeChildCoordinationRequestText.childSearchQueryLogSource(
            for: originalRequesterTextSource
        )

        let beginMutation = beginThread(
            userText: childRequestText,
            mode: umbrellaThread.mode,
            intent: umbrellaThread.intent,
            posture: umbrellaThread.posture,
            interpretation: umbrellaThread.interpretation,
            expectation: umbrellaThread.expectation,
            facets: umbrellaThread.facets,
            workTrace: nil,
            now: now
        )

        var childThread = beginMutation.thread
        Self.mergeCoordinationLaneMetadata(from: umbrellaThread, onto: &childThread.metadata)
        if childThread.metadata[ExchangeThread.originalRequesterTextMetadataKey]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            childThread.metadata[ExchangeThread.originalRequesterTextMetadataKey] = childRequestText
        }
        ExchangeThreadRoleResolver.applyCandidateCoordinationHierarchy(
            parentThreadID: umbrellaThread.id,
            rootThreadID: rootThreadID,
            sourceMatchID: sourceMatch.id,
            sourceRank: sourceRank,
            to: &childThread.metadata
        )

        let searchMutation = try startSearch(
            thread: childThread,
            querySummary: childRequestText,
            now: now
        )
        childThread = searchMutation.thread

        childSearchQuerySourceLog(
            "[ChildSearchQuerySource] " +
            "childThreadID=\(childThread.id.uuidString) " +
            "childRequestText=\(String(childRequestText.prefix(120))) " +
            "searchStartedQuery=\(String(childRequestText.prefix(120))) " +
            "source=\(childRequestLogSource)"
        )

        let selectedMutation = try recordSelectedMatch(
            thread: childThread,
            selectedCounterpartyID: counterpartyID,
            selectedPublicProfileID: sourceMatch.publicProfileID,
            selectedOfferID: sourceMatch.offerID,
            candidateIDs: [counterpartyID],
            summary: selectionSummary,
            nextStep: nextStep,
            now: now
        )

        let childMatch = sourceMatch.copyingForChildCoordinationThread(
            threadID: selectedMutation.thread.id,
            createdAt: now
        )

        let preview = String(childRequestText.prefix(120))
            .replacingOccurrences(of: "\n", with: " ")
        discoveryChildCreateLog(
            "[DiscoveryChildCreate] " +
            "umbrellaThreadID=\(umbrellaThread.id.uuidString) " +
            "childThreadID=\(selectedMutation.thread.id.uuidString) " +
            "sourceMatchID=\(sourceMatch.id.uuidString) " +
            "sourceRank=\(sourceRank) " +
            "counterpartyID=\(counterpartyID) " +
            "publicProfileID=\(sourceMatch.publicProfileID ?? "nil") " +
            "offerID=\(sourceMatch.offerID ?? "nil") " +
            "childRequestTextSource=\(originalRequesterTextSource) " +
            "childRequestPreview=\(preview)"
        )

        let allTurns = beginMutation.turns + searchMutation.turns + selectedMutation.turns
        let searchStartedTurns = allTurns.filter { $0.kind == .searchStarted }
        if searchStartedTurns.count > 1 {
            let first = searchStartedTurns.min(by: { $0.createdAt < $1.createdAt })
            let latest = searchStartedTurns.max(by: { $0.createdAt < $1.createdAt })
            childSearchQueryWarningLog(
                "[ChildSearchQueryWarning] " +
                "childThreadID=\(selectedMutation.thread.id.uuidString) " +
                "searchStartedCount=\(searchStartedTurns.count) " +
                "latestSearchStarted=\(String((latest?.summary ?? "nil").prefix(120))) " +
                "firstSearchStarted=\(String((first?.summary ?? "nil").prefix(120)))"
            )
        }

        return ChildCoordinationThreadCreation(
            thread: selectedMutation.thread,
            turns: allTurns,
            childMatch: childMatch,
            sourceMatchID: sourceMatch.id,
            sourceRank: sourceRank
        )
    }

    public func requestApproval(
        thread: ExchangeThread,
        approval: ExchangeApproval,
        now: Date = Date()
    ) throws -> ThreadMutation {
        exchangeThreadDbg(
            "[ExchangeThreadEngine] requestApproval " +
            "thread=\(thread.id.uuidString) " +
            "from=\(thread.state.phaseTitle) " +
            "approval=\(approval.id.uuidString) " +
            "draft=\(approval.draftID?.uuidString ?? "-") " +
            "summary=\(approval.summary)"
        )

        let nextState = ExchangeState.awaitingApproval(
            .init(
                requestedAt: now,
                summary: approval.summary,
                draftID: approval.draftID,
                expiresAt: approval.expiresAt
            )
        )

        let trace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .appendingStep(
                key: "preparing_outreach_draft",
                title: "Preparing outreach draft",
                detail: approval.summary,
                activating: false,
                at: now
            )
            .markingComplete(
                key: "preparing_outreach_draft",
                headline: "Draft ready for approval.",
                at: now
            )
            .appendingStep(
                key: "awaiting_approval",
                title: "Awaiting approval",
                detail: approval.summary,
                activating: true,
                at: now
            )

        var updated = try transition(
            thread: thread
                .settingApproval(
                    .init(
                        status: .pending,
                        requestedAt: now,
                        requestedDraftID: approval.draftID,
                        note: approval.rationale
                    ),
                    at: now
                )
                .settingWorkTrace(trace, at: now),
            to: nextState,
            trigger: .approvalRequested,
            now: now,
            visibleSummary: approval.summary
        )

        updated = updated.settingDelivery(
            .init(
                status: .pendingApproval,
                note: "Awaiting user approval."
            ),
            at: now
        )

        let turn = ExchangeTurn.approvalRequested(
            threadID: updated.id,
            summary: approval.summary,
            detail: approval.rationale,
            createdAt: now
        )

        exchangeThreadDbg(
            "[ExchangeThreadEngine] requestApproval DONE " +
            "thread=\(updated.id.uuidString) " +
            "to=\(updated.state.phaseTitle)"
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func grantApproval(
        thread: ExchangeThread,
        approval: ExchangeApproval,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let nextState = ExchangeState.sending(
            .init(
                startedAt: now,
                attemptNumber: nextAttemptNumber(from: thread),
                channelSummary: "Preparing outbound coordination."
            )
        )

        var updated = thread.settingApproval(
            .init(
                status: .approved,
                requestedAt: approval.createdAt,
                decidedAt: approval.decidedAt ?? now,
                requestedDraftID: approval.draftID,
                note: approval.decisionNote
            ),
            at: now
        )

        updated = updated.settingDelivery(
            .init(
                status: .readyToSend,
                lastAttemptAt: nil,
                lastConfirmedSendAt: nil,
                externalReference: nil,
                note: "Approval granted. Outbound send is ready to queue."
            ),
            at: now
        )

        let trace = (updated.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                key: "awaiting_approval",
                headline: "Approval granted.",
                at: now
            )
            .appendingStep(
                key: "ready_to_send",
                title: "Ready to send",
                detail: "Preparing outbound coordination.",
                activating: true,
                at: now
            )

        updated = updated.settingWorkTrace(trace, at: now)

        updated = try transition(
            thread: updated,
            to: nextState,
            trigger: .approvalGranted,
            now: now,
            visibleSummary: "Approval granted. Preparing to send."
        )

        let turn = ExchangeTurn(
            threadID: updated.id,
            createdAt: now,
            actor: .user,
            kind: .approvalGranted,
            summary: "Approval granted.",
            detail: approval.decisionNote,
            visibility: .userVisible
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    /// Records an approval decision without entering the outbound **sending / ready-to-send** pipeline.
    ///
    /// Used when federation/policy gates block immediate queueing (for example missing public recipient
    /// routing posture) so UI does not show “Sending” with zero outbox evidence.
    public func grantApprovalCoordinationHold(
        thread: ExchangeThread,
        approval: ExchangeApproval,
        coordinationNote: String?,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let trimmedNote = coordinationNote.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        let userVisibleNote =
            trimmedNote ?? "Unify recorded your approval, but the next external message cannot be queued yet."

        var updated = thread.settingApproval(
            .init(
                status: .approved,
                requestedAt: approval.createdAt,
                decidedAt: approval.decidedAt ?? now,
                requestedDraftID: approval.draftID,
                note: approval.decisionNote
            ),
            at: now
        )

        updated = updated.settingDelivery(
            .init(
                status: .notStarted,
                lastAttemptAt: nil,
                lastConfirmedSendAt: nil,
                externalReference: nil,
                note: "Approval granted. Outbound send is on hold until coordination inputs are satisfied."
            ),
            at: now
        )

        let trace = (updated.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                key: "awaiting_approval",
                headline: "Approval granted.",
                at: now
            )
            .appendingStep(
                key: "coordination_input_needed_after_approval",
                title: "Needs your input",
                detail: userVisibleNote,
                activating: true,
                at: now
            )

        updated = updated.settingWorkTrace(trace, at: now)

        let nextState: ExchangeState
        if let mfStatus = try? matchFoundStatusForCoordinationHold(thread: thread, now: now) {
            nextState = .matchFound(mfStatus)
        } else if let draftID = approval.draftID ?? awaitingApprovalDraftID(from: thread) {
            let summary =
                thread.visibleSummary.flatMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                }
                ?? "Coordination needs input before sending."
            nextState = .draftReady(.init(preparedAt: now, summary: summary, draftID: draftID))
        } else {
            throw ExchangeThreadEngineError.invalidTransition(
                "Cannot resolve a coordination-safe thread state after approval (missing anchors and draft id)."
            )
        }

        updated = try transition(
            thread: updated,
            to: nextState,
            trigger: .approvalGranted,
            now: now,
            visibleSummary: "Approval granted. Needs your input before sending."
        )

        let detailPieces = [approval.decisionNote, trimmedNote].compactMap { $0 }
        let combinedDetail = detailPieces
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        let turn = ExchangeTurn(
            threadID: updated.id,
            createdAt: now,
            actor: .user,
            kind: .approvalGranted,
            summary: "Approval granted.",
            detail: combinedDetail.isEmpty ? nil : combinedDetail,
            visibility: .userVisible
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    private func awaitingApprovalDraftID(from thread: ExchangeThread) -> ExchangeMessageDraft.ID? {
        guard case .awaitingApproval(let st) = thread.state else { return nil }
        return st.draftID
    }

    private func matchFoundStatusForCoordinationHold(
        thread: ExchangeThread,
        now: Date
    ) throws -> ExchangeState.MatchFoundStatus {
        let count = max(1, thread.candidateCounterpartyIDs.count)
        let summary =
            thread.visibleSummary.flatMap {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            }
            ?? "Coordination continues on this path."

        guard let cp = thread.selectedCounterpartyID.flatMap({
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }) else {
            throw ExchangeThreadEngineError.invalidTransition("Missing selected counterparty for coordination hold.")
        }

        let profile = thread.selectedPublicProfileID.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        let offer = thread.selectedOfferID.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        guard profile != nil || offer != nil else {
            throw ExchangeThreadEngineError.invalidTransition("Missing profile or offer anchor for coordination hold.")
        }

        return ExchangeState.MatchFoundStatus(
            foundAt: now,
            candidateCount: count,
            summary: summary,
            nextStep: "Unify needs your input before the next external reply can be sent.",
            selectedCounterpartyID: cp,
            selectedPublicProfileID: profile,
            selectedOfferID: offer
        )
    }

    public func markDraftPrepared(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft,
        now: Date = Date()
    ) throws -> ThreadMutation {
        var updated = thread

        if updated.approval == nil {
            updated = updated.settingApproval(
                .init(
                    status: .notRequired,
                    requestedAt: nil,
                    decidedAt: now,
                    requestedDraftID: draft.id,
                    note: "This draft does not require explicit approval."
                ),
                at: now
            )
        } else if updated.approval?.requestedDraftID == nil {
            updated = updated.settingApproval(
                .init(
                    status: updated.approval?.status ?? .notRequired,
                    requestedAt: updated.approval?.requestedAt,
                    decidedAt: updated.approval?.decidedAt ?? now,
                    requestedDraftID: draft.id,
                    note: updated.approval?.note
                ),
                at: now
            )
        }

        updated = updated.settingDelivery(
            .init(
                status: .readyToSend,
                lastAttemptAt: nil,
                lastConfirmedSendAt: nil,
                externalReference: nil,
                note: "Draft prepared. Ready to queue for outbound send."
            ),
            at: now
        )

        let nextState = ExchangeState.draftReady(
            .init(
                preparedAt: now,
                summary: "Draft prepared.",
                draftID: draft.id
            )
        )

        let trace = (updated.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .appendingStep(
                key: "preparing_outreach_draft",
                title: "Preparing outreach draft",
                detail: draft.subject ?? "Drafting outbound message",
                activating: true,
                at: now
            )
            .markingComplete(
                key: "preparing_outreach_draft",
                headline: "Draft prepared.",
                at: now
            )

        updated = try transition(
            thread: updated.settingWorkTrace(trace, at: now),
            to: nextState,
            trigger: .draftPrepared,
            now: now,
            visibleSummary: "Draft prepared."
        )

        let turn = ExchangeTurn.draftPrepared(
            threadID: updated.id,
            summary: "Draft prepared.",
            detail: draft.subject ?? draft.body,
            createdAt: now
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func replacePreparedDraft(
        thread: ExchangeThread,
        draft: ExchangeMessageDraft,
        now: Date = Date()
    ) throws -> ThreadMutation {
        guard case .draftReady = thread.state else {
            throw ExchangeThreadEngineError.invalidTransition(
                "replacePreparedDraft requires thread to already be in draftReady."
            )
        }

        var updated = thread

        if updated.approval == nil {
            updated = updated.settingApproval(
                .init(
                    status: .notRequired,
                    requestedAt: nil,
                    decidedAt: now,
                    requestedDraftID: draft.id,
                    note: "This draft does not require explicit approval."
                ),
                at: now
            )
        } else {
            updated = updated.settingApproval(
                .init(
                    status: updated.approval?.status ?? .notRequired,
                    requestedAt: updated.approval?.requestedAt,
                    decidedAt: updated.approval?.decidedAt ?? now,
                    requestedDraftID: draft.id,
                    note: updated.approval?.note
                ),
                at: now
            )
        }

        updated = updated.settingDelivery(
            .init(
                status: .readyToSend,
                lastAttemptAt: nil,
                lastConfirmedSendAt: nil,
                externalReference: nil,
                note: "Draft prepared. Ready to queue for outbound send."
            ),
            at: now
        )

        let trace = (updated.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .appendingStep(
                key: "preparing_outreach_draft",
                title: "Preparing outreach draft",
                detail: draft.subject ?? "Drafting outbound message",
                activating: true,
                at: now
            )
            .markingComplete(
                key: "preparing_outreach_draft",
                headline: "Draft prepared.",
                at: now
            )

        updated = updated
            .settingWorkTrace(trace, at: now)
            .withUpdatedState(
                .draftReady(
                    .init(
                        preparedAt: now,
                        summary: "Draft prepared.",
                        draftID: draft.id
                    )
                ),
                at: now,
                visibleSummary: "Draft prepared."
            )

        let turn = ExchangeTurn.draftPrepared(
            threadID: updated.id,
            summary: "Draft prepared.",
            detail: draft.subject ?? draft.body,
            createdAt: now
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func rejectApproval(
        thread: ExchangeThread,
        approval: ExchangeApproval,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let summary = approval.decisionNote ?? "The proposed action was not approved."

        let nextState = ExchangeState.declined(
            .init(
                declinedAt: now,
                reasonSummary: summary
            )
        )

        var updated = thread.settingApproval(
            .init(
                status: .rejected,
                requestedAt: approval.createdAt,
                decidedAt: approval.decidedAt ?? now,
                requestedDraftID: approval.draftID,
                note: approval.decisionNote
            ),
            at: now
        )

        updated = updated.settingDelivery(
            .init(
                status: .notStarted,
                note: "Approval rejected. No outbound action will be taken."
            ),
            at: now
        )

        let trace = (updated.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingBlocked(
                headline: summary,
                at: now
            )

        updated = updated.settingWorkTrace(trace, at: now)

        updated = try transition(
            thread: updated,
            to: nextState,
            trigger: .approvalRejected,
            now: now,
            visibleSummary: summary
        )

        updated = updated.settingOutcome(
            .init(
                status: .declined,
                summary: summary,
                recordedAt: now
            ),
            at: now
        )

        let turn = ExchangeTurn(
            threadID: updated.id,
            createdAt: now,
            actor: .user,
            kind: .approvalRejected,
            summary: "Approval rejected.",
            detail: approval.decisionNote,
            visibility: .userVisible
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func markSendConfirmed(
        thread: ExchangeThread,
        externalReference: String?,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let nextState = ExchangeState.awaitingResponse(
            .init(
                since: now,
                lastOutboundAt: now,
                followUpSuggestedAt: nil
            )
        )

        let trace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                key: "ready_to_send",
                headline: "Outreach sent.",
                at: now
            )
            .appendingStep(
                key: "waiting_for_reply",
                title: "Waiting for reply",
                detail: nil,
                activating: true,
                at: now
            )

        var updated = thread.settingWorkTrace(trace, at: now)

        updated = updated.settingDelivery(
            .init(
                status: .sent,
                lastAttemptAt: now,
                lastConfirmedSendAt: now,
                externalReference: externalReference,
                note: "Outbound action confirmed."
            ),
            at: now
        )

        updated = try transition(
            thread: updated,
            to: nextState,
            trigger: .sendConfirmed,
            now: now,
            visibleSummary: "Message sent. Waiting for a response."
        )

        let turn = ExchangeTurn.sendConfirmed(
            threadID: updated.id,
            summary: "Outbound coordination confirmed.",
            externalReference: externalReference,
            createdAt: now
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func markFailure(
        thread: ExchangeThread,
        failure: ExchangeFailure,
        mappedState: ExchangeState,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let trigger = triggerForFailure(failure: failure, mappedState: mappedState)

        exchangeThreadDbg(
            "[ExchangeThreadEngine] markFailure " +
            "thread=\(thread.id.uuidString) " +
            "from=\(thread.state.phaseTitle) " +
            "to=\(mappedState.phaseTitle) " +
            "trigger=\(trigger) " +
            "failureKind=\(failure.kind) " +
            "failureSummary=\(failure.summary)"
        )

        var workingThread = thread

        switch failure.kind {
        case .deliveryFailure:
            workingThread = workingThread.settingDelivery(
                .init(
                    status: .failed,
                    lastAttemptAt: now,
                    lastConfirmedSendAt: thread.delivery?.lastConfirmedSendAt,
                    externalReference: thread.delivery?.externalReference,
                    note: failure.summary
                ),
                at: now
            )

        case .understandingFailure, .discoveryFailure, .fitFailure, .negotiationFailure, .systemFailure:
            break
        }

        workingThread = workingThread.settingWorkTrace(
            (workingThread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
                .markingBlocked(headline: failure.summary, at: now),
            at: now
        )

        var updated = try transition(
            thread: workingThread,
            to: mappedState,
            trigger: trigger,
            now: now,
            failure: failure,
            visibleSummary: failure.summary
        )

        updated = updated.settingOutcome(
            outcomeSnapshot(for: failure, mappedState: mappedState, at: now),
            at: now
        )

        let turn = failureTurn(
            threadID: updated.id,
            failure: failure,
            mappedState: mappedState,
            createdAt: now
        )

        exchangeThreadDbg(
            "[ExchangeThreadEngine] markFailure DONE " +
            "thread=\(updated.id.uuidString) " +
            "to=\(updated.state.phaseTitle)"
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }

    public func markResolved(
        thread: ExchangeThread,
        summary: String,
        now: Date = Date()
    ) throws -> ThreadMutation {
        let nextState = ExchangeState.resolved(
            .init(
                resolvedAt: now,
                summary: summary
            )
        )

        let trace = (thread.workTrace ?? .starter(headline: "Starting secretary work.", at: now))
            .markingComplete(
                headline: summary,
                at: now
            )

        var updated = try transition(
            thread: thread.settingWorkTrace(trace, at: now),
            to: nextState,
            trigger: .resolutionRecorded,
            now: now,
            visibleSummary: summary
        )

        updated = updated.settingOutcome(
            .init(status: .resolved, summary: summary, recordedAt: now),
            at: now
        )

        updated = updated.clearingFailure(at: now, keepOutcome: true)

        let turn = ExchangeTurn(
            threadID: updated.id,
            createdAt: now,
            actor: .system,
            kind: .threadResolved,
            summary: summary,
            visibility: .userVisible
        )

        return ThreadMutation(thread: updated, turns: [turn])
    }
}

public extension ExchangeThreadEngine {
    struct ThreadMutation: Sendable, Hashable {
        public var thread: ExchangeThread
        public var turns: [ExchangeTurn]

        public init(thread: ExchangeThread, turns: [ExchangeTurn]) {
            self.thread = thread
            self.turns = turns
        }
    }

    struct ChildCoordinationThreadCreation: Sendable, Hashable {
        public var thread: ExchangeThread
        public var turns: [ExchangeTurn]
        public var childMatch: ExchangeMatch
        public var sourceMatchID: ExchangeMatch.ID
        public var sourceRank: Int

        public init(
            thread: ExchangeThread,
            turns: [ExchangeTurn],
            childMatch: ExchangeMatch,
            sourceMatchID: ExchangeMatch.ID,
            sourceRank: Int
        ) {
            self.thread = thread
            self.turns = turns
            self.childMatch = childMatch
            self.sourceMatchID = sourceMatchID
            self.sourceRank = sourceRank
        }
    }
}

private extension ExchangeThreadEngine {
    static let coordinationLaneMetadataKeys: [String] = [
        ExchangeThreadLaneResolver.metadataKey,
        ExchangeThreadLaneResolver.conversationSurfaceMetadataKey,
        ExchangeThread.originalRequesterTextMetadataKey,
        "direct_message_thread",
        "contact_request_thread",
    ]

    static func mergeCoordinationLaneMetadata(
        from umbrellaThread: ExchangeThread,
        onto metadata: inout [String: String]
    ) {
        for key in coordinationLaneMetadataKeys {
            guard let value = umbrellaThread.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                continue
            }
            metadata[key] = value
        }
    }

    static func childCoordinationSummary(
        sourceMatch: ExchangeMatch,
        override: String?
    ) -> String {
        let trimmedOverride = override?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedOverride.isEmpty {
            return trimmedOverride
        }

        let trimmedRecommendation = sourceMatch.recommendation?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedRecommendation.isEmpty {
            return trimmedRecommendation
        }

        return "Coordinating with selected provider."
    }
}

public enum ExchangeThreadEngineError: Error, Sendable, Hashable, LocalizedError {
    case invalidTransition(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let message):
            return message
        }
    }
}

private extension ExchangeThreadEngine {
    func transition(
        thread: ExchangeThread,
        to newState: ExchangeState,
        trigger: ExchangeTransition.Trigger,
        now: Date,
        failure: ExchangeFailure? = nil,
        visibleSummary: String? = nil
    ) throws -> ExchangeThread {
        exchangeThreadDbg(
            "[ExchangeThreadEngine] transition ATTEMPT " +
            "thread=\(thread.id.uuidString) " +
            "from=\(thread.state.phaseTitle) " +
            "to=\(newState.phaseTitle) " +
            "trigger=\(trigger) " +
            "hasFailure=\(failure != nil) " +
            "visibleSummary=\(visibleSummary ?? "-")"
        )

        switch stateMachine.applyTransition(
            thread: thread,
            to: newState,
            trigger: trigger,
            at: now,
            failure: failure,
            visibleSummary: visibleSummary
        ) {
        case .success(let updated):
            exchangeThreadDbg(
                "[ExchangeThreadEngine] transition SUCCESS " +
                "thread=\(updated.id.uuidString) " +
                "from=\(thread.state.phaseTitle) " +
                "to=\(updated.state.phaseTitle) " +
                "trigger=\(trigger)"
            )
            return updated
        case .failure(let error):
            exchangeThreadDbg(
                "[ExchangeThreadEngine] transition FAILURE " +
                "thread=\(thread.id.uuidString) " +
                "from=\(thread.state.phaseTitle) " +
                "to=\(newState.phaseTitle) " +
                "trigger=\(trigger) " +
                "error=\(error.debugDescription)"
            )
            throw ExchangeThreadEngineError.invalidTransition(error.debugDescription)
        }
    }

    func clarificationQuestion(from failure: ExchangeFailure) -> String {
        if case .clarify(let question) = failure.recommendedNextStep {
            let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return failure.recommendedNextStep.summaryLine
    }

    func nextAttemptNumber(from thread: ExchangeThread) -> Int {
        if case .sending(let status) = thread.state {
            return max(1, status.attemptNumber + 1)
        }
        if thread.delivery?.status == .failed {
            return 2
        }
        return 1
    }

    func triggerForFailure(
        failure: ExchangeFailure,
        mappedState: ExchangeState
    ) -> ExchangeTransition.Trigger {
        switch (failure.kind, mappedState) {
        case (.understandingFailure, .needsClarification):
            return .clarificationRequired

        case (.discoveryFailure, .noViableMatch):
            return .noMatchesDetected

        case (.fitFailure, .matchCandidatesWeak):
            return .weakMatchesDetected

        case (.deliveryFailure, .blockedByDeliveryFailure):
            return .deliveryFailureDetected

        case (.negotiationFailure, .stalled):
            return .stallDetected

        case (.negotiationFailure, .declined):
            return .declineObserved

        case (.systemFailure, .blockedBySystemFailure):
            return .systemFailureDetected

        default:
            switch mappedState {
            case .needsClarification:
                return .clarificationRequired

            case .matchFound:
                return .candidateAccepted

            case .matchCandidatesWeak:
                return .weakMatchesDetected

            case .noViableMatch:
                return .noMatchesDetected

            case .blockedByDeliveryFailure:
                return .deliveryFailureDetected

            case .draftReady:
                return .draftPrepared

            case .stalled:
                return .stallDetected

            case .declined:
                return .declineObserved

            case .blockedBySystemFailure:
                return .systemFailureDetected

            case .resolved:
                return .resolutionRecorded

            case .searching:
                return .retryRequested

            case .awaitingApproval:
                return .approvalRequested

            case .sending:
                return .retryRequested

            case .awaitingResponse:
                return .sendConfirmed

            case .drafting:
                return .manualRecovery
            }
        }
    }

    func failureTurn(
        threadID: ExchangeThread.ID,
        failure: ExchangeFailure,
        mappedState: ExchangeState,
        createdAt: Date
    ) -> ExchangeTurn {
        switch failure.kind {
        case .deliveryFailure:
            return .deliveryFailed(threadID: threadID, failure: failure, createdAt: createdAt)

        case .systemFailure:
            return .systemError(threadID: threadID, failure: failure, createdAt: createdAt)

        case .understandingFailure:
            return .clarificationAsked(
                threadID: threadID,
                question: clarificationQuestion(from: failure),
                createdAt: createdAt
            )

        case .discoveryFailure:
            return .noViableMatchObserved(
                threadID: threadID,
                summary: failure.summary,
                detail: failure.recommendedNextStep.summaryLine,
                createdAt: createdAt
            )

        case .fitFailure:
            return .weakMatchesObserved(
                threadID: threadID,
                summary: failure.summary,
                detail: failure.recommendedNextStep.summaryLine,
                createdAt: createdAt
            )

        case .negotiationFailure:
            if case .declined = mappedState {
                return ExchangeTurn(
                    threadID: threadID,
                    createdAt: createdAt,
                    actor: .system,
                    kind: .threadDeclined,
                    summary: failure.summary,
                    detail: failure.visibleExplanation,
                    visibility: .userVisible,
                    failure: failure
                )
            }

            return ExchangeTurn(
                threadID: threadID,
                createdAt: createdAt,
                actor: .system,
                kind: .negotiationFailed,
                summary: failure.summary,
                detail: failure.visibleExplanation,
                visibility: .userVisible,
                failure: failure
            )
        }
    }

    func outcomeSnapshot(
        for failure: ExchangeFailure,
        mappedState: ExchangeState,
        at date: Date
    ) -> ExchangeThread.OutcomeSnapshot {
        let status: ExchangeThread.OutcomeSnapshot.Status

        switch mappedState {
        case .matchCandidatesWeak, .noViableMatch:
            status = .noViableMatch

        case .declined:
            status = .declined

        case .stalled:
            status = .stalled

        case .resolved:
            status = .resolved

        case .blockedByDeliveryFailure, .blockedBySystemFailure:
            status = .failedLegibly

        case .drafting,
             .needsClarification,
             .searching,
             .matchFound,
             .draftReady,
             .awaitingApproval,
             .sending,
             .awaitingResponse:
            status = .failedLegibly
        }

        return .init(
            status: status,
            summary: failure.summary,
            recordedAt: date
        )
    }

    func normalizedIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for rawID in ids {
            let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            output.append(trimmed)
        }

        return output
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ExchangeThread {
    var stateKey: ExchangeTransition.ExchangeStateKey {
        .init(state)
    }
}
