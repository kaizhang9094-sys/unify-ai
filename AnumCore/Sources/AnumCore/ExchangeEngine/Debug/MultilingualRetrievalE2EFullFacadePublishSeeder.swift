import Foundation

#if DEBUG

public enum MultilingualRetrievalE2EFullFacadePublishSeeder {
    public struct Dependencies: Sendable {
        public var directoryClient: any ExchangeDirectoryClient
        public var diagnosticsStore: ProviderSurfaceEnrichmentDiagnosticsStore?
        public var ownerDisplayName: String?

        public init(
            directoryClient: any ExchangeDirectoryClient,
            diagnosticsStore: ProviderSurfaceEnrichmentDiagnosticsStore? = nil,
            ownerDisplayName: String? = "屋顶维修师傅"
        ) {
            self.directoryClient = directoryClient
            self.diagnosticsStore = diagnosticsStore
            self.ownerDisplayName = ownerDisplayName
        }
    }

    public static func seedCatalog(
        facade: ExchangeFacade,
        dependencies: Dependencies,
        seedMode: MultilingualRetrievalE2EAuditSupport.SeedMode,
        expectedEnglishTokens: [String]
    ) async throws -> MultilingualRetrievalE2ESeedResult {
        let totalStarted = CFAbsoluteTimeGetCurrent()
        ExchangeSellerPublicationDebugCapture.clear()

        let entities = MultilingualRetrievalE2EFixtureBuilder.rawRooferEntities()
        let ownerNodeID = entities.profile.nodeID

        var profileSaveAttempted = false
        var profileSaveSucceeded = false
        var offerSaveAttempted = false
        var offerSaveSucceeded = false
        var publishAttempted = false
        var publishSucceeded = false
        var publishFailureReason: String?

        do {
            profileSaveAttempted = true
            try await facade.savePublicProfile(entities.profile)
            profileSaveSucceeded = true
        } catch {
            publishFailureReason = "profileSaveFailed: \(error)"
        }

        if profileSaveSucceeded {
            do {
                offerSaveAttempted = true
                try await facade.saveOffer(entities.offer)
                offerSaveSucceeded = true
            } catch {
                publishFailureReason = "offerSaveFailed: \(error)"
            }
        }

        if offerSaveSucceeded {
            publishAttempted = true
            do {
                _ = try await facade.publishSellerSurface(
                    ownerNodeID: ownerNodeID,
                    ownerDisplayName: dependencies.ownerDisplayName
                )
                publishSucceeded = true
            } catch {
                publishFailureReason = "publishSellerSurfaceFailed: \(error)"
            }
        }

        let capture = ExchangeSellerPublicationDebugCapture.lastBuild
        let diagnostics = await dependencies.diagnosticsStore?.last
        let recoveredDocs = capture?.retrievalDocuments ?? []
        let enrichedSurface = capture?.enrichedIndexedSurface

        var federationAttempted = false
        var federationSucceeded = false
        var federationFailureReason: String?
        if publishSucceeded {
            federationAttempted = true
            let probe = await probeFederationRoundTrip(
                directoryClient: dependencies.directoryClient,
                ownerNodeID: ownerNodeID,
                queryText: "roofer roof estimate Aurora"
            )
            federationSucceeded = probe.succeeded
            federationFailureReason = probe.failureReason
        }

        let usesOverlayForRoofer = !federationSucceeded
        var catalog: [ExchangeDirectoryMatch] = []

        if usesOverlayForRoofer, !recoveredDocs.isEmpty {
            catalog.append(
                MultilingualRetrievalE2EFixtureBuilder.makeDirectoryMatch(
                    nodeID: ownerNodeID,
                    profile: entities.profile,
                    offers: [entities.offer],
                    embeddedDocs: recoveredDocs,
                    includeAxisEmbeddings: seedMode == .localAxisEmbeddings,
                    profileAxis: 4,
                    offerAxes: [MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer: 4]
                )
            )
        }

        catalog.append(
            MultilingualRetrievalE2EFixtureBuilder.buildDeterministicNoisyHomeMatch(
                includeAxisEmbeddings: seedMode == .localAxisEmbeddings
            )
        )

        if seedMode == .onDeviceONNX {
            var config = ONNXSentenceEmbedder.Config()
            config.enableTraceLogs = false
            let embedder = ONNXSentenceEmbedder(config: config)
            _ = embedder.embedPassage("multilingual retrieval e2e full facade warmup")
            catalog = ExchangeRetrievalAccuracyFixtureBuilder.preEmbedCatalogWithONNX(catalog, embedder: embedder)
        }

        let projection = MultilingualRetrievalE2EFixtureBuilder.providerProjectionAudit(from: catalog)
            ?? projectionFromRecoveredDocs(
                recoveredDocs: recoveredDocs,
                profile: entities.profile,
                offer: entities.offer
            )
        let offerObjectCarrier = projection?.offerObjectSearchableText
            ?? objectDoc(from: recoveredDocs, offerID: entities.offer.id)?.searchableText
        let serviceAreas = projection?.serviceAreas
            ?? detailDoc(from: recoveredDocs, offerID: entities.offer.id)?.serviceAreas.map(\.displayName)
            ?? []
        let carrierAfter = projection?.canonicalEnglishRetrievalText
            ?? capture?.canonicalEnglishCarrierAfterPublish
        let carrierBefore = capture?.canonicalEnglishCarrierBeforePublish
        let chinesePreserved = projection?.preservedChineseInSourceBlocks
            ?? entities.offer.summary?.contains("屋顶") == true

        let publication = MultilingualRetrievalE2EFullFacadePublicationSnapshot(
            fullFacadeProfileSaveAttempted: profileSaveAttempted,
            fullFacadeProfileSaveSucceeded: profileSaveSucceeded,
            fullFacadeOfferSaveAttempted: offerSaveAttempted,
            fullFacadeOfferSaveSucceeded: offerSaveSucceeded,
            fullFacadePublishAttempted: publishAttempted,
            fullFacadePublishSucceeded: publishSucceeded,
            publishRetrievalDocumentsAttempted: capture?.publishRetrievalDocumentsAttempted ?? false,
            publishRetrievalDocumentsSucceeded: capture?.publishRetrievalDocumentsSucceeded ?? false,
            federationRoundTripAttempted: federationAttempted,
            federationRoundTripSucceeded: federationSucceeded,
            federationRoundTripFailureReason: federationFailureReason ?? publishFailureReason,
            retrievalDocumentsPublishedCount: capture?.retrievalDocuments.count ?? 0,
            retrievalDocumentsRecoveredCount: recoveredDocs.count,
            canonicalEnglishCarrierBeforePublish: carrierBefore,
            canonicalEnglishCarrierAfterPublish: carrierAfter,
            offerObjectCarrierAfterPublish: offerObjectCarrier,
            serviceAreasAfterPublish: serviceAreas,
            originalChinesePreservedAfterPublish: chinesePreserved,
            usesOverlayFallbackForRoofer: usesOverlayForRoofer
        )

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStarted) * 1000)
        let buildTimings = MultilingualRetrievalE2EProviderBuildTimings(
            indexedSurfaceMs: 0,
            enricherMs: 0,
            retrievalDocsMs: 0,
            embedMs: 0,
            totalMs: totalMs
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingAudit.fullFacadePublishSnapshot(
            projection: projection,
            diagnostics: diagnostics,
            buildTimings: buildTimings,
            expectedEnglishTokens: expectedEnglishTokens,
            publication: publication,
            enrichedSurface: enrichedSurface,
            usesOverlay: usesOverlayForRoofer
        )

        print(
            "[MultilingualE2E] fullFacade seeded profileSave=\(profileSaveSucceeded) offerSave=\(offerSaveSucceeded) " +
            "publish=\(publishSucceeded) docsPublished=\(publication.retrievalDocumentsPublishedCount) " +
            "federationRoundTrip=\(federationSucceeded) overlayFallback=\(usesOverlayForRoofer) totalMs=\(totalMs)"
        )

        return MultilingualRetrievalE2ESeedResult(
            matches: catalog,
            providerProjection: projection,
            providerIndexing: indexing,
            enrichedRooferSurface: enrichedSurface,
            usesOverlayForPublishedRoofer: usesOverlayForRoofer
        )
    }

    public static func seedCatalog(
        for fixture: MultilingualSecretaryMatrixFixture,
        facade: ExchangeFacade,
        dependencies: Dependencies,
        seedMode: MultilingualRetrievalE2EAuditSupport.SeedMode
    ) async throws -> MultilingualRetrievalE2ESeedResult {
        let totalStarted = CFAbsoluteTimeGetCurrent()
        ExchangeSellerPublicationDebugCapture.clear()

        let entities = MultilingualSecretaryMatrixCatalogBuilder.buildRawProviderEntities(for: fixture)
        let ownerNodeID = entities.profile.nodeID
        let ownerDisplayName = dependencies.ownerDisplayName
            ?? MultilingualSecretaryMatrixCatalogBuilder.displayName(from: fixture.providerProfileText)

        var profileSaveAttempted = false
        var profileSaveSucceeded = false
        var offerSaveAttempted = false
        var offerSaveSucceeded = false
        var publishAttempted = false
        var publishSucceeded = false
        var publishFailureReason: String?

        do {
            profileSaveAttempted = true
            try await facade.savePublicProfile(entities.profile)
            profileSaveSucceeded = true
        } catch {
            publishFailureReason = "profileSaveFailed: \(error)"
        }

        if profileSaveSucceeded {
            do {
                offerSaveAttempted = true
                try await facade.saveOffer(entities.offer)
                offerSaveSucceeded = true
            } catch {
                publishFailureReason = "offerSaveFailed: \(error)"
            }
        }

        if offerSaveSucceeded {
            publishAttempted = true
            do {
                _ = try await facade.publishSellerSurface(
                    ownerNodeID: ownerNodeID,
                    ownerDisplayName: ownerDisplayName
                )
                publishSucceeded = true
            } catch {
                publishFailureReason = "publishSellerSurfaceFailed: \(error)"
            }
        }

        let capture = ExchangeSellerPublicationDebugCapture.lastBuild
        let diagnostics = await dependencies.diagnosticsStore?.last
        let recoveredDocs = capture?.retrievalDocuments ?? []
        let enrichedSurface = capture?.enrichedIndexedSurface

        var federationAttempted = false
        var federationSucceeded = false
        var federationFailureReason: String?
        if publishSucceeded {
            federationAttempted = true
            let probe = await probeFederationRoundTrip(
                directoryClient: dependencies.directoryClient,
                ownerNodeID: ownerNodeID,
                queryText: fixture.mockedCanonicalEnglishSearchText
            )
            federationSucceeded = probe.succeeded
            federationFailureReason = probe.failureReason
        }

        let usesOverlay = !federationSucceeded
        var catalog: [ExchangeDirectoryMatch] = []

        if usesOverlay, !recoveredDocs.isEmpty {
            catalog.append(
                MultilingualRetrievalE2EFixtureBuilder.makeDirectoryMatch(
                    nodeID: ownerNodeID,
                    profile: entities.profile,
                    offers: [entities.offer],
                    embeddedDocs: recoveredDocs,
                    includeAxisEmbeddings: seedMode == .localAxisEmbeddings,
                    profileAxis: fixture.retrievalAxis,
                    offerAxes: [fixture.expectedSelectedOfferID: fixture.retrievalAxis]
                )
            )
        }

        catalog.append(MultilingualSecretaryMatrixCatalogBuilder.buildNoisyMatch(for: fixture))

        if seedMode == .onDeviceONNX {
            var config = ONNXSentenceEmbedder.Config()
            config.enableTraceLogs = false
            let embedder = ONNXSentenceEmbedder(config: config)
            _ = embedder.embedPassage("multilingual live subset full facade warmup")
            catalog = ExchangeRetrievalAccuracyFixtureBuilder.preEmbedCatalogWithONNX(catalog, embedder: embedder)
        }

        let projection = MultilingualSecretaryMatrixEvaluation.providerProjectionAudit(catalog: catalog, fixture: fixture)
            ?? projectionFromRecoveredDocs(
                recoveredDocs: recoveredDocs,
                profile: entities.profile,
                offer: entities.offer,
                fixture: fixture
            )
        let offerObjectCarrier = projection?.offerObjectSearchableText
            ?? objectDoc(from: recoveredDocs, offerID: entities.offer.id)?.searchableText
        let serviceAreas = projection?.serviceAreas
            ?? detailDoc(from: recoveredDocs, offerID: entities.offer.id)?.serviceAreas.map(\.displayName)
            ?? fixture.expectedServiceAreas
        let carrierAfter = projection?.canonicalEnglishRetrievalText
            ?? capture?.canonicalEnglishCarrierAfterPublish
        let carrierBefore = capture?.canonicalEnglishCarrierBeforePublish
        let chinesePreserved = projection?.preservedChineseInSourceBlocks
            ?? MultilingualRetrievalE2EEvaluation.containsCJK(entities.offer.summary ?? "")

        let publication = MultilingualRetrievalE2EFullFacadePublicationSnapshot(
            fullFacadeProfileSaveAttempted: profileSaveAttempted,
            fullFacadeProfileSaveSucceeded: profileSaveSucceeded,
            fullFacadeOfferSaveAttempted: offerSaveAttempted,
            fullFacadeOfferSaveSucceeded: offerSaveSucceeded,
            fullFacadePublishAttempted: publishAttempted,
            fullFacadePublishSucceeded: publishSucceeded,
            publishRetrievalDocumentsAttempted: capture?.publishRetrievalDocumentsAttempted ?? false,
            publishRetrievalDocumentsSucceeded: capture?.publishRetrievalDocumentsSucceeded ?? false,
            federationRoundTripAttempted: federationAttempted,
            federationRoundTripSucceeded: federationSucceeded,
            federationRoundTripFailureReason: federationFailureReason ?? publishFailureReason,
            retrievalDocumentsPublishedCount: capture?.retrievalDocuments.count ?? 0,
            retrievalDocumentsRecoveredCount: recoveredDocs.count,
            canonicalEnglishCarrierBeforePublish: carrierBefore,
            canonicalEnglishCarrierAfterPublish: carrierAfter,
            offerObjectCarrierAfterPublish: offerObjectCarrier,
            serviceAreasAfterPublish: serviceAreas,
            originalChinesePreservedAfterPublish: chinesePreserved,
            usesOverlayFallbackForRoofer: usesOverlay
        )

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStarted) * 1000)
        let buildTimings = MultilingualRetrievalE2EProviderBuildTimings(
            indexedSurfaceMs: 0,
            enricherMs: 0,
            retrievalDocsMs: 0,
            embedMs: 0,
            totalMs: totalMs
        )
        let indexing = MultilingualRetrievalE2EProviderIndexingAudit.fullFacadePublishSnapshot(
            projection: projection,
            diagnostics: diagnostics,
            buildTimings: buildTimings,
            expectedEnglishTokens: fixture.expectedEnglishCarrierTokens,
            publication: publication,
            enrichedSurface: enrichedSurface,
            usesOverlay: usesOverlay
        )

        print(
            "[MultilingualLiveSubset] fullFacade seeded fixture=\(fixture.id) profileSave=\(profileSaveSucceeded) " +
            "offerSave=\(offerSaveSucceeded) publish=\(publishSucceeded) federationRoundTrip=\(federationSucceeded) " +
            "overlayFallback=\(usesOverlay) totalMs=\(totalMs)"
        )

        return MultilingualRetrievalE2ESeedResult(
            matches: catalog,
            providerProjection: projection,
            providerIndexing: indexing,
            enrichedRooferSurface: enrichedSurface,
            usesOverlayForPublishedRoofer: usesOverlay
        )
    }

    private static func probeFederationRoundTrip(
        directoryClient: any ExchangeDirectoryClient,
        ownerNodeID: String,
        queryText: String
    ) async -> (succeeded: Bool, failureReason: String?) {
        ExchangeDebugMultilingualFixtureRegistry.clear()
        defer {
            // Caller sets overlay after seed completes.
        }

        do {
            let response = try await directoryClient.search(
                ExchangeDirectorySearchRequest(
                    mode: .transactional,
                    intentKind: .find,
                    queryText: queryText,
                    tags: [],
                    regionTags: [],
                    limit: 20,
                    retrievalResponseMode: .clientRerank
                )
            )
            let found = response.matches.contains { $0.id == ownerNodeID }
            if found {
                return (true, nil)
            }
            return (false, "published_node_not_in_federation_search")
        } catch {
            return (false, String(describing: error))
        }
    }

    private static func projectionFromRecoveredDocs(
        recoveredDocs: [ExchangeRetrievalDocument],
        profile: ExchangePublicNodeProfile,
        offer: ExchangeOffer,
        fixture: MultilingualSecretaryMatrixFixture? = nil
    ) -> MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit? {
        guard !recoveredDocs.isEmpty else { return nil }
        let offerID = offer.id
        let detail = detailDoc(from: recoveredDocs, offerID: offerID)
        let object = objectDoc(from: recoveredDocs, offerID: offerID)
        let chinesePreserved: Bool
        if let fixture {
            switch fixture.languagePair {
            case .enUserEnProvider, .zhUserEnProvider:
                chinesePreserved = true
            case .enUserZhProvider, .zhUserZhProvider, .mixedUserMixedProvider:
                chinesePreserved = MultilingualRetrievalE2EEvaluation.containsCJK(offer.summary ?? "")
                    || MultilingualRetrievalE2EEvaluation.containsCJK(profile.summary ?? "")
            }
        } else {
            chinesePreserved = offer.summary?.contains("屋顶") == true
        }
        return MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit(
            nodeID: profile.nodeID,
            offerID: offerID,
            canonicalEnglishRetrievalText: detail?.canonicalEnglishRetrievalText,
            offerDetailUsesEnglishOnlyRetrievalProjection: detail?.usesEnglishOnlyRetrievalProjection ?? false,
            offerObjectUsesEnglishOnlyRetrievalProjection: object?.usesEnglishOnlyRetrievalProjection ?? false,
            serviceAreas: detail?.serviceAreas.map(\.displayName) ?? [],
            offerObjectSearchableText: object?.searchableText,
            preservedChineseInSourceBlocks: chinesePreserved
        )
    }

    private static func detailDoc(from docs: [ExchangeRetrievalDocument], offerID: String) -> ExchangeRetrievalDocument? {
        docs.first(where: { $0.offerID == offerID && $0.docKind == .offerDetail })
            ?? docs.first(where: { $0.docKind == .offerDetail })
    }

    private static func objectDoc(from docs: [ExchangeRetrievalDocument], offerID: String) -> ExchangeRetrievalDocument? {
        docs.first(where: { $0.offerID == offerID && $0.docKind == .offerObject })
            ?? docs.first(where: { $0.docKind == .offerObject })
    }
}

#endif
