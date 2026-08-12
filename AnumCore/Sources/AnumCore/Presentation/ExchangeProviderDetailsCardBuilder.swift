import Foundation

/// Canonical provider-authored Details card sections for thread and For You surfaces.
///
/// Reads typed `ExchangePublicNodeProfile` / `ExchangeOffer` fields only — never skim re-parse,
/// synthesized fulfillment posture, or internal automation metadata.
public enum ExchangeProviderDetailsCardBuilder {

    public static func build(
        _ input: ExchangeProviderDetailsCardBuildInput,
        policy: ExchangeProviderDetailsCardPolicy = .default,
        debugSource: String = "direct"
    ) -> ExchangeProviderDetailsCardDisplay {
        let profile = input.profile
        let offer = input.offer
        var deduper = LineDeduper(contextTitle: input.contextTitle)

        let presentationContext = input.presentationContext
        var builtSections: [(priority: Int, section: ExchangeDisplaySection)] = []

        if let about = buildAboutSection(
            profile: profile,
            offer: offer,
            presentationContext: presentationContext,
            deduper: &deduper,
            maxLines: policy.maxLinesPerSection
        ) {
            builtSections.append((0, about))
        }

        if let service = buildServiceSection(
            profile: profile,
            offer: offer,
            presentationContext: presentationContext,
            deduper: &deduper,
            maxLines: policy.maxLinesPerSection
        ) {
            builtSections.append((1, service))
        }

        if allowsCommercialSections(for: presentationContext),
           let pricing = buildPricingSection(
               offer: offer,
               deduper: &deduper,
               maxLines: policy.maxLinesPerSection,
               maxPackages: policy.maxPackages
           ) {
            builtSections.append((2, pricing))
        }

        if allowsCommercialSections(for: presentationContext),
           let availability = buildAvailabilitySection(
               offer: offer,
               deduper: &deduper,
               maxLines: policy.maxLinesPerSection
           ) {
            builtSections.append((3, availability))
        }

        if allowsContactSection(for: presentationContext),
           let contact = buildContactSection(
               offer: offer,
               deduper: &deduper,
               maxLines: policy.maxLinesPerSection
           ) {
            builtSections.append((4, contact))
        }

        if allowsCommercialSections(for: presentationContext),
           let policies = buildPoliciesSection(
               offer: offer,
               deduper: &deduper,
               maxLines: policy.maxLinesPerSection,
               maxFAQs: policy.maxFAQs,
               maxBuyerInputs: policy.maxBuyerInputs
           ) {
            builtSections.append((5, policies))
        }

        let sections = builtSections
            .sorted { $0.priority < $1.priority }
            .map(\.section)
            .prefix(policy.maxSections)
            .map { $0 }

        let completeness = ExchangeDisplayCompleteness(
            hasIdentity: !(input.contextTitle?.isEmpty ?? true) || offer != nil || profile != nil,
            hasProfile: profile != nil && builtSections.contains(where: { $0.section.sourceGroup == .profile }),
            hasOffer: offer != nil,
            hasCommercialFacts: offer?.commercialFacts.hasPublishedCommercialSurface == true,
            hasPricing: offer?.commercialFacts.hasAnyPublicPriceSignal == true,
            hasServiceArea: hasServiceAreaSignal(profile: profile, offer: offer),
            hasAvailability: hasAvailabilitySignal(profile: profile, offer: offer),
            isThinProfile: profile != nil && offer == nil && sections.isEmpty
        )

        let display = ExchangeProviderDetailsCardDisplay(
            sections: Array(sections),
            completeness: completeness,
            presentationContext: presentationContext
        )

        ExchangeProviderDetailsCardDebugLog.logBuildResult(
            source: debugSource,
            profile: profile,
            offer: offer,
            display: display,
            contextTitle: input.contextTitle,
            presentationContext: input.presentationContext
        )

        return display
    }

    // MARK: - Presentation context gating (Phase 2B)

    private static func allowsCommercialSections(
        for context: ExchangeProviderDetailsPresentationContext
    ) -> Bool {
        context == .commercialOpportunity
    }

    private static func allowsContactSection(
        for context: ExchangeProviderDetailsPresentationContext
    ) -> Bool {
        switch context {
        case .commercialOpportunity, .opportunityProfile:
            return true
        case .socialProfile, .mixedHydrated, .unknown:
            return false
        }
    }

