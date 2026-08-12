import Foundation

/// Builds canonical separated provider display cards for For You (Phase 1).
public enum ExchangeProviderDisplayBuilder {

    public static func build(_ input: ExchangeProviderDisplayBuildInput) -> ExchangeProviderDisplayCard {
        let profile = input.publicProfile
        let offer = input.surfacedOffer
        let counterparty = input.counterparty
        let policy = input.policy

        let profileLines = buildProfileLines(profile: profile, policy: policy)
        let offerLines = buildOfferLines(offer: offer, policy: policy)
        let commercialLines = buildCommercialLines(
            offer: offer,
            policy: policy,
            includeBuyerInputs: true
        )

        let needsConfirmationLines: [ExchangeDisplayLine] = []

        let title = resolveTitle(profile: profile, counterparty: counterparty, offer: offer)
        let subtitle = resolveSubtitle(
            profile: profile,
            offer: offer,
            title: title
        )
        let imageURL = resolvePrimaryImageURL(
            profile: profile,
            offer: offer,
            surfaceLead: input.surfaceLead
        )
        let galleryURLs = resolveGalleryURLs(profile: profile, offer: offer, primary: imageURL)

        var completeness = ExchangeDisplayCompleteness(
            hasIdentity: !title.isEmpty,
            hasProfile: profile != nil && !profileLines.isEmpty,
            hasOffer: offer != nil && !offerLines.isEmpty,
            hasImage: imageURL != nil,
            hasCommercialFacts: offer?.commercialFacts.hasPublishedCommercialSurface == true,
            hasPricing: offer?.commercialFacts.hasAnyPublicPriceSignal == true,
            hasServiceArea: hasServiceAreaSignal(profile: profile, offer: offer),
            hasAvailability: hasAvailabilitySignal(profile: profile, offer: offer),
            isThinProfile: isThinProfile(profile: profile, profileLines: profileLines),
            isProfileOnlyHydrated: input.sourceSurface == .forYouCachedHydration
        )

        if offer == nil {
            completeness.hasOffer = false
            completeness.hasCommercialFacts = false
        }

        let badges = buildBadges(
            profile: profile,
            offer: offer,
            contactPosture: input.contactPosture,
            completeness: completeness,
            policy: policy
        )

        let previewLines = buildPreviewLines(
            profileLines: profileLines,
            offerLines: offerLines,
            policy: policy
        )

        let resolvedSurfaceLead = input.surfaceLead ?? ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: offer?.id,
            selectedPublicProfileID: profile?.id
        )
        let presentationContext = ExchangeProviderDetailsPresentationContextResolver.deriveForCandidate(
            surfaceLead: resolvedSurfaceLead,
            hasProfile: profile != nil,
            hasOffer: offer != nil
        )
        ExchangeProviderDetailsCardDebugLog.logPresentationContext(
            source: "forYou",
            presentationContext: presentationContext,
            lane: nil,
            queryIntentClass: nil,
            surfacePreference: nil,
            surfaceLead: resolvedSurfaceLead,
            selectedOfferID: offer?.id,
            selectedProfileID: profile?.id
        )

