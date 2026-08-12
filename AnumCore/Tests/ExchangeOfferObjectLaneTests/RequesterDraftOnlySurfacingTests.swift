import Foundation
import Testing
@testable import AnumCore

@Suite("RequesterDraftOnlySurfacing")
struct RequesterDraftOnlySurfacingTests {

    @Test("draftOnly authority allows draft preparation and surfacing when send blocked")
    func draftOnlyAuthoritySemantics() {
        #expect(ExchangeAutonomousUserAuthority.draftOnly.allowsAutonomousSend == false)
        #expect(ExchangeAutonomousUserAuthority.draftOnly.allowsDraftPreparation == true)
        #expect(ExchangeAutonomousUserAuthority.draftOnly.shouldSurfacePreparedDraftWhenSendBlocked == true)
        #expect(ExchangeAutonomousUserAuthority.manualOnly.allowsDraftPreparation == false)
        #expect(ExchangeAutonomousUserAuthority.manualOnly.shouldSurfacePreparedDraftWhenSendBlocked == false)
    }

    @Test("outbound context surfaces draft-only blocked send with prepared draft")
    func outboundContextDraftOnlySurfacing() {
        let metadata: [String: String] = [
            "autonomous_send_lane": "requester_outbound",
            "autonomous_send_outcome": "disabledByUserSetting",
            "autonomous_send_allowed": "false",
            "autonomous_send_user_authority_mode": ExchangeAutonomousUserAuthority.draftOnly.rawValue,
            "autonomous_send_draft_review_required": "true"
        ]
        let ctx = ExchangeSecondHalfOutboundSendContext(
            autonomousMetadata: metadata,
            draftMetadata: [
                "second_half_generated": "true",
                "agency_authored_body": "true"
            ]
        )
        #expect(ctx.requesterOutboundExplicitlyBlockedByRecording == true)
        #expect(ctx.shouldSurfacePreparedRequesterDraftWhenSendBlocked == true)
        #expect(ctx.requesterOutboundBlockedWithoutDraftSurfacing == false)
        #expect(ctx.hasPreparedRequesterOutboundDraft() == true)
    }

    @Test("manualOnly blocked send does not surface hidden draft")
    func manualOnlyBlockedDoesNotSurface() {
        let ctx = ExchangeSecondHalfOutboundSendContext(
            autonomousMetadata: [
                "autonomous_send_outcome": "disabledByUserSetting",
                "autonomous_send_user_authority_mode": ExchangeAutonomousUserAuthority.manualOnly.rawValue
            ],
            draftMetadata: ["second_half_generated": "true"]
        )
        #expect(ctx.shouldSurfacePreparedRequesterDraftWhenSendBlocked == false)
        #expect(ctx.requesterOutboundBlockedWithoutDraftSurfacing == true)
    }

    @Test("UI adapter shows draft ready for draft-only blocked requester clarification")
    func uiAdapterShowsDraftReadyWhenDraftOnlyBlocked() {
        let adapter = ExchangeSecondHalfUIAdapter()
        let threadID = UUID()
        let thread = ExchangeThread(
            id: threadID,
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: .providerSearch,
                surfacePreference: .offer,
                title: "Test",
                objective: "find cleaner"
            ),
            posture: ExchangePosture(),
            state: .searching(.init()),
            metadata: [
                "autonomous_send_outcome": "disabledByUserSetting",
                "autonomous_send_user_authority_mode": ExchangeAutonomousUserAuthority.draftOnly.rawValue,
                "autonomous_send_draft_review_required": "true"
            ]
        )
        let draft = ExchangeMessageDraft(
            threadID: threadID,
            status: .draft,
            kind: .inquiry,
            audience: .externalCounterparty,
            body: "Could you confirm availability for next week?",
            posture: ExchangePosture(),
            metadata: [
                "second_half_generated": "true",
                "agency_authored_body": "true"
            ]
        )
        let snapshot = ExchangeThread.SecondHalfSnapshot(
            schemaVersion: 2,
            currentStateRaw: ExchangeSecondHalfState.awaitingProviderClarification.rawValue,
            roleRaw: ExchangeSecondHalfRole.requester.displayTitle,
            nextMoveActionRaw: ExchangeSecondHalfAction.askClarification.rawValue,
            canRunAutonomously: true,
            needsHumanAttention: false,
            revision: 1,
            lastEvaluatedAt: Date(),
            updatedAt: Date()
        )
        let display = adapter.makeDisplayModel(
            from: snapshot,
            thread: thread,
            selectedCounterpartyName: "Provider",
            latestDraft: draft
        )
        #expect(display.agencyPhase == ExchangeSecondHalfUIAdapter.AgencyPhase.providerClarificationDraftReady)
        #expect(display.hasDraft == true)
        #expect(display.draft?.outboundBodyFull?.contains("availability") == true)
    }
}
