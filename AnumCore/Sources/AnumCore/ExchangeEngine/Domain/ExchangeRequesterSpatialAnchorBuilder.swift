import Foundation

public enum ExchangeRequesterSpatialAnchorBuilder: Sendable {
    public static func makeNone(createdAt: Date = Date()) -> ExchangeRequesterSpatialAnchor {
        ExchangeRequesterSpatialAnchor(
            source: .none,
            coordinate: nil,
            spatial: nil,
            radiusMeters: nil,
            createdAt: createdAt
        )
    }

    public static func makeCurrentDeviceAnchor(
        coordinate: ExchangeCoordinate,
        radiusMeters: Double = ExchangeH3CoverageBuilder.defaultRequesterRadiusMeters,
        resolution: Int = ExchangeH3CoverageBuilder.defaultResolution,
        createdAt: Date = Date()
    ) -> ExchangeRequesterSpatialAnchor {
        guard coordinate.isValid else {
            return makeNone(createdAt: createdAt)
        }

        let spatial = ExchangeH3CoverageBuilder.buildCoverage(
            center: coordinate,
            radiusMeters: radiusMeters,
            resolution: resolution,
            source: .currentDevice
        )

        return ExchangeRequesterSpatialAnchor(
            source: .currentDevice,
            coordinate: coordinate,
            spatial: spatial,
            radiusMeters: radiusMeters,
            createdAt: createdAt
        )
    }

    public static func makeSavedDefaultAnchor(
        coordinate: ExchangeCoordinate,
        radiusMeters: Double = ExchangeH3CoverageBuilder.defaultRequesterRadiusMeters,
        resolution: Int = ExchangeH3CoverageBuilder.defaultResolution,
        createdAt: Date = Date()
    ) -> ExchangeRequesterSpatialAnchor {
        guard coordinate.isValid else {
            return makeNone(createdAt: createdAt)
        }

        let spatial = ExchangeH3CoverageBuilder.buildCoverage(
            center: coordinate,
            radiusMeters: radiusMeters,
            resolution: resolution,
            source: .savedDefault
        )

        return ExchangeRequesterSpatialAnchor(
            source: .savedDefault,
            coordinate: coordinate,
            spatial: spatial,
            radiusMeters: radiusMeters,
            createdAt: createdAt
        )
    }

    public static func makeExplicitQueryAnchor(
        coordinate: ExchangeCoordinate?,
        spatial: ExchangeSpatialCoverage?,
        radiusMeters: Double?,
        createdAt: Date = Date()
    ) -> ExchangeRequesterSpatialAnchor {
        ExchangeRequesterSpatialAnchor(
            source: .explicitQuery,
            coordinate: coordinate,
            spatial: spatial,
            radiusMeters: radiusMeters,
            createdAt: createdAt
        )
    }
}
