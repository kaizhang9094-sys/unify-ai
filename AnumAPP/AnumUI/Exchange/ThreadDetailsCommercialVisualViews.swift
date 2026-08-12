import SwiftUI
import AnumCore

// MARK: - Route dispatcher

struct ThreadDetailsVisualCard: View {
    let layout: ThreadDetailsVisualLayout

    var body: some View {
        let filtered = ThreadDetailsRouteVisualPolicy.filteredLayout(layout)

        if filtered.blocks.isEmpty {
            EmptyView()
        } else {
            switch filtered.context {
            case .commercialOpportunity:
                ThreadDetailsCommercialLayout(layout: filtered)
            case .socialProfile:
                ThreadDetailsSocialProfileLayout(layout: filtered)
            case .opportunityProfile:
                ThreadDetailsOpportunityProfileLayout(layout: filtered)
            case .mixedHydrated:
                ThreadDetailsMixedHydratedLayout(layout: filtered)
            case .unknown:
                ThreadDetailsUnknownLayout(layout: filtered)
            }
        }
    }

    static func hasRenderableContent(for layout: ThreadDetailsVisualLayout) -> Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ThreadDetailsForceLegacyList") {
            return false
        }
        #endif

        return !ThreadDetailsRouteVisualPolicy.filteredLayout(layout).blocks.isEmpty
    }
}

// MARK: - Route block policy

enum ThreadDetailsRouteVisualPolicy {
    static func filteredLayout(_ layout: ThreadDetailsVisualLayout) -> ThreadDetailsVisualLayout {
        ThreadDetailsVisualLayout(
            context: layout.context,
            mode: layout.mode,
            blocks: filteredBlocks(layout.blocks, context: layout.context, mode: layout.mode)
        )
    }

    static func filteredBlocks(
        _ blocks: [ThreadDetailsVisualBlock],
        context: ExchangeProviderDetailsPresentationContext,
        mode: ThreadDetailsVisualMode
    ) -> [ThreadDetailsVisualBlock] {
        blocks.filter { allows($0, context: context, mode: mode) }
    }

    static func allows(
        _ block: ThreadDetailsVisualBlock,
        context: ExchangeProviderDetailsPresentationContext,
        mode: ThreadDetailsVisualMode
    ) -> Bool {
        switch context {
        case .commercialOpportunity:
            switch block.kind {
            case .summary, .offerHighlight, .chipGroup, .priceTile, .availabilityTile:
                return true
            case .contactTile, .note, .policyGroup:
                return mode == .expanded
            }

        case .socialProfile:
            switch block.kind {
            case .summary, .chipGroup:
                return true
            case .note:
                return mode == .expanded
            default:
                return false
            }

        case .opportunityProfile:
            switch block.kind {
            case .summary, .offerHighlight, .chipGroup:
                return true
            case .note:
                return mode == .expanded
            default:
                return false
            }

        case .mixedHydrated:
            switch block.kind {
            case .summary, .offerHighlight, .chipGroup:
                return true
            case .note:
                return mode == .expanded
            default:
                return false
            }

        case .unknown:
            switch block.kind {
            case .summary, .chipGroup:
                return true
            case .note:
                return mode == .expanded
            default:
                return false
            }
        }
    }
}

// MARK: - Block extraction

private extension ThreadDetailsVisualLayout {
    var summaryBlocks: [SummaryBlock] {
        blocks.compactMap {
            if case .summary(let summary) = $0 { return summary }
            return nil
        }
    }

    var firstSummary: SummaryBlock? {
        summaryBlocks.first
    }

    var offerHighlightBlocks: [OfferBlock] {
        blocks.compactMap {
            if case .offerHighlight(let offer) = $0 { return offer }
            return nil
        }
    }

    var firstOfferHighlight: OfferBlock? {
        offerHighlightBlocks.first
    }

    var chipGroups: [ChipGroupBlock] {
        blocks.compactMap {
            if case .chipGroup(let chips) = $0 { return chips }
            return nil
        }
    }

