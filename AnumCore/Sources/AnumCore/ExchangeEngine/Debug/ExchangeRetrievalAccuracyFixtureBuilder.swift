import Foundation

/// Test-fixture-only embedding provider. Maps synthetic fixture concepts to stable 8-dim axis vectors.
/// Must never be wired into production retrieval ranking.
public struct RetrievalAccuracyAxisEmbeddingProvider: MemoryEmbeddingProvider, Sendable {
    public static let dimension = 8

    public init() {}

    public func embed(_ text: String) -> [Float]? {
        Self.vector(for: Self.axisIndex(for: text))
    }

    public static func axisIndex(for text: String) -> Int {
        let key = text.lowercased()
        if containsAny(key, ["computer", "laptop", "macbook", "workstation", "dell"]) { return 0 }
        if containsAny(key, ["car", "vehicle", "toyota", "sedan", "camry"]) { return 1 }
        if containsAny(key, ["wedding", "photography", "photographer", "photo"]) { return 2 }
        if containsAny(key, ["cleaning", "move-out", "move out", "cleaner"]) { return 3 }
        if containsAny(key, ["plumber", "appraisal", "repair", "roof"]) { return 4 }
        if containsAny(key, ["coder", "ios", "app", "software", "backend", "developer"]) { return 5 }
        if containsAny(key, ["robotics", "automation", "founder", "hardware", "ai"]) { return 6 }
        return 7
    }

