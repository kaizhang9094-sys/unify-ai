import XCTest
@testable import AnumCore

final class ExchangeProviderDetailsCardBuilderGatingTests: XCTestCase {

    private func sectionTitles(
        context: ExchangeProviderDetailsPresentationContext
    ) -> [String] {
        let display = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: sampleProfile,
                offer: sampleOffer,
                presentationContext: context
            ),
            policy: ExchangeProviderDetailsCardPolicy(
                maxSections: 10,
                maxLinesPerSection: 10,
                maxPackages: 3,
                maxFAQs: 3,
                maxBuyerInputs: 3
            )
        )
        return display.sections.map(\.title)
    }

    private var sampleProfile: ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            summary: "Experienced operator.",
            openTo: ["collaboration"],
            activityTags: ["Advisor"],
            regionTags: ["Bay Area"]
        )
    }

    private var sampleOffer: ExchangeOffer {
        ExchangeOffer(
            id: "offer-1",
            nodeID: "node-1",
            publicProfileID: "profile-1",
            title: "Advisory Retainer",
            summary: "Monthly strategic guidance.",
            category: "Consulting",
            tags: ["strategy", "growth"],
            regionTags: ["Bay Area"],
            semantic: ExchangeOffer.SemanticSurface(notes: "Offer-only notes."),
            fulfillment: ExchangeOffer.Fulfillment(leadTimeNote: "2 weeks"),
            commercialFacts: ExchangeOffer.CommercialFacts(
                priceDisplay: "$5,000/mo",
                availabilityNote: "Next slot in June",
                cancellationPolicy: "30-day notice"
            ),
            contactInfo: ExchangeOffer.ContactInfo(email: "hello@example.com")
        )
    }

    func testCommercialOpportunityKeepsTransactionalSections() {
        let titles = sectionTitles(context: .commercialOpportunity)
        XCTAssertTrue(titles.contains("About"))
        XCTAssertTrue(titles.contains("Service"))
        XCTAssertTrue(titles.contains("Pricing"))
        XCTAssertTrue(titles.contains("Availability & timing"))
        XCTAssertTrue(titles.contains("Contact"))
        XCTAssertTrue(titles.contains("Policies & questions"))
    }

    func testSocialProfileSuppressesCommercialSections() {
        let display = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: sampleProfile,
                offer: sampleOffer,
                presentationContext: .socialProfile
            ),
            policy: ExchangeProviderDetailsCardPolicy(maxSections: 10, maxLinesPerSection: 10)
        )
        let titles = display.sections.map(\.title)
        XCTAssertTrue(titles.contains("About"))
        XCTAssertTrue(titles.contains("Service"))
        XCTAssertFalse(titles.contains("Pricing"))
        XCTAssertFalse(titles.contains("Availability & timing"))
        XCTAssertFalse(titles.contains("Contact"))
        XCTAssertFalse(titles.contains("Policies & questions"))

        let serviceText = display.sections.first(where: { $0.title == "Service" })?.lines.map { $0.text }.joined(separator: " ") ?? ""
        XCTAssertFalse(serviceText.contains("Consulting"))
        XCTAssertFalse(serviceText.contains("Tags:"))
        XCTAssertTrue(serviceText.contains("Roles:"))
        XCTAssertFalse(serviceText.contains("Advisory Retainer"))
    }

    func testOpportunityProfileAllowsSummaryAndContactNotPricing() {
        let display = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: sampleProfile,
                offer: sampleOffer,
                presentationContext: .opportunityProfile
            ),
            policy: ExchangeProviderDetailsCardPolicy(maxSections: 10, maxLinesPerSection: 10)
        )
        let titles = display.sections.map(\.title)
        XCTAssertTrue(titles.contains("About"))
        XCTAssertTrue(titles.contains("Service"))
        XCTAssertTrue(titles.contains("Contact"))
        XCTAssertFalse(titles.contains("Pricing"))
        XCTAssertFalse(titles.contains("Availability & timing"))
        XCTAssertFalse(titles.contains("Policies & questions"))

        let aboutText = display.sections.first(where: { $0.title == "About" })?.lines.map { $0.text }.joined(separator: " ") ?? ""
        XCTAssertTrue(aboutText.contains("Offer: Monthly strategic guidance."))
        XCTAssertFalse(aboutText.contains("Offer-only notes."))

        let serviceText = display.sections.first(where: { $0.title == "Service" })?.lines.map { $0.text }.joined(separator: " ") ?? ""
        XCTAssertTrue(serviceText.contains("Advisory Retainer"))
        XCTAssertFalse(serviceText.contains("Consulting"))
    }

    func testMixedHydratedIsConservative() {
        let titles = sectionTitles(context: .mixedHydrated)
        XCTAssertTrue(titles.contains("About"))
        XCTAssertTrue(titles.contains("Service"))
        XCTAssertFalse(titles.contains("Pricing"))
        XCTAssertFalse(titles.contains("Availability & timing"))
        XCTAssertFalse(titles.contains("Contact"))
        XCTAssertFalse(titles.contains("Policies & questions"))
    }

    func testUnknownIsSafestMode() {
        let display = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: sampleProfile,
                offer: sampleOffer,
                presentationContext: .unknown
            ),
            policy: ExchangeProviderDetailsCardPolicy(maxSections: 10, maxLinesPerSection: 10)
        )
        let titles = display.sections.map(\.title)
        XCTAssertEqual(Set(titles), Set(["About", "Service"]))
        let aboutText = display.sections.first(where: { $0.title == "About" })?.lines.map { $0.text }.joined(separator: " ") ?? ""
        XCTAssertFalse(aboutText.contains("Offer:"))
    }

    func testSocialProfileIncludesInterestsInAbout() {
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            summary: "Swimmer and builder.",
            interests: ["swimming", "AI"]
        )
        let display = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: profile,
                offer: nil,
                presentationContext: .socialProfile
            ),
            policy: ExchangeProviderDetailsCardPolicy(maxSections: 10, maxLinesPerSection: 10)
        )
        let aboutText = display.sections.first(where: { $0.title == "About" })?.lines.map { $0.text }.joined(separator: " ") ?? ""
        XCTAssertTrue(aboutText.contains("Interests:"))
        XCTAssertTrue(aboutText.contains("swimming"))
        XCTAssertFalse(display.sections.map(\.title).contains("Pricing"))
    }

    func testOpportunityProfileIncludesInterestsWithoutPricing() {
        let display = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: sampleProfileWithInterests,
                offer: sampleOffer,
                presentationContext: .opportunityProfile
            ),
            policy: ExchangeProviderDetailsCardPolicy(maxSections: 10, maxLinesPerSection: 10)
        )
        let aboutText = display.sections.first(where: { $0.title == "About" })?.lines.map { $0.text }.joined(separator: " ") ?? ""
        XCTAssertTrue(aboutText.contains("Interests:"))
        XCTAssertFalse(display.sections.map(\.title).contains("Pricing"))
    }

    func testCommercialOpportunityCapsInterestsWhenAboutFull() {
        let profile = ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            summary: "Primary summary.",
            interests: ["swimming", "AI"],
            openTo: ["partnerships"]
        )
        let display = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: profile,
                offer: sampleOffer,
                presentationContext: .commercialOpportunity
            ),
            policy: ExchangeProviderDetailsCardPolicy(maxSections: 10, maxLinesPerSection: 3)
        )
        let aboutLines = display.sections.first(where: { $0.title == "About" })?.lines ?? []
        XCTAssertLessThanOrEqual(aboutLines.count, 3)
        XCTAssertTrue(display.sections.map { $0.title }.contains("Pricing"))
        let aboutText = aboutLines.map { $0.text }.joined(separator: " ")
        XCTAssertTrue(aboutText.contains("About:"))
        XCTAssertTrue(aboutText.contains("Offer:"))
    }

    func testSocialDiscoveryCanonicalPathUsesSocialProfileContext() {
        let profile = ExchangePublicNodeProfile(
            id: "profile-social",
            nodeID: "node-social",
            summary: "Social operator.",
            interests: ["hiking"]
        )
        var item = ExchangeModels.ForYouItem(
            id: "node-social",
            displayName: "Alex",
            headline: "Builder",
            accessMode: "direct",
            dominantTags: [],
            nodeID: "node-social",
            publicProfileID: "profile-social",
            acceptingInbound: true,
            discoveredAt: Date(),
            canAutonomouslyContact: true,
            discoveryMatchedTerms: [],
            discoveryFactLines: ["Match: shared themes"],
            publicFactLines: ["About: Social operator."],
            suggestedBuyerInputHints: []
        )

        let canonical = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: profile,
                offer: nil,
                contextTitle: item.displayName,
                presentationContext: .socialProfile
            ),
            debugSource: "socialDiscovery"
        )
        item.displayCard = ExchangeProviderDisplayCard(
            title: item.displayName,
            subtitle: item.headline,
            detailSections: canonical.sections,
            diagnostics: ExchangeProviderDisplayDiagnostics(
                sourceSurface: .forYouCachedHydration,
                hadCanonicalProfile: true,
                hadCanonicalOffer: false,
                hadCommercialFacts: false
            )
        )

        let sections = SocialDiscoveryProfileProjection.canonicalSocialDetailsSections(for: item)
        XCTAssertFalse(sections.isEmpty)
        XCTAssertFalse(sections.map { $0.title }.contains("Pricing"))
        let aboutText = sections.first(where: { $0.title == "About" })?.lines.map { $0.text }.joined(separator: " ") ?? ""
        XCTAssertTrue(aboutText.contains("Interests:"))
    }

    private var sampleProfileWithInterests: ExchangePublicNodeProfile {
        ExchangePublicNodeProfile(
            id: "profile-1",
            nodeID: "node-1",
            summary: "Experienced operator.",
            interests: ["AI", "mentoring"],
            openTo: ["collaboration"],
            activityTags: ["Advisor"],
            regionTags: ["Bay Area"]
        )
    }
}

