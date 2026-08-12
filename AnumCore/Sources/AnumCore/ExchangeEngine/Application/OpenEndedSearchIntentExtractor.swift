import Foundation

/// Requester-side hook for deriving `ExchangeCanonicalSearchIntent` from raw user text.
/// Current production path uses `CanonicalSearchIntentHeuristicExtractor`; an LLM-backed
/// implementation can swap in behind this boundary without changing retrieval/discovery compilers.
public protocol OpenEndedSearchIntentExtractor: Sendable {
    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
}

/// Async boundary for runtime-safe LLM-first extraction.
public protocol AsyncOpenEndedSearchIntentExtractor: Sendable {
    func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) async -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent?

    /// Latest extraction diagnostics, when the implementation records them (e.g. async LLM path).
    func lastExtractionDiagnostics() async -> SearchIntentExtractionDiagnostics?
}

public extension AsyncOpenEndedSearchIntentExtractor {
    func lastExtractionDiagnostics() async -> SearchIntentExtractionDiagnostics? {
        nil
    }
}

// MARK: - Heuristic implementation (offline / deterministic)

/// Deterministic lexical extractor used by default; mirrors legacy `ExchangeInterpreter` extraction.
public struct CanonicalSearchIntentHeuristicExtractor: OpenEndedSearchIntentExtractor {
    public init() {}

    public func extract(
        sourceText: String,
        intent: ExchangeIntent
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent? {
        let normalized = normalizeInput(sourceText)
        guard !normalized.isEmpty else { return nil }

        let lower = normalized.lowercased()
        let placeTokens = extractCanonicalPlaceTokens(from: normalized)
        let objectType = inferCanonicalObjectType(from: lower)
        let bedrooms = extractBedroomCount(from: lower)
        let hasSellerFinancing = containsAny(
            lower,
            ["seller financing", "vendor take back", "vendor-take-back", "vtb", "mortgage"]
        )
        let hasCommercialRobotics = containsAny(lower, ["commercial robotics", "robotics"])

        let domainCategory: ExchangeIntentFacets.DomainCategory = {
            if containsAny(lower, ["house", "home", "condo", "bedroom", "mortgage", "seller financing", "vendor take back"]) {
                return .realEstate
            }
            if containsAny(lower, ["roofer", "roofing", "plumber", "electrician", "contractor"]) {
                return .homeService
            }
            if containsAny(lower, ["commercial robotics", "robotics", "experience"]) {
                return .professionalService
            }
            return .general
        }()

        let transactionIntent: ExchangeIntentFacets.TransactionIntent? = {
            if containsAny(lower, ["for sale", "seller financing", "vendor take back"]) { return .forSale }
            if containsAny(lower, ["rent", "lease"]) { return .rent }
            if containsAny(lower, ["hire", "find a", "find someone"]) { return .hire }
            return nil
        }()

        var attributes: [ExchangeIntentFacets.StructuredAttribute] = []
        if let bedrooms {
            attributes.append(.init(key: "bedrooms", value: "\(bedrooms) bedroom", numericValue: Double(bedrooms)))
        }

        var timeConstraints: [ExchangeIntentFacets.StructuredTimeConstraint] = []
        if containsAny(lower, ["tomorrow"]) {
            timeConstraints.append(.init(kind: .day, text: "tomorrow"))
        }
        if containsAny(lower, ["today"]) {
            timeConstraints.append(.init(kind: .day, text: "today"))
        }
        if containsAny(lower, ["saturday"]) {
            timeConstraints.append(.init(kind: .day, text: "saturday"))
        }
        if containsAny(lower, ["sunday"]) {
            timeConstraints.append(.init(kind: .day, text: "sunday"))
        }

        var commercialConstraints: [ExchangeIntentFacets.StructuredCommercialConstraint] = []
        if hasSellerFinancing {
            commercialConstraints.append(
                .init(kind: .financing, key: "sellerFinancing", value: "seller financing", isHard: false)
            )
        }

        let lightweightDiscoveryHints: [String] = {
            var hints: [String] = []
            // Investor / startup discovery (keeps thin VC-style asks materially actionable at fallback confidence).
            if containsAny(lower, ["venture capital", "angel investor", "find a vc", "find vc"]) {
                hints.append("venture funding")
            }
            if containsAny(lower, ["seed"]) && containsAny(lower, ["fund", "funding", "invest", "investor", "startup", "startups", "stage"]) {
                hints.append("seed funding")
            }
            // Social / recreation asks that omit explicit object types (still give recall anchors).
            if containsAny(lower, ["ski buddy", "ski trip"]) || (containsAny(lower, ["ski"]) && containsAny(lower, ["buddy", "mount"])) {
                hints.append("ski")
            }
            return hints
        }()

        let semanticConcepts = sanitizeAtomicLegacyTerms(
            [
                objectType,
                hasCommercialRobotics ? "commercial robotics" : nil,
                hasSellerFinancing ? "seller financing" : nil,
                bedrooms.map { "\($0) bedroom" }
            ].compactMap { $0 } + lightweightDiscoveryHints,
            maxCount: 16
        )

        let broadRecallTokens = sanitizeAtomicLegacyTerms(
            semanticConcepts + placeTokens,
            maxCount: 24
        )

        // Place strength: `StructuredPlace` only exposes `isHard`. Default extracted locales (e.g. "in GTA")
        // are treated as soft for gates — strong matching uses confidence + region overlap without implying
        // automatic disqualification. Set `isHard` only when the user demands an exact locale (must/only/exact).
        // TODO(model): add explicit `PlaceStrength` enum when persistence contracts allow additive migration.
        let placeHard = inferExplicitHardCanonicalPlaceIntent(lower: lower)

        let places = placeTokens.map {
            ExchangeIntentFacets.StructuredPlace(
                normalizedText: $0,
                aliases: [],
                confidence: 0.9,
                isHard: placeHard
            )
        }

        let hardConstraints = intent.constraints.filter(\.isHardConstraint)
        let softPreferences = intent.constraints.filter { !$0.isHardConstraint }

        return ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: domainCategory,
            objectType: objectType,
            transactionIntent: transactionIntent,
            places: places,
            attributes: attributes,
            preferences: [],
            timeConstraints: timeConstraints,
            commercialConstraints: commercialConstraints,
            broadRecallTokens: broadRecallTokens,
            semanticConcepts: semanticConcepts,
            hardConstraints: hardConstraints,
            softPreferences: softPreferences,
            clarificationGaps: [],
            rawUserText: normalized
        )
    }
}

