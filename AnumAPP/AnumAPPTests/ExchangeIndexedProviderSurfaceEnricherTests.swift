import XCTest
@testable import AnumCore

final class ExchangeIndexedProviderSurfaceEnricherTests: XCTestCase {
    func test_publicationCoordinator_withReadyProvider_enrichesBeforeRetrievalPublish() async throws {
        let now = Date(timeIntervalSince1970: 1_726_300_000)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("enrichment-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: storeURL)
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            displayName: "Builder",
            summary: "Baseline profile",
            visibility: .discoverable,
            offers: ["contractor matching"],
            updatedAt: now
        )
        let offer = ExchangeOffer(
            id: "offer-1",
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Home support",
            summary: "Baseline offer",
            status: .active,
            visibility: .publicDiscoverable,
            updatedAt: now
        )
        try await store.savePublicProfile(profile)
        try await store.saveOffer(offer)

        let dto = ProviderSurfaceEnrichmentDTO(
            semanticConcepts: ["works with first-time developers"],
            softPreferences: nil,
            commercialConstraints: nil,
            timeAvailabilityConstraints: nil,
            broadRecallTokens: nil,
            sourceTextBlocks: ["accepts small renovation budgets"],
            confidence: 0.92
        )
        let provider = AsyncFixedSurfaceProvider(rawJSON: encode(dto), ready: true)
        let enricher = LLMIndexedProviderSurfaceEnricher(provider: provider)
        let directory = RecordingDirectoryClient()
        let coordinator = ExchangeSellerPublicationCoordinator(
            store: store,
            directoryClient: directory,
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            embeddingProvider: FixedEmbeddingProvider(dimensions: 8),
            indexedSurfaceEnricher: enricher
        )

        _ = try await coordinator.publishSellerSurface(
            ownerNodeID: "node-1",
            ownerDisplayName: "Builder",
            now: now
        )

        let docs = await directory.lastPublishedDocuments
        let surface = await directory.lastPublishedSurface
        let text = docs.map { $0.semanticText + " " + $0.lexicalText }.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("works with first-time developers"))
        XCTAssertTrue(text.contains("accepts small renovation budgets"))
        XCTAssertEqual(surface?.indexedSurfaceVersion, 1)
        XCTAssertTrue(surface?.indexedProviderSurface?.semanticConcepts.contains(where: {
            $0.lowercased().contains("first-time developers")
        }) == true)
        XCTAssertTrue(surface?.indexedOffers?.contains(where: { $0.offerID == "offer-1" }) == true)
    }

    func test_publicationCoordinator_withBusyProvider_fallsBackUnchanged() async throws {
        let now = Date(timeIntervalSince1970: 1_726_300_001)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("enrichment-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: storeURL)
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            displayName: "Builder",
            summary: "Baseline profile",
            visibility: .discoverable,
            offers: ["contractor matching"],
            updatedAt: now
        )
        let offer = ExchangeOffer(
            id: "offer-1",
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Home support",
            summary: "Baseline offer",
            status: .active,
            visibility: .publicDiscoverable,
            updatedAt: now
        )
        try await store.savePublicProfile(profile)
        try await store.saveOffer(offer)

        let provider = AsyncRecordingSurfaceProvider(ready: false, behavior: .returning("{}"))
        let diagnostics = ProviderSurfaceEnrichmentDiagnosticsStore()
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: provider,
            diagnosticsStore: diagnostics
        )
        let directory = RecordingDirectoryClient()
        let coordinator = ExchangeSellerPublicationCoordinator(
            store: store,
            directoryClient: directory,
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            embeddingProvider: FixedEmbeddingProvider(dimensions: 8),
            indexedSurfaceEnricher: enricher
        )

        _ = try await coordinator.publishSellerSurface(
            ownerNodeID: "node-1",
            ownerDisplayName: "Builder",
            now: now
        )

        let calls = await provider.callCount
        let diag = await diagnostics.last
        let docs = await directory.lastPublishedDocuments
        let publishedSurface = await directory.lastPublishedSurface
        let text = docs.map { $0.semanticText + " " + $0.lexicalText }.joined(separator: " ").lowercased()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(diag?.failureReason, .modelBusy)
        XCTAssertFalse(text.contains("first-time developers"))
        XCTAssertEqual(publishedSurface?.indexedSurfaceVersion, 1)
    }

    func test_publicationPayload_indexedOffers_excludesHiddenInactive() async throws {
        let now = Date(timeIntervalSince1970: 1_726_300_002)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("enrichment-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: storeURL)
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            displayName: "Builder",
            summary: "Baseline profile",
            visibility: .discoverable,
            offers: ["contractor matching"],
            updatedAt: now
        )
        let visibleOffer = ExchangeOffer(
            id: "offer-visible",
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Visible Offer",
            status: .active,
            visibility: .publicDiscoverable,
            updatedAt: now
        )
        let hiddenOffer = ExchangeOffer(
            id: "offer-hidden",
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Hidden Offer",
            status: .active,
            visibility: .hidden,
            updatedAt: now
        )
        let pausedOffer = ExchangeOffer(
            id: "offer-paused",
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Paused Offer",
            status: .paused,
            visibility: .publicDiscoverable,
            updatedAt: now
        )
        try await store.savePublicProfile(profile)
        try await store.saveOffer(visibleOffer)
        try await store.saveOffer(hiddenOffer)
        try await store.saveOffer(pausedOffer)

        let coordinator = ExchangeSellerPublicationCoordinator(
            store: store,
            directoryClient: RecordingDirectoryClient(),
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            embeddingProvider: FixedEmbeddingProvider(dimensions: 8),
            indexedSurfaceEnricher: NoopIndexedProviderSurfaceEnricher()
        )
        let directory = RecordingDirectoryClient()
        let liveCoordinator = ExchangeSellerPublicationCoordinator(
            store: store,
            directoryClient: directory,
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            embeddingProvider: FixedEmbeddingProvider(dimensions: 8),
            indexedSurfaceEnricher: NoopIndexedProviderSurfaceEnricher()
        )

        _ = coordinator // keeps initializer compile coverage
        _ = try await liveCoordinator.publishSellerSurface(
            ownerNodeID: "node-1",
            ownerDisplayName: "Builder",
            now: now
        )

        let indexedOffers = await directory.lastPublishedSurface?.indexedOffers ?? []
        XCTAssertEqual(indexedOffers.map(\.offerID), ["offer-visible"])
    }

    func test_publicationPayload_indexedProjection_capsAndSanitizesAtomicTokens() async throws {
        let now = Date(timeIntervalSince1970: 1_726_300_003)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("enrichment-\(UUID().uuidString).sqlite")
        let store = try ExchangeSQLiteStore(databaseURL: storeURL)
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            displayName: "Builder",
            summary: "Baseline profile",
            visibility: .discoverable,
            offers: ["contractor matching"],
            updatedAt: now
        )
        let offer = ExchangeOffer(
            id: "offer-1",
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Home support",
            status: .active,
            visibility: .publicDiscoverable,
            updatedAt: now
        )
        try await store.savePublicProfile(profile)
        try await store.saveOffer(offer)

        let longBlock = String(repeating: "a", count: 800)
        let dto = ProviderSurfaceEnrichmentDTO(
            broadRecallTokens: [
                "home in gta, and seller offers vendor take back mortgage",
                "gta"
            ],
            sourceTextBlocks: Array(repeating: longBlock, count: 30),
            confidence: 0.95
        )
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: AsyncFixedSurfaceProvider(rawJSON: encode(dto), ready: true)
        )
        let directory = RecordingDirectoryClient()
        let coordinator = ExchangeSellerPublicationCoordinator(
            store: store,
            directoryClient: directory,
            sellerSurfaceService: ExchangeDefaultSellerSurfaceService(),
            publicationService: ExchangeDefaultPublicationService(),
            embeddingProvider: FixedEmbeddingProvider(dimensions: 8),
            indexedSurfaceEnricher: enricher
        )

        _ = try await coordinator.publishSellerSurface(
            ownerNodeID: "node-1",
            ownerDisplayName: "Builder",
            now: now
        )

        let providerProjection = await directory.lastPublishedSurface?.indexedProviderSurface
        XCTAssertFalse(providerProjection?.broadRecallTokens.contains(where: { $0.contains(",") }) ?? true)
        XCTAssertTrue(providerProjection?.broadRecallTokens.contains("gta") == true)
        XCTAssertLessThanOrEqual(providerProjection?.sourceTextBlocks.count ?? 0, 12)
        XCTAssertLessThanOrEqual(providerProjection?.sourceTextBlocks.first?.count ?? 0, 280)
    }

    func test_llmEnrichment_appendsOpenEndedClaims() async {
        let base = fixtureSurface()
        let dto = ProviderSurfaceEnrichmentDTO(
            semanticConcepts: ["works with first-time developers"],
            softPreferences: ["accepts small renovation budgets"],
            sourceTextBlocks: ["works with first-time developers", "accepts small renovation budgets"],
            confidence: 0.92
        )
        let store = ProviderSurfaceEnrichmentDiagnosticsStore()
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: AsyncFixedSurfaceProvider(rawJSON: encode(dto), ready: true),
            diagnosticsStore: store
        )

        let out = await enricher.enrich(surface: base)
        XCTAssertTrue(out.semanticConcepts.contains { $0.lowercased().contains("first-time developers") })
        XCTAssertTrue(out.softPreferences.contains { $0.lowercased().contains("small renovation budgets") })
        let diag = await store.last
        XCTAssertEqual(diag?.source, .llmEnriched)
    }

    func test_commercialEnrichment_vtbPreserved_andVisibleInRetrievalDoc() async {
        let base = fixtureSurface()
        let dto = ProviderSurfaceEnrichmentDTO(
            semanticConcepts: ["vendor take-back mortgage", "seller financing considered"],
            softPreferences: nil,
            commercialConstraints: [
                .init(text: "vendor take-back mortgage", isHard: false),
                .init(text: "seller financing considered", isHard: false)
            ],
            timeAvailabilityConstraints: nil,
            broadRecallTokens: nil,
            sourceTextBlocks: nil,
            confidence: 0.88
        )
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: AsyncFixedSurfaceProvider(rawJSON: encode(dto), ready: true)
        )

        let out = await enricher.enrich(surface: base)
        let doc = ExchangeRetrievalDocumentBuilder().build(from: out, counterpartyID: "cp-1", sourceKind: .local)
            .first { $0.surfaceType == .publicProfileCapability }!
        let haystack = [doc.semanticText, doc.lexicalText].joined(separator: " ").lowercased()
        XCTAssertTrue(haystack.contains("vendor take-back mortgage"))
        XCTAssertTrue(haystack.contains("seller financing considered"))
    }

    func test_doesNotEraseDeterministicFields() async {
        let base = fixtureSurface()
        let dto = ProviderSurfaceEnrichmentDTO(semanticConcepts: ["new semantic"], confidence: 0.9)
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: AsyncFixedSurfaceProvider(rawJSON: encode(dto), ready: true)
        )
        let out = await enricher.enrich(surface: base)
        XCTAssertTrue(Set(out.providerTerms).isSuperset(of: Set(base.providerTerms)))
        XCTAssertTrue(Set(out.capabilityTerms).isSuperset(of: Set(base.capabilityTerms)))
        XCTAssertTrue(Set(out.sourceTextBlocks).isSuperset(of: Set(base.sourceTextBlocks)))
    }

    func test_invalidJSON_returnsOriginal_andDiagnosticsFallback() async {
        let base = fixtureSurface()
        let store = ProviderSurfaceEnrichmentDiagnosticsStore()
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: AsyncFixedSurfaceProvider(rawJSON: "not-json", ready: true),
            diagnosticsStore: store
        )
        let out = await enricher.enrich(surface: base)
        XCTAssertEqual(out, base)
        let diag = await store.last
        XCTAssertEqual(diag?.source, .fallbackOriginal)
    }

    func test_noisyMarkdownRepair_succeeds_recordsRepaired() async {
        let base = fixtureSurface()
        let dto = ProviderSurfaceEnrichmentDTO(semanticConcepts: ["repair phrase"], confidence: 0.95)
        let noisy = "noise ```json\n\(encode(dto))\n``` tail"
        let store = ProviderSurfaceEnrichmentDiagnosticsStore()
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: AsyncFixedSurfaceProvider(rawJSON: noisy, ready: true),
            diagnosticsStore: store
        )
        let out = await enricher.enrich(surface: base)
        XCTAssertTrue(out.semanticConcepts.contains { $0.lowercased().contains("repair phrase") })
        let diag = await store.last
        XCTAssertEqual(diag?.source, .llmRepairedJSON)
    }

    func test_busyProvider_returnsOriginal_withoutCallingProvider() async {
        let base = fixtureSurface()
        let provider = AsyncRecordingSurfaceProvider(ready: false, behavior: .returning("{}"))
        let store = ProviderSurfaceEnrichmentDiagnosticsStore()
        let enricher = LLMIndexedProviderSurfaceEnricher(provider: provider, diagnosticsStore: store)
        let out = await enricher.enrich(surface: base)
        XCTAssertEqual(out, base)
        let calls = await provider.callCount
        let diag = await store.last
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(diag?.failureReason, .modelBusy)
    }

    func test_timeout_returnsOriginal_quickly() async {
        let base = fixtureSurface()
        let provider = AsyncRecordingSurfaceProvider(ready: true, behavior: .sleepThenReturn(seconds: 0.30, json: "{}"))
        let store = ProviderSurfaceEnrichmentDiagnosticsStore()
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: provider,
            config: .init(timeoutSeconds: 0.05),
            diagnosticsStore: store
        )
        let start = CFAbsoluteTimeGetCurrent()
        let out = await enricher.enrich(surface: base)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(out, base)
        XCTAssertLessThan(elapsed, 0.25)
        let diag = await store.last
        XCTAssertEqual(diag?.failureReason, .timeout)
    }

    func test_atomicTokenSanitizer_rejectsFusedBroadRecallSentence() async {
        let base = fixtureSurface()
        let fused = "home in gta, and seller offers vendor take back mortgage"
        let dto = ProviderSurfaceEnrichmentDTO(
            broadRecallTokens: [fused],
            confidence: 0.95
        )
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: AsyncFixedSurfaceProvider(rawJSON: encode(dto), ready: true)
        )
        let out = await enricher.enrich(surface: base)
        XCTAssertFalse(out.broadRecallTokens.contains(fused.lowercased()))
        XCTAssertTrue(out.broadRecallTokens.contains("gta"))
    }

    func test_enrichedSurface_retrievalDocsContainSemanticPhrases() async {
        let base = fixtureSurface()
        let dto = ProviderSurfaceEnrichmentDTO(
            semanticConcepts: ["works with first-time developers"],
            sourceTextBlocks: ["accepts small renovation budgets"],
            confidence: 0.9
        )
        let enricher = LLMIndexedProviderSurfaceEnricher(
            provider: AsyncFixedSurfaceProvider(rawJSON: encode(dto), ready: true)
        )
        let out = await enricher.enrich(surface: base)
        let docs = ExchangeRetrievalDocumentBuilder().build(from: out, counterpartyID: "cp-1", sourceKind: .local)
        let text = docs.map { $0.semanticText + " " + $0.lexicalText }.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("works with first-time developers"))
        XCTAssertTrue(text.contains("accepts small renovation budgets"))
    }
}

