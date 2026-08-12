import Foundation

/// Second-half projection of requester location need (no raw coordinates in phrases).
public struct ExchangeSecondHalfLocationFact: Sendable, Equatable, Hashable {
    public enum Source: String, Sendable, Equatable, Hashable {
        case none
        case explicitPlace
        case currentDevice
        case savedDefault
        case unresolvedNearMe
        case remote
    }

    public var source: Source
    public var isSatisfiedForCurrentStep: Bool
    public var hasSpatialAnchor: Bool
    public var canUseSpatialMatching: Bool
    public var shouldAskClarification: Bool
    public var userFacingLocationPhrase: String?
    public var modelSafeLocationPhrase: String?
    public var clarificationQuestion: String?
    public var debugSummary: String

    public init(
        source: Source,
        isSatisfiedForCurrentStep: Bool,
        hasSpatialAnchor: Bool,
        canUseSpatialMatching: Bool,
        shouldAskClarification: Bool,
        userFacingLocationPhrase: String? = nil,
        modelSafeLocationPhrase: String? = nil,
        clarificationQuestion: String? = nil,
        debugSummary: String
    ) {
        self.source = source
        self.isSatisfiedForCurrentStep = isSatisfiedForCurrentStep
        self.hasSpatialAnchor = hasSpatialAnchor
        self.canUseSpatialMatching = canUseSpatialMatching
        self.shouldAskClarification = shouldAskClarification
        self.userFacingLocationPhrase = Self.cleanPhrase(userFacingLocationPhrase)
        self.modelSafeLocationPhrase = Self.cleanPhrase(modelSafeLocationPhrase)
        self.clarificationQuestion = Self.cleanPhrase(clarificationQuestion)
        self.debugSummary = debugSummary
    }