private extension CanonicalSearchIntentHeuristicExtractor {
    func normalizeInput(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    func inferExplicitHardCanonicalPlaceIntent(lower: String) -> Bool {
        containsAny(
            lower,
            [
                "must be in ",
                "must be near ",
                "only in ",
                "only near ",
                "only homes in ",
                "only houses in ",
                "has to be in ",
                "has to be near ",
                "strictly in ",
                "exactly in ",
                "exactly near "
            ]
        )
    }

    func extractCanonicalPlaceTokens(from text: String) -> [String] {
        let ns = text as NSString
        let patterns = [
            #"(?i)\b(?:in|near|around)\s+([a-z][a-z0-9\s\-]{0,64})"#,
            // "… to Mount St. Louis" — destination phrasing without "in/near/around".
            #"(?i)\bto\s+([a-z][a-z0-9\s\-\.]{0,64})"#
        ]

        var values: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: ns.length)
            )
            for match in matches where match.numberOfRanges > 1 {
                let raw = ns.substring(with: match.range(at: 1))
                let clipped = trimCanonicalClause(raw)
                if let token = clipped.nilIfBlank {
                    values.append(token.lowercased())
                }
            }
        }
        return sanitizeAtomicLegacyTerms(values, maxCount: 6)
    }

    func trimCanonicalClause(_ value: String) -> String {
        let boundaries = [",", ".", ";", " and ", " but ", " who ", " with ", " that ", " which ", " can ", " offers ", " offer "]
        var out = normalizeInput(value)
        for boundary in boundaries {
            if let range = out.lowercased().range(of: boundary) {
                out = String(out[..<range.lowerBound])
            }
        }
        return normalizeInput(out)
    }

    func inferCanonicalObjectType(from lower: String) -> String? {
        if containsAny(lower, ["house", "home"]) { return "house" }
        if containsAny(lower, ["roofer", "roofing"]) { return "roofer" }
        if containsAny(lower, ["commercial robotics", "robotics"]) { return "commercial robotics" }
        if containsAny(lower, ["someone"]) { return "someone" }
        return nil
    }

    func extractBedroomCount(from lower: String) -> Int? {
        let ns = lower as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*bed(?:room)?s?"#) else { return nil }
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        let captured = ns.substring(with: match.range(at: 1))
        return Int(captured)
    }

    func sanitizeRawPhraseList(
        _ values: [String],
        maxCount: Int
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for raw in values {
            let cleaned = raw.nilIfBlank?
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

            guard let cleaned, !cleaned.isEmpty else { continue }

            let lowered = cleaned.lowercased()
            guard !seen.contains(lowered) else { continue }

            seen.insert(lowered)
            out.append(String(cleaned.prefix(120)))

            if out.count >= maxCount { break }
        }

        return out
    }

    func sanitizeAtomicLegacyTerms(
        _ values: [String],
        maxCount: Int
    ) -> [String] {
        let filtered = values.filter { value in
            let lower = value.lowercased()
            return !lower.contains(", and ") &&
                !lower.contains(" and ") &&
                !lower.contains(" who ") &&
                !lower.contains(" with ")
        }
        return sanitizeRawPhraseList(filtered, maxCount: maxCount)
    }

    func sanitizeAtomicLegacyTerms(
        _ values: [String?],
        maxCount: Int
    ) -> [String] {
        sanitizeAtomicLegacyTerms(values.compactMap { $0 }, maxCount: maxCount)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
