import Foundation

#if DEBUG

public struct LocalFederationServerRoundTripAudit: Sendable, Hashable, Codable {
    public var responseMode: String
    public var serverRetrievalDocumentsCount: Int
    public var serverRetrievalHitsCount: Int
    public var docKindCounts: [String: Int]
    public var embeddingCountsByDocKind: [String: Int]
    public var candidateOfferIDsFromDocs: [String]
    public var issues: [String]

    public init(
        responseMode: String,
        serverRetrievalDocumentsCount: Int,
        serverRetrievalHitsCount: Int,
        docKindCounts: [String: Int],
        embeddingCountsByDocKind: [String: Int],
        candidateOfferIDsFromDocs: [String],
        issues: [String]
    ) {
        self.responseMode = responseMode
        self.serverRetrievalDocumentsCount = serverRetrievalDocumentsCount
        self.serverRetrievalHitsCount = serverRetrievalHitsCount
        self.docKindCounts = docKindCounts
        self.embeddingCountsByDocKind = embeddingCountsByDocKind
        self.candidateOfferIDsFromDocs = candidateOfferIDsFromDocs
        self.issues = issues
    }
}

public struct LocalFederationSmokeRunResult: Sendable, Hashable, Codable {
    public var batchID: Int
    public var runID: Int
    public var scenarioID: String
    public var repeatIndex: Int
    public var strictPassed: Bool
    public var strictFailures: [String]
    public var serverRoundTrip: LocalFederationServerRoundTripAudit
    public var accuracyResult: ExchangeRetrievalAccuracyScenarioResult
    public var latencyMs: Int
    public var observationalIssues: [String]
    public var observationalAssessment: ObservationalQualityAssessment

    public init(
        batchID: Int,
        runID: Int,
        scenarioID: String,
        repeatIndex: Int,
        strictPassed: Bool,
        strictFailures: [String],
        serverRoundTrip: LocalFederationServerRoundTripAudit,
        accuracyResult: ExchangeRetrievalAccuracyScenarioResult,
        latencyMs: Int,
        observationalIssues: [String],
        observationalAssessment: ObservationalQualityAssessment
    ) {
        self.batchID = batchID
        self.runID = runID
        self.scenarioID = scenarioID
        self.repeatIndex = repeatIndex
        self.strictPassed = strictPassed
        self.strictFailures = strictFailures
        self.serverRoundTrip = serverRoundTrip
        self.accuracyResult = accuracyResult
        self.latencyMs = latencyMs
        self.observationalIssues = observationalIssues
        self.observationalAssessment = observationalAssessment
    }
}

public struct LocalFederationSmokeAggregateReport: Sendable, Hashable, Codable {
    public var runs: Int
    public var strictPass: Int
    public var forbiddenAttachmentViolations: Int
    public var objectLaneFP: Int
    public var objectLaneFN: Int
    public var docKindRoundTripFailures: Int
    public var embeddingMissing: Int
    public var serverResponseModeMismatch: Int
    public var selectedOfferAccuracy: Double
    public var top1Observational: Double
    public var top3Observational: Double
    public var top1Primary: Double
    public var top1AnyRequired: Double
    public var top3AnyRequired: Double
    public var validAlternateTop1: Int
    public var trueTopKMiss: Int
    public var docKindOrderingIssues: Int
    public var duplicateStaleDocCount: Int
    public var latencyAvgMs: Double
    public var latencyP95Ms: Double
    public var publishGenerationID: String

    public init(
        runs: Int,
        strictPass: Int,
        forbiddenAttachmentViolations: Int,
        objectLaneFP: Int,
        objectLaneFN: Int,
        docKindRoundTripFailures: Int,
        embeddingMissing: Int,
        serverResponseModeMismatch: Int,
        selectedOfferAccuracy: Double,
        top1Observational: Double,
        top3Observational: Double,
        top1Primary: Double,
        top1AnyRequired: Double,
        top3AnyRequired: Double,
        validAlternateTop1: Int,
        trueTopKMiss: Int,
        docKindOrderingIssues: Int,
        duplicateStaleDocCount: Int,
        latencyAvgMs: Double,
        latencyP95Ms: Double,
        publishGenerationID: String
    ) {
        self.runs = runs
        self.strictPass = strictPass
        self.forbiddenAttachmentViolations = forbiddenAttachmentViolations
        self.objectLaneFP = objectLaneFP
        self.objectLaneFN = objectLaneFN
        self.docKindRoundTripFailures = docKindRoundTripFailures
        self.embeddingMissing = embeddingMissing
        self.serverResponseModeMismatch = serverResponseModeMismatch
        self.selectedOfferAccuracy = selectedOfferAccuracy
        self.top1Observational = top1Observational
        self.top3Observational = top3Observational
        self.top1Primary = top1Primary
        self.top1AnyRequired = top1AnyRequired
        self.top3AnyRequired = top3AnyRequired
        self.validAlternateTop1 = validAlternateTop1
        self.trueTopKMiss = trueTopKMiss
        self.docKindOrderingIssues = docKindOrderingIssues
        self.duplicateStaleDocCount = duplicateStaleDocCount
        self.latencyAvgMs = latencyAvgMs
        self.latencyP95Ms = latencyP95Ms
        self.publishGenerationID = publishGenerationID
    }
}

