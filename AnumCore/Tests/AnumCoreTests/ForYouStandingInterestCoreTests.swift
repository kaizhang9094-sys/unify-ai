import XCTest
@testable import AnumCore

final class ForYouStandingInterestCoreTests: XCTestCase {

    private func profile(
        id: String = "prof-1",
        nodeID: String = "node-local",
        headline: String? = "Builder headline",
        summary: String? = "Public summary line.",
        interests: [String] = ["ios", "swift"],
        openTo: [String] = ["collaboration"],
        offers: [String] = ["wholesale plumbing catalog"],
        activityTags: [String] = ["founder"],
        regionTags: [String] = ["bay area"],
        semantic: ExchangePublicNodeProfile.SemanticSurface = .init(domains: ["software"], intentKinds: ["product"])
    ) -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: id,
            nodeID: nodeID,
            headline: headline,
            summary: summary,
            interests: interests,
            offers: offers,
            openTo: openTo,
            activityTags: activityTags,
            regionTags: regionTags,
            semantic: semantic
        )
    }

    func testFingerprint_stableForSamePublicFields() {
        let a = profile()
        let b = profile()
        XCTAssertEqual(
            ForYouStandingInterestProfileFingerprint.make(for: a),
            ForYouStandingInterestProfileFingerprint.make(for: b)
        )
    }

    func testFingerprint_changesWhenInterestsOrOpenToChange() {
        let base = profile()
        let changedInterests = profile(interests: ["rust", "swift"])
        XCTAssertNotEqual(
            ForYouStandingInterestProfileFingerprint.make(for: base),
            ForYouStandingInterestProfileFingerprint.make(for: changedInterests)
        )
        let changedOpenTo = profile(openTo: ["investment"])
        XCTAssertNotEqual(
            ForYouStandingInterestProfileFingerprint.make(for: base),
            ForYouStandingInterestProfileFingerprint.make(for: changedOpenTo)
        )
    }

    func testFingerprint_ignoresOffersArray() {
        let p1 = profile(offers: ["only-offers-a"])
        let p2 = profile(offers: ["completely-different-offer-text"])
        XCTAssertEqual(
            ForYouStandingInterestProfileFingerprint.make(for: p1),
            ForYouStandingInterestProfileFingerprint.make(for: p2),
            "Offers are not part of the standing-interest fingerprint canonical string."
        )
    }

    func testSanitizer_rejectsEmptyGarbage() {
        let p = profile(openTo: [])
        let fp = ForYouStandingInterestProfileFingerprint.make(for: p)
        let raw = ForYouStandingInterest(
            queryText: "   ",
            searchTags: [],
            lookingForTags: [],
            interestTags: [],
            roleTags: [],
            regionTags: [],
            excludedTags: [],
            confidence: 0.5,
            generatedAt: Date(),
            sourceProfileFingerprint: fp,
            debugSummary: nil
        )
        XCTAssertNil(ForYouStandingInterestSanitizer.sanitizedForPersist(raw, profile: p, expectedFingerprint: fp))
    }

    func testSanitizer_normalizesTagsTrimsDedupesCapsConfidence() {
        let p = profile()
        let fp = ForYouStandingInterestProfileFingerprint.make(for: p)
        let longToken = String(repeating: "x", count: 90)
        let raw = ForYouStandingInterest(
            queryText: "  hello world  ",
            searchTags: [" Alpha ", "alpha", longToken],
            lookingForTags: [],
            interestTags: [],
            roleTags: [],
            regionTags: [],
            excludedTags: [],
            confidence: 2.5,
            generatedAt: Date(),
            sourceProfileFingerprint: fp,
            debugSummary: nil
        )
        guard let out = ForYouStandingInterestSanitizer.sanitizedForPersist(raw, profile: p, expectedFingerprint: fp) else {
            return XCTFail("expected sanitized output")
        }
        XCTAssertEqual(out.queryText, "hello world")
        XCTAssertEqual(out.searchTags.count, 2)
        XCTAssertEqual(out.searchTags.first?.lowercased(), "alpha")
        XCTAssertEqual(out.searchTags[1].count, ForYouStandingInterestNormalizer.maxTagLength)
        XCTAssertEqual(out.confidence, 1.0)
    }

    func testHeuristicBuilder_usesPublicProfileFieldsOnly_noOfferTextInQuery() {
        let p = profile(
            headline: "Photo studio",
            summary: "Editorial work.",
            interests: ["portraits"],
            openTo: ["collabs"],
            offers: ["commercial lighting rental sku-99999"],
            activityTags: ["photographer"],
            regionTags: ["oakland"],
            semantic: .init(domains: ["creative"], intentKinds: ["provider"])
        )
        let h = ForYouStandingInterestHeuristicBuilder.build(from: p, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(h.queryText.contains("Photo studio"))
        XCTAssertTrue(h.queryText.contains("Editorial"))
        XCTAssertTrue(h.queryText.contains("portraits"))
        XCTAssertTrue(h.queryText.contains("collabs"))
        XCTAssertFalse(h.queryText.localizedCaseInsensitiveContains("sku-99999"))
        XCTAssertFalse(h.queryText.localizedCaseInsensitiveContains("commercial lighting"))
        XCTAssertTrue(h.searchTags.joined(separator: " ").lowercased().contains("photographer"))
        XCTAssertTrue(h.regionTags.contains(where: { $0.lowercased().contains("oakland") }))
    }

    func testSanitizer_mergesProfileOpenToWhenModelLookingForEmpty() {
        let p = profile(
            headline: "Dancing",
            summary: "About line",
            interests: ["Pharmaceutical"],
            openTo: ["Startups", "coder", "selling my house"],
            activityTags: [],
            regionTags: [],
            semantic: .init(domains: [], intentKinds: [])
        )
        let fp = ForYouStandingInterestProfileFingerprint.make(for: p)
        let raw = ForYouStandingInterest(
            queryText: "Dancing",
            searchTags: ["Venture capitalists"],
            lookingForTags: [],
            interestTags: ["Pharmaceutical"],
            roleTags: [],
            regionTags: [],
            excludedTags: [],
            confidence: 0.35,
            generatedAt: Date(),
            sourceProfileFingerprint: fp,
            debugSummary: "llm"
        )
        guard let out = ForYouStandingInterestSanitizer.sanitizedForPersist(raw, profile: p, expectedFingerprint: fp) else {
            return XCTFail("expected merge")
        }
        XCTAssertEqual(
            Set(out.lookingForTags.map { $0.lowercased() }),
            ["startups", "coder", "selling my house"]
        )
        XCTAssertEqual(out.interestTags.map { $0.lowercased() }, ["pharmaceutical"])
    }

    func testSanitizer_mergesProfileOpenToAfterModelCoder_preservesModelOrderFirst() {
        let p = profile(openTo: ["Startups", "selling my house"])
        let fp = ForYouStandingInterestProfileFingerprint.make(for: p)
        let raw = ForYouStandingInterest(
            queryText: "q",
            searchTags: [],
            lookingForTags: ["coder"],
            interestTags: [],
            roleTags: [],
            regionTags: [],
            excludedTags: [],
            confidence: 0.4,
            generatedAt: Date(),
            sourceProfileFingerprint: fp,
            debugSummary: nil
        )
        guard let out = ForYouStandingInterestSanitizer.sanitizedForPersist(raw, profile: p, expectedFingerprint: fp) else {
            return XCTFail("expected merge")
        }
        XCTAssertEqual(out.lookingForTags.first?.lowercased(), "coder")
        XCTAssertTrue(out.lookingForTags.contains { $0.lowercased() == "startups" })
        XCTAssertTrue(out.lookingForTags.contains { $0.lowercased() == "selling my house" })
    }

    func testDirectorySearchQueryText_combinesQueryWithDirectoryAndLookingForTags() {
        let p = profile()
        let fp = ForYouStandingInterestProfileFingerprint.make(for: p)
        let interest = ForYouStandingInterest(
            queryText: "Dancing in the dark",
            searchTags: ["Venture capitalists"],
            lookingForTags: ["Startups", "coder"],
            interestTags: ["Pharmaceutical", "politics"],
            roleTags: [],
            regionTags: ["Newmarket"],
            excludedTags: [],
            confidence: 0.35,
            generatedAt: Date(),
            sourceProfileFingerprint: fp,
            debugSummary: "llm"
        )
        let q = ForYouStandingInterestSanitizer.directorySearchQueryText(from: interest, profile: p)
        XCTAssertTrue(q.hasPrefix("Dancing in the dark."), "expected headline query prefix")
        XCTAssertTrue(q.localizedCaseInsensitiveContains("venture capitalists"))
        XCTAssertTrue(q.localizedCaseInsensitiveContains("pharmaceutical"))
        XCTAssertTrue(q.localizedCaseInsensitiveContains("politics"))
        XCTAssertTrue(q.localizedCaseInsensitiveContains("startups"))
        XCTAssertTrue(q.localizedCaseInsensitiveContains("coder"))
    }

    func testStandingInterestStore_usesV2CacheNamespace() {
        let store = ForYouStandingInterestStore()
        let key = store.debugStorageKey(forNodeID: "node-x")
        XCTAssertTrue(key.contains("forYou.standingInterest.v2."), key)
    }
}
