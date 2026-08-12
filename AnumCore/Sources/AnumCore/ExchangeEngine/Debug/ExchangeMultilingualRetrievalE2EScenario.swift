import Foundation

#if DEBUG

public struct ExchangeMultilingualRetrievalE2EScenario: Sendable, Hashable {
    public var id: String
    public var rawProviderProfileText: String
    public var rawProviderOfferText: String
    public var rawUserText: String
    public var expectedObjectTypeTokens: [String]
    public var expectedPlaceTokens: [String]
    public var expectedBudgetMax: Int
    public var expectedTimeTokens: [String]
    public var expectedRouteClass: String
    public var expectedTargetKind: String
    public var expectedSurfacePreference: String
    public var expectedSelectedNodeID: String
    public var expectedSelectedOfferID: String
    public var forbiddenNoisyNodeID: String
    public var forbiddenMissingFactCategories: [String]
    public var expectedEnglishCarrierTokens: [String]
    public var expectedObjectLaneActive: Bool

    public init(
        id: String,
        rawProviderProfileText: String,
        rawProviderOfferText: String,
        rawUserText: String,
        expectedObjectTypeTokens: [String],
        expectedPlaceTokens: [String],
        expectedBudgetMax: Int,
        expectedTimeTokens: [String],
        expectedRouteClass: String,
        expectedTargetKind: String,
        expectedSurfacePreference: String,
        expectedSelectedNodeID: String,
        expectedSelectedOfferID: String,
        forbiddenNoisyNodeID: String,
        forbiddenMissingFactCategories: [String],
        expectedEnglishCarrierTokens: [String],
        expectedObjectLaneActive: Bool
    ) {
        self.id = id
        self.rawProviderProfileText = rawProviderProfileText
        self.rawProviderOfferText = rawProviderOfferText
        self.rawUserText = rawUserText
        self.expectedObjectTypeTokens = expectedObjectTypeTokens
        self.expectedPlaceTokens = expectedPlaceTokens
        self.expectedBudgetMax = expectedBudgetMax
        self.expectedTimeTokens = expectedTimeTokens
        self.expectedRouteClass = expectedRouteClass
        self.expectedTargetKind = expectedTargetKind
        self.expectedSurfacePreference = expectedSurfacePreference
        self.expectedSelectedNodeID = expectedSelectedNodeID
        self.expectedSelectedOfferID = expectedSelectedOfferID
        self.forbiddenNoisyNodeID = forbiddenNoisyNodeID
        self.forbiddenMissingFactCategories = forbiddenMissingFactCategories
        self.expectedEnglishCarrierTokens = expectedEnglishCarrierTokens
        self.expectedObjectLaneActive = expectedObjectLaneActive
    }
}

public enum ExchangeMultilingualRetrievalE2EScenarios {
    public static let chineseRoofer = ExchangeMultilingualRetrievalE2EScenario(
        id: "multilingualChineseRoofer",
        rawProviderProfileText: MultilingualRetrievalE2EFixtureBuilder.rawProviderProfileText,
        rawProviderOfferText: MultilingualRetrievalE2EFixtureBuilder.rawProviderOfferText,
        rawUserText: MultilingualRetrievalE2EFixtureBuilder.rawUserText,
        expectedObjectTypeTokens: ["roofer", "roof"],
        expectedPlaceTokens: ["aurora"],
        expectedBudgetMax: 200,
        expectedTimeTokens: ["tomorrow", "2", "pm", "afternoon"],
        expectedRouteClass: "providerSearch",
        expectedTargetKind: "provider",
        expectedSurfacePreference: "offer",
        expectedSelectedNodeID: MultilingualRetrievalE2EFixtureBuilder.NodeID.roofer,
        expectedSelectedOfferID: MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer,
        forbiddenNoisyNodeID: MultilingualRetrievalE2EFixtureBuilder.NodeID.noisyHome,
        forbiddenMissingFactCategories: ["location", "budget", "time"],
        expectedEnglishCarrierTokens: ["roofer", "aurora", "estimate", "200", "tomorrow"],
        expectedObjectLaneActive: false
    )

    public static let mandatory: [ExchangeMultilingualRetrievalE2EScenario] = [chineseRoofer]
}

extension ExchangeRetrievalE2EScenarios {
    /// Bridge to the multilingual scenario for shared retrieval E2E naming.
    public static var multilingualChineseRoofer: ExchangeMultilingualRetrievalE2EScenario {
        ExchangeMultilingualRetrievalE2EScenarios.chineseRoofer
    }
}

#endif
