import Foundation

#if DEBUG

public enum ExchangeRetrievalE2EGate {
    public static let smokeEnvironmentKey = "ANUM_RETRIEVAL_E2E_SMOKE"
    public static let federationPort = 8787

    public static var isLaunchAutomationEnabled: Bool {
        ProcessInfo.processInfo.environment[smokeEnvironmentKey] == "1"
    }

    public static func validateForManualRun() throws -> URL {
        let resolved = ExchangeBootstrap.resolvedFederationBaseURLConfiguration()
        print(
            "[RetrievalE2E] federationConfig baseURL=\(resolved.url.absoluteString) source=\(resolved.source.rawValue)"
        )
        return try validateResolvedBaseURL(resolved)
    }

    public static func validateResolvedBaseURL(
        _ resolved: ExchangeBootstrap.ResolvedFederationBaseURL
    ) throws -> URL {
        let url = resolved.url
        let absolute = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !absolute.isEmpty else {
            return try deny("empty base URL")
        }

        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return try deny("missing host in \(absolute)")
        }

        if isProductionOrPublicCloudHost(host: host, url: url) {
            return try deny("refusing production or public staging federation URL \(absolute)")
        }

        if isCloudflareTunnelHost(host) {
            guard url.scheme?.lowercased() == "https" else {
                return try deny("cloudflare tunnel requires https, got \(absolute)")
            }
            if let port = url.port, port != 443 {
                return try deny("cloudflare tunnel must use default https port, got \(absolute)")
            }
            print("[RetrievalE2E] gate allowed cloudflareTunnel baseURL=\(url.absoluteString)")
            return url
        }

        guard url.scheme?.lowercased() == "http" else {
            return try deny("refusing non-http development federation URL \(absolute)")
        }

        guard url.port == federationPort else {
            return try deny("expected local federation on port \(federationPort), got \(absolute)")
        }

        guard isAllowedRealDeviceDevelopmentHost(host) else {
            return try deny(
                "refusing non-development federation host \(host); allowed localhost, private LAN on port \(federationPort), or trycloudflare.com tunnel"
            )
        }

        print("[RetrievalE2E] gate allowed realDeviceLAN baseURL=\(url.absoluteString)")
        return url
    }

    public static func preflight(baseURL: URL) async throws {
        try await preflight(baseURL: baseURL, options: .retrievalSmokeE2E)
    }

    public struct PreflightOptions: Sendable, Equatable {
        public var requiresRetrievalSmokeManifest: Bool
        public var manifestSkippedLogTag: String?
        public var manifestSkippedReason: String?

        public static let retrievalSmokeE2E = PreflightOptions(
            requiresRetrievalSmokeManifest: true
        )

        public static func multilingualLocalSeeded(reason: String) -> PreflightOptions {
            PreflightOptions(
                requiresRetrievalSmokeManifest: false,
                manifestSkippedLogTag: "MultilingualE2E",
                manifestSkippedReason: reason
            )
        }
    }

    public static func preflight(
        baseURL: URL,
        options: PreflightOptions
    ) async throws {
        let healthURL = baseURL.appendingPathComponent("health")
        try await ExchangeAppSearchSmokeGate.preflightHealth(baseURL: baseURL)
        print("[RetrievalE2E] healthCheck ok url=\(healthURL.absoluteString)")

        if options.requiresRetrievalSmokeManifest {
            try await ExchangeRetrievalSmokeManifestLoader.preflightManifest(baseURL: baseURL)
            return
        }

        if let logTag = options.manifestSkippedLogTag {
            let reason = options.manifestSkippedReason ?? "not_required"
            print("[\(logTag)] remote retrieval-smoke manifest skipped reason=\(reason)")
        }
    }

    /// DEBUG RetrievalE2E allows ephemeral Cloudflare tunnels to localhost federation.
    public static func isCloudflareTunnelHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "trycloudflare.com" || normalized.hasSuffix(".trycloudflare.com")
    }

    /// DEBUG RetrievalE2E allows localhost and RFC1918 LAN hosts for physical-device smoke.
    public static func isAllowedRealDeviceDevelopmentHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1" {
            return true
        }

        let parts = normalized.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0 ... 255).contains($0) }) else {
            return false
        }

        switch parts[0] {
        case 10:
            return true
        case 127:
            return true
        case 192 where parts[1] == 168:
            return true
        case 172 where (16 ... 31).contains(parts[1]):
            return true
        default:
            return false
        }
    }

    private static func isProductionOrPublicCloudHost(host: String, url: URL) -> Bool {
        if isCloudflareTunnelHost(host) {
            return false
        }
        let productionHost = ExchangeBootstrap.liveFederationBaseURL.host?.lowercased()
        if let productionHost, host == productionHost {
            return true
        }
        if url.absoluteString.hasPrefix(ExchangeBootstrap.liveFederationBaseURL.absoluteString) {
            return true
        }
        if host.contains("railway.app") {
            return true
        }
        return false
    }

    @discardableResult
    private static func deny(_ reason: String) throws -> URL {
        print("[RetrievalE2E] gate denied reason=\(reason)")
        throw AppSearchSmokeSkip.invalidBaseURL(reason)
    }
}

#endif
