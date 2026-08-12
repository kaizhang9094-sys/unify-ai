import Foundation

#if DEBUG

public enum ExchangeRetrievalE2EReport {
    private static let logPrefix = "[RetrievalE2E]"

    public static func printRun(_ run: RetrievalE2ERunSnapshot) {
        let compactPreview = run.compactLLMOutput.map { preview($0, limit: 240) } ?? "nil"
        print(
            """
            \(logPrefix) run=\(run.runIndex)/\(run.totalRuns) query="\(run.query)" scenario=\(run.scenarioID)
            \(logPrefix)   rawQuery="\(run.query)"
            \(logPrefix)   compactLLM=\(compactPreview)
            \(logPrefix)   routeClass=\(run.routeClass ?? "nil") surfacePreference=\(run.surfacePreference ?? "nil")
            \(logPrefix)   objectType=\(run.objectType ?? "nil") domainCategory=\(run.domainCategory ?? "nil") transactionIntent=\(run.transactionIntent ?? "nil")
            \(logPrefix)   retrievalQueryObjectText=\(run.retrievalQueryObjectText ?? "nil") objectLaneActive=\(run.objectLaneActive) discoveryCalled=\(run.discoveryCalled)
            \(logPrefix)   fullEvaluateApplied=\(run.fullEvaluateApplied)
            \(logPrefix)   emittedDocKinds=[\(run.emittedDocKinds.joined(separator: ","))]
            """
        )
        for doc in run.topRetrievedDocs {
            let olScore = doc.objectLaneScore.map { String(format: "%.3f", $0) } ?? "nil"
            let score = String(format: "%.3f", doc.finalScore)
            print(
                "\(logPrefix)   top\(doc.rank) docKind=\(doc.docKind ?? "nil") surfaceType=\(doc.surfaceType) offerID=\(doc.offerID ?? "nil") score=\(score) objectLaneScore=\(olScore)"
            )
        }
        let matched = run.projectedMatchedOfferIDs
            .map { node, offers in "\(node):[\(offers.joined(separator: ","))]" }
            .joined(separator: " ")
        print(
            "\(logPrefix)   projectedMatchedOffers={\(matched)} selectedOfferID=\(run.selectedOfferID ?? "nil") uiCardOfferID=\(run.uiCardOfferID ?? "nil") uiSurfaceLead=\(run.uiSurfaceLead ?? "nil")"
        )
        if !run.structuralFailures.isEmpty {
            print("\(logPrefix)   structuralFailures=[\(run.structuralFailures.joined(separator: "; "))]")
        }
        if !run.rankingFailures.isEmpty {
            print("\(logPrefix)   rankingFailures=[\(run.rankingFailures.joined(separator: "; "))]")
        }
        if !run.strictFailures.isEmpty {
            print("\(logPrefix)   strictFailures=[\(run.strictFailures.joined(separator: "; "))]")
        }
        if !run.uiFailures.isEmpty {
            print("\(logPrefix)   uiFailures=[\(run.uiFailures.joined(separator: "; "))]")
        }
        let verdict = run.passed ? "PASS" : "FAIL"
        let reason = run.failureReasons.isEmpty ? "ok" : run.failureReasons.joined(separator: "; ")
        print("\(logPrefix)   \(verdict) reason=\(reason) latencyMs=\(run.latencyMs)")
    }

    public static func printAggregate(
        runs: [RetrievalE2ERunSnapshot],
        artifactPath: String?
    ) -> String {
        let passed = runs.filter(\.passed).count
        let failed = runs.count - passed
        let structuralFailures = runs.reduce(0) { $0 + $1.structuralFailures.count }
        let rankingFailures = runs.reduce(0) { $0 + $1.rankingFailures.count }
        let uiFailures = runs.reduce(0) { $0 + $1.uiFailures.count }
        var lines: [String] = [
            "[RetrievalE2E-AGGREGATE]",
            "passed=\(passed) failed=\(failed) structuralFailures=\(structuralFailures) rankingFailures=\(rankingFailures) uiFailures=\(uiFailures)",
        ]
        for run in runs {
            let status = run.passed ? "PASS" : "FAIL"
            let reason = run.failureReasons.first ?? "ok"
            lines.append("  \(status) \(run.scenarioID): \(reason)")
        }
        if let artifactPath {
            lines.append("artifact=\(artifactPath)")
        }
        let text = lines.joined(separator: "\n")
        print(text)
        return text
    }

    public static func writeJSONL(runs: [RetrievalE2ERunSnapshot], to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var data = Data()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for run in runs {
            data.append(try encoder.encode(run))
            data.append(Data("\n".utf8))
        }
        try data.write(to: url, options: .atomic)
    }

    private static func preview(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}

#endif
