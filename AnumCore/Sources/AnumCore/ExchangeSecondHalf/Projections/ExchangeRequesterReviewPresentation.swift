import Foundation

/// Optional hints from the live thread / Pass-2 agency context so requester review copy can name the opportunity.
public struct ExchangeRequesterReviewSurfaceContext: Sendable, Hashable, Equatable {
    public var subjectMatter: String?
    public var counterpartyDisplayName: String?
    public var offerTitle: String?
    public var profileDisplayName: String?
    public var profileHeadline: String?
    /// First surfaced region tag from offer or profile (projection hint only).
    public var regionHint: String?

    public init(
        subjectMatter: String? = nil,
        counterpartyDisplayName: String? = nil,
        offerTitle: String? = nil,
        profileDisplayName: String? = nil,
        profileHeadline: String? = nil,
        regionHint: String? = nil
    ) {
        self.subjectMatter = subjectMatter?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.counterpartyDisplayName = counterpartyDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.offerTitle = offerTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.profileDisplayName = profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.profileHeadline = profileHeadline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.regionHint = regionHint?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

/// Projection-layer copy shaping for requester-facing second-half review (capability 6–7).
public enum ExchangeRequesterReviewPresentation {

    // MARK: - Title

    public static func reviewCardTitle(
        qualification: ExchangeOpportunityQualification,
        frame: ExchangeDecisionFrame?,
        surface: ExchangeRequesterReviewSurfaceContext?
    ) -> String {
        _ = frame
        let offer = surface?.offerTitle
        let region = surface?.regionHint
        let profileName = surface?.profileDisplayName
        let headline = surface?.profileHeadline
        let subject = surface?.subjectMatter

        if let o = offer, let r = region, !r.isEmpty {
            let geo = "\(o) near \(r)"
            switch qualification.qualityTier {
            case .decisionReady, .strong:
                return clip("Strong fit: \(geo)", max: 56)
            case .promising:
                if !qualification.missingFacts.isEmpty {
                    return clip("Possible fit — needs detail: \(geo)", max: 60)
                }
                return clip("Possible match: \(geo)", max: 56)
            case .weak:
                return clip("Weak match — \(geo)", max: 56)
            }
        }

        let anchorLine = firstNonEmpty([offer, headline, profileName, subject])

        switch qualification.qualityTier {
        case .decisionReady, .strong:
            if let anchor = anchorLine {
                return clip("Strong fit: \(anchor)", max: 52)
            }
            return "Strong match to review"

        case .promising:
            if !qualification.missingFacts.isEmpty {
                if let anchor = anchorLine {
                    return clip("Possible fit — needs detail: \(anchor)", max: 56)
                }
                return "Needs details before recommendation"
            }
            if let anchor = anchorLine {
                return clip("Possible match: \(anchor)", max: 52)
            }
            return "Opportunity Review"

        case .weak:
            if let anchor = anchorLine {
                return clip("Weak match — \(anchor)", max: 52)
            }
            return "Weak match — clarify or keep searching"
        }
    }

    // MARK: - Subtitle (replaces raw Readiness: enum · first strength line)

    public static func reviewCardSubtitle(
        qualification: ExchangeOpportunityQualification,
        decisionNeeds: ExchangeRequesterDecisionNeeds?,
        fallbackStrengthFirstLine: String?
    ) -> String {
        let readiness = decisionNeeds?.decisionReadiness
        let prefix = readiness.map(userFacingReadinessPrefix) ?? ""

        let coreRaw = fallbackStrengthFirstLine?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let core = coreRaw.flatMap { sanitizeFitLine($0) } ?? ""

        let missingHint: String = {
            guard !qualification.missingFacts.isEmpty else { return "" }
            let joined = qualification.missingFacts.prefix(3).joined(separator: "; ")
            return clip(joined, max: 120)
        }()

        var pieces: [String] = []
        if !prefix.isEmpty { pieces.append(prefix) }
        if !core.isEmpty {
            let combined = pieces.joined(separator: " · ")
            if combined.range(of: core, options: .caseInsensitive) == nil {
                pieces.append(core)
            }
        }
        if !missingHint.isEmpty {
            pieces.append("Missing: \(missingHint)")
        }

        let out = pieces.joined(separator: " · ")
        if !out.isEmpty { return out }
        return "Review how this path fits your request."
    }

    private static func userFacingReadinessPrefix(_ readiness: ExchangeRequesterDecisionNeeds.Readiness) -> String {
        switch readiness {
        case .weak:
            return "Weak match so far"
        case .needsFacts:
            return "Worth clarifying before deciding"
        case .reviewReady:
            return "Ready for your review"
        case .decisionReady:
            return "Ready to decide"
        }
    }

    // MARK: - Strength / fact lines

    /// Maps qualifier/agency lines to user-facing copy and drops internal scaffolding.
    public static func sanitizedStrengthReasons(_ lines: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for raw in lines {
            guard let mapped = sanitizeFitLine(raw) else { continue }
            let key = mapped.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(mapped)
            if out.count >= 8 { break }
        }
        return out
    }

    public static func sanitizedWeaknessReasons(_ lines: [String]) -> [String] {
        sanitizedStrengthReasons(lines)
    }

    /// Removes internal agency/audit phrasing from free-text recommendation blocks.
    public static func sanitizedRecommendationBlock(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pieces = trimmed.split(separator: "\n").map(String.init)
        let kept = pieces.compactMap { line -> String? in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            if containsInternalRequesterLeak(t) { return nil }
            return t
        }

        let joined = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.nilIfBlank
    }

    /// Decision packet lines: keep user-meaningful facts; strip internal scaffolding.
    public static func sanitizedDecisionTextLines(_ lines: [String]) -> [String] {
        let filtered = ExchangeSecondHalfLocationResolver.filterPoisonedMissingFacts(lines)
        return filtered.compactMap { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            if containsInternalRequesterLeak(t) { return nil }
            return t
        }
    }

    /// Picks a packet summary that never echoes internal audit phrasing; prefers existing summary when clean.
    public static func decisionPacketSummary(frame: ExchangeDecisionFrame) -> String {
        let trimmed = frame.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !containsInternalRequesterLeak(trimmed) {
            return trimmed
        }
        let fromFacts = sanitizedDecisionTextLines(frame.clarifiedFacts).prefix(2).joined(separator: " ")
        if !fromFacts.isEmpty {
            return fromFacts
        }
        let fromReco = frame.recommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromReco.isEmpty, !containsInternalRequesterLeak(fromReco) {
            return fromReco
        }
        return "Review fit, open questions, and the suggested next step."
    }

    // MARK: - Internal leak detector (for tests)

    /// Sanitizes deterministic pause strings before persistence or UI handoff.
    public static func sanitizedPauseFrame(_ frame: ExchangeRequesterPauseFrame?) -> ExchangeRequesterPauseFrame? {
        guard let frame else { return nil }

        func cleanLine(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return nil }
            if containsInternalRequesterLeak(t) { return nil }
            return ExchangeUserFacingCopySanitizer.sanitize(t, field: .body) ?? t
        }

        let answered = sanitizedDecisionTextLines(frame.answeredFacts)
        let resolved = sanitizedDecisionTextLines(frame.resolvedMissingLabels)
        let still = sanitizedDecisionTextLines(frame.stillMissingFacts)
        let questions = sanitizedDecisionTextLines(frame.providerQuestions)
        let commitments = sanitizedDecisionTextLines(frame.commitmentSignals)
        let weakening = sanitizedDecisionTextLines(frame.weakeningSignals)

        let summary = cleanLine(frame.summaryLine) ?? frame.summaryLine
        let reco = cleanLine(frame.recommendationLine) ?? frame.recommendationLine
        let next = cleanLine(frame.nextActionLabel) ?? frame.nextActionLabel

        return ExchangeRequesterPauseFrame(
            answeredFacts: answered,
            resolvedMissingLabels: resolved,
            stillMissingFacts: still,
            providerQuestions: questions,
            commitmentSignals: commitments,
            weakeningSignals: weakening,
            fitMovement: frame.fitMovement,
            pauseReason: frame.pauseReason,
            summaryLine: summary,
            recommendationLine: reco,
            nextActionLabel: next,
            canContinueOnReply: frame.canContinueOnReply
        )
    }

    public static func containsInternalRequesterLeak(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "anchoring score",
            "offer row present",
            "row present",
            "candidate count",
            "surfaced candidate",
            "knownfacts",
            "known facts:",
            "unresolvedissues",
            "unresolved issues:",
            "qualificationstatus",
            "qualification status",
            "qualification:",
            "qualification tier",
            "stance snapshot",
            "pass 2",
            "pass 3",
            "pass2",
            "pass3",
            "os memory signals",
            "structured os memory",
            "disclosureceiling=",
            "reachability (snapshot): mode="
        ]
        return needles.contains { lower.contains($0) }
    }

