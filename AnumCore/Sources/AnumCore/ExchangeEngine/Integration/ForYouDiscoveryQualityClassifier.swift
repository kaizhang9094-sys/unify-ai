import Foundation

/// Inputs for ``ForYouDiscoveryQualityClassifier`` — counts and mixed items only (no prompts/tags text).
public struct ForYouDiscoveryQualityInputs: Sendable, Hashable {
    public var rawDirectoryMatchCount: Int
    public var afterLocalFilterCount: Int
    public var mixedItemCount: Int
    public var mixedItems: [ExchangeModels.ForYouItem]
    public var mixQualitySummary: String?
    public var directoryClientUnavailable: Bool

    public init(
        rawDirectoryMatchCount: Int,
        afterLocalFilterCount: Int,
        mixedItemCount: Int,
        mixedItems: [ExchangeModels.ForYouItem],
        mixQualitySummary: String? = nil,
        directoryClientUnavailable: Bool = false
    ) {
        self.rawDirectoryMatchCount = rawDirectoryMatchCount
        self.afterLocalFilterCount = afterLocalFilterCount
        self.mixedItemCount = mixedItemCount
        self.mixedItems = mixedItems
        self.mixQualitySummary = mixQualitySummary
        self.directoryClientUnavailable = directoryClientUnavailable
    }
}

/// Conservative For You rail quality (legible sparse vs weak vs strong).
public enum ForYouDiscoveryQualityClassifier {

    public static func classify(_ inputs: ForYouDiscoveryQualityInputs) -> ExchangeModels.ForYouDiscoveryQuality {
        let raw = max(0, inputs.rawDirectoryMatchCount)
        let afterFilter = max(0, inputs.afterLocalFilterCount)
        let mixed = max(0, inputs.mixedItemCount)
        let scores = inputs.mixedItems.compactMap(\.retrievalFitScore)
        let topScore = scores.max() ?? 0
        let withProfile = inputs.mixedItems.filter { ($0.publicProfileID?.isEmpty == false) }.count
        let profileRatio = mixed > 0 ? Double(withProfile) / Double(mixed) : 0
        let withHeadline = inputs.mixedItems.filter {
            ($0.headline?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        }.count
        let headlineRatio = mixed > 0 ? Double(withHeadline) / Double(mixed) : 0
        let withFacts = inputs.mixedItems.filter { !$0.discoveryFactLines.isEmpty || !$0.publicFactLines.isEmpty }
            .count
        let factsRatio = mixed > 0 ? Double(withFacts) / Double(mixed) : 0
        let directRatio = mixed > 0
            ? Double(inputs.mixedItems.filter(\.canAutonomouslyContact).count) / Double(mixed)
            : 0

        #if DEBUG
        Swift.print(
            "[ForYouQuality] raw=\(raw) afterFilter=\(afterFilter) mixed=\(mixed) tier=computing topScore=\(String(format: "%.1f", topScore)) mixSummary=\(inputs.mixQualitySummary ?? "nil")"
        )
        #endif

        if inputs.directoryClientUnavailable {
            let q = ExchangeModels.ForYouDiscoveryQuality(
                tier: .empty,
                title: "No strong suggestions yet",
                message: "Directory search is not available on this build yet. When it is, For You will suggest public profiles here.",
                suggestedAction: "Complete your public profile · Try again later",
                resultCount: 0,
                rawDirectoryMatchCount: 0,
                afterLocalFilterCount: 0,
                weakReason: "no_directory_client"
            )
            #if DEBUG
            Swift.print("[ForYouQuality] tier=\(q.tier.rawValue) weakReason=\(q.weakReason ?? "nil")")
            #endif
            return q
        }

        if mixed == 0 {
            if raw <= 2 {
                let q = ExchangeModels.ForYouDiscoveryQuality(
                    tier: .sparse,
                    title: "Your network is still growing",
                    message: "For You will improve as more public profiles are available near you.",
                    suggestedAction: "Complete your public profile · Refresh when you’re ready",
                    resultCount: 0,
                    rawDirectoryMatchCount: raw,
                    afterLocalFilterCount: afterFilter,
                    weakReason: "few_raw_matches"
                )
                #if DEBUG
                Swift.print("[ForYouQuality] tier=\(q.tier.rawValue) weakReason=\(q.weakReason ?? "nil")")
                #endif
                return q
            }
            let q = ExchangeModels.ForYouDiscoveryQuality(
                tier: .empty,
                title: "No strong suggestions yet",
                message: "Add more interests or looking-for details to help your AI discover better profiles.",
                suggestedAction: "Complete your public profile · Refresh",
                resultCount: 0,
                rawDirectoryMatchCount: raw,
                afterLocalFilterCount: afterFilter,
                weakReason: afterFilter == 0 ? "filtered_all_before_map" : "mixed_to_zero"
            )
            #if DEBUG
            Swift.print("[ForYouQuality] tier=\(q.tier.rawValue) weakReason=\(q.weakReason ?? "nil")")
            #endif
            return q
        }

        var weakSignals = 0
        var weakReasonParts: [String] = []

        if mixed <= 2 && raw <= 4 {
            weakSignals += 1
            weakReasonParts.append("thin_pool")
        }
        if topScore > 0, topScore < 22 {
            weakSignals += 1
            weakReasonParts.append("low_top_score")
        }
        if mixed >= 2, profileRatio < 0.5 {
            weakSignals += 1
            weakReasonParts.append("profile_sparse")
        }
        if mixed >= 2, headlineRatio < 0.45 {
            weakSignals += 1
            weakReasonParts.append("headline_sparse")
        }
        if mixed >= 2, factsRatio < 0.55 {
            weakSignals += 1
            weakReasonParts.append("facts_sparse")
        }
        if mixed >= 2, directRatio < 0.34 {
            weakSignals += 1
            weakReasonParts.append("reachability_tight")
        }

        let isStrong =
            (mixed >= 4)
            || (mixed >= 2 && topScore >= 20)
            || (mixed == 1 && topScore >= 30)
            || (mixed >= 3 && topScore >= 14 && profileRatio >= 0.66)

        let tier: ExchangeModels.ForYouDiscoveryQualityTier
        let weakReason: String?

        if isStrong && weakSignals < 3 {
            tier = .strong
            weakReason = weakSignals > 0 ? weakReasonParts.joined(separator: ",") : nil
        } else if weakSignals >= 2 || (mixed <= 2 && topScore < 28) || !isStrong {
            tier = .weak
            weakReason = weakReasonParts.isEmpty ? "heuristic_weak" : weakReasonParts.joined(separator: ",")
        } else {
            tier = .strong
            weakReason = nil
        }

        let title: String
        let message: String
        let suggested: String?
        if tier == .strong {
            title = "Great matches"
            message = "Profiles line up well with what you’ve shared publicly."
            suggested = nil
        } else {
            title = "Early matches"
            message = "These are broader suggestions while your network grows."
            suggested = "Complete your public profile · Refresh anytime"
        }

        let q = ExchangeModels.ForYouDiscoveryQuality(
            tier: tier,
            title: title,
            message: message,
            suggestedAction: suggested,
            resultCount: mixed,
            rawDirectoryMatchCount: raw,
            afterLocalFilterCount: afterFilter,
            weakReason: weakReason
        )
        #if DEBUG
        Swift.print("[ForYouQuality] tier=\(q.tier.rawValue) weakReason=\(q.weakReason ?? "nil") topScore=\(String(format: "%.1f", topScore))")
        #endif
        return q
    }
}
