import Foundation

#if DEBUG

public struct MultilingualRetrievalE2ETripleComparison: Sendable, Hashable, Codable {
    public var baselineRunMode: String
    public var liveRunMode: String
    public var fullFacadeRunMode: String
    public var firstModeMissingProviderCarrier: String?
    public var baselineHasCarrier: Bool
    public var liveHasCarrier: Bool
    public var fullFacadeHasCarrier: Bool
    public var resultTierByMode: [String: String]
    public var productionParityConfidenceByMode: [String: String]
    public var selectedOfferIDByMode: [String: String]
    public var forbiddenMissingFactsByMode: [String: [String]]
    public var federationVerified: Bool
    public var overlayFallbackUsed: Bool
    public var federationRoundTripSucceeded: Bool
    public var fullFacadeUsesOverlayFallback: Bool
    public var timingDeltaMsByMode: [String: Int]
    public var summaryLines: [String]

    public init(
        baselineRunMode: String,
        liveRunMode: String,
        fullFacadeRunMode: String,
        firstModeMissingProviderCarrier: String?,
        baselineHasCarrier: Bool,
        liveHasCarrier: Bool,
        fullFacadeHasCarrier: Bool,
        resultTierByMode: [String: String],
        productionParityConfidenceByMode: [String: String],
        selectedOfferIDByMode: [String: String],
        forbiddenMissingFactsByMode: [String: [String]],
        federationVerified: Bool,
        overlayFallbackUsed: Bool,
        federationRoundTripSucceeded: Bool,
        fullFacadeUsesOverlayFallback: Bool,
        timingDeltaMsByMode: [String: Int],
        summaryLines: [String]
    ) {
        self.baselineRunMode = baselineRunMode
        self.liveRunMode = liveRunMode
        self.fullFacadeRunMode = fullFacadeRunMode
        self.firstModeMissingProviderCarrier = firstModeMissingProviderCarrier
        self.baselineHasCarrier = baselineHasCarrier
        self.liveHasCarrier = liveHasCarrier
        self.fullFacadeHasCarrier = fullFacadeHasCarrier
        self.resultTierByMode = resultTierByMode
        self.productionParityConfidenceByMode = productionParityConfidenceByMode
        self.selectedOfferIDByMode = selectedOfferIDByMode
        self.forbiddenMissingFactsByMode = forbiddenMissingFactsByMode
        self.federationVerified = federationVerified
        self.overlayFallbackUsed = overlayFallbackUsed
        self.federationRoundTripSucceeded = federationRoundTripSucceeded
        self.fullFacadeUsesOverlayFallback = fullFacadeUsesOverlayFallback
        self.timingDeltaMsByMode = timingDeltaMsByMode
        self.summaryLines = summaryLines
    }
}