    // MARK: - Private

    private static func sanitizeFitLine(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if containsInternalRequesterLeak(trimmed) { return nil }
        if ExchangeSecondHalfLocationResolver.isPoisonedMissingFactLine(trimmed) { return nil }

        let lower = trimmed.lowercased()

        if lower.hasPrefix("location anchored: near your current area")
            || lower == "near your current area" {
            return "Using current area"
        }
        if lower.hasPrefix("search area:") {
            return trimmed
        }

        if lower == "the thread already contains clarified facts." {
            return "Has enough thread detail to work with."
        }
        if lower == "a plausible candidate has already been surfaced." {
            return "A published listing or profile is selected."
        }
        if lower == "thread stance indicates meaningful progress." {
            return "Conversation is moving forward."
        }
        if lower == "thread stance is not yet strong enough." {
            return "Thread needs a bit more back-and-forth."
        }
        if lower == "no surfaced candidate is anchored yet." {
            return "No provider path is locked in yet."
        }
        if lower == "provider structured facts are available for routine answering." {
            return "Published details support routine answers."
        }
        if lower == "requester constraints are available to shape qualification." {
            return "Your request includes clear preferences."
        }
        if lower == "too much remains unresolved for clean surfacing." {
            return "Several details still need clearing up."
        }
        if lower == "the opportunity appears ready for decision framing." {
            return "Enough detail to shape a recommendation."
        }
        if lower == "the thread lacks enough concrete signal." {
            return "Not enough evidence yet to recommend."
        }

        return trimmed
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for v in values {
            if let t = v?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                return t
            }
        }
        return nil
    }

    private static func clip(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        let idx = s.index(s.startIndex, offsetBy: max)
        return String(s[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
