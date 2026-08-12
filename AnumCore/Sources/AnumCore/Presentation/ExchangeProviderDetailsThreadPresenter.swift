import Foundation

/// ThreadView Details compact vs expanded presentation from canonical or curated fallback sections.
public enum ExchangeProviderDetailsThreadPresenter {

    public typealias SectionSnapshot = ExchangeProviderDetailsLegacyFallbackPresenter.SectionSnapshot

    public struct Presentation: Sendable, Hashable {
        public var compactSections: [SectionSnapshot]
        public var expandedSections: [SectionSnapshot]
        public var hasMoreDetails: Bool
        public var hiddenSectionCount: Int
        public var hiddenRowCount: Int

        public init(
            compactSections: [SectionSnapshot] = [],
            expandedSections: [SectionSnapshot] = [],
            hasMoreDetails: Bool = false,
            hiddenSectionCount: Int = 0,
            hiddenRowCount: Int = 0
        ) {
            self.compactSections = compactSections
            self.expandedSections = expandedSections
            self.hasMoreDetails = hasMoreDetails
            self.hiddenSectionCount = hiddenSectionCount
            self.hiddenRowCount = hiddenRowCount
        }

        public var hasAnyContent: Bool {
            !compactSections.isEmpty || !expandedSections.isEmpty
        }
    }

    private enum PresentationMode {
        case compact
        case expanded
    }

    private enum SectionKind: Equatable {
        case about
        case service
        case pricing
        case availability
        case contact
        case policies
        case other

        static func from(title: String, id: String) -> SectionKind {
            let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if normalizedTitle.hasPrefix("about") || normalizedID == "profile" {
                return .about
            }
            if normalizedTitle.hasPrefix("service") || normalizedID == "offer" || normalizedID == "servicearea" {
                return .service
            }
            if normalizedTitle.hasPrefix("pricing") || normalizedTitle.contains("price")
                || normalizedID == "price" || normalizedID == "packages" {
                return .pricing
            }
            if normalizedTitle.hasPrefix("availability") || normalizedID == "availability" {
                return .availability
            }
            if normalizedTitle.hasPrefix("contact") || normalizedID == "contact" {
                return .contact
            }
            if normalizedTitle.hasPrefix("policies") || normalizedID == "policies"
                || normalizedID == "faqs" || normalizedID == "buyerinputs" {
                return .policies
            }
            return .other
        }
    }

    public static func present(
        sourceSections: [SectionSnapshot],
        context: ExchangeProviderDetailsPresentationContext
    ) -> Presentation {
        let prepared = sourceSections.filter(\.hasContent)
        let expanded = applyPresentation(
            prepared,
            context: context,
            mode: .expanded
        )
        let compact = applyPresentation(
            prepared,
            context: context,
            mode: .compact
        )

        let hiddenSections = max(0, expanded.count - compact.count)
        let hiddenRows = max(0, totalRows(expanded) - totalRows(compact))
        let hasMore = !sectionsEquivalent(compact, expanded)

        return Presentation(
            compactSections: compact,
            expandedSections: expanded,
            hasMoreDetails: hasMore,
            hiddenSectionCount: hasMore ? hiddenSections : 0,
            hiddenRowCount: hasMore ? hiddenRows : 0
        )
    }

