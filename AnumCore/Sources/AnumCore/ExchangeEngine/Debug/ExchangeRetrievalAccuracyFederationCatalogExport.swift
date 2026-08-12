import Foundation

#if DEBUG

/// JSON catalog export for local-federation retrieval accuracy smoke seeding.
public enum ExchangeRetrievalAccuracyFederationCatalogExport {
    public struct Catalog: Codable, Sendable {
        public var publishGenerationID: String
        public var seededAt: Date
        public var expectedNodeIDs: [String]
        public var expectedDocIDs: [String]
        public var nodes: [NodeEntry]

        public init(
            publishGenerationID: String,
            seededAt: Date,
            expectedNodeIDs: [String],
            expectedDocIDs: [String],
            nodes: [NodeEntry]
        ) {
            self.publishGenerationID = publishGenerationID
            self.seededAt = seededAt
            self.expectedNodeIDs = expectedNodeIDs
            self.expectedDocIDs = expectedDocIDs
            self.nodes = nodes
        }
    }

    public struct NodeEntry: Codable, Sendable {
        public var nodeID: String
        public var displayName: String
        public var publicProfile: ExchangePublicNodeProfile
        public var offers: [ExchangeOffer]
        public var retrievalDocuments: [ExchangeRetrievalDocument]

        public init(
            nodeID: String,
            displayName: String,
            publicProfile: ExchangePublicNodeProfile,
            offers: [ExchangeOffer],
            retrievalDocuments: [ExchangeRetrievalDocument]
        ) {
            self.nodeID = nodeID
            self.displayName = displayName
            self.publicProfile = publicProfile
            self.offers = offers
            self.retrievalDocuments = retrievalDocuments
        }
    }

    public struct GenerationManifest: Codable, Sendable {
        public var publishGenerationID: String
        public var seededAt: Date
        public var expectedNodeIDs: [String]
        public var expectedDocIDs: [String]
        public var docCountsByKind: [String: Int]
        public var catalogPath: String?

        public init(
            publishGenerationID: String,
            seededAt: Date,
            expectedNodeIDs: [String],
            expectedDocIDs: [String],
            docCountsByKind: [String: Int],
            catalogPath: String? = nil
        ) {
            self.publishGenerationID = publishGenerationID
            self.seededAt = seededAt
            self.expectedNodeIDs = expectedNodeIDs
            self.expectedDocIDs = expectedDocIDs
            self.docCountsByKind = docCountsByKind
            self.catalogPath = catalogPath
        }
    }

    public enum ExportError: Error, CustomStringConvertible, Sendable {
        case catalogEmbeddingInvalid([String])
        case warmupFailed(reason: String)
        case warmupTimedOut
        case writeFailed(path: String, underlying: String)

        public var description: String {
            switch self {
            case .catalogEmbeddingInvalid(let failures):
                return "catalog embedding invalid: \(failures.joined(separator: "; "))"
            case .warmupFailed(let reason):
                return "ONNX warmup failed: \(reason)"
            case .warmupTimedOut:
                return "ONNX warmup timed out"
            case .writeFailed(let path, let underlying):
                return "failed writing \(path): \(underlying)"
            }
        }
    }

    public static func buildONNXCatalog() async throws -> [ExchangeDirectoryMatch] {
        var config = ONNXSentenceEmbedder.Config()
        config.enableTraceLogs = false
        let embedder = ONNXSentenceEmbedder(config: config)

        let warmupVector = try await warmupONNXEmbedder(embedder)
        guard warmupVector.count == ExchangeRetrievalAccuracyFixtureBuilder.onnxEmbeddingDimension else {
            throw ExportError.warmupFailed(
                reason: "expected dim \(ExchangeRetrievalAccuracyFixtureBuilder.onnxEmbeddingDimension) got \(warmupVector.count)"
            )
        }

        let rawCatalog = ExchangeRetrievalAccuracyFixtureBuilder.buildCatalog(includeAxisEmbeddings: false)
        let noEmbeddingFailures = ExchangeRetrievalAccuracyFixtureBuilder.assertCatalogHasNoEmbeddings(rawCatalog)
        if !noEmbeddingFailures.isEmpty {
            throw ExportError.catalogEmbeddingInvalid(noEmbeddingFailures)
        }

        let catalog = ExchangeRetrievalAccuracyFixtureBuilder.preEmbedCatalogWithONNX(rawCatalog, embedder: embedder)
        let onnxFailures = ExchangeRetrievalAccuracyFixtureBuilder.assertCatalogONNXEmbeddings(catalog)
        if !onnxFailures.isEmpty {
            throw ExportError.catalogEmbeddingInvalid(onnxFailures)
        }
        return catalog
    }