    private enum OfferFieldScope {
        case full
        case summaryOnly
        case none
    }

    private static func offerFieldScope(
        for context: ExchangeProviderDetailsPresentationContext
    ) -> OfferFieldScope {
        switch context {
        case .commercialOpportunity:
            return .full
        case .opportunityProfile, .mixedHydrated:
            return .summaryOnly
        case .socialProfile, .unknown:
            return .none
        }
    }

    private static func showsProfileSocialFieldsWhenOfferPresent(
        for context: ExchangeProviderDetailsPresentationContext
    ) -> Bool {
        switch context {
        case .commercialOpportunity:
            return false
        case .socialProfile, .opportunityProfile, .mixedHydrated, .unknown:
            return true
        }
    }

    private static func prefersProfileGeographyAndModality(
        for context: ExchangeProviderDetailsPresentationContext
    ) -> Bool {
        context != .commercialOpportunity
    }

    private static func allowsProfileInterests(
        for context: ExchangeProviderDetailsPresentationContext
    ) -> Bool {
        switch context {
        case .commercialOpportunity, .socialProfile, .opportunityProfile, .mixedHydrated, .unknown:
            return true
        }
    }

    private static func profileInterestsImportance(
        for context: ExchangeProviderDetailsPresentationContext
    ) -> ExchangeDisplayLineImportance {
        context == .commercialOpportunity ? .low : .normal
    }

    private static func profileInterestsLine(
        profile: ExchangePublicNodeProfile?,
        deduper: LineDeduper
    ) -> String? {
        guard let profile else { return nil }
        let blocked = blockedProfileTermKeys(profile: profile)
        var seen = Set<String>()
        var values: [String] = []
        for raw in profile.interests {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = normalizeDedupeKey(trimmed)
            guard !blocked.contains(key), seen.insert(key).inserted else { continue }
            guard !deduper.isDuplicateOfExisting(trimmed) else { continue }
            values.append(trimmed)
        }
        return labeledList(label: "Interests", values: values)
    }

