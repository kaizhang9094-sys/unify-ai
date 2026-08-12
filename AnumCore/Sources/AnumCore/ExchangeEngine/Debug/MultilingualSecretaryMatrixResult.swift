import Foundation

#if DEBUG

public struct MultilingualSecretaryMatrixRunResult: Sendable, Hashable, Codable {
    public var fixtureID: String
    public var vertical: String
    public var languagePair: String
    public var passed: Bool
    public var failureReasons: [String]
    public var selectedOfferID: String?
    public var selectedCandidateID: String?
    public var topCandidates: [MultilingualE2ERetrievedCandidateRow]
    public var canonicalEnglishSearchText: String?
    public var providerCanonicalEnglishRetrievalText: String?
    public var offerObjectUsesEnglishProjection: Bool
    public var serviceAreas: [String]
    public var forbiddenMissingFactsTriggered: [String]
    public var displaySearchQuery: String?
    public var capturedRequestText: String?

    public init(
        fixtureID: String,
        vertical: String,
        languagePair: String,
        passed: Bool,
        failureReasons: [String],
        selectedOfferID: String?,
        selectedCandidateID: String?,
        topCandidates: [MultilingualE2ERetrievedCandidateRow],
        canonicalEnglishSearchText: String?,
        providerCanonicalEnglishRetrievalText: String?,
        offerObjectUsesEnglishProjection: Bool,
        serviceAreas: [String],
        forbiddenMissingFactsTriggered: [String],
        displaySearchQuery: String?,
        capturedRequestText: String?
    ) {
        self.fixtureID = fixtureID
        self.vertical = vertical
        self.languagePair = languagePair
        self.passed = passed
        self.failureReasons = failureReasons
        self.selectedOfferID = selectedOfferID
        self.selectedCandidateID = selectedCandidateID
        self.topCandidates = topCandidates
        self.canonicalEnglishSearchText = canonicalEnglishSearchText
        self.providerCanonicalEnglishRetrievalText = providerCanonicalEnglishRetrievalText
        self.offerObjectUsesEnglishProjection = offerObjectUsesEnglishProjection
        self.serviceAreas = serviceAreas
        self.forbiddenMissingFactsTriggered = forbiddenMissingFactsTriggered
        self.displaySearchQuery = displaySearchQuery
        self.capturedRequestText = capturedRequestText
    }
}

public struct MultilingualSecretaryMatrixBatchResult: Sendable, Hashable, Codable {
    public var runs: [MultilingualSecretaryMatrixRunResult]
    public var passCount: Int
    public var failCount: Int

    public init(runs: [MultilingualSecretaryMatrixRunResult]) {
        self.runs = runs
        self.passCount = runs.filter(\.passed).count
        self.failCount = runs.count - passCount
    }
}

#endif
