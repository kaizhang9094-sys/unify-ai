import Foundation

#if DEBUG
@inline(__always)
private func exchangeStateDbg(_ message: @autoclosure () -> String) {
    Swift.print(message())
}
#else
@inline(__always)
private func exchangeStateDbg(_ message: @autoclosure () -> String) { }
#endif

/// Central state transition validator for Exchange.
///
/// This is the single source of truth for whether a thread may move from one
/// state to another under a given trigger.
///
/// Keep orchestration code out of here. This type validates movement; it does
/// not perform discovery, send messages, or write storage.
public struct ExchangeStateMachine: Sendable {
    public init() {}

    public func validateTransition(
        thread: ExchangeThread,
        to newState: ExchangeState,
        trigger: ExchangeTransition.Trigger
    ) -> ValidationResult {
        let currentKey = ExchangeTransition.ExchangeStateKey(thread.state)
        let newKey = ExchangeTransition.ExchangeStateKey(newState)

        exchangeStateDbg(
            "[ExchangeStateMachine] validateTransition " +
            "thread=\(thread.id.uuidString) " +
            "from=\(currentKey.rawValue) " +
            "to=\(newKey.rawValue) " +
            "trigger=\(trigger.rawValue)"
        )

        guard ExchangeTransition.isLegal(from: thread.state, to: newState, trigger: trigger) else {
            let reason = "Illegal transition from \(currentKey.rawValue) to \(newKey.rawValue) using trigger \(trigger.rawValue)."
            exchangeStateDbg(
                "[ExchangeStateMachine] validateTransition LEGALITY_FAIL " +
                "thread=\(thread.id.uuidString) " +
                "reason=\(reason)"
            )
            return .invalid(reason: reason)
        }

        let result = semanticValidation(
            thread: thread,
            to: newState,
            trigger: trigger
        )

        switch result {
        case .valid:
            exchangeStateDbg(
                "[ExchangeStateMachine] validateTransition OK " +
                "thread=\(thread.id.uuidString) " +
                "from=\(currentKey.rawValue) " +
                "to=\(newKey.rawValue) " +
                "trigger=\(trigger.rawValue)"
            )

        case .invalid(let reason):
            exchangeStateDbg(
                "[ExchangeStateMachine] validateTransition SEMANTIC_FAIL " +
                "thread=\(thread.id.uuidString) " +
                "from=\(currentKey.rawValue) " +
                "to=\(newKey.rawValue) " +
                "trigger=\(trigger.rawValue) " +
                "reason=\(reason)"
            )
        }

        return result
    }

    public func applyTransition(
        thread: ExchangeThread,
        to newState: ExchangeState,
        trigger: ExchangeTransition.Trigger,
        at date: Date = Date(),
        failure: ExchangeFailure? = nil,
        visibleSummary: String? = nil
    ) -> Result<ExchangeThread, StateMachineError> {
        let fromKey = ExchangeTransition.ExchangeStateKey(thread.state)
        let toKey = ExchangeTransition.ExchangeStateKey(newState)

        exchangeStateDbg(
            "[ExchangeStateMachine] applyTransition ATTEMPT " +
            "thread=\(thread.id.uuidString) " +
            "from=\(fromKey.rawValue) " +
            "to=\(toKey.rawValue) " +
            "trigger=\(trigger.rawValue) " +
            "hasFailure=\(failure != nil) " +
            "visibleSummary=\(visibleSummary ?? "-")"
        )

        switch validateTransition(thread: thread, to: newState, trigger: trigger) {
        case .valid:
            var next = thread.withUpdatedState(
                newState,
                at: date,
                failure: failure,
                visibleSummary: visibleSummary
            )

            if isRecoveryTransition(trigger: trigger) {
                exchangeStateDbg(
                    "[ExchangeStateMachine] applyTransition RECOVERY_CLEAR_FAILURE " +
                    "thread=\(thread.id.uuidString) " +
                    "trigger=\(trigger.rawValue)"
                )
                next = next.clearingFailure(at: date, keepOutcome: false)
            }

            exchangeStateDbg(
                "[ExchangeStateMachine] applyTransition SUCCESS " +
                "thread=\(next.id.uuidString) " +
                "from=\(fromKey.rawValue) " +
                "to=\(toKey.rawValue) " +
                "trigger=\(trigger.rawValue)"
            )

            return .success(next)

        case .invalid(let reason):
            exchangeStateDbg(
                "[ExchangeStateMachine] applyTransition FAILURE " +
                "thread=\(thread.id.uuidString) " +
                "from=\(fromKey.rawValue) " +
                "to=\(toKey.rawValue) " +
                "trigger=\(trigger.rawValue) " +
                "reason=\(reason)"
            )

            return .failure(
                .invalidTransition(
                    from: fromKey,
                    to: toKey,
                    trigger: trigger,
                    reason: reason
                )
            )
        }
    }
}

