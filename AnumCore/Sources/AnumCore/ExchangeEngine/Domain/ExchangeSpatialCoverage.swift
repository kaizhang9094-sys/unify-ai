import Foundation

/// Optional H3 spatial footprint for declared service areas or request location needs.
/// Text matching remains authoritative until H3 is wired into ranking (later phases).
public struct ExchangeSpatialCoverage: Codable, Hashable, Sendable {
    public enum ResolutionStatus: String, Codable, Hashable, Sendable {
        case none
        case unresolved
        case resolved
        case ambiguous
        case failed
    }

    public enum Source: String, Codable, Hashable, Sendable {
        case none
        case manualCoordinate
        case currentDevice
        case savedDefault
        case imported
        case geocoder
    }

    public var status: ResolutionStatus
    public var source: Source
    public var h3Resolution: Int?
    public var h3Cells: [String]
    public var centerLatitude: Double?
    public var centerLongitude: Double?
    public var radiusMeters: Double?
    public var capturedAt: Date?

    public init(
        status: ResolutionStatus = .none,
        source: Source = .none,
        h3Resolution: Int? = nil,
        h3Cells: [String] = [],
        centerLatitude: Double? = nil,
        centerLongitude: Double? = nil,
        radiusMeters: Double? = nil,
        capturedAt: Date? = nil
    ) {
        self = Self.makeNormalized(
            status: status,
            source: source,
            h3Resolution: h3Resolution,
            h3Cells: h3Cells,
            centerLatitude: centerLatitude,
            centerLongitude: centerLongitude,
            radiusMeters: radiusMeters,
            capturedAt: capturedAt
        )
    }

    public static let empty: ExchangeSpatialCoverage = {
        Self.makeNormalized(
            status: .none,
            source: .none,
            h3Resolution: nil,
            h3Cells: [],
            centerLatitude: nil,
            centerLongitude: nil,
            radiusMeters: nil,
            capturedAt: nil
        )
    }()

    /// True when status is resolved and at least one valid H3 cell is present.
    public var hasResolvedCells: Bool {
        status == .resolved && !h3Cells.isEmpty && isValid
    }

    /// Whether cells, resolution, and status are internally consistent.
    public var isValid: Bool {
        if h3Cells.isEmpty {
            switch status {
            case .none, .unresolved, .failed:
                return h3Resolution == nil
            case .resolved, .ambiguous:
                return false
            }
        }
        guard let h3Resolution else { return false }
        return ExchangeH3Codec.validateCells(h3Cells, resolution: h3Resolution)
    }

