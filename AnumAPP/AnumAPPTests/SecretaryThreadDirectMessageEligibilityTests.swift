import XCTest
import AnumCore
@testable import AnumAPP

@MainActor
final class SecretaryThreadDirectMessageEligibilityTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_730_000_000)

    func test_selectedCounterpartyWithProfile_canShowMessage() {
        let tid = UUID()
        let nodeID = "fixture-node-1"
        let profile = ExchangePublicNodeProfile(id: "pub-1", nodeID: "n1", counterpartyID: nodeID)
        let cp = ExchangeCounterparty(
            id: nodeID,
            kind: .person,
            displayName: "Alex",
            source: .manualEntry,
            publicProfile: profile
        )
        let thread = baseThread(
            id: tid,
            selectedCounterpartyID: nodeID,
            state: .awaitingResponse(.init(since: t0))
        )
        let detail = makeDetail(thread: thread, counterparties: [cp])
        XCTAssertEqual(SecretaryProjectionEngine.resolvedTrustedNodeIDForManualMessage(for: detail), nodeID)
        XCTAssertTrue(SecretaryProjectionEngine.canShowDirectMessageToTrustedNode(for: detail))
    }

    func test_noCounterparty_hidesMessage() {
        let tid = UUID()
        let thread = baseThread(id: tid, selectedCounterpartyID: nil, state: .draftReady(.init(preparedAt: t0, summary: "x")))
        let detail = makeDetail(thread: thread, counterparties: [])
        XCTAssertNil(SecretaryProjectionEngine.resolvedTrustedNodeIDForManualMessage(for: detail))
        XCTAssertFalse(SecretaryProjectionEngine.canShowDirectMessageToTrustedNode(for: detail))
    }

    func test_matchCounterpartyWhenThreadSelectedNil_resolvesNodeID() {
        let tid = UUID()
        let nodeID = "fixture-node-2"
        let profileID = "pub-prof-2"
        let profile = ExchangePublicNodeProfile(id: profileID, nodeID: "n2", counterpartyID: nodeID)
        let cp = ExchangeCounterparty(
            id: nodeID,
            kind: .person,
            displayName: "Blake",
            source: .manualEntry,
            publicProfile: profile
        )
        let thread = ExchangeThread(
            id: tid,
            createdAt: t0,
            updatedAt: t0,
            mode: .transactional,
            intent: fixtureIntent(),
            posture: ExchangePosture(),
            state: .matchFound(
                .init(
                    foundAt: t0,
                    candidateCount: 1,
                    summary: "m",
                    selectedPublicProfileID: profileID
                )
            ),
            selectedCounterpartyID: nil,
            selectedPublicProfileID: profileID
        )
        let match = ExchangeMatch(
            threadID: tid,
            counterpartyID: nodeID,
            publicProfileID: profileID,
            strength: .strong,
            score: 0.9
        )
        let detail = makeDetail(thread: thread, matches: [match], counterparties: [cp])
        XCTAssertEqual(SecretaryProjectionEngine.resolvedTrustedNodeIDForManualMessage(for: detail), nodeID)
        XCTAssertTrue(SecretaryProjectionEngine.canShowDirectMessageToTrustedNode(for: detail))
    }

    func test_resolvedCounterpartyWithoutPublicProfile_hidesMessage() {
        let tid = UUID()
        let nodeID = "fixture-node-3"
        let cp = ExchangeCounterparty(
            id: nodeID,
            kind: .person,
            displayName: "Casey",
            source: .manualEntry,
            publicProfile: nil
        )
        let thread = baseThread(id: tid, selectedCounterpartyID: nodeID, state: .draftReady(.init(preparedAt: t0, summary: "x")))
        let detail = makeDetail(thread: thread, counterparties: [cp])
        XCTAssertEqual(SecretaryProjectionEngine.resolvedTrustedNodeIDForManualMessage(for: detail), nodeID)
        XCTAssertFalse(SecretaryProjectionEngine.canShowDirectMessageToTrustedNode(for: detail))
    }

    func test_archivedThread_hidesMessage() {
        let tid = UUID()
        let nodeID = "fixture-node-4"
        let profile = ExchangePublicNodeProfile(id: "pub-4", nodeID: "n4", counterpartyID: nodeID)
        let cp = ExchangeCounterparty(
            id: nodeID,
            kind: .person,
            displayName: "Dana",
            source: .manualEntry,
            publicProfile: profile
        )
        var thread = baseThread(id: tid, selectedCounterpartyID: nodeID, state: .awaitingResponse(.init(since: t0)))
        thread.metadata["archived"] = "true"
        let detail = makeDetail(thread: thread, counterparties: [cp])
        XCTAssertFalse(SecretaryProjectionEngine.canShowDirectMessageToTrustedNode(for: detail))
    }

    func test_resolvedTerminalState_hidesMessage() {
        let tid = UUID()
        let nodeID = "fixture-node-5"
        let profile = ExchangePublicNodeProfile(id: "pub-5", nodeID: "n5", counterpartyID: nodeID)
        let cp = ExchangeCounterparty(
            id: nodeID,
            kind: .person,
            displayName: "Ellis",
            source: .manualEntry,
            publicProfile: profile
        )
        let thread = baseThread(
            id: tid,
            selectedCounterpartyID: nodeID,
            state: .resolved(.init(resolvedAt: t0, summary: "Done"))
        )
        let detail = makeDetail(thread: thread, counterparties: [cp])
        XCTAssertFalse(SecretaryProjectionEngine.canShowDirectMessageToTrustedNode(for: detail))
    }

    // MARK: - Fixtures

    private func baseThread(
        id: UUID,
        selectedCounterpartyID: String?,
        state: ExchangeState
    ) -> ExchangeThread {
        ExchangeThread(
            id: id,
            createdAt: t0,
            updatedAt: t0,
            mode: .transactional,
            intent: fixtureIntent(),
            posture: ExchangePosture(),
            state: state,
            selectedCounterpartyID: selectedCounterpartyID
        )
    }

    private func fixtureIntent() -> ExchangeIntent {
        ExchangeIntent(
            kind: .message,
            mode: .transactional,
            queryIntentClass: .directOutreach,
            title: "Fixture",
            objective: "Fixture objective",
            readiness: .ready,
            interpretationConfidence: 1.0
        )
    }

    private func makeDetail(
        thread: ExchangeThread,
        turns: [ExchangeTurn] = [],
        approvals: [ExchangeApproval] = [],
        drafts: [ExchangeMessageDraft] = [],
        matches: [ExchangeMatch] = [],
        counterparties: [ExchangeCounterparty] = []
    ) -> ExchangeModels.ThreadDetail {
        ExchangeModels.ThreadDetail(
            thread: thread,
            turns: turns,
            approvals: approvals,
            drafts: drafts,
            matches: matches,
            counterparties: counterparties,
            artifacts: [],
            summary: "Fixture"
        )
    }
}
