import Foundation

private actor ExchangeSellerSurfacePublishInFlightGuard {
    private var activeProfileIDs = Set<String>()

    func tryAcquire(profileID: String) -> Bool {
        let normalized = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        if activeProfileIDs.contains(normalized) {
            return false
        }
        activeProfileIDs.insert(normalized)
        return true
    }

    func release(profileID: String) {
        let normalized = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        activeProfileIDs.remove(normalized)
    }
}

private enum ExchangeSellerSurfacePublishInFlight {
    static let guardBox = ExchangeSellerSurfacePublishInFlightGuard()
}

private actor ExchangeSellerSurfaceReconcileDebounceGuard {
    static let debounceInterval: TimeInterval = 45

    private var lastSkipAtByProfileID: [String: Date] = [:]

    func shouldSkipRecent(profileID: String, now: Date) -> Bool {
        guard let lastSkipAt = lastSkipAtByProfileID[profileID] else { return false }
        return now.timeIntervalSince(lastSkipAt) < Self.debounceInterval
    }

    func recordSkip(profileID: String, now: Date) {
        lastSkipAtByProfileID[profileID] = now
    }
}

private enum ExchangeSellerSurfaceReconcileDebounce {
    static let guardBox = ExchangeSellerSurfaceReconcileDebounceGuard()
}

public protocol ExchangeSellerPublicationCoordinating: Sendable {
    func publishSellerSurface(
        ownerNodeID: String,
        ownerDisplayName: String?,
        publicSupporterPresentation: ExchangeSupporterPresentation?,
        now: Date
    ) async throws -> ExchangePublicationState

    func unpublishSellerSurface(
        ownerNodeID: String,
        now: Date
    ) async throws -> ExchangePublicationState

    func reconcileSellerSurfacePublication(
        ownerNodeID: String,
        ownerDisplayName: String?,
        now: Date
    ) async throws -> ExchangePublicationState?
}

public struct ExchangeSellerPublicationCoordinator: ExchangeSellerPublicationCoordinating, Sendable {
    private let store: any ExchangeStore
    private let directoryClient: any ExchangeDirectoryClient
    private let sellerSurfaceService: any ExchangeSellerSurfaceService
    private let publicationService: any ExchangePublicationService
    private let embeddingProvider: any MemoryEmbeddingProvider
    private let indexedSurfaceBuilder: ExchangeIndexedProviderSurfaceBuilder
    private let retrievalDocumentBuilder: ExchangeRetrievalDocumentBuilder
    private let indexedSurfaceEnricher: any ExchangeIndexedProviderSurfaceEnricher

    public init(
        store: any ExchangeStore,
        directoryClient: any ExchangeDirectoryClient,
        sellerSurfaceService: any ExchangeSellerSurfaceService,
        publicationService: any ExchangePublicationService,
        embeddingProvider: any MemoryEmbeddingProvider,
        indexedSurfaceBuilder: ExchangeIndexedProviderSurfaceBuilder = .init(),
        retrievalDocumentBuilder: ExchangeRetrievalDocumentBuilder = .init(),
        indexedSurfaceEnricher: any ExchangeIndexedProviderSurfaceEnricher = NoopIndexedProviderSurfaceEnricher()
    ) {
        self.store = store
        self.directoryClient = directoryClient
        self.sellerSurfaceService = sellerSurfaceService
        self.publicationService = publicationService
        self.embeddingProvider = embeddingProvider
        self.indexedSurfaceBuilder = indexedSurfaceBuilder
        self.retrievalDocumentBuilder = retrievalDocumentBuilder
        self.indexedSurfaceEnricher = indexedSurfaceEnricher
    }

