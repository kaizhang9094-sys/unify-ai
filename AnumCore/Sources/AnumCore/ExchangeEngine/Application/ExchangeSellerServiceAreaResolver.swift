import Foundation

/// Platform geocoding for seller service-area chips (implemented in the iOS app target).
public protocol ExchangeSellerServiceAreaGeocoding: Sendable {
    func geocodeAddressString(_ address: String) async throws -> ExchangeCoordinate?
}

public struct ExchangeSellerServiceAreaResolveBatchResult: Sendable, Hashable {
    public var areas: [ExchangeDeclaredServiceArea]
    public var resolvedSpatialCount: Int
    public var textOnlyCount: Int

    public init(
        areas: [ExchangeDeclaredServiceArea],
        resolvedSpatialCount: Int,
        textOnlyCount: Int
    ) {
        self.areas = areas
        self.resolvedSpatialCount = resolvedSpatialCount
        self.textOnlyCount = textOnlyCount
    }

    /// Non-blocking notice when some chips could not be mapped.
    public var userNotice: String? {
        guard textOnlyCount > 0 else { return nil }
        if resolvedSpatialCount > 0 {
            return "Some areas were saved as text only. Map matching may be limited until those areas are verified."
        }
        return "Service areas were saved as text only. Map matching may be limited until areas are verified."
    }
}

/// Resolves seller CSV/chip input into `ExchangeDeclaredServiceArea` values with optional H3 spatial metadata.
public struct ExchangeSellerServiceAreaResolver: Sendable {
    private let geocoder: (any ExchangeSellerServiceAreaGeocoding)?
    private let localPlaceResolver: ExchangeLocalPlaceResolver

    public init(
        geocoder: (any ExchangeSellerServiceAreaGeocoding)? = nil,
        localPlaceResolver: ExchangeLocalPlaceResolver = ExchangeLocalPlaceResolver()
    ) {
        self.geocoder = geocoder
        self.localPlaceResolver = localPlaceResolver
    }

    public func resolveSellerInput(_ csvOrChips: String) async -> ExchangeSellerServiceAreaResolveBatchResult {
        let segments = csvOrChips
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return await resolve(rawSegments: segments)
    }

    public func resolve(rawSegments: [String]) async -> ExchangeSellerServiceAreaResolveBatchResult {
        var cache: [String: ExchangeDeclaredServiceArea] = [:]
        var areas: [ExchangeDeclaredServiceArea] = []
        areas.reserveCapacity(rawSegments.count)

        var seenNormalized = Set<String>()

        for raw in rawSegments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = ExchangeLocationNormalization.normalize(trimmed, stripRegionalSuffixes: true)
            guard !normalized.isEmpty, seenNormalized.insert(normalized).inserted else { continue }

            if let cached = cache[normalized] {
                areas.append(cached)
                continue
            }

            let resolved = await resolveOne(raw: trimmed, normalized: normalized)
            cache[normalized] = resolved
            areas.append(resolved)
        }

        let resolvedSpatialCount = areas.filter { $0.spatial?.hasResolvedCells == true }.count
        let textOnlyCount = areas.count - resolvedSpatialCount

        return ExchangeSellerServiceAreaResolveBatchResult(
            areas: areas,
            resolvedSpatialCount: resolvedSpatialCount,
            textOnlyCount: textOnlyCount
        )
    }

    private func resolveOne(raw: String, normalized: String) async -> ExchangeDeclaredServiceArea {
        if ExchangeLocationNormalization.isRemoteServiceAreaLabel(normalized) {
            logResolve(
                rawText: raw,
                normalizedText: normalized,
                resolver: "remote",
                hasCoordinate: false,
                h3CellCount: 0,
                status: "textOnly"
            )
            return ExchangeDeclaredServiceArea(
                displayName: raw,
                normalizedName: normalized,
                source: .sellerEntered,
                acceptsRemote: true,
                spatial: nil
            )
        }

        let parsed = ExchangeSellerServiceAreaTextParser.parse(raw)
        let placeNormalized = ExchangeLocationNormalization.normalize(
            parsed.placeQuery,
            stripRegionalSuffixes: true
        )

        var coordinate: ExchangeCoordinate?
        var resolverLabel = "failed"
        var radiusMeters = parsed.radiusMeters ?? ExchangeH3CoverageBuilder.defaultSellerRadiusMeters
        var spatialSource: ExchangeSpatialCoverage.Source = .manualCoordinate

        if let gazetteerHit = ExchangeSellerServiceAreaGazetteer.lookup(normalizedKey: placeNormalized) {
            coordinate = gazetteerHit.coordinate
            if parsed.radiusMeters == nil {
                radiusMeters = gazetteerHit.defaultRadiusMeters
            }
            resolverLabel = "local"
        } else {
            let entity = ExchangeQueryEntity(
                kind: .place,
                rawText: parsed.placeQuery,
                normalizedText: placeNormalized,
                confidence: 0.9,
                provenance: .userExplicit
            )
            if let resolvedPlace = await localPlaceResolver.resolvePlace(entity),
               let gazetteerHit = ExchangeSellerServiceAreaGazetteer.lookup(
                normalizedKey: resolvedPlace.normalizedText
               ) {
                coordinate = gazetteerHit.coordinate
                if parsed.radiusMeters == nil {
                    radiusMeters = gazetteerHit.defaultRadiusMeters
                }
                resolverLabel = "local"
            }
        }

        if coordinate == nil, let geocoder {
            do {
                if let geocoded = try await geocoder.geocodeAddressString(parsed.geocodeQuery) {
                    coordinate = geocoded
                    resolverLabel = "geocoder"
                    spatialSource = .geocoder
                }
            } catch {
                resolverLabel = "failed"
            }
        }

        var spatial: ExchangeSpatialCoverage?
        var status = "textOnly"

        if let coordinate, coordinate.isValid {
            let coverage = ExchangeProviderServiceCoverageBuilder.buildProviderServiceCoverage(
                center: coordinate,
                radiusMeters: radiusMeters,
                source: spatialSource
            )
            if coverage.hasResolvedCells {
                spatial = coverage
                status = "resolved"
            }
        }

        logResolve(
            rawText: raw,
            normalizedText: placeNormalized.isEmpty ? normalized : placeNormalized,
            resolver: resolverLabel,
            hasCoordinate: coordinate != nil,
            h3CellCount: spatial?.h3Cells.count ?? 0,
            status: status
        )

        return ExchangeDeclaredServiceArea(
            displayName: raw,
            normalizedName: normalized,
            source: .sellerEntered,
            spatial: spatial
        )
    }

    private func logResolve(
        rawText: String,
        normalizedText: String,
        resolver: String,
        hasCoordinate: Bool,
        h3CellCount: Int,
        status: String
    ) {
        #if DEBUG
        Swift.print(
            "[SellerServiceAreaResolve] rawText=\(rawText) " +
            "normalizedText=\(normalizedText) " +
            "resolver=\(resolver) " +
            "hasCoordinate=\(hasCoordinate) " +
            "h3CellCount=\(h3CellCount) " +
            "status=\(status)"
        )
        #endif
    }
}
