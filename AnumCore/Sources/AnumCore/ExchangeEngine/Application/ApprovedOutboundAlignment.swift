import Foundation

/// Preflight and legality helpers for approved outbound thread ↔ outbox alignment.
enum ApprovedOutboundAlignment {
    enum LegalizeStep: String, Sendable {
        case candidateAccepted
        case draftPrepared
        case approvalRequested
        case approvalGranted
    }

    enum Action: String, Sendable {
        case grant
        case align
        case quarantine
        case skip
    }

    /// Exchange-desk commercial send alignment applies only to commercial inquiry and legacy unknown lanes.
    static func isExchangeSendableLane(_ lane: ExchangeThreadLane) -> Bool {
        switch lane {
        case .commercialInquiry, .unknown:
            return true
        case .directMessage, .contactSignal, .socialConnection:
            return false
        }
    }

    static func hasRecipientAnchor(for thread: ExchangeThread) -> Bool {
        let counterparty = thread.selectedCounterpartyID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !counterparty.isEmpty { return true }

        let profile = thread.selectedPublicProfileID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !profile.isEmpty { return true }

        let offer = thread.selectedOfferID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !offer.isEmpty
    }

    static func hasRenderableDraftBody(_ draft: ExchangeMessageDraft) -> Bool {
        !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether `grantApproval` → `.sending` is legal from the current thread phase.
    static func isLegalGrantApproval(from state: ExchangeState) -> Bool {
        let sendingProbe = ExchangeState.sending(
            .init(
                startedAt: Date(),
                attemptNumber: 1,
                channelSummary: "alignment_probe"
            )
        )
        return ExchangeTransition.isLegal(
            from: state,
            to: sendingProbe,
            trigger: .approvalGranted
        )
    }

    static func isLegalDraftPrepared(from state: ExchangeState, draftID: ExchangeMessageDraft.ID) -> Bool {
        let draftReadyProbe = ExchangeState.draftReady(
            .init(
                preparedAt: Date(),
                summary: "Draft prepared.",
                draftID: draftID
            )
        )
        return ExchangeTransition.isLegal(
            from: state,
            to: draftReadyProbe,
            trigger: .draftPrepared
        )
    }

    static func isLegalCandidateAccepted(
        from state: ExchangeState,
        thread: ExchangeThread,
        selectedCounterpartyID: String
    ) -> Bool {
        let count = max(1, thread.candidateCounterpartyIDs.count)
        let matchFoundProbe = ExchangeState.matchFound(
            .init(
                foundAt: Date(),
                candidateCount: count,
                summary: "Aligned for outbound.",
                selectedCounterpartyID: selectedCounterpartyID
            )
        )
        return ExchangeTransition.isLegal(
            from: state,
            to: matchFoundProbe,
            trigger: .candidateAccepted
        )
    }

    static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