    public func publishSellerSurface(
        ownerNodeID: String,
        ownerDisplayName: String?,
        publicSupporterPresentation: ExchangeSupporterPresentation? = nil,
        now: Date = Date()
    ) async throws -> ExchangePublicationState {
        let nodeID = ownerNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nodeID.isEmpty else {
            throw ExchangeStoreError.storageFailure(reason: "Owner node ID is missing.")
        }

        let profile = try await requireOwnerPublicProfile(ownerNodeID: nodeID)
        let offers = try await store.listOffers(
            filter: .init(
                publicProfileID: profile.id,
                limit: 500
            )
        )

        let existingState = try await store.fetchPublicationState(
            forPublicProfileID: profile.id
        ) ?? publicationService.makeDefaultPublicationState(
            publicProfileID: profile.id,
            now: now
        )

        let issues = sellerSurfaceService.validateSurface(
            publicProfile: profile,
            offers: offers
        )

        let readiness = publicationService.evaluateReadiness(
            publicProfile: profile,
            offers: offers,
            publicationState: existingState,
            validationIssues: issues
        )

        guard readiness.isReadyToPublish else {
            let failedState = existingState.markingPublishFailed(
                summary: readiness.nextStepText ?? readiness.statusLine,
                at: now
            )
            try await store.savePublicationState(
                failedState,
                forPublicProfileID: profile.id
            )
            return failedState
        }

        let startedState = existingState.markingPublishStarted(at: now)
        try await store.savePublicationState(
            startedState,
            forPublicProfileID: profile.id
        )

        var profileForPublish = profile
        profileForPublish.publicSupporterPresentation = publicSupporterPresentation

        #if DEBUG
        GuardianCrownDebugLog.log(
            "PublishCoordinator",
            "nodeID=\(nodeID) profileID=\(profile.id) " +
            "param=\(GuardianCrownDebugLog.presentationLabel(publicSupporterPresentation)) " +
            "profileForPublish=\(GuardianCrownDebugLog.presentationLabel(profileForPublish.publicSupporterPresentation))"
        )
        #endif

        var surfacePayload = sellerSurfaceService.buildPublishedPayload(
            ownerNodeID: nodeID,
            ownerDisplayName: ownerDisplayName,
            publicProfile: profileForPublish,
            offers: offers,
            publicationState: startedState,
            now: now
        )

        let outwardOffers = outwardFacingOffers(offers)
        let deterministicIndexedSurface = indexedSurfaceBuilder.build(
            profile: profile,
            offers: outwardOffers
        )
        let enrichedIndexedSurface = await indexedSurfaceEnricher.enrich(
            surface: deterministicIndexedSurface
        )
        applyIndexedProjection(
            from: enrichedIndexedSurface,
            to: &surfacePayload
        )
        let baseRetrievalDocuments = retrievalDocumentBuilder.build(
            from: enrichedIndexedSurface,
            counterpartyID: nodeID,
            sourceKind: .local
        )

        let retrievalDocuments = enrichEmbeddingsIfNeeded(baseRetrievalDocuments)

#if DEBUG
        logRetrievalSlicePublishDocuments(retrievalDocuments)
        ExchangeSellerPublicationDebugCapture.recordBuild(
            nodeID: nodeID,
            profileID: profile.id,
            deterministicSurface: deterministicIndexedSurface,
            enrichedSurface: enrichedIndexedSurface,
            retrievalDocuments: retrievalDocuments
        )
#endif
        
#if DEBUG
let embeddedCount = retrievalDocuments.filter(\.hasEmbedding).count
let dimensions = retrievalDocuments
    .compactMap { $0.embedding?.count }
    .sorted()

print(
    "[ExchangeSellerPublicationCoordinator] retrieval docs total=\(retrievalDocuments.count) embedded=\(embeddedCount) dims=\(dimensions)"
)
#endif

guard retrievalDocuments.contains(where: \.hasEmbedding) else {
    let failedState = startedState.markingPublishFailed(
        summary: "No embedded retrieval documents were built. Seller surface was not published as discoverable.",
        at: now
    )

    try await store.savePublicationState(
        failedState,
        forPublicProfileID: profile.id
    )

    throw ExchangeStoreError.storageFailure(
        reason: "No embedded retrieval documents were built."
    )
}

        let acquiredInFlight = await ExchangeSellerSurfacePublishInFlight.guardBox.tryAcquire(profileID: profile.id)
        guard acquiredInFlight else {
#if DEBUG
            print(
                "[ExchangeSellerPublicationCoordinator] publish suppressed in-flight profileID=\(profile.id) nodeID=\(nodeID)"
            )
#endif
            return startedState
        }

        do {
#if DEBUG
            ExchangeSellerPublicationDebugCapture.recordPublishAttemptStarted()
#endif
            let publishResponse = try await directoryClient.publishSellerSurface(
                .init(
                    nodeID: nodeID,
                    displayName: ownerDisplayName,
                    surface: surfacePayload
                )
            )

            if !retrievalDocuments.isEmpty {
                _ = try await directoryClient.publishRetrievalDocuments(
                    .init(
                        nodeID: nodeID,
                        sourceKind: .local,
                        documents: retrievalDocuments,
                        replaceAll: true,
                        publishedAt: publishResponse.publishedAt
                    )
                )
            }

            let nextState = startedState.markingPublished(
                remoteProfileID: publishResponse.remoteProfileID,
                remoteOfferIDs: publishResponse.remoteOfferIDs,
                fingerprint: surfacePayload.fingerprint,
                at: publishResponse.publishedAt
            )

            try await store.savePublicationState(
                nextState,
                forPublicProfileID: profile.id
            )

#if DEBUG
            ExchangeSellerPublicationDebugCapture.recordPublishSucceeded(
                retrievalDocumentsPublished: !retrievalDocuments.isEmpty
            )
#endif

            await ExchangeSellerSurfacePublishInFlight.guardBox.release(profileID: profile.id)
            #if DEBUG
            GuardianCrownDebugLog.log(
                "PublishResult",
                "nodeID=\(nodeID) profileID=\(profile.id) success=true " +
                "remoteProfileID=\(publishResponse.remoteProfileID)"
            )
            #endif
            return nextState
        } catch {
#if DEBUG
            ExchangeSellerPublicationDebugCapture.recordPublishFailed(reason: String(describing: error))
            GuardianCrownDebugLog.log(
                "PublishResult",
                "nodeID=\(nodeID) profileID=\(profile.id) success=false " +
                "error=\(error.localizedDescription)"
            )
#endif
            let failedState = startedState.markingPublishFailed(
                summary: String(describing: error),
                at: now
            )
            try await store.savePublicationState(
                failedState,
                forPublicProfileID: profile.id
            )
            await ExchangeSellerSurfacePublishInFlight.guardBox.release(profileID: profile.id)
            throw error
        }
    }