    /// True when compact and expanded would render the same user-visible content.
    static func sectionsEquivalent(
        _ lhs: [SectionSnapshot],
        _ rhs: [SectionSnapshot]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard left.id == right.id,
                  left.title == right.title,
                  left.labeledRows == right.labeledRows,
                  left.valueLines == right.valueLines else {
                return false
            }
        }
        return true
    }

    // MARK: - Presentation pipeline

    private static func applyPresentation(
        _ sections: [SectionSnapshot],
        context: ExchangeProviderDetailsPresentationContext,
        mode: PresentationMode
    ) -> [SectionSnapshot] {
        let caps = presentationCaps(context: context, mode: mode)
        let allowed = sections.filter { section in
            allowsSection(
                SectionKind.from(title: section.title, id: section.id),
                context: context,
                mode: mode
            )
        }

        let ranked = allowed.sorted { lhs, rhs in
            let left = sectionRank(
                SectionKind.from(title: lhs.title, id: lhs.id),
                context: context
            )
            let right = sectionRank(
                SectionKind.from(title: rhs.title, id: rhs.id),
                context: context
            )
            if left != right { return left < right }
            return lhs.title < rhs.title
        }

        return Array(ranked.prefix(caps.maxSections)).compactMap { section in
            presentSection(section, context: context, mode: mode, caps: caps)
        }
    }

    private static func presentSection(
        _ section: SectionSnapshot,
        context: ExchangeProviderDetailsPresentationContext,
        mode: PresentationMode,
        caps: PresentationCaps
    ) -> SectionSnapshot? {
        let kind = SectionKind.from(title: section.title, id: section.id)
        var copy = section

        let sortedRows = sortLabeledRows(
            section.labeledRows,
            sectionKind: kind,
            context: context,
            mode: mode
        ).filter { row in
            ExchangeProviderDetailsLegacyLineGate.allowsDetailsFallbackLine(row.value)
                && allowsLabeledRow(
                    label: row.label,
                    sectionKind: kind,
                    context: context
                )
        }

        copy.labeledRows = Array(sortedRows.prefix(caps.maxLabeledRowsPerSection))

        let sortedValueLines = section.valueLines.filter {
            ExchangeProviderDetailsLegacyLineGate.allowsDetailsFallbackLine($0)
        }
        copy.valueLines = Array(sortedValueLines.prefix(caps.maxValueLinesPerSection))

        return copy.hasContent ? copy : nil
    }

    // MARK: - Section allowlists

    private static func allowsSection(
        _ kind: SectionKind,
        context: ExchangeProviderDetailsPresentationContext,
        mode: PresentationMode
    ) -> Bool {
        switch context {
        case .commercialOpportunity:
            switch mode {
            case .compact:
                switch kind {
                case .about, .service, .pricing, .availability:
                    return true
                case .contact, .policies, .other:
                    return false
                }
            case .expanded:
                switch kind {
                case .other:
                    return false
                default:
                    return true
                }
            }

        case .socialProfile:
            return kind == .about

        case .opportunityProfile:
            switch kind {
            case .about, .service:
                return true
            case .contact:
                return mode == .expanded
            default:
                return false
            }

        case .mixedHydrated:
            switch kind {
            case .about, .service:
                return true
            default:
                return false
            }

        case .unknown:
            return kind == .about
        }
    }

    private static func sectionRank(
        _ kind: SectionKind,
        context: ExchangeProviderDetailsPresentationContext
    ) -> Int {
        switch context {
        case .commercialOpportunity:
            switch kind {
            case .about: return 0
            case .service: return 1
            case .pricing: return 2
            case .availability: return 3
            case .contact: return 4
            case .policies: return 5
            case .other: return 99
            }
        case .socialProfile, .unknown:
            return kind == .about ? 0 : 99
        case .opportunityProfile, .mixedHydrated:
            switch kind {
            case .about: return 0
            case .service: return 1
            case .contact: return 2
            default: return 99
            }
        }
    }

    // MARK: - Row priority

    private static func sortLabeledRows(
        _ rows: [ExchangeProviderDetailsLegacyFallbackPresenter.LabeledRow],
        sectionKind: SectionKind,
        context: ExchangeProviderDetailsPresentationContext,
        mode: PresentationMode
    ) -> [ExchangeProviderDetailsLegacyFallbackPresenter.LabeledRow] {
        rows.sorted { lhs, rhs in
            let left = rowRank(
                label: lhs.label,
                sectionKind: sectionKind,
                context: context,
                mode: mode
            )
            let right = rowRank(
                label: rhs.label,
                sectionKind: sectionKind,
                context: context,
                mode: mode
            )
            if left != right { return left < right }
            return lhs.label < rhs.label
        }
    }

    private static func rowRank(
        label: String,
        sectionKind: SectionKind,
        context: ExchangeProviderDetailsPresentationContext,
        mode: PresentationMode
    ) -> Int {
        let normalized = ExchangeProviderDetailsLegacyFallbackPresenter.normalizeComparable(label)

        switch sectionKind {
        case .about:
            switch normalized {
            case "about", "headline": return 0
            case "offer": return 1
            case "open to": return 2
            case "interests": return 3
            case "roles": return 4
            case "regions": return 5
            case "modality": return 6
            case "tags": return 7
            case "category": return 8
            default: return 20
            }

        case .service:
            switch normalized {
            case "title", "offer title", "service title": return 0
            case "summary", "offer": return 1
            case "category": return 2
            case "area", "service area", "region": return 3
            case "modality": return 4
            case "tags": return 5
            case "roles": return 6
            case "regions": return 7
            default: return 20
            }

        case .pricing:
            switch normalized {
            case "price", "price display": return 0
            case "range": return 1
            case "package", "packages": return 2
            case "minimum", "minimum engagement": return 3
            case "currency": return 4
            case "unit": return 5
            default: return 20
            }

        case .availability:
            switch normalized {
            case "availability": return 0
            case "lead time": return 1
            case "capacity": return 2
            case "fulfillment": return 99
            default: return 20
            }

        case .contact:
            switch normalized {
            case "contact", "contact name", "email", "phone", "website": return 0
            default: return 10
            }

        case .policies, .other:
            return 0
        }
    }

    // MARK: - Caps

    private struct PresentationCaps {
        var maxSections: Int
        var maxLabeledRowsPerSection: Int
        var maxValueLinesPerSection: Int
    }

    private static func presentationCaps(
        context: ExchangeProviderDetailsPresentationContext,
        mode: PresentationMode
    ) -> PresentationCaps {
        switch (context, mode) {
        case (.commercialOpportunity, .compact):
            return PresentationCaps(maxSections: 2, maxLabeledRowsPerSection: 2, maxValueLinesPerSection: 0)
        case (.commercialOpportunity, .expanded):
            return PresentationCaps(maxSections: 6, maxLabeledRowsPerSection: 3, maxValueLinesPerSection: 2)

        case (.socialProfile, .compact):
            return PresentationCaps(maxSections: 2, maxLabeledRowsPerSection: 2, maxValueLinesPerSection: 0)
        case (.socialProfile, .expanded):
            return PresentationCaps(maxSections: 3, maxLabeledRowsPerSection: 3, maxValueLinesPerSection: 0)

        case (.opportunityProfile, .compact):
            return PresentationCaps(maxSections: 2, maxLabeledRowsPerSection: 2, maxValueLinesPerSection: 0)
        case (.opportunityProfile, .expanded):
            return PresentationCaps(maxSections: 3, maxLabeledRowsPerSection: 3, maxValueLinesPerSection: 0)

        case (.mixedHydrated, .compact):
            return PresentationCaps(maxSections: 2, maxLabeledRowsPerSection: 2, maxValueLinesPerSection: 0)
        case (.mixedHydrated, .expanded):
            return PresentationCaps(maxSections: 2, maxLabeledRowsPerSection: 3, maxValueLinesPerSection: 0)

        case (.unknown, .compact):
            return PresentationCaps(maxSections: 1, maxLabeledRowsPerSection: 2, maxValueLinesPerSection: 0)
        case (.unknown, .expanded):
            return PresentationCaps(maxSections: 1, maxLabeledRowsPerSection: 3, maxValueLinesPerSection: 0)
        }
    }

    // MARK: - Row allowlists

    private static func allowsLabeledRow(
        label: String,
        sectionKind: SectionKind,
        context: ExchangeProviderDetailsPresentationContext
    ) -> Bool {
        guard sectionKind == .about else { return true }
        let normalized = ExchangeProviderDetailsLegacyFallbackPresenter.normalizeComparable(label)
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

    // MARK: - Counts

    private static func totalRows(_ sections: [SectionSnapshot]) -> Int {
        sections.reduce(0) { partial, section in
            partial + section.labeledRows.count + section.valueLines.count
        }
    }
}