final class ExchangeProviderDetailsLegacyLineGateTests: XCTestCase {
    func testSuppressesSynthesizedFulfillmentPostureLines() {
        let blocked = [
            "Quote on request · Exploratory commitment · On-site leaning",
            "FAQ auto-answer allowed: yes",
            "Exploratory commitment",
            "On-site leaning",
            "Quote required"
        ]
        for line in blocked {
            XCTAssertFalse(
                ExchangeProviderDetailsLegacyLineGate.allowsDetailsFallbackLine(line),
                "Expected suppression for: \(line)"
            )
        }
    }

    func testAllowsAuthoredCommercialFacts() {
        let allowed = [
            "Price: $5,000/mo",
            "Availability: Next slot in June",
            "Cancellation policy: 30-day notice"
        ]
        for line in allowed {
            XCTAssertTrue(
                ExchangeProviderDetailsLegacyLineGate.allowsDetailsFallbackLine(line),
                "Expected allow for: \(line)"
            )
        }
    }

    func testFilterDetailsFallbackLinesRemovesBlockedOnly() {
        let input = [
            "About: Builder",
            "Quote on request · Exploratory commitment · On-site leaning",
            "Interests: swimming"
        ]
        let output = ExchangeProviderDetailsLegacyLineGate.filterDetailsFallbackLines(
            input,
            source: "test"
        )
        XCTAssertEqual(output, ["About: Builder", "Interests: swimming"])
    }
}

