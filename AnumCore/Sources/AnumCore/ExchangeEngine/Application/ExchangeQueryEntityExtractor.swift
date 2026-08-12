import Foundation

public struct ExchangeQueryEntityExtractor: Sendable {
    public init() {}

    public func extractEntities(
        from text: String,
        intent: ExchangeIntent?,
        facets: ExchangeIntentFacets?
    ) -> [ExchangeQueryEntity] {
        let original = normalizeWhitespace(text)
        guard !original.isEmpty else { return [] }

        var entities: [ExchangeQueryEntity] = []
        let lower = original.lowercased()

        // Time phrases (deterministic lexical).
        let timePhrases = [
            "this weekend",
            "next weekend",
            "today",
            "tomorrow",
            "next week",
            "next saturday",
            "next sunday"
        ]
        for phrase in timePhrases where lower.contains(phrase) {
            entities.append(
                ExchangeQueryEntity(
                    kind: .time,
                    rawText: phrase,
                    confidence: 0.90,
                    provenance: .deterministicExtractor,
                    hardConstraintEligible: false
                )
            )
        }

        // Commercial intent phrases.
        let commercialPhrases = [
            "price",
            "cost",
            "quote",
            "budget",
            "under $",
            "under "
        ]
        for phrase in commercialPhrases where lower.contains(phrase) {
            entities.append(
                ExchangeQueryEntity(
                    kind: .commercialIntent,
                    rawText: phrase,
                    confidence: 0.88,
                    provenance: .deterministicExtractor,
                    hardConstraintEligible: false
                )
            )
        }

        // Place candidate from explicit prepositions (only when the span looks like a real
        // placename; avoids "in a few days" and other temporal fragments becoming `.place`).
        if let placeRaw = extractPlaceCandidate(from: original) {
            let clean = placeRaw.exchangeNormalizedWhitespace
            if isCleanExplicitPlace(clean) {
                entities.append(
                    ExchangeQueryEntity(
                        kind: .place,
                        rawText: clean,
                        confidence: 0.88,
                        provenance: .deterministicExtractor,
                        hardConstraintEligible: true
                    )
                )
            }
        } else if let placeFromFacet = facets?.placeName?.exchangeTrimmedNonEmpty {
            entities.append(
                ExchangeQueryEntity(
                    kind: .place,
                    rawText: placeFromFacet,
                    confidence: 0.70,
                    provenance: .interpreter,
                    hardConstraintEligible: false
                )
            )
        }

        // Service/provider need from leading phrase after removing place/time/commercial tails.
        if let serviceNeed = extractServiceNeed(from: original) {
            entities.append(
                ExchangeQueryEntity(
                    kind: .serviceNeed,
                    rawText: serviceNeed,
                    confidence: 0.86,
                    provenance: .deterministicExtractor,
                    hardConstraintEligible: false
                )
            )
        } else if let fallback = intent?.targetDescription?.exchangeTrimmedNonEmpty {
            entities.append(
                ExchangeQueryEntity(
                    kind: .serviceNeed,
                    rawText: fallback,
                    confidence: 0.62,
                    provenance: .interpreter,
                    hardConstraintEligible: false
                )
            )
        }

        return dedupe(entities)
    }
}

private extension ExchangeQueryEntityExtractor {
    func extractPlaceCandidate(from text: String) -> String? {
        let ns = text as NSString
        let pattern = #"(?i)\b(?:in|near|around)\s+([a-z][a-z\s\-]{0,60})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }

        let captured = ns.substring(with: match.range(at: 1))
        let clipped = trimAtClauseBoundary(captured)
        return clipped.exchangeTrimmedNonEmpty
    }

    func extractServiceNeed(from text: String) -> String? {
        var working = text.lowercased()
        working = working.replacingOccurrences(
            of: #"(?i)\b(?:in|near|around)\s+[a-z][a-z\s\-]{0,60}"#,
            with: "",
            options: .regularExpression
        )

        let trailingStops = [
            " this weekend",
            " next weekend",
            " next saturday",
            " next sunday",
            " next week",
            " today",
            " tomorrow",
            ", give me price",
            " give me price",
            " quote only",
            " under $",
            " under "
        ]
        for stop in trailingStops {
            if let range = working.range(of: stop) {
                working = String(working[..<range.lowerBound])
            }
        }

        let removePrefixes = ["find ", "need ", "looking for ", "please find "]
        for prefix in removePrefixes where working.hasPrefix(prefix) {
            working = String(working.dropFirst(prefix.count))
        }

        working = trimAtClauseBoundary(working)
        return working.exchangeTrimmedNonEmpty
    }

    func trimAtClauseBoundary(_ value: String) -> String {
        let boundaries = [
            ",", ".", ";", " and ", " but ", " because ", " this weekend", " next weekend",
            " next saturday", " next sunday", " next week", " today", " tomorrow",
            " give me", " quote", " price", " cost", " under $", " under "
        ]

        var out = value.exchangeNormalizedWhitespace
        for boundary in boundaries {
            if let range = out.lowercased().range(of: boundary.lowercased()) {
                out = String(out[..<range.lowerBound])
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isCleanExplicitPlace(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.isEmpty { return false }
        if lower.contains("weekend") || lower.contains("price") || lower.contains("quote") || lower.contains("cost") {
            return false
        }
        let words = lower.split(separator: " ")
        guard !words.isEmpty && words.count <= 3 else { return false }

        let blocked: Set<String> = [
            "a", "an", "the", "few", "day", "days", "week", "weeks",
            "month", "months", "today", "tomorrow", "saturday", "sunday"
        ]

        if words.contains(where: { blocked.contains(String($0)) }) {
            return false
        }

        return true
    }

    func dedupe(_ values: [ExchangeQueryEntity]) -> [ExchangeQueryEntity] {
        var seen = Set<String>()
        var out: [ExchangeQueryEntity] = []

        for value in values {
            guard !value.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let key = "\(value.kind.rawValue)||\(value.normalizedText)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(value)
        }
        return out
    }

    func normalizeWhitespace(_ value: String) -> String {
        value.exchangeNormalizedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var exchangeTrimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var exchangeNormalizedWhitespace: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
