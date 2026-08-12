import Foundation

public struct ExchangeResolvedPlace: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var rawText: String
    public var normalizedText: String
    public var canonicalName: String
    public var canonicalID: String
    public var aliases: [String]
    public var parentRegionIDs: [String]
    public var confidence: Double
    public var source: Source

    public init(
        id: String? = nil,
        rawText: String,
        normalizedText: String? = nil,
        canonicalName: String,
        canonicalID: String,
        aliases: [String] = [],
        parentRegionIDs: [String] = [],
        confidence: Double = 0.0,
        source: Source = .unknown
    ) {
        let cleanedRaw = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .exchangeNormalizedWhitespace
        let cleanedCanonicalName = canonicalName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .exchangeNormalizedWhitespace
        let cleanedCanonicalID = canonicalID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .exchangeNormalizedWhitespace
        let cleanedNormalized = (normalizedText ?? cleanedRaw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .exchangeNormalizedWhitespace
            .lowercased()

        self.id = (id?.trimmingCharacters(in: .whitespacesAndNewlines).exchangeNilIfBlank)
            ?? cleanedCanonicalID
            .exchangeNilIfBlank
            ?? UUID().uuidString
        self.rawText = cleanedRaw
        self.normalizedText = cleanedNormalized
        self.canonicalName = cleanedCanonicalName
        self.canonicalID = cleanedCanonicalID
        self.aliases = Self.normalizeList(aliases)
        self.parentRegionIDs = Self.normalizeList(parentRegionIDs)
        self.confidence = Self.clamp(confidence)
        self.source = source
    }
}

public extension ExchangeResolvedPlace {
    enum Source: String, Codable, Sendable, Hashable, CaseIterable {
        case localGazetteer
        case serverEnriched
        case publisherProvided
        case llmSuggested
        case unresolved
        case unknown
    }
}

private extension ExchangeResolvedPlace {
    static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    static func normalizeList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let cleaned = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .exchangeNormalizedWhitespace
                .lowercased()
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            output.append(cleaned)
        }

        return output
    }
}

private extension String {
    var exchangeNormalizedWhitespace: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    var exchangeNilIfBlank: String? {
        isEmpty ? nil : self
    }
}