final class ExchangeProviderDetailsLegacyFallbackPresenterTests: XCTestCase {
    private func sampleLegacySections() -> [ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot] {
        [
            ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot(
                id: "profile",
                title: "Profile",
                labeledRows: [
                    .init(label: "Headline", value: "Builder"),
                    .init(label: "About", value: "Experienced operator."),
                    .init(label: "Category", value: "Consulting"),
                    .init(label: "Open to", value: "collaboration")
                ]
            ),
            ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot(
                id: "offer",
                title: "Offer",
                labeledRows: [
                    .init(label: "Title", value: "Monthly retainer"),
                    .init(label: "Summary", value: "Hands-on support.")
                ]
            ),
            ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot(
                id: "price",
                title: "Price & packages",
                labeledRows: [.init(label: "Price", value: "$5,000/mo")]
            ),
            ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot(
                id: "availability",
                title: "Availability",
                labeledRows: [
                    .init(label: "Availability", value: "June start"),
                    .init(label: "Fulfillment", value: "Quote on request · Exploratory commitment")
                ]
            ),
            ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot(
                id: "policies",
                title: "Policies",
                valueLines: ["Cancellation: 30 days", "Refund: case by case", "Extra policy"]
            ),
            ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot(
                id: "contact",
                title: "Contact",
                labeledRows: [.init(label: "Contact", value: "hello@example.com")]
            )
        ]
    }

