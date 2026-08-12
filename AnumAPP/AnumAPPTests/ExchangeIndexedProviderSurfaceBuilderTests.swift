import XCTest
@testable import AnumCore

final class ExchangeIndexedProviderSurfaceBuilderTests: XCTestCase {
    func test_openEndedPhrasePreservation() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let profile = fixtureProfile(
            summary: "Works with first-time developers and accepts small renovation budgets."
        )
        let offer = fixtureOffer(
            summary: "Contractor who works with first-time developers and accepts small renovation budgets."
        )

        let indexed = builder.build(profile: profile, offers: [offer])
        let allText = (indexed.semanticConcepts + indexed.softPreferences + indexed.sourceTextBlocks)
            .map { $0.lowercased() }
            .joined(separator: " | ")

        XCTAssertTrue(allText.contains("works with first-time developers"))
        XCTAssertTrue(allText.contains("accepts small renovation budgets"))
    }

    func test_commercialConditionPreservation_vendorTakeBack() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let profile = fixtureProfile()
        let offer = fixtureOffer(
            summary: "Home listing with seller financing preferred.",
            commercialFacts: .init(
                priceDisplay: "$900k",
                minimumEngagement: "Seller financing available via vendor take-back mortgage."
            )
        )

        let indexed = builder.build(profile: profile, offers: [offer])
        let text = (
            indexed.sourceTextBlocks +
            indexed.semanticConcepts +
            indexed.commercialConstraints.map(\.text)
        )
        .map { $0.lowercased() }
        .joined(separator: " | ")

        XCTAssertTrue(text.contains("vendor take-back mortgage"))
        XCTAssertTrue(text.contains("seller financing"))
    }

    func test_regionServiceAreaPreservation() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let profile = fixtureProfile(
            summary: "Serving GTA and Aurora.",
            regionTags: ["gta", "aurora"],
            regionAliases: ["greater toronto area"]
        )
        let offer = fixtureOffer(
            commercialFacts: .init(serviceAreaNote: "Greater Toronto Area and Aurora")
        )

        let indexed = builder.build(profile: profile, offers: [offer])
        XCTAssertTrue(indexed.regions.regionTags.contains("gta"))
        XCTAssertTrue(indexed.regions.regionTags.contains("aurora"))
        XCTAssertTrue(indexed.regions.regionAliases.contains("greater toronto area"))
        XCTAssertTrue(indexed.regions.serviceAreaNotes.contains { $0.lowercased().contains("greater toronto area") })
        XCTAssertTrue(indexed.sourceTextBlocks.contains { $0.lowercased().contains("gta") })
    }

    func test_hiddenInactiveOffersRetainedButMarked() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let profile = fixtureProfile()
        let hidden = fixtureOffer(status: .active, visibility: .hidden)
        let inactive = fixtureOffer(id: "offer-2", status: .paused, visibility: .publicDiscoverable)

        let indexed = builder.build(profile: profile, offers: [hidden, inactive])
        XCTAssertEqual(indexed.offers.count, 2)
        XCTAssertTrue(indexed.offers.contains { $0.offerID == hidden.id && $0.visibility == ExchangeOffer.Visibility.hidden.rawValue })
        XCTAssertTrue(indexed.offers.contains { $0.offerID == inactive.id && $0.status == ExchangeOffer.Status.paused.rawValue })
    }

    func test_noFusedClausePollutionInAtomicTerms() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let fused = "home in gta, and seller offers vendor take back mortgage"
        let profile = fixtureProfile(summary: fused)
        let offer = fixtureOffer(summary: fused)

        let indexed = builder.build(profile: profile, offers: [offer])
        let allAtomic = indexed.providerTerms + indexed.capabilityTerms + indexed.broadRecallTokens
        XCTAssertFalse(allAtomic.contains(fused))
        XCTAssertTrue(indexed.sourceTextBlocks.map { $0.lowercased() }.contains(fused))
    }

    func test_schemaVersionAndDefaults() {
        let builder = ExchangeIndexedProviderSurfaceBuilder()
        let profile = fixtureProfile(summary: "   ")
        let offer = fixtureOffer(summary: nil)

        let indexed = builder.build(profile: profile, offers: [offer])
        XCTAssertEqual(indexed.schemaVersion, 1)
        XCTAssertEqual(indexed.offers.first?.schemaVersion, 1)
        XCTAssertFalse(indexed.sourceTextBlocks.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
    }
}

private extension ExchangeIndexedProviderSurfaceBuilderTests {
    func fixtureProfile(
        summary: String? = "General profile summary",
        regionTags: [String] = ["gta"],
        regionAliases: [String] = []
    ) -> ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            displayName: "Builder Profile",
            headline: "Local contractor network",
            summary: summary,
            visibility: .discoverable,
            interests: ["housing"],
            offers: ["contractor matching"],
            openTo: ["home renovation help"],
            excludedTopics: [],
            activityTags: ["contractor"],
            regionTags: regionTags,
            canonicalRegionIDs: ["ca-on-gta"],
            parentRegionIDs: ["ca-on"],
            regionAliases: regionAliases,
            semantic: .init(
                domains: ["real estate"],
                intentKinds: ["service"],
                notes: summary
            )
        )
    }

    func fixtureOffer(
        id: String = "offer-1",
        summary: String? = "Offer summary",
        status: ExchangeOffer.Status = .active,
        visibility: ExchangeOffer.Visibility = .publicDiscoverable,
        commercialFacts: ExchangeOffer.CommercialFacts = .empty
    ) -> ExchangeOffer {
        ExchangeOffer(
            id: id,
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Home support offer",
            summary: summary,
            category: "contractor",
            tags: ["home", "renovation"],
            regionTags: ["gta"],
            semantic: .init(
                domains: ["real estate"],
                serviceKinds: ["contractor"]
            ),
            fulfillment: .init(
                pricingMode: .quoteRequired,
                commitmentMode: .exploratory,
                remoteFriendly: false,
                leadTimeNote: "can come tomorrow"
            ),
            status: status,
            visibility: visibility,
            commercialFacts: commercialFacts
        )
    }
}
