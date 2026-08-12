import Foundation

#if DEBUG

public enum MultilingualSecretaryMatrixCatalogBuilder {
    public static func buildCatalog(for fixture: MultilingualSecretaryMatrixFixture) -> [ExchangeDirectoryMatch] {
        [
            buildExactMatch(for: fixture),
            buildNoisyMatch(for: fixture)
        ]
    }

    public static func buildRawProviderEntities(for fixture: MultilingualSecretaryMatrixFixture) -> RawProviderEntities {
        let profileID = "profile-\(fixture.expectedSelectedNodeID)"
        let serviceAreas = fixture.expectedServiceAreas.compactMap { ExchangeDeclaredServiceArea.fromSellerChip($0) }

        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: fixture.expectedSelectedNodeID,
            displayName: displayName(from: fixture.providerProfileText),
            headline: fixture.providerProfileText,
            summary: fixture.providerProfileText,
            offers: [fixture.providerOfferText],
            activityTags: [fixture.expectedObjectType],
            regionTags: fixture.expectedServiceAreas.map { $0.lowercased() },
            semantic: .init(domains: [fixture.expectedObjectType], notes: fixture.providerProfileText),
            createdAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate,
            updatedAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate
        )

        let offer = ExchangeOffer(
            id: fixture.expectedSelectedOfferID,
            nodeID: fixture.expectedSelectedNodeID,
            publicProfileID: profileID,
            title: fixture.providerOfferText,
            summary: fixture.providerOfferText,
            category: fixture.expectedObjectType,
            tags: [fixture.expectedNeed],
            serviceAreas: serviceAreas,
            semantic: .init(serviceKinds: [fixture.expectedNeed], notes: fixture.providerOfferText),
            status: .active,
            visibility: .publicDiscoverable,
            createdAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate,
            updatedAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate,
            commercialFacts: .init(
                priceDisplay: "Budget-friendly",
                serviceAreaNote: fixture.expectedServiceAreas.joined(separator: " and "),
                availabilityNote: fixture.expectedTimeText
            )
        )

