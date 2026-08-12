import Foundation

/// Strips near-me / device-anchor noise from retrieval lexicals when GPS+H3 resolved the anchor.
public enum ExchangeNearMeLexicalSanitizer: Sendable {
    private static let nearMePhrases = ["near me", "nearby me", "nearby"]
    private static let noiseTokens: Set<String> = ["me", "near", "nearby"]
    private static let nearMeNoiseValues: Set<String> = [
        "me", "near me", "nearby", "nearby me", "current location", "my location"
    ]
    private static let locationRailKeyNeedles = [
        "location", "locationtext", "place", "region", "area"
    ]

    /// Near-me resolved to a current-device H3 anchor; drop near-me text rails.
    public static func shouldStripNearMeLexicals(_ facets: ExchangeIntentFacets?) -> Bool {
        guard let facets else { return false }
        guard let anchor = facets.requesterSpatialAnchor,
              anchor.hasResolvedSpatial,
              anchor.source == .currentDevice || anchor.source == .savedDefault else {
            return false
        }
        if facets.locationRequirement?.kind == .nearMe {
            return true
        }
        if facets.locationRequirement?.spatial?.hasResolvedCells == true {
            return true
        }
        return false
    }

    public static func isNearMeLiteral(_ term: String) -> Bool {
        let lower = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if nearMePhrases.contains(lower) { return true }
        return lower == "near me" || lower == "nearby me" || lower == "nearby"
    }

    public static func isNearMeNoiseToken(_ term: String) -> Bool {
        let lower = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return noiseTokens.contains(lower)
    }

    public static func filterTerms(_ terms: [String]) -> [String] {
        terms.compactMap { term -> String? in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if isNearMeLiteral(trimmed) || isNearMeNoiseToken(trimmed) {
                return nil
            }
            return scrubNearMeFromPhrase(trimmed) ?? trimmed
        }
    }

    public static func filterInterpretationTags(_ tags: [String]) -> [String] {
        var out: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if isNearMeLiteral(trimmed) || isNearMeNoiseToken(trimmed) {
                continue
            }
            let lower = trimmed.lowercased()
            let containsNearMePhrase = nearMePhrases.contains { lower.contains($0) }
            if containsNearMePhrase {
                guard let scrubbed = scrubNearMeFromPhrase(trimmed) else { continue }
                let tokens = tokenize(scrubbed)
                for token in tokens where !isNearMeNoiseToken(token) && !isNearMeLiteral(token) {
                    out.append(token)
                }
                continue
            }
            out.append(trimmed)
        }
        return dedupePreservingOrder(out)
    }

    public static func sanitizeFacets(_ facets: ExchangeIntentFacets) -> ExchangeIntentFacets {
        guard shouldStripNearMeLexicals(facets) else { return facets }
        var copy = facets
        copy = stripPoisonedLocationRails(in: copy)
        copy.regionTerms = filterTerms(copy.regionTerms)
        copy.softLocationTerms = filterTerms(copy.softLocationTerms)
        copy.primaryKeywords = filterTerms(copy.primaryKeywords)
        copy.secondaryKeywords = filterTerms(copy.secondaryKeywords)
        copy.providerTerms = filterTerms(copy.providerTerms)
        copy.capabilityTerms = filterTerms(copy.capabilityTerms)
        copy.affinityTerms = filterTerms(copy.affinityTerms)
        copy = scrubLocationRequirementFields(in: copy)
        if var searchIntent = copy.searchIntent {
            searchIntent.broadRecallTokens = filterTerms(searchIntent.broadRecallTokens)
            searchIntent.places = searchIntent.places.filter { place in
                !isNearMeLiteral(place.normalizedText) &&
                !place.aliases.contains(where: isNearMeLiteral)
            }
            copy.searchIntent = searchIntent
        }
        return copy
    }

    public static func sanitizeInterpretedRequest(
        _ request: inout ExchangeInterpreter.InterpretedRequest
    ) {
        guard shouldStripNearMeLexicals(request.facets) else { return }
        request.facets = sanitizeFacets(request.facets)
        request.semanticTags = filterInterpretationTags(request.semanticTags)
        request.discoveryKeywords = filterInterpretationTags(request.discoveryKeywords)
        request.targetTags = filterInterpretationTags(request.targetTags)
    }

    // MARK: - Private

    private static func stripPoisonedLocationRails(
        in facets: ExchangeIntentFacets
    ) -> ExchangeIntentFacets {
        var copy = facets
        let locationTextBefore = copy.locationText
        var hardStripped = 0
        var softStripped = 0

        if let locationText = copy.locationText,
           isNearMeLiteral(locationText) || isNearMeNoiseToken(locationText) || isNearMeRailNoiseValue(locationText) {
            copy.locationText = nil
        }

        copy.hardRequirements = copy.hardRequirements.filter { req in
            if isLocationRailKey(req.key), isNearMeRailNoiseValue(req.value) {
                hardStripped += 1
                return false
            }
            return true
        }

        copy.softPreferences = copy.softPreferences.filter { pref in
            if isLocationRailKey(pref.key), isNearMeRailNoiseValue(pref.value) {
                softStripped += 1
                return false
            }
            return true
        }

        #if DEBUG
        if hardStripped > 0 || softStripped > 0 || locationTextBefore != copy.locationText {
            Swift.print(
                "[NearMeSanitizer] strippedLocationRails hard=\(hardStripped) soft=\(softStripped) " +
                    "locationTextBefore=\(locationTextBefore ?? "nil") locationTextAfter=\(copy.locationText ?? "nil") " +
                    "anchorResolved=true"
            )
        }
        #endif

        return copy
    }

    private static func isLocationRailKey(_ key: String) -> Bool {
        let lower = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return locationRailKeyNeedles.contains { lower.contains($0) }
    }

    private static func isNearMeRailNoiseValue(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if nearMeNoiseValues.contains(lower) { return true }
        return isNearMeLiteral(lower) || isNearMeNoiseToken(lower)
    }

    private static func scrubLocationRequirementFields(
        in facets: ExchangeIntentFacets
    ) -> ExchangeIntentFacets {
        var copy = facets
        guard var requirement = copy.locationRequirement else { return copy }
        if let phrase = requirement.sourcePhrase, isNearMeLiteral(phrase) {
            requirement.sourcePhrase = nil
        }
        if let name = requirement.normalizedName, isNearMeLiteral(name) || isNearMeNoiseToken(name) {
            requirement.normalizedName = nil
        }
        requirement.aliases = requirement.aliases.filter { !isNearMeLiteral($0) && !isNearMeNoiseToken($0) }
        copy.locationRequirement = requirement
        return copy
    }

    private static func scrubNearMeFromPhrase(_ phrase: String) -> String? {
        var text = phrase
        for pattern in nearMePhrases {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .caseInsensitive)
        }
        text = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func dedupePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let key = value.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(value)
        }
        return out
    }

}