private extension ExchangeIndexedProviderSurfaceEnricherTests {
    actor RecordingDirectoryClient: ExchangeDirectoryClient {
        private(set) var lastPublishedDocuments: [ExchangeRetrievalDocument] = []
        private(set) var lastPublishedSurface: ExchangePublishedSellerSurfacePayload?

        func search(_ request: ExchangeDirectorySearchRequest) async throws -> ExchangeDirectorySearchResponse {
            return ExchangeDirectorySearchResponse(matches: [], source: .local)
        }

        func publishSellerSurface(_ request: ExchangeSellerSurfacePublishRequest) async throws -> ExchangeSellerSurfacePublishResponse {
            lastPublishedSurface = request.surface
            return ExchangeSellerSurfacePublishResponse(
                ok: true,
                remoteProfileID: request.surface.publicProfile.id,
                remoteOfferIDs: request.surface.offers.map(\.id),
                publishedAt: Date()
            )
        }

        func unpublishSellerSurface(nodeID: String, publicProfileID: String) async throws -> ExchangeSellerSurfaceUnpublishResponse {
            return ExchangeSellerSurfaceUnpublishResponse(
                ok: true,
                nodeID: nodeID,
                publicProfileID: publicProfileID,
                unpublishedAt: Date()
            )
        }

        func publishRetrievalDocuments(_ request: ExchangeRetrievalDocumentPublishRequest) async throws -> ExchangeRetrievalDocumentPublishResponse {
            lastPublishedDocuments = request.documents
            return ExchangeRetrievalDocumentPublishResponse(
                ok: true,
                nodeID: request.nodeID,
                sourceKind: request.sourceKind,
                acceptedDocumentCount: request.documents.count,
                publishedAt: request.publishedAt
            )
        }
    }