    private static func blockedProfileTermKeys(profile: ExchangePublicNodeProfile) -> Set<String> {
        var blocked = Set<String>()
        for raw in profile.openTo + profile.activityTags + profile.regionTags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            blocked.insert(normalizeDedupeKey(trimmed))
        }
        return blocked
    }

    private static func normalizeDedupeKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    // MARK: - Sections

    private static func buildAboutSection(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        presentationContext: ExchangeProviderDetailsPresentationContext,
        deduper: inout LineDeduper,
        maxLines: Int
    ) -> ExchangeDisplaySection? {
        let offerScope = offerFieldScope(for: presentationContext)
        var lines: [ExchangeDisplayLine] = []

        if let summary = trimmed(profile?.summary) {
            appendLine(
                "About: \(summary)",
                to: &lines,
                deduper: &deduper,
                source: .providerProfile,
                group: .profile,
                fieldKey: "about",
                importance: .high
            )
        } else if let headline = trimmed(profile?.headline) {
            appendLine(
                headline,
                to: &lines,
                deduper: &deduper,
                source: .providerProfile,
                group: .profile,
                fieldKey: "headline",
                importance: .high
            )
        }

        if offerScope != .none,
           let offerSummary = trimmed(offer?.summary),
           !deduper.isDuplicateOfExisting(offerSummary) {
            appendLine(
                "Offer: \(offerSummary)",
                to: &lines,
                deduper: &deduper,
                source: .providerOffer,
                group: .profile,
                fieldKey: "offerSummary",
                importance: .high
            )
        }

        if let notes = trimmed(profile?.semantic.notes) {
            appendLine(
                notes,
                to: &lines,
                deduper: &deduper,
                source: .providerProfile,
                group: .profile,
                fieldKey: "semanticNotes",
                importance: .normal
            )
        } else if offerScope == .full, let notes = trimmed(offer?.semantic.notes) {
            appendLine(
                notes,
                to: &lines,
                deduper: &deduper,
                source: .providerOffer,
                group: .profile,
                fieldKey: "semanticNotes",
                importance: .normal
            )
        }

        let showOpenTo = offer == nil || showsProfileSocialFieldsWhenOfferPresent(for: presentationContext)
        if showOpenTo, let openTo = labeledList(label: "Open to", values: profile?.openTo ?? []) {
            appendLine(
                openTo,
                to: &lines,
                deduper: &deduper,
                source: .providerProfile,
                group: .profile,
                fieldKey: "openTo",
                importance: .normal
            )
        }

        if allowsProfileInterests(for: presentationContext),
           let interests = profileInterestsLine(profile: profile, deduper: deduper) {
            appendLine(
                interests,
                to: &lines,
                deduper: &deduper,
                source: .providerProfile,
                group: .profile,
                fieldKey: "interests",
                importance: profileInterestsImportance(for: presentationContext)
            )
        }

        return section(
            title: "About",
            sourceGroup: .profile,
            lines: capLines(lines, max: maxLines)
        )
    }

    private static func buildServiceSection(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        presentationContext: ExchangeProviderDetailsPresentationContext,
        deduper: inout LineDeduper,
        maxLines: Int
    ) -> ExchangeDisplaySection? {
        let offerScope = offerFieldScope(for: presentationContext)
        let preferProfileGeography = prefersProfileGeographyAndModality(for: presentationContext)
        var lines: [ExchangeDisplayLine] = []

        if let offer {
            switch offerScope {
            case .full, .summaryOnly:
                if let title = trimmed(offer.title),
                   !deduper.matchesContextTitle(title) {
                    appendLine(
                        title,
                        to: &lines,
                        deduper: &deduper,
                        source: .providerOffer,
                        group: .offer,
                        fieldKey: "offerTitle",
                        importance: .high
                    )
                }
            case .none:
                break
            }

            if offerScope == .full {
                if let category = trimmed(offer.category) {
                    appendLine(
                        category,
                        to: &lines,
                        deduper: &deduper,
                        source: .providerOffer,
                        group: .offer,
                        fieldKey: "category",
                        importance: .normal
                    )
                }
                if let tags = labeledList(label: "Tags", values: offer.tags) {
                    appendLine(
                        tags,
                        to: &lines,
                        deduper: &deduper,
                        source: .providerOffer,
                        group: .offer,
                        fieldKey: "tags",
                        importance: .normal
                    )
                }
            }
        }

        if let areaLine = serviceAreaLine(
            profile: profile,
            offer: offer,
            preferProfileOnly: preferProfileGeography
        ) {
            let areaSource: ExchangeDisplaySource = preferProfileGeography || offer == nil
                ? .providerProfile
                : .providerOffer
            appendLine(
                areaLine,
                to: &lines,
                deduper: &deduper,
                source: areaSource,
                group: .offer,
                fieldKey: "serviceArea",
                importance: .normal
            )
        }

        if let modality = fulfillmentModesLine(
            profile: profile,
            offer: offer,
            preferProfileOnly: preferProfileGeography
        ) {
            let modalitySource: ExchangeDisplaySource = preferProfileGeography || offer == nil
                ? .providerProfile
                : .providerOffer
            appendLine(
                modality,
                to: &lines,
                deduper: &deduper,
                source: modalitySource,
                group: .offer,
                fieldKey: "modality",
                importance: .normal
            )
        }

        let showProfileRolesAndRegions = offer == nil
            || showsProfileSocialFieldsWhenOfferPresent(for: presentationContext)
        if showProfileRolesAndRegions {
            if let roles = labeledList(label: "Roles", values: profile?.activityTags ?? []) {
                appendLine(
                    roles,
                    to: &lines,
                    deduper: &deduper,
                    source: .providerProfile,
                    group: .offer,
                    fieldKey: "roles",
                    importance: .normal
                )
            }
            if let regions = labeledList(label: "Region", values: profile?.regionTags ?? []) {
                appendLine(
                    regions,
                    to: &lines,
                    deduper: &deduper,
                    source: .providerProfile,
                    group: .offer,
                    fieldKey: "regions",
                    importance: .normal
                )
            }
        }

        return section(
            title: "Service",
            sourceGroup: .offer,
            lines: capLines(lines, max: maxLines)
        )
    }

    private static func buildPricingSection(
        offer: ExchangeOffer?,
        deduper: inout LineDeduper,
        maxLines: Int,
        maxPackages: Int
    ) -> ExchangeDisplaySection? {
        guard let offer else { return nil }
        let cf = offer.commercialFacts
        var lines: [ExchangeDisplayLine] = []

        if let priceDisplay = trimmed(cf.priceDisplay) {
            appendLine(
                "Price: \(priceDisplay)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "priceDisplay",
                importance: .high
            )
        }

        if cf.priceMin != nil || cf.priceMax != nil {
            let minPart = cf.priceMin.map { "min \(priceDecimal($0))" }
            let maxPart = cf.priceMax.map { "max \(priceDecimal($0))" }
            let range = [minPart, maxPart].compactMap { $0 }.joined(separator: " · ")
            if !range.isEmpty {
                appendLine(
                    "Price range: \(range)",
                    to: &lines,
                    deduper: &deduper,
                    source: .commercialFact,
                    group: .commercial,
                    fieldKey: "priceRange",
                    importance: .normal
                )
            }
        }

        if let currency = trimmed(cf.currency) {
            appendLine(
                "Currency: \(currency)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "currency",
                importance: .low
            )
        }

        if let unit = trimmed(cf.priceUnit) {
            appendLine(
                "Unit: \(unit)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "priceUnit",
                importance: .low
            )
        }

        for pkg in cf.packages.prefix(maxPackages) {
            let title = trimmed(pkg.title) ?? ""
            guard !title.isEmpty else { continue }
            var text = "Package: \(title)"
            if let summary = trimmed(pkg.summary) {
                text += " — \(summary)"
            }
            if let price = trimmed(pkg.priceDisplay) {
                text += " (\(price))"
            }
            appendLine(
                text,
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "package",
                importance: .normal
            )
        }

        if let minimum = trimmed(cf.minimumEngagement) {
            appendLine(
                "Minimum: \(minimum)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "minimumEngagement",
                importance: .normal
            )
        }

        return section(
            title: "Pricing",
            sourceGroup: .commercial,
            lines: capLines(lines, max: maxLines)
        )
    }

    private static func buildAvailabilitySection(
        offer: ExchangeOffer?,
        deduper: inout LineDeduper,
        maxLines: Int
    ) -> ExchangeDisplaySection? {
        guard let offer else { return nil }
        var lines: [ExchangeDisplayLine] = []

        if let note = trimmed(offer.commercialFacts.availabilityNote) {
            appendLine(
                note,
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "availabilityNote",
                importance: .high
            )
        }

        if let lead = trimmed(offer.fulfillment.leadTimeNote) {
            appendLine(
                "Lead time: \(lead)",
                to: &lines,
                deduper: &deduper,
                source: .providerOffer,
                group: .commercial,
                fieldKey: "leadTimeNote",
                importance: .normal
            )
        }

        if let capacity = trimmed(offer.fulfillment.capacityNote) {
            appendLine(
                "Capacity: \(capacity)",
                to: &lines,
                deduper: &deduper,
                source: .providerOffer,
                group: .commercial,
                fieldKey: "capacityNote",
                importance: .normal
            )
        }

        return section(
            title: "Availability & timing",
            sourceGroup: .commercial,
            lines: capLines(lines, max: maxLines)
        )
    }

    private static func buildContactSection(
        offer: ExchangeOffer?,
        deduper: inout LineDeduper,
        maxLines: Int
    ) -> ExchangeDisplaySection? {
        guard let contact = offer?.contactInfo?.normalized(), !contact.isEmpty else { return nil }
        var lines: [ExchangeDisplayLine] = []

        if let name = trimmed(contact.contactName) {
            appendLine(
                name,
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "contactName",
                importance: .normal
            )
        }
        if let business = trimmed(contact.businessName) {
            appendLine(
                business,
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "businessName",
                importance: .normal
            )
        }
        if let method = trimmed(contact.preferredContactMethod?.rawValue) {
            appendLine(
                "Preferred: \(method.capitalized)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "preferredContactMethod",
                importance: .normal
            )
        }
        if let email = trimmed(contact.email) {
            appendLine(
                "Email: \(email)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "email",
                importance: .normal
            )
        }
        if let phone = trimmed(contact.phone) {
            appendLine(
                "Phone: \(phone)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "phone",
                importance: .normal
            )
        }
        if let website = trimmed(contact.website) {
            appendLine(
                "Website: \(website)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "website",
                importance: .normal
            )
        }
        if let area = trimmed(contact.serviceAddressOrArea) {
            appendLine(
                "Area: \(area)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "serviceAddressOrArea",
                importance: .normal
            )
        }
        if let hours = trimmed(contact.availabilityNote) {
            appendLine(
                "Contact hours: \(hours)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "contactAvailabilityNote",
                importance: .low
            )
        }

        return section(
            title: "Contact",
            sourceGroup: .commercial,
            lines: capLines(lines, max: maxLines)
        )
    }

    private static func buildPoliciesSection(
        offer: ExchangeOffer?,
        deduper: inout LineDeduper,
        maxLines: Int,
        maxFAQs: Int,
        maxBuyerInputs: Int
    ) -> ExchangeDisplaySection? {
        guard let offer else { return nil }
        let cf = offer.commercialFacts
        var lines: [ExchangeDisplayLine] = []

        if let cancellation = trimmed(cf.cancellationPolicy) {
            appendLine(
                "Cancellation: \(cancellation)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "cancellationPolicy",
                importance: .normal
            )
        }
        if let refund = trimmed(cf.refundPolicy) {
            appendLine(
                "Refund: \(refund)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "refundPolicy",
                importance: .normal
            )
        }
        if let warranty = trimmed(cf.warrantyPolicy) {
            appendLine(
                "Warranty: \(warranty)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "warrantyPolicy",
                importance: .normal
            )
        }

        for raw in cf.requiredBuyerInputs.prefix(maxBuyerInputs) {
            guard let hint = trimmed(raw) else { continue }
            appendLine(
                hint,
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "requiredBuyerInput",
                importance: .normal
            )
        }

        for faq in cf.faqs.prefix(maxFAQs) {
            let question = faq.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = faq.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !question.isEmpty, !answer.isEmpty else { continue }
            appendLine(
                "\(question) — \(answer)",
                to: &lines,
                deduper: &deduper,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "faq",
                importance: .normal
            )
        }

        return section(
            title: "Policies & questions",
            sourceGroup: .commercial,
            lines: capLines(lines, max: maxLines)
        )
    }

    // MARK: - Field helpers

    private static func serviceAreaLine(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        preferProfileOnly: Bool = false
    ) -> String? {
        if !preferProfileOnly {
            if let note = trimmed(offer?.commercialFacts.serviceAreaNote) {
                return "Area: \(note)"
            }
            if let offer {
                let labels = offer.effectiveServiceAreas.map(\.displayName).filter { !$0.isEmpty }
                if let areas = labeledList(label: "Area", values: labels) {
                    return areas
                }
                if let regions = labeledList(label: "Area", values: offer.regionTags) {
                    return regions
                }
            }
        }
        if let regions = labeledList(label: "Area", values: profile?.regionTags ?? []) {
            return regions
        }
        return nil
    }

    private static func fulfillmentModesLine(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        preferProfileOnly: Bool = false
    ) -> String? {
        if !preferProfileOnly,
           let offer,
           !offer.semantic.fulfillmentModes.isEmpty {
            let labels = offer.semantic.fulfillmentModes.map(humanizeOfferFulfillmentMode)
            return labeledList(label: "Modality", values: labels)
        }
        if let profile, !profile.semantic.fulfillmentModes.isEmpty {
            let labels = profile.semantic.fulfillmentModes.map(humanizeProfileFulfillmentMode)
            return labeledList(label: "Modality", values: labels)
        }
        return nil
    }

    private static func humanizeOfferFulfillmentMode(_ mode: ExchangeOffer.SemanticSurface.FulfillmentMode) -> String {
        switch mode {
        case .localOnly: "Local only"
        case .localPreferred: "Local preferred"
        case .remoteFriendly: "Remote-friendly"
        case .shippable: "Shippable"
        case .digitalDelivery: "Digital delivery"
        case .inPerson: "In person"
        }
    }

    private static func humanizeProfileFulfillmentMode(_ mode: ExchangePublicNodeProfile.SemanticSurface.FulfillmentMode) -> String {
        switch mode {
        case .localOnly: "Local only"
        case .localPreferred: "Local preferred"
        case .remoteFriendly: "Remote-friendly"
        case .shippable: "Shippable"
        case .digitalDelivery: "Digital delivery"
        case .inPerson: "In person"
        }
    }

    private static func hasServiceAreaSignal(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?
    ) -> Bool {
        if let note = trimmed(offer?.commercialFacts.serviceAreaNote), !note.isEmpty {
            return true
        }
        if let offer, !offer.effectiveServiceAreas.isEmpty || !offer.regionTags.isEmpty {
            return true
        }
        if let profile, !profile.regionTags.isEmpty {
            return true
        }
        return false
    }

    private static func hasAvailabilitySignal(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?
    ) -> Bool {
        if trimmed(offer?.commercialFacts.availabilityNote) != nil {
            return true
        }
        if trimmed(offer?.fulfillment.leadTimeNote) != nil {
            return true
        }
        if trimmed(offer?.fulfillment.capacityNote) != nil {
            return true
        }
        if trimmed(offer?.contactInfo?.availabilityNote) != nil {
            return true
        }
        return false
    }

    // MARK: - Line assembly

    private static func appendLine(
        _ raw: String,
        to lines: inout [ExchangeDisplayLine],
        deduper: inout LineDeduper,
        source: ExchangeDisplaySource,
        group: ExchangeDisplaySourceGroup,
        fieldKey: String,
        importance: ExchangeDisplayLineImportance
    ) {
        guard let accepted = ExchangeProviderDisplayCopyGate.acceptsUserFacingLine(raw) else { return }
        guard deduper.registerIfUnique(accepted) else { return }
        lines.append(
            ExchangeDisplayLine(
                text: accepted,
                source: source,
                sourceGroup: group,
                fieldKey: fieldKey,
                importance: importance
            )
        )
    }

    private static func section(
        title: String,
        sourceGroup: ExchangeDisplaySourceGroup,
        lines: [ExchangeDisplayLine]
    ) -> ExchangeDisplaySection? {
        guard !lines.isEmpty else { return nil }
        return ExchangeDisplaySection(
            title: title,
            sourceGroup: sourceGroup,
            lines: lines
        )
    }

    private static func capLines(_ lines: [ExchangeDisplayLine], max limit: Int) -> [ExchangeDisplayLine] {
        Array(lines.prefix(Swift.max(0, limit)))
    }

    private static func labeledList(label: String, values: [String]) -> String? {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return "\(label): \(cleaned.prefix(3).joined(separator: ", "))"
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func priceDecimal(_ value: Decimal) -> String {
        (value as NSDecimalNumber).stringValue
    }

    // MARK: - Dedup

    private struct LineDeduper {
        private let contextTitleKey: String?
        private var seen = Set<String>()

        init(contextTitle: String?) {
            if let title = contextTitle {
                contextTitleKey = Self.normalizeKey(title)
            } else {
                contextTitleKey = nil
            }
        }

        func matchesContextTitle(_ raw: String) -> Bool {
            guard let contextTitleKey else { return false }
            return Self.normalizeKey(raw) == contextTitleKey
        }

        func isDuplicateOfExisting(_ raw: String) -> Bool {
            seen.contains(Self.normalizeKey(raw))
        }

        mutating func registerIfUnique(_ line: String) -> Bool {
            let key = Self.normalizeKey(line)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }

        private static func normalizeKey(_ raw: String) -> String {
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
                .lowercased()
        }
    }
}