    func chipGroups(with style: ThreadDetailsChipGroupStyle) -> [ChipGroupBlock] {
        chipGroups.filter { $0.style == style }
    }

    var priceTiles: [PriceTileBlock] {
        blocks.compactMap {
            if case .priceTile(let price) = $0 { return price }
            return nil
        }
    }

    var availabilityTiles: [AvailabilityTileBlock] {
        blocks.compactMap {
            if case .availabilityTile(let availability) = $0 { return availability }
            return nil
        }
    }

    var contactTiles: [ContactTileBlock] {
        blocks.compactMap {
            if case .contactTile(let contact) = $0 { return contact }
            return nil
        }
    }

    var noteBlocks: [NoteBlock] {
        blocks.compactMap {
            if case .note(let note) = $0 { return note }
            return nil
        }
    }

    var policyGroups: [PolicyGroupBlock] {
        blocks.compactMap {
            if case .policyGroup(let policies) = $0 { return policies }
            return nil
        }
    }

    func chipGroupsOrdered(
        styles: [ThreadDetailsChipGroupStyle],
        includeRemaining: Bool = true
    ) -> [ChipGroupBlock] {
        var ordered: [ChipGroupBlock] = []
        var seenIDs = Set<String>()

        for style in styles {
            for group in chipGroups(with: style) where seenIDs.insert(group.id).inserted {
                ordered.append(group)
            }
        }

        if includeRemaining {
            for group in chipGroups where seenIDs.insert(group.id).inserted {
                ordered.append(group)
            }
        }

        return ordered
    }

    var profileSafeChipGroups: [ChipGroupBlock] {
        chipGroupsOrdered(styles: [.interests, .openTo, .profile], includeRemaining: false)
    }
}

// MARK: - Shared composition

private struct ThreadDetailsComposedLayoutStack<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func threadDetailsChipGroupTitle(_ block: ChipGroupBlock) -> String? {
    if let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
        return title
    }

    switch block.style {
    case .serviceFit:
        return "Service fit"
    case .interests:
        return "Interests"
    case .openTo:
        return "Open to"
    case .profile:
        return nil
    }
}

@ViewBuilder
private func threadDetailsChipGroupView(_ block: ChipGroupBlock) -> some View {
    ThreadDetailsChipCloud(
        title: threadDetailsChipGroupTitle(block),
        chips: block.chips
    )
}

@ViewBuilder
private func threadDetailsSingleChipInlineView(_ block: ChipGroupBlock) -> some View {
    let cleaned = block.chips
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    if cleaned.count == 1 {
        HStack(alignment: .center, spacing: 9) {
            if let title = threadDetailsChipGroupTitle(block) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)
            }

            ThreadDetailsMiniChip(text: cleaned[0])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
        threadDetailsChipGroupView(block)
    }
}

/// DEBUG / emergency fallback only. Production routes should use composed layouts.
private struct ThreadDetailsVisualBlockStack: View {
    let blocks: [ThreadDetailsVisualBlock]
    let context: ExchangeProviderDetailsPresentationContext

    var body: some View {
        ThreadDetailsComposedLayoutStack {
            ForEach(blocks) { block in
                ThreadDetailsVisualBlockView(block: block, context: context)
            }
        }
    }
}

// MARK: - Route layouts

struct ThreadDetailsSocialProfileLayout: View {
    let layout: ThreadDetailsVisualLayout

    var body: some View {
        let chips = socialChipGroups

        if layout.firstSummary == nil, chips.isEmpty, layout.noteBlocks.isEmpty {
            EmptyView()
        } else {
            ThreadDetailsComposedLayoutStack(spacing: compactAwareSpacing) {
                if let summary = layout.firstSummary {
                    ThreadDetailsSummaryBlockView(paragraphs: summary.paragraphs)
                }

                ForEach(chips) { group in
                    threadDetailsSingleChipInlineView(group)
                }

                if layout.mode == .expanded {
                    ForEach(layout.noteBlocks) { note in
                        ThreadDetailsNoteView(text: note.text)
                    }
                }
            }
        }
    }