    /// Sanitized copy: lowercase valid cells, clamped resolution/coordinates.
    public func normalized() -> ExchangeSpatialCoverage {
        Self.makeNormalized(
            status: status,
            source: source,
            h3Resolution: h3Resolution,
            h3Cells: h3Cells,
            centerLatitude: centerLatitude,
            centerLongitude: centerLongitude,
            radiusMeters: radiusMeters,
            capturedAt: capturedAt
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try container.decodeIfPresent(ResolutionStatus.self, forKey: .status) ?? .none,
            source: try container.decodeIfPresent(Source.self, forKey: .source) ?? .none,
            h3Resolution: try container.decodeIfPresent(Int.self, forKey: .h3Resolution),
            h3Cells: try container.decodeIfPresent([String].self, forKey: .h3Cells) ?? [],
            centerLatitude: try container.decodeIfPresent(Double.self, forKey: .centerLatitude),
            centerLongitude: try container.decodeIfPresent(Double.self, forKey: .centerLongitude),
            radiusMeters: try container.decodeIfPresent(Double.self, forKey: .radiusMeters),
            capturedAt: try container.decodeIfPresent(Date.self, forKey: .capturedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        let sanitized = normalized()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sanitized.status, forKey: .status)
        try container.encode(sanitized.source, forKey: .source)
        try container.encodeIfPresent(sanitized.h3Resolution, forKey: .h3Resolution)
        if !sanitized.h3Cells.isEmpty {
            try container.encode(sanitized.h3Cells, forKey: .h3Cells)
        }
        try container.encodeIfPresent(sanitized.centerLatitude, forKey: .centerLatitude)
        try container.encodeIfPresent(sanitized.centerLongitude, forKey: .centerLongitude)
        try container.encodeIfPresent(sanitized.radiusMeters, forKey: .radiusMeters)
        try container.encodeIfPresent(sanitized.capturedAt, forKey: .capturedAt)
    }

    // MARK: - Private

    private enum CodingKeys: String, CodingKey {
        case status
        case source
        case h3Resolution
        case h3Cells
        case centerLatitude
        case centerLongitude
        case radiusMeters
        case capturedAt
    }

    private static func makeNormalized(
        status: ResolutionStatus,
        source: Source,
        h3Resolution: Int?,
        h3Cells: [String],
        centerLatitude: Double?,
        centerLongitude: Double?,
        radiusMeters: Double?,
        capturedAt: Date?
    ) -> ExchangeSpatialCoverage {
        var copy = ExchangeSpatialCoverage(
            status: status,
            source: source,
            h3Resolution: h3Resolution,
            h3Cells: [],
            centerLatitude: sanitizeLatitude(centerLatitude),
            centerLongitude: sanitizeLongitude(centerLongitude),
            radiusMeters: sanitizeRadius(radiusMeters),
            capturedAt: capturedAt,
            bypassNormalization: true
        )

        let validCells = ExchangeH3Codec.normalizeCells(h3Cells).filter {
            ExchangeH3Codec.validateCellString($0)
        }
        copy.h3Cells = validCells

        if let h3Resolution {
            copy.h3Resolution = clampResolution(h3Resolution)
        }

        if validCells.isEmpty {
            copy.h3Cells = []
            copy.h3Resolution = nil
            if copy.status == .resolved || copy.status == .ambiguous {
                copy.status = .none
            }
            if copy.status == .none {
                copy.source = .none
            }
        } else {
            if copy.h3Resolution == nil, let inferred = ExchangeH3Codec.cellResolution(validCells[0]) {
                copy.h3Resolution = inferred
            }
            if copy.status == .none {
                copy.status = .resolved
            }
        }

        if copy.isEffectivelyEmpty {
            return ExchangeSpatialCoverage(
                status: .none,
                source: .none,
                h3Resolution: nil,
                h3Cells: [],
                centerLatitude: nil,
                centerLongitude: nil,
                radiusMeters: nil,
                capturedAt: nil,
                bypassNormalization: true
            )
        }
        return copy
    }

    private init(
        status: ResolutionStatus,
        source: Source,
        h3Resolution: Int?,
        h3Cells: [String],
        centerLatitude: Double?,
        centerLongitude: Double?,
        radiusMeters: Double?,
        capturedAt: Date?,
        bypassNormalization: Bool = false
    ) {
        if !bypassNormalization {
            self = Self.makeNormalized(
                status: status,
                source: source,
                h3Resolution: h3Resolution,
                h3Cells: h3Cells,
                centerLatitude: centerLatitude,
                centerLongitude: centerLongitude,
                radiusMeters: radiusMeters,
                capturedAt: capturedAt
            )
            return
        }
        self.status = status
        self.source = source
        self.h3Resolution = h3Resolution
        self.h3Cells = h3Cells
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.radiusMeters = radiusMeters
        self.capturedAt = capturedAt
    }

    private var isEffectivelyEmpty: Bool {
        status == .none &&
            source == .none &&
            h3Cells.isEmpty &&
            h3Resolution == nil &&
            centerLatitude == nil &&
            centerLongitude == nil &&
            radiusMeters == nil &&
            capturedAt == nil
    }

    private static func clampResolution(_ value: Int) -> Int {
        min(ExchangeH3Codec.maxResolution, max(ExchangeH3Codec.minResolution, value))
    }

    private static func sanitizeLatitude(_ value: Double?) -> Double? {
        guard let value, value >= -90, value <= 90 else { return nil }
        return value
    }

    private static func sanitizeLongitude(_ value: Double?) -> Double? {
        guard let value, value >= -180, value <= 180 else { return nil }
        return value
    }

    private static func sanitizeRadius(_ value: Double?) -> Double? {
        guard let value, value > 0, value <= 500_000 else { return nil }
        return value
    }
}

public extension ExchangeSpatialCoverage? {
    /// Returns normalized spatial metadata, or nil when empty after sanitization.
    func normalizedOptional() -> ExchangeSpatialCoverage? {
        guard let self else { return nil }
        let normalized = self.normalized()
        return normalized.isEffectivelyEmptyOptional ? nil : normalized
    }
}

private extension ExchangeSpatialCoverage {
    var isEffectivelyEmptyOptional: Bool {
        status == .none && source == .none && h3Cells.isEmpty && h3Resolution == nil
    }
}