    func testSocialProfileCuratesProfileSafeRowsOnly() {
        let output = ExchangeProviderDetailsLegacyFallbackPresenter.present(
            .init(sections: sampleLegacySections(), context: .socialProfile)
        )
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output.first?.title, "About")
        let labels = output.first?.labeledRows.map(\.label) ?? []
        XCTAssertTrue(labels.contains("Headline"))
        XCTAssertFalse(labels.contains("Category"))
    }

    func testCommercialOpportunityCapsSectionsAndSuppressesFulfillmentPosture() {
        let output = ExchangeProviderDetailsLegacyFallbackPresenter.present(
            .init(sections: sampleLegacySections(), context: .commercialOpportunity)
        )
        XCTAssertLessThanOrEqual(output.count, 3)
        XCTAssertEqual(output.map(\.id), ["profile", "offer", "price"])
        XCTAssertFalse(output.contains { $0.id == "policies" })
        let availability = sampleLegacySections().first { $0.id == "availability" }
        XCTAssertNotNil(availability)
    }

    func testHeroDedupeRemovesDuplicateOfferTitle() {
        let output = ExchangeProviderDetailsLegacyFallbackPresenter.present(
            .init(
                sections: sampleLegacySections(),
                context: .opportunityProfile,
                heroDedupeTexts: ["monthly retainer"],
                contextTitle: "Monthly retainer"
            )
        )
        let offer = output.first { $0.id == "offer" }
        XCTAssertEqual(offer?.labeledRows.map(\.label), ["Summary"])
    }

    func testEmptyCardDisplayCarriesPresentationContextForFallback() {
        let display = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: nil,
                offer: nil,
                presentationContext: .socialProfile
            ),
            debugSource: "test"
        )
        XCTAssertFalse(display.hasContent)
        XCTAssertEqual(display.presentationContext, .socialProfile)
    }

    func testUnknownContextIsMostConservative() {
        let output = ExchangeProviderDetailsLegacyFallbackPresenter.present(
            .init(sections: sampleLegacySections(), context: .unknown)
        )
        XCTAssertEqual(output.map(\.id), ["profile"])
        let labels = output.first?.labeledRows.map(\.label) ?? []
        XCTAssertFalse(labels.contains("Open to"))
    }
}

final class ExchangeProviderDetailsThreadPresenterTests: XCTestCase {
    private func commercialSourceSections() -> [ExchangeProviderDetailsThreadPresenter.SectionSnapshot] {
        [
            .init(
                id: "canonical-0-about",
                title: "About",
                labeledRows: [
                    .init(label: "About", value: "Experienced operator."),
                    .init(label: "Offer", value: "Hands-on support."),
                    .init(label: "Open to", value: "collaboration")
                ]
            ),
            .init(
                id: "canonical-1-service",
                title: "Service",
                labeledRows: [
                    .init(label: "Category", value: "Consulting"),
                    .init(label: "Area", value: "Bay Area"),
                    .init(label: "Modality", value: "Remote")
                ]
            ),
            .init(
                id: "canonical-2-pricing",
                title: "Pricing",
                labeledRows: [
                    .init(label: "Price", value: "$5,000/mo"),
                    .init(label: "Currency", value: "USD"),
                    .init(label: "Unit", value: "month")
                ]
            ),
            .init(
                id: "canonical-3-availability",
                title: "Availability & timing",
                labeledRows: [.init(label: "Availability", value: "June start")]
            ),
            .init(
                id: "canonical-4-contact",
                title: "Contact",
                labeledRows: [.init(label: "Email", value: "hello@example.com")]
            ),
            .init(
                id: "canonical-5-policies",
                title: "Policies & questions",
                valueLines: ["Cancellation: 30 days", "Refund: case by case"]
            )
        ]
    }

    func testCommercialCompactShowsPreviewWithoutPoliciesOrContact() {
        let output = ExchangeProviderDetailsThreadPresenter.present(
            sourceSections: commercialSourceSections(),
            context: .commercialOpportunity
        )
        XCTAssertLessThanOrEqual(output.compactSections.count, 2)
        XCTAssertFalse(output.compactSections.contains { $0.title.hasPrefix("Policies") })
        XCTAssertFalse(output.compactSections.contains { $0.title == "Contact" })
        XCTAssertTrue(output.hasMoreDetails)
        XCTAssertGreaterThan(output.hiddenRowCount, 0)
    }

