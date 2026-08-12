import Foundation

// MARK: - For You result mixing (conservative; server rank prior)

/// Tunable mix posture for the For You rail. UI selector is a future seam; default is ``balanced``.
public enum ForYouResultMixMode: String, Sendable, CaseIterable, Hashable {
    case balanced
    case nearby
    case similarInterests
    case newFaces
    case opportunity
    case wildcard
}

/// Viewer-side public signals used for lightweight overlap boosts (never local offers / constitution).
public struct ForYouViewerMixSignals: Sendable, Hashable {
    public var interestTags: [String]
    public var openToTags: [String]
    public var regionTags: [String]
    /// Directory tags from standing interest (search + interest + role); optional extra overlap signal.
    public var directoryTags: [String]

    public init(
        interestTags: [String],
        openToTags: [String],
        regionTags: [String],
        directoryTags: [String] = []
    ) {
        self.interestTags = interestTags
        self.openToTags = openToTags
        self.regionTags = regionTags
        self.directoryTags = directoryTags
    }
}

/// Optional knobs for personalization without coupling to AppServices.
public struct ForYouResultMixContext: Sendable, Hashable {
    public var mode: ForYouResultMixMode
    public var dismissedNodeIDs: Set<String>
    public var previouslySeenForYouNodeIDs: Set<String>
    public var trustedNodeIDs: Set<String>
    public var connectedNodeIDs: Set<String>

    public init(
        mode: ForYouResultMixMode = .balanced,
        dismissedNodeIDs: Set<String> = [],
        previouslySeenForYouNodeIDs: Set<String> = [],
        trustedNodeIDs: Set<String> = [],
        connectedNodeIDs: Set<String> = []
    ) {
        self.mode = mode
        self.dismissedNodeIDs = dismissedNodeIDs
        self.previouslySeenForYouNodeIDs = previouslySeenForYouNodeIDs
        self.trustedNodeIDs = trustedNodeIDs
        self.connectedNodeIDs = connectedNodeIDs
    }

    public static let `default` = ForYouResultMixContext()
}

private struct ForYouResultMixFeatures: Sendable, Hashable {
    var serverScore: Double?
    var serverOrderScore: Double
    var regionScore: Double
    var interestOverlapScore: Double
    var openToOverlapScore: Double
    var reachabilityScore: Double
    var completenessScore: Double
    var noveltyScore: Double
}

public struct ForYouResultMixOutput: Sendable, Hashable {
    public var items: [ExchangeModels.ForYouItem]
    /// Short UI-safe chips keyed by `ForYouItem.id` (same as `nodeID` when stable).
    public var reasonChipsByItemID: [String: [String]]
    /// Optional single-line summary for diagnostics; not shown in product UI by default.
    public var qualitySummary: String?

    public init(
        items: [ExchangeModels.ForYouItem],
        reasonChipsByItemID: [String: [String]] = [:],
        qualitySummary: String? = nil
    ) {
        self.items = items
        self.reasonChipsByItemID = reasonChipsByItemID
        self.qualitySummary = qualitySummary
    }
}

/// Conservative post-processor for For You directory results. **Does not** replace server ranking.
public enum ForYouResultMixer {

