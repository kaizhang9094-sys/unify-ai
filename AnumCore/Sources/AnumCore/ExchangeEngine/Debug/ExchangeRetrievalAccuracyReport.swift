import Foundation

public struct ExchangeRetrievalAccuracyScenarioExpectation: Sendable {
    public var id: String
    public var queryLabel: String
    public var expectedSummary: String
    public var objectLaneActive: Bool
    public var requiredInTopK: [String]
    public var forbiddenNodes: [String]
    public var requiredMatchedOffers: [String: [String]]
    public var forbiddenAttachments: [(nodeID: String, offerID: String)]
    public var selectedOfferID: String?
    public var selectedOfferIDMustBeNil: Bool
    public var requiredDocKindsInTopTrace: [ExchangeRetrievalDocument.DocKind]
    public var forbiddenDocKindsFirstRank: [ExchangeRetrievalDocument.DocKind]
    public var maxRankByNode: [String: Int]
    public var requiresAdvanceable: Bool?
    public var allowsWeakOrNone: Bool
    public var topK: Int
    public var category: ScenarioCategory
    /// Narrow top1 target for observational primary accuracy. Defaults to first `requiredInTopK` entry.
    public var primaryExpectedNodeID: String?
    /// Nodes that are acceptable as top1 for observational scoring (defaults to `requiredInTopK`).
    public var acceptableTop1NodeIDs: [String]
    /// Labels equivalent provider swaps for report classification only.
    public var equivalentResultGroupName: String?
    /// Optional override for observational miss classification when heuristics are insufficient.
    public var observationalMissTypeOverride: ObservationalMissClassification?

    public enum ScenarioCategory: String, Sendable, Hashable, Codable {
        case objectLane
        case packageFAQ
        case providerCapability
        case seekingAffinity
        case mixedNoisy
    }

    public init(
        id: String,
        queryLabel: String,
        expectedSummary: String,
        objectLaneActive: Bool,
        requiredInTopK: [String] = [],
        forbiddenNodes: [String] = [],
        requiredMatchedOffers: [String: [String]] = [:],
        forbiddenAttachments: [(nodeID: String, offerID: String)] = [],
        selectedOfferID: String? = nil,
        selectedOfferIDMustBeNil: Bool = false,
        requiredDocKindsInTopTrace: [ExchangeRetrievalDocument.DocKind] = [],
        forbiddenDocKindsFirstRank: [ExchangeRetrievalDocument.DocKind] = [],
        maxRankByNode: [String: Int] = [:],
        requiresAdvanceable: Bool? = nil,
        allowsWeakOrNone: Bool = false,
        topK: Int = 5,
        category: ScenarioCategory,
        primaryExpectedNodeID: String? = nil,
        acceptableTop1NodeIDs: [String] = [],
        equivalentResultGroupName: String? = nil,
        observationalMissTypeOverride: ObservationalMissClassification? = nil
    ) {
        self.id = id
        self.queryLabel = queryLabel
        self.expectedSummary = expectedSummary
        self.objectLaneActive = objectLaneActive
        self.requiredInTopK = requiredInTopK
        self.forbiddenNodes = forbiddenNodes
        self.requiredMatchedOffers = requiredMatchedOffers
        self.forbiddenAttachments = forbiddenAttachments
        self.selectedOfferID = selectedOfferID
        self.selectedOfferIDMustBeNil = selectedOfferIDMustBeNil
        self.requiredDocKindsInTopTrace = requiredDocKindsInTopTrace
        self.forbiddenDocKindsFirstRank = forbiddenDocKindsFirstRank
        self.maxRankByNode = maxRankByNode
        self.requiresAdvanceable = requiresAdvanceable
        self.allowsWeakOrNone = allowsWeakOrNone
        self.topK = topK
        self.category = category
        self.primaryExpectedNodeID = primaryExpectedNodeID
        self.acceptableTop1NodeIDs = acceptableTop1NodeIDs
        self.equivalentResultGroupName = equivalentResultGroupName
        self.observationalMissTypeOverride = observationalMissTypeOverride
    }

    public func resolvedPrimaryExpectedNodeID() -> String? {
        primaryExpectedNodeID ?? requiredInTopK.first
    }

    public func resolvedAcceptableTop1NodeIDs() -> [String] {
        if !acceptableTop1NodeIDs.isEmpty {
            return acceptableTop1NodeIDs
        }
        return requiredInTopK
    }
}

public enum ObservationalMissClassification: String, Sendable, Hashable, Codable, CaseIterable {
    case strictFailure
    case validAlternateRequiredNode
    case equivalentSiblingProvider
    case expectedNodeInTopK
    case docKindOrderingIssue
    case trueTopKMiss
    case serverRoundTripIssue
    case safetyViolation
}

public struct ObservationalMissRecord: Sendable, Hashable, Codable {
    public var scenarioID: String
    public var classification: ObservationalMissClassification
    public var top1NodeID: String?
    public var primaryExpectedNodeID: String?
    public var expectedRank: Int?
    public var safetyImpact: String
    public var detail: String

    public init(
        scenarioID: String,
        classification: ObservationalMissClassification,
        top1NodeID: String?,
        primaryExpectedNodeID: String?,
        expectedRank: Int?,
        safetyImpact: String,
        detail: String
    ) {
        self.scenarioID = scenarioID
        self.classification = classification
        self.top1NodeID = top1NodeID
        self.primaryExpectedNodeID = primaryExpectedNodeID
        self.expectedRank = expectedRank
        self.safetyImpact = safetyImpact
        self.detail = detail
    }
}

