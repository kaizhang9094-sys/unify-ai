import Foundation

extension ExchangeSecondHalfOutboundSendContext {
    private static let userAuthorityModeMetadataKey = "autonomous_send_user_authority_mode"
    private static let draftReviewRequiredMetadataKey = "autonomous_send_draft_review_required"

    /// Parsed thread-autonomy mode recorded alongside the latest autonomous send decision.
    public var recordedUserAuthorityMode: ExchangeAutonomousUserAuthority? {
        if let raw = autonomousMetadata[Self.userAuthorityModeMetadataKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let parsed = ExchangeAutonomousUserAuthority(rawValue: raw) {
            return parsed
        }
        let summary = autonomousMetadata["autonomous_send_user_authority"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !summary.isEmpty else { return nil }
        for mode in [
            ExchangeAutonomousUserAuthority.draftOnly,
            .manualOnly,
            .routineAutoRespond,
            .fullWithinBoundaries,
            .missing,
            .invalid
        ] {
            if summary.contains(mode.rawValue) {
                return mode
            }
        }
        return nil
    }

    /// True when autonomy recording blocked send but draft-only mode expects user review.
    public var requesterDraftReviewRequiredWhenSendBlocked: Bool {
        if autonomousMetadata[Self.draftReviewRequiredMetadataKey] == "true" {
            return true
        }
        guard requesterOutboundExplicitlyBlockedByRecording else { return false }
        return recordedUserAuthorityMode?.shouldSurfacePreparedDraftWhenSendBlocked == true
    }

    /// Prepared second-half outbound exists locally (template or agency-authored body).
    public func hasPreparedRequesterOutboundDraft(latestDraft: ExchangeMessageDraft? = nil) -> Bool {
        if let latestDraft, isSurfacedRequesterSecondHalfDraft(latestDraft) {
            return true
        }
        if truthyMarker(draftMetadata["second_half_generated"]) {
            return true
        }
        if truthyMarker(draftMetadata["agency_authored_body"]) {
            return true
        }
        return false
    }

    /// Draft-only (or equivalent recording) should keep prepared drafts visible after send block.
    public var shouldSurfacePreparedRequesterDraftWhenSendBlocked: Bool {
        requesterDraftReviewRequiredWhenSendBlocked
    }

    /// User setting blocked send and UI should not treat the thread as draft-ready.
    public var requesterOutboundBlockedWithoutDraftSurfacing: Bool {
        requesterOutboundExplicitlyBlockedByRecording
            && !shouldSurfacePreparedRequesterDraftWhenSendBlocked
    }

    private func isSurfacedRequesterSecondHalfDraft(_ draft: ExchangeMessageDraft) -> Bool {
        guard draft.isActionable else { return false }
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        if truthyMarker(draft.metadata["second_half_generated"]) {
            return true
        }
        if truthyMarker(draft.metadata["agency_authored_body"]) {
            return true
        }
        return false
    }
}
