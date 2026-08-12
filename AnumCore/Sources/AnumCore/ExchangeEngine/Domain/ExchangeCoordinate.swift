import Foundation

/// A WGS84 geographic coordinate (manual entry or device-provided in later phases).
public struct ExchangeCoordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracyMeters: Double?
    public var capturedAt: Date?

    public init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double? = nil,
        capturedAt: Date? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.capturedAt = capturedAt
    }

    public var isValid: Bool {
        guard latitude >= -90, latitude <= 90 else { return false }
        guard longitude >= -180, longitude <= 180 else { return false }
        if let horizontalAccuracyMeters {
            guard horizontalAccuracyMeters >= 0, horizontalAccuracyMeters <= 500_000 else { return false }
        }
        return true
    }
}
