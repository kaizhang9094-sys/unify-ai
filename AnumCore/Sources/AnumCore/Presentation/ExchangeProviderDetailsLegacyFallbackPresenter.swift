import Foundation

/// Curates ThreadView legacy Details fallback: context gating, caps, dedupe, and line suppression.
///
/// Legacy fallback is a safety net — not a second Details renderer. Output stays small and user-facing.
public enum ExchangeProviderDetailsLegacyFallbackPresenter {

    public struct LabeledRow: Sendable, Hashable {
        public var label: String
        public var value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct SectionSnapshot: Sendable, Hashable {
        public var id: String
        public var title: String
        public var labeledRows: [LabeledRow]
        public var valueLines: [String]

        public init(
            id: String,
            title: String,
            labeledRows: [LabeledRow] = [],
            valueLines: [String] = []
        ) {
            self.id = id
            self.title = title
            self.labeledRows = labeledRows
            self.valueLines = valueLines
        }

        public var hasContent: Bool {
            !labeledRows.isEmpty || valueLines.contains(where: { !$0.isEmpty })
        }
    }

    public struct PresentInput: Sendable, Hashable {
        public var sections: [SectionSnapshot]
        public var context: ExchangeProviderDetailsPresentationContext
        /// Normalized hero / current-opportunity text used to suppress duplicate rows.
        public var heroDedupeTexts: Set<String>
        /// Offer or profile title shown in hero — suppresses duplicate offer-title rows.
        public var contextTitle: String?

        public init(
            sections: [SectionSnapshot],
            context: ExchangeProviderDetailsPresentationContext,
            heroDedupeTexts: Set<String> = [],
            contextTitle: String? = nil
        ) {
            self.sections = sections
            self.context = context
            self.heroDedupeTexts = heroDedupeTexts
            self.contextTitle = contextTitle
        }
    }

    /// Context gate → row filter → hero dedupe → canonical titles → caps.
    public static func present(_ input: PresentInput) -> [SectionSnapshot] {
        let contextFiltered = filterSectionsForContext(input.sections, context: input.context)
        let lineFiltered = contextFiltered.compactMap { filterSectionLines($0, context: input.context) }
        let deduped = lineFiltered.compactMap { dedupeAgainstHero($0, input: input) }
        let titled = deduped.map { canonicalizeSectionTitle($0) }
        return applyCaps(titled, context: input.context)
    }

    // MARK: - Context gating

    private static func filterSectionsForContext(
        _ sections: [SectionSnapshot],
        context: ExchangeProviderDetailsPresentationContext
    ) -> [SectionSnapshot] {
        sections.compactMap { section in
            guard allowsLegacySection(id: section.id, context: context) else {
                logSuppression(sectionID: section.id, context: context, reason: "sectionNotAllowedForContext")
                return nil
            }
            return section
        }
    }

    private static func allowsLegacySection(
        id: String,
        context: ExchangeProviderDetailsPresentationContext
    ) -> Bool {
        switch context {
        case .commercialOpportunity:
            return commercialSectionPriority[id] != nil
        case .socialProfile:
            return id == "profile"
        case .opportunityProfile, .mixedHydrated:
            return id == "profile" || id == "offer"
        case .unknown:
            return id == "profile"
        }
    }

    // MARK: - Row / line filtering

    private static func filterSectionLines(
        _ section: SectionSnapshot,
        context: ExchangeProviderDetailsPresentationContext
    ) -> SectionSnapshot? {
        var filtered = section

        switch section.id {
        case "profile":
            filtered.labeledRows = section.labeledRows.filter { row in
                let allowed = allowsProfileRowLabel(row.label, context: context)
                if !allowed {
                    logSuppression(
                        sectionID: section.id,
                        context: context,
                        reason: "profileRowLabel=\(row.label)"
                    )
                }
                return allowed
            }
        case "offer":
            filtered.labeledRows = section.labeledRows.filter { row in
                let normalized = normalizeLabel(row.label)
                let allowed = normalized == "title" || normalized == "summary"
                if !allowed {
                    logSuppression(
                        sectionID: section.id,
                        context: context,
                        reason: "offerRowLabel=\(row.label)"
                    )
                }
                return allowed
            }
        case "availability":
            filtered.labeledRows = section.labeledRows.filter { row in
                if normalizeLabel(row.label) == "fulfillment" {
                    return ExchangeProviderDetailsLegacyLineGate.allowsDetailsFallbackLine(row.value)
                }
                return true
            }
        default:
            break
        }

        filtered.labeledRows = filtered.labeledRows.filter { row in
            ExchangeProviderDetailsLegacyLineGate.allowsDetailsFallbackLine(row.value)
        }

        filtered.valueLines = ExchangeProviderDetailsLegacyLineGate.filterDetailsFallbackLines(
            section.valueLines,
            source: "legacyFallbackPresenter-\(section.id)"
        )

        return filtered.hasContent ? filtered : nil
    }

    private static func allowsProfileRowLabel(
        _ label: String,
        context: ExchangeProviderDetailsPresentationContext
    ) -> Bool {
        let normalized = normalizeLabel(label)
        switch context {
        case .commercialOpportunity:
            return true
        case .socialProfile:
            return socialProfileRowLabels.contains(normalized)
        case .opportunityProfile:
            return opportunityProfileRowLabels.contains(normalized)
        case .mixedHydrated:
            return mixedHydratedProfileRowLabels.contains(normalized)
        case .unknown:
            return unknownProfileRowLabels.contains(normalized)
        }
    }

    // MARK: - Hero dedupe

