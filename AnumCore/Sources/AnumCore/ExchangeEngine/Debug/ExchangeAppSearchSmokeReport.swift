import Foundation

#if DEBUG

public enum ExchangeAppSearchSmokeReport {
    public struct AggregateMetrics: Sendable, Hashable, Codable {
        public var runs: Int
        public var strictPass: Int
        public var engineVsThreadMismatch: Int
        public var threadVsUIMismatch: Int
        public var forbiddenAttachmentViolations: Int
        public var objectLaneFP: Int
        public var objectLaneFN: Int
        public var wrongFallbackOfferSelections: Int
        public var serverResponseModeMismatch: Int
        public var top1Primary: Double
        public var top1AnyRequired: Double
        public var top3AnyRequired: Double
        public var latencyAvgMs: Double
        public var latencyP95Ms: Double
    }

    public static func printRun(_ run: AppSearchSmokeRunSnapshot) {
        print(
            """
            [APP-SEARCH-SMOKE] run=\(run.runIndex)/\(run.totalRuns) query="\(run.query)" scenario=\(run.scenarioID)
            strict=\(run.strictPassed ? "PASS" : "FAIL")
            threadID=\(run.thread.threadID)
            intentClass=\(run.engine.intentClass ?? "nil")
            facetsQueryIntentClass=\(run.engine.facetsQueryIntentClass ?? "nil")
            objectType=\(run.engine.objectType ?? "nil")
            domainCategory=\(run.engine.domainCategory ?? "nil")
            transactionIntent=\(run.engine.transactionIntent ?? "nil")
            objectLaneActive=\(run.engine.objectLaneActive)
            discoveryCalled=\(run.engine.discoveryCalled)
            serverBaseURL=\(run.serverBaseURL)
            responseMode=\(run.engine.responseMode)
            topNodes=\(run.engine.topNodes)
            selectedOfferID_engine=\(run.engine.selectedOfferID ?? "nil")
            selectedOfferID_thread=\(run.thread.selectedOfferID ?? "nil")
            selectedOfferID_ui=\(run.ui.selectedOfferID ?? "nil")
            matchedOffers_engine=\(run.engine.matchedOffersByNode)
            matchedOffers_thread=\(run.thread.matchedOffersByNode)
            provenObjectOfferIDs=\(run.engine.provenObjectOfferIDs)
            forbiddenViolations=\(run.engine.forbiddenAttachmentViolations)
            objectLaneFP=\(run.engine.objectLaneFP)
            objectLaneFN=\(run.engine.objectLaneFN)
            engineVsThreadMismatch=\(run.engineVsThreadMismatch)
            threadVsUIMismatch=\(run.threadVsUIMismatch)
            uiProjectionIssues=\(run.uiProjectionIssues)
            runtimeWiringIssues=\(run.runtimeWiringIssues)
            serverRoundTripIssues=\(run.engine.serverRoundTripIssues)
            wrongFallbackOfferSelections=\(run.wrongFallbackOfferSelections)
            latencyMs=\(run.latencyMs)
            """
        )
        if !run.engine.strictFailures.isEmpty {
            print("strictFailures=\(run.engine.strictFailures)")
        }
    }

    public static func makeAggregateMetrics(from runs: [AppSearchSmokeRunSnapshot]) -> AggregateMetrics {
        var engineThread = 0
        var threadUI = 0
        var forbidden = 0
        var olFP = 0
        var olFN = 0
        var fallback = 0
        var modeMismatch = 0
        var top1PrimaryHits = 0
        var top1AnyHits = 0
        var top3AnyHits = 0
        var rankingExpectations = 0

        for run in runs {
            if !run.engineVsThreadMismatch.isEmpty { engineThread += 1 }
            if !run.threadVsUIMismatch.isEmpty { threadUI += 1 }
            forbidden += run.engine.forbiddenAttachmentViolations
            olFP += run.engine.objectLaneFP
            olFN += run.engine.objectLaneFN
            fallback += run.wrongFallbackOfferSelections
            if run.engine.serverRoundTripIssues.contains(where: { $0.contains("responseMode") }) {
                modeMismatch += 1
            }
            if let primary = run.observationalTop1PrimaryHit,
               let anyRequired = run.observationalTop1AnyRequiredHit {
                rankingExpectations += 1
                if primary { top1PrimaryHits += 1 }
                if anyRequired { top1AnyHits += 1 }
            }
            if run.observationalTop3AnyRequiredHit == true {
                top3AnyHits += 1
            }
        }

        let latencies = runs.map { Double($0.latencyMs) }.sorted()
        let avg = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let p95Index = max(0, min(latencies.count - 1, Int(Double(latencies.count) * 0.95) - 1))
        let p95 = latencies.isEmpty ? 0 : latencies[p95Index]
        let rankingDenominator = max(rankingExpectations, 1)

        return AggregateMetrics(
            runs: runs.count,
            strictPass: runs.filter(\.strictPassed).count,
            engineVsThreadMismatch: engineThread,
            threadVsUIMismatch: threadUI,
            forbiddenAttachmentViolations: forbidden,
            objectLaneFP: olFP,
            objectLaneFN: olFN,
            wrongFallbackOfferSelections: fallback,
            serverResponseModeMismatch: modeMismatch,
            top1Primary: rankingExpectations == 0 ? 0 : Double(top1PrimaryHits) / Double(rankingDenominator),
            top1AnyRequired: rankingExpectations == 0 ? 0 : Double(top1AnyHits) / Double(rankingDenominator),
            top3AnyRequired: rankingExpectations == 0 ? 0 : Double(top3AnyHits) / Double(max(rankingExpectations, 1)),
            latencyAvgMs: avg,
            latencyP95Ms: p95
        )
    }

    public static func printAggregate(
        metrics: AggregateMetrics,
        artifactPath: String?,
        publishGenerationID: String?
    ) -> String {
        let text =
            """
            [APP-SEARCH-SMOKE-AGGREGATE]
            runs=\(metrics.runs)
            strictPass=\(metrics.strictPass)/\(metrics.runs)
            engineVsThreadMismatch=\(metrics.engineVsThreadMismatch)
            threadVsUIMismatch=\(metrics.threadVsUIMismatch)
            forbiddenAttachmentViolations=\(metrics.forbiddenAttachmentViolations)
            objectLaneFP=\(metrics.objectLaneFP)
            objectLaneFN=\(metrics.objectLaneFN)
            wrongFallbackOfferSelections=\(metrics.wrongFallbackOfferSelections)
            serverResponseModeMismatch=\(metrics.serverResponseModeMismatch)
            top1Primary=\(String(format: "%.2f", metrics.top1Primary))
            top1AnyRequired=\(String(format: "%.2f", metrics.top1AnyRequired))
            top3AnyRequired=\(String(format: "%.2f", metrics.top3AnyRequired))
            latencyAvgMs=\(String(format: "%.0f", metrics.latencyAvgMs))
            latencyP95Ms=\(String(format: "%.0f", metrics.latencyP95Ms))
            artifact=\(artifactPath ?? "nil")
            publishGenerationID=\(publishGenerationID ?? "nil")
            """
        print(text)
        return text
    }

    public static func writeJSONL(runs: [AppSearchSmokeRunSnapshot], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var lines: [String] = []
        lines.reserveCapacity(runs.count)
        for run in runs {
            let data = try encoder.encode(run)
            guard let line = String(data: data, encoding: .utf8) else { continue }
            lines.append(line)
        }
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

#endif
