import XCTest

@testable import AnumCore

final class ForYouBM25DiagnosticsTests: XCTestCase {

    func testDebugTokenizeMatchesLexicalQueryTokenizationForDirectoryRerankQuery() {
        let query = ForYouRetrievalQueryBuilder.buildForDirectoryRerank(
            queryText: "Looking for a coder to start a venture. Startups, coder",
            directoryTags: [],
            openToTags: [],
            regionTags: [],
            interestTags: [],
            roleTags: [],
            candidateDocumentCount: 4
        )
        let joined = ExchangeBM25Index.lexicalQueryTextForBM25Search(query)
        let tokens = ExchangeBM25Index.debugTokenize(joined)
        XCTAssertTrue(tokens.contains("looking"), "tokens=\(tokens)")
        XCTAssertTrue(tokens.contains("coder"), "tokens=\(tokens)")
        XCTAssertTrue(tokens.contains("start"), "tokens=\(tokens)")
        XCTAssertTrue(tokens.contains("venture"), "tokens=\(tokens)")
        XCTAssertTrue(tokens.contains("startups"), "tokens=\(tokens)")
        XCTAssertFalse(tokens.contains("for"), "stopword 'for' should be removed; tokens=\(tokens)")
    }

    func testBm25HitPresentFalseWhenNodeMissingFromScoreMap() {
        let map: [String: Double] = ["a": 1.0]
        XCTAssertFalse(ForYouClientRetrievalBM25LogSemantics.bm25HitPresent(bestScoreByNode: map, nodeID: "missing"))
    }

    func testBm25RankSourcePositionalFallbackWhenScoreZero() {
        let map = ["n1": 0.0]
        XCTAssertEqual(
            ForYouClientRetrievalBM25LogSemantics.bm25RankSource(
                bestScoreByNode: map,
                nodeID: "n1",
                bm25Rank: 1
            ),
            "positionalFallback"
        )
    }

    func testExactTokenMismatchCoderVsCodersNoOverlap() {
        let q = Set(ExchangeBM25Index.debugTokenize("coder"))
        let d = Set(ExchangeBM25Index.debugTokenize("coders"))
        XCTAssertTrue(q.intersection(d).isEmpty)
    }

    func testExactTokenMismatchStartupVsStartupsNoOverlap() {
        let q = Set(ExchangeBM25Index.debugTokenize("startup"))
        let d = Set(ExchangeBM25Index.debugTokenize("startups"))
        XCTAssertTrue(q.intersection(d).isEmpty)
    }


    func testBm25RankSourceHitWhenScorePositive() {
        let map = ["n1": 0.42]
        XCTAssertEqual(
            ForYouClientRetrievalBM25LogSemantics.bm25RankSource(
                bestScoreByNode: map,
                nodeID: "n1",
                bm25Rank: 2
            ),
            "hit"
        )
    }
}
