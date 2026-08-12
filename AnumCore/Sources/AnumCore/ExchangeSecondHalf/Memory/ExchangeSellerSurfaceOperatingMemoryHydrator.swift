import Foundation

/// Maps published seller surface rows into `ExchangeStructuredOperatingMemory`.
///
/// - Pure Swift: no IO, mutation of domain objects, LLM calls, or side effects on offers/profiles.
/// - Facts are conservative summaries of what is already publicly published.
public enum ExchangeSellerSurfaceOperatingMemoryHydrator {
    public static func hydrate(
        publicProfile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?
    ) -> ExchangeStructuredOperatingMemory {
        hydrateInternal(publicProfile: publicProfile, offer: offer)
    }

    /// Short lines for embedding into thread-scale `knownFacts` (read-model / UI).
    public static func offerFulfillmentFactLines(for offer: ExchangeOffer) -> [String] {
        let f = offer.fulfillment
        var lines: [String] = []
        lines.append("Offer fulfillment — pricing mode: \(f.pricingMode.displayLabel)")
        lines.append("Offer fulfillment — commitment mode: \(f.commitmentMode.displayLabel)")
        lines.append(f.remoteFriendly ? "Offer fulfillment — remote-friendly: yes"
            : "Offer fulfillment — remote-friendly: no")

        if let note = trim(f.leadTimeNote) {
            lines.append("Offer fulfillment — lead time: \(note)")
        }

        if let note = trim(f.capacityNote) {
            lines.append("Offer fulfillment — capacity note: \(note)")
        }

        return dedupeLines(lines)
    }

    // MARK: - Internal

    private static func hydrateInternal(
        publicProfile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?
    ) -> ExchangeStructuredOperatingMemory {
        var pricingRules: [ExchangeStructuredOperatingMemory.PricingRule] = []
        var serviceItems: [ExchangeStructuredOperatingMemory.ServiceItem] = []
        var coverageAreas: [ExchangeStructuredOperatingMemory.CoverageArea] = []
        var availabilityWindows: [ExchangeStructuredOperatingMemory.AvailabilityWindow] = []
        var capacityRules: [ExchangeStructuredOperatingMemory.CapacityRule] = []
        var leadTimes: [ExchangeStructuredOperatingMemory.LeadTimeRule] = []
        var standardPolicies: [ExchangeStructuredOperatingMemory.PolicyRule] = []
        var exclusions: [String] = []
        var requesterConstraints: [ExchangeStructuredOperatingMemory.RequesterConstraint] = []

        if let offer {
            hydrateOffer(
                offer,
                pricingRules: &pricingRules,
                serviceItems: &serviceItems,
                coverageAreas: &coverageAreas,
                availabilityWindows: &availabilityWindows,
                standardPolicies: &standardPolicies,
                capacityRules: &capacityRules,
                leadTimes: &leadTimes,
                requesterConstraints: &requesterConstraints
            )
        }

        if let publicProfile {
            hydratePublicProfile(
                publicProfile,
                serviceItems: &serviceItems,
                coverageAreas: &coverageAreas,
                availabilityWindows: &availabilityWindows,
                standardPolicies: &standardPolicies,
                exclusions: &exclusions,
                requesterConstraints: &requesterConstraints
            )
        }

        exclusions = dedupeLines(exclusions)

        return ExchangeStructuredOperatingMemory(
            pricingRules: pricingRules,
            serviceItems: serviceItems,
            coverageAreas: coverageAreas,
            availabilityWindows: availabilityWindows,
            capacityRules: capacityRules,
            leadTimes: leadTimes,
            standardPolicies: standardPolicies,
            exclusions: exclusions,
            requesterConstraints: requesterConstraints
        )
    }

