import Foundation

#if DEBUG

public struct MultilingualRetrievalE2EProviderBuildTimings: Sendable, Hashable, Codable {
    public var indexedSurfaceMs: Int
    public var enricherMs: Int
    public var retrievalDocsMs: Int
    public var embedMs: Int
    public var totalMs: Int

    public init(
        indexedSurfaceMs: Int,
        enricherMs: Int,
        retrievalDocsMs: Int,
        embedMs: Int,
        totalMs: Int
    ) {
        self.indexedSurfaceMs = indexedSurfaceMs
        self.enricherMs = enricherMs
        self.retrievalDocsMs = retrievalDocsMs
        self.embedMs = embedMs
        self.totalMs = totalMs
    }
}

public struct MultilingualRetrievalE2EFullFacadePublicationSnapshot: Sendable, Hashable, Codable {
    public var fullFacadeProfileSaveAttempted: Bool
    public var fullFacadeProfileSaveSucceeded: Bool
    public var fullFacadeOfferSaveAttempted: Bool
    public var fullFacadeOfferSaveSucceeded: Bool
    public var fullFacadePublishAttempted: Bool
    public var fullFacadePublishSucceeded: Bool
    public var publishRetrievalDocumentsAttempted: Bool
    public var publishRetrievalDocumentsSucceeded: Bool
    public var federationRoundTripAttempted: Bool
    public var federationRoundTripSucceeded: Bool
    public var federationRoundTripFailureReason: String?
    public var retrievalDocumentsPublishedCount: Int
    public var retrievalDocumentsRecoveredCount: Int
    public var canonicalEnglishCarrierBeforePublish: String?
    public var canonicalEnglishCarrierAfterPublish: String?
    public var offerObjectCarrierAfterPublish: String?
    public var serviceAreasAfterPublish: [String]
    public var originalChinesePreservedAfterPublish: Bool
    public var usesOverlayFallbackForRoofer: Bool

    public init(
        fullFacadeProfileSaveAttempted: Bool,
        fullFacadeProfileSaveSucceeded: Bool,
        fullFacadeOfferSaveAttempted: Bool,
        fullFacadeOfferSaveSucceeded: Bool,
        fullFacadePublishAttempted: Bool,
        fullFacadePublishSucceeded: Bool,
        publishRetrievalDocumentsAttempted: Bool,
        publishRetrievalDocumentsSucceeded: Bool,
        federationRoundTripAttempted: Bool,
        federationRoundTripSucceeded: Bool,
        federationRoundTripFailureReason: String?,
        retrievalDocumentsPublishedCount: Int,
        retrievalDocumentsRecoveredCount: Int,
        canonicalEnglishCarrierBeforePublish: String?,
        canonicalEnglishCarrierAfterPublish: String?,
        offerObjectCarrierAfterPublish: String?,
        serviceAreasAfterPublish: [String],
        originalChinesePreservedAfterPublish: Bool,
        usesOverlayFallbackForRoofer: Bool
    ) {
        self.fullFacadeProfileSaveAttempted = fullFacadeProfileSaveAttempted
        self.fullFacadeProfileSaveSucceeded = fullFacadeProfileSaveSucceeded
        self.fullFacadeOfferSaveAttempted = fullFacadeOfferSaveAttempted
        self.fullFacadeOfferSaveSucceeded = fullFacadeOfferSaveSucceeded
        self.fullFacadePublishAttempted = fullFacadePublishAttempted
        self.fullFacadePublishSucceeded = fullFacadePublishSucceeded
        self.publishRetrievalDocumentsAttempted = publishRetrievalDocumentsAttempted
        self.publishRetrievalDocumentsSucceeded = publishRetrievalDocumentsSucceeded
        self.federationRoundTripAttempted = federationRoundTripAttempted
        self.federationRoundTripSucceeded = federationRoundTripSucceeded
        self.federationRoundTripFailureReason = federationRoundTripFailureReason
        self.retrievalDocumentsPublishedCount = retrievalDocumentsPublishedCount
        self.retrievalDocumentsRecoveredCount = retrievalDocumentsRecoveredCount
        self.canonicalEnglishCarrierBeforePublish = canonicalEnglishCarrierBeforePublish
        self.canonicalEnglishCarrierAfterPublish = canonicalEnglishCarrierAfterPublish
        self.offerObjectCarrierAfterPublish = offerObjectCarrierAfterPublish
        self.serviceAreasAfterPublish = serviceAreasAfterPublish
        self.originalChinesePreservedAfterPublish = originalChinesePreservedAfterPublish
        self.usesOverlayFallbackForRoofer = usesOverlayFallbackForRoofer
    }
}

