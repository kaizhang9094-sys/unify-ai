import Foundation

// MARK: - Mode & layout

public enum ThreadDetailsVisualMode: String, Sendable, Hashable, Codable {
    case compact
    case expanded
}

public struct ThreadDetailsVisualLayout: Sendable, Hashable, Codable {
    public var context: ExchangeProviderDetailsPresentationContext
    public var mode: ThreadDetailsVisualMode
    public var blocks: [ThreadDetailsVisualBlock]

    public init(
        context: ExchangeProviderDetailsPresentationContext,
        mode: ThreadDetailsVisualMode,
        blocks: [ThreadDetailsVisualBlock] = []
    ) {
        self.context = context
        self.mode = mode
        self.blocks = blocks
    }

    public var hasContent: Bool {
        blocks.contains { $0.hasContent }
    }
}

// MARK: - Blocks

public enum ThreadDetailsVisualBlock: Identifiable, Sendable, Hashable, Codable {
    case summary(SummaryBlock)
    case offerHighlight(OfferBlock)
    case chipGroup(ChipGroupBlock)
    case priceTile(PriceTileBlock)
    case availabilityTile(AvailabilityTileBlock)
    case contactTile(ContactTileBlock)
    case note(NoteBlock)
    case policyGroup(PolicyGroupBlock)

    public var id: String {
        switch self {
        case .summary(let block): return "summary-\(block.id)"
        case .offerHighlight(let block): return "offer-\(block.id)"
        case .chipGroup(let block): return "chips-\(block.id)"
        case .priceTile(let block): return "price-\(block.id)"
        case .availabilityTile(let block): return "availability-\(block.id)"
        case .contactTile(let block): return "contact-\(block.id)"
        case .note(let block): return "note-\(block.id)"
        case .policyGroup(let block): return "policies-\(block.id)"
        }
    }

    public var hasContent: Bool {
        switch self {
        case .summary(let block): return block.hasContent
        case .offerHighlight(let block): return block.hasContent
        case .chipGroup(let block): return block.hasContent
        case .priceTile(let block): return block.hasContent
        case .availabilityTile(let block): return block.hasContent
        case .contactTile(let block): return block.hasContent
        case .note(let block): return block.hasContent
        case .policyGroup(let block): return block.hasContent
        }
    }

    public var kind: ThreadDetailsVisualBlockKind {
        switch self {
        case .summary: return .summary
        case .offerHighlight: return .offerHighlight
        case .chipGroup: return .chipGroup
        case .priceTile: return .priceTile
        case .availabilityTile: return .availabilityTile
        case .contactTile: return .contactTile
        case .note: return .note
        case .policyGroup: return .policyGroup
        }
    }
}

public enum ThreadDetailsVisualBlockKind: String, Sendable, Hashable, Codable {
    case summary
    case offerHighlight
    case chipGroup
    case priceTile
    case availabilityTile
    case contactTile
    case note
    case policyGroup
}

public struct SummaryBlock: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var paragraphs: [String]

    public init(id: String = "primary", paragraphs: [String] = []) {
        self.id = id
        self.paragraphs = paragraphs
    }

    public var hasContent: Bool {
        paragraphs.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public struct OfferBlock: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var title: String?
    public var summary: String?

    public init(id: String = "primary", title: String? = nil, summary: String? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
    }

    public var hasContent: Bool {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !title.isEmpty || !summary.isEmpty
    }
}

public enum ThreadDetailsChipGroupStyle: String, Sendable, Hashable, Codable {
    case profile
    case serviceFit
    case openTo
    case interests
}

public struct ChipGroupBlock: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var style: ThreadDetailsChipGroupStyle
    public var title: String?
    public var chips: [String]

    public init(
        id: String,
        style: ThreadDetailsChipGroupStyle,
        title: String? = nil,
        chips: [String] = []
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.chips = chips
    }

    public var hasContent: Bool {
        chips.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public struct PriceTileBlock: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var primary: String?
    public var secondary: String?
    public var packageLines: [String]
    public var footnote: String?

    public init(
        id: String = "primary",
        primary: String? = nil,
        secondary: String? = nil,
        packageLines: [String] = [],
        footnote: String? = nil
    ) {
        self.id = id
        self.primary = primary
        self.secondary = secondary
        self.packageLines = packageLines
        self.footnote = footnote
    }

    public var hasContent: Bool {
        let primary = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secondary = secondary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let footnote = footnote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !primary.isEmpty
            || !secondary.isEmpty
            || !footnote.isEmpty
            || packageLines.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public struct AvailabilityTileBlock: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var primary: String?
    public var detailLines: [String]

    public init(id: String = "primary", primary: String? = nil, detailLines: [String] = []) {
        self.id = id
        self.primary = primary
        self.detailLines = detailLines
    }

    public var hasContent: Bool {
        let primary = primary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !primary.isEmpty
            || detailLines.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public enum ThreadDetailsContactRowKind: String, Sendable, Hashable, Codable {
    case name
    case business
    case email
    case phone
    case website
    case preferredMethod
    case area
    case hours
    case summary
    case other
}

public struct ThreadDetailsContactRow: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var kind: ThreadDetailsContactRowKind
    public var value: String

    public init(id: String, kind: ThreadDetailsContactRowKind, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }
}

public struct ContactTileBlock: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var rows: [ThreadDetailsContactRow]

    public init(id: String = "primary", rows: [ThreadDetailsContactRow] = []) {
        self.id = id
        self.rows = rows
    }

    public var hasContent: Bool {
        rows.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public struct NoteBlock: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var text: String

    public init(id: String = "primary", text: String = "") {
        self.id = id
        self.text = text
    }

    public var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct PolicyGroupBlock: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var items: [String]

    public init(id: String = "primary", items: [String] = []) {
        self.id = id
        self.items = items
    }

    public var hasContent: Bool {
        items.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
