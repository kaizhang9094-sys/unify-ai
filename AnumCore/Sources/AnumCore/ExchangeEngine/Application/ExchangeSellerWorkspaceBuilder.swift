import Foundation

/// Builds seller-facing app projections from durable Exchange domain records.
///
/// Seller workspace is publication-owned, not interaction-owned.
/// Root objects:
/// - public profile
/// - offers
/// - publication state
///
/// Not:
/// - counterparty
public struct ExchangeSellerWorkspaceBuilder: Sendable {
    private let publicationService: any ExchangePublicationService
    private let sellerSurfaceService: any ExchangeSellerSurfaceService

    public init(
        publicationService: any ExchangePublicationService = ExchangeDefaultPublicationService(),
        sellerSurfaceService: any ExchangeSellerSurfaceService = ExchangeDefaultSellerSurfaceService()
    ) {
        self.publicationService = publicationService
        self.sellerSurfaceService = sellerSurfaceService
    }

    public func buildWorkspaceSummary(
        ownerDisplayName: String?,
        publicProfile: ExchangePublicNodeProfile?,
        offers: [ExchangeOffer],
        publicationState: ExchangePublicationState?
    ) -> ExchangeModels.SellerWorkspaceSummary {
        let validationIssues = sellerSurfaceService.validateSurface(
            publicProfile: publicProfile,
            offers: offers
        )

        let readiness = publicationService.evaluateReadiness(
            publicProfile: publicProfile,
            offers: offers,
            publicationState: publicationState,
            validationIssues: validationIssues
        )

        let offerViews = offers
            .map { buildOfferView($0) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.displayTitle < rhs.displayTitle
            }

        let activeOfferCount = offers.filter { $0.status == .active }.count
        let draftOfferCount = offers.filter { $0.status == .draft }.count
        let pausedOfferCount = offers.filter { $0.status == .paused }.count
        let archivedOfferCount = offers.filter { $0.status == .archived }.count
        let visibleOfferCount = offers.filter { $0.visibility != .hidden }.count

        let publicProfileView = publicProfile.map {
            buildPublicProfileView(
                profile: $0,
                ownerDisplayName: ownerDisplayName,
                publicationState: publicationState,
                activeOfferCount: activeOfferCount,
                visibleOfferCount: visibleOfferCount
            )
        }

        return ExchangeModels.SellerWorkspaceSummary(
            ownerDisplayName: ownerDisplayName?.nilIfBlank,
            publicProfile: publicProfileView,
            offers: offerViews,
            publicationState: publicationState,
            activeOfferCount: activeOfferCount,
            draftOfferCount: draftOfferCount,
            pausedOfferCount: pausedOfferCount,
            archivedOfferCount: archivedOfferCount,
            needsPublicationAttention: readiness.nextAction != .manageLiveSurface,
            statusLine: readiness.statusLine,
            nextStepText: readiness.nextStepText,
            lastPublishedAt: publicationState?.publishedAt,
            publicationBadgeText: publicationBadgeText(
                publicationState: publicationState,
                validationIssues: validationIssues,
                offers: offers,
                publicProfile: publicProfile
            ),
            publicationDetailLine: publicationDetailLine(
                readiness: readiness,
                publicationState: publicationState,
                validationIssues: validationIssues,
                offers: offers,
                publicProfile: publicProfile
            ),
            discoverabilityLine: discoverabilityLine(
                publicProfile: publicProfile,
                visibleOfferCount: visibleOfferCount
            ),
            primaryCTAHint: primaryCTAHint(
                publicationState: publicationState,
                validationIssues: validationIssues,
                offers: offers,
                publicProfile: publicProfile
            )
        )
    }

