import Foundation

/// Maps social discovery thread state into the shared public-profile detail presentation shape.
public enum SocialDiscoveryProfileProjection {
    public static func forYouItem(
        from detail: ExchangeModels.ThreadDetail,
        supplementalImageURLs: [String] = [],
        now: Date = Date()
    ) -> ExchangeModels.ForYouItem {
        let match = detail.selectedMatch ?? detail.matches.first
        let counterparty = detail.selectedCounterparty
            ?? detail.counterparties.first(where: { $0.id == detail.thread.selectedCounterpartyID })
            ?? detail.counterparties.first

        let nodeID = trimmed(
            counterparty?.id
                ?? detail.thread.selectedCounterpartyID
                ?? match?.counterpartyID
        ) ?? "unknown"

        let publicProfile = counterparty?.publicProfile
        let publicProfileID = trimmed(
            detail.selectedPublicProfileID
                ?? publicProfile?.id
                ?? match?.publicProfileID
                ?? match?.metadata["public_profile_id"]
        )

        let displayName = trimmed(
            counterparty?.displayName
                ?? match?.metadata["public_profile_display_name"]
                ?? match?.metadata["counterparty_name"]
                ?? detail.thread.selectedCounterpartyID
        ) ?? "Profile"

        let headline = trimmed(
            publicProfile?.headline
                ?? publicProfile?.summary
                ?? match?.metadata["public_profile_headline"]
                ?? match?.metadata["public_profile_summary"]
        )

        let matchReasonSummary = trimmed(
            detail.thread.selectedMatchRationale
                ?? match?.recommendation
                ?? matchReasonLine(from: match)
        )

        let discoveryFactLines = buildDiscoveryFactLines(
            match: match,
            publicProfile: publicProfile,
            semanticTags: detail.semanticTags
        )

        let publicFactLines = buildPublicFactLines(
            match: match,
            publicProfile: publicProfile
        )

        let dominantTags = normalizedTags(
            publicProfile?.activityTags
                ?? commaSeparatedList(match?.metadata["public_profile_activity_tags"])
                + detail.semanticTags
        )

        let primaryImageURL = resolvePrimaryImageURL(
            publicProfile: publicProfile,
            supplementalImageURLs: supplementalImageURLs
        )

        let accessMode = trimmed(
            publicProfile?.reachability.accessMode.rawValue
                ?? match?.metadata["public_profile_access_mode"]
        ) ?? "unknown"

        let acceptingInbound = publicProfile?.reachability.acceptingInbound ?? true
        let canAutonomouslyContact = publicProfile?.allowsDirectContactInPrinciple ?? false

        var item = ExchangeModels.ForYouItem(
            id: nodeID,
            displayName: displayName,
            headline: headline,
            matchReasonSummary: matchReasonSummary,
            accessMode: accessMode,
            dominantTags: dominantTags,
            topOfferTitle: nil,
            nodeID: nodeID,
            publicProfileID: publicProfileID,
            acceptingInbound: acceptingInbound,
            discoveredAt: detail.thread.updatedAt,
            canAutonomouslyContact: canAutonomouslyContact,
            blockedReason: nil,
            linkedThreadID: nil,
            primaryImageURL: primaryImageURL,
            surfacedOfferImageURLs: [],
            publicOfferContactInfo: nil,
            discoveryMatchedTerms: [],
            discoveryFactLines: discoveryFactLines,
            publicFactLines: publicFactLines,
            suggestedBuyerInputHints: [],
            retrievalFitScore: match?.score,
            discoverySourceLabel: "Social search",
            publicSupporterPresentation: publicProfile?.publicSupporterPresentation
        )

        attachCanonicalSocialDetails(
            item: &item,
            publicProfile: publicProfile,
            publicProfileID: publicProfileID
        )

        return item
    }

    public static func forYouItem(
        from inboxItem: ExchangeModels.InboxItem,
        now: Date = Date()
    ) -> ExchangeModels.ForYouItem {
        let captured = inboxItem.capturedRequestText ?? inboxItem.title
        let intent = ExchangeIntent(
            kind: .find,
            mode: .relational,
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity,
            title: captured,
            objective: captured
        )
        let syntheticThread = ExchangeThread(
            id: inboxItem.threadID,
            createdAt: inboxItem.updatedAt,
            updatedAt: inboxItem.updatedAt,
            mode: .relational,
            intent: intent,
            posture: ExchangePosture(),
            state: inboxItem.state,
            selectedCounterpartyID: inboxItem.selectedCounterpartyID,
            selectedPublicProfileID: inboxItem.selectedPublicProfileID,
            selectedOfferID: inboxItem.selectedOfferID,
            selectedMatchRationale: inboxItem.selectedMatchWhy ?? inboxItem.selectedMatchSummary
        )

        let detail = ExchangeModels.ThreadDetail(
            thread: syntheticThread,
            turns: [],
            approvals: [],
            drafts: [],
            matches: inboxItem.latestMatch.map { [$0] } ?? [],
            counterparties: [],
            artifacts: [],
            summary: inboxItem.subtitle,
            semanticTags: inboxItem.semanticTags,
            selectedPublicProfileID: inboxItem.selectedPublicProfileID,
            selectedOfferID: inboxItem.selectedOfferID,
            selectedMatch: inboxItem.latestMatch
        )

        return forYouItem(
            from: detail,
            supplementalImageURLs: inboxItem.surfaceListImageURLCandidates,
            now: now
        )
    }

