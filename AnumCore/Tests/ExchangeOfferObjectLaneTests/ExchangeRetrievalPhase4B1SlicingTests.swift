import Foundation
import Testing
@testable import AnumCore

@Suite("ExchangeRetrievalPhase4B1Slicing")
struct ExchangeRetrievalPhase4B1SlicingTests {
    @Test("profile_intro contains displayName and headline only")
    func profileIntroFields() {
        let profile = sampleProfile()
        let docs = buildIndexedDocs(profile: profile, offers: [])
        let intro = docs.first { $0.docKind == .profileIntro }
        #expect(intro != nil)
        #expect(intro?.sourceField == "profile_intro")
        #expect(intro?.surfaceType == .publicProfile)

        let embedding = intro?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(embedding.contains("multi seller"))
        #expect(embedding.contains("electronics and vehicles"))
        #expect(!embedding.contains("general reseller"))
        #expect(!embedding.contains("collaboration inquiries"))
        #expect(!embedding.contains("selling my car"))
    }

    @Test("profile_about contains summary and approach text")
    func profileAboutFields() {
        let profile = sampleProfile()
        let docs = buildIndexedDocs(profile: profile, offers: [])
        let about = docs.first { $0.docKind == .profileAbout }
        #expect(about != nil)
        #expect(about?.sourceField == "profile_about")

        let embedding = about?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(embedding.contains("general reseller"))
        #expect(embedding.contains("prefer async intro"))
        #expect(embedding.contains("reselling"))
        #expect(!embedding.contains("collaboration inquiries"))
        #expect(!embedding.contains("selling my car"))
    }

    @Test("profile_capability excludes intro about seeking and offers")
    func slimProfileCapability() {
        let profile = sampleProfile()
        let docs = buildIndexedDocs(profile: profile, offers: [sampleOffer()])
        let capability = docs.first { $0.docKind == .profileCapability }
        #expect(capability != nil)

        let embedding = capability?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(embedding.contains("retail"))
        #expect(!embedding.contains("electronics and vehicles"))
        #expect(!embedding.contains("general reseller"))
        #expect(!embedding.contains("prefer async intro"))
        #expect(!embedding.contains("collaboration inquiries"))
        #expect(!embedding.contains("photography"))
        #expect(!embedding.contains("macbook pro"))
    }

    @Test("profile_seeking and profile_affinity remain unchanged")
    func seekingAffinityUnchanged() {
        let profile = sampleProfile()
        let docs = buildIndexedDocs(profile: profile, offers: [])
        let seeking = docs.first { $0.docKind == .profileSeeking }
        let affinity = docs.first { $0.docKind == .profileAffinity }
        #expect(seeking?.sourceField == "profile_seeking")
        #expect(affinity?.sourceField == "profile_affinity")
        #expect(seeking?.retrievalEmbeddingText.localizedCaseInsensitiveContains("collaboration") == true)
        #expect(affinity?.retrievalEmbeddingText.localizedCaseInsensitiveContains("photography") == true)
    }

    @Test("profileIntro and profileAbout Codable round-trip")
    func profileSliceCodableRoundTrip() throws {
        let profile = sampleProfile()
        let docs = buildIndexedDocs(profile: profile, offers: [])
        for kind in [ExchangeRetrievalDocument.DocKind.profileIntro, .profileAbout] {
            guard let doc = docs.first(where: { $0.docKind == kind }) else {
                Issue.record("Missing docKind \(kind.rawValue)")
                continue
            }
            let data = try JSONEncoder().encode(doc)
            let decoded = try JSONDecoder().decode(ExchangeRetrievalDocument.self, from: data)
            #expect(decoded.docKind == kind)
            #expect(decoded.sourceField == doc.sourceField)
        }
    }

