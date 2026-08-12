import Foundation

#if DEBUG

public struct RetrievalE2ERetrievedDocRow: Sendable, Hashable, Codable {
    public var rank: Int
    public var docKind: String?
    public var surfaceType: String
    public var offerID: String?
    public var counterpartyID: String
    public var finalScore: Double
    public var objectLaneScore: Double?

    public init(
        rank: Int,
        docKind: String?,
        surfaceType: String,
        offerID: String?,
        counterpartyID: String,
        finalScore: Double,
        objectLaneScore: Double?
    ) {
        self.rank = rank
        self.docKind = docKind
        self.surfaceType = surfaceType
        self.offerID = offerID
        self.counterpartyID = counterpartyID
        self.finalScore = finalScore
        self.objectLaneScore = objectLaneScore
    }
}

public struct RetrievalE2ERunSnapshot: Sendable, Hashable, Codable {
    public var runIndex: Int
    public var totalRuns: Int
    public var query: String
    public var scenarioID: String
    public var passed: Bool
    public var failureReasons: [String]
    public var latencyMs: Int
    public var compactLLMOutput: String?
    public var routeClass: String?
    public var surfacePreference: String?
    public var objectType: String?
    public var domainCategory: String?
    public var transactionIntent: String?
    public var retrievalQueryObjectText: String?
    public var objectLaneActive: Bool
    public var discoveryCalled: Bool
    public var emittedDocKinds: [String]
    public var topRetrievedDocs: [RetrievalE2ERetrievedDocRow]
    public var projectedMatchedOfferIDs: [String: [String]]
    public var selectedOfferID: String?
    public var uiCardOfferID: String?
    public var uiSurfaceLead: String?
    public var fullEvaluateApplied: Bool
    public var structuralFailures: [String]
    public var rankingFailures: [String]
    public var strictFailures: [String]
    public var uiFailures: [String]

    public init(
        runIndex: Int,
        totalRuns: Int,
        query: String,
        scenarioID: String,
        passed: Bool,
        failureReasons: [String],
        latencyMs: Int,
        compactLLMOutput: String?,
        routeClass: String?,
        surfacePreference: String?,
        objectType: String?,
        domainCategory: String?,
        transactionIntent: String?,
        retrievalQueryObjectText: String?,
        objectLaneActive: Bool,
        discoveryCalled: Bool,
        emittedDocKinds: [String],
        topRetrievedDocs: [RetrievalE2ERetrievedDocRow],
        projectedMatchedOfferIDs: [String: [String]],
        selectedOfferID: String?,
        uiCardOfferID: String?,
        uiSurfaceLead: String?,
        fullEvaluateApplied: Bool = false,
        structuralFailures: [String] = [],
        rankingFailures: [String] = [],
        strictFailures: [String] = [],
        uiFailures: [String] = []
    ) {
        self.runIndex = runIndex
        self.totalRuns = totalRuns
        self.query = query
        self.scenarioID = scenarioID
        self.passed = passed
        self.failureReasons = failureReasons
        self.latencyMs = latencyMs
        self.compactLLMOutput = compactLLMOutput
        self.routeClass = routeClass
        self.surfacePreference = surfacePreference
        self.objectType = objectType
        self.domainCategory = domainCategory
        self.transactionIntent = transactionIntent
        self.retrievalQueryObjectText = retrievalQueryObjectText
        self.objectLaneActive = objectLaneActive
        self.discoveryCalled = discoveryCalled
        self.emittedDocKinds = emittedDocKinds
        self.topRetrievedDocs = topRetrievedDocs
        self.projectedMatchedOfferIDs = projectedMatchedOfferIDs
        self.selectedOfferID = selectedOfferID
        self.uiCardOfferID = uiCardOfferID
        self.uiSurfaceLead = uiSurfaceLead
        self.fullEvaluateApplied = fullEvaluateApplied
        self.structuralFailures = structuralFailures
        self.rankingFailures = rankingFailures
        self.strictFailures = strictFailures
        self.uiFailures = uiFailures
    }
}

public struct RetrievalE2EBatchResult: Sendable, Hashable, Codable {
    public var runs: [RetrievalE2ERunSnapshot]
    public var aggregateReportText: String
    public var artifactPath: String?

    public init(
        runs: [RetrievalE2ERunSnapshot],
        aggregateReportText: String,
        artifactPath: String?
    ) {
        self.runs = runs
        self.aggregateReportText = aggregateReportText
        self.artifactPath = artifactPath
    }
}

#endif