    private static func cleanPhrase(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Canonical second-half location resolver for gap reduction, agency context, and UI projection.
public enum ExchangeSecondHalfLocationResolver: Sendable {
    private static let nearMeNoiseValues: Set<String> = [
        "me", "near me", "nearby", "nearby me", "current location", "my location"
    ]

    private static let locationRailKeyNeedles = [
        "location", "locationtext", "place", "region", "area"
    ]

    public static func resolve(facets: ExchangeIntentFacets?) -> ExchangeSecondHalfLocationFact {
        guard let facets else {
            return neutralFact(source: .none)
        }

        if let place = explicitPlaceName(from: facets) {
            let phrase = "Search area: \(place)"
            return ExchangeSecondHalfLocationFact(
                source: .explicitPlace,
                isSatisfiedForCurrentStep: true,
                hasSpatialAnchor: facets.requesterSpatialAnchor?.hasResolvedSpatial == true,
                canUseSpatialMatching: facets.requesterSpatialAnchor?.hasResolvedSpatial == true,
                shouldAskClarification: false,
                userFacingLocationPhrase: phrase,
                modelSafeLocationPhrase: phrase,
                clarificationQuestion: nil,
                debugSummary: "source=explicitPlace satisfied=true hasSpatial=\(facets.requesterSpatialAnchor?.hasResolvedSpatial == true)"
            )
        }

        if facets.locationRequirement?.kind == .remote {
            return ExchangeSecondHalfLocationFact(
                source: .remote,
                isSatisfiedForCurrentStep: true,
                hasSpatialAnchor: false,
                canUseSpatialMatching: false,
                shouldAskClarification: false,
                userFacingLocationPhrase: "Remote / online",
                modelSafeLocationPhrase: "Remote / online",
                clarificationQuestion: nil,
                debugSummary: "source=remote satisfied=true hasSpatial=false"
            )
        }

        if hasResolvedDeviceNearMe(facets: facets, source: .savedDefault) {
            return resolvedNearMeFact(source: .savedDefault, facets: facets)
        }

        if hasResolvedDeviceNearMe(facets: facets, source: .currentDevice) {
            return resolvedNearMeFact(source: .currentDevice, facets: facets)
        }

        if facets.locationRequirement?.kind == .nearMe {
            return ExchangeSecondHalfLocationFact(
                source: .unresolvedNearMe,
                isSatisfiedForCurrentStep: false,
                hasSpatialAnchor: false,
                canUseSpatialMatching: false,
                shouldAskClarification: true,
                userFacingLocationPhrase: nil,
                modelSafeLocationPhrase: nil,
                clarificationQuestion: "What city or area should I search in?",
                debugSummary: "source=unresolvedNearMe satisfied=false hasSpatial=false askClarification=true"
            )
        }

        return neutralFact(source: .none)
    }

    // MARK: - Requester location gap suppression

    /// True when requester location is already known for this step (not a missing user fact).
    public static func suppressesRequesterLocationGaps(_ fact: ExchangeSecondHalfLocationFact) -> Bool {
        guard fact.isSatisfiedForCurrentStep else { return false }
        switch fact.source {
        case .explicitPlace, .currentDevice, .savedDefault, .remote:
            return true
        case .none, .unresolvedNearMe:
            return false
        }
    }

    public static func shouldSkipRequesterLocationRail(
        key: String,
        value: String,
        locationFact: ExchangeSecondHalfLocationFact
    ) -> Bool {
        guard suppressesRequesterLocationGaps(locationFact) else { return false }
        if isLocationRailKey(key) { return true }
        return isPoisonedLocationRail(key: key, value: value)
    }

    public static func isRequesterLocationIntentGap(
        _ gap: ExchangeRequesterIntentGap,
        locationFact: ExchangeSecondHalfLocationFact
    ) -> Bool {
        guard suppressesRequesterLocationGaps(locationFact) else { return false }
        if gap.source == "secondHalfLocation" { return false }
        if gap.label == "Search area" { return false }

        if gap.kind == .region {
            return true
        }

        if let key = requirementKey(fromGapRequestedValue: gap.requestedValue),
           isLocationRailKey(key) {
            return true
        }

        let label = gap.label.lowercased()
        if label.contains("region (facets)") {
            return true
        }

        return false
    }

    public static func isProviderServeLocationQuestion(_ question: String) -> Bool {
        let lower = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        let serveCue = lower.contains("serve") || lower.contains("service area") || lower.contains("service coverage")
        let askCue = lower.contains("confirm whether") || lower.contains("can you confirm")
        return serveCue && askCue
    }

    public static func filterRequesterLocationMissingFactLines(
        _ lines: [String],
        locationFact: ExchangeSecondHalfLocationFact?
    ) -> [String] {
        let out = filterPoisonedMissingFacts(lines)
        guard let fact = locationFact, suppressesRequesterLocationGaps(fact) else {
            return out
        }
        return out.filter { !isRequesterLocationMissingFactLine($0) }
    }

    public static func filterProviderQuestionsWithoutSurface(
        _ questions: [String],
        hasAnchoredProviderSurface: Bool
    ) -> [String] {
        guard !hasAnchoredProviderSurface else { return questions }
        return questions.filter { !isProviderServeLocationQuestion($0) }
    }

    // MARK: - Poison detection (legacy textual rails)

    public static func isLocationRailKey(_ key: String) -> Bool {
        let lower = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return locationRailKeyNeedles.contains { lower.contains($0) }
    }

    public static func isNearMeNoiseValue(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if nearMeNoiseValues.contains(lower) { return true }
        return ExchangeNearMeLexicalSanitizer.isNearMeLiteral(lower)
            || ExchangeNearMeLexicalSanitizer.isNearMeNoiseToken(lower)
    }

    public static func isPoisonedLocationRail(key: String, value: String) -> Bool {
        isLocationRailKey(key) && isNearMeNoiseValue(value)
    }

    public static func isPoisonedLocationText(_ text: String) -> Bool {
        isNearMeNoiseValue(text)
    }

    public static func isPoisonedMissingFactLine(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }

        if lower.contains("locationtext: me")
            || lower.contains("location: me")
            || lower.contains("locationtext: near me")
            || lower.contains("location: near me") {
            return true
        }

        if lower.contains("confirm this requirement: locationtext")
            || lower.contains("confirm this requirement: location:") {
            return true
        }

        if lower.contains("could you clarify: intent gap")
            && (lower.contains("locationtext") || lower.contains("location: me")) {
            return true
        }

        return false
    }

    public static func filterPoisonedMissingFacts(_ lines: [String]) -> [String] {
        lines.filter { !isPoisonedMissingFactLine($0) }
    }

    /// Legacy opportunity-qualification copy that implies the requester location is unresolved.
    public static func isMisleadingRequesterLocationUnresolvedLine(
        _ line: String,
        locationFact: ExchangeSecondHalfLocationFact?
    ) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.contains("location fit boundaries"),
              lower.contains("your requirement"),
              lower.contains("unresolved") else {
            return false
        }
        return locationFact?.isSatisfiedForCurrentStep == true
    }

    public static func filterPoisonedRecommendedQuestions(_ lines: [String]) -> [String] {
        lines.filter { question in
            let lower = question.lowercased()
            if isPoisonedMissingFactLine(question) { return false }
            if lower.contains("confirm this requirement: locationtext") { return false }
            if lower.contains("locationtext: me") || lower.contains("location: me") { return false }
            return true
        }
    }

    public static func knownFactLine(for fact: ExchangeSecondHalfLocationFact) -> String? {
        guard fact.isSatisfiedForCurrentStep, let phrase = fact.userFacingLocationPhrase else {
            return nil
        }
        if fact.source == .explicitPlace {
            return phrase
        }
        return "Location anchored: \(phrase)"
    }

