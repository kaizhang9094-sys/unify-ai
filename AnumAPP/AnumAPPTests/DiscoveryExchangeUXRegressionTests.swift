import Foundation
import XCTest
import AnumCore
@testable import AnumAPP

/// Regression coverage for Discovery / Exchange secretary UX contracts (fixtures only).
final class DiscoveryExchangeUXRegressionTests: XCTestCase {
    private let t0 = SecretaryProjectionTestSupport.fixtureDate
    private let threadAutonomyKey = "secretary.threadAutonomy.mode"
    private var previousAutonomyValue: Any?

    override func setUp() {
        super.setUp()
        previousAutonomyValue = UserDefaults.standard.object(forKey: threadAutonomyKey)
    }

    override func tearDown() {
        if let previousAutonomyValue {
            UserDefaults.standard.set(previousAutonomyValue, forKey: threadAutonomyKey)
        } else {
            UserDefaults.standard.removeObject(forKey: threadAutonomyKey)
        }
        super.tearDown()
    }

    // MARK: - 1) Routine draft, auto-reply OFF → inline Send + prepared-send queue path

    func test_routineExternalDraft_manualAutonomy_usesSendAndPreparedQueueSemantics() {
        UserDefaults.standard.set(ExchangeModels.ExchangeThreadAutonomyMode.manualOnly.rawValue, forKey: threadAutonomyKey)

        let tid = UUID()
        let draftID = UUID()
        let cp: ExchangeCounterparty.ID = "fixture-discovery-anchor-cp"
        let thread = routineThread(id: tid, counterpartyID: cp)
        let draft = routineOutboundDraft(threadID: tid, draftID: draftID)
        let sh = requesterRoutineSecondHalf(threadID: tid, assessment: gateAllowingAssessment())
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            outboxItems: [],
            inboxItems: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        XCTAssertTrue(ExchangeMessageDraft.hasUserFacingRenderableExternalOutboundDraft(in: [draft], thread: thread))
        XCTAssertTrue(ExchangeOutboundRecipientAnchor.hasRecipientSurface(for: thread))

        let panel = SecretaryProjectionEngine.approvalDisplay(for: detail)
        XCTAssertEqual(panel.primaryTitle, "Send")
        XCTAssertNil(panel.approvalID)
        XCTAssertTrue(panel.prefersSecondHalfPreparedSend, "Routine path should prefer queuePreparedSecondHalfOutboundSend when no pending approval row.")
        XCTAssertFalse(panel.requiresHumanApproval)
        XCTAssertFalse(panel.hasDecisionPacket)
        XCTAssertFalse(panel.hasCommitmentBoundary)

        XCTAssertTrue(SecretaryProjectionEngine.threadViewDirectApproveAndSendEligible(for: detail))
        XCTAssertNil(SecretaryProjectionEngine.threadViewAutonomyGateDeniedExplanation(for: detail))
        XCTAssertFalse(SecretaryProjectionEngine.threadViewAutonomousRoutineSuppressesManualSend(for: detail))
    }

    // MARK: - 2) Auto-reply ON + gate allowed → suppress manual Send; real pipeline surfaces Sending