public enum ExchangeRetrievalLocalFederationSmokeReport {
    public static let expectedEmbeddingDimension = ExchangeRetrievalAccuracyFixtureBuilder.onnxEmbeddingDimension

    public static func auditServerRoundTrip(
        matches: [ExchangeDirectoryMatch],
        expectedNodeIDs: Set<String>,
        expectedDocIDs: Set<String>,
        requestedResponseMode: String = ExchangeDirectorySearchRequest.RetrievalResponseMode.clientRerank.rawValue,
        observedResponseMode: String? = nil
    ) -> LocalFederationServerRoundTripAudit {
        var issues: [String] = []
        let responseMode = observedResponseMode ?? requestedResponseMode

        if responseMode != ExchangeDirectorySearchRequest.RetrievalResponseMode.clientRerank.rawValue {
            issues.append("responseMode expected clientRerank got \(responseMode)")
        }

        var docKindCounts: [String: Int] = [:]
        var embeddingCountsByDocKind: [String: Int] = [:]
        var totalDocs = 0
        var totalHits = 0
        var candidateOfferIDs: [String] = []

        for match in matches {
            let nodeID = match.id
            if !expectedNodeIDs.contains(nodeID) {
                issues.append("unexpected nodeID outside catalog: \(nodeID)")
            }

            totalDocs += match.retrievalDocuments.count
            totalHits += match.retrievalHits.count
            candidateOfferIDs.append(contentsOf: match.candidateOfferIDsFromDocs)

            let hydratedOfferIDs = Set(match.offers.map(\.id))
            let docCandidateIDs = Set(match.candidateOfferIDsFromDocs)
            let hitOfferIDs = Set(match.retrievalHits.compactMap { hit -> String? in
                guard let offerID = hit.offerID?.trimmingCharacters(in: .whitespacesAndNewlines), !offerID.isEmpty else {
                    return nil
                }
                return offerID
            })

            for offerID in docCandidateIDs where !hitOfferIDs.contains(offerID) {
                issues.append("candidateOfferID \(offerID) lacks retrievalHit proof on \(nodeID)")
            }

            if hydratedOfferIDs.count > 1,
               docCandidateIDs == hydratedOfferIDs,
               hitOfferIDs != hydratedOfferIDs,
               !docCandidateIDs.isEmpty {
                issues.append(
                    "candidateOfferIDsFromDocs lists all hydrated offers on \(nodeID) without full hit proof"
                )
            }

            for doc in match.retrievalDocuments {
                if !expectedDocIDs.contains(doc.id) {
                    issues.append("unexpected retrieval doc outside catalog: \(doc.id) node=\(nodeID)")
                }
                let kind = doc.docKind?.rawValue ?? "nil"
                docKindCounts[kind, default: 0] += 1
                if doc.docKind == nil {
                    issues.append("missing docKind on doc \(doc.id)")
                }
                if doc.sourceField?.isEmpty != false, doc.docKind != nil {
                    issues.append("missing sourceField on doc \(doc.id) kind=\(kind)")
                }
                if doc.hasEmbedding {
                    embeddingCountsByDocKind[kind, default: 0] += 1
                    if doc.embeddingDimension != expectedEmbeddingDimension {
                        issues.append(
                            "embedding dim \(doc.embeddingDimension) on doc \(doc.id), expected \(expectedEmbeddingDimension)"
                        )
                    }
                } else if !match.retrievalDocuments.isEmpty {
                    issues.append("missing embedding on clientRerank doc \(doc.id) kind=\(kind)")
                }
            }

            for hit in match.retrievalHits {
                if let hitNode = hit.nodeID, hitNode != nodeID {
                    issues.append("retrievalHit nodeID mismatch \(hitNode) vs \(nodeID)")
                }
                if hit.docKind == nil {
                    issues.append("retrievalHit missing docKind doc=\(hit.retrievalDocID ?? "nil")")
                }
                if hit.sourceField?.isEmpty != false, hit.docKind != nil {
                    issues.append("retrievalHit missing sourceField doc=\(hit.retrievalDocID ?? "nil")")
                }
                if let hitOffer = hit.offerID, let docKind = hit.docKind?.rawValue {
                    if docKind.hasPrefix("offer_"), hitOffer.isEmpty {
                        issues.append("retrievalHit missing offerID for offer doc \(hit.retrievalDocID ?? "nil")")
                    }
                }
                if hit.embedding == nil || hit.embedding?.isEmpty == true {
                    if let docID = hit.retrievalDocID,
                       match.retrievalDocuments.contains(where: { $0.id == docID && $0.hasEmbedding }) {
                        issues.append("retrievalHit missing embedding for doc \(docID)")
                    }
                }
            }
        }

        if matches.isEmpty {
            issues.append("search returned zero directory matches")
        } else if totalDocs == 0 {
            issues.append("search matches missing retrievalDocuments")
        }

        return LocalFederationServerRoundTripAudit(
            responseMode: responseMode,
            serverRetrievalDocumentsCount: totalDocs,
            serverRetrievalHitsCount: totalHits,
            docKindCounts: docKindCounts,
            embeddingCountsByDocKind: embeddingCountsByDocKind,
            candidateOfferIDsFromDocs: Array(Set(candidateOfferIDs)).sorted(),
            issues: issues
        )
    }