    @Test("offer_package contains descriptive package text without price")
    func offerPackageFields() {
        let offer = sampleOffer()
        let docs = buildIndexedDocs(profile: sampleProfile(openTo: []), offers: [offer])
        let package = docs.first { $0.docKind == .offerPackage }
        #expect(package != nil)
        #expect(package?.sourceField == "offer_package")
        #expect(package?.id.hasPrefix("offer-package::") == true)

        let embedding = package?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(embedding.contains("standard"))
        #expect(embedding.contains("includes charger"))
        #expect(!embedding.contains("$999"))
        #expect(!embedding.contains("toronto"))
    }

    @Test("offer_faq is excluded from offer_detail embedding")
    func offerFAQSeparateFromDetail() {
        let offer = sampleOffer(
            faqs: [.init(question: "Is delivery included?", answer: "Yes within Toronto")]
        )
        let docs = buildIndexedDocs(profile: sampleProfile(openTo: []), offers: [offer])
        let detail = docs.first { $0.docKind == .offerDetail }
        let faq = docs.first { $0.docKind == .offerFAQ }
        #expect(detail != nil)
        #expect(faq != nil)

        let detailEmbedding = detail?.retrievalEmbeddingText.lowercased() ?? ""
        let faqEmbedding = faq?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(!detailEmbedding.contains("delivery included"))
        #expect(faqEmbedding.contains("delivery included"))
        #expect(faqEmbedding.contains("yes within toronto"))
    }

    @Test("slim offer_detail excludes package FAQ price and logistics")
    func slimOfferDetail() {
        let offer = sampleOffer()
        let docs = buildIndexedDocs(profile: sampleProfile(openTo: []), offers: [offer])
        let detail = docs.first { $0.docKind == .offerDetail }
        #expect(detail != nil)

        let embedding = detail?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(embedding.contains("macbook pro"))
        #expect(embedding.contains("refurbished"))
        #expect(!embedding.contains("includes charger"))
        #expect(!embedding.contains("$999"))
        #expect(!embedding.contains("ships in"))
        #expect(!embedding.contains("limited stock"))
        #expect(!embedding.contains("greater toronto"))
    }

    @Test("offer_object remains identity-only")
    func offerObjectUnchanged() {
        let docs = buildIndexedDocs(profile: sampleProfile(openTo: []), offers: [sampleOffer()])
        let objectDoc = docs.first { $0.docKind == .offerObject }
        #expect(objectDoc?.sourceField == "offer_object")

        let embedding = objectDoc?.retrievalEmbeddingText.lowercased() ?? ""
        #expect(embedding.contains("macbook pro"))
        #expect(embedding.contains("computer"))
        #expect(!embedding.contains("refurbished"))
        #expect(!embedding.contains("includes charger"))
    }

    @Test("offer package and faq docKinds round-trip")
    func offerSliceCodableRoundTrip() throws {
        let offer = sampleOffer(faqs: [.init(question: "Warranty?", answer: "90 days")])
        let docs = buildIndexedDocs(profile: sampleProfile(openTo: []), offers: [offer])
        for kind in [ExchangeRetrievalDocument.DocKind.offerPackage, .offerFAQ] {
            guard let doc = docs.first(where: { $0.docKind == kind }) else {
                Issue.record("Missing docKind \(kind.rawValue)")
                continue
            }
            let data = try JSONEncoder().encode(doc)
            let decoded = try JSONDecoder().decode(ExchangeRetrievalDocument.self, from: data)
            #expect(decoded.docKind == kind)
            #expect(decoded.offerID == doc.offerID)
        }
    }

