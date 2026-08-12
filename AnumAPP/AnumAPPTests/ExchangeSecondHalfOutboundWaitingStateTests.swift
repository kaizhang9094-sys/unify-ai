import Foundation
import XCTest
import AnumCore
@testable import AnumAPP

/// Requester “awaiting provider clarification” must not read as “waiting for reply” until send proof exists.
@MainActor
final class ExchangeSecondHalfOutboundWaitingStateTests: XCTestCase {

    private let adapter = ExchangeSecondHalfUIAdapter()
    private let fixtureDate = SecretaryProjectionTestSupport.fixtureDate

    // MARK: - Adapter / projection path

    func test_projection_awaitingProvider_withDraft_blockedAutonomous_showsDraftReadyNotWaitingPhase() throws {
        let nextMove = ExchangeNextMoveViewModel(
            action: .askClarification,
            title: "Ask a clarifying question",
            rationale: "Fixture rationale",
            requiredInputs: [],
            needsGeneration: false,
            needsUserInput: false,
            needsApproval: false
        )
        let pendingDraft = ExchangeDraftComposer.Draft(
            subject: "Quick question",
            body: "Can you confirm weekend availability?",
            usedStructuredFacts: [],
            notes: []
        )
        let projection = ExchangeSecondHalfProjection(
            currentState: .awaitingProviderClarification,
            role: .requester,
            stance: ExchangeThreadStance(),
            qualification: ExchangeOpportunityQualification(),
            pendingDraft: pendingDraft,
            visibleActions: [.askClarification],
            nextMove: nextMove
        )

        let ctx = ExchangeSecondHalfOutboundSendContext(
            autonomousMetadata: [
                "autonomous_send_lane": "requester_outbound",
                "autonomous_send_outcome": "disabledByUserSetting",
                "autonomous_send_allowed": "false"
            ],
            draftMetadata: [:],
            deliverySnapshot: nil
        )

        let display = adapter.makeDisplayModel(from: projection, outboundSendContext: ctx)

        XCTAssertEqual(display.agencyPhase, ExchangeSecondHalfUIAdapter.AgencyPhase.providerClarificationDraftReady)

        let blob = userFacingBlob(from: display)
        XCTAssertFalse(blob.contains("waiting for provider"))
        XCTAssertFalse(blob.contains("waiting for response"))
        XCTAssertFalse(blob.contains("waiting on them"))
        XCTAssertFalse(blob.contains("sent. waiting"))
        XCTAssertTrue(blob.contains("draft") || blob.contains("review"))
    }

    func test_projection_awaitingProvider_outboundQueuedMetadata_showsWaitingPhase() throws {
        let nextMove = ExchangeNextMoveViewModel(
            action: .askClarification,
            title: "Ask",
            rationale: "r",
            needsGeneration: false,
            needsUserInput: false,
            needsApproval: false
        )
        let projection = ExchangeSecondHalfProjection(
            currentState: .awaitingProviderClarification,
            role: .requester,
            stance: ExchangeThreadStance(),
            qualification: ExchangeOpportunityQualification(),
            pendingDraft: ExchangeDraftComposer.Draft(body: "Q"),
            visibleActions: [.askClarification],
            nextMove: nextMove
        )

        let ctx = ExchangeSecondHalfOutboundSendContext(
            autonomousMetadata: [:],
            draftMetadata: ["second_half_outbound_queued": "true"],
            deliverySnapshot: nil
        )

        let display = adapter.makeDisplayModel(from: projection, outboundSendContext: ctx)
        XCTAssertEqual(display.agencyPhase, ExchangeSecondHalfUIAdapter.AgencyPhase.awaitingProviderAnswer)
    }

    // MARK: - Cached snapshot path

