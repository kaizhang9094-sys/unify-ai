import Foundation

#if DEBUG

public enum MultilingualSecretaryLiveSubsetReport {
    public static func defaultArtifactURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent("multilingual_live_subset_audit.jsonl", isDirectory: false)
    }

    public static func writeJSONL(records: [MultilingualSecretaryLiveSubsetAuditRecord], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var lines: [String] = []
        lines.reserveCapacity(records.count)
        for record in records {
            let data = try encoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else { continue }
            lines.append(line)
        }
        let payload = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try payload.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func noisyOutrankingDetected(failureReasons: [String]) -> Bool {
        failureReasons.contains(where: { $0.contains("noisy profile/offer outranked exact object offer") })
    }

    public static func carrierLost(
        failureReasons: [String],
        providerCanonicalEnglishRetrievalText: String?
    ) -> Bool {
        if failureReasons.contains(where: { $0.contains("canonicalEnglishRetrievalText missing") }) {
            return true
        }
        let carrier = providerCanonicalEnglishRetrievalText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return carrier.isEmpty
    }

    public static func defaultSummaryArtifactURL() -> URL {
        defaultArtifactURL().deletingLastPathComponent()
            .appendingPathComponent("multilingual_live_subset_summary.json", isDirectory: false)
    }

    public static func writeSummaryJSON(
        summary: MultilingualSecretaryLiveSubsetSummary,
        to url: URL
    ) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let artifact = MultilingualSecretaryLiveSubsetBatchSummaryArtifact(
            summary: summary,
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(artifact)
        try data.write(to: url, options: [.atomic])
    }

    public static func summarize(
        _ records: [MultilingualSecretaryLiveSubsetAuditRecord],
        config: MultilingualSecretaryLiveSubsetClusteringConfig = .default
    ) -> MultilingualSecretaryLiveSubsetSummary {
        let passCount = records.filter(\.passed).count
        let failCount = records.count - passCount
        let warningCount = records.reduce(0) { $0 + $1.warnings.count }
        let totalLatency = records.map(\.timings.totalMs)
        let averageTotalLatencyMs = totalLatency.isEmpty
            ? 0
            : totalLatency.reduce(0, +) / totalLatency.count
        let slowest = records.max(by: { $0.timings.totalMs < $1.timings.totalMs })
        let failuresByFixture = Dictionary(
            uniqueKeysWithValues: records
                .filter { !$0.failureReasons.isEmpty }
                .map { ($0.fixtureID, $0.failureReasons) }
        )
        let clusters = MultilingualSecretaryLiveSubsetFailureClustering.clusterSummary(
            from: records,
            config: config
        )

        return MultilingualSecretaryLiveSubsetSummary(
            passCount: passCount,
            failCount: failCount,
            warningCount: warningCount,
            averageTotalLatencyMs: averageTotalLatencyMs,
            slowestFixtureID: slowest?.fixtureID,
            slowestTotalLatencyMs: slowest?.timings.totalMs ?? 0,
            carrierLossCount: records.filter(\.carrierLost).count,
            noisyOutrankingCount: records.filter(\.noisyOutrankingDetected).count,
            forbiddenMissingFactCount: records.filter { !$0.forbiddenMissingFactsTriggered.isEmpty }.count,
            failuresByFixture: failuresByFixture,
            categoryCounts: clusters.categoryCounts,
            fixturesByCategory: clusters.fixturesByCategory,
            slowestByCategory: clusters.slowestByCategory
        )
    }

    public static func applyFailureCategories(
        to record: MultilingualSecretaryLiveSubsetAuditRecord,
        config: MultilingualSecretaryLiveSubsetClusteringConfig = .default
    ) -> MultilingualSecretaryLiveSubsetAuditRecord {
        var updated = record
        updated.failureCategories = MultilingualSecretaryLiveSubsetFailureClustering
            .categorize(record, config: config)
            .map(\.rawValue)
        return updated
    }

    public static func printRecord(_ record: MultilingualSecretaryLiveSubsetAuditRecord) {
        print(
            "[MultilingualLiveSubset] \(record.passed ? "PASS" : "FAIL") fixture=\(record.fixtureID) " +
            "mode=\(record.runMode) tier=\(record.resultTier) confidence=\(record.productionParityConfidence) " +
            "selectedOffer=\(record.selectedOfferID ?? "nil") totalMs=\(record.timings.totalMs) " +
            "noisyOutranking=\(record.noisyOutrankingDetected) carrierLost=\(record.carrierLost)"
        )
        if !record.warnings.isEmpty {
            print("[MultilingualLiveSubset] warnings=\(record.warnings.joined(separator: "; "))")
        }
        if !record.failureReasons.isEmpty {
            print("[MultilingualLiveSubset] failures=\(record.failureReasons.joined(separator: "; "))")
        }
        if !record.failureCategories.isEmpty {
            print("[MultilingualLiveSubset] categories=\(record.failureCategories.joined(separator: ","))")
        }
    }

    public static func printSummary(
        _ summary: MultilingualSecretaryLiveSubsetSummary,
        artifactPath: String,
        summaryArtifactPath: String? = nil
    ) -> String {
        var failureLines: [String] = []
        for (fixtureID, reasons) in summary.failuresByFixture.sorted(by: { $0.key < $1.key }) {
            failureLines.append("\(fixtureID): \(reasons.joined(separator: "; "))")
        }
        let clusterLines = MultilingualSecretaryLiveSubsetFailureClustering.failureClusterLines(
            categoryCounts: summary.categoryCounts,
            fixturesByCategory: summary.fixturesByCategory
        )
        var lines = [
            "Multilingual secretary live subset smoke",
            "pass=\(summary.passCount) fail=\(summary.failCount) warnings=\(summary.warningCount)",
            "averageTotalLatencyMs=\(summary.averageTotalLatencyMs)",
            "slowest=\(summary.slowestFixtureID ?? "none") totalMs=\(summary.slowestTotalLatencyMs)",
            "carrierLossCount=\(summary.carrierLossCount)",
            "noisyOutrankingCount=\(summary.noisyOutrankingCount)",
            "forbiddenMissingFactCount=\(summary.forbiddenMissingFactCount)",
            "artifact=\(artifactPath)"
        ]
        if let summaryArtifactPath {
            lines.append("summaryArtifact=\(summaryArtifactPath)")
        }
        lines.append(failureLines.isEmpty ? "failuresByFixture=none" : "failuresByFixture:\n\(failureLines.joined(separator: "\n"))")
        lines.append(clusterLines.isEmpty ? "Failure clusters: none" : "Failure clusters:\n\(clusterLines.joined(separator: "\n"))")
        if !summary.slowestByCategory.isEmpty {
            let slowestLines = summary.slowestByCategory
                .sorted(by: { $0.key < $1.key })
                .map { "- \($0.key): \($0.value)" }
            lines.append("slowestByCategory:\n\(slowestLines.joined(separator: "\n"))")
        }
        let text = lines.joined(separator: "\n")
        print("[MultilingualLiveSubset] \(text.replacingOccurrences(of: "\n", with: " | "))")
        return text
    }
}

#endif
