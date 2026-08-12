import Foundation

/// Maps Phase 3 ThreadView Details sections into semantic visual blocks for future premium UI.
///
/// Does not change content selection — only interprets existing section rows.
public enum ThreadDetailsVisualBlockMapper {

    public typealias SectionSnapshot = ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot

    public static func map(
        sections: [SectionSnapshot],
        context: ExchangeProviderDetailsPresentationContext,
        mode: ThreadDetailsVisualMode
    ) -> ThreadDetailsVisualLayout {
        var parsed = ParsedSections()
        for section in sections where section.hasContent {
            ingest(section, into: &parsed)
        }

        var blocks = assembleBlocks(from: parsed, context: context, mode: mode)
        blocks = applyModePresentationRules(blocks, context: context, mode: mode)
        return ThreadDetailsVisualLayout(context: context, mode: mode, blocks: blocks)
    }

    // MARK: - Parsed bucket

    private struct ParsedSections {
        var summaryParagraphs: [String] = []
        var offerTitle: String?
        var offerSummary: String?
        var openToChips: [String] = []
        var interestChips: [String] = []
        var serviceFitChips: [String] = []
        var profileChips: [String] = []
        var noteText: String?
        var pricePrimary: String?
        var priceSecondary: String?
        var packageLines: [String] = []
        var priceFootnote: String?
        var availabilityPrimary: String?
        var availabilityDetails: [String] = []
        var contactRows: [ThreadDetailsContactRow] = []
        var policyItems: [String] = []
    }

    // MARK: - Ingest

