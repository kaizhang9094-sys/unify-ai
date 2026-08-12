import Foundation
import XCTest
import AnumCore
@testable import AnumAPP

/// Latest-search vs priority/current-work picker behavior for Dashboard strip and Threads → Recent.
@MainActor
final class ExchangeLatestSearchPickerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let tNew = Date(timeIntervalSinceReferenceDate: 800_000_100)
    private let tOld = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - A) New search beats older pending (latest vs priority)

    func test_pickLatestSearchResultItem_prefersNewerSearching_overOlderPendingApproval() {
        let olderID = UUID()
        let newerID = UUID()
        let items = [
            searchInboxItem(
                threadID: olderID,
                title: "Older pending",
                state: .awaitingApproval(.init(summary: "Approve")),
                updatedAt: tOld,
                hasPendingApproval: true
            ),
            searchInboxItem(
                threadID: newerID,
                title: "Newer search",
                state: .searching(.init(startedAt: tNew)),
                updatedAt: tNew,
                shouldDiscover: true
            )
        ]

        let latest = SecretarySearchResultProjection.pickLatestSearchResultItem(from: items)
        XCTAssertEqual(latest?.threadID, newerID)

        let current = SecretarySearchResultProjection.pickCurrentSearchResultItem(from: items)
        XCTAssertEqual(current?.threadID, olderID)
    }

    // MARK: - B) Preferred thread when eligible

    func test_pickLatestSearchResultItem_prefersPreferredThreadWhenEligible() {
        let preferredID = UUID()
        let otherID = UUID()
        let items = [
            searchInboxItem(
                threadID: otherID,
                title: "Other",
                state: .searching(.init(startedAt: tNew)),
                updatedAt: tNew,
                shouldDiscover: true
            ),
            searchInboxItem(
                threadID: preferredID,
                title: "Preferred",
                state: .searching(.init(startedAt: tOld)),
                updatedAt: tOld,
                shouldDiscover: true
            )
        ]

        let picked = SecretarySearchResultProjection.pickLatestSearchResultItem(
            from: items,
            preferredThreadID: preferredID
        )
        XCTAssertEqual(picked?.threadID, preferredID)
    }

    // MARK: - C) Same updatedAt — state rank / preferred tie-break

    func test_pickLatestSearchResultItem_sameUpdatedAt_usesStateRankTieBreak() {
        let pendingID = UUID()
        let searchingID = UUID()
        let items = [
            searchInboxItem(
                threadID: pendingID,
                title: "Pending",
                state: .awaitingApproval(.init(summary: "Approve")),
                updatedAt: t0,
                hasPendingApproval: true
            ),
            searchInboxItem(
                threadID: searchingID,
                title: "Searching",
                state: .searching(.init(startedAt: t0)),
                updatedAt: t0,
                shouldDiscover: true
            )
        ]

        let picked = SecretarySearchResultProjection.pickLatestSearchResultItem(from: items)
        XCTAssertEqual(picked?.threadID, searchingID)
    }

    // MARK: - D) Ineligible threads excluded

    func test_pickLatestSearchResultItem_excludesCandidateCoordinationAndBucketNone() {
        let eligibleID = UUID()
        let coordinationID = UUID()
        let resolvedID = UUID()
        let items = [
            searchInboxItem(
                threadID: eligibleID,
                title: "Eligible search",
                state: .searching(.init(startedAt: tNew)),
                updatedAt: tNew,
                shouldDiscover: true
            ),
            searchInboxItem(
                threadID: coordinationID,
                title: "Child path",
                state: .searching(.init(startedAt: tNew.addingTimeInterval(10))),
                updatedAt: tNew.addingTimeInterval(10),
                shouldDiscover: true,
                threadRole: .candidateCoordination
            ),
            searchInboxItem(
                threadID: resolvedID,
                title: "Resolved none",
                state: .resolved(.init(resolvedAt: tNew.addingTimeInterval(20), summary: "Done")),
                updatedAt: tNew.addingTimeInterval(20)
            )
        ]

        let picked = SecretarySearchResultProjection.pickLatestSearchResultItem(from: items)
        XCTAssertEqual(picked?.threadID, eligibleID)
    }

    // MARK: - E) In-progress empty matches — not no-match recovery

    func test_classifyRecentSessionKind_searchingWithEmptyMatches_isActiveCoordination() {
        let tid = UUID()
        let inbox = searchInboxItem(
            threadID: tid,
            title: "find me a plumber",
            state: .searching(.init(startedAt: t0)),
            updatedAt: t0,
            shouldDiscover: true,
            capturedRequestText: "find me a plumber"
        )
        let detail = ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: tid,
                createdAt: t0,
                updatedAt: t0,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .providerSearch,
                    title: "Find Provider",
                    objective: "find me a plumber",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: .searching(.init(startedAt: t0))
            ),
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: "Searching"
        )

        let kind = SecretarySearchResultProjection.classifyRecentSessionKind(
            inboxItem: inbox,
            detail: detail,
            rankedMatches: []
        )

        XCTAssertEqual(kind, .activeCoordination)
        XCTAssertTrue(SecretarySearchResultProjection.isSearchInProgress(inbox))
    }

    // MARK: - F) Preferred no-match on dashboard strip

    func test_pickLatestSearchResultItem_dashboardStrip_includesPreferredNoMatch_overOlderWeak() {
        let noMatchID = UUID()
        let weakID = UUID()
        let items = [
            searchInboxItem(
                threadID: weakID,
                title: "Older weak search",
                state: .matchCandidatesWeak(.init(
                    candidateCount: 1,
                    explanation: "Weak",
                    suggestedRefinement: nil
                )),
                updatedAt: tOld,
                shouldDiscover: true,
                threadRole: .umbrellaSearch
            ),
            searchInboxItem(
                threadID: noMatchID,
                title: "Find me a piano teacher.",
                state: .noViableMatch(.init(
                    explanation: "No match",
                    suggestedNextStep: "Refine the request or widen the criteria only if you want broader discovery."
                )),
                updatedAt: tNew,
                shouldDiscover: false,
                capturedRequestText: "Find me a piano teacher.",
                threadRole: .umbrellaSearch,
                interpretationNextStep: "Refine the request or widen the criteria only if you want broader discovery."
            )
        ]

        let picked = SecretarySearchResultProjection.pickLatestSearchResultItem(
            from: items,
            preferredThreadID: noMatchID,
            surface: "dashboardStrip"
        )
        XCTAssertEqual(picked?.threadID, noMatchID)
    }

    func test_pickLatestSearchResultItem_threadsRecent_includesNoMatch_overOlderWeak() {
        let noMatchID = UUID()
        let weakID = UUID()
        let items = [
            searchInboxItem(
                threadID: weakID,
                title: "Older weak search",
                state: .matchCandidatesWeak(.init(
                    candidateCount: 1,
                    explanation: "Weak",
                    suggestedRefinement: nil
                )),
                updatedAt: tOld,
                shouldDiscover: true,
                threadRole: .umbrellaSearch
            ),
            searchInboxItem(
                threadID: noMatchID,
                title: "Find me a piano teacher.",
                state: .noViableMatch(.init(
                    explanation: "No match",
                    suggestedNextStep: "Refine the request or widen the criteria only if you want broader discovery."
                )),
                updatedAt: tNew,
                shouldDiscover: false,
                capturedRequestText: "Find me a piano teacher.",
                threadRole: .umbrellaSearch
            )
        ]

        let picked = SecretarySearchResultProjection.pickLatestSearchResultItem(
            from: items,
            preferredThreadID: noMatchID,
            surface: "threadsRecent"
        )
        XCTAssertEqual(picked?.threadID, noMatchID)
    }

    func test_pickLatestSearchResultItem_latestNoMatch_beatsOlderWeak_withoutPreferred() {
        let noMatchID = UUID()
        let weakID = UUID()
        let items = [
            searchInboxItem(
                threadID: weakID,
                title: "Older weak search",
                state: .matchCandidatesWeak(.init(
                    candidateCount: 1,
                    explanation: "Weak",
                    suggestedRefinement: nil
                )),
                updatedAt: tOld,
                shouldDiscover: true,
                threadRole: .umbrellaSearch
            ),
            searchInboxItem(
                threadID: noMatchID,
                title: "Find me a piano teacher.",
                state: .noViableMatch(.init(
                    explanation: "No match",
                    suggestedNextStep: "Refine search or widen scope"
                )),
                updatedAt: tNew,
                shouldDiscover: false,
                capturedRequestText: "Find me a piano teacher.",
                threadRole: .umbrellaSearch
            )
        ]

        let picked = SecretarySearchResultProjection.pickLatestSearchResultItem(
            from: items,
            surface: "dashboardStrip"
        )
        XCTAssertEqual(picked?.threadID, noMatchID)
    }

    // MARK: - Immediate strip override / handoff picker

    func test_buildImmediateStripInboxItem_noViableMatch_mapsToSearchResultBucket() {
        let tid = UUID()
        let detail = threadDetail(
            threadID: tid,
            state: .noViableMatch(.init(
                searchedAt: tNew,
                explanation: "No match",
                suggestedNextStep: "Refine search or widen scope"
            )),
            summary: "No piano teachers found"
        )
        let item = SecretarySearchResultProjection.buildImmediateStripInboxItem(
            detail: detail,
            capturedRequestText: "Find me a piano teacher."
        )
        XCTAssertEqual(item.threadID, tid)
        XCTAssertEqual(item.capturedRequestText, "Find me a piano teacher.")
        XCTAssertEqual(
            SecretaryProjectionEngine.bucket(for: item),
            .searchResult
        )
        XCTAssertEqual(SecretaryProjectionEngine.interactionPolicy(for: item), .terminalSearchReceipt)
        XCTAssertFalse(SecretaryProjectionEngine.isOperationalThreadOpenAllowed(item))
    }

    func test_pickLatestSearchResultItem_dashboardStrip_prefersPreferredNoMatchDuringHandoff() {
        let noMatchID = UUID()
        let weakID = UUID()
        let items = [
            searchInboxItem(
                threadID: weakID,
                title: "Older weak search",
                state: .matchCandidatesWeak(.init(
                    candidateCount: 1,
                    explanation: "Weak",
                    suggestedRefinement: nil
                )),
                updatedAt: tNew.addingTimeInterval(100),
                shouldDiscover: true,
                threadRole: .umbrellaSearch
            ),
            searchInboxItem(
                threadID: noMatchID,
                title: "Find me a piano teacher.",
                state: .noViableMatch(.init(
                    explanation: "No match",
                    suggestedNextStep: "Refine search or widen scope"
                )),
                updatedAt: tNew,
                shouldDiscover: false,
                capturedRequestText: "Find me a piano teacher.",
                threadRole: .umbrellaSearch
            )
        ]

        let picked = SecretarySearchResultProjection.pickLatestSearchResultItem(
            from: items,
            preferredThreadID: noMatchID,
            surface: "dashboardStrip",
            preferPreferredWhenEligible: true
        )
        XCTAssertEqual(picked?.threadID, noMatchID)
    }

    func test_shouldClearLocalStripOverride_whenSnapshotContainsSameNoMatchState() {
        let tid = UUID()
        let override = searchInboxItem(
            threadID: tid,
            title: "Find me a piano teacher.",
            state: .noViableMatch(.init(explanation: "No match")),
            updatedAt: tNew,
            capturedRequestText: "Find me a piano teacher.",
            threadRole: .umbrellaSearch
        )
        let snapshot = [
            searchInboxItem(
                threadID: tid,
                title: "Find me a piano teacher.",
                state: .noViableMatch(.init(explanation: "No match")),
                updatedAt: tNew,
                capturedRequestText: "Find me a piano teacher.",
                threadRole: .umbrellaSearch
            )
        ]
        XCTAssertTrue(
            SecretarySearchResultProjection.shouldClearLocalStripOverride(
                overrideItem: override,
                snapshotThreads: snapshot
            )
        )
    }

    func test_shouldClearLocalStripOverride_falseWhenSnapshotMissingThread() {
        let override = searchInboxItem(
            threadID: UUID(),
            title: "Find me a piano teacher.",
            state: .noViableMatch(.init(explanation: "No match")),
            updatedAt: tNew,
            capturedRequestText: "Find me a piano teacher.",
            threadRole: .umbrellaSearch
        )
        XCTAssertFalse(
            SecretarySearchResultProjection.shouldClearLocalStripOverride(
                overrideItem: override,
                snapshotThreads: []
            )
        )
    }

    private func threadDetail(
        threadID: ExchangeThread.ID,
        state: ExchangeState,
        summary: String
    ) -> ExchangeModels.ThreadDetail {
        ExchangeModels.ThreadDetail(
            thread: ExchangeThread(
                id: threadID,
                createdAt: t0,
                updatedAt: tNew,
                mode: .transactional,
                intent: ExchangeIntent(
                    kind: .message,
                    mode: .transactional,
                    queryIntentClass: .providerSearch,
                    title: "Find Provider",
                    objective: "Find me a piano teacher.",
                    readiness: .ready,
                    interpretationConfidence: 1.0
                ),
                posture: ExchangePosture(),
                state: state,
                interpretation: .init(
                    userQuestion: "Find me a piano teacher.",
                    userNextStep: "Refine search or widen scope",
                    shouldDiscover: false
                )
            ),
            turns: [],
            approvals: [],
            drafts: [],
            matches: [],
            counterparties: [],
            artifacts: [],
            summary: summary
        )
    }

    // MARK: - Fixtures

    private func searchInboxItem(
        threadID: ExchangeThread.ID,
        title: String,
        state: ExchangeState,
        updatedAt: Date,
        shouldDiscover: Bool = false,
        hasPendingApproval: Bool = false,
        capturedRequestText: String? = nil,
        threadRole: ExchangeThreadRole = .standalone,
        interpretationNextStep: String? = nil
    ) -> ExchangeModels.InboxItem {
        ExchangeModels.InboxItem(
            threadID: threadID,
            title: title,
            capturedRequestText: capturedRequestText,
            subtitle: "",
            state: state,
            stateTitle: "Fixture",
            updatedAt: updatedAt,
            requiresHumanDecision: false,
            hasFailure: false,
            hasPendingApproval: hasPendingApproval,
            shouldDiscover: shouldDiscover,
            interpretationNextStep: interpretationNextStep,
            threadRole: threadRole
        )
    }
}
