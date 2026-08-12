import Foundation

/// App-layer location access for one-shot requester coordinates (CoreLocation implementation lives in AnumAPP).
public protocol ExchangeRequesterLocationProviding: Sendable {
    var authorizationStatus: ExchangeLocationAuthorizationStatus { get async }

    /// Requests when-in-use permission if needed. Returns whether authorized when-in-use (or always).
    func requestWhenInUsePermission() async -> Bool

    /// One-shot fix; nil when denied, restricted, timed out, or invalid.
    func requestOneShotCoordinate() async -> ExchangeCoordinate?

    /// Last cached requester coordinate from a prior successful fix (app-defined freshness).
    func lastKnownCoordinate() async -> ExchangeCoordinate?

    func clearLocation() async
}

public extension ExchangeRequesterLocationProviding {
    func lastKnownCoordinate() async -> ExchangeCoordinate? {
        nil
    }
}

public enum ExchangeLocationAuthorizationStatus: String, Sendable, Hashable, Codable {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways

    public var isAuthorizedForWhenInUse: Bool {
        switch self {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        }
    }
}