    public func unpublishSellerSurface(
        ownerNodeID: String,
        now: Date = Date()
    ) async throws -> ExchangePublicationState {
        let nodeID = ownerNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nodeID.isEmpty else {
            throw ExchangeStoreError.storageFailure(reason: "Owner node ID is missing.")
        }

        let profile = try await requireOwnerPublicProfile(ownerNodeID: nodeID)
        let existingState = try await store.fetchPublicationState(
            forPublicProfileID: profile.id
        ) ?? publicationService.makeDefaultPublicationState(
            publicProfileID: profile.id,
            now: now
        )

        let pending = existingState.markingPendingUnpublish(at: now)
        try await store.savePublicationState(
            pending,
            forPublicProfileID: profile.id
        )

        do {
            _ = try await directoryClient.unpublishSellerSurface(
                nodeID: nodeID,
                publicProfileID: profile.id
            )

            let paused = pending.markingPaused(at: now)
            try await store.savePublicationState(
                paused,
                forPublicProfileID: profile.id
            )

            return paused
        } catch {
            let failed = pending.markingPublishFailed(
                summary: String(describing: error),
                at: now
            )
            try await store.savePublicationState(
                failed,
                forPublicProfileID: profile.id
            )
            throw error
        }
    }

    public func reconcileSellerSurfacePublication(
        ownerNodeID: String,
        ownerDisplayName: String?,
        now: Date = Date()
    ) async throws -> ExchangePublicationState? {
        let nodeID = ownerNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nodeID.isEmpty else { return nil }

        let profiles = try await store.listPublicProfiles(
            filter: .init(
                nodeID: nodeID,
                limit: 1
            )
        )

        guard let profile = profiles.first else { return nil }

        let offers = try await store.listOffers(
            filter: .init(
                publicProfileID: profile.id,
                limit: 500
            )
        )

        let state = try await store.fetchPublicationState(
            forPublicProfileID: profile.id
        ) ?? publicationService.makeDefaultPublicationState(
            publicProfileID: profile.id,
            now: now
        )

        let issues = sellerSurfaceService.validateSurface(
            publicProfile: profile,
            offers: offers
        )

        let readiness = publicationService.evaluateReadiness(
            publicProfile: profile,
            offers: offers,
            publicationState: state,
            validationIssues: issues
        )

        guard readiness.isReadyToPublish else {
            return state
        }

        if state.needsPublicationAttempt {
            let candidatePayload = sellerSurfaceService.buildPublishedPayload(
                ownerNodeID: nodeID,
                ownerDisplayName: ownerDisplayName,
                publicProfile: profile,
                offers: offers,
                publicationState: state,
                now: now
            )

            if await shouldSkipReconcilePublish(
                profileID: profile.id,
                fingerprint: candidatePayload.fingerprint,
                state: state,
                now: now
            ) {
                print(
                    "[ExchangeSellerPublicationCoordinator] publish skipped recent unchanged fingerprint"
                )
                await ExchangeSellerSurfaceReconcileDebounce.guardBox.recordSkip(
                    profileID: profile.id,
                    now: now
                )
                return state
            }

            return try await publishSellerSurface(
                ownerNodeID: nodeID,
                ownerDisplayName: ownerDisplayName,
                publicSupporterPresentation: profile.publicSupporterPresentation,
                now: now
            )
        }

        return state
    }
}