// MARK: - DEBUG trace

public enum ExchangeProviderDetailsCardDebugLog {
    public static func logBuildResult(
        source: String,
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        display: ExchangeProviderDetailsCardDisplay,
        contextTitle: String? = nil,
        presentationContext: ExchangeProviderDetailsPresentationContext = .unknown
    ) {
        #if DEBUG
        let profileLabel = logLabel(
            profile?.displayName,
            fallback: profile?.headline,
            empty: "-"
        )
        let offerLabel = logLabel(offer?.title, empty: "-")
        let contextSuffix: String = {
            guard let contextTitle = trimmed(contextTitle) else { return "" }
            return " contextTitle=\(compactLogText(contextTitle, max: 80))"
        }()
        print(
            "[ProviderDetailsCard][build] source=\(source) presentationContext=\(presentationContext.rawValue) " +
            "profile=\(profileLabel) offer=\(offerLabel)\(contextSuffix) sections=\(display.sections.count)"
        )

        for section in display.sections {
            print(
                "[ProviderDetailsCard][section] source=\(source) title=\(section.title) rows=\(section.lines.count)"
            )
            for line in section.lines {
                let (label, value) = splitLabelValue(line.text)
                let preview = compactLogText(value, max: 120)
                let fieldKey = trimmed(line.fieldKey) ?? "-"
                print(
                    "[ProviderDetailsCard][row] source=\(source) section=\(section.title) label=\(label) value=\(preview) fieldKey=\(fieldKey)"
                )
            }
        }
        #endif
    }

