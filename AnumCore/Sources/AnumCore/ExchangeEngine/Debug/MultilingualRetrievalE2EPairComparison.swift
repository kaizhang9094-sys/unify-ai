import Foundation

#if DEBUG

public struct MultilingualRetrievalE2EPairComparison: Sendable, Hashable, Codable {
    public var baselineRunMode: String
    public var liveRunMode: String
    public var bothHaveProviderCanonicalEnglishRetrievalText: Bool
    public var bothOfferObjectUseEnglishOnlyProjection: Bool
    public var serviceAreasMatch: Bool
    public var selectedOfferIDMatch: Bool
    public var forbiddenMissingFactsMatch: Bool
    public var uiPrimaryRequestTextMatch: Bool
    public var timingDeltaMs: Int
    public var summaryLines: [String]

    public init(
        baselineRunMode: String,
        liveRunMode: String,
        bothHaveProviderCanonicalEnglishRetrievalText: Bool,
        bothOfferObjectUseEnglishOnlyProjection: Bool,
        serviceAreasMatch: Bool,
        selectedOfferIDMatch: Bool,
        forbiddenMissingFactsMatch: Bool,
        uiPrimaryRequestTextMatch: Bool,
        timingDeltaMs: Int,
        summaryLines: [String]
    ) {
        self.baselineRunMode = baselineRunMode
        self.liveRunMode = liveRunMode
        self.bothHaveProviderCanonicalEnglishRetrievalText = bothHaveProviderCanonicalEnglishRetrievalText
        self.bothOfferObjectUseEnglishOnlyProjection = bothOfferObjectUseEnglishOnlyProjection
        self.serviceAreasMatch = serviceAreasMatch
        self.selectedOfferIDMatch = selectedOfferIDMatch
        self.forbiddenMissingFactsMatch = forbiddenMissingFactsMatch
        self.uiPrimaryRequestTextMatch = uiPrimaryRequestTextMatch
        self.timingDeltaMs = timingDeltaMs
        self.summaryLines = summaryLines
    }
}

public enum MultilingualRetrievalE2EPairComparisonBuilder {
    public static func compare(
        baseline: MultilingualE2ERunSnapshot,
        live: MultilingualE2ERunSnapshot
    ) -> MultilingualRetrievalE2EPairComparison {
        let baselineCarrier = !(baseline.providerIndexing.providerCanonicalEnglishRetrievalText?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let liveCarrier = !(live.providerIndexing.providerCanonicalEnglishRetrievalText?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        let bothCarrier = baselineCarrier && liveCarrier
        let bothObjectEnglish = baseline.offerObjectUsesEnglishOnlyRetrievalProjection
            && live.offerObjectUsesEnglishOnlyRetrievalProjection
        let serviceAreasMatch = Set(baseline.serviceAreas.map { $0.lowercased() })
            == Set(live.serviceAreas.map { $0.lowercased() })
        let selectedOfferMatch = baseline.selectedOfferID == live.selectedOfferID
        let forbiddenMatch = baseline.secondHalf.forbiddenMissingFactsTriggered.sorted()
            == live.secondHalf.forbiddenMissingFactsTriggered.sorted()
        let uiPrimaryMatch = normalizedPrimaryUI(baseline) == normalizedPrimaryUI(live)
        let timingDelta = live.timings.totalMs - baseline.timings.totalMs

        var lines: [String] = []
        lines.append("providerCarrier baseline=\(baselineCarrier) live=\(liveCarrier)")
        lines.append("offerObjectEnglish baseline=\(baseline.offerObjectUsesEnglishOnlyRetrievalProjection) live=\(live.offerObjectUsesEnglishOnlyRetrievalProjection)")
        lines.append("serviceAreas baseline=\(baseline.serviceAreas.joined(separator: ",")) live=\(live.serviceAreas.joined(separator: ","))")
        lines.append("selectedOffer baseline=\(baseline.selectedOfferID ?? "nil") live=\(live.selectedOfferID ?? "nil")")
        lines.append("forbiddenMissingFacts baseline=\(baseline.secondHalf.forbiddenMissingFactsTriggered.joined(separator: ",")) live=\(live.secondHalf.forbiddenMissingFactsTriggered.joined(separator: ","))")
        lines.append("uiPrimary baseline=\(normalizedPrimaryUI(baseline) ?? "nil") live=\(normalizedPrimaryUI(live) ?? "nil")")
        lines.append("timingMs baseline=\(baseline.timings.totalMs) live=\(live.timings.totalMs) delta=\(timingDelta)")
        if live.timings.totalMs > baseline.timings.totalMs {
            lines.append("warning: live mode slower by \(timingDelta)ms")
        }

        return MultilingualRetrievalE2EPairComparison(
            baselineRunMode: baseline.runMode,
            liveRunMode: live.runMode,
            bothHaveProviderCanonicalEnglishRetrievalText: bothCarrier,
            bothOfferObjectUseEnglishOnlyProjection: bothObjectEnglish,
            serviceAreasMatch: serviceAreasMatch,
            selectedOfferIDMatch: selectedOfferMatch,
            forbiddenMissingFactsMatch: forbiddenMatch,
            uiPrimaryRequestTextMatch: uiPrimaryMatch,
            timingDeltaMs: timingDelta,
            summaryLines: lines
        )
    }

    public static func printComparison(_ comparison: MultilingualRetrievalE2EPairComparison) -> String {
        let text = comparison.summaryLines.joined(separator: "\n")
        print("[MultilingualE2E][Pair] \(comparison.summaryLines.joined(separator: " | "))")
        return text
    }

    private static func normalizedPrimaryUI(_ run: MultilingualE2ERunSnapshot) -> String? {
        let display = run.displaySearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !display.isEmpty { return display }
        let captured = run.capturedRequestText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return captured.isEmpty ? nil : captured
    }
}

#endif
