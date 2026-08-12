import Foundation

/// Requester-side location need extracted from search text (gazetteer-optional).
public struct ExchangeLocationRequirement: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case none
        case namedPlace
        case nearPlace
        case nearMe
        case remote
        case hybrid
    }

    public enum Strictness: String, Codable, Sendable, Hashable {
        case unspecified
        case preferred
        case required
        case requiresClarification
        case notLocal
    }

    public var rawText: String?
    public var displayName: String?
    public var normalizedName: String?
    public var aliases: [String]
    public var kind: Kind
    public var strictness: Strictness
    public var sourcePhrase: String?
    public var extractionSource: String?
    /// Optional H3 footprint; nil for text-only or unresolved near-me without coordinates.
    public var spatial: ExchangeSpatialCoverage?

    public init(
        rawText: String? = nil,
        displayName: String? = nil,
        normalizedName: String? = nil,
        aliases: [String] = [],
        kind: Kind = .none,
        strictness: Strictness = .unspecified,
        sourcePhrase: String? = nil,
        extractionSource: String? = nil,
        spatial: ExchangeSpatialCoverage? = nil
    ) {
        self.rawText = Self.cleanOptional(rawText)
        self.displayName = Self.cleanOptional(displayName)
        let normalized = normalizedName.map {
            ExchangeLocationNormalization.normalize($0, stripRegionalSuffixes: true)
        } ?? ExchangeLocationNormalization.normalize(displayName ?? rawText ?? "", stripRegionalSuffixes: true)
        self.normalizedName = normalized.isEmpty ? nil : normalized
        self.aliases = Self.sanitizeAliases(aliases, excluding: self.normalizedName)
        self.kind = kind
        self.strictness = strictness
        self.sourcePhrase = Self.cleanOptional(sourcePhrase)
        self.extractionSource = Self.cleanOptional(extractionSource)
        self.spatial = spatial.normalizedOptional()
    }

    public static let none = ExchangeLocationRequirement(kind: .none, strictness: .unspecified)

    public var hasNamedPlace: Bool {
        guard let normalizedName, !normalizedName.isEmpty else { return false }
        switch kind {
        case .namedPlace, .nearPlace, .hybrid:
            return true
        case .none, .nearMe, .remote:
            return false
        }
    }

    public var requiresLocationEvidence: Bool {
        switch strictness {
        case .required:
            return kind != .none && kind != .remote
        case .preferred:
            return hasNamedPlace
        case .unspecified, .requiresClarification, .notLocal:
            return false
        }
    }

    public var needsClarification: Bool {
        strictness == .requiresClarification || (kind == .nearMe && strictness != .notLocal)
    }

    /// True when near-me is covered by a resolved spatial footprint (no text region rails).
    public var hasResolvedSpatialNearMe: Bool {
        kind == .nearMe && spatial?.hasResolvedCells == true
    }

    /// Soft terms for directory search / BM25 (display + normalized + aliases).
    public var searchTerms: [String] {
        var seen = Set<String>()
        var out: [String] = []

        func append(_ raw: String?) {
            guard let raw else { return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(trimmed)
            let normalized = ExchangeLocationNormalization.normalize(trimmed, stripRegionalSuffixes: true)
            if !normalized.isEmpty, !seen.contains(normalized) {
                seen.insert(normalized)
                out.append(normalized)
            }
        }

        append(displayName)
        append(rawText)
        if let normalizedName { append(normalizedName) }
        for alias in aliases { append(alias) }
        return out
    }

    /// Lexical place terms for retrieval/directory; empty when near-me is spatially resolved.
    public var lexicalSearchTerms: [String] {
        guard !hasResolvedSpatialNearMe else { return [] }
        return searchTerms
    }

    public func applyingLegacyFacetFields(
        locationText: String?,
        placeName: String?
    ) -> ExchangeLocationRequirement {
        var copy = self
        if copy.displayName == nil {
            copy.displayName = placeName ?? locationText
        }
        if copy.rawText == nil {
            copy.rawText = locationText ?? placeName
        }
        if copy.normalizedName == nil || copy.normalizedName?.isEmpty == true {
            let n = ExchangeLocationNormalization.normalize(
                copy.displayName ?? copy.rawText ?? "",
                stripRegionalSuffixes: true
            )
            copy.normalizedName = n.isEmpty ? nil : n
        }
        return copy
    }

    private static func cleanOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(160))
    }

    private static func sanitizeAliases(_ values: [String], excluding normalized: String?) -> [String] {
        var seen = Set<String>()
        if let normalized, !normalized.isEmpty {
            seen.insert(normalized)
        }
        var out: [String] = []
        for raw in values {
            let n = ExchangeLocationNormalization.normalize(raw, stripRegionalSuffixes: true)
            guard !n.isEmpty, !seen.contains(n) else { continue }
            seen.insert(n)
            out.append(n)
            if out.count >= 12 { break }
        }
        return out
    }
}