    private static func dedupeAgainstHero(
        _ section: SectionSnapshot,
        input: PresentInput
    ) -> SectionSnapshot? {
        var filtered = section
        let heroTexts = input.heroDedupeTexts

        filtered.labeledRows = section.labeledRows.filter { row in
            let valueNorm = normalizeComparable(row.value)
            if heroTexts.contains(valueNorm) {
                logSuppression(sectionID: section.id, context: input.context, reason: "heroDuplicateValue")
                return false
            }
            if section.id == "offer", normalizeLabel(row.label) == "title" {
                let contextTitleNorm = normalizeComparable(input.contextTitle)
                if !contextTitleNorm.isEmpty, valueNorm == contextTitleNorm {
                    logSuppression(sectionID: section.id, context: input.context, reason: "heroDuplicateOfferTitle")
                    return false
                }
            }
            return true
        }

        filtered.valueLines = section.valueLines.filter { line in
            let norm = normalizeComparable(line)
            if heroTexts.contains(norm) {
                logSuppression(sectionID: section.id, context: input.context, reason: "heroDuplicateValueLine")
                return false
            }
            return true
        }

        return filtered.hasContent ? filtered : nil
    }

    // MARK: - Canonical section titles

    private static func canonicalizeSectionTitle(_ section: SectionSnapshot) -> SectionSnapshot {
        var copy = section
        switch section.id {
        case "profile":
            copy.title = "About"
        case "offer":
            copy.title = "Service"
        case "price":
            copy.title = "Pricing"
        case "packages":
            copy.title = "Pricing"
        case "serviceArea":
            copy.title = "Service"
        case "availability":
            copy.title = "Availability"
        case "contact":
            copy.title = "Contact"
        case "policies":
            copy.title = "Policies"
        case "buyerInputs":
            copy.title = "Policies"
        case "faqs":
            copy.title = "Policies"
        default:
            break
        }
        return copy
    }

    // MARK: - Caps

    private struct FallbackCaps {
        var maxSections: Int
        var maxLabeledRowsPerSection: Int
        var maxValueLinesPerSection: Int
    }

    private static func applyCaps(
        _ sections: [SectionSnapshot],
        context: ExchangeProviderDetailsPresentationContext
    ) -> [SectionSnapshot] {
        let caps = caps(for: context)
        let ranked = sections.sorted { lhs, rhs in
            let left = sectionRank(id: lhs.id, context: context)
            let right = sectionRank(id: rhs.id, context: context)
            if left != right { return left < right }
            return lhs.title < rhs.title
        }

        return Array(ranked.prefix(caps.maxSections)).compactMap { section in
            var capped = section
            capped.labeledRows = Array(section.labeledRows.prefix(caps.maxLabeledRowsPerSection))
            capped.valueLines = Array(section.valueLines.prefix(caps.maxValueLinesPerSection))
            return capped.hasContent ? capped : nil
        }
    }

    private static func caps(for context: ExchangeProviderDetailsPresentationContext) -> FallbackCaps {
        switch context {
        case .commercialOpportunity:
            return FallbackCaps(maxSections: 3, maxLabeledRowsPerSection: 2, maxValueLinesPerSection: 1)
        case .socialProfile:
            return FallbackCaps(maxSections: 1, maxLabeledRowsPerSection: 3, maxValueLinesPerSection: 0)
        case .opportunityProfile:
            return FallbackCaps(maxSections: 2, maxLabeledRowsPerSection: 2, maxValueLinesPerSection: 0)
        case .mixedHydrated:
            return FallbackCaps(maxSections: 2, maxLabeledRowsPerSection: 2, maxValueLinesPerSection: 0)
        case .unknown:
            return FallbackCaps(maxSections: 1, maxLabeledRowsPerSection: 2, maxValueLinesPerSection: 0)
        }
    }

    private static func sectionRank(
        id: String,
        context: ExchangeProviderDetailsPresentationContext
    ) -> Int {
        switch context {
        case .commercialOpportunity:
            return commercialSectionPriority[id] ?? 99
        default:
            switch id {
            case "profile": return 0
            case "offer": return 1
            default: return 99
            }
        }
    }

    /// Lower rank = higher priority. Skim-heavy sections rank last and are dropped first under caps.
    private static let commercialSectionPriority: [String: Int] = [
        "profile": 0,
        "offer": 1,
        "price": 2,
        "availability": 3,
        "contact": 4,
        "serviceArea": 5,
        "packages": 6,
        "policies": 7,
        "faqs": 8,
        "buyerInputs": 9
    ]

    private static let socialProfileRowLabels: Set<String> = [
        "headline", "about", "open to", "interests", "roles", "regions", "modality", "tags"
    ]

    private static let opportunityProfileRowLabels: Set<String> = socialProfileRowLabels

    private static let mixedHydratedProfileRowLabels: Set<String> = [
        "headline", "about", "open to", "regions", "roles"
    ]

    private static let unknownProfileRowLabels: Set<String> = [
        "headline", "about", "regions", "roles"
    ]

    // MARK: - Normalization

    public static func normalizeComparable(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private static func normalizeLabel(_ raw: String) -> String {
        normalizeComparable(raw)
    }

    private static func logSuppression(
        sectionID: String,
        context: ExchangeProviderDetailsPresentationContext,
        reason: String
    ) {
        #if DEBUG
        print(
            "[ProviderDetailsCard][legacyFallback] sectionID=\(sectionID) " +
            "presentationContext=\(context.rawValue) suppressed reason=\(reason)"
        )
        #endif
    }
}