    /// Provider-side coverage gap when requester location is satisfied but no seller surface is anchored.
    public static func opportunityQualificationCoverageMiss(
        locationFact: ExchangeSecondHalfLocationFact,
        hasOffer: Bool,
        hasProfile: Bool
    ) -> String? {
        guard locationFact.isSatisfiedForCurrentStep else { return nil }
        guard !hasOffer, !hasProfile else { return nil }
        return "Provider service coverage is not anchored yet."
    }

    public static func uiDisplayPhrase(for fact: ExchangeSecondHalfLocationFact) -> String? {
        guard fact.isSatisfiedForCurrentStep else { return nil }
        switch fact.source {
        case .currentDevice, .savedDefault:
            return "Using current area"
        case .explicitPlace:
            return fact.userFacingLocationPhrase
        case .remote:
            return fact.userFacingLocationPhrase
        case .none, .unresolvedNearMe:
            return nil
        }
    }

    // MARK: - Private

    private static func neutralFact(source: ExchangeSecondHalfLocationFact.Source) -> ExchangeSecondHalfLocationFact {
        ExchangeSecondHalfLocationFact(
            source: source,
            isSatisfiedForCurrentStep: false,
            hasSpatialAnchor: false,
            canUseSpatialMatching: false,
            shouldAskClarification: false,
            userFacingLocationPhrase: nil,
            modelSafeLocationPhrase: nil,
            clarificationQuestion: nil,
            debugSummary: "source=\(source.rawValue) satisfied=false hasSpatial=false askClarification=false"
        )
    }

    private static func resolvedNearMeFact(
        source: ExchangeSecondHalfLocationFact.Source,
        facets: ExchangeIntentFacets
    ) -> ExchangeSecondHalfLocationFact {
        let phrase: String
        switch source {
        case .savedDefault:
            phrase = "Near your saved area"
        default:
            phrase = "Near your current area"
        }
        let hasSpatial = facets.requesterSpatialAnchor?.hasResolvedSpatial == true
            || facets.locationRequirement?.spatial?.hasResolvedCells == true
        return ExchangeSecondHalfLocationFact(
            source: source,
            isSatisfiedForCurrentStep: true,
            hasSpatialAnchor: hasSpatial,
            canUseSpatialMatching: hasSpatial,
            shouldAskClarification: false,
            userFacingLocationPhrase: phrase,
            modelSafeLocationPhrase: phrase,
            clarificationQuestion: nil,
            debugSummary: "source=\(source.rawValue) satisfied=true hasSpatial=\(hasSpatial)"
        )
    }

    private static func hasResolvedDeviceNearMe(
        facets: ExchangeIntentFacets,
        source: ExchangeRequesterSpatialAnchor.Source
    ) -> Bool {
        if let anchor = facets.requesterSpatialAnchor,
           anchor.source == source,
           anchor.hasResolvedSpatial {
            return facets.locationRequirement?.kind == .nearMe
                || facets.locationRequirement?.hasResolvedSpatialNearMe == true
        }
        if source == .currentDevice,
           facets.locationRequirement?.hasResolvedSpatialNearMe == true {
            return true
        }
        return false
    }

    private static func explicitPlaceName(from facets: ExchangeIntentFacets) -> String? {
        if let requirement = facets.locationRequirement, requirement.hasNamedPlace {
            let name = requirement.displayName
                ?? requirement.normalizedName
                ?? requirement.rawText
            if let cleaned = cleanedExplicitPlace(name) {
                return cleaned
            }
        }

        if let places = facets.searchIntent?.places {
            for place in places {
                let name = place.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let cleaned = cleanedExplicitPlace(name) {
                    return cleaned
                }
            }
        }

        if let placeName = facets.placeName, let cleaned = cleanedExplicitPlace(placeName) {
            return cleaned
        }

        if let locationText = facets.locationText, let cleaned = cleanedExplicitPlace(locationText) {
            return cleaned
        }

        return nil
    }

    private static func isRequesterLocationMissingFactLine(_ line: String) -> Bool {
        let lower = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if isPoisonedMissingFactLine(line) { return true }
        if lower.contains("intent gap (place / region") { return true }
        if lower.contains("intent gap (hard requirement"), lower.contains("locationtext:") { return true }
        if lower.contains("intent gap (soft preference"), lower.contains("location:") { return true }
        if lower.contains("intent gap (region (facets)") { return true }
        return false
    }

    private static func requirementKey(fromGapRequestedValue value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let key = trimmed[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private static func cleanedExplicitPlace(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isPoisonedLocationText(trimmed) { return nil }
        if ExchangeNearMeLexicalSanitizer.isNearMeLiteral(trimmed) { return nil }
        return trimmed
    }
}