    public static func mix(
        items: [ExchangeModels.ForYouItem],
        viewer: ForYouViewerMixSignals,
        localNodeID: String?,
        activeUnresolvedCounterpartyIDs: Set<String>,
        context: ForYouResultMixContext = .default
    ) -> ForYouResultMixOutput {
        #if DEBUG
        let serverOrder = items.map(\.nodeID).joined(separator: ",")
        Swift.print("[ForYouRanking][mix] serverOrder=\(serverOrder)")
        var mixerDiagDropped: [String] = []
        mixerDiagDropped.reserveCapacity(8)
        var mixerDiagSurvivingInputOrder: [String] = []
        mixerDiagSurvivingInputOrder.reserveCapacity(items.count)
        #endif

        let weights = Self.weights(for: context.mode)
        let trimmedSelf = localNodeID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let viewerInterest = Self.normalizedTokenSet(viewer.interestTags + viewer.directoryTags)
        let viewerOpenTo = Self.normalizedTokenSet(viewer.openToTags)
        let viewerRegions = Self.normalizedTokenSet(viewer.regionTags)

        let totalCount = max(items.count, 1)

        var scored: [(item: ExchangeModels.ForYouItem, originalIndex: Int, final: Double, serverPrior: Double)] = []
        scored.reserveCapacity(items.count)

        for (idx, item) in items.enumerated() {
            let nid = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            let iid = item.id.trimmingCharacters(in: .whitespacesAndNewlines)

            let dropReason: String?
            if !trimmedSelf.isEmpty, nid == trimmedSelf || iid == trimmedSelf {
                dropReason = "self"
            } else if context.dismissedNodeIDs.contains(nid) || context.dismissedNodeIDs.contains(iid) {
                dropReason = "dismissed"
            } else if activeUnresolvedCounterpartyIDs.contains(nid) || activeUnresolvedCounterpartyIDs.contains(iid) {
                dropReason = "activeThread"
            } else {
                dropReason = nil
            }

            if let reason = dropReason {
                #if DEBUG
                mixerDiagDropped.append("\(nid):\(reason)")
                #endif
                continue
            }

            #if DEBUG
            mixerDiagSurvivingInputOrder.append(nid)
            #endif

            let features = Self.computeFeatures(
                item: item,
                originalIndex: idx,
                totalCount: totalCount,
                viewerInterest: viewerInterest,
                viewerOpenTo: viewerOpenTo,
                viewerRegions: viewerRegions,
                context: context
            )

            let ioBlend = 0.5 * features.interestOverlapScore + 0.5 * features.openToOverlapScore
            let serverPrior = Self.serverPriorComponent(
                normalizedOrder: features.serverOrderScore,
                normalizedScore: features.serverScore.map { Self.normalizeServerScoreInBatch($0, items: items) }
            )

            var final = weights.wServer * serverPrior
                + weights.wRegion * features.regionScore
                + weights.wInterestOpenTo * ioBlend
                + weights.wReach * features.reachabilityScore
                + weights.wComplete * features.completenessScore
                + weights.wNovel * features.noveltyScore

            if context.trustedNodeIDs.contains(nid) || context.trustedNodeIDs.contains(iid) {
                final += 0.012
            }

            let chips = Self.reasonChips(
                item: item,
                features: features,
                serverPrior: serverPrior,
                context: context
            )

            var stamped = item
            stamped.mixReasonChips = chips
            scored.append((stamped, idx, final, serverPrior))
        }

        guard !scored.isEmpty else {
            #if DEBUG
            Swift.print("[ForYouRanking][mix] finalOrder=")
            Swift.print(
                "[ForYouMixerDiag][output] thinPool=notUsedInMixer order= dropped=\(mixerDiagDropped.joined(separator: ",")) reordered=false"
            )
            #endif
            return ForYouResultMixOutput(
                items: [],
                reasonChipsByItemID: [:],
                qualitySummary: Self.qualitySummaryLine(mode: context.mode, count: 0)
            )
        }

        #if DEBUG
        let mixerDiagPreSortOrder = scored.map { $0.item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines) }
        let mixerDiagContextLine =
            "mode=\(context.mode.rawValue) dismissed=\(context.dismissedNodeIDs.count) previouslyShown=\(context.previouslySeenForYouNodeIDs.count) trusted=\(context.trustedNodeIDs.count) connected=\(context.connectedNodeIDs.count) activeThreadExclusion=\(activeUnresolvedCounterpartyIDs.count)"
        let mixerDiagInputScores = items.map { item -> String in
            let nid = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            let s = item.retrievalFitScore.map { String(format: "%.2f", $0) } ?? "nil"
            return "\(nid)(serverScore=\(s))"
        }.joined(separator: "|")
        Swift.print("[ForYouMixerDiag][input] thinPool=notUsedInMixer affectsTierOnly=false \(mixerDiagContextLine) order=\(mixerDiagInputScores)")
        #endif