public struct ObservationalQualityAssessment: Sendable, Hashable, Codable {
    public var top1NodeID: String?
    public var primaryExpectedNodeID: String?
    public var acceptableTop1NodeIDs: [String]
    public var expectedRankOfPrimary: Int?
    public var top1PrimaryHit: Bool
    public var top1AnyRequiredHit: Bool
    public var top3AnyRequiredHit: Bool
    public var missRecords: [ObservationalMissRecord]
    public var informationalNotes: [String]

    public init(
        top1NodeID: String?,
        primaryExpectedNodeID: String?,
        acceptableTop1NodeIDs: [String],
        expectedRankOfPrimary: Int?,
        top1PrimaryHit: Bool,
        top1AnyRequiredHit: Bool,
        top3AnyRequiredHit: Bool,
        missRecords: [ObservationalMissRecord],
        informationalNotes: [String]
    ) {
        self.top1NodeID = top1NodeID
        self.primaryExpectedNodeID = primaryExpectedNodeID
        self.acceptableTop1NodeIDs = acceptableTop1NodeIDs
        self.expectedRankOfPrimary = expectedRankOfPrimary
        self.top1PrimaryHit = top1PrimaryHit
        self.top1AnyRequiredHit = top1AnyRequiredHit
        self.top3AnyRequiredHit = top3AnyRequiredHit
        self.missRecords = missRecords
        self.informationalNotes = informationalNotes
    }
}

public struct ExchangeRetrievalAccuracyScenarioResult: Sendable, Hashable, Codable {
    public var scenarioID: String
    public var queryLabel: String
    public var passed: Bool
    public var expectedSummary: String
    public var failureReason: String?
    public var actualTopSummaries: [String]
    public var selectedOfferID: String?
    public var matchedOffersByNode: [String: [String]]
    public var objectLaneActive: Bool
    public var provenObjectOfferIDs: [String]
    public var topDocKinds: [String]
    public var topObjectEvidenceScores: [String: Double]
    public var queryContext: ExchangeRetrievalDebugTrace.QueryContext?
    public var directoryRecall: ExchangeRetrievalDebugTrace.DirectoryRecall?

    public init(
        scenarioID: String,
        queryLabel: String,
        passed: Bool,
        expectedSummary: String,
        failureReason: String?,
        actualTopSummaries: [String],
        selectedOfferID: String?,
        matchedOffersByNode: [String: [String]],
        objectLaneActive: Bool,
        provenObjectOfferIDs: [String],
        topDocKinds: [String],
        topObjectEvidenceScores: [String: Double],
        queryContext: ExchangeRetrievalDebugTrace.QueryContext?,
        directoryRecall: ExchangeRetrievalDebugTrace.DirectoryRecall?
    ) {
        self.scenarioID = scenarioID
        self.queryLabel = queryLabel
        self.passed = passed
        self.expectedSummary = expectedSummary
        self.failureReason = failureReason
        self.actualTopSummaries = actualTopSummaries
        self.selectedOfferID = selectedOfferID
        self.matchedOffersByNode = matchedOffersByNode
        self.objectLaneActive = objectLaneActive
        self.provenObjectOfferIDs = provenObjectOfferIDs
        self.topDocKinds = topDocKinds
        self.topObjectEvidenceScores = topObjectEvidenceScores
        self.queryContext = queryContext
        self.directoryRecall = directoryRecall
    }
}

public struct ExchangeRetrievalAccuracyAggregateMetrics: Sendable, Hashable, Codable {
    public var totalScenarios: Int
    public var passedScenarios: Int
    public var top1Accuracy: Double
    public var top3Accuracy: Double
    public var top1PrimaryAccuracy: Double
    public var top1AnyRequiredAccuracy: Double
    public var top3AnyRequiredAccuracy: Double
    public var selectedOfferAccuracy: Double
    public var forbiddenAttachmentViolations: Int
    public var objectLaneFalsePositives: Int
    public var objectLaneFalseNegatives: Int
    public var providerCapabilityPassCount: Int
    public var seekingAffinityPassCount: Int
    public var packageFAQPassCount: Int

    public init(
        totalScenarios: Int,
        passedScenarios: Int,
        top1Accuracy: Double,
        top3Accuracy: Double,
        top1PrimaryAccuracy: Double,
        top1AnyRequiredAccuracy: Double,
        top3AnyRequiredAccuracy: Double,
        selectedOfferAccuracy: Double,
        forbiddenAttachmentViolations: Int,
        objectLaneFalsePositives: Int,
        objectLaneFalseNegatives: Int,
        providerCapabilityPassCount: Int,
        seekingAffinityPassCount: Int,
        packageFAQPassCount: Int
    ) {
        self.totalScenarios = totalScenarios
        self.passedScenarios = passedScenarios
        self.top1Accuracy = top1Accuracy
        self.top3Accuracy = top3Accuracy
        self.top1PrimaryAccuracy = top1PrimaryAccuracy
        self.top1AnyRequiredAccuracy = top1AnyRequiredAccuracy
        self.top3AnyRequiredAccuracy = top3AnyRequiredAccuracy
        self.selectedOfferAccuracy = selectedOfferAccuracy
        self.forbiddenAttachmentViolations = forbiddenAttachmentViolations
        self.objectLaneFalsePositives = objectLaneFalsePositives
        self.objectLaneFalseNegatives = objectLaneFalseNegatives
        self.providerCapabilityPassCount = providerCapabilityPassCount
        self.seekingAffinityPassCount = seekingAffinityPassCount
        self.packageFAQPassCount = packageFAQPassCount
    }
}

