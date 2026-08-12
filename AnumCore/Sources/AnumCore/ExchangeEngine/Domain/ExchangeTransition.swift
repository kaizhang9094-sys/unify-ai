import Foundation

#if DEBUG
@inline(__always)
private func exchangeTransitionDbg(_ message: @autoclosure () -> String) {
    Swift.print(message())
}
#else
@inline(__always)
private func exchangeTransitionDbg(_ message: @autoclosure () -> String) { }
#endif

/// A single legal state transition in the exchange workflow.
///
/// Keep legality explicit here rather than scattering workflow rules across
/// orchestrators, stores, views, or transport code.
///
/// This type operates on state keys, not full ExchangeState payloads, because
/// legality is about phase shape, not associated-value contents.
public struct ExchangeTransition: Codable, Sendable, Hashable {
    public var from: ExchangeStateKey
    public var to: ExchangeStateKey
    public var trigger: Trigger
    public var note: String?

    public init(
        from: ExchangeStateKey,
        to: ExchangeStateKey,
        trigger: Trigger,
        note: String? = nil
    ) {
        self.from = from
        self.to = to
        self.trigger = trigger
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

public extension ExchangeTransition {
    enum Trigger: String, Codable, Sendable, CaseIterable, Hashable {
        case clarificationRequired
        case clarificationAnswered

        case searchStarted
        case weakMatchesDetected
        case noMatchesDetected
        case candidateAccepted

        case draftPrepared
        case approvalRequested
        case approvalGranted
        case approvalRejected
        case approvalExpired

        case sendConfirmed
        case deliveryFailureDetected

        case replyReceived
        case followUpNeeded
        case declineObserved
        case stallDetected
        case resolutionRecorded

        case systemFailureDetected
        case manualRecovery
        case retryRequested
    }

    enum ExchangeStateKey: String, Codable, Sendable, CaseIterable, Hashable {
        case drafting
        case needsClarification

        case searching
        case matchFound
        case matchCandidatesWeak
        case noViableMatch

        case draftReady
        case awaitingApproval
        case sending
        case blockedByDeliveryFailure

        case awaitingResponse
        case declined
        case stalled
        case resolved

        case blockedBySystemFailure
    }
}

public extension ExchangeTransition.ExchangeStateKey {
    init(_ state: ExchangeState) {
        switch state {
        case .drafting:
            self = .drafting

        case .needsClarification:
            self = .needsClarification

        case .searching:
            self = .searching

        case .matchFound:
            self = .matchFound

        case .matchCandidatesWeak:
            self = .matchCandidatesWeak

        case .noViableMatch:
            self = .noViableMatch

        case .draftReady:
            self = .draftReady

        case .awaitingApproval:
            self = .awaitingApproval

        case .sending:
            self = .sending

        case .blockedByDeliveryFailure:
            self = .blockedByDeliveryFailure

        case .awaitingResponse:
            self = .awaitingResponse

        case .declined:
            self = .declined

        case .stalled:
            self = .stalled

        case .resolved:
            self = .resolved

        case .blockedBySystemFailure:
            self = .blockedBySystemFailure
        }
    }
}

public extension ExchangeTransition {
    static let legalTransitions: Set<ExchangeTransition> = [
        // MARK: - Drafting

        .init(from: .drafting, to: .needsClarification, trigger: .clarificationRequired),
        .init(from: .drafting, to: .searching, trigger: .searchStarted),
        .init(from: .drafting, to: .draftReady, trigger: .draftPrepared),
        .init(from: .drafting, to: .awaitingApproval, trigger: .approvalRequested),
        .init(from: .drafting, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Needs clarification

        .init(from: .needsClarification, to: .searching, trigger: .clarificationAnswered),
        .init(from: .needsClarification, to: .draftReady, trigger: .draftPrepared),
        .init(from: .needsClarification, to: .awaitingApproval, trigger: .approvalRequested),
        .init(from: .needsClarification, to: .blockedBySystemFailure, trigger: .systemFailureDetected),
        .init(from: .needsClarification, to: .needsClarification, trigger: .clarificationRequired),

        // MARK: - Searching

        .init(from: .searching, to: .matchFound, trigger: .candidateAccepted),
        .init(from: .searching, to: .matchCandidatesWeak, trigger: .weakMatchesDetected),
        .init(from: .searching, to: .noViableMatch, trigger: .noMatchesDetected),
        .init(from: .searching, to: .draftReady, trigger: .draftPrepared),
        .init(from: .searching, to: .awaitingApproval, trigger: .approvalRequested),
        .init(from: .searching, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Match found

        // This is now the clean post-discovery review state.
        // UI "Continue on found path" should advance from here into draft/approval/second-half flow.
        .init(from: .matchFound, to: .draftReady, trigger: .draftPrepared),
        .init(from: .matchFound, to: .awaitingApproval, trigger: .approvalRequested),
        .init(from: .matchFound, to: .sending, trigger: .approvalGranted),

        // Allow search refinement/retry from a found path.
        .init(from: .matchFound, to: .searching, trigger: .retryRequested),
        .init(from: .matchFound, to: .matchCandidatesWeak, trigger: .weakMatchesDetected),
        .init(from: .matchFound, to: .noViableMatch, trigger: .noMatchesDetected),

        // Allow another selected candidate to replace the current found path.
        .init(from: .matchFound, to: .matchFound, trigger: .candidateAccepted),

        // Manual recovery / clarification / failures.
        .init(from: .matchFound, to: .drafting, trigger: .manualRecovery),
        .init(from: .matchFound, to: .needsClarification, trigger: .clarificationRequired),
        .init(from: .matchFound, to: .blockedByDeliveryFailure, trigger: .deliveryFailureDetected),
        .init(from: .matchFound, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Weak matches

        .init(from: .matchCandidatesWeak, to: .searching, trigger: .retryRequested),
        .init(from: .matchCandidatesWeak, to: .matchFound, trigger: .candidateAccepted),
        .init(from: .matchCandidatesWeak, to: .draftReady, trigger: .draftPrepared),
        .init(from: .matchCandidatesWeak, to: .awaitingApproval, trigger: .approvalRequested),
        .init(from: .matchCandidatesWeak, to: .noViableMatch, trigger: .noMatchesDetected),
        .init(from: .matchCandidatesWeak, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - No viable match

        .init(from: .noViableMatch, to: .searching, trigger: .retryRequested),
        .init(from: .noViableMatch, to: .resolved, trigger: .resolutionRecorded),
        .init(from: .noViableMatch, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Draft ready

        .init(from: .draftReady, to: .awaitingApproval, trigger: .approvalRequested),
        .init(from: .draftReady, to: .sending, trigger: .approvalGranted),
        .init(from: .draftReady, to: .searching, trigger: .retryRequested),
        .init(from: .draftReady, to: .matchFound, trigger: .candidateAccepted),
        .init(from: .draftReady, to: .drafting, trigger: .manualRecovery),
        .init(from: .draftReady, to: .needsClarification, trigger: .clarificationRequired),
        .init(from: .draftReady, to: .blockedByDeliveryFailure, trigger: .deliveryFailureDetected),
        .init(from: .draftReady, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Awaiting approval

        .init(from: .awaitingApproval, to: .sending, trigger: .approvalGranted),
        /// Approval recorded, but outbound cannot enter the send pipeline yet (policy / routing / draft).
        .init(from: .awaitingApproval, to: .matchFound, trigger: .approvalGranted),
        .init(from: .awaitingApproval, to: .draftReady, trigger: .approvalGranted),
        .init(from: .awaitingApproval, to: .declined, trigger: .approvalRejected),
        .init(from: .awaitingApproval, to: .stalled, trigger: .approvalExpired),
        .init(from: .awaitingApproval, to: .awaitingApproval, trigger: .approvalRequested),
        .init(from: .awaitingApproval, to: .searching, trigger: .retryRequested),
        .init(from: .awaitingApproval, to: .matchFound, trigger: .candidateAccepted),
        .init(from: .awaitingApproval, to: .drafting, trigger: .manualRecovery),
        .init(from: .awaitingApproval, to: .needsClarification, trigger: .clarificationRequired),
        .init(from: .awaitingApproval, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Sending

        .init(from: .sending, to: .awaitingResponse, trigger: .sendConfirmed),
        .init(from: .sending, to: .blockedByDeliveryFailure, trigger: .deliveryFailureDetected),
        .init(from: .sending, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Delivery failure

        .init(from: .blockedByDeliveryFailure, to: .sending, trigger: .retryRequested),
        .init(from: .blockedByDeliveryFailure, to: .searching, trigger: .retryRequested),
        .init(from: .blockedByDeliveryFailure, to: .matchFound, trigger: .candidateAccepted),
        .init(from: .blockedByDeliveryFailure, to: .draftReady, trigger: .draftPrepared),
        .init(from: .blockedByDeliveryFailure, to: .awaitingApproval, trigger: .approvalRequested),
        .init(from: .blockedByDeliveryFailure, to: .stalled, trigger: .stallDetected),
        .init(from: .blockedByDeliveryFailure, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Awaiting response

        // A user may send a follow-up while already waiting for a reply.
        // The send path uses the same approved-outbound trigger as other user-approved sends.
        .init(from: .awaitingResponse, to: .sending, trigger: .approvalGranted),
        .init(from: .awaitingResponse, to: .draftReady, trigger: .followUpNeeded),
        .init(from: .awaitingResponse, to: .resolved, trigger: .replyReceived),
        .init(from: .awaitingResponse, to: .resolved, trigger: .resolutionRecorded),
        .init(from: .awaitingResponse, to: .declined, trigger: .declineObserved),
        .init(from: .awaitingResponse, to: .stalled, trigger: .stallDetected),
        .init(from: .awaitingResponse, to: .blockedByDeliveryFailure, trigger: .deliveryFailureDetected),
        .init(from: .awaitingResponse, to: .searching, trigger: .retryRequested),
        .init(from: .awaitingResponse, to: .matchFound, trigger: .candidateAccepted),
        .init(from: .awaitingResponse, to: .drafting, trigger: .manualRecovery),
        .init(from: .awaitingResponse, to: .needsClarification, trigger: .clarificationRequired),
        .init(from: .awaitingResponse, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Declined

        .init(from: .declined, to: .searching, trigger: .retryRequested),
        .init(from: .declined, to: .matchFound, trigger: .candidateAccepted),
        .init(from: .declined, to: .resolved, trigger: .resolutionRecorded),
        .init(from: .declined, to: .drafting, trigger: .manualRecovery),
        .init(from: .declined, to: .needsClarification, trigger: .clarificationRequired),
        .init(from: .declined, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Stalled

        .init(from: .stalled, to: .searching, trigger: .retryRequested),
        .init(from: .stalled, to: .matchFound, trigger: .candidateAccepted),
        .init(from: .stalled, to: .sending, trigger: .retryRequested),
        .init(from: .stalled, to: .draftReady, trigger: .draftPrepared),
        .init(from: .stalled, to: .awaitingApproval, trigger: .approvalRequested),
        .init(from: .stalled, to: .resolved, trigger: .resolutionRecorded),
        .init(from: .stalled, to: .drafting, trigger: .manualRecovery),
        .init(from: .stalled, to: .needsClarification, trigger: .clarificationRequired),
        .init(from: .stalled, to: .blockedBySystemFailure, trigger: .systemFailureDetected),

        // MARK: - Resolved

        .init(from: .resolved, to: .resolved, trigger: .resolutionRecorded),

        // MARK: - System failure

        .init(from: .blockedBySystemFailure, to: .drafting, trigger: .manualRecovery),
        .init(from: .blockedBySystemFailure, to: .searching, trigger: .manualRecovery),
        .init(from: .blockedBySystemFailure, to: .matchFound, trigger: .manualRecovery),
        .init(from: .blockedBySystemFailure, to: .draftReady, trigger: .manualRecovery),
        .init(from: .blockedBySystemFailure, to: .awaitingApproval, trigger: .manualRecovery),
        .init(from: .blockedBySystemFailure, to: .resolved, trigger: .resolutionRecorded)
    ]

    static func isLegal(
        from current: ExchangeState,
        to proposed: ExchangeState,
        trigger: Trigger
    ) -> Bool {
        let fromKey = ExchangeStateKey(current)
        let toKey = ExchangeStateKey(proposed)

        let transition = ExchangeTransition(
            from: fromKey,
            to: toKey,
            trigger: trigger
        )

        let isLegal = legalTransitions.contains(transition)

        exchangeTransitionDbg(
            "[ExchangeTransition] isLegal " +
            "from=\(fromKey.rawValue) " +
            "to=\(toKey.rawValue) " +
            "trigger=\(trigger.rawValue) " +
            "result=\(isLegal)"
        )

        if !isLegal {
            let nearby = legalTransitions
                .filter { $0.from == fromKey }
                .sorted {
                    if $0.trigger.rawValue != $1.trigger.rawValue {
                        return $0.trigger.rawValue < $1.trigger.rawValue
                    }
                    return $0.to.rawValue < $1.to.rawValue
                }
                .map { "\($0.from.rawValue)->\($0.to.rawValue) via \($0.trigger.rawValue)" }
                .joined(separator: " | ")

            exchangeTransitionDbg(
                "[ExchangeTransition] illegal transition detail " +
                "from=\(fromKey.rawValue) " +
                "to=\(toKey.rawValue) " +
                "trigger=\(trigger.rawValue) " +
                "allowedFromCurrent=[\(nearby)]"
            )
        }

        return isLegal
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