    struct FixedEmbeddingProvider: MemoryEmbeddingProvider, Sendable {
        let dimensions: Int
        func embed(_ text: String) -> [Float]? {
            Array(repeating: 0.1, count: dimensions)
        }
    }

    actor AsyncRecordingSurfaceProvider: AsyncProviderSurfaceEnrichmentJSONProvider {
        enum Behavior {
            case returning(String)
            case sleepThenReturn(seconds: Double, json: String)
            case throwing(Error)
        }

        private(set) var callCount: Int = 0
        let ready: Bool
        let behavior: Behavior

        init(ready: Bool, behavior: Behavior) {
            self.ready = ready
            self.behavior = behavior
        }

        func isReadyForImmediateExtraction() async -> Bool { ready }

        func enrichProviderSurfaceJSON(prompt: String) async throws -> String {
            callCount += 1
            switch behavior {
            case .returning(let json):
                return json
            case .sleepThenReturn(let seconds, let json):
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return json
            case .throwing(let error):
                throw error
            }
        }
    }

    struct AsyncFixedSurfaceProvider: AsyncProviderSurfaceEnrichmentJSONProvider {
        let rawJSON: String
        let ready: Bool
        func isReadyForImmediateExtraction() async -> Bool { ready }
        func enrichProviderSurfaceJSON(prompt: String) async throws -> String { rawJSON }
    }

