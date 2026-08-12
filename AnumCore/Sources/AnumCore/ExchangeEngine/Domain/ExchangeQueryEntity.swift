import Foundation

public struct ExchangeQueryEntity: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: Kind
    public var rawText: String
    public var normalizedText: String
    public var confidence: Double
    public var provenance: Provenance
    public var hardConstraintEligible: Bool

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        rawText: String,
        normalizedText: String? = nil,
        confidence: Double = 0.0,
        provenance: Provenance = .unknown,
        hardConstraintEligible: Bool = false
    ) {
        let cleanedRaw = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .exchangeNormalizedWhitespace

        let normalizedCandidate = (normalizedText ?? cleanedRaw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .exchangeNormalizedWhitespace
            .lowercased()

        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : id
        self.kind = kind
        self.rawText = cleanedRaw
        self.normalizedText = normalizedCandidate
        self.confidence = Self.clamp(confidence)
        self.provenance = provenance
        self.hardConstraintEligible = hardConstraintEligible
    }

    public func isHighConfidence(threshold: Double = 0.80) -> Bool {
        confidence >= Self.clamp(threshold)
    }
}

public extension ExchangeQueryEntity {
    enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case serviceNeed
        case providerType
        case place
        case time
        case commercialIntent
        case scope
        case fulfillment
        case exclusion
        case unknown
    }

    enum Provenance: String, Codable, Sendable, Hashable, CaseIterable {
        case interpreter
        case deterministicExtractor
        case llmExtraction
        case userExplicit
        case carriedForward
        case unknown
    }
}

private extension ExchangeQueryEntity {
    static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}

private extension String {
    var exchangeNormalizedWhitespace: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