    public static func strictFailures(
        expectation: ExchangeRetrievalAccuracyScenarioExpectation,
        accuracyResult: ExchangeRetrievalAccuracyScenarioResult,
        rankingTrace: [ExchangeRetrievalDebugTrace.RankingRow],
        serverRoundTrip: LocalFederationServerRoundTripAudit
    ) -> [String] {
        var failures = ExchangeRetrievalAccuracyReport.strictInvariantFailures(
            expectation: expectation,
            result: accuracyResult,
            rankingTrace: rankingTrace
        )
        failures.append(contentsOf: serverRoundTrip.issues)
        return failures
    }

    public static func printRunReport(
        run: LocalFederationSmokeRunResult,
        serverBaseURL: String,
        publishGenerationID: String
    ) {
        let status = run.strictPassed ? "PASS" : "FAIL"
        let result = run.accuracyResult
        let rt = run.serverRoundTrip
        print(
            """
            [LOCAL-FED-SMOKE] batch=\(run.batchID) run=\(run.runID) scenario=\(run.scenarioID) repeat=\(run.repeatIndex)
            strict=\(status)
            serverBaseURL=\(serverBaseURL)
            publishGenerationID=\(publishGenerationID)
            responseMode=\(rt.responseMode)
            serverDocs=\(rt.serverRetrievalDocumentsCount)
            serverHits=\(rt.serverRetrievalHitsCount)
            docKindCounts=\(formatCounts(rt.docKindCounts))
            embeddingCountsByDocKind=\(formatCounts(rt.embeddingCountsByDocKind))
            candidateOfferIDsFromDocs=\(rt.candidateOfferIDsFromDocs)
            top5Nodes=\(topNodeIDs(from: result, limit: 5))
            top5Offers=\(topOfferIDs(from: result, limit: 5))
            top10DocKinds=\(Array(result.topDocKinds.prefix(10)))
            selectedOfferID=\(result.selectedOfferID ?? "nil")
            matchedOffers=\(result.matchedOffersByNode)
            provenObjectOfferIDs=\(result.provenObjectOfferIDs)
            objectEvidenceScoreByOfferID=\(result.topObjectEvidenceScores)
            forbiddenViolations=\(result.failureReason?.contains("forbidden attachment") == true ? 1 : countForbidden(result))
            objectLaneFP=\(objectLaneFP(expectationActive: result.objectLaneActive, proven: result.provenObjectOfferIDs))
            objectLaneFN=\(objectLaneFN(result: result))
            serverRoundTripIssues=\(rt.issues)
            latencyMs=\(run.latencyMs)
            failureReason=\(run.strictFailures.joined(separator: "; "))
            """
        )
        if !run.observationalIssues.isEmpty {
            print("observationalIssues=\(run.observationalIssues)")
        }
        let observationalMisses = run.observationalAssessment.missRecords.filter {
            switch $0.classification {
            case .validAlternateRequiredNode, .equivalentSiblingProvider, .expectedNodeInTopK,
                 .docKindOrderingIssue, .trueTopKMiss:
                return true
            case .strictFailure, .safetyViolation, .serverRoundTripIssue:
                return false
            }
        }
        if !observationalMisses.isEmpty {
            print("observationalClassification=" + observationalMisses.map {
                "\($0.classification.rawValue)|top1=\($0.top1NodeID ?? "nil")|primary=\($0.primaryExpectedNodeID ?? "nil")|rank=\($0.expectedRank.map(String.init) ?? "nil")|impact=\($0.safetyImpact)|\($0.detail)"
            }.joined(separator: "; "))
        }
    }

