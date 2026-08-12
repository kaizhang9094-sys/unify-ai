import Foundation

#if DEBUG

public enum ExchangeAppSearchSmokeGate {
    public static let smokeEnvironmentKey = "ANUM_APP_SEARCH_SMOKE"
    public static let defaultLocalBaseURL = URL(string: "http://127.0.0.1:8787")!
    public static let generationManifestPath =
        ProcessInfo.processInfo.environment["ANUM_LOCAL_FED_SMOKE_GENERATION_FILE"]
        ?? "/tmp/anum-local-fed-smoke-generation.json"

    public static var isLaunchAutomationEnabled: Bool {
        ProcessInfo.processInfo.environment[smokeEnvironmentKey] == "1"
    }

    public static func validateForManualRun() throws -> URL {
        try validateResolvedBaseURL(ExchangeBootstrap.resolvedFederationBaseURLConfiguration())
    }

    public static func validateForLaunchAutomation() throws -> URL {
        guard isLaunchAutomationEnabled else {
            throw AppSearchSmokeSkip.automationDisabled
        }
        return try validateForManualRun()
    }

    public static func validateResolvedBaseURL(_ resolved: ExchangeBootstrap.ResolvedFederationBaseURL) throws -> URL {
        let url = resolved.url
        guard let host = url.host?.lowercased() else {
            throw AppSearchSmokeSkip.invalidBaseURL("missing host in \(url.absoluteString)")
        }

        let productionHost = ExchangeBootstrap.liveFederationBaseURL.host?.lowercased()
        if host == productionHost || url.absoluteString.hasPrefix(ExchangeBootstrap.liveFederationBaseURL.absoluteString) {
            throw AppSearchSmokeSkip.invalidBaseURL(
                "refusing production federation URL \(url.absoluteString)"
            )
        }
        if host.contains("railway.app") || host.contains("trycloudflare.com") {
            throw AppSearchSmokeSkip.invalidBaseURL(
                "refusing public/staging federation URL \(url.absoluteString)"
            )
        }

        let allowedLocal = host == "127.0.0.1" || host == "localhost" || host == "::1"
        guard allowedLocal else {
            throw AppSearchSmokeSkip.invalidBaseURL(
                "4H-1 simulator-only: refusing non-localhost federation URL \(url.absoluteString)"
            )
        }
        guard url.scheme?.lowercased() == "http" else {
            throw AppSearchSmokeSkip.invalidBaseURL(
                "refusing non-http localhost URL \(url.absoluteString)"
            )
        }
        guard url.port == 8787 else {
            throw AppSearchSmokeSkip.invalidBaseURL(
                "expected local federation on port 8787, got \(url.absoluteString)"
            )
        }
        return url
    }

    public static func preflight(baseURL: URL) async throws {
        try await preflightHealth(baseURL: baseURL)
        try preflightSeedManifest()
    }

    public static func preflightHealth(baseURL: URL) async throws {
        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppSearchSmokeSkip.serverUnreachable(
                "GET \(healthURL.absoluteString) failed status=\(code); start Phase 4F local federation server first"
            )
        }
    }

    public static func preflightSeedManifest() throws {
        let path = generationManifestPath
        guard FileManager.default.fileExists(atPath: path) else {
            throw AppSearchSmokeSkip.manifestMissing(
                "seed manifest missing at \(path); run ./AnumCore/scripts/run-retrieval-local-federation-smoke.sh first"
            )
        }
    }
}

public enum AppSearchSmokeSkip: Error, CustomStringConvertible, Sendable {
    case automationDisabled
    case invalidBaseURL(String)
    case manifestMissing(String)
    case serverUnreachable(String)
    case runnerSetup(String)

    public var description: String {
        switch self {
        case .automationDisabled:
            return "ANUM_APP_SEARCH_SMOKE not set"
        case .invalidBaseURL(let reason):
            return reason
        case .manifestMissing(let path):
            return path
        case .serverUnreachable(let reason):
            return reason
        case .runnerSetup(let reason):
            return reason
        }
    }
}

#endif