        let tieEpsilon = 0.015
        let sorted = scored.sorted { a, b in
            if abs(a.final - b.final) > 1e-9 {
                return a.final > b.final
            }
            if abs(a.serverPrior - b.serverPrior) > 1e-9 {
                return a.serverPrior > b.serverPrior
            }
            return a.originalIndex < b.originalIndex
        }

        var ordered = Self.applyDiversityNearTies(
            sorted,
            tieEpsilon: tieEpsilon,
            serverPriorGapMax: 0.04
        )

        if context.mode == .wildcard {
            ordered = Self.applyDiversityNearTies(ordered, tieEpsilon: tieEpsilon * 1.35, serverPriorGapMax: 0.045)
        }

        var chipsMap: [String: [String]] = [:]
        chipsMap.reserveCapacity(ordered.count)
        var outItems: [ExchangeModels.ForYouItem] = []
        outItems.reserveCapacity(ordered.count)
        for row in ordered {
            outItems.append(row.item)
            chipsMap[row.item.id] = row.item.mixReasonChips
        }

        let summary = Self.qualitySummaryLine(mode: context.mode, count: outItems.count)

        #if DEBUG
        let finalOrder = outItems.map(\.nodeID).joined(separator: ",")
        Swift.print("[ForYouRanking][mix] finalOrder=\(finalOrder)")
        let sortReordered = mixerDiagPreSortOrder != sorted.map { $0.item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines) }
        let outIDs = outItems.map { $0.nodeID.trimmingCharacters(in: .whitespacesAndNewlines) }
        let diversityOrSortReordered = mixerDiagSurvivingInputOrder != outIDs
        let mixerDiagOutScores = outItems.map { item -> String in
            let nid = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
            let s = item.retrievalFitScore.map { String(format: "%.2f", $0) } ?? "nil"
            return "\(nid)(serverScore=\(s))"
        }.joined(separator: "|")
        Swift.print(
            "[ForYouMixerDiag][output] thinPool=notUsedInMixer order=\(mixerDiagOutScores) dropped=\(mixerDiagDropped.joined(separator: ",")) reordered=\(diversityOrSortReordered) sortReordered=\(sortReordered)"
        )
        #endif

        return ForYouResultMixOutput(items: outItems, reasonChipsByItemID: chipsMap, qualitySummary: summary)
    }

    // MARK: - Weights (sum to 1.0; server branch ≥ 0.55 for wildcard)

    private struct ModeWeights: Sendable {
        var wServer: Double
        var wRegion: Double
        var wInterestOpenTo: Double
        var wReach: Double
        var wComplete: Double
        var wNovel: Double
    }

    private static func weights(for mode: ForYouResultMixMode) -> ModeWeights {
        switch mode {
        case .balanced:
            return .init(wServer: 0.75, wRegion: 0.08, wInterestOpenTo: 0.07, wReach: 0.05, wComplete: 0.05, wNovel: 0.0)
        case .nearby:
            return .init(wServer: 0.68, wRegion: 0.17, wInterestOpenTo: 0.06, wReach: 0.05, wComplete: 0.04, wNovel: 0.0)
        case .similarInterests:
            return .init(wServer: 0.68, wRegion: 0.06, wInterestOpenTo: 0.17, wReach: 0.05, wComplete: 0.04, wNovel: 0.0)
        case .newFaces:
            return .init(wServer: 0.70, wRegion: 0.05, wInterestOpenTo: 0.05, wReach: 0.05, wComplete: 0.04, wNovel: 0.11)
        case .opportunity:
            return .init(wServer: 0.70, wRegion: 0.06, wInterestOpenTo: 0.06, wReach: 0.10, wComplete: 0.08, wNovel: 0.0)
        case .wildcard:
            return .init(wServer: 0.57, wRegion: 0.09, wInterestOpenTo: 0.11, wReach: 0.07, wComplete: 0.06, wNovel: 0.10)
        }
    }

    // MARK: - Features

    private static func computeFeatures(
        item: ExchangeModels.ForYouItem,
        originalIndex: Int,
        totalCount: Int,
        viewerInterest: Set<String>,
        viewerOpenTo: Set<String>,
        viewerRegions: Set<String>,
        context: ForYouResultMixContext
    ) -> ForYouResultMixFeatures {
        let n = max(totalCount, 1)
        let serverOrderScore = 1.0 - (Double(originalIndex) / Double(n))

        let candidateBagTokens = Self.normalizedTokenSet(
            item.dominantTags
                + item.discoveryMatchedTerms
                + Self.tokenize(item.headline ?? "")
        )
        let candidateHaystack = Self.normalizedHaystack(
            item.discoveryFactLines + item.publicFactLines + [item.headline ?? ""]
        )

        let interestOverlap = Self.jaccard(viewerInterest, candidateBagTokens)
        let openToOverlap = Self.jaccard(viewerOpenTo, candidateBagTokens)

        let regionOverlap: Double
        if viewerRegions.isEmpty {
            regionOverlap = 0.0
        } else {
            let hitCount = viewerRegions.filter { region in
                candidateHaystack.contains(region)
                    || candidateBagTokens.contains(where: { $0.contains(region) || region.contains($0) })
            }.count
            regionOverlap = min(1.0, Double(hitCount) / Double(max(viewerRegions.count, 1)))
        }

        let reachability: Double
        if item.canAutonomouslyContact {
            reachability = 1.0
        } else if item.acceptingInbound {
            reachability = 0.45
        } else {
            reachability = 0.2
        }

        var completeness: Double = 0.0
        if let url = item.primaryImageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            completeness += 0.34
        }
        if let h = item.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            completeness += 0.33
        }
        if item.discoveryFactLines.count >= 2 {
            completeness += 0.33
        }
        completeness = min(1.0, completeness)

        let nid = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let iid = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        var novelty: Double = 1.0
        if context.connectedNodeIDs.contains(nid) || context.connectedNodeIDs.contains(iid) {
            novelty = min(novelty, 0.35)
        }
        if context.previouslySeenForYouNodeIDs.contains(nid)
            || context.previouslySeenForYouNodeIDs.contains(iid) {
            novelty = min(novelty, 0.25)
        }

        return ForYouResultMixFeatures(
            serverScore: item.retrievalFitScore,
            serverOrderScore: serverOrderScore,
            regionScore: min(1.0, regionOverlap),
            interestOverlapScore: min(1.0, interestOverlap),
            openToOverlapScore: min(1.0, openToOverlap),
            reachabilityScore: reachability,
            completenessScore: completeness,
            noveltyScore: novelty
        )
    }

    private static func serverPriorComponent(
        normalizedOrder: Double,
        normalizedScore: Double?
    ) -> Double {
        if let s = normalizedScore {
            return 0.5 * s + 0.5 * normalizedOrder
        }
        return normalizedOrder
    }

    /// Min–max normalize raw directory scores across the **incoming** list (pre-filter), bounded to [0,1].
    private static func normalizeServerScoreInBatch(
        _ score: Double,
        items: [ExchangeModels.ForYouItem]
    ) -> Double {
        let scores = items.compactMap(\.retrievalFitScore)
        guard let minV = scores.min(), let maxV = scores.max(), maxV > minV else {
            return 0.5
        }
        let t = (score - minV) / (maxV - minV)
        return min(1.0, max(0.0, t))
    }

    private static func diversityKey(for item: ExchangeModels.ForYouItem) -> String {
        let raw = (item.dominantTags.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.isEmpty { return "∅" }
        return String(raw.prefix(14))
    }

    // MARK: - Diversity (near-ties only)

    private static func applyDiversityNearTies(
        _ rows: [(item: ExchangeModels.ForYouItem, originalIndex: Int, final: Double, serverPrior: Double)],
        tieEpsilon: Double,
        serverPriorGapMax: Double
    ) -> [(item: ExchangeModels.ForYouItem, originalIndex: Int, final: Double, serverPrior: Double)] {
        guard rows.count > 1 else { return rows }
        var out = rows

        let window = 4
        var i = 0
        while i < out.count - 1 {
            let a = out[i]
            let b = out[i + 1]
            let sameKey = Self.diversityKey(for: a.item) == Self.diversityKey(for: b.item)
            let nearTie = abs(a.final - b.final) < tieEpsilon

            if sameKey && nearTie {
                if let m = Self.findSwapIndex(
                    rows: out,
                    from: i + 1,
                    window: window,
                    tieEpsilon: tieEpsilon,
                    serverPriorGapMax: serverPriorGapMax,
                    avoidKey: Self.diversityKey(for: a.item)
                ) {
                    out.swapAt(i + 1, m)
                }
            }
            i += 1
        }
        return out
    }

    private static func findSwapIndex(
        rows: [(item: ExchangeModels.ForYouItem, originalIndex: Int, final: Double, serverPrior: Double)],
        from: Int,
        window: Int,
        tieEpsilon: Double,
        serverPriorGapMax: Double,
        avoidKey: String
    ) -> Int? {
        let anchor = rows[from]
        let upper = min(rows.count, from + window)
        for j in (from + 1)..<upper {
            let cand = rows[j]
            guard Self.diversityKey(for: cand.item) != avoidKey else { continue }
            guard abs(cand.final - anchor.final) < tieEpsilon * 1.4 else { continue }
            guard cand.serverPrior >= anchor.serverPrior - serverPriorGapMax else { continue }
            return j
        }
        return nil
    }

    // MARK: - Reason chips

    private static func reasonChips(
        item: ExchangeModels.ForYouItem,
        features: ForYouResultMixFeatures,
        serverPrior: Double,
        context: ForYouResultMixContext
    ) -> [String] {
        var chips: [String] = []
        chips.reserveCapacity(3)

        let nid = item.nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let iid = item.id.trimmingCharacters(in: .whitespacesAndNewlines)

        if features.regionScore >= 0.34 {
            chips.append("Nearby")
        }
        if features.interestOverlapScore >= 0.22 {
            chips.append("Shared interests")
        }
        if features.openToOverlapScore >= 0.22 {
            chips.append("Looking for similar things")
        }
        if features.reachabilityScore >= 0.95 {
            chips.append("Easy to contact")
        }
        if context.mode == .newFaces || context.mode == .wildcard {
            if !context.previouslySeenForYouNodeIDs.isEmpty,
               !context.previouslySeenForYouNodeIDs.contains(nid),
               !context.previouslySeenForYouNodeIDs.contains(iid),
               features.noveltyScore >= 0.9 {
                chips.append("Fresh suggestion")
            }
        }
        if serverPrior >= 0.82 {
            chips.append("Strong match")
        }

        var seen = Set<String>()
        let deduped = chips.filter { seen.insert($0).inserted }
        return Array(deduped.prefix(3))
    }

    private static func qualitySummaryLine(mode: ForYouResultMixMode, count: Int) -> String {
        "ForYou mix mode=\(mode.rawValue) items=\(count)"
    }

    // MARK: - Text helpers

    private static func normalizedTokenSet(_ values: [String]) -> Set<String> {
        var out: Set<String> = []
        for v in values {
            for t in tokenize(v) where !t.isEmpty {
                out.insert(t)
            }
        }
        return out
    }

    private static func tokenize(_ text: String) -> [String] {
        let lower = text.lowercased()
        let scalars = lower.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" {
                return Character(scalar)
            }
            return " "
        }
        let rebuilt = String(scalars)
        return rebuilt.split(separator: " ").map(String.init)
    }

    private static func normalizedHaystack(_ lines: [String]) -> String {
        lines
            .joined(separator: " ")
            .lowercased()
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty || b.isEmpty { return 0.0 }
        let inter = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0.0 }
        return Double(inter) / Double(union)
    }
}