private extension ExchangeSellerPublicationCoordinator {
    func shouldSkipReconcilePublish(
        profileID: String,
        fingerprint: String?,
        state: ExchangePublicationState,
        now: Date
    ) async -> Bool {
        guard let fingerprint,
              let lastPublished = state.lastPublishedFingerprint,
              fingerprint == lastPublished else {
            return false
        }

        let debounce = ExchangeSellerSurfaceReconcileDebounceGuard.debounceInterval

        if state.status == .pendingPublish {
            return true
        }

        if let lastSuccess = state.lastSuccessAt,
           now.timeIntervalSince(lastSuccess) < debounce {
            return true
        }

        if let lastAttempt = state.lastAttemptAt,
           now.timeIntervalSince(lastAttempt) < debounce {
            return true
        }

        return await ExchangeSellerSurfaceReconcileDebounce.guardBox.shouldSkipRecent(
            profileID: profileID,
            now: now
        )
    }

    func applyIndexedProjection(
        from indexedSurface: ExchangeIndexedProviderSurface,
        to payload: inout ExchangePublishedSellerSurfacePayload
    ) {
        payload.indexedSurfaceVersion = indexedSurface.schemaVersion
        payload.indexedProviderSurface = makeProviderProjection(from: indexedSurface)
        let outwardOfferIDs = Set(payload.offers.map(\.id))
        let projectedOffers = indexedSurface.offers
            .filter {
                $0.visibility.lowercased() != ExchangeOffer.Visibility.hidden.rawValue.lowercased()
                    && $0.status.lowercased() == ExchangeOffer.Status.active.rawValue.lowercased()
                    && outwardOfferIDs.contains($0.offerID)
            }
            .map(makeOfferProjection(from:))
        payload.indexedOffers = projectedOffers.isEmpty ? nil : projectedOffers
    }