    private static func ingest(_ section: SectionSnapshot, into parsed: inout ParsedSections) {
        let kind = sectionKind(title: section.title, id: section.id)

        for row in section.labeledRows {
            let field = inferFieldKey(label: row.label, sectionKind: kind, value: row.value)
            applyField(
                field,
                label: row.label,
                value: row.value,
                sectionKind: kind,
                into: &parsed
            )
        }

        for (index, line) in section.valueLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let field = inferValueLineField(
                line: trimmed,
                sectionKind: kind,
                index: index
            )
            applyField(
                field,
                label: nil,
                value: trimmed,
                sectionKind: kind,
                into: &parsed
            )
        }
    }

    private enum InferredField: Equatable {
        case about
        case headline
        case offerSummary
        case openTo
        case interests
        case semanticNotes
        case offerTitle
        case category
        case tags
        case serviceArea
        case modality
        case roles
        case regions
        case priceDisplay
        case priceRange
        case package
        case minimumEngagement
        case currency
        case priceUnit
        case availabilityNote
        case leadTimeNote
        case capacityNote
        case fulfillment
        case contactName
        case businessName
        case preferredContactMethod
        case email
        case phone
        case website
        case serviceAddressOrArea
        case contactAvailabilityNote
        case contactSummary
        case cancellationPolicy
        case refundPolicy
        case warrantyPolicy
        case requiredBuyerInput
        case faq
        case unknown
    }

    private static func inferFieldKey(
        label: String,
        sectionKind: SectionKind,
        value: String
    ) -> InferredField {
        let normalizedLabel = normalize(label)
        let normalizedValue = normalize(value)

        if normalizedLabel.hasPrefix("about") { return .about }
        if normalizedLabel == "headline" { return .headline }
        if normalizedLabel == "offer" { return .offerSummary }
        if normalizedLabel == "open to" { return .openTo }
        if normalizedLabel == "interests" { return .interests }
        if normalizedLabel == "title" || normalizedLabel == "offer title" || normalizedLabel == "service title" {
            return .offerTitle
        }
        if normalizedLabel == "summary" { return .offerSummary }
        if normalizedLabel == "category" { return .category }
        if normalizedLabel == "tags" { return .tags }
        if normalizedLabel == "area" || normalizedLabel == "service area" || normalizedLabel == "region" {
            return sectionKind == .about ? .regions : .serviceArea
        }
        if normalizedLabel == "regions" { return .regions }
        if normalizedLabel == "modality" { return .modality }
        if normalizedLabel == "roles" { return .roles }
        if normalizedLabel == "price" || normalizedLabel == "price display" { return .priceDisplay }
        if normalizedLabel == "range" || normalizedLabel == "price range" { return .priceRange }
        if normalizedLabel == "currency" { return .currency }
        if normalizedLabel == "unit" { return .priceUnit }
        if normalizedLabel == "minimum" || normalizedLabel == "minimum engagement" { return .minimumEngagement }
        if normalizedLabel == "availability" { return .availabilityNote }
        if normalizedLabel == "lead time" { return .leadTimeNote }
        if normalizedLabel == "capacity" { return .capacityNote }
        if normalizedLabel == "fulfillment" { return .fulfillment }
        if normalizedLabel == "contact" { return .contactSummary }
        if normalizedLabel == "email" { return .email }
        if normalizedLabel == "phone" { return .phone }
        if normalizedLabel == "website" { return .website }
        if normalizedLabel == "preferred" || normalizedLabel == "preferred contact" { return .preferredContactMethod }
        if normalizedLabel == "contact hours" { return .contactAvailabilityNote }
        if normalizedLabel.hasPrefix("cancellation") { return .cancellationPolicy }
        if normalizedLabel.hasPrefix("refund") { return .refundPolicy }
        if normalizedLabel.hasPrefix("warranty") { return .warrantyPolicy }

        if normalizedValue.hasPrefix("package:") { return .package }
        if sectionKind == .pricing { return .unknown }
        if sectionKind == .contact { return .contactSummary }
        return .unknown
    }

    private static func inferValueLineField(
        line: String,
        sectionKind: SectionKind,
        index: Int
    ) -> InferredField {
        let normalized = normalize(line)

        if normalized.hasPrefix("cancellation:") { return .cancellationPolicy }
        if normalized.hasPrefix("refund:") { return .refundPolicy }
        if normalized.hasPrefix("warranty:") { return .warrantyPolicy }
        if normalized.hasPrefix("package:") { return .package }
        if normalized.hasPrefix("lead time:") { return .leadTimeNote }
        if normalized.hasPrefix("capacity:") { return .capacityNote }
        if normalized.hasPrefix("email:") { return .email }
        if normalized.hasPrefix("phone:") { return .phone }
        if normalized.hasPrefix("website:") { return .website }
        if normalized.hasPrefix("preferred:") { return .preferredContactMethod }
        if normalized.hasPrefix("contact hours:") { return .contactAvailabilityNote }
        if normalized.hasPrefix("area:") { return .serviceAddressOrArea }
        if line.contains(" — "), sectionKind == .policies { return .faq }

        switch sectionKind {
        case .about:
            return index == 0 ? .headline : .semanticNotes
        case .service:
            return .offerTitle
        case .availability:
            return .availabilityNote
        case .contact:
            return index == 0 ? .contactName : .businessName
        case .pricing:
            if normalized.hasPrefix("price range:") { return .priceRange }
            if normalized.hasPrefix("price:") { return .priceDisplay }
            return .package
        case .policies:
            return .requiredBuyerInput
        default:
            return .unknown
        }
    }

    private static func applyField(
        _ field: InferredField,
        label: String?,
        value: String,
        sectionKind: SectionKind,
        into parsed: inout ParsedSections
    ) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        switch field {
        case .about, .headline:
            appendUnique(cleaned, to: &parsed.summaryParagraphs)
        case .offerSummary:
            if parsed.offerSummary == nil {
                parsed.offerSummary = stripLabelPrefix(cleaned, knownLabels: ["Offer"])
            } else {
                appendUnique(cleaned, to: &parsed.summaryParagraphs)
            }
        case .openTo:
            parsed.openToChips.append(contentsOf: parseChipValues(cleaned))
        case .interests:
            parsed.interestChips.append(contentsOf: parseChipValues(cleaned))
        case .semanticNotes:
            parsed.noteText = mergeNote(parsed.noteText, with: cleaned)
        case .offerTitle:
            if parsed.offerTitle == nil {
                parsed.offerTitle = cleaned
            }
        case .category, .tags, .modality, .serviceArea:
            parsed.serviceFitChips.append(contentsOf: parseChipValues(cleaned, label: label))
        case .roles, .regions:
            parsed.profileChips.append(contentsOf: parseChipValues(cleaned, label: label))
        case .priceDisplay:
            parsed.pricePrimary = stripLabelPrefix(cleaned, knownLabels: ["Price"])
        case .priceRange:
            parsed.priceSecondary = stripLabelPrefix(cleaned, knownLabels: ["Price range", "Range"])
        case .package:
            parsed.packageLines.append(formatPackageLine(cleaned))
        case .minimumEngagement:
            parsed.priceFootnote = "Minimum: \(stripLabelPrefix(cleaned, knownLabels: ["Minimum"]))"
        case .currency, .priceUnit:
            break
        case .availabilityNote:
            parsed.availabilityPrimary = parsed.availabilityPrimary ?? stripLabelPrefix(
                cleaned,
                knownLabels: ["Availability"]
            )
        case .leadTimeNote, .capacityNote:
            parsed.availabilityDetails.append(stripLabelPrefix(
                cleaned,
                knownLabels: ["Lead time", "Capacity"]
            ))
        case .fulfillment:
            break
        case .contactName:
            appendContactRow(kind: .name, value: cleaned, into: &parsed)
        case .businessName:
            appendContactRow(kind: .business, value: cleaned, into: &parsed)
        case .preferredContactMethod:
            appendContactRow(kind: .preferredMethod, value: cleaned, into: &parsed)
        case .email:
            appendContactRow(kind: .email, value: stripLabelPrefix(cleaned, knownLabels: ["Email"]), into: &parsed)
        case .phone:
            appendContactRow(kind: .phone, value: stripLabelPrefix(cleaned, knownLabels: ["Phone"]), into: &parsed)
        case .website:
            appendContactRow(kind: .website, value: stripLabelPrefix(cleaned, knownLabels: ["Website"]), into: &parsed)
        case .serviceAddressOrArea:
            appendContactRow(kind: .area, value: stripLabelPrefix(cleaned, knownLabels: ["Area"]), into: &parsed)
        case .contactAvailabilityNote:
            appendContactRow(kind: .hours, value: stripLabelPrefix(cleaned, knownLabels: ["Contact hours"]), into: &parsed)
        case .contactSummary:
            appendContactRow(kind: .summary, value: cleaned, into: &parsed)
        case .cancellationPolicy, .refundPolicy, .warrantyPolicy, .requiredBuyerInput, .faq:
            parsed.policyItems.append(formatPolicyLine(field: field, label: label, value: cleaned))
        case .unknown:
            if sectionKind == .policies {
                parsed.policyItems.append(cleaned)
            } else if sectionKind == .pricing {
                parsed.packageLines.append(cleaned)
            } else if sectionKind == .about {
                appendUnique(cleaned, to: &parsed.summaryParagraphs)
            }
        }
    }

    // MARK: - Assemble

    private static func assembleBlocks(
        from parsed: ParsedSections,
        context: ExchangeProviderDetailsPresentationContext,
        mode: ThreadDetailsVisualMode
    ) -> [ThreadDetailsVisualBlock] {
        var blocks: [ThreadDetailsVisualBlock] = []

        if allows(.summary, context: context, mode: mode),
           let summary = buildSummary(from: parsed, mode: mode) {
            blocks.append(.summary(summary))
        }

        if allows(.offerHighlight, context: context, mode: mode),
           let offer = buildOffer(from: parsed, mode: mode) {
            blocks.append(.offerHighlight(offer))
        }

        blocks.append(contentsOf: buildChipGroups(from: parsed, context: context, mode: mode))

        if allows(.priceTile, context: context, mode: mode),
           let price = buildPriceTile(from: parsed, mode: mode) {
            blocks.append(.priceTile(price))
        }

        if allows(.availabilityTile, context: context, mode: mode),
           let availability = buildAvailabilityTile(from: parsed, mode: mode) {
            blocks.append(.availabilityTile(availability))
        }

        if allows(.contactTile, context: context, mode: mode),
           let contact = buildContactTile(from: parsed) {
            blocks.append(.contactTile(contact))
        }

        if allows(.note, context: context, mode: mode),
           let note = buildNote(from: parsed, mode: mode) {
            blocks.append(.note(note))
        }

        if allows(.policyGroup, context: context, mode: mode),
           let policies = buildPolicyGroup(from: parsed, mode: mode) {
            blocks.append(.policyGroup(policies))
        }

        return blocks
    }

    private static func buildSummary(from parsed: ParsedSections, mode: ThreadDetailsVisualMode) -> SummaryBlock? {
        let limit = mode == .compact ? 2 : 3
        let paragraphs = Array(parsed.summaryParagraphs.prefix(limit))
        guard !paragraphs.isEmpty else { return nil }
        return SummaryBlock(paragraphs: paragraphs)
    }

    private static func buildOffer(from parsed: ParsedSections, mode: ThreadDetailsVisualMode) -> OfferBlock? {
        let title = parsed.offerTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = parsed.offerSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTitle = !(title?.isEmpty ?? true)
        let hasSummary = !(summary?.isEmpty ?? true)
        guard hasTitle || hasSummary else { return nil }

        if mode == .compact, hasTitle, hasSummary {
            return OfferBlock(title: title, summary: nil)
        }
        return OfferBlock(title: title, summary: summary)
    }

    private static func buildChipGroups(
        from parsed: ParsedSections,
        context: ExchangeProviderDetailsPresentationContext,
        mode: ThreadDetailsVisualMode
    ) -> [ThreadDetailsVisualBlock] {
        guard allows(.chipGroup, context: context, mode: mode) else { return [] }

        let chipLimit = mode == .compact ? 4 : 8
        var blocks: [ThreadDetailsVisualBlock] = []

        if allowsServiceFitChips(context: context) {
            let chips = uniqueNonEmpty(Array(parsed.serviceFitChips.prefix(chipLimit)))
            if !chips.isEmpty {
                blocks.append(.chipGroup(ChipGroupBlock(
                    id: "service-fit",
                    style: .serviceFit,
                    title: nil,
                    chips: chips
                )))
            }
        }

        let interestLimit = mode == .compact ? min(3, chipLimit) : chipLimit
        let interests = uniqueNonEmpty(Array(parsed.interestChips.prefix(interestLimit)))
        if !interests.isEmpty {
            blocks.append(.chipGroup(ChipGroupBlock(
                id: "interests",
                style: .interests,
                title: "Interests",
                chips: interests
            )))
        }

        let openTo = uniqueNonEmpty(Array(parsed.openToChips.prefix(chipLimit)))
        if !openTo.isEmpty {
            blocks.append(.chipGroup(ChipGroupBlock(
                id: "open-to",
                style: .openTo,
                title: "Open to",
                chips: openTo
            )))
        }

        let profile = uniqueNonEmpty(Array(parsed.profileChips.prefix(chipLimit)))
        if !profile.isEmpty, allowsProfileChips(context: context) {
            blocks.append(.chipGroup(ChipGroupBlock(
                id: "profile",
                style: .profile,
                title: nil,
                chips: profile
            )))
        }

        return blocks
    }

    private static func buildPriceTile(from parsed: ParsedSections, mode: ThreadDetailsVisualMode) -> PriceTileBlock? {
        let packageLimit = mode == .compact ? 0 : 2
        let block = PriceTileBlock(
            primary: parsed.pricePrimary,
            secondary: parsed.priceSecondary,
            packageLines: Array(parsed.packageLines.prefix(packageLimit)),
            footnote: parsed.priceFootnote
        )
        return block.hasContent ? block : nil
    }

    private static func buildAvailabilityTile(
        from parsed: ParsedSections,
        mode: ThreadDetailsVisualMode
    ) -> AvailabilityTileBlock? {
        let detailLimit = mode == .compact ? 0 : 2
        let block = AvailabilityTileBlock(
            primary: parsed.availabilityPrimary,
            detailLines: Array(parsed.availabilityDetails.prefix(detailLimit))
        )
        return block.hasContent ? block : nil
    }

    private static func buildContactTile(from parsed: ParsedSections) -> ContactTileBlock? {
        guard !parsed.contactRows.isEmpty else { return nil }
        return ContactTileBlock(rows: parsed.contactRows)
    }

    private static func buildNote(from parsed: ParsedSections, mode: ThreadDetailsVisualMode) -> NoteBlock? {
        guard mode == .expanded else { return nil }
        guard let text = parsed.noteText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return NoteBlock(text: text)
    }

    private static func buildPolicyGroup(from parsed: ParsedSections, mode: ThreadDetailsVisualMode) -> PolicyGroupBlock? {
        guard mode == .expanded else { return nil }
        let limit = 3
        let items = uniqueNonEmpty(Array(parsed.policyItems.prefix(limit)))
        guard !items.isEmpty else { return nil }
        return PolicyGroupBlock(items: items)
    }

    // MARK: - Mode presentation rules

    private static func applyModePresentationRules(
        _ blocks: [ThreadDetailsVisualBlock],
        context: ExchangeProviderDetailsPresentationContext,
        mode: ThreadDetailsVisualMode
    ) -> [ThreadDetailsVisualBlock] {
        guard context == .commercialOpportunity, mode == .compact else { return blocks }

        let hasPrice = blocks.contains { $0.kind == .priceTile }
        let hasAvailability = blocks.contains { $0.kind == .availabilityTile }
        guard hasPrice, hasAvailability else { return blocks }

        return blocks.filter { $0.kind != .availabilityTile }
    }

    // MARK: - Context allowlists

    private static func allows(
        _ kind: ThreadDetailsVisualBlockKind,
        context: ExchangeProviderDetailsPresentationContext,
        mode: ThreadDetailsVisualMode
    ) -> Bool {
        switch context {
        case .commercialOpportunity:
            switch kind {
            case .summary, .offerHighlight, .chipGroup, .priceTile, .availabilityTile:
                return true
            case .contactTile, .policyGroup, .note:
                return mode == .expanded
            }
        case .socialProfile:
            switch kind {
            case .summary, .chipGroup, .note:
                return true
            default:
                return false
            }
        case .opportunityProfile:
            switch kind {
            case .summary, .offerHighlight, .chipGroup, .note:
                return true
            case .contactTile:
                return mode == .expanded
            default:
                return false
            }
        case .mixedHydrated:
            switch kind {
            case .summary, .offerHighlight, .chipGroup, .note:
                return true
            default:
                return false
            }
        case .unknown:
            switch kind {
            case .summary, .chipGroup:
                return true
            case .note:
                return mode == .expanded
            default:
                return false
            }
        }
    }

    private static func allowsServiceFitChips(context: ExchangeProviderDetailsPresentationContext) -> Bool {
        context == .commercialOpportunity
    }

    private static func allowsProfileChips(context: ExchangeProviderDetailsPresentationContext) -> Bool {
        switch context {
        case .socialProfile, .opportunityProfile, .mixedHydrated, .unknown:
            return true
        case .commercialOpportunity:
            return false
        }
    }

    // MARK: - Section kind

    private enum SectionKind {
        case about
        case service
        case pricing
        case availability
        case contact
        case policies
        case other

        static func from(title: String, id: String) -> SectionKind {
            sectionKind(title: title, id: id)
        }
    }

    private static func sectionKind(title: String, id: String) -> SectionKind {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedTitle.hasPrefix("about") || normalizedID == "profile" { return .about }
        if normalizedTitle.hasPrefix("service") || normalizedID == "offer" || normalizedID == "servicearea" {
            return .service
        }
        if normalizedTitle.hasPrefix("pricing") || normalizedTitle.contains("price")
            || normalizedID == "price" || normalizedID == "packages" {
            return .pricing
        }
        if normalizedTitle.hasPrefix("availability") || normalizedID == "availability" { return .availability }
        if normalizedTitle.hasPrefix("contact") || normalizedID == "contact" { return .contact }
        if normalizedTitle.hasPrefix("policies") || normalizedID == "policies"
            || normalizedID == "faqs" || normalizedID == "buyerinputs" {
            return .policies
        }
        return .other
    }

    // MARK: - Helpers

    private static func normalize(_ raw: String) -> String {
        ExchangeProviderDetailsLegacyFallbackPresenter.normalizeComparable(raw)
    }

    private static func parseChipValues(_ raw: String, label: String? = nil) -> [String] {
        let stripped = stripLabelPrefix(raw, knownLabels: [label].compactMap { $0 })
        return stripped
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stripLabelPrefix(_ raw: String, knownLabels: [String]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in knownLabels {
            let prefix = "\(label):"
            if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return trimmed
    }

    private static func formatPackageLine(_ raw: String) -> String {
        stripLabelPrefix(raw, knownLabels: ["Package", "Package:"])
    }

    private static func formatPolicyLine(field: InferredField, label: String?, value: String) -> String {
        if let label, !label.isEmpty, !value.lowercased().hasPrefix(label.lowercased()) {
            return "\(label): \(value)"
        }
        return value
    }

    private static func appendUnique(_ value: String, to array: inout [String]) {
        let key = normalize(value)
        guard !key.isEmpty else { return }
        guard !array.contains(where: { normalize($0) == key }) else { return }
        array.append(value)
    }

    private static func uniqueNonEmpty(_ values: [String]) -> [String] {
        var output: [String] = []
        var seen = Set<String>()
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = normalize(trimmed)
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }

    private static func mergeNote(_ existing: String?, with incoming: String) -> String {
        guard let existing, !existing.isEmpty else { return incoming }
        if normalize(existing) == normalize(incoming) { return existing }
        return "\(existing) \(incoming)"
    }

    private static func appendContactRow(
        kind: ThreadDetailsContactRowKind,
        value: String,
        into parsed: inout ParsedSections
    ) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = "\(kind.rawValue)-\(parsed.contactRows.count)"
        parsed.contactRows.append(ThreadDetailsContactRow(id: id, kind: kind, value: trimmed))
    }
}

// MARK: - DEBUG trace

public enum ThreadDetailsVisualBlockDebugLog {
    public static func logMappedLayout(_ layout: ThreadDetailsVisualLayout, source: String) {
        #if DEBUG
        print(
            "[ThreadDetailsVisual][map] source=\(source) " +
            "presentationContext=\(layout.context.rawValue) mode=\(layout.mode.rawValue) " +
            "blocks=\(layout.blocks.count)"
        )
        for block in layout.blocks {
            print(
                "[ThreadDetailsVisual][block] source=\(source) kind=\(block.kind.rawValue) id=\(block.id)"
            )
        }
        #endif
    }
}
