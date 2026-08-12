import Foundation

#if DEBUG

public enum MultilingualRetrievalE2EReport {
    public static func writeJSONL(runs: [MultilingualE2ERunSnapshot], to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var lines: [String] = []
        lines.reserveCapacity(runs.count)
        for run in runs {
            let data = try encoder.encode(run)
            guard let line = String(data: data, encoding: .utf8) else { continue }
            lines.append(line)
        }
        let payload = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try payload.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func printRun(_ run: MultilingualE2ERunSnapshot) {
        let runMode = MultilingualRetrievalE2EMode(rawValue: run.runMode) ?? .injectedCarrierFixture
        let tier = MultilingualE2EResultTier(rawValue: run.resultTier) ?? .fail
        let headline = MultilingualE2EResultTierResolver.consoleSummaryLabel(tier: tier, runMode: runMode)
        print(
            "[MultilingualE2E] \(headline) mode=\(run.runMode) scenario=\(run.scenarioID) " +
            "tier=\(run.resultTier) confidence=\(run.productionParityConfidence) " +
            "federationVerified=\(run.federationVerified) overlayFallback=\(run.overlayFallbackUsed) " +
            "selectedOffer=\(run.selectedOfferID ?? "nil") totalMs=\(run.timings.totalMs)"
        )
        if !run.warnings.isEmpty {
            print("[MultilingualE2E] warnings=\(run.warnings.joined(separator: "; "))")
        }
        if !run.failureReasons.isEmpty {
            print("[MultilingualE2E] failures=\(run.failureReasons.joined(separator: "; "))")
        }
    }

    public static func printAggregate(runs: [MultilingualE2ERunSnapshot], artifactPath: String) -> String {
        let passCount = runs.filter(\.passed).count
        let tierCounts = Dictionary(grouping: runs, by: \.resultTier).mapValues(\.count)
        let tierSummary = MultilingualE2EResultTier.allCases
            .map { tier in "\(tier.rawValue)=\(tierCounts[tier.rawValue, default: 0])" }
            .joined(separator: " ")
        let lines = [
            "Multilingual retrieval E2E smoke",
            "pass=\(passCount)/\(runs.count)",
            "tiers: \(tierSummary)",
            "artifact=\(artifactPath)"
        ]
        let text = lines.joined(separator: "\n")
        print("[MultilingualE2E] \(text.replacingOccurrences(of: "\n", with: " | "))")
        return text
    }
}

#endif