    /// Canonical social Details sections for the profile sheet (offer-free, `.socialProfile`).
    public static func canonicalSocialDetailsSections(
        for item: ExchangeModels.ForYouItem
    ) -> [ExchangeDisplaySection] {
        item.displayCard?.detailSections.filter { !$0.lines.isEmpty } ?? []
    }

    // MARK: - Canonical social Details

    private static func attachCanonicalSocialDetails(
        item: inout ExchangeModels.ForYouItem,
        publicProfile: ExchangePublicNodeProfile?,
        publicProfileID: String?
    ) {
        ExchangeProviderDetailsCardDebugLog.logPresentationContext(
            source: "socialDiscovery",
            presentationContext: .socialProfile,
            lane: nil,
            queryIntentClass: nil,
            surfacePreference: nil,
            surfaceLead: .profileLed,
            selectedOfferID: nil,
            selectedProfileID: publicProfileID
        )

        let legacyLineCount = item.discoveryFactLines.count + item.publicFactLines.count
        let canonicalCard = ExchangeProviderDetailsCardBuilder.build(
            ExchangeProviderDetailsCardBuildInput(
                profile: publicProfile,
                offer: nil,
                selectedOfferID: nil,
                contextTitle: item.displayName,
                presentationContext: .socialProfile
            ),
            debugSource: "socialDiscovery"
        )

        ExchangeProviderDetailsCardDebugLog.logSurfaceSelection(
            source: "socialDiscovery",
            usingCanonical: canonicalCard.hasContent,
            canonicalSectionCount: canonicalCard.sections.count,
            legacyLineCount: legacyLineCount
        )

        guard canonicalCard.hasContent else { return }

        item.displayCard = ExchangeProviderDisplayCard(
            title: item.displayName,
            subtitle: item.headline,
            imageURL: item.primaryImageURL,
            detailSections: canonicalCard.sections,
            completeness: canonicalCard.completeness,
            diagnostics: ExchangeProviderDisplayDiagnostics(
                sourceSurface: .forYouCachedHydration,
                hadCanonicalProfile: publicProfile != nil,
                hadCanonicalOffer: false,
                hadCommercialFacts: false
            )
        )
    }

    // MARK: - Private

    private static func matchReasonLine(from match: ExchangeMatch?) -> String? {
        guard let match else { return nil }
        let summaries = match.reasons
            .map { $0.summary.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !summaries.isEmpty else { return nil }
        return summaries.prefix(3).joined(separator: " · ")
    }

    private static func buildDiscoveryFactLines(
        match: ExchangeMatch?,
        publicProfile: ExchangePublicNodeProfile?,
        semanticTags: [String]
    ) -> [String] {
        var lines: [String] = []

        if let matchReason = matchReasonLine(from: match) {
            lines.append("Match: \(matchReason)")
        }

        if let interests = labeledList(
            label: "Interests",
            values: publicProfile?.interests
                ?? commaSeparatedList(match?.metadata["public_profile_interests"])
        ) {
            lines.append(interests)
        }

        if let openTo = labeledList(
            label: "Open to",
            values: publicProfile?.openTo
                ?? commaSeparatedList(match?.metadata["public_profile_open_to"])
        ) {
            lines.append(openTo)
        }

        if let regions = labeledList(
            label: "Region",
            values: publicProfile?.regionTags
                ?? commaSeparatedList(match?.metadata["public_profile_regions"])
        ) {
            lines.append(regions)
        }

        let themes = normalizedTags(
            semanticTags + commaSeparatedList(match?.metadata["public_profile_activity_tags"])
        )
        if !themes.isEmpty {
            lines.append("Shared themes: \(themes.prefix(6).joined(separator: ", "))")
        }

        return dedupedLines(lines, max: 10)
    }

    private static func buildPublicFactLines(
        match: ExchangeMatch?,
        publicProfile: ExchangePublicNodeProfile?
    ) -> [String] {
        var lines: [String] = []

        if let about = trimmed(
            publicProfile?.summary
                ?? match?.metadata["public_profile_summary"]
        ) {
            lines.append("About: \(about)")
        }

        if let offers = labeledList(
            label: "Offers",
            values: publicProfile?.offers
                ?? commaSeparatedList(match?.metadata["public_profile_offers"])
        ) {
            lines.append(offers)
        }

        return dedupedLines(lines, max: 8)
    }

    private static func resolvePrimaryImageURL(
        publicProfile: ExchangePublicNodeProfile?,
        supplementalImageURLs: [String]
    ) -> String? {
        if let primary = trimmed(publicProfile?.primaryImageURL) {
            return primary
        }
        for raw in supplementalImageURLs {
            if let url = trimmed(raw) {
                return url
            }
        }
        return nil
    }

    private static func labeledList(label: String, values: [String]) -> String? {
        let cleaned = normalizedTags(values)
        guard !cleaned.isEmpty else { return nil }
        return "\(label): \(cleaned.joined(separator: ", "))"
    }

    private static func commaSeparatedList(_ raw: String?) -> [String] {
        guard let raw = trimmed(raw) else { return [] }
        return raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    private static func dedupedLines(_ lines: [String], max: Int) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
            if output.count >= max { break }
        }
        return output
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