public struct MultilingualRetrievalE2EProviderIndexingSnapshot: Sendable, Hashable, Codable {
    public var runMode: String
    public var providerIndexingSource: String
    public var providerEnricherAttempted: Bool
    public var providerEnricherSucceeded: Bool
    public var providerEnricherFailureReason: String?
    public var providerCanonicalEnglishRetrievalText: String?
    public var providerCanonicalEnglishRetrievalTextTokenCheck: [String: Bool]
    public var providerOriginalLanguageTextPreserved: Bool
    public var providerUnsafeFallbackTriggered: Bool
    public var providerBuildTimings: MultilingualRetrievalE2EProviderBuildTimings?
    public var fullFacadePublication: MultilingualRetrievalE2EFullFacadePublicationSnapshot?

    public init(
        runMode: String,
        providerIndexingSource: String,
        providerEnricherAttempted: Bool,
        providerEnricherSucceeded: Bool,
        providerEnricherFailureReason: String?,
        providerCanonicalEnglishRetrievalText: String?,
        providerCanonicalEnglishRetrievalTextTokenCheck: [String: Bool],
        providerOriginalLanguageTextPreserved: Bool,
        providerUnsafeFallbackTriggered: Bool,
        providerBuildTimings: MultilingualRetrievalE2EProviderBuildTimings?,
        fullFacadePublication: MultilingualRetrievalE2EFullFacadePublicationSnapshot? = nil
    ) {
        self.runMode = runMode
        self.providerIndexingSource = providerIndexingSource
        self.providerEnricherAttempted = providerEnricherAttempted
        self.providerEnricherSucceeded = providerEnricherSucceeded
        self.providerEnricherFailureReason = providerEnricherFailureReason
        self.providerCanonicalEnglishRetrievalText = providerCanonicalEnglishRetrievalText
        self.providerCanonicalEnglishRetrievalTextTokenCheck = providerCanonicalEnglishRetrievalTextTokenCheck
        self.providerOriginalLanguageTextPreserved = providerOriginalLanguageTextPreserved
        self.providerUnsafeFallbackTriggered = providerUnsafeFallbackTriggered
        self.providerBuildTimings = providerBuildTimings
        self.fullFacadePublication = fullFacadePublication
    }
}

public enum MultilingualRetrievalE2EProviderIndexingAudit {
    public static func injectedBaselineSnapshot(
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
        buildTimings: MultilingualRetrievalE2EProviderBuildTimings?,
        expectedEnglishTokens: [String]
    ) -> MultilingualRetrievalE2EProviderIndexingSnapshot {
        let carrier = projection?.canonicalEnglishRetrievalText
        return MultilingualRetrievalE2EProviderIndexingSnapshot(
            runMode: MultilingualRetrievalE2EMode.injectedCarrierFixture.rawValue,
            providerIndexingSource: "injectedCarrierFixture",
            providerEnricherAttempted: false,
            providerEnricherSucceeded: false,
            providerEnricherFailureReason: nil,
            providerCanonicalEnglishRetrievalText: carrier,
            providerCanonicalEnglishRetrievalTextTokenCheck: tokenCheck(
                carrier: carrier,
                expectedTokens: expectedEnglishTokens
            ),
            providerOriginalLanguageTextPreserved: projection?.preservedChineseInSourceBlocks ?? false,
            providerUnsafeFallbackTriggered: false,
            providerBuildTimings: buildTimings
        )
    }

    public static func liveEnricherSnapshot(
        enrichedSurface: ExchangeIndexedProviderSurface,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
        diagnostics: ProviderSurfaceEnrichmentDiagnostics?,
        buildTimings: MultilingualRetrievalE2EProviderBuildTimings?,
        expectedEnglishTokens: [String],
        primaryOfferID: String? = nil
    ) -> MultilingualRetrievalE2EProviderIndexingSnapshot {
        let resolvedOfferID = primaryOfferID ?? MultilingualRetrievalE2EFixtureBuilder.OfferID.roofer
        let carrier = projection?.canonicalEnglishRetrievalText
            ?? enrichedSurface.offers.first(where: { $0.offerID == resolvedOfferID })?
            .canonicalEnglishRetrievalText
        let attempted = diagnostics?.attemptedLLM ?? true
        let enricherSucceeded = enricherProducedEnglishCarrier(
            diagnostics: diagnostics,
            carrier: carrier,
            projection: projection
        )
        let unsafeFallback = unsafeFallbackTriggered(
            surface: enrichedSurface,
            diagnostics: diagnostics,
            carrier: carrier
        )

        return MultilingualRetrievalE2EProviderIndexingSnapshot(
            runMode: MultilingualRetrievalE2EMode.livePublishEnricher.rawValue,
            providerIndexingSource: "liveEnricherCorePath",
            providerEnricherAttempted: attempted,
            providerEnricherSucceeded: enricherSucceeded,
            providerEnricherFailureReason: diagnostics?.failureReason?.rawValue,
            providerCanonicalEnglishRetrievalText: carrier,
            providerCanonicalEnglishRetrievalTextTokenCheck: tokenCheck(
                carrier: carrier,
                expectedTokens: expectedEnglishTokens
            ),
            providerOriginalLanguageTextPreserved: projection?.preservedChineseInSourceBlocks
                ?? surfacePreservesOriginalLanguage(enrichedSurface),
            providerUnsafeFallbackTriggered: unsafeFallback,
            providerBuildTimings: buildTimings
        )
    }

