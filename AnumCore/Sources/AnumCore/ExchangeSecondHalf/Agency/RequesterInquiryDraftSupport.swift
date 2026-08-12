import Foundation

/// Requester autonomous inquiry drafting helpers — small grounded passes (not bulk templates).
public enum RequesterInquiryOpportunityLabel: Sendable {
    /// Source logged for UX/debug only.
    public enum Source: String, Sendable {
        case offerTitle
        case profileDisplayName
        case counterpartyName
        case fallbackThisOpportunity
    }

    public static func resolve(
        offer: ExchangeOffer?,
        publicProfile: ExchangePublicNodeProfile?,
        counterpartyDisplayName: String?
    ) -> (source: Source, label: String) {
        if let offer {
            let title = offer.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty,
               !ExchangeUserFacingCopySanitizer.isGenericExchangeTitle(title) {
                return (.offerTitle, title)
            }
        }
        if let name = publicProfile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return (.profileDisplayName, name)
        }
        if let name = counterpartyDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return (.counterpartyName, name)
        }
        return (.fallbackThisOpportunity, "this opportunity")
    }
}

enum RequesterInquiryQuestionNormalizer: Sendable {
    /// Strips planner/diagnostic scaffolding that must never leak to providers.
    static func isInternalDraftScaffold(_ line: String) -> Bool {
        containsInternalDraftScaffold(line)
    }

    /// Strips planner/diagnostic scaffolding that must never leak to providers.
    static func filteredUserFacingFactsAndGaps(_ lines: [String]) -> [String] {
        dedupePreserveOrder(lines.filter { !containsInternalDraftScaffold($0) }.compactMap(normalizeWhitespace))
    }

    /// Autonomous compose supplemental rows: empty when grounded compare succeeded (no gap backfill).
    static func autonomousComposeSupplementalRows(
        pass2LLMCompareSucceeded: Bool,
        missingFactsLines: [String],
        recommendedQuestionLines: [String]
    ) -> (missingFacts: [String], recommendedQuestions: [String]) {
        guard !pass2LLMCompareSucceeded else {
            return ([], [])
        }
        return (
            filteredUserFacingFactsAndGaps(missingFactsLines),
            filteredUserFacingFactsAndGaps(recommendedQuestionLines)
        )
    }

    /// Light-touch question shaping using explicit requester wording (not domain templates).
    static func normalizedProviderDirectedQuestions(
        originalRequesterText: String,
        missingFactsLines: [String],
        offerCategory: String?,
        providerDirectedQuestions: [String]
    ) -> [String] {
        let orig = originalRequesterText.lowercased()
        let filteredMissing = filteredUserFacingFactsAndGaps(missingFactsLines)
        let mergedMissing = filteredMissing.joined(separator: " ").lowercased()

        func logNorm(before: String, after: String, reason: String) {
            #if DEBUG
            let b = before.replacingOccurrences(of: "\n", with: " ").prefix(220)
            let a = after.replacingOccurrences(of: "\n", with: " ").prefix(220)
            Swift.print(
                "[RequesterQuestionNormalize] before=\(b) after=\(a) reason=\(reason)"
            )
            #endif
        }

        var out: [String] = []
        for raw in providerDirectedQuestions {
            let trimmed = normalizeWhitespace(raw) ?? ""
            guard !trimmed.isEmpty else { continue }
            if containsInternalDraftScaffold(trimmed) { continue }

            var line = trimmed
            let lower = line.lowercased()

            if lower.contains("price range") || lower.contains("pricing for this"),
               orig.contains("$") || orig.contains("million") || orig.contains("budget") {

                let budgetToken = inferredBudgetSnippet(
                    originalAndMissingLowercasedBlob: orig + "\n" + mergedMissing,
                    fallbackFromQuestion: trimmed
                )
                if !budgetToken.isEmpty {
                    let rewritten = sellerFacingOfferQuestion(
                        offerCategory: offerCategory,
                        budgetToken: budgetToken
                    )
                    if rewritten != trimmed {
                        logNorm(before: trimmed, after: rewritten, reason: "preservedRequesterConstraint_budget")
                        line = rewritten
                    }
                }
            }

            let wantsSoon = orig.contains("this week")
                || mergedMissing.contains("this week")
                || lower.contains("this week")
            let isGenericAppointment = lower.contains("earliest convenience")
                || (lower.contains("schedule") && lower.contains("view") && lower.contains("earliest"))

            if wantsSoon, isGenericAppointment {
                let cat = offerCategory?.lowercased() ?? ""
                let isRealEstate = cat.contains("real estate") || cat.contains("housing") || cat.contains("property")

                let preferViewing = isRealEstate
                    || orig.contains("viewing")
                    || mergedMissing.contains("viewing")
                    || lower.contains("viewing")

                let rewritten = preferViewing
                    ? "Is there availability for a viewing this week?"
                    : "Is there availability this week?"

                logNorm(before: trimmed, after: rewritten, reason: "preservedRequesterConstraint_timeline")
                line = rewritten
            }

            if let kept = normalizeWhitespace(line) {
                out.append(kept)
            }
        }

        return dedupePreserveOrder(out)
    }

