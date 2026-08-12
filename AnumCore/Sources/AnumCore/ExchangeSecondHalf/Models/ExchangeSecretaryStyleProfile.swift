import Foundation

public enum ExchangeSecretaryTone: String, Codable, CaseIterable, Hashable, Sendable {
    case neutral
    case warm
    case formal
    case concise
    case direct
}

public enum ExchangeWarmthDirectness: String, Codable, CaseIterable, Hashable, Sendable {
    case warm
    case balanced
    case direct
}

public enum ExchangeFirmnessLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case soft
    case balanced
    case firm
}

public enum ExchangeDisclosureStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case minimal
    case normal
    case transparent
}

public enum ExchangeInitiativeLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case conservative
    case balanced
    case proactive
}

public enum ExchangeNegotiationStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case relationshipFirst
    case balanced
    case efficiencyFirst
    case priceFirst
}

public enum ExchangeApprovalSensitivity: String, Codable, CaseIterable, Hashable, Sendable {
    case low
    case medium
    case high
}

/// User-defined secretary style and behavior preferences.
///
/// This keeps both requester-side and provider-side behavior grounded in the
/// user’s chosen representation rather than generic assistant tone.
public struct ExchangeSecretaryStyleProfile: Codable, Hashable, Sendable {
    public var tone: ExchangeSecretaryTone
    public var warmthDirectness: ExchangeWarmthDirectness
    public var firmness: ExchangeFirmnessLevel
    public var disclosureStyle: ExchangeDisclosureStyle
    public var initiativeLevel: ExchangeInitiativeLevel
    public var negotiationStyle: ExchangeNegotiationStyle
    public var approvalSensitivity: ExchangeApprovalSensitivity
    public var freeformInstructions: String?

    public init(
        tone: ExchangeSecretaryTone = .neutral,
        warmthDirectness: ExchangeWarmthDirectness = .balanced,
        firmness: ExchangeFirmnessLevel = .balanced,
        disclosureStyle: ExchangeDisclosureStyle = .normal,
        initiativeLevel: ExchangeInitiativeLevel = .balanced,
        negotiationStyle: ExchangeNegotiationStyle = .balanced,
        approvalSensitivity: ExchangeApprovalSensitivity = .medium,
        freeformInstructions: String? = nil
    ) {
        self.tone = tone
        self.warmthDirectness = warmthDirectness
        self.firmness = firmness
        self.disclosureStyle = disclosureStyle
        self.initiativeLevel = initiativeLevel
        self.negotiationStyle = negotiationStyle
        self.approvalSensitivity = approvalSensitivity
        self.freeformInstructions = freeformInstructions
    }
}

public extension ExchangeSecretaryStyleProfile {
    static let `default` = ExchangeSecretaryStyleProfile()

    var hasFreeformInstructions: Bool {
        guard let freeformInstructions else { return false }
        return !freeformInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Compact multi-line block for secretary ChatML representation / runner scaffold.
    /// Intended to be merged into `ExchangeIntelligenceModelRunRequest.representationSupplement`
    /// so structured tasks receive non-empty representation guidance alongside task JSON.
    func compactRepresentationPromptBlock() -> String {
        var lines: [String] = []
        lines.append("Secretary tone and behavior (profile):")
        lines.append("- tone: \(tone.rawValue)")
        lines.append("- warmth/directness: \(warmthDirectness.rawValue)")
        lines.append("- firmness: \(firmness.rawValue)")
        lines.append("- disclosure: \(disclosureStyle.rawValue)")
        lines.append("- initiative: \(initiativeLevel.rawValue)")
        lines.append("- negotiation: \(negotiationStyle.rawValue)")
        lines.append("- approval sensitivity: \(approvalSensitivity.rawValue)")
        if let f = freeformInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            let clipped = f.count > 400 ? String(f.prefix(400)) + "…" : f
            lines.append("- additional instructions: \(clipped)")
        }
        return lines.joined(separator: "\n")
    }

    /// Typed enums only (no freeform). Use `ExchangeSecretaryPromptInstructionBlocks.secretaryStyleGuideBlock` for voice freeform.
    func compactTypedStylePromptBlock() -> String {
        """
        Secretary tone and behavior (typed profile):
        - tone: \(tone.rawValue)
        - warmth/directness: \(warmthDirectness.rawValue)
        - firmness: \(firmness.rawValue)
        - disclosure: \(disclosureStyle.rawValue)
        - initiative: \(initiativeLevel.rawValue)
        - negotiation: \(negotiationStyle.rawValue)
        - approval sensitivity: \(approvalSensitivity.rawValue)
        """
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether this profile differs from the built-in default (for debug attribution).
    var isNonDefaultProfile: Bool {
        self != Self.default
    }
}