    private var compactAwareSpacing: CGFloat {
        layout.mode == .compact ? 10 : 12
    }

    private var socialChipGroups: [ChipGroupBlock] {
        if layout.mode == .compact {
            return layout.chipGroupsOrdered(
                styles: [.interests, .openTo],
                includeRemaining: false
            )
        }

        return layout.chipGroupsOrdered(
            styles: [.interests, .openTo, .profile],
            includeRemaining: true
        )
    }
}

struct ThreadDetailsOpportunityProfileLayout: View {
    let layout: ThreadDetailsVisualLayout

    var body: some View {
        let chips = opportunityChipGroups

        if layout.firstSummary == nil,
           layout.firstOfferHighlight == nil,
           chips.isEmpty,
           layout.noteBlocks.isEmpty {
            EmptyView()
        } else {
            ThreadDetailsComposedLayoutStack(spacing: compactAwareSpacing) {
                if let summary = layout.firstSummary {
                    ThreadDetailsSummaryBlockView(paragraphs: summary.paragraphs)
                }

                if let offer = layout.firstOfferHighlight {
                    ThreadDetailsOfferHighlightView(
                        eyebrow: "Relevant offer",
                        title: offer.title,
                        summary: offer.summary,
                        style: .relevance
                    )
                }

                ForEach(chips) { group in
                    threadDetailsSingleChipInlineView(group)
                }

                if layout.mode == .expanded {
                    ForEach(layout.noteBlocks) { note in
                        ThreadDetailsNoteView(text: note.text)
                    }
                }
            }
        }
    }

    private var compactAwareSpacing: CGFloat {
        layout.mode == .compact ? 10 : 12
    }

    private var opportunityChipGroups: [ChipGroupBlock] {
        let ordered = layout.chipGroupsOrdered(
            styles: [.interests, .openTo, .profile],
            includeRemaining: true
        )

        if layout.mode == .compact {
            return Array(ordered.prefix(1))
        }

        return ordered
    }
}

struct ThreadDetailsMixedHydratedLayout: View {
    let layout: ThreadDetailsVisualLayout

    var body: some View {
        let chips = layout.profileSafeChipGroups
        let offer = layout.mode == .expanded ? layout.firstOfferHighlight : nil

        if layout.firstSummary == nil, offer == nil, chips.isEmpty, layout.noteBlocks.isEmpty {
            EmptyView()
        } else {
            ThreadDetailsComposedLayoutStack(spacing: compactAwareSpacing) {
                if let summary = layout.firstSummary {
                    ThreadDetailsSummaryBlockView(paragraphs: summary.paragraphs)
                }

                if let offer {
                    ThreadDetailsOfferHighlightView(
                        eyebrow: "Related context",
                        title: offer.title,
                        summary: offer.summary,
                        style: .relevance
                    )
                }

                ForEach(chips) { group in
                    threadDetailsSingleChipInlineView(group)
                }

                if layout.mode == .expanded {
                    ForEach(layout.noteBlocks) { note in
                        ThreadDetailsNoteView(text: note.text)
                    }
                }
            }
        }
    }

    private var compactAwareSpacing: CGFloat {
        layout.mode == .compact ? 10 : 12
    }
}

struct ThreadDetailsUnknownLayout: View {
    let layout: ThreadDetailsVisualLayout

    var body: some View {
        let chips = Array(layout.chipGroups.prefix(1))

        if layout.firstSummary == nil, chips.isEmpty, layout.noteBlocks.isEmpty {
            EmptyView()
        } else {
            ThreadDetailsComposedLayoutStack(spacing: 10) {
                if let summary = layout.firstSummary {
                    ThreadDetailsSummaryBlockView(paragraphs: summary.paragraphs)
                }

                ForEach(chips) { group in
                    threadDetailsSingleChipInlineView(group)
                }

                if layout.mode == .expanded {
                    ForEach(layout.noteBlocks) { note in
                        ThreadDetailsNoteView(text: note.text)
                    }
                }
            }
        }
    }
}

