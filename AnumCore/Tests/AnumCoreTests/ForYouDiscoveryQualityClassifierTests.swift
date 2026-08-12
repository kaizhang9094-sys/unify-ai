import XCTest
@testable import AnumCore

final class ForYouDiscoveryQualityClassifierTests: XCTestCase {

    private func item(
        id: String,
        score: Double?,
        headline: String? = "Headline",
        publicProfileID: String? = "pp-1",
        factCount: Int = 2,
        canContact: Bool = true
    ) -> ExchangeModels.ForYouItem {
        let lines = (0..<factCount).map { "Fact line \($0)" }
        return ExchangeModels.ForYouItem(
            id: id,
            displayName: "DN",
            headline: headline,
            matchReasonSummary: nil,
            accessMode: "direct",
            dominantTags: ["t"],
            topOfferTitle: nil,
            nodeID: id,
            publicProfileID: publicProfileID,
            acceptingInbound: true,
            discoveredAt: Date(timeIntervalSince1970: 1_700_000_000),
            canAutonomouslyContact: canContact,
            blockedReason: nil,
            linkedThreadID: nil,
            primaryImageURL: nil,
            surfacedOfferImageURLs: [],
            publicOfferContactInfo: nil,
            discoveryMatchedTerms: [],
            discoveryFactLines: lines,
            publicFactLines: [],
            suggestedBuyerInputHints: [],
            retrievalFitScore: score,
            discoverySourceLabel: "Directory"
        )
    }

    func testEmpty_mixedZero_rawHigh_returnsEmptyTier() {
        let q = ForYouDiscoveryQualityClassifier.classify(
            ForYouDiscoveryQualityInputs(
                rawDirectoryMatchCount: 8,
                afterLocalFilterCount: 3,
                mixedItemCount: 0,
                mixedItems: [],
                mixQualitySummary: nil,
                directoryClientUnavailable: false
            )
        )
        XCTAssertEqual(q.tier, .empty)
        XCTAssertEqual(q.resultCount, 0)
    }

    func testSparse_mixedZero_rawLow_returnsSparse() {
        let q = ForYouDiscoveryQualityClassifier.classify(
            ForYouDiscoveryQualityInputs(
                rawDirectoryMatchCount: 2,
                afterLocalFilterCount: 1,
                mixedItemCount: 0,
                mixedItems: [],
                mixQualitySummary: nil,
                directoryClientUnavailable: false
            )
        )
        XCTAssertEqual(q.tier, .sparse)
    }

    func testWeak_lowScoreThinMix() {
        let items = [
            item(id: "a", score: 10, headline: nil, publicProfileID: nil, factCount: 0, canContact: false),
            item(id: "b", score: 11, headline: nil, publicProfileID: nil, factCount: 0, canContact: false)
        ]
        let q = ForYouDiscoveryQualityClassifier.classify(
            ForYouDiscoveryQualityInputs(
                rawDirectoryMatchCount: 4,
                afterLocalFilterCount: 2,
                mixedItemCount: items.count,
                mixedItems: items,
                mixQualitySummary: "test",
                directoryClientUnavailable: false
            )
        )
        XCTAssertEqual(q.tier, .weak)
    }

    func testStrong_enoughItemsAndScores() {
        let items = (0..<4).map { i in
            item(id: "n\(i)", score: 40 + Double(i), headline: "H\(i)", publicProfileID: "p\(i)", factCount: 2, canContact: true)
        }
        let q = ForYouDiscoveryQualityClassifier.classify(
            ForYouDiscoveryQualityInputs(
                rawDirectoryMatchCount: 10,
                afterLocalFilterCount: 4,
                mixedItemCount: items.count,
                mixedItems: items,
                mixQualitySummary: nil,
                directoryClientUnavailable: false
            )
        )
        XCTAssertEqual(q.tier, .strong)
    }

    func testDirectoryUnavailable_returnsEmptyTierSoftCopy() {
        let q = ForYouDiscoveryQualityClassifier.classify(
            ForYouDiscoveryQualityInputs(
                rawDirectoryMatchCount: 0,
                afterLocalFilterCount: 0,
                mixedItemCount: 0,
                mixedItems: [],
                mixQualitySummary: nil,
                directoryClientUnavailable: true
            )
        )
        XCTAssertEqual(q.tier, .empty)
        XCTAssertEqual(q.weakReason, "no_directory_client")
    }
}