    public static func logSurfaceSelection(
        source: String,
        usingCanonical: Bool,
        canonicalSectionCount: Int,
        legacyLineCount: Int
    ) {
        #if DEBUG
        print(
            "[ProviderDetailsCard][select] source=\(source) usingCanonical=\(usingCanonical) " +
            "canonicalSections=\(canonicalSectionCount) legacyLines=\(legacyLineCount)"
        )
        #endif
    }

    public static func logPresentationContext(
        source: String,
        presentationContext: ExchangeProviderDetailsPresentationContext,
        lane: ExchangeThreadLane?,
        queryIntentClass: ExchangeIntent.QueryIntentClass?,
        surfacePreference: ExchangeIntent.SurfacePreference?,
        surfaceLead: ExchangePresentationSurfaceLead?,
        selectedOfferID: String?,
        selectedProfileID: String?,
        threadID: String? = nil
    ) {
        #if DEBUG
        let threadSuffix = threadID.map { " threadID=\($0)" } ?? ""
        let laneLabel = lane.map(\.rawValue) ?? "-"
        let queryLabel = queryIntentClass.map(\.rawValue) ?? "-"
        let surfacePrefLabel = surfacePreference.map(\.rawValue) ?? "-"
        let surfaceLeadLabel: String = {
            guard let surfaceLead else { return "-" }
            switch surfaceLead {
            case .offerLed: return "offerLed"
            case .profileLed: return "profileLed"
            case .ambiguous: return "ambiguous"
            }
        }()
        let offerID = trimmed(selectedOfferID) ?? "-"
        let profileID = trimmed(selectedProfileID) ?? "-"
        print(
            "[ProviderDetailsCard][context] source=\(source)\(threadSuffix) " +
            "presentationContext=\(presentationContext.rawValue) lane=\(laneLabel) " +
            "queryIntentClass=\(queryLabel) surfacePreference=\(surfacePrefLabel) " +
            "surfaceLead=\(surfaceLeadLabel) selectedOfferID=\(offerID) selectedProfileID=\(profileID)"
        )
        #endif
    }