    func testCommercialExpandedIncludesPoliciesLast() {
        let output = ExchangeProviderDetailsThreadPresenter.present(
            sourceSections: commercialSourceSections(),
            context: .commercialOpportunity
        )
        XCTAssertLessThanOrEqual(output.expandedSections.count, 6)
        XCTAssertEqual(output.expandedSections.last?.title, "Policies & questions")
    }

    func testSocialProfileCompactAndExpandedStayProfileSafe() {
        let source: [ExchangeProviderDetailsThreadPresenter.SectionSnapshot] = [
            .init(
                id: "canonical-0-about",
                title: "About",
                labeledRows: [
                    .init(label: "About", value: "Social operator."),
                    .init(label: "Interests", value: "hiking"),
                    .init(label: "Open to", value: "collaboration")
                ]
            ),
            .init(
                id: "canonical-2-pricing",
                title: "Pricing",
                labeledRows: [.init(label: "Price", value: "$100")]
            )
        ]
        let output = ExchangeProviderDetailsThreadPresenter.present(
            sourceSections: source,
            context: .socialProfile
        )
        XCTAssertEqual(output.compactSections.map(\.title), ["About"])
        XCTAssertEqual(output.expandedSections.map(\.title), ["About"])
        XCTAssertTrue(output.hasMoreDetails)
    }

    func testUnknownContextIsSingleAboutSection() {
        let source: [ExchangeProviderDetailsThreadPresenter.SectionSnapshot] = [
            .init(
                id: "profile",
                title: "About",
                labeledRows: [
                    .init(label: "Headline", value: "Builder"),
                    .init(label: "Open to", value: "chat")
                ]
            ),
            .init(
                id: "offer",
                title: "Service",
                labeledRows: [.init(label: "Title", value: "Retainer")]
            )
        ]
        let output = ExchangeProviderDetailsThreadPresenter.present(
            sourceSections: source,
            context: .unknown
        )
        XCTAssertEqual(output.compactSections.count, 1)
        XCTAssertEqual(output.expandedSections.count, 1)
        let labels = output.compactSections.first?.labeledRows.map(\.label) ?? []
        XCTAssertTrue(labels.contains("Headline"))
        XCTAssertFalse(labels.contains("Open to"))
    }
    func testHasMoreDetailsFalseWhenCompactMatchesExpanded() {
        let source: [ExchangeProviderDetailsThreadPresenter.SectionSnapshot] = [
            .init(
                id: "canonical-0-about",
                title: "About",
                labeledRows: [.init(label: "About", value: "Social operator.")]
            )
        ]
        let output = ExchangeProviderDetailsThreadPresenter.present(
            sourceSections: source,
            context: .socialProfile
        )
        XCTAssertFalse(output.hasMoreDetails)
        XCTAssertEqual(output.hiddenSectionCount, 0)
        XCTAssertEqual(output.hiddenRowCount, 0)
        XCTAssertTrue(
            ExchangeProviderDetailsThreadPresenter.sectionsEquivalent(
                output.compactSections,
                output.expandedSections
            )
        )
    }
}

final class ThreadDetailsVisualBlockMapperTests: XCTestCase {
    private typealias Section = ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot

    func testCommercialCompactMapsSummaryServiceFitAndPriceTile() {
        let sections: [Section] = [
            .init(
                id: "canonical-0-about",
                title: "About",
                labeledRows: [
                    .init(label: "About", value: "Experienced operator."),
                    .init(label: "Offer", value: "Hands-on support.")
                ]
            ),
            .init(
                id: "canonical-1-service",
                title: "Service",
                labeledRows: [
                    .init(label: "Category", value: "Consulting"),
                    .init(label: "Area", value: "Bay Area")
                ]
            ),
            .init(
                id: "canonical-2-pricing",
                title: "Pricing",
                labeledRows: [.init(label: "Price", value: "$5,000/mo")]
            ),
            .init(
                id: "canonical-3-availability",
                title: "Availability & timing",
                labeledRows: [.init(label: "Availability", value: "June start")]
            )
        ]

        let layout = ThreadDetailsVisualBlockMapper.map(
            sections: sections,
            context: .commercialOpportunity,
            mode: .compact
        )

        XCTAssertEqual(layout.context, .commercialOpportunity)
        XCTAssertEqual(layout.mode, .compact)
        XCTAssertTrue(layout.blocks.contains { $0.kind == .summary })
        XCTAssertTrue(layout.blocks.contains { $0.kind == .chipGroup })
        XCTAssertTrue(layout.blocks.contains { $0.kind == .priceTile })
        XCTAssertFalse(layout.blocks.contains { $0.kind == .availabilityTile })
        XCTAssertFalse(layout.blocks.contains { $0.kind == .policyGroup })
    }

