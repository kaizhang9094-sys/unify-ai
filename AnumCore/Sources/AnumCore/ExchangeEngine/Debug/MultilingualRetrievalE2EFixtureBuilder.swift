import Foundation

#if DEBUG

/// Builds Chinese provider fixtures for multilingual retrieval E2E smoke.
///
/// Uses the real indexed-surface + retrieval-document builder path. English retrieval carriers are
/// injected on the indexed offer surface to mirror enricher output in local/test mode.
public enum MultilingualRetrievalE2EFixtureBuilder {
    public enum NodeID {
        public static let roofer = "node-multilingual-roofer-zh"
        public static let noisyHome = "node-multilingual-noisy-home-zh"
    }

    public enum OfferID {
        public static let roofer = "offer-multilingual-roofer-zh"
        public static let noisyHome = "offer-multilingual-noisy-home-zh"
    }

    public static let rawProviderOfferText =
        "屋顶维修师傅，服务Aurora和Newmarket，提供免费上门估价，可预约明天下午。"
    public static let rawProviderProfileText = rawProviderOfferText
    public static let rawUserText =
        "帮我找一个明天下午2点能来Aurora估价、预算200以内的屋顶工"

    public static let rooferEnglishRetrievalCarrier =
        "roofer, roof repair, roof estimate, free on-site estimate, service area Aurora and Newmarket, available tomorrow afternoon"
    public static let noisyHomeEnglishRetrievalCarrier =
        "general home services, renovation, cleaning, plumbing, electrical, broad home maintenance, Greater Toronto Area"

    private static let fixtureDate = ExchangeRetrievalAccuracyFixtureBuilder.fixtureDate

    public struct ProviderProjectionAudit: Sendable, Hashable, Codable {
        public var nodeID: String
        public var offerID: String
        public var canonicalEnglishRetrievalText: String?
        public var offerDetailUsesEnglishOnlyRetrievalProjection: Bool
        public var offerObjectUsesEnglishOnlyRetrievalProjection: Bool
        public var serviceAreas: [String]
        public var offerObjectSearchableText: String?
        public var preservedChineseInSourceBlocks: Bool

        public init(
            nodeID: String,
            offerID: String,
            canonicalEnglishRetrievalText: String?,
            offerDetailUsesEnglishOnlyRetrievalProjection: Bool,
            offerObjectUsesEnglishOnlyRetrievalProjection: Bool,
            serviceAreas: [String],
            offerObjectSearchableText: String?,
            preservedChineseInSourceBlocks: Bool
        ) {
            self.nodeID = nodeID
            self.offerID = offerID
            self.canonicalEnglishRetrievalText = canonicalEnglishRetrievalText
            self.offerDetailUsesEnglishOnlyRetrievalProjection = offerDetailUsesEnglishOnlyRetrievalProjection
            self.offerObjectUsesEnglishOnlyRetrievalProjection = offerObjectUsesEnglishOnlyRetrievalProjection
            self.serviceAreas = serviceAreas
            self.offerObjectSearchableText = offerObjectSearchableText
            self.preservedChineseInSourceBlocks = preservedChineseInSourceBlocks
        }
    }

    public static func buildCatalog(includeAxisEmbeddings: Bool) -> [ExchangeDirectoryMatch] {
        [
            buildRooferMatch(includeAxisEmbeddings: includeAxisEmbeddings),
            buildNoisyHomeMatch(includeAxisEmbeddings: includeAxisEmbeddings)
        ]
    }

    public struct RawProviderEntities: Sendable, Hashable {
        public var profile: ExchangePublicNodeProfile
        public var offer: ExchangeOffer

        public init(profile: ExchangePublicNodeProfile, offer: ExchangeOffer) {
            self.profile = profile
            self.offer = offer
        }
    }

    public static func rawRooferEntities() -> RawProviderEntities {
        let nodeID = NodeID.roofer
        let profileID = "profile-multilingual-roofer-zh"
        let aurora = ExchangeDeclaredServiceArea.fromSellerChip("Aurora")!
        let newmarket = ExchangeDeclaredServiceArea.fromSellerChip("Newmarket")!

        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "屋顶维修师傅",
            headline: rawProviderProfileText,
            summary: rawProviderProfileText,
            offers: [rawProviderOfferText],
            activityTags: ["roofing", "estimate"],
            regionTags: ["aurora", "newmarket"],
            semantic: .init(domains: ["roofing"], notes: rawProviderProfileText),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )

        let offer = ExchangeOffer(
            id: OfferID.roofer,
            nodeID: nodeID,
            publicProfileID: profileID,
            title: rawProviderOfferText,
            summary: rawProviderOfferText,
            category: "roofing",
            tags: ["屋顶", "估价"],
            serviceAreas: [aurora, newmarket],
            semantic: .init(serviceKinds: ["roof repair"], notes: rawProviderOfferText),
            status: .active,
            visibility: .publicDiscoverable,
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            commercialFacts: .init(
                priceDisplay: "Free estimate",
                serviceAreaNote: "Aurora and Newmarket",
                availabilityNote: "available tomorrow afternoon"
            )
        )
        return RawProviderEntities(profile: profile, offer: offer)
    }

    public static func buildDeterministicNoisyHomeMatch(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let entities = rawNoisyHomeEntities()
        let surface = ExchangeIndexedProviderSurfaceBuilder().build(
            profile: entities.profile,
            offers: [entities.offer]
        )
        let rawDocs = ExchangeRetrievalDocumentBuilder().build(
            from: surface,
            counterpartyID: NodeID.noisyHome,
            sourceKind: .remote
        )
        return makeDirectoryMatch(
            nodeID: NodeID.noisyHome,
            profile: entities.profile,
            offers: [entities.offer],
            embeddedDocs: rawDocs,
            includeAxisEmbeddings: includeAxisEmbeddings,
            profileAxis: 7,
            offerAxes: [OfferID.noisyHome: 7]
        )
    }

    public static func makeDirectoryMatch(
        nodeID: String,
        profile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer],
        embeddedDocs: [ExchangeRetrievalDocument],
        includeAxisEmbeddings: Bool,
        profileAxis: Int,
        offerAxes: [String: Int]
    ) -> ExchangeDirectoryMatch {
        let docs: [ExchangeRetrievalDocument]
        if includeAxisEmbeddings {
            docs = embedDocuments(embeddedDocs, profileAxis: profileAxis, offerAxes: offerAxes)
        } else {
            docs = embeddedDocs
        }

        let candidateOfferIDs = docs.compactMap { doc -> String? in
            guard doc.docKind == .offerObject, let offerID = doc.offerID else { return nil }
            return offerID
        }
        let hits = docs.map { doc in
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
            retrievalDocuments: docs,
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

    private static func rawNoisyHomeEntities() -> RawProviderEntities {
        let nodeID = NodeID.noisyHome
        let profileID = "profile-multilingual-noisy-home-zh"
        let noisyText = "综合家政服务公司，提供装修、清洁、管道、电气等全屋服务，服务多伦多及GTA大部分地区。"

        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "综合家政服务",
            headline: noisyText,
            summary: noisyText,
            offers: [noisyText],
            activityTags: ["home service", "general"],
            regionTags: ["toronto", "gta"],
            semantic: .init(domains: ["home service"], notes: noisyText),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )

        let offer = ExchangeOffer(
            id: OfferID.noisyHome,
            nodeID: nodeID,
            publicProfileID: profileID,
            title: noisyText,
            summary: noisyText,
            category: "home service",
            tags: ["家政", "装修", "清洁"],
            semantic: .init(serviceKinds: ["general home service"], notes: noisyText),
            status: .active,
            visibility: .publicDiscoverable,
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        return RawProviderEntities(profile: profile, offer: offer)
    }

    public static func providerProjectionAudit(from matches: [ExchangeDirectoryMatch]) -> ProviderProjectionAudit? {
        guard let match = matches.first(where: { $0.id == NodeID.roofer }) else { return nil }
        let offerDocs = match.retrievalDocuments.filter { $0.offerID == OfferID.roofer }
        let detailDoc = offerDocs.first(where: { $0.docKind == .offerDetail })
        let objectDoc = offerDocs.first(where: { $0.docKind == .offerObject })
        let serviceAreas = detailDoc?.serviceAreas.map(\.displayName) ?? []
        let sourceChinese = match.offers.first?.summary?.contains("屋顶") == true
        return ProviderProjectionAudit(
            nodeID: NodeID.roofer,
            offerID: OfferID.roofer,
            canonicalEnglishRetrievalText: detailDoc?.canonicalEnglishRetrievalText,
            offerDetailUsesEnglishOnlyRetrievalProjection: detailDoc?.usesEnglishOnlyRetrievalProjection ?? false,
            offerObjectUsesEnglishOnlyRetrievalProjection: objectDoc?.usesEnglishOnlyRetrievalProjection ?? false,
            serviceAreas: serviceAreas,
            offerObjectSearchableText: objectDoc?.searchableText,
            preservedChineseInSourceBlocks: sourceChinese
        )
    }

    // MARK: - Builders

    private static func buildRooferMatch(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let entities = rawRooferEntities()
        return makeMatch(
            nodeID: NodeID.roofer,
            profile: entities.profile,
            offers: [entities.offer],
            englishCarrier: rooferEnglishRetrievalCarrier,
            semanticConcepts: ["roofer", "roof repair", "roof estimate", "free on-site estimate"],
            objectIdentityTerms: ["roofer", "roof repair"],
            profileAxis: 4,
            offerAxes: [OfferID.roofer: 4],
            includeAxisEmbeddings: includeAxisEmbeddings
        )
    }

    private static func buildNoisyHomeMatch(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let entities = rawNoisyHomeEntities()
        return makeMatch(
            nodeID: NodeID.noisyHome,
            profile: entities.profile,
            offers: [entities.offer],
            englishCarrier: noisyHomeEnglishRetrievalCarrier,
            semanticConcepts: ["home service", "renovation", "cleaning", "plumbing"],
            objectIdentityTerms: ["home service"],
            profileAxis: 7,
            offerAxes: [OfferID.noisyHome: 7],
            includeAxisEmbeddings: includeAxisEmbeddings
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
        offerAxes: [String: Int],
        includeAxisEmbeddings: Bool
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
        let embeddedDocs: [ExchangeRetrievalDocument]
        if includeAxisEmbeddings {
            embeddedDocs = embedDocuments(rawDocs, profileAxis: profileAxis, offerAxes: offerAxes)
        } else {
            embeddedDocs = rawDocs
        }

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
        offerAxes: [String: Int]
    ) -> [ExchangeRetrievalDocument] {
        documents.map { doc in
            let axis: Int = {
                if doc.docKind == .offerObject, let offerID = doc.offerID, let mapped = offerAxes[offerID] {
                    return mapped
                }
                if let offerID = doc.offerID, let mapped = offerAxes[offerID] {
                    return mapped
                }
                return profileAxis
            }()
            return doc.withRetrievalEmbedding(
                RetrievalAccuracyAxisEmbeddingProvider.vector(for: axis),
                updatedAt: fixtureDate
            )
        }
    }
}

private extension ExchangeRetrievalDocument {
    func withRetrievalEmbedding(_ embedding: [Float], updatedAt: Date) -> ExchangeRetrievalDocument {
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