    private static func containsInternalDraftScaffold(_ line: String) -> Bool {
        let lower = line.lowercased()
        let needles = [
            "outbound probe",
            "intent gap",
            "service gap",
            "services matching",
            "canonicalintent",
            "compare gap",
            "match caution",
            "match review",
            "reconcile this concern",
            "public-surface-aligned",
            "public surface aligned",
            "opportunityqualificationmissing",
            "second-half",
            "second half",
            "probedetected",
            "requestedthemeflags",
            "knownfactscount",
            "missingpreview",
            "recommendedpreview",
            "matched-provider details",
            "requester asked to confirm",
            "pricing, availability, location, or similar",
            "could you clarify:",
            "can you confirm whether",
            "could you confirm whether",
            "underspecified publicly",
            "underspecified",
            "geographic/service area",
            "service area fit",
            "geographic/service area fit",
            "area fit is underspecified",
            "fit is underspecified",
            "for this request",
            "for this job",
            "hardened timeline",
            "high-level cues",
            "high level cues",
            "rely on beyond",
            "beyond high-level",
            "grounding cues",
            "surface cues",
            "preferred contractor type",
            "general vs. specialized",
            "certification body",
            "certification standard"
        ]
        return needles.contains { lower.contains($0) }
    }

    private static func normalizeWhitespace(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func dedupePreserveOrder(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in lines {
            let key = line.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(line)
        }
        return out
    }

    private static func inferredBudgetSnippet(
        originalAndMissingLowercasedBlob blob: String,
        fallbackFromQuestion: String
    ) -> String {
        let text = blob
        /// Prefer `$1.8M`/`$420` style fragments anywhere in blob.
        if let slice = RegexHelpers.firstUSDAmountDisplay(in: text) {
            return slice
        }
        if let spelled = RegexHelpers.firstSpelledMillionBudget(in: text) {
            return spelled
        }
        let fq = fallbackFromQuestion.lowercased()
        if fq.contains("$") {
            let parts = fallbackFromQuestion.split(whereSeparator: { $0.isWhitespace })
            let withDollar = parts.first { $0.contains("$") }.map(String.init) ?? ""
            return withDollar.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func sellerFacingOfferQuestion(offerCategory: String?, budgetToken: String) -> String {
        let cat = offerCategory?.lowercased() ?? ""
        let b = budgetToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty else {
            return "Could you confirm pricing in line with the requester's expectations?"
        }
        if cat.contains("real estate") || cat.contains("property") || cat.contains("housing") {
            return "Would the seller consider an offer around \(b)?"
        }
        return "Could you confirm whether an offer around \(b) might be workable?"
    }
}

// MARK: - Regex helpers

private enum RegexHelpers {
    static func firstUSDAmountDisplay(in text: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"\$\s*([\d,.]+)(\s*[MmKk])?"#,
            options: []
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range(at: 0), in: text) else {
            return nil
        }
        return String(text[swiftRange]).replacingOccurrences(of: " ", with: "").nilIfBlank
    }

    static func firstSpelledMillionBudget(in text: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"(around|under|up to|approximately|approx\.?)\s*([\d,.]+|\d+)\s*(million|mm|m)\b"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range),
              let whole = Range(match.range(at: 0), in: text) else {
            return nil
        }
        return String(text[whole]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
