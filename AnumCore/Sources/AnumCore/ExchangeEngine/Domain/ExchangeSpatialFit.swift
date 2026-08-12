import Foundation

/// Lightweight spatial overlap signal for discovery/retrieval ranking boosts.
public enum ExchangeSpatialFit: Sendable, Hashable {
    case unavailable
    case noOverlap
    case overlap(cellCount: Int)
}

public enum ExchangeSpatialOverlap: Sendable {
    public static func spatialOverlap(
        requester: ExchangeSpatialCoverage?,
        providerAreas: [ExchangeDeclaredServiceArea]
    ) -> ExchangeSpatialFit {
        guard let requester, requester.hasResolvedCells else {
            return .unavailable
        }

        let requesterCells = Set(requester.h3Cells)
        guard !requesterCells.isEmpty else {
            return .unavailable
        }

        var providerCells = Set<String>()
        for area in providerAreas {
            guard let spatial = area.spatial, spatial.hasResolvedCells else { continue }
            providerCells.formUnion(spatial.h3Cells)
        }

        guard !providerCells.isEmpty else {
            return .unavailable
        }

        let intersectionCount = requesterCells.intersection(providerCells).count
        return intersectionCount > 0 ? .overlap(cellCount: intersectionCount) : .noOverlap
    }

    public static func spatialOverlap(
        requesterAnchor: ExchangeRequesterSpatialAnchor?,
        providerAreas: [ExchangeDeclaredServiceArea]
    ) -> ExchangeSpatialFit {
        spatialOverlap(requester: requesterAnchor?.spatial, providerAreas: providerAreas)
    }
}

/// Capped H3 overlap boost / mild demotion for discovery and retrieval scoring.
public struct ExchangeSpatialOverlapScoreAdjustment: Sendable, Hashable {
    public var boost: Double
    public var demotion: Double
    public var fit: ExchangeSpatialFit

    public var scoreDelta: Double { boost - demotion }

    public static let zero = ExchangeSpatialOverlapScoreAdjustment(
        boost: 0,
        demotion: 0,
        fit: .unavailable
    )
}

public enum ExchangeSpatialOverlapScoring: Sendable {
    /// Base boost when at least one H3 cell overlaps.
    public static let baseBoost: Double = 0.04
    /// Maximum H3 overlap boost (small, capped).
    public static let maxBoost: Double = 0.08
    /// Extra boost per overlapping cell, up to `cellCountBoostCap` cells.
    public static let perCellBoostIncrement: Double = 0.01
    public static let cellCountBoostCap: Int = 4
    /// Mild demotion when both sides have H3, no overlap, explicit region required, and text region match failed.
    public static let mildDemotion: Double = 0.04

    public static func boostForOverlap(cellCount: Int) -> Double {
        let cappedCells = min(max(cellCount, 0), cellCountBoostCap)
        let extra = Double(cappedCells) * perCellBoostIncrement
        return min(baseBoost + extra, maxBoost)
    }

    public static func scoreAdjustment(
        fit: ExchangeSpatialFit,
        explicitRegionRequired: Bool,
        textRegionMatchSucceeded: Bool
    ) -> ExchangeSpatialOverlapScoreAdjustment {
        switch fit {
        case .unavailable:
            return .init(boost: 0, demotion: 0, fit: fit)

        case .overlap(let cellCount):
            return .init(
                boost: boostForOverlap(cellCount: cellCount),
                demotion: 0,
                fit: fit
            )

        case .noOverlap:
            let demotion =
                explicitRegionRequired && !textRegionMatchSucceeded ? mildDemotion : 0
            return .init(boost: 0, demotion: demotion, fit: fit)
        }
    }

    public static func evaluate(
        requesterAnchor: ExchangeRequesterSpatialAnchor?,
        providerAreas: [ExchangeDeclaredServiceArea],
        explicitRegionRequired: Bool,
        textRegionMatchSucceeded: Bool
    ) -> ExchangeSpatialOverlapScoreAdjustment {
        let fit = ExchangeSpatialOverlap.spatialOverlap(
            requesterAnchor: requesterAnchor,
            providerAreas: providerAreas
        )
        return scoreAdjustment(
            fit: fit,
            explicitRegionRequired: explicitRegionRequired,
            textRegionMatchSucceeded: textRegionMatchSucceeded
        )
    }

    /// `[DiscoveryH3] spatialFit` log line (metadata only; no cell IDs).
    public static func discoveryLogLine(
        adjustment: ExchangeSpatialOverlapScoreAdjustment,
        requesterResolved: Bool,
        providerHasResolvedH3: Bool
    ) -> String {
        let resultLabel: String = {
            switch adjustment.fit {
            case .unavailable:
                return "unavailable"
            case .noOverlap:
                return "noOverlap"
            case .overlap(let cellCount):
                return "overlap cellCount=\(cellCount)"
            }
        }()
        let delta = String(format: "%.3f", adjustment.scoreDelta)
        return "[DiscoveryH3] spatialFit requester=\(requesterResolved) providerH3=\(providerHasResolvedH3) result=\(resultLabel) scoreDelta=\(delta)"
    }

    public static func providerHasResolvedH3(_ areas: [ExchangeDeclaredServiceArea]) -> Bool {
        areas.contains { $0.spatial?.hasResolvedCells == true }
    }
}