    func test_routineExternalDraft_autonomyOn_gateAllowed_suppressesManualSend_andShowsTruthfulSending() {
        UserDefaults.standard.set(
            ExchangeModels.ExchangeThreadAutonomyMode.routineAutoRespond.rawValue,
            forKey: threadAutonomyKey
        )

        let tid = UUID()
        let draftID = UUID()
        let cp: ExchangeCounterparty.ID = "fixture-discovery-anchor-cp-2"
        var thread = routineThread(id: tid, counterpartyID: cp)
        thread.state = .sending(.init(startedAt: t0, attemptNumber: 1, channelSummary: "Fixture"))
        let draft = routineOutboundDraft(threadID: tid, draftID: draftID)
        let sh = requesterRoutineSecondHalf(threadID: tid, assessment: gateAllowingAssessment())
        let outbox = fixtureOutbox(threadID: tid, draftID: draftID, phase: .queued)

        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            outboxItems: [outbox],
            inboxItems: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        XCTAssertTrue(SecretaryProjectionEngine.threadViewAutonomousRoutineSuppressesManualSend(for: detail))
        XCTAssertFalse(SecretaryProjectionEngine.threadViewDirectApproveAndSendEligible(for: detail))

        XCTAssertTrue(
            detail.outboxItems.contains { ob in
                ob.threadID == tid && ob.isActive && ob.deliveryState.phase == .queued
            }
        )
        // Pipeline-backed “Sending…” row (builder may dedupe when second-half mirrors the same draft in UI).
        let pipelineRows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail, secondHalfDisplay: nil)
        XCTAssertTrue(pipelineRows.contains { $0.title == "Sending…" })
    }

    // MARK: - 3) Auto-reply ON + gate denied → Review path (not routine Send) + hold copy; no ghost Sending

    func test_routineExternalDraft_autonomyOn_gateDenied_prefersReviewNotRoutineSend_andNoGhostSending() {
        UserDefaults.standard.set(
            ExchangeModels.ExchangeThreadAutonomyMode.fullWithinBoundaries.rawValue,
            forKey: threadAutonomyKey
        )

        let tid = UUID()
        let draftID = UUID()
        let cp: ExchangeCounterparty.ID = "fixture-discovery-anchor-cp-3"
        var thread = routineThread(id: tid, counterpartyID: cp)
        thread.state = .sending(.init(startedAt: t0, attemptNumber: 1, channelSummary: "Misleading"))
        let draft = routineOutboundDraft(threadID: tid, draftID: draftID)
        let sh = requesterRoutineSecondHalf(threadID: tid, assessment: gateBlockingAssessment())

        let detailNoOutbox = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [draft],
            matches: [],
            counterparties: [],
            artifacts: [],
            outboxItems: [],
            inboxItems: [],
            summary: "Fixture",
            secondHalfDisplay: sh
        )

        let blocked = SecretaryProjectionEngine.threadViewAutonomyGateDeniedExplanation(for: detailNoOutbox)
        XCTAssertNotNil(blocked)
        XCTAssertFalse(blocked!.isEmpty)

        XCTAssertFalse(SecretaryProjectionEngine.threadViewAutonomousRoutineSuppressesManualSend(for: detailNoOutbox))
        XCTAssertFalse(SecretaryProjectionEngine.threadViewDirectApproveAndSendEligible(for: detailNoOutbox))

        let vs = SecretaryProjectionEngine.visibleThreadStatus(for: detailNoOutbox)
        if case .sending = vs.primary {
            XCTFail("Unexpected ghost Sending visible status without outbox/delivery evidence")
        }

        let panel = SecretaryProjectionEngine.approvalDisplay(for: detailNoOutbox)
        XCTAssertNotEqual(panel.primaryTitle, "Send")
        XCTAssertTrue(
            panel.primaryTitle == "Review" || panel.primaryTitle == "Review request" || panel.primaryTitle == "Answer needed"
        )
    }

    func test_copySanitizer_replacesFiledPhrases() {
        XCTAssertEqual(
            ExchangeUserFacingCopySanitizer.sanitize("Reply filed", field: .body),
            "Linked to conversation"
        )
        XCTAssertEqual(
            ExchangeUserFacingCopySanitizer.sanitize("filed", field: .status),
            "Added to conversation"
        )
    }

    func test_postApprovalTranscript_genericNoPipeline_avoidsSendingClaims() {
        let tid = UUID()
        let grant = ExchangeTurn(
            threadID: tid,
            createdAt: t0.addingTimeInterval(200),
            actor: .user,
            kind: .approvalGranted,
            summary: "Approval granted",
            detail: nil
        )
        let thread = routineThread(id: tid, counterpartyID: "fixture-discovery-anchor-cp-4")
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [grant],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            outboxItems: [],
            inboxItems: [],
            summary: "Fixture",
            secondHalfDisplay: nil
        )
        let rows = ExchangeModels.ThreadTranscriptBuilder.build(from: detail, secondHalfDisplay: nil)
        let row = rows.first { $0.title == "After your approval" }
        XCTAssertNotNil(row)
        XCTAssertTrue(row!.bodyPreview.localizedCaseInsensitiveContains("approval recorded"))
        XCTAssertFalse(row!.bodyPreview.localizedCaseInsensitiveContains("sending"))
        XCTAssertFalse(row!.bodyPreview.localizedCaseInsensitiveContains("ready to send"))
    }

    // MARK: - 4) Inbox reconciled copy

    func test_inboundReconciledCopy_avoidsFiledWording() {
        XCTAssertEqual(SecretaryInboundUserFacingCopy.linkedConversationSectionTitle, "Linked to conversation")
        XCTAssertEqual(SecretaryInboundUserFacingCopy.linkedThreadChip, "In thread")
        XCTAssertEqual(
            SecretaryInboundUserFacingCopy.processingHeadline(for: .reconciledIntoThread),
            "In thread"
        )

        let banned = ["filed", "reply filed"]
        for phrase in banned {
            XCTAssertFalse(
                SecretaryInboundUserFacingCopy.linkedConversationSectionTitle.localizedCaseInsensitiveContains(phrase)
            )
            XCTAssertFalse(
                SecretaryInboundUserFacingCopy.linkedThreadChip.localizedCaseInsensitiveContains(phrase)
            )
            XCTAssertFalse(
                SecretaryInboundUserFacingCopy.processingHeadline(for: .reconciledIntoThread)
                    .localizedCaseInsensitiveContains(phrase)
            )
        }
    }

    // MARK: - 5) Inbound provider dashboard title + preview

    func test_inboundProviderDashboardTitle_prefersInquiryOrSender_notRawNodeTitle() {
        let tid = UUID()
        let item = ExchangeModels.InboxItem(
            threadID: tid,
            title: "Inbound message from node-abcdef12",
            capturedRequestText: nil,
            subtitle: "",
            state: .drafting,
            stateTitle: "Drafting",
            updatedAt: t0,
            requiresHumanDecision: false,
            hasFailure: false,
            visibleSummary: nil,
            selectedCounterpartyID: "cp-1",
            selectedCounterpartyName: "Weekend photo package",
            selectedOfferID: "offer-1",
            hasPendingApproval: false,
            hasDraft: false,
            hasActionableExternalOutboundDraft: false,
            prefersInboundProviderCardTitleRewrite: true,
            cardInboundSenderLabel: "Alex Kim",
            cardInboundRequesterPreview: "Are you available June 14?"
        )

        let title = SecretaryProjectionEngine.displayTitle(for: item, surface: "home")
        XCTAssertFalse(title.localizedCaseInsensitiveContains("Inbound message from node"))
        XCTAssertTrue(title.localizedCaseInsensitiveContains("new inquiry about") || title.localizedCaseInsensitiveContains("new message from"))

        let subtitle = SecretaryProjectionEngine.displayCardSubtitle(for: item, surface: "home")
        XCTAssertTrue(subtitle.localizedCaseInsensitiveContains("june 14"))
    }

    // MARK: - Fixtures

    private func routineThread(id: UUID, counterpartyID: ExchangeCounterparty.ID) -> ExchangeThread {
        ExchangeThread(
            id: id,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(10),
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .message,
                mode: .transactional,
                queryIntentClass: .directOutreach,
                title: "Fixture",
                objective: "Fixture objective",
                readiness: .ready,
                interpretationConfidence: 1.0
            ),
            posture: ExchangePosture(),
            state: .draftReady(.init(preparedAt: t0, summary: "Fixture")),
            selectedCounterpartyID: counterpartyID,
            selectedOfferID: nil,
            lastInboundEnvelopeID: nil
        )
    }

    private func routineOutboundDraft(threadID: UUID, draftID: UUID) -> ExchangeMessageDraft {
        ExchangeMessageDraft(
            id: draftID,
            threadID: threadID,
            createdAt: t0,
            updatedAt: t0.addingTimeInterval(2),
            status: .draft,
            kind: .followUp,
            audience: .externalCounterparty,
            subject: "Re: June 14",
            body: "We can do June 14 afternoon. Does that work for you?",
            posture: ExchangePosture(),
            metadata: ["second_half_generated": "true"]
        )
    }

    private func gateAllowingAssessment() -> ExchangeAgencyAssessment {
        let decision = ExchangeAgencyDecision(
            recommendedAction: nil,
            autonomyDisposition: .allowAutonomousOutbound,
            requiresUserApproval: false,
            requiresUserInput: false,
            blockReasons: [],
            permitReasons: ["ok"]
        )
        return ExchangeAgencyAssessment(
            groundedFactLines: ["a", "b"],
            agencyDecision: decision
        )
    }

    private func gateBlockingAssessment() -> ExchangeAgencyAssessment {
        let decision = ExchangeAgencyDecision(
            recommendedAction: .askClarification,
            autonomyDisposition: .holdForApproval,
            requiresUserApproval: true,
            requiresUserInput: false,
            blockReasons: ["block_a"],
            permitReasons: []
        )
        return ExchangeAgencyAssessment(
            groundedFactLines: ["x"],
            agencyDecision: decision
        )
    }

    private func requesterRoutineSecondHalf(
        threadID: UUID,
        assessment: ExchangeAgencyAssessment?
    ) -> ExchangeSecondHalfUIAdapter.DisplayModel {
        let role = ExchangeSecondHalfRole.requester.displayTitle
        return ExchangeSecondHalfUIAdapter.DisplayModel(
            threadID: threadID,
            placement: .activeCoordination,
            title: "Fixture title",
            subtitle: "Fixture subtitle",
            summary: "",
            postureSummary: "Fixture posture",
            recommendation: "",
            stateLabel: "Fixture state",
            roleLabel: role,
            hero: ExchangeSecondHalfUIAdapter.Hero(
                eyebrow: "Fixture",
                title: "Hero headline",
                subtitle: "Hero subtitle",
                statusLine: "Fixture status line"
            ),
            status: ExchangeSecondHalfUIAdapter.Status(
                state: "Coordination",
                role: role,
                quality: "Fixture quality",
                readiness: "Fixture readiness",
                isBlocking: false,
                isAutonomous: true,
                isDecisionReady: false,
                isTerminal: false
            ),
            operatingContext: ExchangeSecondHalfUIAdapter.OperatingContextSection(
                role: role,
                postureSummary: "Fixture operating posture",
                readiness: "Ready enough",
                urgency: "Normal",
                trust: "Fixture trust",
                priceSensitivity: "Unknown",
                flexibility: "Moderate"
            ),
            boundary: ExchangeSecondHalfUIAdapter.BoundarySection(
                title: "",
                kind: "coordination",
                reason: "",
                requiresHumanApproval: false,
                allowsAutonomousDrafting: true,
                allowsAutonomousSending: true,
                externalEffectLine: ""
            ),
            draft: ExchangeSecondHalfUIAdapter.DraftSection(
                subject: "Re: June 14",
                bodyPreview: "We can do June 14 afternoon.",
                requiresApprovalBeforeSending: false
            ),
            needsHumanAttention: false,
            canRunAutonomously: true,
            agencyPhase: .unknown,
            hasDecisionPacket: false,
            hasProviderReception: false,
            hasRequesterReview: false,
            hasDraft: true,
            isTerminal: false,
            agencyAssessment: assessment
        )
    }

    private func fixtureOutbox(
        threadID: UUID,
        draftID: UUID,
        phase: ExchangeDeliveryState.Phase
    ) -> ExchangeOutboxItem {
        ExchangeOutboxItem(
            threadID: threadID,
            draftID: draftID,
            targetNodeID: "fixture-remote-node",
            envelopeID: "fixture-envelope-\(draftID.uuidString.prefix(8))",
            deliveryState: ExchangeDeliveryState(
                phase: phase,
                priority: .userInitiated,
                note: nil,
                queuedAt: t0
            ),
            payloadSummary: "Fixture outbound",
            isActive: true
        )
    }
}