public extension ExchangeStateMachine {
    enum ValidationResult: Sendable, Hashable {
        case valid
        case invalid(reason: String)
    }

    enum StateMachineError: Error, Sendable, Hashable {
        case invalidTransition(
            from: ExchangeTransition.ExchangeStateKey,
            to: ExchangeTransition.ExchangeStateKey,
            trigger: ExchangeTransition.Trigger,
            reason: String
        )

        public var debugDescription: String {
            switch self {
            case let .invalidTransition(from, to, trigger, reason):
                return "Invalid transition \(from.rawValue) -> \(to.rawValue) via \(trigger.rawValue): \(reason)"
            }
        }
    }
}

private extension ExchangeStateMachine {
    func semanticValidation(
        thread: ExchangeThread,
        to newState: ExchangeState,
        trigger: ExchangeTransition.Trigger
    ) -> ValidationResult {
        switch newState {
        case .drafting:
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation drafting OK " +
                "thread=\(thread.id.uuidString)"
            )
            return .valid

        case .needsClarification(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation needsClarification " +
                "thread=\(thread.id.uuidString) " +
                "question=\(status.question) " +
                "attempts=\(status.attempts)"
            )

            guard !status.question.trimmed.isEmpty else {
                return .invalid(reason: "Clarification state requires a non-empty question.")
            }

            guard status.attempts >= 1 else {
                return .invalid(reason: "Clarification attempts must be at least 1.")
            }

            return .valid

        case .searching(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation searching " +
                "thread=\(thread.id.uuidString) " +
                "query=\(status.querySummary ?? "-") " +
                "scope=\(status.scopeSummary ?? "-") " +
                "candidateCount=\(status.candidateCount) " +
                "requiresClarificationBeforeAction=\(thread.intent.requiresClarificationBeforeAction) " +
                "primarySearchText=\(thread.primarySearchText) " +
                "selectedCounterpartyID=\(thread.selectedCounterpartyID ?? "-") " +
                "selectedPublicProfileID=\(thread.selectedPublicProfileID ?? "-") " +
                "selectedOfferID=\(thread.selectedOfferID ?? "-") " +
                "trigger=\(trigger.rawValue)"
            )

            if thread.intent.requiresClarificationBeforeAction,
               trigger != .clarificationAnswered,
               trigger != .retryRequested {
                let hasSearchableIntent =
                    !thread.primarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                exchangeStateDbg(
                    "[ExchangeStateMachine] semanticValidation searching clarificationGate " +
                    "thread=\(thread.id.uuidString) " +
                    "hasSearchableIntent=\(hasSearchableIntent) " +
                    "trigger=\(trigger.rawValue)"
                )

                if !hasSearchableIntent {
                    return .invalid(reason: "Thread still requires clarification before search can begin.")
                }
            }

            guard status.candidateCount >= 0 else {
                return .invalid(reason: "Searching state cannot have a negative candidate count.")
            }

            return .valid

        case .matchFound(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation matchFound " +
                "thread=\(thread.id.uuidString) " +
                "candidateCount=\(status.candidateCount) " +
                "summary=\(status.summary) " +
                "selectedCounterpartyID=\(status.selectedCounterpartyID ?? "-") " +
                "selectedPublicProfileID=\(status.selectedPublicProfileID ?? "-") " +
                "selectedOfferID=\(status.selectedOfferID ?? "-") " +
                "threadSelectedCounterpartyID=\(thread.selectedCounterpartyID ?? "-") " +
                "threadSelectedPublicProfileID=\(thread.selectedPublicProfileID ?? "-") " +
                "threadSelectedOfferID=\(thread.selectedOfferID ?? "-") " +
                "trigger=\(trigger.rawValue)"
            )

            guard status.candidateCount >= 1 else {
                return .invalid(reason: "Match found state requires at least one candidate.")
            }

            guard !status.summary.trimmed.isEmpty else {
                return .invalid(reason: "Match found state requires a non-empty summary.")
            }

            let statusSelectedCounterpartyID = status.selectedCounterpartyID?.trimmed.nilIfBlank
            let threadSelectedCounterpartyID = thread.selectedCounterpartyID?.trimmed.nilIfBlank
            let statusSelectedProfileID = status.selectedPublicProfileID?.trimmed.nilIfBlank
            let threadSelectedProfileID = thread.selectedPublicProfileID?.trimmed.nilIfBlank
            let statusSelectedOfferID = status.selectedOfferID?.trimmed.nilIfBlank
            let threadSelectedOfferID = thread.selectedOfferID?.trimmed.nilIfBlank

            let selectedCounterpartyID = statusSelectedCounterpartyID ?? threadSelectedCounterpartyID
            let selectedProfileID = statusSelectedProfileID ?? threadSelectedProfileID
            let selectedOfferID = statusSelectedOfferID ?? threadSelectedOfferID

            guard selectedCounterpartyID != nil else {
                return .invalid(reason: "Match found state requires a selected counterparty id.")
            }

            let hasSurfaceAnchor =
                selectedProfileID != nil ||
                selectedOfferID != nil

            guard hasSurfaceAnchor else {
                return .invalid(reason: "Match found state requires a selected public profile id or selected offer id.")
            }

            if !thread.candidateCounterpartyIDs.isEmpty,
               let selectedCounterpartyID,
               !thread.candidateCounterpartyIDs.contains(selectedCounterpartyID) {
                return .invalid(reason: "Selected counterparty must be included in active candidate ids.")
            }

            return .valid

        case .matchCandidatesWeak(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation weakMatches " +
                "thread=\(thread.id.uuidString) " +
                "candidateCount=\(status.candidateCount) " +
                "explanation=\(status.explanation)"
            )

            guard !status.explanation.trimmed.isEmpty else {
                return .invalid(reason: "Weak matches state requires an explanation.")
            }

            guard status.candidateCount >= 1 else {
                return .invalid(reason: "Weak matches state requires at least one candidate.")
            }

            guard !thread.candidateCounterpartyIDs.isEmpty else {
                return .invalid(reason: "Weak matches state requires active candidate ids on the thread.")
            }

            return .valid

        case .noViableMatch(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation noViableMatch " +
                "thread=\(thread.id.uuidString) " +
                "explanation=\(status.explanation) " +
                "candidateIDs=\(thread.candidateCounterpartyIDs.count) " +
                "trigger=\(trigger.rawValue)"
            )

            guard !status.explanation.trimmed.isEmpty else {
                return .invalid(reason: "No viable match state requires an explanation.")
            }

            if !thread.candidateCounterpartyIDs.isEmpty && trigger == .noMatchesDetected {
                return .invalid(reason: "No viable match should not be entered while thread still carries active candidates.")
            }

            return .valid

        case .draftReady(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation draftReady " +
                "thread=\(thread.id.uuidString) " +
                "summary=\(status.summary) " +
                "draftID=\(status.draftID?.uuidString ?? "-")"
            )

            guard !status.summary.trimmed.isEmpty else {
                return .invalid(reason: "Draft ready state requires a non-empty summary.")
            }

            guard status.draftID != nil else {
                return .invalid(reason: "Draft ready state requires a draft id.")
            }

            return .valid

        case .awaitingApproval(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation awaitingApproval " +
                "thread=\(thread.id.uuidString) " +
                "summary=\(status.summary) " +
                "draftID=\(status.draftID?.uuidString ?? "-") " +
                "expiresAt=\(String(describing: status.expiresAt))"
            )

            guard !status.summary.trimmed.isEmpty else {
                return .invalid(reason: "Awaiting approval requires a non-empty approval summary.")
            }

            guard status.draftID != nil else {
                return .invalid(reason: "Awaiting approval requires a draft id.")
            }

            if let expiresAt = status.expiresAt, expiresAt <= status.requestedAt {
                return .invalid(reason: "Approval expiration must be later than the request time.")
            }

            return .valid

        case .sending(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation sending " +
                "thread=\(thread.id.uuidString) " +
                "attemptNumber=\(status.attemptNumber) " +
                "approvalStatus=\(String(describing: thread.approval?.status)) " +
                "state=\(ExchangeTransition.ExchangeStateKey(thread.state).rawValue)"
            )

            switch thread.state {
            case .awaitingApproval:
                if let approval = thread.approval {
                    switch approval.status {
                    case .approved:
                        break
                    case .pending, .rejected, .expired, .notRequired:
                        return .invalid(reason: "Cannot send from awaitingApproval unless approval is granted.")
                    }
                } else {
                    return .invalid(reason: "Cannot send from awaitingApproval without approval state.")
                }

            default:
                if let approval = thread.approval {
                    switch approval.status {
                    case .pending, .rejected, .expired:
                        return .invalid(reason: "Cannot send while approval is not granted.")
                    case .approved, .notRequired:
                        break
                    }
                }
            }

            guard status.attemptNumber >= 1 else {
                return .invalid(reason: "Sending state requires attemptNumber >= 1.")
            }

            return .valid

        case .blockedByDeliveryFailure(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation blockedByDeliveryFailure " +
                "thread=\(thread.id.uuidString) " +
                "failureID=\(status.failureID.uuidString) " +
                "latestFailureID=\(thread.latestFailure?.id.uuidString ?? "-") " +
                "trigger=\(trigger.rawValue)"
            )

            guard status.failureID != UUID.zero else {
                return .invalid(reason: "Delivery failure state requires a real failure id.")
            }

            guard thread.latestFailure?.id == status.failureID || trigger == .deliveryFailureDetected else {
                return .invalid(reason: "Delivery failure state should reference the current delivery failure.")
            }

            return .valid

        case .awaitingResponse(let status):
            let externallyProgressed = isExternallyProgressed(thread: thread, trigger: trigger)

            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation awaitingResponse " +
                "thread=\(thread.id.uuidString) " +
                "since=\(status.since) " +
                "lastOutboundAt=\(String(describing: status.lastOutboundAt)) " +
                "externallyProgressed=\(externallyProgressed) " +
                "trigger=\(trigger.rawValue) " +
                "deliveryStatus=\(String(describing: thread.delivery?.status))"
            )

