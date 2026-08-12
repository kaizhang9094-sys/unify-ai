import Foundation

#if DEBUG

public enum RetrievalE2EPreflightFailure: Error, CustomStringConvertible, Sendable {
    case localManifestMissing(String)
    case remoteManifestMissing(String)
    case remoteManifestInvalid(String)
    case manifestInvalid(String)

    public var logReason: String {
        switch self {
        case .localManifestMissing(let path):
            return "localManifestMissing path=\(path)"
        case .remoteManifestMissing(let detail):
            return "remoteManifestMissing \(detail)"
        case .remoteManifestInvalid(let detail):
            return "remoteManifestInvalid \(detail)"
        case .manifestInvalid(let detail):
            return "manifestInvalid \(detail)"
        }
    }

    public var description: String {
        logReason
    }
}

public enum ExchangeRetrievalSmokeManifestLoader {
    public enum LoadMode: String, Sendable {
        case localFile
        case remoteHTTP
    }

    public static let remoteManifestPath = "debug/retrieval-smoke/manifest"

    public static func manifestLoadMode(for baseURL: URL) -> LoadMode {
        guard let host = baseURL.host?.lowercased(), !host.isEmpty else {
            return .remoteHTTP
        }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return .localFile
        }
        return .remoteHTTP
    }

    public static func remoteManifestURL(baseURL: URL) -> URL {
        baseURL
            .appendingPathComponent("debug")
            .appendingPathComponent("retrieval-smoke")
            .appendingPathComponent("manifest")
    }

    public static func preflightManifest(
        baseURL: URL,
        session: URLSession = .shared
    ) async throws {
        switch manifestLoadMode(for: baseURL) {
        case .localFile:
            try preflightLocalManifest()
        case .remoteHTTP:
            try await preflightRemoteManifest(baseURL: baseURL, session: session)
        }
    }

    public static func preflightLocalManifest() throws {
        let path = ExchangeAppSearchSmokeGate.generationManifestPath
        print("[RetrievalE2E] manifestLoad mode=localFile path=\(path)")
        guard FileManager.default.fileExists(atPath: path) else {
            print("[RetrievalE2E] PRE_FLIGHT_FAIL reason=localManifestMissing")
            throw RetrievalE2EPreflightFailure.localManifestMissing(path)
        }
        let manifest = try ExchangeRetrievalAccuracyFederationCatalogExport.loadManifest(
            from: URL(fileURLWithPath: path)
        )
        try validateManifest(manifest)
        print("[RetrievalE2E] manifestLoad ok publishGenerationID=\(manifest.publishGenerationID)")
    }

    public static func preflightRemoteManifest(
        baseURL: URL,
        session: URLSession = .shared
    ) async throws {
        let manifestURL = remoteManifestURL(baseURL: baseURL)
        print("[RetrievalE2E] manifestLoad mode=remote url=\(manifestURL.absoluteString)")

        var request = URLRequest(url: manifestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[RetrievalE2E] PRE_FLIGHT_FAIL reason=remoteManifestMissing")
            throw RetrievalE2EPreflightFailure.remoteManifestMissing(
                "GET \(manifestURL.absoluteString) transport error: \(error)"
            )
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200 ..< 300).contains(statusCode) else {
            print("[RetrievalE2E] PRE_FLIGHT_FAIL reason=remoteManifestMissing")
            throw RetrievalE2EPreflightFailure.remoteManifestMissing(
                "GET \(manifestURL.absoluteString) status=\(statusCode)"
            )
        }

        let manifest = try parseRemoteManifestPayload(data)
        try validateManifest(manifest)
        print("[RetrievalE2E] manifestLoad ok publishGenerationID=\(manifest.publishGenerationID)")
    }

    public static func parseRemoteManifestPayload(_ data: Data) throws -> ExchangeRetrievalAccuracyFederationCatalogExport.GenerationManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let wire = try decoder.decode(RemoteManifestWireResponse.self, from: data)
        guard wire.ok else {
            let reason = wire.reason ?? "ok=false"
            print("[RetrievalE2E] PRE_FLIGHT_FAIL reason=remoteManifestMissing")
            throw RetrievalE2EPreflightFailure.remoteManifestMissing(reason)
        }

        guard
            let publishGenerationID = wire.publishGenerationID?.trimmingCharacters(in: .whitespacesAndNewlines),
            !publishGenerationID.isEmpty,
            let expectedNodeIDs = wire.expectedNodeIDs,
            let expectedDocIDs = wire.expectedDocIDs,
            let docCountsByKind = wire.docCountsByKind
        else {
            print("[RetrievalE2E] PRE_FLIGHT_FAIL reason=remoteManifestInvalid")
            throw RetrievalE2EPreflightFailure.remoteManifestInvalid("missing required manifest fields")
        }

        return ExchangeRetrievalAccuracyFederationCatalogExport.GenerationManifest(
            publishGenerationID: publishGenerationID,
            seededAt: wire.seededAt ?? Date(timeIntervalSince1970: 0),
            expectedNodeIDs: expectedNodeIDs,
            expectedDocIDs: expectedDocIDs,
            docCountsByKind: docCountsByKind,
            catalogPath: wire.manifestPath
        )
    }

    public static func validateManifest(
        _ manifest: ExchangeRetrievalAccuracyFederationCatalogExport.GenerationManifest
    ) throws {
        let generationID = manifest.publishGenerationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !generationID.isEmpty else {
            print("[RetrievalE2E] PRE_FLIGHT_FAIL reason=manifestInvalid")
            throw RetrievalE2EPreflightFailure.manifestInvalid("publishGenerationID empty")
        }
        guard !manifest.expectedNodeIDs.isEmpty else {
            print("[RetrievalE2E] PRE_FLIGHT_FAIL reason=manifestInvalid")
            throw RetrievalE2EPreflightFailure.manifestInvalid("expectedNodeIDs empty")
        }
        guard !manifest.expectedDocIDs.isEmpty else {
            print("[RetrievalE2E] PRE_FLIGHT_FAIL reason=manifestInvalid")
            throw RetrievalE2EPreflightFailure.manifestInvalid("expectedDocIDs empty")
        }
    }
}

private struct RemoteManifestWireResponse: Decodable {
    var ok: Bool
    var publishGenerationID: String?
    var seededAt: Date?
    var expectedNodeIDs: [String]?
    var expectedDocIDs: [String]?
    var docCountsByKind: [String: Int]?
    var reason: String?
    var manifestPath: String?
}

#endif