// MARK: - Commercial layout

struct ThreadDetailsCommercialLayout: View {
    let layout: ThreadDetailsVisualLayout

    var body: some View {
        if !hasComposedContent {
            EmptyView()
        } else {
            ThreadDetailsComposedLayoutStack(spacing: compactAwareSpacing) {
                if let summary = layout.firstSummary {
                    ThreadDetailsSummaryBlockView(paragraphs: summary.paragraphs)
                }

                if shouldShowOfferHighlight, let offer = layout.firstOfferHighlight {
                    ThreadDetailsOfferHighlightView(
                        eyebrow: "Opportunity",
                        title: offer.title,
                        summary: offer.summary,
                        style: .commercial
                    )
                }

                ForEach(commercialChipGroups) { group in
                    threadDetailsSingleChipInlineView(group)
                }

                commercialTileSection

                if layout.mode == .expanded {
                    ForEach(layout.contactTiles) { contact in
                        ThreadDetailsContactTile(rows: contact.rows)
                    }

                    ForEach(layout.policyGroups) { policies in
                        ThreadDetailsPolicyNotes(items: policies.items)
                    }
                }
            }
        }
    }

    private var compactAwareSpacing: CGFloat {
        layout.mode == .compact ? 10 : 12
    }

    private var shouldShowOfferHighlight: Bool {
        guard let offer = layout.firstOfferHighlight else { return false }

        let title = offer.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = offer.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if layout.mode == .compact {
            // Thin commercial cards often already show the same offer in the hero.
            // Keep compact focused unless the offer carries real extra summary text.
            return !summary.isEmpty && summary.caseInsensitiveCompare(title) != .orderedSame
        }

        return !title.isEmpty || !summary.isEmpty
    }

    private var hasComposedContent: Bool {
        layout.firstSummary != nil
            || shouldShowOfferHighlight
            || !commercialChipGroups.isEmpty
            || layout.priceTiles.first != nil
            || layout.availabilityTiles.first != nil
            || (layout.mode == .expanded && !layout.contactTiles.isEmpty)
            || (layout.mode == .expanded && !layout.policyGroups.isEmpty)
    }

    private var commercialChipGroups: [ChipGroupBlock] {
        layout.chipGroupsOrdered(styles: [.serviceFit], includeRemaining: true)
    }