    func testCommercialExpandedIncludesContactAndPoliciesLast() {
        let sections: [Section] = [
            .init(
                id: "canonical-2-pricing",
                title: "Pricing",
                labeledRows: [.init(label: "Price", value: "$100")]
            ),
            .init(
                id: "canonical-4-contact",
                title: "Contact",
                labeledRows: [.init(label: "Email", value: "hello@example.com")]
            ),
            .init(
                id: "canonical-5-policies",
                title: "Policies & questions",
                valueLines: ["Cancellation: 30 days"]
            )
        ]

        let layout = ThreadDetailsVisualBlockMapper.map(
            sections: sections,
            context: .commercialOpportunity,
            mode: .expanded
        )

        XCTAssertTrue(layout.blocks.contains { $0.kind == .contactTile })
        XCTAssertTrue(layout.blocks.contains { $0.kind == .policyGroup })
        if let last = layout.blocks.last {
            XCTAssertEqual(last.kind, .policyGroup)
        }
    }

    func testSocialProfileNeverMapsCommercialTiles() {
        let sections: [Section] = [
            .init(
                id: "canonical-0-about",
                title: "About",
                labeledRows: [
                    .init(label: "About", value: "Social operator."),
                    .init(label: "Interests", value: "hiking, mentoring")
                ]
            ),
            .init(
                id: "canonical-2-pricing",
                title: "Pricing",
                labeledRows: [.init(label: "Price", value: "$100")]
            )
        ]

        let layout = ThreadDetailsVisualBlockMapper.map(
            sections: sections,
            context: .socialProfile,
            mode: .expanded
        )

        XCTAssertTrue(layout.blocks.contains { $0.kind == .summary })
        XCTAssertTrue(layout.blocks.contains { $0.kind == .chipGroup })
        XCTAssertFalse(layout.blocks.contains { $0.kind == .priceTile })
        XCTAssertFalse(layout.blocks.contains { $0.kind == .availabilityTile })
        XCTAssertFalse(layout.blocks.contains { $0.kind == .contactTile })
    }

    func testOpportunityProfileMapsOfferHighlight() {
        let sections: [Section] = [
            .init(
                id: "canonical-0-about",
                title: "About",
                labeledRows: [.init(label: "About", value: "Builder profile.")]
            ),
            .init(
                id: "canonical-1-service",
                title: "Service",
                labeledRows: [
                    .init(label: "Title", value: "Monthly retainer"),
                    .init(label: "Summary", value: "Hands-on support.")
                ]
            )
        ]

        let layout = ThreadDetailsVisualBlockMapper.map(
            sections: sections,
            context: .opportunityProfile,
            mode: .compact
        )

        XCTAssertTrue(layout.blocks.contains { $0.kind == .offerHighlight })
        if case .offerHighlight(let offer)? = layout.blocks.first(where: { $0.kind == .offerHighlight }) {
            XCTAssertEqual(offer.title, "Monthly retainer")
        } else {
            XCTFail("Expected offer highlight block")
        }
    }

    func testUnknownContextIsConservative() {
        let sections: [Section] = [
            .init(
                id: "profile",
                title: "About",
                labeledRows: [
                    .init(label: "Headline", value: "Builder"),
                    .init(label: "Open to", value: "collaboration")
                ]
            ),
            .init(
                id: "offer",
                title: "Service",
                labeledRows: [.init(label: "Title", value: "Retainer")]
            )
        ]

        let layout = ThreadDetailsVisualBlockMapper.map(
            sections: sections,
            context: .unknown,
            mode: .compact
        )

        XCTAssertTrue(layout.blocks.contains { $0.kind == .summary })
        XCTAssertFalse(layout.blocks.contains { $0.kind == .offerHighlight })
        XCTAssertFalse(layout.blocks.contains { $0.kind == .priceTile })
    }
}
