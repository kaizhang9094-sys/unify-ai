import Foundation
@testable import AnumCore

enum ExchangeRetrievalLocalFederationSmokeGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["ANUM_RETRIEVAL_LOCAL_FEDERATION_SMOKE"] == "1"
    }

    static var isFullBatchMode: Bool {
        ProcessInfo.processInfo.environment["ANUM_LOCAL_FED_SMOKE_FULL"] == "1"
    }

    static var generationManifestPath: String {
        ProcessInfo.processInfo.environment["ANUM_LOCAL_FED_SMOKE_GENERATION_FILE"]
            ?? "/tmp/anum-local-fed-smoke-generation.json"
    }

    static var resolvedBaseURL: URL? {
        let raw = ProcessInfo.processInfo.environment["UNIFY_DEBUG_FEDERATION_BASE_URL"]
            ?? ProcessInfo.processInfo.environment["ANUM_FEDERATION_BASE_URL"]
        guard let raw, let url = URL(string: raw) else { return nil }
        return url
    }

    static func validateLocalhostBaseURL(_ url: URL) throws {
        guard let host = url.host?.lowercased() else {
            throw LocalFederationSmokeSkip.invalidBaseURL("missing host in \(url.absoluteString)")
        }
        let allowed = host == "127.0.0.1" || host == "localhost" || host == "::1"
        guard allowed else {
            throw LocalFederationSmokeSkip.invalidBaseURL(
                "refusing non-local federation URL \(url.absoluteString); use http://127.0.0.1:8787"
            )
        }
        if url.scheme?.lowercased() != "http" {
            throw LocalFederationSmokeSkip.invalidBaseURL(
                "refusing non-http federation URL \(url.absoluteString)"
            )
        }
    }

    static func requireConfiguration() throws -> URL {
        guard isEnabled else {
            throw LocalFederationSmokeSkip.disabled
        }
        guard let url = resolvedBaseURL else {
            throw LocalFederationSmokeSkip.invalidBaseURL(
                "set UNIFY_DEBUG_FEDERATION_BASE_URL=http://127.0.0.1:8787"
            )
        }
        try validateLocalhostBaseURL(url)
        return url
    }
}

enum LocalFederationSmokeSkip: Error, CustomStringConvertible, Sendable {
    case disabled
    case invalidBaseURL(String)
    case manifestMissing(String)
    case serverUnreachable(String)
    case harnessSetup(String)

    var description: String {
        switch self {
        case .disabled:
            return "ANUM_RETRIEVAL_LOCAL_FEDERATION_SMOKE not set"
        case .invalidBaseURL(let reason):
            return reason
        case .manifestMissing(let path):
            return "generation manifest missing at \(path)"
        case .serverUnreachable(let reason):
            return "local federation server unreachable: \(reason)"
        case .harnessSetup(let reason):
            return "harness setup failed: \(reason)"
        }
    }
}