    public static func makeCatalog(from matches: [ExchangeDirectoryMatch]) -> Catalog {
        let generationID = UUID().uuidString.lowercased()
        let seededAt = Date()
        var nodes: [NodeEntry] = []
        nodes.reserveCapacity(matches.count)
        var expectedDocIDs: [String] = []

        for match in matches {
            guard let profile = match.publicProfile ?? match.counterparty.publicProfile else {
                continue
            }
            let nodeID = match.id
            let displayName: String = {
                let trimmed = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nodeID : trimmed
            }()
            nodes.append(
                NodeEntry(
                    nodeID: nodeID,
                    displayName: displayName,
                    publicProfile: profile,
                    offers: match.offers,
                    retrievalDocuments: match.retrievalDocuments
                )
            )
            expectedDocIDs.append(contentsOf: match.retrievalDocuments.map(\.id))
        }

        return Catalog(
            publishGenerationID: generationID,
            seededAt: seededAt,
            expectedNodeIDs: matches.map(\.id).sorted(),
            expectedDocIDs: expectedDocIDs.sorted(),
            nodes: nodes
        )
    }

    public static func docCountsByKind(in catalog: Catalog) -> [String: Int] {
        var counts: [String: Int] = [:]
        for node in catalog.nodes {
            for doc in node.retrievalDocuments {
                let kind = doc.docKind?.rawValue ?? "nil"
                counts[kind, default: 0] += 1
            }
        }
        return counts
    }

    public static func writeCatalog(_ catalog: Catalog, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(catalog)
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(path: url.path, underlying: String(describing: error))
        }
    }

    public static func writeManifest(_ manifest: GenerationManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(manifest)
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.writeFailed(path: url.path, underlying: String(describing: error))
        }
    }

    public static func loadManifest(from url: URL) throws -> GenerationManifest {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GenerationManifest.self, from: data)
    }

    public static func exportCatalogAndManifest(
        catalogURL: URL,
        manifestURL: URL
    ) async throws -> GenerationManifest {
        let matches = try await buildONNXCatalog()
        let catalog = makeCatalog(from: matches)
        try writeCatalog(catalog, to: catalogURL)
        let manifest = GenerationManifest(
            publishGenerationID: catalog.publishGenerationID,
            seededAt: catalog.seededAt,
            expectedNodeIDs: catalog.expectedNodeIDs,
            expectedDocIDs: catalog.expectedDocIDs,
            docCountsByKind: docCountsByKind(in: catalog),
            catalogPath: catalogURL.path
        )
        try writeManifest(manifest, to: manifestURL)
        return manifest
    }

    private static func warmupONNXEmbedder(_ embedder: ONNXSentenceEmbedder) async throws -> [Float] {
        try await withThrowingTaskGroup(of: Result<[Float], Error>.self) { group in
            group.addTask {
                let vector = await Task.detached(priority: .userInitiated) {
                    embedder.embedQuery("warmup local federation catalog export")
                }.value
                guard let vector, !vector.isEmpty else {
                    return .failure(ExportError.warmupFailed(reason: "embedQuery returned nil/empty"))
                }
                return .success(vector)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return .failure(ExportError.warmupTimedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw ExportError.warmupFailed(reason: "no warmup result")
            }
            switch first {
            case .success(let vector):
                return vector
            case .failure(let error):
                throw error
            }
        }
    }
}

#endif