    public static func logFacadeRequest(
        source: String,
        threadID: String?,
        selectedOfferID: String?,
        selectedProfileID: String?,
        contextTitle: String?
    ) {
        #if DEBUG
        let threadSuffix = threadID.map { " threadID=\($0)" } ?? ""
        let offerID = trimmed(selectedOfferID) ?? "-"
        let profileID = trimmed(selectedProfileID) ?? "-"
        let contextSuffix: String = {
            guard let contextTitle = trimmed(contextTitle) else { return "" }
            return " contextTitle=\(compactLogText(contextTitle, max: 80))"
        }()
        print(
            "[ProviderDetailsCard][facade] source=\(source)\(threadSuffix) selectedOfferID=\(offerID) selectedProfileID=\(profileID)\(contextSuffix)"
        )
        #endif
    }

    public static func logThreadViewUsage(
        threadID: String,
        display: ExchangeProviderDetailsCardDisplay,
        contextTitle: String?
    ) {
        #if DEBUG
        let contextSuffix: String = {
            guard let contextTitle = trimmed(contextTitle) else { return "" }
            return " contextTitle=\(compactLogText(contextTitle, max: 80))"
        }()
        let rowCount = display.sections.reduce(0) { $0 + $1.lines.count }
        print(
            "[ProviderDetailsCard][threadView] threadID=\(threadID) usesCanonical=\(display.hasContent) sections=\(display.sections.count) rows=\(rowCount)\(contextSuffix)"
        )
        #endif
    }

    #if DEBUG
    private static func splitLabelValue(_ text: String) -> (String, String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmedText.firstIndex(of: ":") else {
            return ("-", trimmedText)
        }

        let label = String(trimmedText[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmedText[trimmedText.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty {
            return ("-", trimmedText)
        }
        return (label, value.isEmpty ? trimmedText : value)
    }

    private static func logLabel(
        _ primary: String?,
        fallback: String? = nil,
        empty: String
    ) -> String {
        if let primary = trimmed(primary) {
            return compactLogText(primary, max: 80)
        }
        if let fallback = trimmed(fallback) {
            return compactLogText(fallback, max: 80)
        }
        return empty
    }

    private static func compactLogText(_ raw: String, max: Int) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > max else { return collapsed }
        return String(collapsed.prefix(max)) + "…"
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    #endif
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