public enum ExchangeLocationRequirementBuilder {
  public static func build(
    from canonical: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
    sourceText: String,
    extractionSource: String
  ) -> ExchangeLocationRequirement? {
    let lower = sourceText.lowercased()

    if lower.contains("near me") || lower.contains("nearby me") {
      return ExchangeLocationRequirement(
        rawText: "near me",
        displayName: "near me",
        kind: .nearMe,
        strictness: .requiresClarification,
        sourcePhrase: "near me",
        extractionSource: extractionSource
      )
    }

    if lower.contains(" online") || lower.hasPrefix("online") ||
      lower.contains(" remote") || lower.contains(" virtual") {
      return ExchangeLocationRequirement(
        rawText: sourceText,
        displayName: "online",
        normalizedName: "online",
        kind: .remote,
        strictness: .notLocal,
        sourcePhrase: "online",
        extractionSource: extractionSource
      )
    }

    guard let firstPlace = canonical.places.first else { return nil }
    let display = firstPlace.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !display.isEmpty else { return nil }

    let nearPlace = lower.contains("near \(display)") || lower.contains("around \(display)")
    let kind: ExchangeLocationRequirement.Kind = nearPlace ? .nearPlace : .namedPlace
    let strictness: ExchangeLocationRequirement.Strictness = {
      if firstPlace.isHard { return .required }
      if canonical.extractionSource == .heuristicFallback { return .preferred }
      return .preferred
    }()

    return ExchangeLocationRequirement(
      rawText: display,
      displayName: display,
      normalizedName: ExchangeLocationNormalization.normalize(display, stripRegionalSuffixes: true),
      aliases: firstPlace.aliases,
      kind: kind,
      strictness: strictness,
      sourcePhrase: display,
      extractionSource: extractionSource
    )
  }

  public static func buildHeuristic(
    sourceText: String,
    places: [ExchangeIntentFacets.StructuredPlace]
  ) -> ExchangeLocationRequirement? {
    build(
      from: ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
        places: places,
        rawUserText: sourceText,
        extractionSource: .heuristicFallback
      ),
      sourceText: sourceText,
      extractionSource: SearchIntentExtractionSource.heuristicFallback.rawValue
    )
  }
}

private func mergeUniqueLocationTerms(_ values: [String], maxCount: Int) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for raw in values {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let key = trimmed.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        out.append(String(trimmed.prefix(120)))
        if out.count >= maxCount { break }
    }
    return out
}

public enum ExchangeLocationRequirementMapping {
    /// Maps a location requirement onto legacy facet fields for compatibility.
    public static func applyToFacets(
        _ requirement: ExchangeLocationRequirement?,
        facets: inout ExchangeIntentFacets
    ) {
        guard let requirement, requirement.kind != .none else {
            facets.locationRequirement = nil
            return
        }

        facets.locationRequirement = requirement

        if facets.locationText == nil {
            facets.locationText = requirement.displayName ?? requirement.rawText
        }
        if facets.placeName == nil {
            facets.placeName = requirement.displayName
        }

        let softTerms = requirement.lexicalSearchTerms
        if !softTerms.isEmpty {
            facets.softLocationTerms = mergeUniqueLocationTerms(
                facets.softLocationTerms + softTerms,
                maxCount: 16
            )
            facets.regionTerms = mergeUniqueLocationTerms(
                facets.regionTerms + softTerms,
                maxCount: 12
            )
        }

        switch requirement.strictness {
        case .required:
            facets.explicitRegionRequired = true
            facets.prefersLocalFirst = true
        case .preferred:
            if !facets.explicitRegionRequired {
                facets.prefersLocalFirst = true
            }
        case .requiresClarification:
            facets.allowsAutonomousClarification = true
        case .notLocal:
            facets.allowsRemoteOrShipped = true
            facets.fulfillmentMode = .remoteFriendly
        case .unspecified:
            break
        }

        switch requirement.kind {
        case .remote:
            facets.allowsRemoteOrShipped = true
            facets.fulfillmentMode = .remoteFriendly
        case .nearMe:
            facets.prefersLocalFirst = true
        case .namedPlace, .nearPlace, .hybrid:
            facets.prefersLocalFirst = true
        case .none:
            break
        }
    }

    public static func buildFromFacets(_ facets: ExchangeIntentFacets) -> ExchangeLocationRequirement? {
        if let existing = facets.locationRequirement, existing.kind != .none {
            return existing
        }

        let lower = [
            facets.locationText,
            facets.placeName,
            facets.searchIntent?.rawUserText
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if lower.contains("near me") || lower.contains("nearby") {
            return ExchangeLocationRequirement(
                rawText: facets.locationText ?? "near me",
                displayName: facets.placeName,
                kind: .nearMe,
                strictness: facets.explicitRegionRequired ? .requiresClarification : .preferred,
                sourcePhrase: "near me"
            )
        }

        if lower.contains("online") || lower.contains("remote") || lower.contains("virtual") {
            return ExchangeLocationRequirement(
                rawText: facets.locationText,
                displayName: facets.placeName,
                kind: .remote,
                strictness: .notLocal,
                sourcePhrase: facets.locationText
            )
        }

        if let place = facets.placeName ?? facets.locationText, !place.isEmpty {
            return ExchangeLocationRequirement(
                rawText: facets.locationText,
                displayName: place,
                kind: .namedPlace,
                strictness: facets.explicitRegionRequired ? .required : .preferred,
                sourcePhrase: facets.locationText
            )
        }

        return nil
    }
}