        return RawProviderEntities(profile: profile, offer: offer)
    }

    public struct RawProviderEntities: Sendable, Hashable {
        public var profile: ExchangePublicNodeProfile
        public var offer: ExchangeOffer

        public init(profile: ExchangePublicNodeProfile, offer: ExchangeOffer) {
            self.profile = profile
            self.offer = offer
        }
    }

    public static func buildExactMatch(for fixture: MultilingualSecretaryMatrixFixture) -> ExchangeDirectoryMatch {
        let entities = buildRawProviderEntities(for: fixture)
        return makeMatch(
            nodeID: fixture.expectedSelectedNodeID,
            profile: entities.profile,
            offers: [entities.offer],
            englishCarrier: fixture.mockedProviderCanonicalEnglishRetrievalText,
            semanticConcepts: fixture.expectedEnglishCarrierTokens,
            objectIdentityTerms: [fixture.expectedObjectType],
            profileAxis: fixture.retrievalAxis,
            offerAxis: fixture.retrievalAxis
        )
    }

    public static func buildNoisyMatch(for fixture: MultilingualSecretaryMatrixFixture) -> ExchangeDirectoryMatch {
        let noisyText = MultilingualSecretaryMatrixFixtures.noisyText(for: fixture.vertical)
        let nodeID = fixture.forbiddenNoisyNodeID
        let profileID = "profile-\(nodeID)"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "General home services",
            headline: noisyText,
            summary: noisyText,
            offers: [noisyText],
            activityTags: ["home service", "general"],
            regionTags: ["gta", "toronto"],
            semantic: .init(domains: ["home service"], notes: noisyText),
            createdAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate,
            updatedAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate
        )
        let offer = ExchangeOffer(
            id: "offer-\(nodeID)",
            nodeID: nodeID,
            publicProfileID: profileID,
            title: noisyText,
            summary: noisyText,
            category: "home service",
            tags: ["general"],
            semantic: .init(serviceKinds: ["general home service"], notes: noisyText),
            status: .active,
            visibility: .publicDiscoverable,
            createdAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate,
            updatedAt: ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate
        )
        return makeMatch(
            nodeID: nodeID,
            profile: profile,
            offers: [offer],
            englishCarrier: noisyText,
            semanticConcepts: ["home service", "general"],
            objectIdentityTerms: ["home service"],
            profileAxis: MultilingualSecretaryMatrixAxisEmbeddingProvider.noisyAxis,
            offerAxis: MultilingualSecretaryMatrixAxisEmbeddingProvider.noisyAxis
        )
    }

    private static func makeMatch(
        nodeID: String,
        profile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer],
        englishCarrier: String,
        semanticConcepts: [String],
        objectIdentityTerms: [String],
        profileAxis: Int,
        offerAxis: Int
    ) -> ExchangeDirectoryMatch {
        var surface = ExchangeIndexedProviderSurfaceBuilder().build(profile: profile, offers: offers)
        if !surface.offers.isEmpty {
            surface.offers[0].canonicalEnglishRetrievalText = englishCarrier
            surface.offers[0].semanticConcepts = semanticConcepts
            surface.offers[0].objectIdentityTerms = objectIdentityTerms
        }

        let rawDocs = ExchangeRetrievalDocumentBuilder().build(
            from: surface,
            counterpartyID: nodeID,
            sourceKind: .remote
        )
        let embeddedDocs = embedDocuments(rawDocs, profileAxis: profileAxis, offerAxis: offerAxis)
        let candidateOfferIDs = embeddedDocs.compactMap { doc -> String? in
            guard doc.docKind == .offerObject, let offerID = doc.offerID else { return nil }
            return offerID
        }
        let hits = embeddedDocs.map { doc in
            ExchangeDirectoryRetrievalHit(
                retrievalDocID: doc.id,
                nodeID: nodeID,
                docKind: doc.docKind,
                sourceField: doc.sourceField,
                surfaceType: doc.surfaceType.rawValue,
                entityType: doc.entityType.rawValue,
                offerID: doc.offerID,
                publicProfileID: doc.publicProfileID,
                title: doc.title,
                lexicalScore: 1.0,
                vectorSimilarity: 0.5,
                retrievalScore: 1.0,
                embedding: doc.embedding
            )
        }
        let counterparty = ExchangeCounterparty(
            id: nodeID,
            kind: .secretaryNode,
            displayName: profile.displayName ?? nodeID,
            source: .relayNetwork,
            identity: .init(nodeID: nodeID, publicKeyID: nil, verification: .unverified),
            publicProfile: profile,
            tags: profile.activityTags,
            semantic: .empty,
            contactRoutes: [],
            status: .active
        )
        return ExchangeDirectoryMatch(
            id: nodeID,
            counterparty: counterparty,
            publicProfile: profile,
            offers: offers,
            retrievalDocuments: embeddedDocs,
            reachability: .init(
                isDiscoverable: true,
                isRouteableInPrinciple: true,
                allowsDirectContactInPrinciple: true,
                requiresIntroductionInPrinciple: false,
                accessMode: .direct,
                disclosureCeiling: .balanced,
                hasRouteHint: true
            ),
            retrievalHits: hits,
            candidateOfferIDsFromDocs: Array(Set(candidateOfferIDs)).sorted()
        )
    }

    private static func embedDocuments(
        _ documents: [ExchangeRetrievalDocument],
        profileAxis: Int,
        offerAxis: Int
    ) -> [ExchangeRetrievalDocument] {
        let fixtureDate = ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate
        return documents.map { doc in
            let axis = doc.docKind == .offerObject ? offerAxis : profileAxis
            return doc.withMatrixRetrievalEmbedding(
                MultilingualSecretaryMatrixAxisEmbeddingProvider.vector(for: axis),
                updatedAt: fixtureDate
            )
        }
    }

    public static func displayName(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 40 { return trimmed }
        return String(trimmed.prefix(40))
    }
}

private extension ExchangeRetrievalDocument {
    func withMatrixRetrievalEmbedding(_ embedding: [Float], updatedAt: Date) -> ExchangeRetrievalDocument {
        ExchangeRetrievalDocument(
            id: id,
            counterpartyID: counterpartyID,
            nodeID: nodeID,
            publicProfileID: publicProfileID,
            offerID: offerID,
            entityType: entityType,
            surfaceType: surfaceType,
            sourceKind: sourceKind,
            docKind: docKind,
            sourceField: sourceField,
            visibility: visibility,
            availability: availability,
            accessMode: accessMode,
            acceptingInbound: acceptingInbound,
            routeableOnly: routeableOnly,
            title: title,
            summary: summary,
            category: category,
            tags: tags,
            regionTags: regionTags,
            canonicalRegionIDs: canonicalRegionIDs,
            regionAliases: regionAliases,
            parentRegionIDs: parentRegionIDs,
            serviceAreas: serviceAreas,
            primaryText: primaryText,
            secondaryText: secondaryText,
            lexicalText: lexicalText,
            semanticText: semanticText,
            canonicalEnglishRetrievalText: canonicalEnglishRetrievalText,
            providerTerms: providerTerms,
            capabilityTerms: capabilityTerms,
            affinityTerms: affinityTerms,
            filterTokens: filterTokens,
            embedding: embedding,
            updatedAt: updatedAt
        )
    }
}

#endif
