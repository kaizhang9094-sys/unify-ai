import Foundation
import XCTest
@testable import AnumCore

final class ApprovedOutboundAlignmentTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let engine = ExchangeThreadEngine()

    private func commercialIntent() -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .providerSearch,
            title: "Find supplier",
            objective: "Source widgets",
            readiness: .ready
        )
    }

    private func weakMatchThread(
        selectedCounterpartyID: String? = "peer-1",
        candidateIDs: [String] = ["peer-1", "peer-2"]
    ) -> ExchangeThread {
        var thread = ExchangeThread(
            mode: .transactional,
            intent: commercialIntent(),
            posture: .default,
            state: .matchCandidatesWeak(
                .init(
                    candidateCount: candidateIDs.count,
                    explanation: "Several possible matches."
                )
            ),
            metadata: [:]
        )
        thread.selectedCounterpartyID = selectedCounterpartyID
        thread.candidateCounterpartyIDs = candidateIDs
        return thread
    }

    private func draft(for thread: ExchangeThread, body: String = "Hello supplier") -> ExchangeMessageDraft {
        ExchangeMessageDraft(
            threadID: thread.id,
            kind: .introduction,
            audience: .externalCounterparty,
            body: body,
            posture: thread.posture,
            targetCounterpartyID: thread.selectedCounterpartyID
        )
    }

    private func approved(for thread: ExchangeThread, draft: ExchangeMessageDraft) -> ExchangeApproval {
        ExchangeApproval(
            threadID: thread.id,
            status: .approved,
            kind: .outboundSend,
            requestedAction: .sendMessage,
            draftID: draft.id,
            summary: "Send prepared outreach.",
            decidedAt: now
        )
    }

    func testGrantApprovalFromMatchCandidatesWeakRemainsIllegal() {
        let thread = weakMatchThread()
        let draft = draft(for: thread)
        let approval = approved(for: thread, draft: draft)

        XCTAssertThrowsError(try engine.grantApproval(thread: thread, approval: approval, now: now)) { error in
            guard case ExchangeThreadEngineError.invalidTransition = error else {
                return XCTFail("Expected invalidTransition, got \(error)")
            }
        }
    }

    func testIsLegalGrantApprovalFalseForWeakMatch() {
        let thread = weakMatchThread()
        XCTAssertFalse(ApprovedOutboundAlignment.isLegalGrantApproval(from: thread.state))
    }

    func testWeakMatchLegalAlignmentViaDraftPreparedThenGrant() throws {
        let thread = weakMatchThread()
        let draft = draft(for: thread)
        let approval = approved(for: thread, draft: draft)

        XCTAssertTrue(ApprovedOutboundAlignment.isLegalDraftPrepared(from: thread.state, draftID: draft.id))

        let prepared = try engine.markDraftPrepared(thread: thread, draft: draft, now: now)
        XCTAssertTrue(ApprovedOutboundAlignment.isLegalGrantApproval(from: prepared.thread.state))

        let granted = try engine.grantApproval(thread: prepared.thread, approval: approval, now: now)
        if case .sending = granted.thread.state {
            // expected
        } else {
            XCTFail("Expected sending after legal alignment, got \(granted.thread.state.phaseTitle)")
        }
    }

    func testWeakMatchWithoutAnchorCannotLegalizeGrant() {
        let thread = weakMatchThread(selectedCounterpartyID: nil, candidateIDs: [])
        let draft = draft(for: thread, body: "Hello")

        XCTAssertFalse(ApprovedOutboundAlignment.hasRecipientAnchor(for: thread))
        XCTAssertFalse(ApprovedOutboundAlignment.isLegalGrantApproval(from: thread.state))
        XCTAssertFalse(ApprovedOutboundAlignment.isLegalDraftPrepared(from: thread.state, draftID: draft.id))
    }

    func testAwaitingApprovalGrantApprovalTransitionsToSending() throws {
        let draftID = UUID()
        var thread = ExchangeThread(
            mode: .transactional,
            intent: commercialIntent(),
            posture: .default,
            state: .awaitingApproval(
                .init(
                    requestedAt: now,
                    summary: "Please approve.",
                    draftID: draftID
                )
            ),
            metadata: [:]
        )
        thread.selectedCounterpartyID = "peer-1"

        let draft = ExchangeMessageDraft(
            id: draftID,
            threadID: thread.id,
            kind: .introduction,
            audience: .externalCounterparty,
            body: "Ready to send",
            posture: thread.posture,
            targetCounterpartyID: "peer-1"
        )
        let approval = approved(for: thread, draft: draft)

        XCTAssertTrue(ApprovedOutboundAlignment.isLegalGrantApproval(from: thread.state))
        let granted = try engine.grantApproval(thread: thread, approval: approval, now: now)
        if case .sending = granted.thread.state {
            // expected
        } else {
            XCTFail("Expected sending, got \(granted.thread.state.phaseTitle)")
        }
    }

    func testDraftReadyGrantApprovalTransitionsToSending() throws {
        let draftID = UUID()
        let thread = ExchangeThread(
            mode: .transactional,
            intent: commercialIntent(),
            posture: .default,
            state: .draftReady(
                .init(preparedAt: now, summary: "Prepared", draftID: draftID)
            ),
            selectedCounterpartyID: "peer-1",
            metadata: [:]
        )
        let draft = ExchangeMessageDraft(
            id: draftID,
            threadID: thread.id,
            kind: .introduction,
            audience: .externalCounterparty,
            body: "Ready to send",
            posture: thread.posture,
            targetCounterpartyID: "peer-1"
        )
        let approval = approved(for: thread, draft: draft)

        XCTAssertTrue(ApprovedOutboundAlignment.isLegalGrantApproval(from: thread.state))
        let granted = try engine.grantApproval(thread: thread, approval: approval, now: now)
        if case .sending = granted.thread.state {
            // expected
        } else {
            XCTFail("Expected sending, got \(granted.thread.state.phaseTitle)")
        }
    }

    func testLaneDefenseNonCommercialLanesNotExchangeSendable() {
        let socialThread = ExchangeThread(
            mode: .relational,
            intent: ExchangeIntent(
                kind: .find,
                mode: .relational,
                queryIntentClass: .socialAffinitySearch,
                title: "Find friends",
                objective: "Connect",
                readiness: .ready
            ),
            posture: .default,
            state: .draftReady(.init(preparedAt: now, summary: "Prepared", draftID: UUID())),
            metadata: ["contact_request_thread": "true"]
        )

        let lane = ExchangeThreadLaneResolver.lane(for: socialThread)
        XCTAssertEqual(lane, ExchangeThreadLane.contactSignal)
        XCTAssertFalse(ApprovedOutboundAlignment.isExchangeSendableLane(lane))

        let dmLane = ExchangeThreadLaneResolver.lane(
            for: socialThread.intent,
            metadata: ["direct_message_thread": "true"]
        )
        XCTAssertEqual(dmLane, ExchangeThreadLane.directMessage)
        XCTAssertFalse(ApprovedOutboundAlignment.isExchangeSendableLane(dmLane))

        XCTAssertTrue(ApprovedOutboundAlignment.isExchangeSendableLane(.commercialInquiry))
        XCTAssertTrue(ApprovedOutboundAlignment.isExchangeSendableLane(.unknown))
    }
}
