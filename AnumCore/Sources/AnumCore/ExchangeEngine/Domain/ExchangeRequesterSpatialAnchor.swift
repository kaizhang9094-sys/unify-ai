import Foundation

/// Requester-side spatial anchor for discovery/retrieval (H3 prepared; ranking uses later phases).
public struct ExchangeRequesterSpatialAnchor: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable {
        case explicitQuery
        case currentDevice
        case savedDefault
        case none
    }

    public var source: Source
    public var coordinate: ExchangeCoordinate?
    public var spatial: ExchangeSpatialCoverage?
    public var radiusMeters: Double?
    public var createdAt: Date?

    public init(
        source: Source = .none,
        coordinate: ExchangeCoordinate? = nil,
        spatial: ExchangeSpatialCoverage? = nil,
        radiusMeters: Double? = nil,
        createdAt: Date? = nil
    ) {
        self.source = source
        self.coordinate = coordinate?.isValid == true ? coordinate : nil
        self.spatial = spatial.map { $0.normalized() }
        self.radiusMeters = radiusMeters.map { max(0, $0) }
        self.createdAt = createdAt
    }

    public static let none = ExchangeRequesterSpatialAnchor(source: .none)

    public var hasResolvedSpatial: Bool {
        spatial?.hasResolvedCells == true
    }
}