    func makeProviderProjection(
        from surface: ExchangeIndexedProviderSurface
    ) -> ExchangePublishedSellerSurfacePayload.IndexedProviderSurfaceProjection {
        .init(
            schemaVersion: surface.schemaVersion,
            semanticConcepts: cappedPhrases(surface.semanticConcepts, maxCount: 24, maxLength: 120),
            broadRecallTokens: cappedAtomic(surface.broadRecallTokens, maxCount: 48),
            hardConstraints: cappedPhrases(surface.hardConstraints, maxCount: 24, maxLength: 140),
            softPreferences: cappedPhrases(surface.softPreferences, maxCount: 24, maxLength: 140),
            commercialConstraints: surface.commercialConstraints
                .map { .init(text: $0.text, isHard: $0.isHard) }
                .filter { !$0.text.isEmpty }
                .prefix(16)
                .map { $0 },
            timeAvailabilityConstraints: surface.timeAvailabilityConstraints
                .map { .init(text: $0.text, isHard: $0.isHard) }
                .filter { !$0.text.isEmpty }
                .prefix(16)
                .map { $0 },
            sourceTextBlocks: cappedPhrases(surface.sourceTextBlocks, maxCount: 12, maxLength: 280),
            regions: .init(
                regionTags: cappedAtomic(surface.regions.regionTags, maxCount: 24),
                canonicalRegionIDs: cappedAtomic(surface.regions.canonicalRegionIDs, maxCount: 32),
                parentRegionIDs: cappedAtomic(surface.regions.parentRegionIDs, maxCount: 32),
                regionAliases: cappedAtomic(surface.regions.regionAliases, maxCount: 32),
                serviceAreaNotes: cappedPhrases(surface.regions.serviceAreaNotes, maxCount: 8, maxLength: 140)
            ),
            reachability: .init(
                accessMode: surface.reachability.accessMode,
                acceptingInbound: surface.reachability.acceptingInbound,
                disclosureCeiling: surface.reachability.disclosureCeiling,
                routeableOnly: surface.reachability.routeableOnly,
                intentCategoryPolicy: surface.reachability.intentCategoryPolicy
            ),
            updatedAt: surface.updatedAt
        )
    }

    func makeOfferProjection(
        from offer: ExchangeIndexedOfferSurface
    ) -> ExchangePublishedSellerSurfacePayload.IndexedOfferSurfaceProjection {
        .init(
            offerID: offer.offerID,
            schemaVersion: offer.schemaVersion,
            semanticConcepts: cappedPhrases(offer.semanticConcepts, maxCount: 20, maxLength: 120),
            broadRecallTokens: cappedAtomic(offer.broadRecallTokens, maxCount: 32),
            hardConstraints: cappedPhrases(offer.hardConstraints, maxCount: 16, maxLength: 140),
            softPreferences: cappedPhrases(offer.softPreferences, maxCount: 16, maxLength: 140),
            commercialConstraints: offer.commercialConstraints
                .map { .init(text: $0.text, isHard: $0.isHard) }
                .filter { !$0.text.isEmpty }
                .prefix(12)
                .map { $0 },
            timeAvailabilityConstraints: offer.timeAvailabilityConstraints
                .map { .init(text: $0.text, isHard: $0.isHard) }
                .filter { !$0.text.isEmpty }
                .prefix(12)
                .map { $0 },
            fulfillment: .init(
                pricingMode: offer.fulfillment.pricingMode,
                commitmentMode: offer.fulfillment.commitmentMode,
                remoteFriendly: offer.fulfillment.remoteFriendly,
                leadTimeNote: offer.fulfillment.leadTimeNote,
                capacityNote: offer.fulfillment.capacityNote,
                serviceAreaNote: offer.fulfillment.serviceAreaNote
            ),
            sourceTextBlocks: cappedPhrases(offer.sourceTextBlocks, maxCount: 8, maxLength: 260),
            visibility: offer.visibility,
            status: offer.status,
            updatedAt: offer.updatedAt
        )
    }

