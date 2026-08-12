import Foundation

#if DEBUG

public struct AppSearchSmokeEngineSnapshot: Sendable, Hashable, Codable {
    public var query: String
    public var scenarioID: String
    public var intentClass: String?
    public var facetsQueryIntentClass: String?
    public var objectType: String?
    public var domainCategory: String?
    public var transactionIntent: String?
    public var objectLaneActive: Bool
    public var discoveryCalled: Bool
    public var responseMode: String
    public var topNodes: [String]
    public var selectedOfferID: String?
    public var matchedOffersByNode: [String: [String]]
    public var provenObjectOfferIDs: [String]
    public var objectEvidenceScoreByOfferID: [String: Double]
    public var topDocKinds: [String]
    public var forbiddenAttachmentViolations: Int
    public var objectLaneFP: Int
    public var objectLaneFN: Int
    public var strictFailures: [String]
    public var serverRoundTripIssues: [String]
}

public struct AppSearchSmokeThreadSnapshot: Sendable, Hashable, Codable {
    public var threadID: String
    public var selectedOfferID: String?
    public var selectedPublicProfileID: String?
    public var selectedCounterpartyID: String?
    public var matchedOffersByNode: [String: [String]]
    public var provenObjectOfferIDs: [String]
    public var topNodes: [String]
}

public struct AppSearchSmokeUIProjectionSnapshot: Sendable, Hashable, Codable {
    public var selectedOfferID: String?
    public var matchedOffersByNode: [String: [String]]
    public var preferredMatchCounterpartyID: String?
    public var preferredMatchOfferID: String?
    public var cardOfferID: String?
    public var visiblePublicProfileID: String?
    public var surfaceLead: String
    public var displaySearchQuery: String?
    public var capturedRequestText: String?
    public var visibleSummary: String?
    public var threadTitle: String?

    public init(
        selectedOfferID: String?,
        matchedOffersByNode: [String: [String]],
        preferredMatchCounterpartyID: String?,
        preferredMatchOfferID: String?,
        cardOfferID: String?,
        visiblePublicProfileID: String?,
        surfaceLead: String,
        displaySearchQuery: String? = nil,
        capturedRequestText: String? = nil,
        visibleSummary: String? = nil,
        threadTitle: String? = nil
    ) {
        self.selectedOfferID = selectedOfferID
        self.matchedOffersByNode = matchedOffersByNode
        self.preferredMatchCounterpartyID = preferredMatchCounterpartyID
        self.preferredMatchOfferID = preferredMatchOfferID
        self.cardOfferID = cardOfferID
        self.visiblePublicProfileID = visiblePublicProfileID
        self.surfaceLead = surfaceLead
        self.displaySearchQuery = displaySearchQuery
        self.capturedRequestText = capturedRequestText
        self.visibleSummary = visibleSummary
        self.threadTitle = threadTitle
    }
}

public struct AppSearchSmokeRunSnapshot: Sendable, Hashable, Codable {
    public var runIndex: Int
    public var totalRuns: Int
    public var query: String
    public var scenarioID: String
    public var serverBaseURL: String
    public var publishGenerationID: String?
    public var strictPassed: Bool
    public var latencyMs: Int
    public var engine: AppSearchSmokeEngineSnapshot
    public var thread: AppSearchSmokeThreadSnapshot
    public var ui: AppSearchSmokeUIProjectionSnapshot
    public var engineVsThreadMismatch: [String]
    public var threadVsUIMismatch: [String]
    public var uiProjectionIssues: [String]
    public var runtimeWiringIssues: [String]
    public var wrongFallbackOfferSelections: Int
    public var observationalTop1PrimaryHit: Bool?
    public var observationalTop1AnyRequiredHit: Bool?
    public var observationalTop3AnyRequiredHit: Bool?
}

public struct AppSearchSmokeBatchResult: Sendable, Hashable, Codable {
    public var runs: [AppSearchSmokeRunSnapshot]
    public var aggregateReportText: String
    public var artifactPath: String?
}

#endif
