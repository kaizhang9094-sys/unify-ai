import Foundation

#if DEBUG

public enum MultilingualSecretaryMatrixVertical: String, Sendable, Hashable, Codable, CaseIterable {
    case roofer
    case cleaner
    case plumber
    case weddingPhotographer
    case dogSeller
    case homeInspector
    case movingCompany
    case renovationContractor
    case postpartumCaregiver
    case electrician
}

public enum MultilingualSecretaryMatrixLanguagePair: String, Sendable, Hashable, Codable, CaseIterable {
    case enUserEnProvider
    case zhUserEnProvider
    case enUserZhProvider
    case zhUserZhProvider
    case mixedUserMixedProvider
}

public struct MultilingualSecretaryMatrixFixture: Sendable, Hashable, Codable {
    public var id: String
    public var vertical: MultilingualSecretaryMatrixVertical
    public var languagePair: MultilingualSecretaryMatrixLanguagePair
    public var userText: String
    public var providerProfileText: String
    public var providerOfferText: String
    public var mockedCanonicalEnglishSearchText: String
    public var mockedProviderCanonicalEnglishRetrievalText: String
    public var expectedObjectType: String
    public var expectedNeed: String
    public var expectedPlace: String
    public var expectedBudgetMax: Int
    public var expectedTimeText: String
    public var expectedRouteClass: String
    public var expectedTargetKind: String
    public var expectedSurfacePreference: String
    public var expectedProviderFacts: [String]
    public var forbiddenMissingFacts: [String]
    public var expectedSelectedOfferID: String
    public var expectedSelectedNodeID: String
    public var forbiddenNoisyNodeID: String
    public var expectedServiceAreas: [String]
    public var expectedEnglishCarrierTokens: [String]
    public var retrievalAxis: Int
    public var originalDisplayTextMustEqualUserText: Bool

    /// Offer ID for the deliberately noisy broader catalog row (see `MultilingualSecretaryMatrixCatalogBuilder`).
    public var forbiddenNoisyOfferID: String {
        "offer-\(forbiddenNoisyNodeID)"
    }

    public init(
        id: String,
        vertical: MultilingualSecretaryMatrixVertical,
        languagePair: MultilingualSecretaryMatrixLanguagePair,
        userText: String,
        providerProfileText: String,
        providerOfferText: String,
        mockedCanonicalEnglishSearchText: String,
        mockedProviderCanonicalEnglishRetrievalText: String,
        expectedObjectType: String,
        expectedNeed: String,
        expectedPlace: String,
        expectedBudgetMax: Int,
        expectedTimeText: String,
        expectedRouteClass: String,
        expectedTargetKind: String,
        expectedSurfacePreference: String,
        expectedProviderFacts: [String],
        forbiddenMissingFacts: [String],
        expectedSelectedOfferID: String,
        expectedSelectedNodeID: String,
        forbiddenNoisyNodeID: String,
        expectedServiceAreas: [String],
        expectedEnglishCarrierTokens: [String],
        retrievalAxis: Int,
        originalDisplayTextMustEqualUserText: Bool = true
    ) {
        self.id = id
        self.vertical = vertical
        self.languagePair = languagePair
        self.userText = userText
        self.providerProfileText = providerProfileText
        self.providerOfferText = providerOfferText
        self.mockedCanonicalEnglishSearchText = mockedCanonicalEnglishSearchText
        self.mockedProviderCanonicalEnglishRetrievalText = mockedProviderCanonicalEnglishRetrievalText
        self.expectedObjectType = expectedObjectType
        self.expectedNeed = expectedNeed
        self.expectedPlace = expectedPlace
        self.expectedBudgetMax = expectedBudgetMax
        self.expectedTimeText = expectedTimeText
        self.expectedRouteClass = expectedRouteClass
        self.expectedTargetKind = expectedTargetKind
        self.expectedSurfacePreference = expectedSurfacePreference
        self.expectedProviderFacts = expectedProviderFacts
        self.forbiddenMissingFacts = forbiddenMissingFacts
        self.expectedSelectedOfferID = expectedSelectedOfferID
        self.expectedSelectedNodeID = expectedSelectedNodeID
        self.forbiddenNoisyNodeID = forbiddenNoisyNodeID
        self.expectedServiceAreas = expectedServiceAreas
        self.expectedEnglishCarrierTokens = expectedEnglishCarrierTokens
        self.retrievalAxis = retrievalAxis
        self.originalDisplayTextMustEqualUserText = originalDisplayTextMustEqualUserText
    }

    public func toMultilingualScenario() -> ExchangeMultilingualRetrievalE2EScenario {
        ExchangeMultilingualRetrievalE2EScenario(
            id: id,
            rawProviderProfileText: providerProfileText,
            rawProviderOfferText: providerOfferText,
            rawUserText: userText,
            expectedObjectTypeTokens: [expectedObjectType],
            expectedPlaceTokens: [expectedPlace.lowercased()],
            expectedBudgetMax: expectedBudgetMax,
            expectedTimeTokens: timeTokens(from: expectedTimeText),
            expectedRouteClass: expectedRouteClass,
            expectedTargetKind: expectedTargetKind,
            expectedSurfacePreference: expectedSurfacePreference,
            expectedSelectedNodeID: expectedSelectedNodeID,
            expectedSelectedOfferID: expectedSelectedOfferID,
            forbiddenNoisyNodeID: forbiddenNoisyNodeID,
            forbiddenMissingFactCategories: forbiddenMissingFacts,
            expectedEnglishCarrierTokens: expectedEnglishCarrierTokens,
            expectedObjectLaneActive: false
        )
    }

    private func timeTokens(from text: String) -> [String] {
        let lowered = text.lowercased()
        var tokens = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if lowered.contains("tomorrow") { tokens.append("tomorrow") }
        if lowered.contains("saturday") { tokens.append("saturday") }
        if lowered.contains("friday") { tokens.append("friday") }
        if lowered.contains("week") { tokens.append("week") }
        if lowered.contains("month") { tokens.append("month") }
        return Array(Set(tokens)).sorted()
    }
}

#endif