    @Test("offer_package cannot prove object evidence")
    func offerPackageObjectLaneSafety() {
        let doc = docsByKind(.offerPackage).first!
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(doc))
    }

    @Test("offer_faq cannot prove object evidence")
    func offerFAQObjectLaneSafety() {
        let docs = buildIndexedDocs(
            profile: sampleProfile(openTo: []),
            offers: [sampleOffer(faqs: [.init(question: "Warranty?", answer: "90 days")])]
        )
        let doc = docs.first { $0.docKind == .offerFAQ }
        #expect(doc != nil)
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(doc!))
    }

    @Test("offer_detail cannot prove object evidence")
    func offerDetailObjectLaneSafety() {
        let doc = docsByKind(.offerDetail).first!
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(doc))
    }

    @Test("nil docKind cannot prove object evidence")
    func nilDocKindBackwardCompat() {
        let legacy = ExchangeRetrievalDocument(
            id: "offer::legacy",
            counterpartyID: "seller-1",
            offerID: "legacy-offer",
            entityType: .offer,
            surfaceType: .offer,
            sourceKind: .local,
            title: "Legacy",
            lexicalText: "computer laptop"
        )
        #expect(legacy.docKind == nil)
        #expect(!ExchangeOfferObjectLane.canProveOfferObjectEvidence(legacy))
    }

    @Test("indexed and direct builders emit compatible profile docKinds")
    func indexedDirectParity() {
        let profile = sampleProfile()
        let offer = sampleOffer()
        let indexedDocs = buildIndexedDocs(profile: profile, offers: [offer])
        let directDocs = ExchangeRetrievalDocumentBuilder().buildDocuments(
            profile: profile,
            offers: [offer],
            counterpartyID: "seller-1",
            sourceKind: .local
        )
        let indexedKinds = Set(indexedDocs.compactMap(\.docKind?.rawValue))
        let directKinds = Set(directDocs.compactMap(\.docKind?.rawValue))
        #expect(indexedKinds == directKinds)
    }
}

private func buildIndexedDocs(
    profile: ExchangePublicNodeProfile,
    offers: [ExchangeOffer]
) -> [ExchangeRetrievalDocument] {
    let surface = ExchangeIndexedProviderSurfaceBuilder().build(profile: profile, offers: offers)
    return ExchangeRetrievalDocumentBuilder().build(
        from: surface,
        counterpartyID: "seller-1",
        sourceKind: .local
    )
}

private func docsByKind(_ kind: ExchangeRetrievalDocument.DocKind) -> [ExchangeRetrievalDocument] {
    buildIndexedDocs(profile: sampleProfile(openTo: []), offers: [sampleOffer()])
        .filter { $0.docKind == kind }
}

private func sampleProfile(openTo: [String] = ["Collaboration inquiries"]) -> ExchangePublicNodeProfile {
    ExchangePublicNodeProfile(
        id: "profile-1",
        nodeID: "seller-1",
        displayName: "Multi seller",
        headline: "Electronics and vehicles",
        summary: "General reseller with broad inventory",
        interests: ["Photography"],
        offers: ["Selling my car"],
        openTo: openTo,
        activityTags: ["reselling"],
        regionTags: ["Toronto"],
        semantic: .init(domains: ["retail"], notes: "Experienced seller"),
        approach: .init(note: "Prefer async intro messages")
    )
}

private func sampleOffer(
    faqs: [ExchangeOffer.FAQ] = []
) -> ExchangeOffer {
    var fulfillment = ExchangeOffer.Fulfillment(
        pricingMode: .fixed,
        commitmentMode: .exploratory,
        remoteFriendly: true
    )
    fulfillment.leadTimeNote = "Ships in 2 days"
    fulfillment.capacityNote = "Limited stock"

    return ExchangeOffer(
        id: "computer-offer",
        nodeID: "seller-1",
        publicProfileID: "profile-1",
        title: "MacBook Pro",
        summary: "Refurbished laptop in excellent condition",
        category: "computer",
        tags: ["laptop"],
        semantic: .init(serviceKinds: ["computer"]),
        fulfillment: fulfillment,
        status: .active,
        visibility: .publicDiscoverable,
        commercialFacts: .init(
            priceDisplay: "$999",
            packages: [
                .init(id: "pkg-standard", title: "Standard", summary: "Includes charger", priceDisplay: "$999")
            ],
            serviceAreaNote: "Greater Toronto Area",
            availabilityNote: "Available now",
            faqs: faqs
        )
    )
}