    func test_snapshot_awaitingProvider_withDraftAndBlockedMetadata_usesDraftReadyLabels() throws {
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture",
            objective: "Outbound waiting copy",
            readiness: .ready
        )
        let snapshot = ExchangeThread.SecondHalfSnapshot(
            schemaVersion: 2,
            currentStateRaw: ExchangeSecondHalfState.awaitingProviderClarification.rawValue,
            roleRaw: ExchangeSecondHalfRole.requester.rawValue,
            nextMoveActionRaw: ExchangeSecondHalfAction.askClarification.rawValue,
            draftPreview: "Can you confirm pricing for a half-day shoot?",
            lastEvaluatedAt: fixtureDate,
            updatedAt: fixtureDate
        )
        var thread = ExchangeThread(
            id: UUID(),
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            mode: .transactional,
            intent: intent,
            posture: .default,
            secondHalf: snapshot,
            state: .awaitingResponse(.init(since: fixtureDate)),
            metadata: [
                "autonomous_send_lane": "requester_outbound",
                "autonomous_send_outcome": "disabledByUserSetting",
                "autonomous_send_allowed": "false"
            ]
        )

        let display = adapter.makeDisplayModel(
            from: snapshot,
            thread: thread,
            selectedCounterpartyName: "Pat",
            latestDraft: nil
        )

        XCTAssertEqual(display.agencyPhase, ExchangeSecondHalfUIAdapter.AgencyPhase.providerClarificationDraftReady)
        let blob = userFacingBlob(from: display)
        XCTAssertFalse(blob.contains("waiting for response"))
        XCTAssertTrue(blob.contains("draft"))
    }

    // MARK: - Secretary inbox boundary

    func test_projectionEngine_boundaryLine_unsentProviderClarificationAvoidsSentWaitingCopy() throws {
        let tid = UUID()
        let sh = SecretaryProjectionTestSupport.minimalSecondHalfDisplay(
            threadID: tid,
            placement: .currentFocus,
            boundaryReason: "",
            externalEffectLine: "",
            agencyPhase: .providerClarificationDraftReady,
            agencyPhaseTitle: "Draft ready",
            agencyPhaseDetail: "Review and send the question to the provider. Nothing has been sent yet."
        )

        let item = ExchangeModels.InboxItem(
            threadID: tid,
            title: "Fixture exchange",
            capturedRequestText: nil,
            subtitle: "Subtitle",
            state: .awaitingResponse(.init(since: fixtureDate)),
            stateTitle: "Awaiting Reply",
            updatedAt: fixtureDate,
            requiresHumanDecision: false,
            hasFailure: false,
            visibleSummary: nil,
            hasPendingApproval: false,
            hasDraft: true,
            hasActionableExternalOutboundDraft: true,
            awaitingReply: true,
            needsClarification: false,
            secondHalfDisplay: sh
        )

        let line = SecretaryProjectionEngine.boundaryLine(for: item)
        XCTAssertTrue(line.lowercased().contains("draft"))
        XCTAssertFalse(line.lowercased().contains("sent. waiting"))
    }

    func test_projectionEngine_threadNextMove_whenAutoFollowUpsOff_showsManualActionLine() {
        let intent = ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture",
            objective: "Need one follow-up",
            readiness: .ready
        )
        let thread = ExchangeThread(
            id: UUID(),
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            mode: .transactional,
            intent: intent,
            posture: .default,
            secondHalf: nil,
            state: .awaitingResponse(.init(since: fixtureDate)),
            metadata: [
                "autonomous_send_lane": "requester_outbound",
                "autonomous_send_outcome": "disabledByUserSetting",
                "autonomous_send_allowed": "false"
            ]
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: thread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Fixture"
        )

        let next = SecretaryProjectionEngine.threadNextMove(detail).lowercased()
        XCTAssertTrue(next.contains("auto-follow-ups are off"))
        XCTAssertTrue(next.contains("manually"))
    }

    private func userFacingBlob(from display: ExchangeSecondHalfUIAdapter.DisplayModel) -> String {
        [
            display.summary,
            display.subtitle,
            display.agencyPhaseTitle,
            display.agencyPhaseDetail,
            display.agencyPhase?.displayTitle,
            display.hero.statusLine,
            display.stateLabel,
            display.status.state,
            display.recommendation,
            display.nextMove?.title,
            display.nextMove?.rationale,
            display.draft?.bodyPreview
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }
}