    public func buildPublicProfileView(
        profile: ExchangePublicNodeProfile,
        ownerDisplayName: String?,
        publicationState: ExchangePublicationState?,
        activeOfferCount: Int,
        visibleOfferCount: Int
    ) -> ExchangeModels.PublicProfileView {
        let displayName =
            profile.displayName?.nilIfBlank
            ?? ownerDisplayName?.nilIfBlank
            ?? "Unnamed Profile"

        let cleanedSummary = profile.summary?.nilIfBlank
        let cleanedHeadline = profile.headline?.nilIfBlank
        let introLine = cleanedHeadline ?? cleanedSummary

        let openToItems = cleanedItems(profile.openTo)
        let offerItems = cleanedItems(profile.offers)
        let interestItems = cleanedItems(profile.interests)
        let activityItems = cleanedItems(profile.activityTags)
        let regionItems = cleanedItems(profile.regionTags)

        return ExchangeModels.PublicProfileView(
            profile: profile,
            displayName: displayName,
            headline: cleanedHeadline,
            summary: cleanedSummary,
            summaryLine: publicProfileSummaryLine(
                profile: profile,
                displayName: displayName,
                visibleOfferCount: visibleOfferCount
            ),
            publicIntroLine: introLine,
            discoverabilityLine: publicProfileDiscoverabilityLine(
                profile: profile,
                visibleOfferCount: visibleOfferCount
            ),
            publicationStatus: publicationState?.status,
            publicationStatusText: publicationStatusText(publicationState?.status),
            publicationBadgeText: publicProfilePublicationBadgeText(publicationState?.status),
            publicationDetailLine: publicProfilePublicationDetailLine(
                publicationState: publicationState,
                visibleOfferCount: visibleOfferCount
            ),
            lastPublishedAt: publicationState?.publishedAt,
            activeOfferCount: activeOfferCount,
            visibleOfferCount: visibleOfferCount,
            openToItems: openToItems,
            offerItems: offerItems,
            interestItems: interestItems,
            activityItems: activityItems,
            regionItems: regionItems,
            openToLine: joinedPreview(openToItems),
            offerLine: joinedPreview(offerItems),
            interestLine: joinedPreview(interestItems),
            activityLine: joinedPreview(activityItems),
            regionLine: joinedPreview(regionItems)
        )
    }

    public func buildOfferView(_ offer: ExchangeOffer) -> ExchangeModels.OfferView {
        ExchangeModels.OfferView(
            offer: offer,
            displayTitle: offer.title,
            subtitle: offer.summary?.nilIfBlank
                ?? offer.category?.nilIfBlank
                ?? offer.semantic.notes?.nilIfBlank,
            statusText: offerStatusText(offer.status),
            visibilityText: offerVisibilityText(offer.visibility),
            fulfillmentText: offerFulfillmentText(offer.fulfillment),
            priceText: offerPriceText(offer),
            regionText: offerRegionText(offer),
            tagLine: offer.tags.isEmpty ? nil : offer.tags.prefix(3).joined(separator: " · "),
            contactSummary: offerContactSummary(offer),
            updatedAt: offer.updatedAt
        )
    }
}

private extension ExchangeSellerWorkspaceBuilder {
    func publicationStatusText(_ status: ExchangePublicationState.Status?) -> String? {
        guard let status else { return nil }

        switch status {
        case .draft: return "Draft"
        case .pendingPublish: return "Publishing"
        case .published: return "Published"
        case .stale: return "Needs Republish"
        case .paused: return "Paused"
        case .pendingUnpublish: return "Unpublishing"
        case .archived: return "Archived"
        case .failed: return "Failed"
        }
    }

    func publicationBadgeText(
        publicationState: ExchangePublicationState?,
        validationIssues: [ExchangeSellerValidationIssue],
        offers: [ExchangeOffer],
        publicProfile: ExchangePublicNodeProfile?
    ) -> String {
        if publicProfile == nil {
            return "Setup"
        }

        if !validationIssues.isEmpty {
            return "Needs Work"
        }

        if offers.isEmpty {
            return "Add Offer"
        }

        switch publicationState?.status {
        case .draft:
            return "Ready"
        case .pendingPublish:
            return "Publishing"
        case .published:
            return "Live"
        case .stale:
            return "Update Needed"
        case .paused:
            return "Paused"
        case .pendingUnpublish:
            return "Withdrawing"
        case .archived:
            return "Archived"
        case .failed:
            return "Failed"
        case .none:
            return "Ready"
        }
    }

