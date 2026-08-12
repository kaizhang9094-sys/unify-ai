import Foundation
import SwiftyH3

/// Builds bounded H3 cell coverage from a center coordinate and radius (no geocoding).
public enum ExchangeH3CoverageBuilder: Sendable {
    public static let defaultResolution = 7
    public static let defaultRequesterRadiusMeters: Double = 10_000
    public static let defaultSellerRadiusMeters: Double = 15_000
    public static let defaultMaxCells = 128

    /// Maximum grid disk ring count before cell explosion (safety bound).
    public static let maxGridDiskDistance = 32

    public static func buildCoverage(
        center: ExchangeCoordinate,
        radiusMeters: Double,
        resolution: Int = defaultResolution,
        maxCells: Int = defaultMaxCells,
        source: ExchangeSpatialCoverage.Source
    ) -> ExchangeSpatialCoverage {
        let cappedMaxCells = min(max(maxCells, 1), ExchangeH3Codec.maxCellsPerSet)
        let clampedResolution = min(
            ExchangeH3Codec.maxResolution,
            max(ExchangeH3Codec.minResolution, resolution)
        )

        guard center.isValid else {
            return failedCoverage(
                center: center,
                radiusMeters: radiusMeters,
                resolution: clampedResolution,
                source: source
            )
        }

        guard let h3Resolution = H3Cell.Resolution(rawValue: Int32(clampedResolution)) else {
            return failedCoverage(
                center: center,
                radiusMeters: radiusMeters,
                resolution: clampedResolution,
                source: source
            )
        }

        let latLng = H3LatLng(latitudeDegs: center.latitude, longitudeDegs: center.longitude)

        let centerCell: H3Cell
        do {
            centerCell = try latLng.cell(at: h3Resolution)
        } catch {
            return failedCoverage(
                center: center,
                radiusMeters: radiusMeters,
                resolution: clampedResolution,
                source: source
            )
        }

        let centerCellString = centerCell.description.lowercased()
        guard ExchangeH3Codec.validateCellString(centerCellString) else {
            return failedCoverage(
                center: center,
                radiusMeters: radiusMeters,
                resolution: clampedResolution,
                source: source
            )
        }

        let effectiveRadius = max(0, radiusMeters)
        let diskDistance: Int32
        if effectiveRadius <= 0 {
            diskDistance = 0
        } else {
            diskDistance = gridDiskDistance(
                radiusMeters: effectiveRadius,
                resolution: h3Resolution,
                maxCells: cappedMaxCells
            )
        }

        var rawCells: [String] = [centerCellString]
        if diskDistance > 0 {
            do {
                let disk = try centerCell.gridDisk(distance: diskDistance)
                rawCells.append(contentsOf: disk.map { $0.description.lowercased() })
            } catch {
                return failedCoverage(
                    center: center,
                    radiusMeters: effectiveRadius,
                    resolution: clampedResolution,
                    source: source
                )
            }
        }

        let normalizedCells = cappedNormalizedCells(
            rawCells,
            centerCell: centerCellString,
            maxCells: cappedMaxCells
        )

        guard !normalizedCells.isEmpty else {
            return failedCoverage(
                center: center,
                radiusMeters: effectiveRadius,
                resolution: clampedResolution,
                source: source
            )
        }

        return ExchangeSpatialCoverage(
            status: .resolved,
            source: source,
            h3Resolution: clampedResolution,
            h3Cells: normalizedCells,
            centerLatitude: center.latitude,
            centerLongitude: center.longitude,
            radiusMeters: effectiveRadius > 0 ? effectiveRadius : nil,
            capturedAt: center.capturedAt
        )
    }

    /// Conservative grid-disk ring count from radius and average hex edge length at resolution.
    public static func gridDiskDistance(
        radiusMeters: Double,
        resolution: Int,
        maxCells: Int
    ) -> Int32 {
        guard let h3Resolution = H3Cell.Resolution(rawValue: Int32(resolution)) else { return 0 }
        return gridDiskDistance(
            radiusMeters: radiusMeters,
            resolution: h3Resolution,
            maxCells: maxCells
        )
    }

    /// Conservative grid-disk ring count from radius and average hex edge length at resolution.
    public static func gridDiskDistance(
        radiusMeters: Double,
        resolution: H3Cell.Resolution,
        maxCells: Int
    ) -> Int32 {
        guard radiusMeters > 0 else { return 0 }

        let edgeMeters = resolution.averageHexagonEdgeLength.converted(to: .meters).value
        guard edgeMeters > 0 else { return 0 }

        var k = Int32(ceil(radiusMeters / edgeMeters))
        k = min(k, Int32(maxGridDiskDistance))

        while k > 0, estimatedGridDiskCellCount(distance: k) > maxCells {
            k -= 1
        }
        return max(Int32(0), k)
    }

    // MARK: - Private

    private static func failedCoverage(
        center: ExchangeCoordinate,
        radiusMeters: Double,
        resolution: Int,
        source: ExchangeSpatialCoverage.Source
    ) -> ExchangeSpatialCoverage {
        ExchangeSpatialCoverage(
            status: .failed,
            source: source,
            h3Resolution: nil,
            h3Cells: [],
            centerLatitude: center.isValid ? center.latitude : nil,
            centerLongitude: center.isValid ? center.longitude : nil,
            radiusMeters: radiusMeters > 0 ? radiusMeters : nil,
            capturedAt: center.capturedAt
        )
    }

    /// H3 grid disk cell count: `1 + 3 * k * (k + 1)` for ring distance `k`.
    private static func estimatedGridDiskCellCount(distance k: Int32) -> Int {
        guard k > 0 else { return 1 }
        let kk = Int(k)
        return 1 + 3 * kk * (kk + 1)
    }

    private static func cappedNormalizedCells(
        _ raw: [String],
        centerCell: String,
        maxCells: Int
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        func append(_ value: String) {
            guard ExchangeH3Codec.validateCellString(value) else { return }
            guard let normalized = ExchangeH3Codec.normalizeCellString(value) else { return }
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            out.append(normalized)
        }

        append(centerCell)
        let others = raw
            .compactMap { ExchangeH3Codec.normalizeCellString($0) }
            .filter { $0 != centerCell && ExchangeH3Codec.validateCellString($0) }
            .sorted()
        for cell in others {
            append(cell)
            if out.count >= maxCells { break }
        }
        return Array(out.prefix(maxCells))
    }
}