    public static func printAggregateReport(
        aggregate: LocalFederationSmokeAggregateReport
    ) {
        print(
            """
            [LOCAL-FED-SMOKE-AGGREGATE]
            runs=\(aggregate.runs)
            strictPass=\(aggregate.strictPass)/\(aggregate.runs)
            top1Primary=\(String(format: "%.2f", aggregate.top1Primary))
            top1AnyRequired=\(String(format: "%.2f", aggregate.top1AnyRequired))
            top3AnyRequired=\(String(format: "%.2f", aggregate.top3AnyRequired))
            validAlternateTop1=\(aggregate.validAlternateTop1)
            trueTopKMiss=\(aggregate.trueTopKMiss)
            docKindOrderingIssues=\(aggregate.docKindOrderingIssues)
            forbiddenAttachmentViolations=\(aggregate.forbiddenAttachmentViolations)
            objectLaneFP=\(aggregate.objectLaneFP)
            objectLaneFN=\(aggregate.objectLaneFN)
            docKindRoundTripFailures=\(aggregate.docKindRoundTripFailures)
            embeddingMissing=\(aggregate.embeddingMissing)
            serverResponseModeMismatch=\(aggregate.serverResponseModeMismatch)
            selectedOfferAccuracy=\(String(format: "%.2f", aggregate.selectedOfferAccuracy))
            top1Observational=\(String(format: "%.2f", aggregate.top1Observational))
            top3Observational=\(String(format: "%.2f", aggregate.top3Observational))
            duplicateStaleDocCount=\(aggregate.duplicateStaleDocCount)
            latencyAvgMs=\(String(format: "%.0f", aggregate.latencyAvgMs))
            latencyP95Ms=\(String(format: "%.0f", aggregate.latencyP95Ms))
            publishGenerationID=\(aggregate.publishGenerationID)
            """
        )
    }

