import Foundation
import CoreLocation
import AnumCore

/// One-shot when-in-use location for requester discovery anchors (no continuous tracking).
@MainActor
final class RequesterLocationService: NSObject, ExchangeRequesterLocationProviding {
    private let manager: CLLocationManager
    private var oneShotContinuation: CheckedContinuation<ExchangeCoordinate?, Never>?
    private var permissionContinuation: CheckedContinuation<Bool, Never>?
    private var oneShotTimeoutTask: Task<Void, Never>?

    private(set) var lastKnownCoordinate: ExchangeCoordinate?

    private static let oneShotTimeoutSeconds: TimeInterval = 12

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    var authorizationStatus: ExchangeLocationAuthorizationStatus {
        get async {
            Self.mapAuthorization(manager.authorizationStatus)
        }
    }

    func requestWhenInUsePermission() async -> Bool {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .restricted, .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                permissionContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }

    func requestOneShotLocation() async -> ExchangeCoordinate? {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            return nil
        }

        if let cached = lastKnownCoordinate, isFresh(cached) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            oneShotContinuation = continuation
            manager.requestLocation()

            oneShotTimeoutTask?.cancel()
            oneShotTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.oneShotTimeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finishOneShot(with: nil)
            }
        }
    }

    func clearLocation() async {
        lastKnownCoordinate = nil
    }

    private func finishOneShot(with coordinate: ExchangeCoordinate?) {
        oneShotTimeoutTask?.cancel()
        oneShotTimeoutTask = nil
        if let coordinate, coordinate.isValid {
            lastKnownCoordinate = coordinate
        }
        oneShotContinuation?.resume(returning: coordinate)
        oneShotContinuation = nil
    }

    private func finishPermission(granted: Bool) {
        permissionContinuation?.resume(returning: granted)
        permissionContinuation = nil
    }

    private func isFresh(_ coordinate: ExchangeCoordinate) -> Bool {
        guard let capturedAt = coordinate.capturedAt else { return false }
        return Date().timeIntervalSince(capturedAt) < 300
    }

    private static func mapAuthorization(_ status: CLAuthorizationStatus) -> ExchangeLocationAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorizedAlways:
            return .authorizedAlways
        case .authorizedWhenInUse:
            return .authorizedWhenInUse
        @unknown default:
            return .denied
        }
    }

    private static func mapCoordinate(from location: CLLocation) -> ExchangeCoordinate? {
        let coordinate = ExchangeCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            capturedAt: location.timestamp
        )
        return coordinate.isValid ? coordinate : nil
    }
}

extension RequesterLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard permissionContinuation != nil else { return }
            let status = manager.authorizationStatus
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                finishPermission(granted: true)
            case .denied, .restricted:
                finishPermission(granted: false)
            case .notDetermined:
                break
            @unknown default:
                finishPermission(granted: false)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            guard oneShotContinuation != nil else { return }
            if let latest {
                finishOneShot(with: Self.mapCoordinate(from: latest))
            } else {
                finishOneShot(with: nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard oneShotContinuation != nil else { return }
            finishOneShot(with: nil)
        }
    }
}

extension RequesterLocationService {
    func requestOneShotCoordinate() async -> ExchangeCoordinate? {
        await requestOneShotLocation()
    }

    func lastKnownCoordinate() async -> ExchangeCoordinate? {
        guard let cached = lastKnownCoordinate, cached.isValid else { return nil }
        return cached
    }
}

// MARK: - Seller service-area geocoding (address strings only; not requester GPS)

/// iOS `CLGeocoder` adapter for seller service-area resolution (app layer only).
public struct SellerServiceAreaGeocodingService: ExchangeSellerServiceAreaGeocoding, Sendable {
    public init() {}

    public func geocodeAddressString(_ address: String) async throws -> ExchangeCoordinate? {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        guard let placemark = placemarks.first,
              let location = placemark.location else {
            return nil
        }

        return ExchangeCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            capturedAt: Date()
        )
    }
}