public enum ExchangeRetrievalAccuracyReport {
    public static func evaluate(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation,
        rankedCandidates: [ExchangeDiscoveryService.RankedCandidate],
        selectedOfferID: String?,
        objectLaneActive: Bool,
        queryContext: ExchangeRetrievalDebugTrace.QueryContext?,
        directoryRecall: ExchangeRetrievalDebugTrace.DirectoryRecall?,
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow]
    ) -> ExchangeRetrievalAccuracyScenarioResult {
        var failures: [String] = []

        if objectLaneActive != expectation.objectLaneActive {
            failures.append(
                "objectLaneActive expected \(expectation.objectLaneActive) got \(objectLaneActive)"
            )
        }

        let topNodes = rankedCandidates.prefix(expectation.topK).map { $0.candidate.counterparty.id }

        for nodeID in expectation.requiredInTopK {
            if !topNodes.contains(nodeID) {
                failures.append("required node \(nodeID) missing from top \(expectation.topK): \(topNodes)")
            }
        }

        for nodeID in expectation.forbiddenNodes {
            if topNodes.contains(nodeID) {
                failures.append("forbidden node \(nodeID) appeared in top \(expectation.topK)")
            }
        }

        for (nodeID, maxRank) in expectation.maxRankByNode {
            if let index = topNodes.firstIndex(of: nodeID) {
                let rank = index + 1
                if rank > maxRank {
                    failures.append("node \(nodeID) rank \(rank) exceeds max \(maxRank)")
                }
            }
        }

        var matchedOffersByNode: [String: [String]] = [:]
        for ranked in rankedCandidates.prefix(expectation.topK) {
            let nodeID = ranked.candidate.counterparty.id
            let offerIDs = ranked.candidate.matchedOffers.map(\.id)
            if !offerIDs.isEmpty {
                matchedOffersByNode[nodeID] = offerIDs
            }
        }

        for (nodeID, requiredOffers) in expectation.requiredMatchedOffers {
            let actual = Set(matchedOffersByNode[nodeID] ?? [])
            for offerID in requiredOffers where !actual.contains(offerID) {
                failures.append("node \(nodeID) missing required matched offer \(offerID); got \(actual)")
            }
        }

        for forbidden in expectation.forbiddenAttachments {
            let actual = Set(matchedOffersByNode[forbidden.nodeID] ?? [])
            if actual.contains(forbidden.offerID) {
                failures.append("forbidden attachment \(forbidden.offerID) on \(forbidden.nodeID)")
            }
        }

        if expectation.selectedOfferIDMustBeNil {
            if let selectedOfferID {
                failures.append("selectedOfferID must be nil, got \(selectedOfferID)")
            }
        } else if let expectedOffer = expectation.selectedOfferID {
            if selectedOfferID != expectedOffer {
                failures.append("selectedOfferID expected \(expectedOffer), got \(selectedOfferID ?? "nil")")
            }
        }

        let topTrace = Array(rankingTrace.prefix(expectation.topK))
        let topDocKindStrings = topTrace.compactMap(\.docKind)
        for requiredKind in expectation.requiredDocKindsInTopTrace {
            let raw = requiredKind.rawValue
            if !topDocKindStrings.contains(raw) {
                failures.append("required docKind \(raw) missing from top trace")
            }
        }

        if let firstKind = topTrace.first?.docKind {
            for forbiddenKind in expectation.forbiddenDocKindsFirstRank where firstKind == forbiddenKind.rawValue {
                failures.append("forbidden docKind \(forbiddenKind.rawValue) ranked first")
            }
        }

        let provenObjectOfferIDs = rankedCandidates.flatMap { ranked in
            Array(ranked.candidate.provenObjectOfferIDs)
        }
        let uniqueProven = Array(Set(provenObjectOfferIDs)).sorted()

        if let requiresAdvanceable = expectation.requiresAdvanceable {
            let hasAdvanceable = rankedCandidates.contains(where: \.isAdvanceable)
            if requiresAdvanceable && !hasAdvanceable {
                failures.append("expected advanceable candidate, none found")
            }
            if !requiresAdvanceable && hasAdvanceable && !expectation.allowsWeakOrNone {
                failures.append("expected non-advanceable outcome, found advanceable candidate")
            }
        }

        if expectation.allowsWeakOrNone && rankedCandidates.isEmpty {
            // acceptable weak/none path
        } else if rankedCandidates.isEmpty && !expectation.allowsWeakOrNone {
            failures.append("expected candidates, got empty shortlist")
        }

        var topObjectEvidence: [String: Double] = [:]
        for ranked in rankedCandidates.prefix(expectation.topK) {
            for (offerID, score) in ranked.candidate.objectEvidenceScoreByOfferID {
                topObjectEvidence[offerID] = max(topObjectEvidence[offerID] ?? 0, score)
            }
        }

        let actualTopSummaries = rankedCandidates.prefix(expectation.topK).enumerated().map { index, ranked in
            let nodeID = ranked.candidate.counterparty.id
            let offers = ranked.candidate.matchedOffers.map(\.id).joined(separator: ",")
            let docKind = rankingTrace[safe: index]?.docKind ?? "unknown"
            let score = String(format: "%.3f", ranked.candidate.overallScore)
            return "#\(index + 1) node=\(nodeID) offers=[\(offers)] docKind=\(docKind) score=\(score)"
        }

        return ExchangeRetrievalAccuracyScenarioResult(
            scenarioID: expectation.id,
            queryLabel: expectation.queryLabel,
            passed: failures.isEmpty,
            expectedSummary: expectation.expectedSummary,
            failureReason: failures.isEmpty ? nil : failures.joined(separator: "; "),
            actualTopSummaries: actualTopSummaries,
            selectedOfferID: selectedOfferID,
            matchedOffersByNode: matchedOffersByNode,
            objectLaneActive: objectLaneActive,
            provenObjectOfferIDs: uniqueProven,
            topDocKinds: topDocKindStrings,
            topObjectEvidenceScores: topObjectEvidence,
            queryContext: queryContext,
            directoryRecall: directoryRecall
        )
    }

    public static func aggregate(
        expectations: [ExchangeRetrievalAccuracyScenarioExpectation],
        results: [ExchangeRetrievalAccuracyScenarioResult]
    ) -> ExchangeRetrievalAccuracyAggregateMetrics {
        let resultByID = Dictionary(uniqueKeysWithValues: results.map { ($0.scenarioID, $0) })
        var top1PrimaryHits = 0
        var top1AnyRequiredHits = 0
        var top3AnyRequiredHits = 0
        var selectedOfferChecks = 0
        var selectedOfferHits = 0
        var forbiddenViolations = 0
        var olFalsePositives = 0
        var olFalseNegatives = 0
        var providerPass = 0
        var seekingPass = 0
        var packagePass = 0
        var rankingExpectationCount = 0

        for expectation in expectations {
            guard let result = resultByID[expectation.id] else { continue }
            if result.passed {
                switch expectation.category {
                case .providerCapability: providerPass += 1
                case .seekingAffinity: seekingPass += 1
                case .packageFAQ: packagePass += 1
                default: break
                }
            }

            let assessment = observationalAssessment(
                expectation: expectation,
                result: result
            )
            if assessment.primaryExpectedNodeID != nil || !assessment.acceptableTop1NodeIDs.isEmpty {
                rankingExpectationCount += 1
                if assessment.top1PrimaryHit { top1PrimaryHits += 1 }
                if assessment.top1AnyRequiredHit { top1AnyRequiredHits += 1 }
                if assessment.top3AnyRequiredHit { top3AnyRequiredHits += 1 }
            }

            if expectation.selectedOfferID != nil || expectation.selectedOfferIDMustBeNil {
                selectedOfferChecks += 1
                if result.passed || result.selectedOfferID == expectation.selectedOfferID {
                    selectedOfferHits += 1
                }
            }

            if let reason = result.failureReason, reason.contains("forbidden attachment") {
                forbiddenViolations += 1
            }

            if expectation.objectLaneActive {
                if !result.provenObjectOfferIDs.isEmpty && result.selectedOfferID == nil && !expectation.selectedOfferIDMustBeNil {
                    olFalseNegatives += 1
                }
            } else if !result.provenObjectOfferIDs.isEmpty && expectation.category != .objectLane {
                olFalsePositives += 1
            }
        }

        let total = expectations.count
        let passed = results.filter(\.passed).count
        let top1AnyRequired = rankingExpectationCount == 0
            ? 0
            : Double(top1AnyRequiredHits) / Double(rankingExpectationCount)
        let top3AnyRequired = rankingExpectationCount == 0
            ? 0
            : Double(top3AnyRequiredHits) / Double(rankingExpectationCount)
        return ExchangeRetrievalAccuracyAggregateMetrics(
            totalScenarios: total,
            passedScenarios: passed,
            top1Accuracy: top1AnyRequired,
            top3Accuracy: top3AnyRequired,
            top1PrimaryAccuracy: rankingExpectationCount == 0
                ? 0
                : Double(top1PrimaryHits) / Double(rankingExpectationCount),
            top1AnyRequiredAccuracy: top1AnyRequired,
            top3AnyRequiredAccuracy: top3AnyRequired,
            selectedOfferAccuracy: selectedOfferChecks == 0 ? 0 : Double(selectedOfferHits) / Double(selectedOfferChecks),
            forbiddenAttachmentViolations: forbiddenViolations,
            objectLaneFalsePositives: olFalsePositives,
            objectLaneFalseNegatives: olFalseNegatives,
            providerCapabilityPassCount: providerPass,
            seekingAffinityPassCount: seekingPass,
            packageFAQPassCount: packagePass
        )
    }

    public static func printReport(
        results: [ExchangeRetrievalAccuracyScenarioResult],
        metrics: ExchangeRetrievalAccuracyAggregateMetrics
    ) {
        print("\n=== ExchangeRetrievalAccuracyReport ===")
        for result in results {
            let status = result.passed ? "PASS" : "FAIL"
            print("[\(status)] \(result.scenarioID)")
            print("  query: \(result.queryLabel)")
            print("  expected: \(result.expectedSummary)")
            print("  actualTop5:")
            for line in result.actualTopSummaries {
                print("    \(line)")
            }
            print("  selectedOfferID: \(result.selectedOfferID ?? "nil")")
            print("  matchedOffers: \(result.matchedOffersByNode)")
            print("  objectLaneActive: \(result.objectLaneActive)")
            print("  provenObjectOfferIDs: \(result.provenObjectOfferIDs)")
            print("  topDocKinds: \(result.topDocKinds)")
            print("  topObjectEvidence: \(result.topObjectEvidenceScores)")
            if let reason = result.failureReason {
                print("  failureReason: \(reason)")
            }
        }
        print("\n--- Aggregate ---")
        print("passed: \(metrics.passedScenarios)/\(metrics.totalScenarios)")
        print(String(format: "top1PrimaryAccuracy: %.2f", metrics.top1PrimaryAccuracy))
        print(String(format: "top1AnyRequiredAccuracy: %.2f", metrics.top1AnyRequiredAccuracy))
        print(String(format: "top3AnyRequiredAccuracy: %.2f", metrics.top3AnyRequiredAccuracy))
        print(String(format: "top1Accuracy: %.2f", metrics.top1Accuracy))
        print(String(format: "top3Accuracy: %.2f", metrics.top3Accuracy))
        print(String(format: "selectedOfferAccuracy: %.2f", metrics.selectedOfferAccuracy))
        print("forbiddenAttachmentViolations: \(metrics.forbiddenAttachmentViolations)")
        print("objectLaneFalsePositives: \(metrics.objectLaneFalsePositives)")
        print("objectLaneFalseNegatives: \(metrics.objectLaneFalseNegatives)")
        print("providerCapabilityPassCount: \(metrics.providerCapabilityPassCount)")
        print("seekingAffinityPassCount: \(metrics.seekingAffinityPassCount)")
        print("packageFAQPassCount: \(metrics.packageFAQPassCount)")
        print("=== End Report ===\n")
    }

    // MARK: - Tier B strict vs observational

    public static func strictInvariantFailures(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation,
        result: ExchangeRetrievalAccuracyScenarioResult,
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow] = []
    ) -> [String] {
        var failures: [String] = []

        if result.objectLaneActive != expectation.objectLaneActive {
            failures.append(
                "objectLaneActive expected \(expectation.objectLaneActive) got \(result.objectLaneActive)"
            )
        }

        for forbidden in expectation.forbiddenAttachments {
            let actual = Set(result.matchedOffersByNode[forbidden.nodeID] ?? [])
            if actual.contains(forbidden.offerID) {
                failures.append("forbidden attachment \(forbidden.offerID) on \(forbidden.nodeID)")
            }
        }

        if expectation.selectedOfferIDMustBeNil {
            if let selectedOfferID = result.selectedOfferID {
                failures.append("selectedOfferID must be nil, got \(selectedOfferID)")
            }
        } else if let expectedOffer = expectation.selectedOfferID {
            if result.selectedOfferID != expectedOffer {
                failures.append("selectedOfferID expected \(expectedOffer), got \(result.selectedOfferID ?? "nil")")
            }
        }

        if expectation.objectLaneActive {
            if !result.provenObjectOfferIDs.isEmpty,
               result.selectedOfferID == nil,
               !expectation.selectedOfferIDMustBeNil,
               expectation.selectedOfferID != nil {
                failures.append("object-lane false negative: proven offers \(result.provenObjectOfferIDs) but selectedOfferID nil")
            }
        } else if !result.provenObjectOfferIDs.isEmpty {
            failures.append(
                "object-lane false positive: provenObjectOfferIDs=\(result.provenObjectOfferIDs) while object lane inactive"
            )
        }

        let minimumObjectEvidence = ExchangeOfferObjectLane.minimumObjectEvidenceScore
        for row in rankingTrace {
            guard let docKind = row.docKind else { continue }
            guard docKind != ExchangeRetrievalDocument.DocKind.offerObject.rawValue else { continue }
            guard let objectScore = row.objectLaneScore, objectScore >= minimumObjectEvidence else { continue }
            failures.append(
                "non-offer_object docKind=\(docKind) doc=\(row.documentID) objectLaneScore=\(objectScore) proves object evidence"
            )
        }

        return failures
    }

    public static func observationalAssessment(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation,
        result: ExchangeRetrievalAccuracyScenarioResult,
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow] = [],
        tierAReference: ExchangeRetrievalAccuracyScenarioResult? = nil,
        serverRoundTripIssues: [String] = []
    ) -> ObservationalQualityAssessment {
        var missRecords: [ObservationalMissRecord] = []
        var informationalNotes: [String] = []

        let topNodes = topNodeIDs(from: result, limit: expectation.topK)
        let top1 = topNodes.first
        let primary = expectation.resolvedPrimaryExpectedNodeID()
        let acceptable = expectation.resolvedAcceptableTop1NodeIDs()
        let acceptableSet = Set(acceptable)
        let expectedRankOfPrimary = primary.flatMap { nodeID in
            topNodes.firstIndex(of: nodeID).map { $0 + 1 }
        }

        let strictFailures = strictInvariantFailures(
            expectation: expectation,
            result: result,
            rankingTrace: rankingTrace
        )
        for failure in strictFailures {
            let classification: ObservationalMissClassification = failure.contains("forbidden attachment")
                ? .safetyViolation
                : .strictFailure
            missRecords.append(
                ObservationalMissRecord(
                    scenarioID: expectation.id,
                    classification: classification,
                    top1NodeID: top1,
                    primaryExpectedNodeID: primary,
                    expectedRank: expectedRankOfPrimary,
                    safetyImpact: classification == .safetyViolation ? "strict safety fail" : "strict invariant fail",
                    detail: failure
                )
            )
        }

        for issue in serverRoundTripIssues {
            missRecords.append(
                ObservationalMissRecord(
                    scenarioID: expectation.id,
                    classification: .serverRoundTripIssue,
                    top1NodeID: top1,
                    primaryExpectedNodeID: primary,
                    expectedRank: expectedRankOfPrimary,
                    safetyImpact: "strict safety fail",
                    detail: issue
                )
            )
        }

        for nodeID in expectation.requiredInTopK where !topNodes.contains(nodeID) {
            missRecords.append(
                ObservationalMissRecord(
                    scenarioID: expectation.id,
                    classification: .trueTopKMiss,
                    top1NodeID: top1,
                    primaryExpectedNodeID: primary,
                    expectedRank: nil,
                    safetyImpact: "none",
                    detail: "required node \(nodeID) missing from top \(expectation.topK): \(topNodes)"
                )
            )
        }

        for nodeID in expectation.forbiddenNodes where topNodes.contains(nodeID) {
            missRecords.append(
                ObservationalMissRecord(
                    scenarioID: expectation.id,
                    classification: .trueTopKMiss,
                    top1NodeID: top1,
                    primaryExpectedNodeID: primary,
                    expectedRank: topNodes.firstIndex(of: nodeID).map { $0 + 1 },
                    safetyImpact: "none",
                    detail: "forbidden node \(nodeID) appeared in top \(expectation.topK)"
                )
            )
        }

        for (nodeID, maxRank) in expectation.maxRankByNode {
            if let index = topNodes.firstIndex(of: nodeID) {
                let rank = index + 1
                if rank > maxRank {
                    missRecords.append(
                        ObservationalMissRecord(
                            scenarioID: expectation.id,
                            classification: .trueTopKMiss,
                            top1NodeID: top1,
                            primaryExpectedNodeID: primary,
                            expectedRank: rank,
                            safetyImpact: "none",
                            detail: "node \(nodeID) rank \(rank) exceeds max \(maxRank)"
                        )
                    )
                }
            }
        }

        for (nodeID, requiredOffers) in expectation.requiredMatchedOffers {
            let actual = Set(result.matchedOffersByNode[nodeID] ?? [])
            for offerID in requiredOffers where !actual.contains(offerID) {
                missRecords.append(
                    ObservationalMissRecord(
                        scenarioID: expectation.id,
                        classification: .trueTopKMiss,
                        top1NodeID: top1,
                        primaryExpectedNodeID: primary,
                        expectedRank: topNodes.firstIndex(of: nodeID).map { $0 + 1 },
                        safetyImpact: "none",
                        detail: "node \(nodeID) missing required matched offer \(offerID); got \(actual)"
                    )
                )
            }
        }

        for requiredKind in expectation.requiredDocKindsInTopTrace {
            let raw = requiredKind.rawValue
            if !result.topDocKinds.contains(raw) {
                missRecords.append(
                    ObservationalMissRecord(
                        scenarioID: expectation.id,
                        classification: .trueTopKMiss,
                        top1NodeID: top1,
                        primaryExpectedNodeID: primary,
                        expectedRank: expectedRankOfPrimary,
                        safetyImpact: "none",
                        detail: "required docKind \(raw) missing from top trace"
                    )
                )
            }
        }

        if let firstKind = result.topDocKinds.first {
            for forbiddenKind in expectation.forbiddenDocKindsFirstRank where firstKind == forbiddenKind.rawValue {
                missRecords.append(
                    ObservationalMissRecord(
                        scenarioID: expectation.id,
                        classification: .trueTopKMiss,
                        top1NodeID: top1,
                        primaryExpectedNodeID: primary,
                        expectedRank: 1,
                        safetyImpact: "none",
                        detail: "forbidden docKind \(forbiddenKind.rawValue) ranked first"
                    )
                )
            }
        }

        if !result.passed {
            let strict = Set(strictFailures)
            if let reason = result.failureReason {
                for part in reason.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                    if !part.isEmpty, !strict.contains(part) {
                        informationalNotes.append(part)
                    }
                }
            }
        }

        if let primary, let top1, top1 != primary {
            if acceptableSet.contains(top1) {
                let classification = expectation.observationalMissTypeOverride
                    ?? (expectation.equivalentResultGroupName != nil
                        ? .equivalentSiblingProvider
                        : .validAlternateRequiredNode)
                let groupLabel = expectation.equivalentResultGroupName ?? "acceptable required node"
                missRecords.append(
                    ObservationalMissRecord(
                        scenarioID: expectation.id,
                        classification: classification,
                        top1NodeID: top1,
                        primaryExpectedNodeID: primary,
                        expectedRank: expectedRankOfPrimary,
                        safetyImpact: "none",
                        detail: "top1=\(top1) primary=\(primary) (\(groupLabel))"
                    )
                )
            } else if let rank = expectedRankOfPrimary, rank <= expectation.topK {
                missRecords.append(
                    ObservationalMissRecord(
                        scenarioID: expectation.id,
                        classification: .expectedNodeInTopK,
                        top1NodeID: top1,
                        primaryExpectedNodeID: primary,
                        expectedRank: rank,
                        safetyImpact: "none",
                        detail: "top1 miss: expected \(primary) got \(top1) (rank #\(rank) in top\(expectation.topK))"
                    )
                )
            }
        }

        let coderNode = ExchangeRetrievalAccuracyFixtureBuilder.NodeID.coder
        let coderTrace = rankingTrace.filter { $0.counterpartyID == coderNode }
        if expectation.id == "capability.build-ios-app",
           let capScore = coderTrace.first(where: { $0.docKind == ExchangeRetrievalDocument.DocKind.profileCapability.rawValue })?.finalScore,
           let aboutScore = coderTrace.first(where: { $0.docKind == ExchangeRetrievalDocument.DocKind.profileAbout.rawValue })?.finalScore,
           aboutScore > capScore {
            let detail = "profile_about (\(aboutScore)) beats profile_capability (\(capScore)) on coder node"
            missRecords.append(
                ObservationalMissRecord(
                    scenarioID: expectation.id,
                    classification: .docKindOrderingIssue,
                    top1NodeID: top1,
                    primaryExpectedNodeID: primary,
                    expectedRank: expectedRankOfPrimary,
                    safetyImpact: "none",
                    detail: detail
                )
            )
            informationalNotes.append(detail)
        }

        if let tierAReference {
            let tierATop1 = topNodeIDs(from: tierAReference, limit: 1).first
            if tierATop1 != top1 {
                informationalNotes.append("top1 differs from Tier A: axis=\(tierATop1 ?? "nil") onnx=\(top1 ?? "nil")")
            }
        }

        let hasRankingExpectation = primary != nil || !acceptableSet.isEmpty
        let top1PrimaryHit: Bool = {
            guard hasRankingExpectation else { return true }
            guard let top1 else { return false }
            guard let primary else { return acceptableSet.contains(top1) }
            return top1 == primary
        }()
        let top1AnyRequiredHit: Bool = {
            guard !acceptableSet.isEmpty else {
                guard let primary else { return !hasRankingExpectation }
                return top1 == primary
            }
            guard let top1 else { return false }
            return acceptableSet.contains(top1)
        }()
        let top3AnyRequiredHit: Bool = {
            if !acceptableSet.isEmpty {
                return topNodes.prefix(3).contains { acceptableSet.contains($0) }
            }
            if !expectation.requiredInTopK.isEmpty {
                return expectation.requiredInTopK.contains { topNodes.prefix(3).contains($0) }
            }
            return true
        }()

        return ObservationalQualityAssessment(
            top1NodeID: top1,
            primaryExpectedNodeID: primary,
            acceptableTop1NodeIDs: acceptable,
            expectedRankOfPrimary: expectedRankOfPrimary,
            top1PrimaryHit: top1PrimaryHit,
            top1AnyRequiredHit: top1AnyRequiredHit,
            top3AnyRequiredHit: top3AnyRequiredHit,
            missRecords: missRecords,
            informationalNotes: informationalNotes
        )
    }

    public static func observationalIssues(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation,
        result: ExchangeRetrievalAccuracyScenarioResult,
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow] = [],
        tierAReference: ExchangeRetrievalAccuracyScenarioResult? = nil,
        serverRoundTripIssues: [String] = []
    ) -> [String] {
        let assessment = observationalAssessment(
            expectation: expectation,
            result: result,
            rankingTrace: rankingTrace,
            tierAReference: tierAReference,
            serverRoundTripIssues: serverRoundTripIssues
        )

        var issues: [String] = []
        for record in assessment.missRecords {
            switch record.classification {
            case .validAlternateRequiredNode, .equivalentSiblingProvider:
                issues.append("\(record.classification.rawValue): \(record.detail)")
            case .docKindOrderingIssue:
                issues.append(record.detail)
            case .expectedNodeInTopK, .trueTopKMiss:
                issues.append(record.detail)
            case .strictFailure, .safetyViolation, .serverRoundTripIssue:
                break
            }
        }
        issues.append(contentsOf: assessment.informationalNotes)
        return issues
    }

    public struct StrictInvariantMetrics: Sendable, Hashable, Codable {
        public var totalScenarios: Int
        public var strictPassCount: Int
        public var forbiddenAttachmentViolations: Int
        public var objectLaneFalsePositives: Int
        public var objectLaneFalseNegatives: Int

        public init(
            totalScenarios: Int,
            strictPassCount: Int,
            forbiddenAttachmentViolations: Int,
            objectLaneFalsePositives: Int,
            objectLaneFalseNegatives: Int
        ) {
            self.totalScenarios = totalScenarios
            self.strictPassCount = strictPassCount
            self.forbiddenAttachmentViolations = forbiddenAttachmentViolations
            self.objectLaneFalsePositives = objectLaneFalsePositives
            self.objectLaneFalseNegatives = objectLaneFalseNegatives
        }
    }

    public static func strictAggregate(
        expectations: [ExchangeRetrievalAccuracyScenarioExpectation],
        results: [ExchangeRetrievalAccuracyScenarioResult],
        rankingTracesByScenarioID: [String: [ExchangeRetrievalDebugTrace.RankingRow]] = [:]
    ) -> StrictInvariantMetrics {
        let resultByID = Dictionary(uniqueKeysWithValues: results.map { ($0.scenarioID, $0) })
        var strictPass = 0
        var forbiddenViolations = 0
        var olFalsePositives = 0
        var olFalseNegatives = 0

        for expectation in expectations {
            guard let result = resultByID[expectation.id] else { continue }
            let trace = rankingTracesByScenarioID[expectation.id] ?? []
            let strictFailures = strictInvariantFailures(
                expectation: expectation,
                result: result,
                rankingTrace: trace
            )
            if strictFailures.isEmpty {
                strictPass += 1
            }
            for failure in strictFailures {
                if failure.contains("forbidden attachment") {
                    forbiddenViolations += 1
                }
                if failure.contains("false positive") {
                    olFalsePositives += 1
                }
                if failure.contains("false negative") {
                    olFalseNegatives += 1
                }
            }
        }

        return StrictInvariantMetrics(
            totalScenarios: expectations.count,
            strictPassCount: strictPass,
            forbiddenAttachmentViolations: forbiddenViolations,
            objectLaneFalsePositives: olFalsePositives,
            objectLaneFalseNegatives: olFalseNegatives
        )
    }

    public struct TierComparisonRow: Sendable, Hashable, Codable {
        public var scenarioID: String
        public var queryLabel: String
        public var tierAStrictPassed: Bool
        public var tierBStrictPassed: Bool
        public var tierATop1: String?
        public var tierBTop1: String?
        public var tierATop3: [String]
        public var tierBTop3: [String]
        public var tierASelectedOfferID: String?
        public var tierBSelectedOfferID: String?
        public var tierAProvenObjectOfferIDs: [String]
        public var tierBProvenObjectOfferIDs: [String]
        public var tierAObjectEvidence: [String: Double]
        public var tierBObjectEvidence: [String: Double]
        public var tierATopDocKinds: [String]
        public var tierBTopDocKinds: [String]
        public var tierAStrictFailures: [String]
        public var tierBStrictFailures: [String]
        public var observationalIssues: [String]
    }

    private static func topNodeIDs(from result: ExchangeRetrievalAccuracyScenarioResult, limit: Int) -> [String] {
        result.actualTopSummaries.prefix(limit).compactMap { summary -> String? in
            summary.split(separator: " ").first(where: { $0.hasPrefix("node=") })?
                .replacingOccurrences(of: "node=", with: "")
        }
    }

    public static func makeTierComparisonRow(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation,
        tierA: ExchangeRetrievalAccuracyScenarioResult,
        tierB: ExchangeRetrievalAccuracyScenarioResult,
        tierARankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        tierBRankingTrace: [ExchangeRetrievalDebugTrace.RankingRow]
    ) -> TierComparisonRow {
        let tierAStrict = strictInvariantFailures(
            expectation: expectation,
            result: tierA,
            rankingTrace: tierARankingTrace
        )
        let tierBStrict = strictInvariantFailures(
            expectation: expectation,
            result: tierB,
            rankingTrace: tierBRankingTrace
        )
        return TierComparisonRow(
            scenarioID: expectation.id,
            queryLabel: expectation.queryLabel,
            tierAStrictPassed: tierAStrict.isEmpty,
            tierBStrictPassed: tierBStrict.isEmpty,
            tierATop1: topNodeIDs(from: tierA, limit: 1).first,
            tierBTop1: topNodeIDs(from: tierB, limit: 1).first,
            tierATop3: topNodeIDs(from: tierA, limit: 3),
            tierBTop3: topNodeIDs(from: tierB, limit: 3),
            tierASelectedOfferID: tierA.selectedOfferID,
            tierBSelectedOfferID: tierB.selectedOfferID,
            tierAProvenObjectOfferIDs: tierA.provenObjectOfferIDs,
            tierBProvenObjectOfferIDs: tierB.provenObjectOfferIDs,
            tierAObjectEvidence: tierA.topObjectEvidenceScores,
            tierBObjectEvidence: tierB.topObjectEvidenceScores,
            tierATopDocKinds: tierA.topDocKinds,
            tierBTopDocKinds: tierB.topDocKinds,
            tierAStrictFailures: tierAStrict,
            tierBStrictFailures: tierBStrict,
            observationalIssues: observationalIssues(
                expectation: expectation,
                result: tierB,
                rankingTrace: tierBRankingTrace,
                tierAReference: tierA
            )
        )
    }

    public static func printTierComparisonReport(
        rows: [TierComparisonRow],
        tierAMetrics: StrictInvariantMetrics,
        tierBMetrics: StrictInvariantMetrics,
        tierAObservational: ExchangeRetrievalAccuracyAggregateMetrics,
        tierBObservational: ExchangeRetrievalAccuracyAggregateMetrics
    ) {
        print("\n=== ExchangeRetrieval Tier A vs Tier B ONNX Smoke ===")
        print("Run: ANUM_RETRIEVAL_ONNX_SMOKE=1 swift test --filter ExchangeRetrievalOnnxSmokeTests")
        for row in rows {
            print("[\(row.scenarioID)] \(row.queryLabel)")
            print("  strict: tierA=\(row.tierAStrictPassed ? "PASS" : "FAIL") tierB=\(row.tierBStrictPassed ? "PASS" : "FAIL")")
            print("  top1: tierA=\(row.tierATop1 ?? "nil") tierB=\(row.tierBTop1 ?? "nil")")
            print("  top3: tierA=\(row.tierATop3) tierB=\(row.tierBTop3)")
            print("  selectedOfferID: tierA=\(row.tierASelectedOfferID ?? "nil") tierB=\(row.tierBSelectedOfferID ?? "nil")")
            print("  provenObjectOfferIDs: tierA=\(row.tierAProvenObjectOfferIDs) tierB=\(row.tierBProvenObjectOfferIDs)")
            print("  objectEvidence: tierA=\(row.tierAObjectEvidence) tierB=\(row.tierBObjectEvidence)")
            print("  topDocKinds: tierA=\(row.tierATopDocKinds) tierB=\(row.tierBTopDocKinds)")
            if !row.tierBStrictFailures.isEmpty {
                print("  tierB strictFailures: \(row.tierBStrictFailures.joined(separator: "; "))")
            }
            if !row.observationalIssues.isEmpty {
                print("  observational: \(row.observationalIssues.joined(separator: "; "))")
            }
        }

        print("\n--- Strict aggregate ---")
        print("tierA strictPass: \(tierAMetrics.strictPassCount)/\(tierAMetrics.totalScenarios)")
        print("tierB strictPass: \(tierBMetrics.strictPassCount)/\(tierBMetrics.totalScenarios)")
        print("tierA forbiddenAttachmentViolations: \(tierAMetrics.forbiddenAttachmentViolations)")
        print("tierB forbiddenAttachmentViolations: \(tierBMetrics.forbiddenAttachmentViolations)")
        print("tierA objectLaneFalsePositives: \(tierAMetrics.objectLaneFalsePositives)")
        print("tierB objectLaneFalsePositives: \(tierBMetrics.objectLaneFalsePositives)")
        print("tierA objectLaneFalseNegatives: \(tierAMetrics.objectLaneFalseNegatives)")
        print("tierB objectLaneFalseNegatives: \(tierBMetrics.objectLaneFalseNegatives)")

        print("\n--- Observational aggregate ---")
        print(String(
            format: "tierA top1Primary: %.2f top1AnyRequired: %.2f top3AnyRequired: %.2f",
            tierAObservational.top1PrimaryAccuracy,
            tierAObservational.top1AnyRequiredAccuracy,
            tierAObservational.top3AnyRequiredAccuracy
        ))
        print(String(
            format: "tierB top1Primary: %.2f top1AnyRequired: %.2f top3AnyRequired: %.2f",
            tierBObservational.top1PrimaryAccuracy,
            tierBObservational.top1AnyRequiredAccuracy,
            tierBObservational.top3AnyRequiredAccuracy
        ))

        let regressions = rows.filter { row in
            row.tierAStrictPassed && !row.tierBStrictPassed
        }.map(\.scenarioID)
        if !regressions.isEmpty {
            print("ranking safety regressions (A strict pass, B strict fail): \(regressions)")
        }

        let rankingRegressions = rows.filter { row in
            row.tierATop1 != nil && row.tierBTop1 != nil && row.tierATop1 != row.tierBTop1
        }.map { "\($0.scenarioID): \($0.tierATop1 ?? "nil") -> \($0.tierBTop1 ?? "nil")" }
        if !rankingRegressions.isEmpty {
            print("top1 ranking differences: \(rankingRegressions)")
        }
        print("=== End Tier Comparison ===\n")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