    func cappedPhrases(
        _ values: [String],
        maxCount: Int,
        maxLength: Int
    ) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(maxLength)) }
            .reduce(into: [String]()) { acc, item in
                guard !acc.contains(item) else { return }
                acc.append(item)
            }
            .prefix(maxCount)
            .map { $0 }
    }

    func cappedAtomic(
        _ values: [String],
        maxCount: Int
    ) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { isAtomicToken($0) }
            .reduce(into: [String]()) { acc, item in
                guard !acc.contains(item) else { return }
                acc.append(item)
            }
            .prefix(maxCount)
            .map { $0 }
    }

    func isAtomicToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= 64 else { return false }
        if token.contains(",") || token.contains(".") || token.contains(";") || token.contains("\n") {
            return false
        }
        let wordCount = token.split(whereSeparator: \.isWhitespace).count
        return wordCount > 0 && wordCount <= 6
    }

    func outwardFacingOffers(_ offers: [ExchangeOffer]) -> [ExchangeOffer] {
        offers
            .filter { $0.status == .active && $0.visibility != .hidden }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.title < rhs.title
            }
    }

    func requireOwnerPublicProfile(
        ownerNodeID: String
    ) async throws -> ExchangePublicNodeProfile {
        let profiles = try await store.listPublicProfiles(
            filter: .init(
                nodeID: ownerNodeID,
                limit: 1
            )
        )

        guard let profile = profiles.first else {
            throw ExchangeStoreError.publicProfileNotFound("profile-\(ownerNodeID)")
        }

        return profile
    }

    func enrichEmbeddingsIfNeeded(
        _ documents: [ExchangeRetrievalDocument]
    ) -> [ExchangeRetrievalDocument] {
        documents.map { document in
            guard !document.hasEmbedding else { return document }
            return document.updatingEmbedding(buildEmbedding(for: document))
        }
    }

    func buildEmbedding(
        for document: ExchangeRetrievalDocument
    ) -> [Float]? {
        let text = bestEmbeddingText(for: document)
        guard !text.isEmpty else { return nil }

        guard let embedding = embeddingProvider.embed(text), !embedding.isEmpty else {
            return nil
        }

        return embedding
    }

    func bestEmbeddingText(
        for document: ExchangeRetrievalDocument
    ) -> String {
        document.retrievalEmbeddingText
    }

    func logRetrievalSlicePublishDocuments(_ documents: [ExchangeRetrievalDocument]) {
        for document in documents {
            let text = bestEmbeddingText(for: document)
            let dim = document.embeddingDimension
            let kinds = retrievalSliceBlockKinds(document.surfaceType)
            print(
                "[RetrievalSlice][publish] docID=\(document.id) surfaceType=\(document.surfaceType.rawValue) textChars=\(text.count) embeddingDim=\(dim) blockKinds=\(kinds)"
            )
            switch document.surfaceType {
            case .publicProfileCapability, .publicProfileSeeking, .publicProfileAffinity, .offer:
                let preview = text.count > 200 ? String(text.prefix(200)) + "…" : text
                print("[RetrievalSlice][publish] surfaceType=\(document.surfaceType.rawValue) preview=\(preview)")
            default:
                break
            }
        }
    }

    func retrievalSliceBlockKinds(_ surface: ExchangeRetrievalDocument.SurfaceType) -> String {
        switch surface {
        case .publicProfileCapability:
            return "identity,capability,commercial"
        case .publicProfileSeeking:
            return "seeking"
        case .publicProfileAffinity:
            return "affinity"
        case .offer:
            return "offer"
        case .publicProfile:
            return "legacyPublicProfile"
        case .unknown(let wire):
            return "unknown:\(wire)"
        }
    }

    func normalizeWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