    func encode(_ dto: ProviderSurfaceEnrichmentDTO) -> String {
        let data = try! JSONEncoder().encode(dto)
        return String(data: data, encoding: .utf8)!
    }

    func fixtureSurface() -> ExchangeIndexedProviderSurface {
        ExchangeIndexedProviderSurface(
            id: "profile-1",
            publicProfileID: "profile-1",
            nodeID: "node-1",
            displayName: "Builder Profile",
            headline: "Local contractor network",
            summary: "Reliable local team",
            visibility: "discoverable",
            availability: "open",
            regions: .init(
                regionTags: ["gta"],
                canonicalRegionIDs: ["ca-on-gta"],
                parentRegionIDs: ["ca-on"],
                regionAliases: ["greater toronto area"]
            ),
            providerTerms: ["builder profile", "local contractor network"],
            capabilityTerms: ["contractor matching", "real estate"],
            affinityTerms: ["housing"],
            broadRecallTokens: ["gta"],
            semanticConcepts: ["home renovation support"],
            hardConstraints: [],
            softPreferences: [],
            commercialConstraints: [],
            timeAvailabilityConstraints: [],
            reachability: .init(
                accessMode: "direct",
                acceptingInbound: true,
                disclosureCeiling: "balanced",
                routeableOnly: false,
                intentCategoryPolicy: "permissive"
            ),
            offers: [],
            sourceTextBlocks: ["Reliable local team"],
            updatedAt: Date(timeIntervalSince1970: 1_726_200_000),
            schemaVersion: 1
        )
    }
}