    func publicationDetailLine(
        readiness: ExchangePublicationReadiness,
        publicationState: ExchangePublicationState?,
        validationIssues: [ExchangeSellerValidationIssue],
        offers: [ExchangeOffer],
        publicProfile: ExchangePublicNodeProfile?
    ) -> String? {
        if publicProfile == nil {
            return "Start with a public profile so your secretary has a legible outward-facing introduction."
        }

        if !validationIssues.isEmpty {
            if let first = validationIssues.first?.summary.nilIfBlank {
                return first
            }
            return readiness.nextStepText?.nilIfBlank
        }

        if offers.isEmpty {
            return "Your profile exists, but nothing concrete is available outward yet."
        }

        if let next = readiness.nextStepText?.nilIfBlank {
            return next
        }

        switch publicationState?.status {
        case .draft:
            return "Your surface is shaped and can be published when ready."
        case .pendingPublish:
            return "Your surface is currently being published."
        case .published:
            return "Your public surface is live and discoverable."
        case .stale:
            return "Your surface changed and needs republishing."
        case .paused:
            return "Your surface is paused."
        case .pendingUnpublish:
            return "Your surface is being withdrawn."
        case .archived:
            return "Your surface is archived."
        case .failed:
            return "The last publication attempt failed."
        case .none:
            return readiness.statusLine.nilIfBlank
        }
    }

    func discoverabilityLine(
        publicProfile: ExchangePublicNodeProfile?,
        visibleOfferCount: Int
    ) -> String? {
        guard let publicProfile else { return nil }

        let visibility = publicProfile.visibility.rawValue
        let availability = publicProfile.availability.rawValue

        if visibleOfferCount > 0 {
            return "\(visibleOfferCount) visible offering\(visibleOfferCount == 1 ? "" : "s") · \(visibility.capitalized) · \(availability.capitalized)"
        }

        return "\(visibility.capitalized) · \(availability.capitalized)"
    }

    func primaryCTAHint(
        publicationState: ExchangePublicationState?,
        validationIssues: [ExchangeSellerValidationIssue],
        offers: [ExchangeOffer],
        publicProfile: ExchangePublicNodeProfile?
    ) -> String? {
        if publicProfile == nil {
            return "Create public surface"
        }

        if !validationIssues.isEmpty {
            return "Fix surface"
        }

        if offers.isEmpty {
            return "Add your offering"
        }

        switch publicationState?.status {
        case .draft, .stale, .failed:
            return "Publish surface"
        case .pendingPublish:
            return "Publishing"
        case .paused:
            return "Resume surface"
        case .pendingUnpublish:
            return "Withdrawing"
        case .archived:
            return "Restore surface"
        case .published:
            return "Manage surface"
        case .none:
            return "Manage surface"
        }
    }

    func publicProfileSummaryLine(
        profile: ExchangePublicNodeProfile,
        displayName: String,
        visibleOfferCount: Int
    ) -> String? {
        if let summary = profile.summary?.nilIfBlank {
            return summary
        }

        if let headline = profile.headline?.nilIfBlank {
            return headline
        }

        if visibleOfferCount > 0 {
            return "\(displayName) currently has \(visibleOfferCount) visible offering\(visibleOfferCount == 1 ? "" : "s")."
        }

        return nil
    }

    func publicProfileDiscoverabilityLine(
        profile: ExchangePublicNodeProfile,
        visibleOfferCount: Int
    ) -> String? {
        let visibility = profile.visibility.rawValue.capitalized
        let availability = profile.availability.rawValue.capitalized

        if visibleOfferCount > 0 {
            return "\(visibility) · \(availability) · \(visibleOfferCount) visible offering\(visibleOfferCount == 1 ? "" : "s")"
        }

        return "\(visibility) · \(availability)"
    }

