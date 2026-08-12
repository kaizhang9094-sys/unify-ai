import Foundation

#if DEBUG

public struct MultilingualRetrievalE2ESeedResult: Sendable {
    public var matches: [ExchangeDirectoryMatch]
    public var providerProjection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
    public var providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot
    public var enrichedRooferSurface: ExchangeIndexedProviderSurface?
    public var usesOverlayForPublishedRoofer: Bool

    public init(
        matches: [ExchangeDirectoryMatch],
        providerProjection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
        providerIndexing: MultilingualRetrievalE2EProviderIndexingSnapshot,
        enrichedRooferSurface: ExchangeIndexedProviderSurface? = nil,
        usesOverlayForPublishedRoofer: Bool = true
    ) {
        self.matches = matches
        self.providerProjection = providerProjection
        self.providerIndexing = providerIndexing
        self.enrichedRooferSurface = enrichedRooferSurface
        self.usesOverlayForPublishedRoofer = usesOverlayForPublishedRoofer
    }
}

public enum MultilingualRetrievalE2ELiveEnricherSeeder {
    public static func seedCatalog(
        seedMode: MultilingualRetrievalE2EAuditSupport.SeedMode,
        indexedSurfaceEnricher: any ExchangeIndexedProviderSurfaceEnricher,
        diagnosticsStore: ProviderSurfaceEnrichmentDiagnosticsStore?,
        expectedEnglishTokens: [String]
    ) async throws -> MultilingualRetrievalE2ESeedResult {
        let totalStarted = CFAbsoluteTimeGetCurrent()

        let indexedStarted = CFAbsoluteTimeGetCurrent()
        let rooferEntities = MultilingualRetrievalE2EFixtureBuilder.rawRooferEntities()
        let indexedSurfaceBuilder = ExchangeIndexedProviderSurfaceBuilder()
        let deterministicRooferSurface = indexedSurfaceBuilder.build(
            profile: rooferEntities.profile,
            offers: [rooferEntities.offer]
        )
        let indexedSurfaceMs = Int((CFAbsoluteTimeGetCurrent() - indexedStarted) * 1000)

        let enrichStarted = CFAbsoluteTimeGetCurrent()
        let enrichedRooferSurface = await indexedSurfaceEnricher.enrich(surface: deterministicRooferSurface)
        let enricherMs = Int((CFAbsoluteTimeGetCurrent() - enrichStarted) * 1000)
        let diagnostics = await diagnosticsStore?.last

        let docsStarted = CFAbsoluteTimeGetCurrent()
        let retrievalDocumentBuilder = ExchangeRetrievalDocumentBuilder()
        let rooferDocs = retrievalDocumentBuilder.build(
            from: enrichedRooferSurface,
            counterpartyID: MultilingualRetrievalE2EFixtureBuilder.NodeID.roofer,
            sourceKind: .remote
        )
        let retrievalDocsMs = Int((CFAbsoluteTimeGetCurrent() - docsStarted) * 1000)

        let embedStarted = CFAbsoluteTimeGetCurrent()
        var catalog = [
            MultilingualRetrievalE2EFixtureBuilder.makeDirectoryMatch(
                nodeID: MultilingualRetrievalE2EFixtureBuilder.NodeID.roofer,
                profile: rooferEntities.profile,
                offers: [rooferEntities.offer],
                embeddedDocs: rooferDocs,
                includeAxisEmbeddings: seedMode == .localAxisEmbeddings,
                profileAxis: 4,
                offerAxes: [MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer: 4]
            ),
            MultilingualRetrievalE2EFixtureBuilder.buildDeterministicNoisyHomeMatch(
                includeAxisEmbeddings: seedMode == .localAxisEmbeddings
            )
        ]
        catalog = try await embedCatalog(catalog, seedMode: seedMode)
        let embedMs = Int((CFAbsoluteTimeGetCurrent() - embedStarted) * 1000)
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStarted) * 1000)

        let projection = MultilingualRetrievalE2EFixtureBuilder.providerProjectionAudit(from: catalog)
        let buildTimings = MultilingualRetrievalE2EProviderBuildTimings(
            indexedSurfaceMs: indexedSurfaceMs,
            enricherMs: enricherMs,
            retrievalDocsMs: retrievalDocsMs,
            embedMs: embedMs,
            totalMs: totalMs
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingAudit.liveEnricherSnapshot(
            enrichedSurface: enrichedRooferSurface,
            projection: projection,
            diagnostics: diagnostics,
            buildTimings: buildTimings,
            expectedEnglishTokens: expectedEnglishTokens
        )

        print(
            "[MultilingualE2E] liveEnricher seeded enricherAttempted=\(indexing.providerEnricherAttempted) " +
            "enricherSucceeded=\(indexing.providerEnricherSucceeded) unsafeFallback=\(indexing.providerUnsafeFallbackTriggered) " +
            "carrierPresent=\(!(indexing.providerCanonicalEnglishRetrievalText?.isEmpty ?? true)) totalMs=\(totalMs)"
        )

        return MultilingualRetrievalE2ESeedResult(
            matches: catalog,
            providerProjection: projection,
            providerIndexing: indexing,
            enrichedRooferSurface: enrichedRooferSurface
        )
    }

    public static func seedCatalog(
        for fixture: MultilingualSecretaryMatrixFixture,
        seedMode: MultilingualRetrievalE2EAuditSupport.SeedMode,
        indexedSurfaceEnricher: any ExchangeIndexedProviderSurfaceEnricher,
        diagnosticsStore: ProviderSurfaceEnrichmentDiagnosticsStore?
    ) async throws -> MultilingualRetrievalE2ESeedResult {
        let totalStarted = CFAbsoluteTimeGetCurrent()

        let indexedStarted = CFAbsoluteTimeGetCurrent()
        let entities = MultilingualSecretaryMatrixCatalogBuilder.buildRawProviderEntities(for: fixture)
        let indexedSurfaceBuilder = ExchangeIndexedProviderSurfaceBuilder()
        let deterministicSurface = indexedSurfaceBuilder.build(
            profile: entities.profile,
            offers: [entities.offer]
        )
        let indexedSurfaceMs = Int((CFAbsoluteTimeGetCurrent() - indexedStarted) * 1000)

        let enrichStarted = CFAbsoluteTimeGetCurrent()
        let enrichedSurface = await indexedSurfaceEnricher.enrich(surface: deterministicSurface)
        let enricherMs = Int((CFAbsoluteTimeGetCurrent() - enrichStarted) * 1000)
        let diagnostics = await diagnosticsStore?.last

        let docsStarted = CFAbsoluteTimeGetCurrent()
        let retrievalDocumentBuilder = ExchangeRetrievalDocumentBuilder()
        let exactDocs = retrievalDocumentBuilder.build(
            from: enrichedSurface,
            counterpartyID: fixture.expectedSelectedNodeID,
            sourceKind: .remote
        )
        let retrievalDocsMs = Int((CFAbsoluteTimeGetCurrent() - docsStarted) * 1000)

        let embedStarted = CFAbsoluteTimeGetCurrent()
        var catalog = [
            MultilingualRetrievalE2EFixtureBuilder.makeDirectoryMatch(
                nodeID: fixture.expectedSelectedNodeID,
                profile: entities.profile,
                offers: [entities.offer],
                embeddedDocs: exactDocs,
                includeAxisEmbeddings: seedMode == .localAxisEmbeddings,
                profileAxis: fixture.retrievalAxis,
                offerAxes: [fixture.expectedSelectedOfferID: fixture.retrievalAxis]
            ),
            MultilingualSecretaryMatrixCatalogBuilder.buildNoisyMatch(for: fixture)
        ]
        catalog = try await embedCatalog(catalog, seedMode: seedMode)
        let embedMs = Int((CFAbsoluteTimeGetCurrent() - embedStarted) * 1000)
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStarted) * 1000)

        let projection = MultilingualSecretaryMatrixEvaluation.providerProjectionAudit(
            catalog: catalog,
            fixture: fixture
        )
        let buildTimings = MultilingualRetrievalE2EProviderBuildTimings(
            indexedSurfaceMs: indexedSurfaceMs,
            enricherMs: enricherMs,
            retrievalDocsMs: retrievalDocsMs,
            embedMs: embedMs,
            totalMs: totalMs
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingAudit.liveEnricherSnapshot(
            enrichedSurface: enrichedSurface,
            projection: projection,
            diagnostics: diagnostics,
            buildTimings: buildTimings,
            expectedEnglishTokens: fixture.expectedEnglishCarrierTokens,
            primaryOfferID: fixture.expectedSelectedOfferID
        )

        print(
            "[MultilingualLiveSubset] liveEnricher seeded fixture=\(fixture.id) enricherAttempted=\(indexing.providerEnricherAttempted) " +
            "enricherSucceeded=\(indexing.providerEnricherSucceeded) unsafeFallback=\(indexing.providerUnsafeFallbackTriggered) " +
            "carrierPresent=\(!(indexing.providerCanonicalEnglishRetrievalText?.isEmpty ?? true)) totalMs=\(totalMs)"
        )

        return MultilingualRetrievalE2ESeedResult(
            matches: catalog,
            providerProjection: projection,
            providerIndexing: indexing,
            enrichedRooferSurface: enrichedSurface
        )
    }

    private static func embedCatalog(
        _ catalog: [ExchangeDirectoryMatch],
        seedMode: MultilingualRetrievalE2EAuditSupport.SeedMode
    ) async throws -> [ExchangeDirectoryMatch] {
        switch seedMode {
        case .localAxisEmbeddings:
            return catalog
        case .onDeviceONNX:
            var config = ONNXSentenceEmbedder.Config()
            config.enableTraceLogs = false
            let embedder = ONNXSentenceEmbedder(config: config)
            _ = embedder.embedPassage("multilingual retrieval e2e live enricher warmup")
            return ExchangeRetrievalAccuracyFixtureBuilder.preEmbedCatalogWithONNX(catalog, embedder: embedder)
        }
    }
}

#endif