    public static func makeAggregate(
        runs: [LocalFederationSmokeRunResult],
        expectations: [ExchangeRetrievalAccuracyScenarioExpectation],
        publishGenerationID: String
    ) -> LocalFederationSmokeAggregateReport {
        let strictPass = runs.filter(\.strictPassed).count
        var forbidden = 0
        var olFP = 0
        var olFN = 0
        var docKindFailures = 0
        var embeddingMissing = 0
        var modeMismatch = 0
        var duplicateStale = 0

        for run in runs {
            for failure in run.strictFailures {
                if failure.contains("forbidden attachment") { forbidden += 1 }
                if failure.contains("false positive") { olFP += 1 }
                if failure.contains("false negative") { olFN += 1 }
                if failure.contains("docKind") || failure.contains("sourceField") { docKindFailures += 1 }
                if failure.contains("missing embedding") || failure.contains("embedding dim") { embeddingMissing += 1 }
                if failure.contains("responseMode") { modeMismatch += 1 }
                if failure.contains("outside catalog") || failure.contains("unexpected retrieval doc") {
                    duplicateStale += 1
                }
            }
        }

        var top1PrimaryHits = 0
        var top1AnyRequiredHits = 0
        var top3AnyRequiredHits = 0
        var rankingExpectationCount = 0
        var validAlternateTop1 = 0
        var trueTopKMiss = 0
        var docKindOrderingIssues = 0
        var selectedChecks = 0
        var selectedHits = 0
        for run in runs {
            let assessment = run.observationalAssessment
            if assessment.primaryExpectedNodeID != nil || !assessment.acceptableTop1NodeIDs.isEmpty {
                rankingExpectationCount += 1
                if assessment.top1PrimaryHit { top1PrimaryHits += 1 }
                if assessment.top1AnyRequiredHit { top1AnyRequiredHits += 1 }
                if assessment.top3AnyRequiredHit { top3AnyRequiredHits += 1 }
                if !assessment.top1PrimaryHit && assessment.top1AnyRequiredHit {
                    validAlternateTop1 += 1
                }
            }
            for record in assessment.missRecords {
                switch record.classification {
                case .trueTopKMiss:
                    trueTopKMiss += 1
                case .docKindOrderingIssue:
                    docKindOrderingIssues += 1
                default:
                    break
                }
            }
        }
        for (index, run) in runs.enumerated() {
            guard index < expectations.count else { continue }
            let expectation = expectations[index]
            if expectation.selectedOfferID != nil || expectation.selectedOfferIDMustBeNil {
                selectedChecks += 1
                if expectation.selectedOfferIDMustBeNil {
                    if run.accuracyResult.selectedOfferID == nil { selectedHits += 1 }
                } else if run.accuracyResult.selectedOfferID == expectation.selectedOfferID {
                    selectedHits += 1
                }
            }
        }

        let latencies = runs.map { Double($0.latencyMs) }.sorted()
        let avg = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let p95Index = max(0, min(latencies.count - 1, Int(Double(latencies.count) * 0.95) - 1))
        let p95 = latencies.isEmpty ? 0 : latencies[p95Index]
        let rankingDenominator = max(rankingExpectationCount, 1)

        return LocalFederationSmokeAggregateReport(
            runs: runs.count,
            strictPass: strictPass,
            forbiddenAttachmentViolations: forbidden,
            objectLaneFP: olFP,
            objectLaneFN: olFN,
            docKindRoundTripFailures: docKindFailures,
            embeddingMissing: embeddingMissing,
            serverResponseModeMismatch: modeMismatch,
            selectedOfferAccuracy: selectedChecks == 0 ? 0 : Double(selectedHits) / Double(selectedChecks),
            top1Observational: rankingExpectationCount == 0
                ? 0
                : Double(top1PrimaryHits) / Double(rankingDenominator),
            top3Observational: rankingExpectationCount == 0
                ? 0
                : Double(top3AnyRequiredHits) / Double(rankingDenominator),
            top1Primary: rankingExpectationCount == 0
                ? 0
                : Double(top1PrimaryHits) / Double(rankingDenominator),
            top1AnyRequired: rankingExpectationCount == 0
                ? 0
                : Double(top1AnyRequiredHits) / Double(rankingDenominator),
            top3AnyRequired: rankingExpectationCount == 0
                ? 0
                : Double(top3AnyRequiredHits) / Double(rankingDenominator),
            validAlternateTop1: validAlternateTop1,
            trueTopKMiss: trueTopKMiss,
            docKindOrderingIssues: docKindOrderingIssues,
            duplicateStaleDocCount: duplicateStale,
            latencyAvgMs: avg,
            latencyP95Ms: p95,
            publishGenerationID: publishGenerationID
        )
    }

    private static func formatCounts(_ counts: [String: Int]) -> String {
        counts.keys.sorted().map { "\($0):\(counts[$0] ?? 0)" }.joined(separator: ",")
    }

    private static func topNodeIDs(from result: ExchangeRetrievalAccuracyScenarioResult, limit: Int) -> [String] {
        result.actualTopSummaries.prefix(limit).compactMap { summary -> String? in
            summary.split(separator: " ").first(where: { $0.hasPrefix("node=") })?
                .replacingOccurrences(of: "node=", with: "")
        }
    }

    private static func topOfferIDs(from result: ExchangeRetrievalAccuracyScenarioResult, limit: Int) -> [String] {
        var offers: [String] = []
        for (_, ids) in result.matchedOffersByNode.sorted(by: { $0.key < $1.key }) {
            for id in ids where !offers.contains(id) {
                offers.append(id)
                if offers.count >= limit { return offers }
            }
        }
        if let selected = result.selectedOfferID, !offers.contains(selected) {
            offers.insert(selected, at: 0)
        }
        return Array(offers.prefix(limit))
    }

    private static func countForbidden(_ result: ExchangeRetrievalAccuracyScenarioResult) -> Int {
        guard let reason = result.failureReason else { return 0 }
        return reason.components(separatedBy: ";").filter { $0.contains("forbidden attachment") }.count
    }

    private static func objectLaneFP(expectationActive: Bool, proven: [String]) -> Int {
        !expectationActive && !proven.isEmpty ? 1 : 0
    }

    private static func objectLaneFN(result: ExchangeRetrievalAccuracyScenarioResult) -> Int {
        result.objectLaneActive && !result.provenObjectOfferIDs.isEmpty && result.selectedOfferID == nil ? 1 : 0
    }
}

#endif