    func publicProfilePublicationBadgeText(
        _ status: ExchangePublicationState.Status?
    ) -> String? {
        guard let status else { return nil }

        switch status {
        case .draft:
            return "Ready"
        case .pendingPublish:
            return "Publishing"
        case .published:
            return "Live"
        case .stale:
            return "Update Needed"
        case .paused:
            return "Paused"
        case .pendingUnpublish:
            return "Withdrawing"
        case .archived:
            return "Archived"
        case .failed:
            return "Failed"
        }
    }

    func publicProfilePublicationDetailLine(
        publicationState: ExchangePublicationState?,
        visibleOfferCount: Int
    ) -> String? {
        switch publicationState?.status {
        case .draft:
            return "Saved locally and ready to publish."
        case .pendingPublish:
            return "Publication is in progress."
        case .published:
            return visibleOfferCount > 0
                ? "Published and outwardly visible."
                : "Published, but no visible offers are attached yet."
        case .stale:
            return "Changed since the last publish and needs republishing."
        case .paused:
            return "Currently paused."
        case .pendingUnpublish:
            return "Being withdrawn from discovery."
        case .archived:
            return "Archived and no longer active."
        case .failed:
            return "The last publish attempt failed."
        case .none:
            return nil
        }
    }

    func offerStatusText(_ status: ExchangeOffer.Status) -> String {
        switch status {
        case .draft: return "Draft"
        case .active: return "Active"
        case .paused: return "Paused"
        case .archived: return "Archived"
        }
    }

    func offerVisibilityText(_ visibility: ExchangeOffer.Visibility) -> String {
        switch visibility.rawValue.lowercased() {
        case "public", "publicdiscoverable":
            return "Public"
        case "limited", "limitedsurface":
            return "Limited"
        case "hidden", "privateonly":
            return "Hidden"
        default:
            return visibility.rawValue.capitalized
        }
    }

    func offerFulfillmentText(_ fulfillment: ExchangeOffer.Fulfillment) -> String {
        let semanticModes = fulfillmentSummaryModes(from: fulfillment)

        if !semanticModes.isEmpty {
            return semanticModes.joined(separator: " · ")
        }

        if fulfillment.remoteFriendly {
            return "Remote friendly"
        }

        switch fulfillment.commitmentMode {
        case .exploratory:
            return "Exploratory"
        case .active:
            return "Active"
        case .approvalRequired:
            return "Approval required"
        }
    }

    func fulfillmentSummaryModes(from fulfillment: ExchangeOffer.Fulfillment) -> [String] {
        var parts: [String] = []

        if fulfillment.remoteFriendly {
            parts.append("Remote friendly")
        }

        switch fulfillment.pricingMode {
        case .fixed:
            parts.append("Fixed price")
        case .quoteRequired:
            parts.append("Quote required")
        case .custom:
            parts.append("Custom pricing")
        case .undisclosed:
            break
        }

        return parts
    }

    func offerPriceText(_ offer: ExchangeOffer) -> String? {
        switch offer.fulfillment.pricingMode {
        case .fixed:
            return "Fixed price"
        case .quoteRequired:
            return "Quote required"
        case .custom:
            return "Custom pricing"
        case .undisclosed:
            return nil
        }
    }

    func offerRegionText(_ offer: ExchangeOffer) -> String? {
        guard !offer.regionTags.isEmpty else { return nil }
        return offer.regionTags.prefix(3).joined(separator: " · ")
    }

    func offerContactSummary(_ offer: ExchangeOffer) -> String? {
        guard let contact = offer.contactInfo?.normalized(), !contact.isEmpty else { return nil }

        var parts: [String] = []
        if let method = contact.preferredContactMethod?.rawValue {
            parts.append("Preferred: \(method.capitalized)")
        }
        if let email = contact.email?.nilIfBlank {
            parts.append(email)
        } else if let phone = contact.phone?.nilIfBlank {
            parts.append(phone)
        } else if let website = contact.website?.nilIfBlank {
            parts.append(website)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func cleanedItems(_ items: [String]) -> [String] {
        items.compactMap { $0.nilIfBlank }
    }

    func joinedPreview(_ items: [String], limit: Int = 3) -> String? {
        guard !items.isEmpty else { return nil }
        return items.prefix(limit).joined(separator: " · ").nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
