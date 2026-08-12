import Foundation

/// Production fallback for `canonicalEnglishRetrievalText` when LLM enrichment fails on non-English surfaces.
/// Uses English-safe structured seller/offer facts only; never copies raw display or source blocks.
public enum ExchangeStructuredEnglishRetrievalCarrierBuilder {
    public static func surfaceAppearsNonEnglish(_ surface: ExchangeIndexedProviderSurface) -> Bool {
        let samples = [
            surface.displayName,
            surface.headline,
            surface.summary
        ].compactMap { $0 } + surface.sourceTextBlocks + surface.offers.flatMap(\.sourceTextBlocks)
        return samples.contains(where: ExchangeRetrievalEnglishProjection.containsSignificantNonEnglish)
    }

    /// Applies structured English carriers to profile and offer surfaces when enough English-safe facts exist.
    /// Returns nil when no carrier could be built.
    @discardableResult
    public static func apply(to surface: ExchangeIndexedProviderSurface) -> ExchangeIndexedProviderSurface? {
        var copy = surface
        var appliedAny = false

        if let profileCarrier = buildProfileCarrier(from: surface) {
            copy.canonicalEnglishRetrievalText = profileCarrier
            appliedAny = true
        }

        for index in copy.offers.indices {
            guard let offerCarrier = buildOfferCarrier(from: copy.offers[index]) else { continue }
            copy.offers[index].canonicalEnglishRetrievalText = offerCarrier
            appliedAny = true
        }

        return appliedAny ? copy : nil
    }

    public static func buildProfileCarrier(from surface: ExchangeIndexedProviderSurface) -> String? {
        var candidates: [String] = []
        candidates.append(contentsOf: surface.capabilityTerms)
        candidates.append(contentsOf: surface.semanticConcepts)
        candidates.append(contentsOf: surface.providerTerms)
        candidates.append(contentsOf: surface.regions.regionTags)
        candidates.append(contentsOf: surface.regions.regionAliases)
        candidates.append(contentsOf: surface.regions.serviceAreaNotes)
        candidates.append(contentsOf: surface.commercialConstraints.map(\.text))
        candidates.append(contentsOf: surface.timeAvailabilityConstraints.map(\.text))
        candidates.append(contentsOf: surface.retrievalSlices?.capabilityBlocks ?? [])
        let phrases = dedupePhrases(englishSafeStrings(candidates))
        return composeCarrier(from: phrases)
    }

    public static func buildOfferCarrier(from offer: ExchangeIndexedOfferSurface) -> String? {
        var candidates: [String] = []
        if let category = offer.category { candidates.append(category) }
        if let freeTextCategory = offer.freeTextCategory { candidates.append(freeTextCategory) }
        candidates.append(contentsOf: offer.objectIdentityTerms ?? [])
        candidates.append(contentsOf: offer.capabilityTerms)
        candidates.append(contentsOf: offer.affinityTerms)
        candidates.append(contentsOf: offer.serviceAreas.map(\.displayName))
        if let serviceAreaNote = offer.fulfillment.serviceAreaNote { candidates.append(serviceAreaNote) }
        if let leadTimeNote = offer.fulfillment.leadTimeNote { candidates.append(leadTimeNote) }
        if let capacityNote = offer.fulfillment.capacityNote { candidates.append(capacityNote) }
        candidates.append(contentsOf: offer.commercialConstraints.map(\.text))
        candidates.append(contentsOf: offer.timeAvailabilityConstraints.map(\.text))
        for slice in offer.packageSlices {
            candidates.append(slice.title)
            if let summary = slice.summary { candidates.append(summary) }
            candidates.append(slice.descriptiveText)
        }
        for slice in offer.faqSlices {
            candidates.append(slice.question)
            candidates.append(slice.answer)
        }
        let phrases = dedupePhrases(englishSafeStrings(candidates))
        return composeCarrier(from: phrases)
    }

    public static func hasAnyEnglishRetrievalCarrier(on surface: ExchangeIndexedProviderSurface) -> Bool {
        if ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(surface.canonicalEnglishRetrievalText) != nil {
            return true
        }
        return surface.offers.contains {
            ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish($0.canonicalEnglishRetrievalText) != nil
        }
    }

    private static func englishSafeStrings(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { value in
                guard !value.isEmpty else { return false }
                guard !ExchangeRetrievalEnglishProjection.containsSignificantNonEnglish(value) else { return false }
                return true
            }
    }

    private static func dedupePhrases(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(value)
        }
        return out
    }

    private static func composeCarrier(from phrases: [String]) -> String? {
        guard hasSufficientCarrierContent(phrases) else { return nil }
        let joined = phrases.joined(separator: ", ")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(500))
    }

    /// Requires at least two English word tokens across all phrases.
    private static func hasSufficientCarrierContent(_ phrases: [String]) -> Bool {
        let wordCount = phrases
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .count
        return wordCount >= 2
    }
}