        let canonicalCard = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: profile,
                offer: offer,
                selectedOfferID: offer?.id,
                contextTitle: resolveTitle(profile: profile, counterparty: counterparty, offer: offer),
                presentationContext: presentationContext
            ),
            debugSource: "forYou"
        )
        let detailSections = canonicalCard.sections

        let legacyDetailSections = buildDetailSections(
            profileLines: profileLines,
            offerLines: offerLines,
            commercialLines: detailsSafeCommercialLines(commercialLines, source: "forYouDisplayDetailSections"),
            needsConfirmationLines: needsConfirmationLines
        )
        let resolvedDetailSections = detailSections.isEmpty ? legacyDetailSections : detailSections
        ExchangeProviderDetailsCardDebugLog.logSurfaceSelection(
            source: "forYou",
            usingCanonical: !detailSections.isEmpty,
            canonicalSectionCount: detailSections.count,
            legacyLineCount: legacyFallbackLineCount(
                profileLines: profileLines,
                offerLines: offerLines,
                commercialLines: commercialLines,
                needsConfirmationLines: needsConfirmationLines
            )
        )

        let diagnostics = ExchangeProviderDisplayDiagnostics(
            sourceSurface: input.sourceSurface,
            hadCanonicalProfile: profile != nil,
            hadCanonicalOffer: offer != nil,
            hadCommercialFacts: offer?.commercialFacts.hasPublishedCommercialSurface == true,
            missingReason: diagnosticsMissingReason(
                input: input,
                completeness: completeness
            )
        )

        return ExchangeProviderDisplayCard(
            title: title,
            subtitle: subtitle,
            imageURL: imageURL,
            galleryImageURLs: galleryURLs,
            badges: badges,
            previewLines: previewLines,
            profileLines: profileLines,
            offerLines: offerLines,
            commercialLines: commercialLines,
            needsConfirmationLines: needsConfirmationLines,
            detailSections: resolvedDetailSections,
            completeness: completeness,
            diagnostics: diagnostics
        )
    }

    // MARK: - Profile lines

    private static func buildProfileLines(
        profile: ExchangePublicNodeProfile?,
        policy: ExchangeProviderDisplayPolicy
    ) -> [ExchangeDisplayLine] {
        guard let profile else { return [] }

        var candidates: [(String, String, ExchangeDisplayLineImportance)] = []

        if let summary = trimmed(profile.summary) {
            candidates.append(("about", "About: \(summary)", .high))
        } else if let headline = trimmed(profile.headline) {
            candidates.append(("headline", headline, .high))
        }

        if let openTo = labeledList(label: "Open to", values: profile.openTo) {
            candidates.append(("openTo", openTo, .normal))
        }
        if let interests = labeledList(label: "Interests", values: profile.interests) {
            candidates.append(("interests", interests, .normal))
        }
        if let roles = labeledList(label: "Roles", values: profile.activityTags) {
            candidates.append(("roles", roles, .normal))
        }
        if let regions = labeledList(label: "Region", values: profile.regionTags) {
            candidates.append(("regions", regions, .normal))
        }
        if let offers = labeledList(label: "Offers", values: profile.offers) {
            candidates.append(("profileOffers", offers, .normal))
        }

        return capLines(
            candidates.compactMap { key, text, importance in
                guard let accepted = ExchangeProviderDisplayCopyGate.acceptsUserFacingLine(text) else {
                    return nil
                }
                return line(
                    accepted,
                    source: .providerProfile,
                    group: .profile,
                    fieldKey: key,
                    importance: importance
                )
            },
            max: policy.maxProfileLines
        )
    }

    // MARK: - Offer lines (non-commercial)

    private static func buildOfferLines(
        offer: ExchangeOffer?,
        policy: ExchangeProviderDisplayPolicy
    ) -> [ExchangeDisplayLine] {
        guard let offer else { return [] }

        var candidates: [(String, String, ExchangeDisplayLineImportance)] = []

        let title = trimmed(offer.title)
        if let title {
            candidates.append(("offerTitle", title, .high))
        }
        if let summary = trimmed(offer.summary), summary != title {
            candidates.append(("offerSummary", summary, .high))
        }
        if let category = trimmed(offer.category) {
            candidates.append(("category", category, .normal))
        }
        if let tags = labeledList(label: "Tags", values: offer.tags) {
            candidates.append(("tags", tags, .normal))
        }

        let areaLabels = offer.effectiveServiceAreas.map(\.displayName).filter { !$0.isEmpty }
        if areaLabels.isEmpty, !offer.regionTags.isEmpty {
            if let regions = labeledList(label: "Area", values: offer.regionTags) {
                candidates.append(("regions", regions, .normal))
            }
        } else if let areas = labeledList(label: "Area", values: areaLabels) {
            candidates.append(("serviceAreas", areas, .normal))
        }

        if let lead = trimmed(offer.fulfillment.leadTimeNote) {
            candidates.append(("leadTime", "Lead time: \(lead)", .normal))
        }
        if let capacity = trimmed(offer.fulfillment.capacityNote) {
            candidates.append(("capacity", "Capacity: \(capacity)", .normal))
        }

        return capLines(
            candidates.compactMap { key, text, importance in
                guard let accepted = ExchangeProviderDisplayCopyGate.acceptsUserFacingLine(text) else {
                    return nil
                }
                return line(
                    accepted,
                    source: .providerOffer,
                    group: .offer,
                    fieldKey: key,
                    importance: importance
                )
            },
            max: policy.maxOfferLines
        )
    }

    // MARK: - Commercial / details lines

    private static func buildCommercialLines(
        offer: ExchangeOffer?,
        policy: ExchangeProviderDisplayPolicy,
        includeBuyerInputs: Bool
    ) -> [ExchangeDisplayLine] {
        guard policy.allowCommercialFacts, let offer else { return [] }

        var out: [ExchangeDisplayLine] = []

        if offer.commercialFacts.hasPublishedCommercialSurface {
            let skimLines = ExchangeProviderDetailsLegacyLineGate.filterCommercialSkimLines(
                offer.commercialSurfaceSkimLines,
                source: "forYouDisplayCommercial"
            )
            for skim in skimLines.prefix(12) {
                guard let accepted = ExchangeProviderDisplayCopyGate.acceptsUserFacingLine(skim) else {
                    continue
                }
                out.append(
                    line(
                        accepted,
                        source: .commercialFact,
                        group: .commercial,
                        fieldKey: "commercialSkim",
                        importance: .normal
                    )
                )
            }
        }

        out.append(contentsOf: contactSummaryLines(offer.contactInfo))

        if includeBuyerInputs {
            for raw in offer.commercialFacts.requiredBuyerInputs {
                guard let hint = trimmed(raw) else { continue }
                let text = "May need from you: \(hint)"
                guard let accepted = ExchangeProviderDisplayCopyGate.acceptsUserFacingLine(text) else {
                    continue
                }
                out.append(
                    line(
                        accepted,
                        source: .commercialFact,
                        group: .commercial,
                        fieldKey: "requiredBuyerInput",
                        importance: .normal
                    )
                )
            }
        }

        return capLines(out, max: policy.maxCommercialLines)
    }

    private static func contactSummaryLines(
        _ contact: ExchangeOffer.ContactInfo?
    ) -> [ExchangeDisplayLine] {
        guard let contact else { return [] }
        var rows: [String] = []
        if let email = trimmed(contact.email) { rows.append("Email: \(email)") }
        if let phone = trimmed(contact.phone) { rows.append("Phone: \(phone)") }
        if let website = trimmed(contact.website) { rows.append("Website: \(website)") }
        if let note = trimmed(contact.availabilityNote) { rows.append("Contact hours: \(note)") }

        return rows.compactMap { raw in
            guard let accepted = ExchangeProviderDisplayCopyGate.acceptsUserFacingLine(raw) else {
                return nil
            }
            return line(
                accepted,
                source: .commercialFact,
                group: .commercial,
                fieldKey: "contactInfo",
                importance: .low
            )
        }
    }

    // MARK: - Card-level slots

    private static func resolveTitle(
        profile: ExchangePublicNodeProfile?,
        counterparty: ExchangeCounterparty?,
        offer: ExchangeOffer?
    ) -> String {
        if let name = trimmed(profile?.displayName) {
            return name
        }
        if let name = trimmed(counterparty?.displayName) {
            return name
        }
        if let title = trimmed(offer?.title) {
            return title
        }
        return "Public profile"
    }

    private static func resolveSubtitle(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        title: String
    ) -> String? {
        let titleNorm = normalizeKey(title)

        if let offerTitle = trimmed(offer?.title), normalizeKey(offerTitle) != titleNorm {
            return offerTitle
        }
        if let headline = trimmed(profile?.headline), normalizeKey(headline) != titleNorm {
            return headline
        }
        if let summary = trimmed(offer?.summary) {
            return summary
        }
        if let profileSummary = trimmed(profile?.summary) {
            return profileSummary
        }
        if let firstOffer = profile?.offers.first.flatMap({ trimmed($0) }) {
            return firstOffer
        }
        return nil
    }

    private static func resolvePrimaryImageURL(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        surfaceLead: ExchangePresentationSurfaceLead?
    ) -> String? {
        let lead = surfaceLead ?? ExchangePresentationSurfaceLead.resolve(
            selectedOfferID: offer?.id,
            selectedPublicProfileID: profile?.id
        )

        switch lead {
        case .offerLed:
            return trimmed(offer?.primaryImageURL)
                ?? offer?.normalizedPublicOfferImageURLs().first
                ?? trimmed(profile?.primaryImageURL)
        case .profileLed:
            return trimmed(profile?.primaryImageURL)
                ?? trimmed(offer?.primaryImageURL)
                ?? offer?.normalizedPublicOfferImageURLs().first
        case .ambiguous:
            return trimmed(offer?.primaryImageURL)
                ?? offer?.normalizedPublicOfferImageURLs().first
                ?? trimmed(profile?.primaryImageURL)
        }
    }

    private static func resolveGalleryURLs(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        primary: String?
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let t = trimmed(raw) else { return }
            let key = t.lowercased()
            guard seen.insert(key).inserted else { return }
            ordered.append(t)
        }

        append(primary)
        for url in offer?.normalizedPublicOfferImageURLs() ?? [] {
            append(url)
            if ordered.count >= ExchangeOffer.maxPublicOfferImageCount { break }
        }
        append(profile?.primaryImageURL)

        return Array(ordered.prefix(ExchangeOffer.maxPublicOfferImageCount))
    }

    // MARK: - Badges

    private static func buildBadges(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?,
        contactPosture: ExchangeProviderDisplayContactPosture?,
        completeness: ExchangeDisplayCompleteness,
        policy: ExchangeProviderDisplayPolicy
    ) -> [ExchangeDisplayBadge] {
        var badges: [ExchangeDisplayBadge] = []
        var seen = Set<String>()

        func appendBadge(_ label: String, source: ExchangeDisplaySource, fieldKey: String) {
            guard badges.count < policy.maxBadges else { return }
            guard let clean = ExchangeProviderDisplayCopyGate.acceptsBadgeLabel(label) else { return }
            let key = clean.lowercased()
            guard seen.insert(key).inserted else { return }
            badges.append(ExchangeDisplayBadge(label: clean, source: source, fieldKey: fieldKey))
        }

        if let posture = contactPosture {
            if posture.requiresIntroduction {
                appendBadge("Introduction preferred", source: .providerProfile, fieldKey: "reachability")
            } else if posture.allowsDirectContact && posture.acceptingInbound {
                appendBadge("Open to contact", source: .providerProfile, fieldKey: "reachability")
            }
        } else if let profile {
            switch profile.reachability.accessMode {
            case .introRequired, .introPreferred:
                appendBadge("Introduction preferred", source: .providerProfile, fieldKey: "reachability")
            case .direct where profile.reachability.acceptingInbound:
                appendBadge("Open to contact", source: .providerProfile, fieldKey: "reachability")
            default:
                break
            }
        }

        if profile?.availability == .open {
            appendBadge("Available", source: .providerProfile, fieldKey: "availability")
        }

        if completeness.hasServiceArea {
            appendBadge("Local", source: .providerOffer, fieldKey: "serviceArea")
        }

        if completeness.hasPricing {
            appendBadge("Price listed", source: .commercialFact, fieldKey: "pricing")
        }

        if completeness.isThinProfile {
            appendBadge("Details limited", source: .missingFact, fieldKey: "thinProfile")
        }

        if let category = trimmed(offer?.category) {
            if let badge = ExchangeProviderDisplayCopyGate.acceptsCategoryBadge(category) {
                appendBadge(badge, source: .providerOffer, fieldKey: "category")
            }
        } else if let tag = profile?.activityTags.first {
            if let badge = ExchangeProviderDisplayCopyGate.acceptsCategoryBadge(tag) {
                appendBadge(badge, source: .providerProfile, fieldKey: "activityTag")
            }
        }

        return badges
    }

    // MARK: - Preview + sections

    private static func buildPreviewLines(
        profileLines: [ExchangeDisplayLine],
        offerLines: [ExchangeDisplayLine],
        policy: ExchangeProviderDisplayPolicy
    ) -> [ExchangeDisplayLine] {
        var pool: [ExchangeDisplayLine] = []
        pool.append(contentsOf: profileLines.filter { $0.importance == .high })
        pool.append(contentsOf: profileLines.filter { $0.importance != .high })
        pool.append(contentsOf: offerLines.filter { $0.importance == .high })
        pool.append(contentsOf: offerLines.filter { $0.importance != .high })

        var seen = Set<String>()
        var out: [ExchangeDisplayLine] = []
        for line in pool {
            let key = normalizeKey(line.text)
            guard seen.insert(key).inserted else { continue }
            out.append(line)
            if out.count >= policy.maxPreviewLines { break }
        }
        return out
    }

    private static func legacyFallbackLineCount(
        profileLines: [ExchangeDisplayLine],
        offerLines: [ExchangeDisplayLine],
        commercialLines: [ExchangeDisplayLine],
        needsConfirmationLines: [ExchangeDisplayLine]
    ) -> Int {
        profileLines.count + offerLines.count + commercialLines.count + needsConfirmationLines.count
    }

    private static func buildDetailSections(
        profileLines: [ExchangeDisplayLine],
        offerLines: [ExchangeDisplayLine],
        commercialLines: [ExchangeDisplayLine],
        needsConfirmationLines: [ExchangeDisplayLine]
    ) -> [ExchangeDisplaySection] {
        var sections: [ExchangeDisplaySection] = []
        if !profileLines.isEmpty {
            sections.append(
                ExchangeDisplaySection(
                    title: "Public profile",
                    sourceGroup: .profile,
                    lines: profileLines
                )
            )
        }
        if !offerLines.isEmpty {
            sections.append(
                ExchangeDisplaySection(
                    title: "Offer",
                    sourceGroup: .offer,
                    lines: offerLines
                )
            )
        }
        if !commercialLines.isEmpty {
            sections.append(
                ExchangeDisplaySection(
                    title: "Details",
                    sourceGroup: .commercial,
                    lines: commercialLines
                )
            )
        }
        if !needsConfirmationLines.isEmpty {
            sections.append(
                ExchangeDisplaySection(
                    title: "Needs confirmation",
                    sourceGroup: .needsConfirmation,
                    lines: needsConfirmationLines
                )
            )
        }
        return sections
    }

    // MARK: - Helpers

    private static func line(
        _ text: String,
        source: ExchangeDisplaySource,
        group: ExchangeDisplaySourceGroup,
        fieldKey: String?,
        importance: ExchangeDisplayLineImportance
    ) -> ExchangeDisplayLine {
        ExchangeDisplayLine(
            text: text,
            source: source,
            sourceGroup: group,
            fieldKey: fieldKey,
            importance: importance
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

    private static func normalizeKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func detailsSafeCommercialLines(
        _ lines: [ExchangeDisplayLine],
        source: String
    ) -> [ExchangeDisplayLine] {
        lines.filter { line in
            guard ExchangeProviderDetailsLegacyLineGate.allowsDetailsFallbackLine(line.text) else {
                if let category = ExchangeProviderDetailsLegacyLineGate.suppressionCategory(for: line.text) {
                    #if DEBUG
                    print(
                        "[ProviderDetailsCard][legacyGate] source=\(source) " +
                        "suppressed=\(category.rawValue) reason=synthesizedFulfillmentNotDetailsSafe"
                    )
                    #endif
                }
                return false
            }
            return true
        }
    }

    private static func fulfillmentPostureLine(_ fulfillment: ExchangeOffer.Fulfillment) -> String? {
        let pricing: String? = switch fulfillment.pricingMode {
        case .fixed: "Fixed pricing"
        case .quoteRequired: "Quote on request"
        case .custom: "Custom pricing"
        case .undisclosed: nil
        }
        let commitment: String? = switch fulfillment.commitmentMode {
        case .exploratory: "Exploratory commitment"
        case .active: "Active commitment"
        case .approvalRequired: "Approval required"
        }
        var parts: [String] = []
        if let pricing { parts.append(pricing) }
        if let commitment { parts.append(commitment) }
        if fulfillment.remoteFriendly {
            parts.append("Remote-friendly")
        } else {
            parts.append("On-site leaning")
        }
        let joined = parts.joined(separator: " · ")
        return ExchangeProviderDisplayCopyGate.acceptsUserFacingLine(joined)
    }

    private static func hasServiceAreaSignal(
        profile: ExchangePublicNodeProfile?,
        offer: ExchangeOffer?
    ) -> Bool {
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
        if profile?.availability == .open { return true }
        if let note = offer?.commercialFacts.availabilityNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return true
        }
        if let note = offer?.contactInfo?.availabilityNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return true
        }
        return false
    }

    private static func isThinProfile(
        profile: ExchangePublicNodeProfile?,
        profileLines: [ExchangeDisplayLine]
    ) -> Bool {
        guard profile != nil else { return true }
        let hasAbout = profileLines.contains { $0.fieldKey == "about" || $0.fieldKey == "headline" }
        let hasTags = profileLines.count >= 2
        return !hasAbout && !hasTags
    }

    private static func diagnosticsMissingReason(
        input: ExchangeProviderDisplayBuildInput,
        completeness: ExchangeDisplayCompleteness
    ) -> String? {
        if input.sourceSurface == .forYouCachedHydration && !completeness.hasOffer {
            return "cached_profile_only"
        }
        if completeness.isThinProfile {
            return "thin_profile"
        }
        return nil
    }
}