    public static func vector(for axis: Int) -> [Float] {
        var components = Array(repeating: Float(0), count: dimension)
        let clamped = max(0, min(axis, dimension - 1))
        components[clamped] = 1
        return components
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

/// Deterministic 10-node retrieval accuracy fixture catalog.
public enum ExchangeRetrievalAccuracyFixtureBuilder {
    public static let fixtureDate = Date(timeIntervalSince1970: 1_700_000_000)
    public static let onnxEmbeddingDimension = 384

    public enum NodeID {
        public static let carSeller = "node-car-seller"
        public static let computerSeller = "node-computer-seller"
        public static let multiSeller = "node-multi-seller"
        public static let photographer = "node-photographer"
        public static let cleaner = "node-cleaner"
        public static let plumber = "node-plumber"
        public static let coder = "node-coder"
        public static let roboticsFounder = "node-robotics-founder"
        public static let policyHeavy = "node-policy-heavy"
        public static let noisyProfile = "node-noisy-profile"
    }

    public enum OfferID {
        public static let toyotaCamry = "offer-toyota-camry"
        public static let dellLaptop = "offer-dell-laptop"
        public static let multiCar = "offer-multi-car"
        public static let multiComputer = "offer-multi-computer"
        public static let weddingPhoto = "offer-wedding-photo"
        public static let moveoutCleaning = "offer-moveout-cleaning"
        public static let appraisalRepair = "offer-appraisal-repair"
        public static let warrantyHeavy = "offer-warranty-heavy"
        public static let minorListing = "offer-minor-listing"
    }

    public static func buildCatalog(includeAxisEmbeddings: Bool = true) -> [ExchangeDirectoryMatch] {
        [
            buildCarSeller(includeAxisEmbeddings: includeAxisEmbeddings),
            buildComputerSeller(includeAxisEmbeddings: includeAxisEmbeddings),
            buildMultiSeller(includeAxisEmbeddings: includeAxisEmbeddings),
            buildPhotographer(includeAxisEmbeddings: includeAxisEmbeddings),
            buildCleaner(includeAxisEmbeddings: includeAxisEmbeddings),
            buildPlumber(includeAxisEmbeddings: includeAxisEmbeddings),
            buildCoder(includeAxisEmbeddings: includeAxisEmbeddings),
            buildRoboticsFounder(includeAxisEmbeddings: includeAxisEmbeddings),
            buildPolicyHeavy(includeAxisEmbeddings: includeAxisEmbeddings),
            buildNoisyProfile(includeAxisEmbeddings: includeAxisEmbeddings)
        ]
    }

    /// Ensures Tier B ONNX pre-embed starts from docs without axis vectors.
    public static func assertCatalogHasNoEmbeddings(_ catalog: [ExchangeDirectoryMatch]) -> [String] {
        var failures: [String] = []
        for match in catalog {
            for doc in match.retrievalDocuments where doc.hasEmbedding {
                failures.append(
                    "unexpected embedding on \(doc.id) dim=\(doc.embeddingDimension) node=\(match.id)"
                )
            }
        }
        return failures
    }

    /// Validates ONNX pre-embed output before smoke scenarios run.
    public static func assertCatalogONNXEmbeddings(_ catalog: [ExchangeDirectoryMatch]) -> [String] {
        var failures: [String] = []
        for match in catalog {
            for doc in match.retrievalDocuments {
                let text = doc.retrievalEmbeddingText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                guard doc.hasEmbedding else {
                    failures.append("missing ONNX embedding for \(doc.id) node=\(match.id)")
                    continue
                }
                if doc.embeddingDimension != onnxEmbeddingDimension {
                    failures.append(
                        "embedding dim \(doc.embeddingDimension) != \(onnxEmbeddingDimension) for \(doc.id)"
                    )
                }
            }
        }
        return failures
    }

    /// Serial ONNX passage embedding for fixture catalog docs (test/smoke only).
    public static func preEmbedCatalogWithONNX(
        _ catalog: [ExchangeDirectoryMatch],
        embedder: ONNXSentenceEmbedder
    ) -> [ExchangeDirectoryMatch] {
        catalog.map { match in
            var embeddedDocs: [ExchangeRetrievalDocument] = []
            embeddedDocs.reserveCapacity(match.retrievalDocuments.count)
            for doc in match.retrievalDocuments {
                let text = doc.retrievalEmbeddingText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    embeddedDocs.append(doc)
                    continue
                }
                guard let embedding = embedder.embedPassage(text), !embedding.isEmpty else {
                    embeddedDocs.append(doc)
                    continue
                }
                embeddedDocs.append(doc.withRetrievalEmbedding(embedding, updatedAt: fixtureDate))
            }

            let embeddingByDocID = Dictionary(uniqueKeysWithValues: embeddedDocs.map { ($0.id, $0.embedding) })
            let embeddedHits = match.retrievalHits.map { hit -> ExchangeDirectoryRetrievalHit in
                guard let docID = hit.retrievalDocID, let embedding = embeddingByDocID[docID] else {
                    return hit
                }
                var updated = hit
                updated.embedding = embedding
                return updated
            }

            return ExchangeDirectoryMatch(
                id: match.id,
                counterparty: match.counterparty,
                publicProfile: match.publicProfile,
                offers: match.offers,
                retrievalDocuments: embeddedDocs,
                reachability: match.reachability,
                matchReason: match.matchReason,
                matchedTerms: match.matchedTerms,
                score: match.score,
                vectorSignals: match.vectorSignals,
                retrievalHits: embeddedHits,
                candidateOfferIDsFromDocs: match.candidateOfferIDsFromDocs
            )
        }
    }

    // MARK: - Nodes

    private static func buildCarSeller(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.carSeller
        let profileID = "profile-car-seller"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "Local Vehicle Seller",
            headline: "Local used vehicle seller",
            summary: "Used sedans and local vehicle sales",
            offers: ["Toyota Camry used sedan"],
            activityTags: ["automotive", "vehicle"],
            regionTags: ["Toronto"],
            semantic: .init(domains: ["automotive"], notes: "Used car dealer"),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        let offer = makeOffer(
            id: OfferID.toyotaCamry,
            nodeID: nodeID,
            profileID: profileID,
            title: "Toyota Camry",
            summary: "Used sedan in good condition",
            category: "car",
            tags: ["vehicle", "sedan", "toyota"],
            serviceKinds: ["car"],
            axis: 1
        )
        return makeMatch(nodeID: nodeID, profile: profile, offers: [offer], profileAxis: 1, offerAxes: [OfferID.toyotaCamry: 1], includeAxisEmbeddings: includeAxisEmbeddings)
    }

    private static func buildComputerSeller(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.computerSeller
        let profileID = "profile-computer-seller"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "Electronics Refurbisher",
            headline: "Electronics refurbisher",
            summary: "Refurbished laptops and workstations",
            offers: ["Dell laptop computer"],
            activityTags: ["electronics", "refurbisher"],
            regionTags: ["Toronto"],
            semantic: .init(domains: ["electronics"], notes: "Computer refurbisher"),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        let offer = makeOffer(
            id: OfferID.dellLaptop,
            nodeID: nodeID,
            profileID: profileID,
            title: "Dell Laptop",
            summary: "Refurbished laptop workstation computer",
            category: "computer",
            tags: ["laptop", "computer", "dell"],
            serviceKinds: ["computer"],
            axis: 0,
            faqs: [.init(question: "Is delivery included?", answer: "Yes within Toronto")],
            packages: [
                .init(id: "pkg-standard", title: "Standard package", summary: "Includes charger and sleeve")
            ]
        )
        return makeMatch(nodeID: nodeID, profile: profile, offers: [offer], profileAxis: 0, offerAxes: [OfferID.dellLaptop: 0], includeAxisEmbeddings: includeAxisEmbeddings)
    }

    private static func buildMultiSeller(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.multiSeller
        let profileID = "profile-multi-seller"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "General Reseller",
            headline: "General reseller",
            summary: "Mixed inventory reseller",
            offers: ["Used car", "Refurbished computer"],
            activityTags: ["reseller"],
            regionTags: ["Toronto"],
            semantic: .init(domains: ["retail"], notes: "General reseller"),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        let carOffer = makeOffer(
            id: OfferID.multiCar,
            nodeID: nodeID,
            profileID: profileID,
            title: "Used Car",
            summary: "Selling my car sedan vehicle",
            category: "car",
            tags: ["car", "vehicle"],
            serviceKinds: ["car"],
            axis: 1
        )
        let computerOffer = makeOffer(
            id: OfferID.multiComputer,
            nodeID: nodeID,
            profileID: profileID,
            title: "Refurbished Computer",
            summary: "MacBook Pro laptop computer workstation",
            category: "computer",
            tags: ["computer", "laptop"],
            serviceKinds: ["computer"],
            axis: 0
        )
        return makeMatch(
            nodeID: nodeID,
            profile: profile,
            offers: [carOffer, computerOffer],
            profileAxis: 7,
            offerAxes: [OfferID.multiCar: 1, OfferID.multiComputer: 0],
            includeAxisEmbeddings: includeAxisEmbeddings
        )
    }

    private static func buildPhotographer(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.photographer
        let profileID = "profile-photographer"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "Wedding Photographer",
            headline: "Wedding event photographer",
            summary: "Wedding and event photography services",
            interests: ["Photography"],
            offers: ["Wedding photography packages"],
            activityTags: ["photographer", "wedding"],
            regionTags: ["Toronto"],
            semantic: .init(domains: ["photography"], notes: "Event photographer"),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        let offer = makeOffer(
            id: OfferID.weddingPhoto,
            nodeID: nodeID,
            profileID: profileID,
            title: "Wedding Photography",
            summary: "Professional wedding photography package service",
            category: "photography",
            tags: ["wedding", "photography", "photographer"],
            serviceKinds: ["photography"],
            axis: 2,
            faqs: [
                .init(question: "How long does photo delivery take?", answer: "Two weeks editing included"),
                .init(question: "Do you travel for weddings?", answer: "Yes within Ontario")
            ],
            packages: [
                .init(id: "pkg-starter", title: "Starter wedding package", summary: "Ceremony coverage"),
                .init(id: "pkg-fullday", title: "Full-day wedding package", summary: "Full day wedding coverage")
            ]
        )
        return makeMatch(nodeID: nodeID, profile: profile, offers: [offer], profileAxis: 2, offerAxes: [OfferID.weddingPhoto: 2], includeAxisEmbeddings: includeAxisEmbeddings)
    }

    private static func buildCleaner(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.cleaner
        let profileID = "profile-cleaner"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "Home Cleaning Service",
            headline: "Home cleaning service",
            summary: "Residential move-out cleaning",
            offers: ["Move-out cleaning package"],
            activityTags: ["cleaning"],
            regionTags: ["Toronto"],
            semantic: .init(domains: ["cleaning"], notes: "Home cleaning"),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        let offer = makeOffer(
            id: OfferID.moveoutCleaning,
            nodeID: nodeID,
            profileID: profileID,
            title: "Move-Out Cleaning Package",
            summary: "Deep move-out cleaning for apartments and homes",
            category: "cleaning",
            tags: ["cleaning", "move-out"],
            serviceKinds: ["cleaning"],
            axis: 3
        )
        return makeMatch(nodeID: nodeID, profile: profile, offers: [offer], profileAxis: 3, offerAxes: [OfferID.moveoutCleaning: 3], includeAxisEmbeddings: includeAxisEmbeddings)
    }

    private static func buildPlumber(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.plumber
        let profileID = "profile-plumber"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "Local Home Service",
            headline: "Local home service provider",
            summary: "Plumbing appraisal and repair services",
            offers: ["Appraisal and repair service"],
            activityTags: ["plumber", "home service"],
            regionTags: ["Toronto"],
            semantic: .init(domains: ["home service"], notes: "Licensed plumber"),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        let offer = makeOffer(
            id: OfferID.appraisalRepair,
            nodeID: nodeID,
            profileID: profileID,
            title: "Appraisal and Repair Service",
            summary: "Plumber appraisal and pipe repair service",
            category: "plumbing",
            tags: ["plumber", "appraisal", "repair"],
            serviceKinds: ["plumbing"],
            axis: 4
        )
        return makeMatch(nodeID: nodeID, profile: profile, offers: [offer], profileAxis: 4, offerAxes: [OfferID.appraisalRepair: 4], includeAxisEmbeddings: includeAxisEmbeddings)
    }

    private static func buildCoder(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.coder
        let profileID = "profile-coder"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "Software Developer",
            headline: "Software developer",
            summary: "Long background story in software engineering and product work",
            interests: ["AI", "Robotics", "Local founders"],
            offers: [],
            openTo: ["Startup collaborations", "Contract projects"],
            activityTags: ["coder", "developer"],
            regionTags: ["Toronto"],
            semantic: .init(
                domains: ["software"],
                notes: "iOS web backend developer open to startup collaborations AI robotics local founders"
            ),
            approach: .init(note: "Prefer async intro for collaboration inquiries"),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        return makeMatch(nodeID: nodeID, profile: profile, offers: [], profileAxis: 5, offerAxes: [:], includeAxisEmbeddings: includeAxisEmbeddings)
    }

    private static func buildRoboticsFounder(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.roboticsFounder
        let profileID = "profile-robotics-founder"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "Robotics Founder",
            headline: "Hardware automation hobbyist and founder",
            summary: "Interests in robotics automation and AI hardware projects",
            interests: ["Robotics", "Automation", "AI"],
            openTo: ["Hardware collaborators", "Startup collaborations"],
            activityTags: ["founder", "robotics"],
            regionTags: ["Toronto"],
            semantic: .init(
                domains: ["robotics"],
                notes: "Looking for hardware collaborators robotics automation AI local founders"
            ),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        return makeMatch(nodeID: nodeID, profile: profile, offers: [], profileAxis: 6, offerAxes: [:], includeAxisEmbeddings: includeAxisEmbeddings)
    }

    private static func buildPolicyHeavy(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.policyHeavy
        let profileID = "profile-policy-heavy"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "Terms-Heavy Seller",
            headline: "Terms-heavy seller",
            summary: "Seller with extensive warranty and policy documentation",
            offers: ["Warranty-heavy listing"],
            activityTags: ["retail"],
            regionTags: ["Toronto"],
            semantic: .init(domains: ["retail"], notes: "Policy heavy seller"),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        let offer = makeOffer(
            id: OfferID.warrantyHeavy,
            nodeID: nodeID,
            profileID: profileID,
            title: "Warranty Heavy Listing",
            summary: "Consumer electronics with extensive warranty terms",
            category: "electronics",
            tags: ["warranty", "policy"],
            serviceKinds: ["electronics"],
            axis: 7,
            faqs: [
                .init(question: "What is the warranty policy?", answer: "Extended warranty terms apply"),
                .init(question: "What is the refund policy?", answer: "See full refund policy document"),
                .init(question: "What is the cancellation policy?", answer: "Cancellation within 14 days")
            ]
        )
        return makeMatch(nodeID: nodeID, profile: profile, offers: [offer], profileAxis: 7, offerAxes: [OfferID.warrantyHeavy: 7], includeAxisEmbeddings: includeAxisEmbeddings)
    }

    private static func buildNoisyProfile(includeAxisEmbeddings: Bool) -> ExchangeDirectoryMatch {
        let nodeID = NodeID.noisyProfile
        let profileID = "profile-noisy"
        let profile = ExchangePublicNodeProfile(
            id: profileID,
            nodeID: nodeID,
            displayName: "Broad Background Seller",
            headline: "Broad background narrative",
            summary: "Very long general background narrative with weak specific capability signal",
            offers: ["Minor listing"],
            activityTags: ["general"],
            regionTags: ["Toronto"],
            semantic: .init(domains: ["general"], notes: "Broad background with weak capability"),
            createdAt: fixtureDate,
            updatedAt: fixtureDate
        )
        let offer = makeOffer(
            id: OfferID.minorListing,
            nodeID: nodeID,
            profileID: profileID,
            title: "Minor Listing",
            summary: "Minor general listing item",
            category: "general",
            tags: ["general"],
            serviceKinds: ["general"],
            axis: 7
        )
        return makeMatch(nodeID: nodeID, profile: profile, offers: [offer], profileAxis: 7, offerAxes: [OfferID.minorListing: 7], includeAxisEmbeddings: includeAxisEmbeddings)
    }

    // MARK: - Builders

    private static func makeOffer(
        id: String,
        nodeID: String,
        profileID: String,
        title: String,
        summary: String,
        category: String,
        tags: [String],
        serviceKinds: [String],
        axis: Int,
        faqs: [ExchangeOffer.FAQ] = [],
        packages: [ExchangeOffer.PackageOption] = []
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: id,
            nodeID: nodeID,
            publicProfileID: profileID,
            title: title,
            summary: summary,
            category: category,
            tags: tags,
            semantic: .init(serviceKinds: serviceKinds),
            status: .active,
            visibility: .publicDiscoverable,
            createdAt: fixtureDate,
            updatedAt: fixtureDate,
            commercialFacts: .init(
                packages: packages,
                faqs: faqs
            )
        )
    }

    private static func makeMatch(
        nodeID: String,
        profile: ExchangePublicNodeProfile,
        offers: [ExchangeOffer],
        profileAxis: Int,
        offerAxes: [String: Int],
        includeAxisEmbeddings: Bool
    ) -> ExchangeDirectoryMatch {
        let surface = ExchangeIndexedProviderSurfaceBuilder().build(profile: profile, offers: offers)
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