            guard externallyProgressed else {
                return .invalid(reason: "Cannot wait for a response before delivery is confirmed.")
            }

            if let lastOutboundAt = status.lastOutboundAt, lastOutboundAt > status.since {
                return .invalid(reason: "Awaiting response 'since' must not be earlier than last outbound confirmation.")
            }

            return .valid

        case .declined(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation declined " +
                "thread=\(thread.id.uuidString) " +
                "reason=\(status.reasonSummary ?? "-")"
            )

            if let reason = status.reasonSummary, reason.trimmed.isEmpty {
                return .invalid(reason: "Declined reason summary cannot be blank.")
            }

            return .valid

        case .stalled(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation stalled " +
                "thread=\(thread.id.uuidString) " +
                "reason=\(status.reasonSummary)"
            )

            guard !status.reasonSummary.trimmed.isEmpty else {
                return .invalid(reason: "Stalled state requires a reason summary.")
            }

            return .valid

        case .resolved(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation resolved " +
                "thread=\(thread.id.uuidString) " +
                "summary=\(status.summary)"
            )

            guard !status.summary.trimmed.isEmpty else {
                return .invalid(reason: "Resolved state requires a summary.")
            }

            return .valid

        case .blockedBySystemFailure(let status):
            exchangeStateDbg(
                "[ExchangeStateMachine] semanticValidation blockedBySystemFailure " +
                "thread=\(thread.id.uuidString) " +
                "failureID=\(status.failureID.uuidString) " +
                "latestFailureID=\(thread.latestFailure?.id.uuidString ?? "-") " +
                "trigger=\(trigger.rawValue)"
            )

