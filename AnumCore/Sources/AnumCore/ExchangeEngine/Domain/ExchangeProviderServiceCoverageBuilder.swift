import Foundation

/// Builds declared provider service-area H3 coverage (not device GPS).
public enum ExchangeProviderServiceCoverageBuilder: Sendable {
    public static func buildProviderServiceCoverage(
        center: ExchangeCoordinate,
        radiusMeters: Double = ExchangeH3CoverageBuilder.defaultSellerRadiusMeters,
        resolution: Int = ExchangeH3CoverageBuilder.defaultResolution,
        maxCells: Int = ExchangeH3CoverageBuilder.defaultMaxCells,
        source: ExchangeSpatialCoverage.Source = .manualCoordinate
    ) -> ExchangeSpatialCoverage {
        let coverage = ExchangeH3CoverageBuilder.buildCoverage(
            center: center,
            radiusMeters: radiusMeters,
            resolution: resolution,
            maxCells: maxCells,
            source: source
        )

        let cellCount = coverage.h3Cells.count
        let resolutionLog = coverage.h3Resolution.map(String.init) ?? "nil"
        let statusLog = coverage.status.rawValue
        print(
            "[SellerH3] offerCoverageBuilt status=\(statusLog) resolution=\(resolutionLog) cellCount=\(cellCount) source=\(source.rawValue)"
        )

        return coverage
    }
}
