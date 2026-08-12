import XCTest
@testable import AnumCore

final class ForYouResultMixerCoreTests: XCTestCase {

    private func forYouItem(
        id: String,
        nodeID: String,
        dominantTags: [String],
        retrievalFitScore: Double?,
        discoveryMatchedTerms: [String] = [],
        discoveryFactLines: [String] = [],
        headline: String? = nil,
        canAutonomouslyContact: Bool = false,
        acceptingInbound: Bool = true
    ) -> ExchangeModels.ForYouItem {
        ExchangeModels.ForYouItem(
            id: id,
            displayName: "DN-\(id)",
            headline: headline,
            matchReasonSummary: nil,
            accessMode: "direct",
            dominantTags: dominantTags,
            topOfferTitle: nil,
            nodeID: nodeID,
            publicProfileID: "pp-\(id)",
            acceptingInbound: acceptingInbound,
            discoveredAt: Date(timeIntervalSince1970: 1_700_000_000),
            canAutonomouslyContact: canAutonomouslyContact,
            blockedReason: nil,
            linkedThreadID: nil,
            primaryImageURL: nil,
            surfacedOfferImageURLs: [],
            publicOfferContactInfo: nil,
            discoveryMatchedTerms: discoveryMatchedTerms,
            discoveryFactLines: discoveryFactLines,
            publicFactLines: [],
            suggestedBuyerInputHints: [],
            retrievalFitScore: retrievalFitScore,
            discoverySourceLabel: "Directory"
        )
    }

    func testServerDominance_strongServerWeakLocal_keepsStrongerFirst_balanced() {
        let viewer = ForYouViewerMixSignals(
            interestTags: ["photo", "studio"],
            openToTags: [],
            regionTags: [],
            directoryTags: []
        )
        let weakLocal = forYouItem(
            id: "b",
            nodeID: "b",
            dominantTags: ["photo", "studio"],
            retrievalFitScore: 12,
            discoveryMatchedTerms: ["photo", "studio"],
            headline: "Photo lover"
        )
        let strongServer = forYouItem(
            id: "a",
            nodeID: "a",
            dominantTags: ["unrelated"],
            retrievalFitScore: 96,
            discoveryMatchedTerms: [],
            headline: nil
        )
        let items = [weakLocal, strongServer]
        let out = ForYouResultMixer.mix(
            items: items,
            viewer: viewer,
            localNodeID: nil,
            activeUnresolvedCounterpartyIDs: [],
            context: .init(mode: .balanced)
        )
        XCTAssertEqual(out.items.map(\.id), ["a", "b"], "Higher retrievalFitScore should stay ahead despite weaker local overlap.")
    }

    func testWeakLocalDoesNotBuryMuchStrongerServerCandidate() {
        let viewer = ForYouViewerMixSignals(
            interestTags: ["alpha", "beta"],
            openToTags: ["gamma"],
            regionTags: [],
            directoryTags: ["alpha"]
        )
        let strongLate = forYouItem(
            id: "late-strong",
            nodeID: "late-strong",
            dominantTags: ["other"],
            retrievalFitScore: 99,
            discoveryMatchedTerms: [],
            headline: nil
        )
        let weakEarly = forYouItem(
            id: "early-weak",
            nodeID: "early-weak",
            dominantTags: ["alpha", "beta", "gamma"],
            retrievalFitScore: 8,
            discoveryMatchedTerms: ["alpha", "beta"],
            headline: "alpha beta headline"
        )
        let items = [weakEarly, strongLate]
        let out = ForYouResultMixer.mix(
            items: items,
            viewer: viewer,
            localNodeID: nil,
            activeUnresolvedCounterpartyIDs: [],
            context: .init(mode: .balanced)
        )
        XCTAssertEqual(out.items.first?.id, "late-strong")
    }

    func testNearTieDiversity_threeCloseScores_duplicateKeyPairRetained() {
        let viewer = ForYouViewerMixSignals(interestTags: [], openToTags: [], regionTags: [], directoryTags: [])
        let dupA = forYouItem(id: "d1", nodeID: "d1", dominantTags: ["samekey"], retrievalFitScore: 80.0)
        let dupB = forYouItem(id: "d2", nodeID: "d2", dominantTags: ["samekey"], retrievalFitScore: 79.99)
        let altC = forYouItem(id: "d3", nodeID: "d3", dominantTags: ["otherkey"], retrievalFitScore: 79.98)
        let items = [dupA, dupB, altC]
        let out = ForYouResultMixer.mix(
            items: items,
            viewer: viewer,
            localNodeID: nil,
            activeUnresolvedCounterpartyIDs: [],
            context: .init(mode: .balanced)
        )
        XCTAssertEqual(out.items.count, 3)
        let ids = Set(out.items.map(\.id))
        XCTAssertEqual(ids, Set(["d1", "d2", "d3"]))
        XCTAssertEqual(out.items.first?.id, "d1", "Strongest server-ranked row should stay first when scores are tight.")
    }

    func testDismissedFiltering_removesDismissedNode() {
        let a = forYouItem(id: "a", nodeID: "a", dominantTags: ["x"], retrievalFitScore: 50)
        let b = forYouItem(id: "b", nodeID: "b", dominantTags: ["y"], retrievalFitScore: 40)
        let out = ForYouResultMixer.mix(
            items: [a, b],
            viewer: ForYouViewerMixSignals(interestTags: [], openToTags: [], regionTags: []),
            localNodeID: nil,
            activeUnresolvedCounterpartyIDs: [],
            context: .init(dismissedNodeIDs: ["b"])
        )
        XCTAssertEqual(out.items.map(\.id), ["a"])
    }

    func testPreviouslySeen_affectsFreshChipWhenModeNewFaces() {
        let fresh = forYouItem(id: "fresh", nodeID: "fresh", dominantTags: ["t"], retrievalFitScore: 70, headline: "H")
        let seen = forYouItem(id: "seen", nodeID: "seen", dominantTags: ["t"], retrievalFitScore: 71, headline: "H2")
        let out = ForYouResultMixer.mix(
            items: [seen, fresh],
            viewer: ForYouViewerMixSignals(interestTags: ["t"], openToTags: [], regionTags: []),
            localNodeID: nil,
            activeUnresolvedCounterpartyIDs: [],
            context: .init(mode: .newFaces, previouslySeenForYouNodeIDs: ["seen"])
        )
        let freshChips = out.reasonChipsByItemID["fresh"] ?? []
        XCTAssertTrue(freshChips.contains("Fresh suggestion"), "Unseen node should be eligible for fresh chip when history is non-empty.")
        let seenChips = out.reasonChipsByItemID["seen"] ?? []
        XCTAssertFalse(seenChips.contains("Fresh suggestion"))
    }

    func testEmptyInput_returnsEmptyOutput() {
        let out = ForYouResultMixer.mix(
            items: [],
            viewer: ForYouViewerMixSignals(interestTags: [], openToTags: [], regionTags: []),
            localNodeID: nil,
            activeUnresolvedCounterpartyIDs: []
        )
        XCTAssertTrue(out.items.isEmpty)
        XCTAssertTrue(out.reasonChipsByItemID.isEmpty)
    }
}