            guard status.failureID != UUID.zero else {
                return .invalid(reason: "System failure state requires a real failure id.")
            }

            guard thread.latestFailure?.id == status.failureID || trigger == .systemFailureDetected else {
                return .invalid(reason: "System failure state should reference the current system failure.")
            }

            return .valid
        }
    }

    func isExternallyProgressed(
        thread: ExchangeThread,
        trigger: ExchangeTransition.Trigger
    ) -> Bool {
        if trigger == .sendConfirmed {
            exchangeStateDbg(
                "[ExchangeStateMachine] isExternallyProgressed true via trigger " +
                "thread=\(thread.id.uuidString)"
            )
            return true
        }

        if let delivery = thread.delivery {
            switch delivery.status {
            case .sent:
                exchangeStateDbg(
                    "[ExchangeStateMachine] isExternallyProgressed true via delivery.sent " +
                    "thread=\(thread.id.uuidString)"
                )
                return true

            case .notStarted, .pendingApproval, .readyToSend, .sending, .failed:
                break
            }
        }

        if let externalEffect = thread.latestFailure?.externalEffect,
           externalEffect.changedAnythingExternally {
            exchangeStateDbg(
                "[ExchangeStateMachine] isExternallyProgressed true via latestFailure.externalEffect " +
                "thread=\(thread.id.uuidString)"
            )
            return true
        }

        exchangeStateDbg(
            "[ExchangeStateMachine] isExternallyProgressed false " +
            "thread=\(thread.id.uuidString) " +
            "trigger=\(trigger.rawValue)"
        )
        return false
    }

    func isRecoveryTransition(trigger: ExchangeTransition.Trigger) -> Bool {
        switch trigger {
        case .manualRecovery, .clarificationAnswered:
            return true

        case .retryRequested,
             .clarificationRequired,
             .searchStarted,
             .weakMatchesDetected,
             .noMatchesDetected,
             .candidateAccepted,
             .draftPrepared,
             .approvalRequested,
             .approvalGranted,
             .approvalRejected,
             .approvalExpired,
             .sendConfirmed,
             .deliveryFailureDetected,
             .replyReceived,
             .followUpNeeded,
             .declineObserved,
             .stallDetected,
             .resolutionRecorded,
             .systemFailureDetected:
            return false
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension UUID {
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