    public static func fullFacadePublishSnapshot(
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?,
        diagnostics: ProviderSurfaceEnrichmentDiagnostics?,
        buildTimings: MultilingualRetrievalE2EProviderBuildTimings?,
        expectedEnglishTokens: [String],
        publication: MultilingualRetrievalE2EFullFacadePublicationSnapshot,
        enrichedSurface: ExchangeIndexedProviderSurface?,
        usesOverlay: Bool
    ) -> MultilingualRetrievalE2EProviderIndexingSnapshot {
        let carrier = projection?.canonicalEnglishRetrievalText
            ?? publication.canonicalEnglishCarrierAfterPublish
        let attempted = diagnostics?.attemptedLLM ?? publication.fullFacadePublishAttempted
        let enricherSucceeded = enricherProducedEnglishCarrier(
            diagnostics: diagnostics,
            carrier: carrier,
            projection: projection
        )
        let unsafeFallback: Bool = {
            guard let enrichedSurface else { return false }
            return unsafeFallbackTriggered(
                surface: enrichedSurface,
                diagnostics: diagnostics,
                carrier: carrier
            )
        }()
        let indexingSource = usesOverlay ? "fullFacadePublishPathWithOverlay" : "fullFacadePublishPath"

        return MultilingualRetrievalE2EProviderIndexingSnapshot(
            runMode: MultilingualRetrievalE2EMode.fullFacadePublishPath.rawValue,
            providerIndexingSource: indexingSource,
            providerEnricherAttempted: attempted,
            providerEnricherSucceeded: enricherSucceeded,
            providerEnricherFailureReason: diagnostics?.failureReason?.rawValue
                ?? publication.federationRoundTripFailureReason,
            providerCanonicalEnglishRetrievalText: carrier,
            providerCanonicalEnglishRetrievalTextTokenCheck: tokenCheck(
                carrier: carrier,
                expectedTokens: expectedEnglishTokens
            ),
            providerOriginalLanguageTextPreserved: projection?.preservedChineseInSourceBlocks
                ?? publication.originalChinesePreservedAfterPublish,
            providerUnsafeFallbackTriggered: unsafeFallback,
            providerBuildTimings: buildTimings,
            fullFacadePublication: publication
        )
    }

    public static func tokenCheck(carrier: String?, expectedTokens: [String]) -> [String: Bool] {
        let lowered = carrier?.lowercased() ?? ""
        var out: [String: Bool] = [:]
        for token in expectedTokens {
            out[token] = lowered.contains(token.lowercased())
        }
        return out
    }

    public static func enricherProducedEnglishCarrier(
        diagnostics: ProviderSurfaceEnrichmentDiagnostics?,
        carrier: String?,
        projection: MultilingualRetrievalE2EFixtureBuilder.ProviderProjectionAudit?
    ) -> Bool {
        let hasCarrier = !(carrier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard hasCarrier else { return false }
        guard let diagnostics else { return hasCarrier }
        switch diagnostics.source {
        case .llmEnriched, .llmRepairedJSON, .deterministicStructuredEnglish:
            return true
        case .deterministicOnly, .fallbackOriginal:
            return false
        }
    }

    public static func unsafeFallbackTriggered(
        surface: ExchangeIndexedProviderSurface,
        diagnostics: ProviderSurfaceEnrichmentDiagnostics?,
        carrier: String?
    ) -> Bool {
        guard surfaceAppearsNonEnglish(surface) else { return false }
        let hasCarrier = !(carrier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if hasCarrier { return false }
        guard let diagnostics else { return true }
        switch diagnostics.source {
        case .fallbackOriginal, .deterministicOnly:
            return true
        case .deterministicStructuredEnglish:
            return false
        case .llmEnriched, .llmRepairedJSON:
            return !hasCarrier
        }
    }

    public static func surfaceAppearsNonEnglish(_ surface: ExchangeIndexedProviderSurface) -> Bool {
        let samples = [
            surface.displayName,
            surface.headline,
            surface.summary
        ].compactMap { $0 } + surface.sourceTextBlocks + surface.offers.flatMap(\.sourceTextBlocks)
        return samples.contains(where: ExchangeRetrievalEnglishProjection.containsSignificantNonEnglish)
    }

    public static func surfacePreservesOriginalLanguage(_ surface: ExchangeIndexedProviderSurface) -> Bool {
        let joined = (
            [surface.displayName, surface.headline, surface.summary].compactMap { $0 }
            + surface.sourceTextBlocks
            + surface.offers.flatMap(\.sourceTextBlocks)
        ).joined(separator: " ")
        return MultilingualRetrievalE2EEvaluation.containsCJK(joined)
    }
}

#endif