    private static func hydrateOffer(
        _ offer: ExchangeOffer,
        pricingRules: inout [ExchangeStructuredOperatingMemory.PricingRule],
        serviceItems: inout [ExchangeStructuredOperatingMemory.ServiceItem],
        coverageAreas: inout [ExchangeStructuredOperatingMemory.CoverageArea],
        availabilityWindows: inout [ExchangeStructuredOperatingMemory.AvailabilityWindow],
        standardPolicies: inout [ExchangeStructuredOperatingMemory.PolicyRule],
        capacityRules: inout [ExchangeStructuredOperatingMemory.CapacityRule],
        leadTimes: inout [ExchangeStructuredOperatingMemory.LeadTimeRule],
        requesterConstraints: inout [ExchangeStructuredOperatingMemory.RequesterConstraint]
    ) {
        let titleLine = trim(offer.title)
        let summaryLine = trim(offer.summary)
        let categoryLine = trim(offer.category)

        if titleLine != nil || summaryLine != nil || categoryLine != nil {
            let detailsPieces = [categoryLine.map { "Category: \($0)" }, summaryLine]
                .compactMap { $0 }
            let detailsText = detailsPieces.isEmpty ? nil : detailsPieces.joined(separator: " · ")
            serviceItems.append(
                ExchangeStructuredOperatingMemory.ServiceItem(
                    id: UUID(),
                    name: titleLine ?? "Published offer",
                    details: detailsText,
                    isActive: offer.status == .active
                )
            )
        }

        for tag in offer.tags {
            guard let trimmed = trim(tag), !trimmed.isEmpty else { continue }
            serviceItems.append(
                ExchangeStructuredOperatingMemory.ServiceItem(
                    id: UUID(),
                    name: trimmed,
                    details: nil,
                    isActive: offer.status == .active
                )
            )
        }

        for region in offer.regionTags {
            guard let name = trim(region), !name.isEmpty else { continue }
            coverageAreas.append(
                ExchangeStructuredOperatingMemory.CoverageArea(
                    id: UUID(),
                    name: name,
                    details: "From published offer geography tags."
                )
            )
        }

        let fm = offer.semantic.fulfillmentModes
        if !fm.isEmpty {
            let readable = fm.map(\.rawValue).sorted().joined(separator: ", ")
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer fulfillment modes",
                    details: readable
                )
            )
        }

        if let notes = trim(offer.semantic.notes) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer semantic notes",
                    details: notes
                )
            )
        }

        let f = offer.fulfillment

        pricingRules.append(
            ExchangeStructuredOperatingMemory.PricingRule(
                id: UUID(),
                label: "Offer pricing posture",
                amountDescription: f.pricingMode.displayLabel,
                notes: "Published fulfillment pricing mode."
            )
        )

        standardPolicies.append(
            ExchangeStructuredOperatingMemory.PolicyRule(
                id: UUID(),
                title: "Offer commitment posture",
                details: "Published commitment posture: \(f.commitmentMode.displayLabel)."
            )
        )

        standardPolicies.append(
            ExchangeStructuredOperatingMemory.PolicyRule(
                id: UUID(),
                title: "Remote readiness",
                details: f.remoteFriendly
                    ? "This offer is framed as supporting remote fulfillment."
                    : "This offer is framed as primarily onsite or non-remote absent other notes."
            )
        )

        if let lt = trim(f.leadTimeNote) {
            leadTimes.append(
                ExchangeStructuredOperatingMemory.LeadTimeRule(
                    id: UUID(),
                    label: "Published lead time",
                    turnaroundDescription: lt
                )
            )
        }

        if let cap = trim(f.capacityNote) {
            capacityRules.append(
                ExchangeStructuredOperatingMemory.CapacityRule(
                    id: UUID(),
                    label: "Published capacity signals",
                    details: cap
                )
            )
        }

        hydrateCommercialFacts(
            offer.commercialFacts,
            pricingRules: &pricingRules,
            serviceItems: &serviceItems,
            coverageAreas: &coverageAreas,
            availabilityWindows: &availabilityWindows,
            standardPolicies: &standardPolicies,
            requesterConstraints: &requesterConstraints
        )

        if offer.status == .active, offer.visibility != .hidden {
            appendPublishedContactLines(
                offer.contactInfo,
                standardPolicies: &standardPolicies
            )
        }
    }

    private static func appendPublishedContactLines(
        _ contact: ExchangeOffer.ContactInfo?,
        standardPolicies: inout [ExchangeStructuredOperatingMemory.PolicyRule]
    ) {
        guard let contact, !contact.isEmpty else { return }

        if let method = contact.preferredContactMethod {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer — preferred contact method",
                    details: method.rawValue
                )
            )
        }
        if let line = trim(contact.contactName) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer — contact name",
                    details: line
                )
            )
        }
        if let line = trim(contact.businessName) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer — business name",
                    details: line
                )
            )
        }
        if let line = trim(contact.email) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer — email",
                    details: line
                )
            )
        }
        if let line = trim(contact.phone) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer — phone",
                    details: line
                )
            )
        }
        if let line = trim(contact.website) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer — website",
                    details: line
                )
            )
        }
        if let line = trim(contact.availabilityNote) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer — availability note",
                    details: line
                )
            )
        }
        if let line = trim(contact.serviceAddressOrArea) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Offer — service area / address",
                    details: line
                )
            )
        }
    }

    private static func hydrateCommercialFacts(
        _ cf: ExchangeOffer.CommercialFacts,
        pricingRules: inout [ExchangeStructuredOperatingMemory.PricingRule],
        serviceItems: inout [ExchangeStructuredOperatingMemory.ServiceItem],
        coverageAreas: inout [ExchangeStructuredOperatingMemory.CoverageArea],
        availabilityWindows: inout [ExchangeStructuredOperatingMemory.AvailabilityWindow],
        standardPolicies: inout [ExchangeStructuredOperatingMemory.PolicyRule],
        requesterConstraints: inout [ExchangeStructuredOperatingMemory.RequesterConstraint]
    ) {
        guard cf.hasPublishedCommercialSurface else { return }

        if let pd = trim(cf.priceDisplay) {
            pricingRules.append(
                ExchangeStructuredOperatingMemory.PricingRule(
                    id: UUID(),
                    label: "Published price display",
                    amountDescription: pd,
                    notes: "From offer commercial surface v1.5."
                )
            )
        }

        if cf.priceMin != nil || cf.priceMax != nil || trim(cf.currency) != nil || trim(cf.priceUnit) != nil {
            var parts: [String] = []
            if let mn = cf.priceMin {
                parts.append("min \((mn as NSDecimalNumber).stringValue)")
            }
            if let mx = cf.priceMax {
                parts.append("max \((mx as NSDecimalNumber).stringValue)")
            }
            if let cur = trim(cf.currency) {
                parts.append("currency \(cur)")
            }
            if let unit = trim(cf.priceUnit) {
                parts.append("unit \(unit)")
            }
            let row = parts.joined(separator: " · ")
            if !row.isEmpty {
                pricingRules.append(
                    ExchangeStructuredOperatingMemory.PricingRule(
                        id: UUID(),
                        label: "Published price range / unit",
                        amountDescription: row,
                        notes: "Structured from offer commercial surface v1.5."
                    )
                )
            }
        }

        for pkg in cf.packages {
            let title = trim(pkg.title) ?? pkg.title
            var details: [String] = []
            if let s = trim(pkg.summary) {
                details.append(s)
            }
            if let p = trim(pkg.priceDisplay) {
                details.append("Price: \(p)")
            }
            serviceItems.append(
                ExchangeStructuredOperatingMemory.ServiceItem(
                    id: UUID(),
                    name: "Package: \(title)",
                    details: details.isEmpty ? nil : details.joined(separator: " · "),
                    isActive: true
                )
            )
        }

        if let san = trim(cf.serviceAreaNote) {
            coverageAreas.append(
                ExchangeStructuredOperatingMemory.CoverageArea(
                    id: UUID(),
                    name: "Service area (published)",
                    details: san
                )
            )
        }

        if let an = trim(cf.availabilityNote) {
            availabilityWindows.append(
                ExchangeStructuredOperatingMemory.AvailabilityWindow(
                    id: UUID(),
                    label: "Offer availability (published)",
                    details: an
                )
            )
        }

        if let me = trim(cf.minimumEngagement) {
            requesterConstraints.append(
                ExchangeStructuredOperatingMemory.RequesterConstraint(
                    id: UUID(),
                    key: "Minimum engagement",
                    value: me
                )
            )
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Minimum engagement (published)",
                    details: me
                )
            )
        }

        if let cp = trim(cf.cancellationPolicy) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Cancellation policy (published)",
                    details: cp
                )
            )
        }

        if let rp = trim(cf.refundPolicy) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Refund policy (published)",
                    details: rp
                )
            )
        }

        if let wp = trim(cf.warrantyPolicy) {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Warranty policy (published)",
                    details: wp
                )
            )
        }

        for input in cf.requiredBuyerInputs {
            guard let line = trim(input) else { continue }
            requesterConstraints.append(
                ExchangeStructuredOperatingMemory.RequesterConstraint(
                    id: UUID(),
                    key: "Seller asks you for",
                    value: line
                )
            )
        }

        for f in cf.faqs {
            let q = trim(f.question) ?? ""
            let a = trim(f.answer) ?? ""
            guard !q.isEmpty || !a.isEmpty else { continue }
            serviceItems.append(
                ExchangeStructuredOperatingMemory.ServiceItem(
                    id: UUID(),
                    name: "FAQ · \(q)",
                    details: a.isEmpty ? nil : a,
                    isActive: true
                )
            )
        }

        let posture = cf.resolvedAutoAnswerPolicy()
        let postureLines = """
        Pricing auto-answer: \(posture.canAnswerPricing ? "allowed" : "not allowed"); \
        Availability: \(posture.canAnswerAvailability ? "allowed" : "not allowed"); \
        Policies: \(posture.canAnswerPolicies ? "allowed" : "not allowed"); \
        Service area: \(posture.canAnswerServiceArea ? "allowed" : "not allowed"); \
        FAQs: \(posture.canAnswerFAQs ? "allowed" : "not allowed"); \
        Custom quotes need approval: \(posture.requiresApprovalForCustomQuote ? "yes" : "no").
        """
        standardPolicies.append(
            ExchangeStructuredOperatingMemory.PolicyRule(
                id: UUID(),
                title: "Public automation posture",
                details: postureLines.replacingOccurrences(of: "\n", with: " ")
            )
        )
    }

    private static func hydratePublicProfile(
        _ profile: ExchangePublicNodeProfile,
        serviceItems: inout [ExchangeStructuredOperatingMemory.ServiceItem],
        coverageAreas: inout [ExchangeStructuredOperatingMemory.CoverageArea],
        availabilityWindows: inout [ExchangeStructuredOperatingMemory.AvailabilityWindow],
        standardPolicies: inout [ExchangeStructuredOperatingMemory.PolicyRule],
        exclusions: inout [String],
        requesterConstraints: inout [ExchangeStructuredOperatingMemory.RequesterConstraint]
    ) {
        if let dn = trim(profile.displayName) {
            let detail = trim(profile.summary).map { summary in
                if let headline = trim(profile.headline) {
                    "\(headline). \(summary)"
                } else {
                    summary
                }
            } ?? trim(profile.headline)
            serviceItems.append(
                ExchangeStructuredOperatingMemory.ServiceItem(
                    id: UUID(),
                    name: dn,
                    details: detail,
                    isActive: true
                )
            )
        } else if let headline = trim(profile.headline) {
            serviceItems.append(
                ExchangeStructuredOperatingMemory.ServiceItem(
                    id: UUID(),
                    name: headline,
                    details: trim(profile.summary),
                    isActive: true
                )
            )
        }

        for region in profile.regionTags {
            guard let name = trim(region), !name.isEmpty else { continue }
            coverageAreas.append(
                ExchangeStructuredOperatingMemory.CoverageArea(
                    id: UUID(),
                    name: name,
                    details: "Region tag published on seller profile."
                )
            )
        }

        availabilityWindows.append(
            ExchangeStructuredOperatingMemory.AvailabilityWindow(
                id: UUID(),
                label: "Public availability posture",
                details: profile.availability.rawValue
            )
        )

        let r = profile.reachability
        let reachLine = """
        Published access mode: \(r.accessMode.rawValue). \
        Accepting inbound (published): \(r.acceptingInbound ? "yes" : "no"). \
        Disclosure ceiling: \(r.disclosureCeiling.rawValue). \
        Intent category policy: \(r.intentCategoryPolicy.rawValue). \
        Routeable-only: \(r.routeableOnly ? "yes" : "no").
        """
        standardPolicies.append(
            ExchangeStructuredOperatingMemory.PolicyRule(
                id: UUID(),
                title: "Public access mode",
                details: trim(reachLine.replacingOccurrences(of: "\n", with: " ")) ?? reachLine
            )
        )

        let interests = uniqSortedStrings(profile.interests.map { trim($0) }.compactMap { $0 })
        if !interests.isEmpty {
            requesterConstraints.append(
                ExchangeStructuredOperatingMemory.RequesterConstraint(
                    id: UUID(),
                    key: "Interests",
                    value: interests.joined(separator: "; ")
                )
            )
        }

        let offersList = uniqSortedStrings(profile.offers.map { trim($0) }.compactMap { $0 })
        if !offersList.isEmpty {
            requesterConstraints.append(
                ExchangeStructuredOperatingMemory.RequesterConstraint(
                    id: UUID(),
                    key: "Public offers listing",
                    value: offersList.joined(separator: "; ")
                )
            )
        }

        let openToVals = uniqSortedStrings(profile.openTo.map { trim($0) }.compactMap { $0 })
        if !openToVals.isEmpty {
            requesterConstraints.append(
                ExchangeStructuredOperatingMemory.RequesterConstraint(
                    id: UUID(),
                    key: "Open to receiving",
                    value: openToVals.joined(separator: "; ")
                )
            )
        }

        exclusions.append(contentsOf: profile.excludedTopics.compactMap { trim($0) })

        for tag in profile.activityTags {
            guard let t = trim(tag), !t.isEmpty else { continue }
            serviceItems.append(
                ExchangeStructuredOperatingMemory.ServiceItem(
                    id: UUID(),
                    name: t,
                    details: nil,
                    isActive: true
                )
            )
        }

        let domainLine = uniqSortedStrings(profile.semantic.domains.map { trim($0) }.compactMap { $0 }).joined(separator: ", ")
        let intentKinds = uniqSortedStrings(profile.semantic.intentKinds.map { trim($0) }.compactMap { $0 }).joined(separator: ", ")
        let audienceLine = profile.semantic.audienceKinds.map(\.rawValue).sorted().joined(separator: ", ")
        let modeLine = profile.semantic.fulfillmentModes.map(\.rawValue).sorted().joined(separator: ", ")
        let semanticPieces = [
            domainLine.isEmpty ? nil : "Domains: \(domainLine)",
            intentKinds.isEmpty ? nil : "Intent kinds: \(intentKinds)",
            audienceLine.isEmpty ? nil : "Audience kinds: \(audienceLine)",
            modeLine.isEmpty ? nil : "Fulfillment modes: \(modeLine)",
            trim(profile.semantic.notes).map { "Semantic notes: \($0)" }
        ].compactMap { $0 }

        if !semanticPieces.isEmpty {
            standardPolicies.append(
                ExchangeStructuredOperatingMemory.PolicyRule(
                    id: UUID(),
                    title: "Profile semantic posture",
                    details: semanticPieces.joined(separator: " • ")
                )
            )
        }
    }

    private static func dedupeLines(_ lines: [String]) -> [String] {
        uniqSortedStrings(lines)
    }

    private static func uniqSortedStrings(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        let trimmed = strings
            .compactMap { trim($0) }
            .filter { !$0.isEmpty }
        var ordered: [String] = []

        for s in trimmed {
            let lowered = s.lowercased()
            if seen.insert(lowered).inserted {
                ordered.append(s)
            }
        }

        return ordered
    }

    private static func trim(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private extension ExchangeOffer.Fulfillment.PricingMode {
    var displayLabel: String {
        switch self {
        case .fixed: return "Fixed"
        case .quoteRequired: return "Quote required"
        case .custom: return "Custom"
        case .undisclosed: return "Undisclosed"
        }
    }
}

private extension ExchangeOffer.Fulfillment.CommitmentMode {
    var displayLabel: String {
        switch self {
        case .exploratory: return "Exploratory"
        case .active: return "Active"
        case .approvalRequired: return "Approval required"
        }
    }
}