    @ViewBuilder
    private var commercialTileSection: some View {
        let price = layout.priceTiles.first
        let availability = layout.availabilityTiles.first

        if layout.mode == .expanded, let price, let availability {
            HStack(alignment: .top, spacing: 10) {
                ThreadDetailsInfoTile(
                    title: "Pricing",
                    primary: price.primary,
                    secondary: price.secondary,
                    detailLines: price.packageLines,
                    footnote: price.footnote,
                    accentSymbol: "dollarsign.circle"
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                ThreadDetailsInfoTile(
                    title: "Timing",
                    primary: availability.primary,
                    secondary: nil,
                    detailLines: availability.detailLines,
                    footnote: nil,
                    accentSymbol: "calendar"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            if let price {
                ThreadDetailsInfoTile(
                    title: "Pricing",
                    primary: price.primary,
                    secondary: price.secondary,
                    detailLines: price.packageLines,
                    footnote: price.footnote,
                    accentSymbol: "dollarsign.circle"
                )
            }

            if layout.mode == .expanded, let availability {
                ThreadDetailsInfoTile(
                    title: "Timing",
                    primary: availability.primary,
                    secondary: nil,
                    detailLines: availability.detailLines,
                    footnote: nil,
                    accentSymbol: "calendar"
                )
            }
        }
    }
}

// MARK: - Block dispatcher

struct ThreadDetailsVisualBlockView: View {
    let block: ThreadDetailsVisualBlock
    let context: ExchangeProviderDetailsPresentationContext

    var body: some View {
        switch block {
        case .summary(let summary):
            ThreadDetailsSummaryBlockView(paragraphs: summary.paragraphs)

        case .offerHighlight(let offer):
            ThreadDetailsOfferHighlightView(
                eyebrow: offerEyebrow,
                title: offer.title,
                summary: offer.summary,
                style: offerHighlightStyle
            )

        case .chipGroup(let chips):
            threadDetailsSingleChipInlineView(chips)

        case .priceTile(let price):
            ThreadDetailsInfoTile(
                title: "Pricing",
                primary: price.primary,
                secondary: price.secondary,
                detailLines: price.packageLines,
                footnote: price.footnote,
                accentSymbol: "dollarsign.circle"
            )

        case .availabilityTile(let availability):
            ThreadDetailsInfoTile(
                title: "Timing",
                primary: availability.primary,
                secondary: nil,
                detailLines: availability.detailLines,
                footnote: nil,
                accentSymbol: "calendar"
            )

        case .contactTile(let contact):
            ThreadDetailsContactTile(rows: contact.rows)

        case .note(let note):
            ThreadDetailsNoteView(text: note.text)

        case .policyGroup(let policies):
            ThreadDetailsPolicyNotes(items: policies.items)
        }
    }

    private var offerHighlightStyle: ThreadDetailsOfferHighlightStyle {
        switch context {
        case .commercialOpportunity:
            return .commercial
        case .opportunityProfile, .mixedHydrated:
            return .relevance
        default:
            return .plain
        }
    }

    private var offerEyebrow: String? {
        switch context {
        case .commercialOpportunity:
            return "Opportunity"
        case .opportunityProfile:
            return "Relevant offer"
        case .mixedHydrated:
            return "Related context"
        default:
            return nil
        }
    }
}

// MARK: - Summary

struct ThreadDetailsSummaryBlockView: View {
    let paragraphs: [String]

    var body: some View {
        let cleaned = cleanedParagraphs

        if cleaned.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: cleaned.count > 1 ? 7 : 0) {
                ForEach(Array(cleaned.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph)
                        .font(.system(size: index == 0 ? 14.8 : 13.5, weight: .medium))
                        .foregroundStyle(
                            index == 0
                                ? SecretaryTheme.darkPrimaryText.opacity(0.94)
                                : SecretaryTheme.darkSecondaryText
                        )
                        .lineLimit(index == 0 ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cleanedParagraphs: [String] {
        paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Offer highlight

enum ThreadDetailsOfferHighlightStyle {
    case commercial
    case relevance
    case plain
}

struct ThreadDetailsOfferHighlightView: View {
    let eyebrow: String?
    let title: String?
    let summary: String?
    var style: ThreadDetailsOfferHighlightStyle = .commercial

    var body: some View {
        let title = cleaned(title)
        let summary = cleaned(summary)

        if title == nil, summary == nil {
            EmptyView()
        } else {
            switch style {
            case .commercial, .relevance:
                premiumBody(title: title, summary: summary)
            case .plain:
                plainBody(title: title, summary: summary)
            }
        }
    }

    @ViewBuilder
    private func premiumBody(title: String?, summary: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow = cleaned(eyebrow) {
                HStack(spacing: 6) {
                    Image(systemName: style == .commercial ? "scope" : "sparkle.magnifyingglass")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.78))

                    Text(eyebrow)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .font(.system(size: style == .relevance ? 14.5 : 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let summary {
                    Text(summary)
                        .font(.system(size: 13.2, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(style == .relevance ? 2 : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            threadDetailsSubtleCardBackground(cornerRadius: 14)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(SecretaryTheme.darkOrange.opacity(style == .commercial ? 0.52 : 0.36))
                .frame(width: 2.5)
                .padding(.vertical, 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    SecretaryTheme.darkStroke.opacity(style == .relevance ? 0.45 : 0.55),
                    lineWidth: 1
                )
        }
    }

    @ViewBuilder
    private func plainBody(title: String?, summary: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let summary {
                Text(summary)
                    .font(.system(size: 13.2, weight: .medium))
                    .foregroundStyle(SecretaryTheme.darkSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Chips

struct ThreadDetailsChipCloud: View {
    let title: String?
    let chips: [String]

    var body: some View {
        let cleaned = cleanedChips

        if cleaned.isEmpty {
            EmptyView()
        } else if cleaned.count == 1, let title = cleanedTitle {
            HStack(alignment: .center, spacing: 9) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)

                ThreadDetailsMiniChip(text: cleaned[0])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                if let title = cleanedTitle {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(cleaned, id: \.self) { chip in
                            ThreadDetailsMiniChip(text: chip)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private var cleanedTitle: String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var cleanedChips: [String] {
        chips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct ThreadDetailsMiniChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.8, weight: .semibold))
            .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                threadDetailsGlassCapsuleBackground()
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.7), lineWidth: 1)
            }
    }
}

// MARK: - Info tile

struct ThreadDetailsInfoTile: View {
    let title: String
    let primary: String?
    let secondary: String?
    let detailLines: [String]
    let footnote: String?
    let accentSymbol: String

    var body: some View {
        let primary = cleaned(primary)
        let secondary = cleaned(secondary)
        let detailLines = cleanedLines(detailLines)
        let footnote = cleaned(footnote)

        if primary == nil, secondary == nil, detailLines.isEmpty, footnote == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: accentSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.82))

                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                }

                if let primary {
                    Text(primary)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(SecretaryTheme.darkPrimaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let secondary {
                    Text(secondary)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(detailLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkSecondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let footnote {
                    Text(footnote)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(SecretaryTheme.darkMutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                threadDetailsGlassRoundedBackground(cornerRadius: 12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SecretaryTheme.darkStroke.opacity(0.62), lineWidth: 1)
            }
        }
    }

    private func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanedLines(_ lines: [String]) -> [String] {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Contact

struct ThreadDetailsContactTile: View {
    let rows: [ThreadDetailsContactRow]

    var body: some View {
        let cleanedRows = rows.filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if cleanedRows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Text("Contact")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cleanedRows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: symbol(for: row.kind))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(SecretaryTheme.darkOrange.opacity(0.78))
                                .frame(width: 14, alignment: .center)

                            Text(row.value)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(SecretaryTheme.darkPrimaryText.opacity(0.92))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    threadDetailsGlassRoundedBackground(cornerRadius: 12)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SecretaryTheme.darkStroke.opacity(0.62), lineWidth: 1)
                }
            }
        }
    }

    private func symbol(for kind: ThreadDetailsContactRowKind) -> String {
        switch kind {
        case .name, .business:
            return "person.crop.circle"
        case .email:
            return "envelope"
        case .phone:
            return "phone"
        case .website:
            return "globe"
        case .preferredMethod:
            return "bubble.left.and.text.bubble.right"
        case .area:
            return "mappin.and.ellipse"
        case .hours:
            return "clock"
        case .summary, .other:
            return "link"
        }
    }
}

// MARK: - Notes & policies

struct ThreadDetailsNoteView: View {
    let text: String

    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            EmptyView()
        } else {
            Text(trimmed)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SecretaryTheme.darkSecondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ThreadDetailsPolicyNotes: View {
    let items: [String]

    var body: some View {
        let cleaned = cleanedItems

        if cleaned.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.darkMutedText)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(cleaned, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(SecretaryTheme.darkSecondaryText.opacity(0.92))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var cleanedItems: [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Shared chrome

private func threadDetailsGlassCapsuleBackground() -> some View {
    ZStack {
        Capsule(style: .continuous)
            .fill(SecretaryTheme.darkGlass.opacity(0.82))

        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
    .clipShape(Capsule(style: .continuous))
}

private func threadDetailsGlassRoundedBackground(cornerRadius: CGFloat) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SecretaryTheme.darkGlass.opacity(0.78))

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
}

private func threadDetailsSubtleCardBackground(cornerRadius: CGFloat) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(SecretaryTheme.darkGlass.opacity(0.52))

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial.opacity(0.72))
            .environment(\.colorScheme, .dark)
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
}
