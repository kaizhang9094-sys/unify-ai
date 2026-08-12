import Foundation

/// Compact requester intent grounding for Pass-2 requester-match compare (context only, not outbound copy).
public enum ExchangeRequesterCompareGroundingSummary: Sendable {

    public static func render(
        originalRequesterMessage: String,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?,
        thread: ExchangeThread?,
        facets: ExchangeIntentFacets?
    ) -> String? {
        var lines: [String] = []

        let message = originalRequesterMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            lines.append("originalMessage: \(message)")
        }

        if let facets {
            lines.append("queryIntentClass: \(facets.queryIntentClass.rawValue)")
            lines.append("surfacePreference: \(facets.surfacePreference.rawValue)")
            lines.append("routingSurface: \(routingSurfaceLabel(facets: facets))")
            if let locationLine = locationGroundingLine(facets: facets) {
                lines.append(locationLine)
            }
        } else if let thread {
            lines.append("queryIntentClass: \(thread.intent.queryIntentClass.rawValue)")
            lines.append("surfacePreference: \(thread.intent.surfacePreference.rawValue)")
        }

        if let searchIntent {
            lines.append(contentsOf: linesFromSearchIntent(searchIntent))
        }

        if let thread {
            lines.append(contentsOf: linesFromThreadIntent(thread.intent))
        }

        let deduped = dedupeLines(lines)
        guard !deduped.isEmpty else { return nil }
        return deduped.joined(separator: "\n")
    }

    // MARK: - Routing surface (prompt style hint)

    static func routingSurfaceLabel(facets: ExchangeIntentFacets) -> String {
        switch facets.queryIntentClass {
        case .offerSearch, .providerSearch, .directOutreach, .followUp, .statusCheck:
            return "provider/offer"
        case .capabilitySearch, .collaborationSearch:
            return "capability/collaboration"
        case .socialAffinitySearch:
            return "social/affinity"
        case .relationshipSearch:
            return "relationship"
        case .generalDiscovery:
            switch facets.surfacePreference {
            case .offer:
                return "provider/offer"
            case .capability:
                return "capability/collaboration"
            case .affinity:
                return "social/affinity"
            case .mixed:
                return "mixed"
            }
        }
    }

    // MARK: - Search intent

    private static func linesFromSearchIntent(
        _ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> [String] {
        var lines: [String] = []

        let tasks = ExchangeCanonicalSearchIntentTaskPhrases.topTaskPhrases(from: si, maxCount: 3)
        if !tasks.isEmpty {
            lines.append("task: \(tasks.joined(separator: "; "))")
        }

        if let object = si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines), !object.isEmpty {
            lines.append("object: \(object)")
        }

        let places = si.places.compactMap { place -> String? in
            let primary = place.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !primary.isEmpty else { return nil }
            if ExchangeSecondHalfLocationResolver.isPoisonedLocationText(primary) {
                return nil
            }
            let aliases = place.aliases
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != primary.lowercased() }
            if aliases.isEmpty { return primary }
            return "\(primary) (\(aliases.joined(separator: ", ")))"
        }
        if !places.isEmpty {
            lines.append("place: \(places.joined(separator: "; "))")
        }

        let times = si.timeConstraints
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !times.isEmpty {
            lines.append("time: \(times.joined(separator: "; "))")
        }

        let commercial = si.commercialConstraints.compactMap { cc -> String? in
            let value = cc.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return "\(cc.kind.rawValue)/\(cc.key): \(value)"
        }
        if !commercial.isEmpty {
            lines.append("commercial: \(commercial.joined(separator: "; "))")
        }

        let budgetRequired = si.commercialConstraints.contains { $0.kind == .budget }
            || budgetMentioned(in: si.rawUserText)
        lines.append("budgetOrPriceRequired: \(budgetRequired)")

        let credentialRequired = credentialMentioned(in: si.rawUserText)
        lines.append("credentialOrLicenseRequired: \(credentialRequired)")

        return lines
    }

    private static func linesFromThreadIntent(_ intent: ExchangeIntent) -> [String] {
        var lines: [String] = []
        if !intent.desiredOutcomes.isEmpty {
            lines.append("desiredOutcomes: \(intent.desiredOutcomes.map(\.rawValue).joined(separator: ", "))")
        }
        for c in intent.constraints.prefix(4) {
            let line = "\(c.key): \(c.value)".trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line != ":" else { continue }
            if ExchangeSecondHalfLocationResolver.isPoisonedLocationRail(key: c.key, value: c.value) {
                continue
            }
            lines.append("constraint: \(line)")
        }
        return lines
    }

    private static func locationGroundingLine(facets: ExchangeIntentFacets) -> String? {
        let fact = ExchangeSecondHalfLocationResolver.resolve(facets: facets)
        guard let phrase = fact.modelSafeLocationPhrase else { return nil }
        return "location: \(phrase)"
    }

    private static func budgetMentioned(in raw: String?) -> Bool {
        let lower = raw?.lowercased() ?? ""
        return lower.contains("budget") || lower.contains("price") || lower.contains("$")
    }

    private static func credentialMentioned(in raw: String?) -> Bool {
        let lower = raw?.lowercased() ?? ""
        return lower.contains("licensed") || lower.contains("license")
            || lower.contains("certified") || lower.contains("insured")
    }

    private static func dedupeLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in lines {
            let key = line.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(line)
        }
        return out
    }
}