public enum MultilingualRetrievalE2ETripleComparisonBuilder {
    public static func compare(
        baseline: MultilingualE2ERunSnapshot,
        live: MultilingualE2ERunSnapshot,
        fullFacade: MultilingualE2ERunSnapshot
    ) -> MultilingualRetrievalE2ETripleComparison {
        let baselineCarrier = hasCarrier(baseline)
        let liveCarrier = hasCarrier(live)
        let fullFacadeCarrier = hasCarrier(fullFacade)

        let firstMissing = firstModeMissingCarrier(
            baselineHasCarrier: baselineCarrier,
            liveHasCarrier: liveCarrier,
            fullFacadeHasCarrier: fullFacadeCarrier
        )

        let federationOK = fullFacade.providerIndexing.fullFacadePublication?.federationRoundTripSucceeded ?? false
        let overlayFallback = fullFacade.overlayFallbackUsed

        let resultTierByMode: [String: String] = [
            baseline.runMode: baseline.resultTier,
            live.runMode: live.resultTier,
            fullFacade.runMode: fullFacade.resultTier
        ]
        let confidenceByMode: [String: String] = [
            baseline.runMode: baseline.productionParityConfidence,
            live.runMode: live.productionParityConfidence,
            fullFacade.runMode: fullFacade.productionParityConfidence
        ]
        let selectedByMode: [String: String] = [
            baseline.runMode: baseline.selectedOfferID ?? "nil",
            live.runMode: live.selectedOfferID ?? "nil",
            fullFacade.runMode: fullFacade.selectedOfferID ?? "nil"
        ]
        let forbiddenByMode: [String: [String]] = [
            baseline.runMode: baseline.secondHalf.forbiddenMissingFactsTriggered,
            live.runMode: live.secondHalf.forbiddenMissingFactsTriggered,
            fullFacade.runMode: fullFacade.secondHalf.forbiddenMissingFactsTriggered
        ]
        let timingDelta: [String: Int] = [
            baseline.runMode: 0,
            live.runMode: live.timings.totalMs - baseline.timings.totalMs,
            fullFacade.runMode: fullFacade.timings.totalMs - baseline.timings.totalMs
        ]

        var lines: [String] = []
        lines.append("resultTier baseline=\(baseline.resultTier) live=\(live.resultTier) fullFacade=\(fullFacade.resultTier)")
        lines.append("confidence baseline=\(baseline.productionParityConfidence) live=\(live.productionParityConfidence) fullFacade=\(fullFacade.productionParityConfidence)")
        lines.append("carrier baseline=\(baselineCarrier) live=\(liveCarrier) fullFacade=\(fullFacadeCarrier)")
        lines.append("firstMissingCarrierMode=\(firstMissing ?? "none")")
        lines.append("selectedOffer baseline=\(baseline.selectedOfferID ?? "nil") live=\(live.selectedOfferID ?? "nil") fullFacade=\(fullFacade.selectedOfferID ?? "nil")")
        lines.append("forbiddenMissingFacts baseline=\(baseline.secondHalf.forbiddenMissingFactsTriggered.joined(separator: ",")) live=\(live.secondHalf.forbiddenMissingFactsTriggered.joined(separator: ",")) fullFacade=\(fullFacade.secondHalf.forbiddenMissingFactsTriggered.joined(separator: ","))")
        lines.append("federationVerified=\(fullFacade.federationVerified) overlayFallback=\(fullFacade.overlayFallbackUsed)")
        lines.append("federationRoundTrip=\(federationOK) fullFacadeOverlayFallback=\(overlayFallback)")
        lines.append("timingMs baseline=\(baseline.timings.totalMs) live=\(live.timings.totalMs) fullFacade=\(fullFacade.timings.totalMs)")

        return MultilingualRetrievalE2ETripleComparison(
            baselineRunMode: baseline.runMode,
            liveRunMode: live.runMode,
            fullFacadeRunMode: fullFacade.runMode,
            firstModeMissingProviderCarrier: firstMissing,
            baselineHasCarrier: baselineCarrier,
            liveHasCarrier: liveCarrier,
            fullFacadeHasCarrier: fullFacadeCarrier,
            resultTierByMode: resultTierByMode,
            productionParityConfidenceByMode: confidenceByMode,
            selectedOfferIDByMode: selectedByMode,
            forbiddenMissingFactsByMode: forbiddenByMode,
            federationVerified: fullFacade.federationVerified,
            overlayFallbackUsed: fullFacade.overlayFallbackUsed,
            federationRoundTripSucceeded: federationOK,
            fullFacadeUsesOverlayFallback: overlayFallback,
            timingDeltaMsByMode: timingDelta,
            summaryLines: lines
        )
    }

    public static func printComparison(_ comparison: MultilingualRetrievalE2ETripleComparison) -> String {
        let text = comparison.summaryLines.joined(separator: "\n")
        print("[MultilingualE2E][Triple] \(comparison.summaryLines.joined(separator: " | "))")
        return text
    }

    public static func firstModeMissingCarrier(
        baselineHasCarrier: Bool,
        liveHasCarrier: Bool,
        fullFacadeHasCarrier: Bool
    ) -> String? {
        if !baselineHasCarrier {
            return MultilingualRetrievalE2EMode.injectedCarrierFixture.rawValue
        }
        if !liveHasCarrier {
            return MultilingualRetrievalE2EMode.livePublishEnricher.rawValue
        }
        if !fullFacadeHasCarrier {
            return MultilingualRetrievalE2EMode.fullFacadePublishPath.rawValue
        }
        return nil
    }

    private static func hasCarrier(_ run: MultilingualE2ERunSnapshot) -> Bool {
        !(run.providerIndexing.providerCanonicalEnglishRetrievalText?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

#endif
