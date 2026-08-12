import Foundation

/// Central place to strip internal / engineering language from strings that may reach
/// Secretary or Discovery UI. Storage and engines keep full text; this is display-only.
public enum ExchangeUserFacingCopySanitizer: Sendable {

    public enum Field: Sendable {
        case title
        case subtitle
        case body
        case status
        case general
    }

    /// Returns `nil` when the line should be dropped in favor of a caller-provided fallback.
    public static func sanitize(_ raw: String?, field: Field) -> String? {
        guard var line = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
            return nil
        }

        let lower = line.lowercased()

        if shouldDropEntirely(lower) {
            return nil
        }

        if let mapped = phraseReplacement(for: lower, original: line) {
            line = mapped
        }

        line = stripKnownInternalPrefixes(line)

        line = applyExchangePersonVocabulary(line)

        if looksLikeRawIdentifier(lower), field != .title {
            return nil
        }

        if field == .title, isLikelyRawNodeTitle(line) {
            return shortenNodeLabel(line) ?? "New activity"
        }

        let clipped = clip(line, field: field)
        return clipped.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    public static func sanitizeOrFallback(_ raw: String?, field: Field, fallback: String) -> String {
        sanitize(raw, field: field) ?? fallback
    }

    /// Workspace / thread titles that must not substitute for real requester wording in outbound drafts.
    public static func isGenericExchangeTitle(_ title: String) -> Bool {
        let collapsed = normalizedGenericTitleKey(title)
        guard !collapsed.isEmpty else { return false }
        let compact = collapsed.replacingOccurrences(of: " ", with: "")

        let genericSpaced: Set<String> = [
            "find",
            "find match",
            "find provider",
            "find shared interest match",
            "request",
            "draft message",
            "search",
            "match",
            "new exchange",
            "untitled exchange",
            "provider path",
            "result path"
        ]
        let genericCompact: Set<String> = [
            "find",
            "findmatch",
            "findprovider",
            "findsharedinterestmatch",
            "request",
            "draftmessage",
            "search",
            "match",
            "newexchange",
            "untitledexchange",
            "providerpath",
            "resultpath"
        ]
        if genericSpaced.contains(collapsed) || genericCompact.contains(compact) { return true }
        if compact.hasPrefix("findmatch") || compact.hasPrefix("findprovider") { return true }
        if collapsed.hasPrefix("find match") || collapsed.hasPrefix("find provider") { return true }
        if collapsed.hasPrefix("find shared interest") || compact.hasPrefix("findsharedinterest") {
            return true
        }
        return false
    }

    /// Lowercases, collapses whitespace, and strips punctuation so scaffold titles match across formatting variants.
    private static func normalizedGenericTitleKey(_ title: String) -> String {
        let collapsed = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(\s)+"#, with: " ", options: .regularExpression)
            .lowercased()
        let alnumAndSpace = CharacterSet.alphanumerics.union(.whitespaces)
        let stripped = collapsed.unicodeScalars
            .filter { alnumAndSpace.contains($0) }
            .map { Character($0) }
        let joined = String(stripped)
            .replacingOccurrences(of: #"(\s)+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined
    }

    public struct FederationBodySanitizeResult: Sendable, Hashable {
        public let cleaned: String
        public let removedInternalScaffold: Bool
        public let forbiddenTermsFound: [String]
        public let usedMinimalSafeFallback: Bool
        public let fallbackReason: String?

        public init(
            cleaned: String,
            removedInternalScaffold: Bool,
            forbiddenTermsFound: [String],
            usedMinimalSafeFallback: Bool = false,
            fallbackReason: String? = nil
        ) {
            self.cleaned = cleaned
            self.removedInternalScaffold = removedInternalScaffold
            self.forbiddenTermsFound = forbiddenTermsFound
            self.usedMinimalSafeFallback = usedMinimalSafeFallback
            self.fallbackReason = fallbackReason
        }
    }

    public static let forbiddenFederationScaffoldTerms: [String] = [
        "Draft grounded on published facts:",
        "response-response-inbound",
        "Response - Inbound message from node",
        "Response — Inbound message from node",
        "Inbound message from node-",
        "Hi node-",
        "Outbound probe:",
        "requester asked to confirm",
        "matched-provider details",
        "pricing, availability, location, or similar",
        "Intent gap",
        "Compare gap",
        "Match caution",
        "OpportunityQualificationMissing",
        "probeDetected",
        "requestedThemeFlags",
        "knownFactsCount",
        "missingPreview",
        "recommendedPreview",
        "Second-half",
        "second-half"
    ]

    /// Control separator unlikely to occur in prose (draft metadata stitching only).
    public static let requesterSafeQuestionMetadataSeparator = "\u{001E}"

    /// Final relay-visible body sanitization — uses optional agency metadata for a bounded safe fallback body.
    public static func sanitizedFederationUserVisibleOutboundBody(
        raw: String,
        draftMetadata: [String: String]
    ) -> FederationBodySanitizeResult {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return FederationBodySanitizeResult(cleaned: "", removedInternalScaffold: false, forbiddenTermsFound: [])
        }

        var working = aggressivelyStripInternalScaffolding(from: base)
        working = purgeSentencesContainingForbiddenSubstrings(working)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let remainingTerms = matchedForbiddenSubstringTerms(in: working)
        if remainingTerms.isEmpty {
            let baseResult = finalizeFederationBodyCandidate(working, originalTrimmed: base)
            return FederationBodySanitizeResult(
                cleaned: baseResult.cleaned,
                removedInternalScaffold: baseResult.removedInternalScaffold,
                forbiddenTermsFound: [],
                usedMinimalSafeFallback: false,
                fallbackReason: nil
            )
        }

        let safeEnabled = draftMetadata["agency_inquiry_safe_enabled"] == "true"
        let safeOppTrimmed = draftMetadata["agency_inquiry_safe_opportunity"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard safeEnabled, !safeOppTrimmed.isEmpty else {
            let ultra = minimalSafeRequesterInquiryFallbackBody(opportunity: "this opportunity", normalizedQuestions: [])
            let ultraTerms = matchedForbiddenSubstringTerms(in: ultra)
            if ultraTerms.isEmpty {
                return FederationBodySanitizeResult(
                    cleaned: ultra,
                    removedInternalScaffold: true,
                    forbiddenTermsFound: remainingTerms,
                    usedMinimalSafeFallback: true,
                    fallbackReason: "forbidden_ultra_fallback_no_agency_safe_metadata"
                )
            }

            return FederationBodySanitizeResult(
                cleaned: "",
                removedInternalScaffold: true,
                forbiddenTermsFound: remainingTerms + ultraTerms,
                usedMinimalSafeFallback: true,
                fallbackReason: "forbidden_blocked_no_safe_construct"
            )
        }

        let opp = safeOppTrimmed
        let rawQs = draftMetadata["agency_inquiry_safe_questions"] ?? ""
        let qs = rawQs
            .split(whereSeparator: { $0 == Character(ExchangeUserFacingCopySanitizer.requesterSafeQuestionMetadataSeparator) })
            .map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        let fallback = minimalSafeRequesterInquiryFallbackBody(opportunity: opp, normalizedQuestions: Array(qs.prefix(2)))

        let fbTerms = matchedForbiddenSubstringTerms(in: fallback)
        if !fbTerms.isEmpty {
            return FederationBodySanitizeResult(
                cleaned: "",
                removedInternalScaffold: true,
                forbiddenTermsFound: fbTerms + remainingTerms,
                usedMinimalSafeFallback: true,
                fallbackReason: "forbidden_even_on_fallback_construct"
            )
        }

        return FederationBodySanitizeResult(
            cleaned: fallback,
            removedInternalScaffold: true,
            forbiddenTermsFound: remainingTerms,
            usedMinimalSafeFallback: true,
            fallbackReason: "forbidden_scaffold_remaining"
        )
    }

    public static func cleanFederationUserVisibleBody(_ raw: String) -> FederationBodySanitizeResult {
        cleanFederationBodyInternal(raw)
    }

    public static func cleanReceivedFederationBody(_ raw: String) -> FederationBodySanitizeResult {
        cleanFederationBodyInternal(raw)
    }

    /// Collapses obvious node-id-only titles to a short, human label.
    public static func shortenNodeLabel(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard lower.hasPrefix("node-") else { return nil }

        let tail = trimmed.dropFirst("node-".count)
        let prefix = String(tail.prefix(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return "Network contact" }
        return "Network contact (\(prefix)…)"
    }

    /// Display-only label when a contact has no display name (Contacts / trust surfaces).
    public static func contactHandleLine(fromNodeID raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "Contact" }
        if t.count <= 14 {
            return "Contact handle (\(t))"
        }
        let prefix = String(t.prefix(8))
        return "Contact handle (\(prefix)…)"
    }

    // MARK: - Internals

    private static func shouldDropEntirely(_ lower: String) -> Bool {
        let needles = [
            "deterministic public structures",
            "safe autonomous coordination",
            "provider-facing search",
            "pass 1", "pass 2", "pass1", "pass2",
            "hydrated seller",
            "agency planner",
            "decision frame",
            "clarified facts",
            "selected counterparty",
            "balanced tone",
            "providerpartialanswerorescalation",
            "retrieval score",
            "body hash",
            "llm accepted",
            "runtime mode"
        ]

        for n in needles where lower.contains(n) {
            return true
        }

        return false
    }

    private static func cleanFederationBodyInternal(_ raw: String) -> FederationBodySanitizeResult {
        let originalTrimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if originalTrimmed.isEmpty {
            return FederationBodySanitizeResult(cleaned: "", removedInternalScaffold: false, forbiddenTermsFound: [])
        }
        let out = finalizeFederationBodyCandidate(
            aggressivelyStripInternalScaffolding(from: originalTrimmed),
            originalTrimmed: originalTrimmed
        )
        return FederationBodySanitizeResult(
            cleaned: out.cleaned,
            removedInternalScaffold: out.removedInternalScaffold,
            forbiddenTermsFound: matchedForbiddenSubstringTerms(in: out.cleaned)
        )
    }

    /// Non-blocking legacy helper for inbound payloads (no autonomous inquiry fallback semantics).
    private static func finalizeFederationBodyCandidate(
        _ cleanedCandidate: String,
        originalTrimmed: String
    ) -> (cleaned: String, removedInternalScaffold: Bool) {
        var candidate = cleanedCandidate.trimmingCharacters(in: .whitespacesAndNewlines)

        candidate = candidate.replacingOccurrences(
            of: "Response — Response —",
            with: "Response —",
            options: [.caseInsensitive]
        )
        candidate = candidate.replacingOccurrences(
            of: "Response - Response -",
            with: "Response -",
            options: [.caseInsensitive]
        )

        let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBody = cleaned.isEmpty ? originalTrimmed : cleaned
        let forbidden = matchedForbiddenSubstringTerms(in: finalBody)
        let removed = finalBody != originalTrimmed || !forbidden.isEmpty
        return (finalBody, removed)
    }

    private static func aggressivelyStripInternalScaffolding(from originalTrimmed: String) -> String {
        var candidate = originalTrimmed
        var removed = false

        if let stripped = stripPrefixCaseInsensitive(
            candidate,
            prefix: "Draft grounded on published facts:"
        ) {
            candidate = stripped
            removed = true
        }

        if let boundary = rangeOfDivider(candidate) {
            let afterDivider = String(candidate[boundary.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if looksLikeLikelyInternalScaffoldPrefix(afterDivider) {
                candidate = String(candidate[..<boundary.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                removed = true
            }
        }

        var lines = candidate
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        lines = lines.filter { line in
            let lower = line.lowercased()
            let termHit = forbiddenFederationSubstrings(forScanningOnly: lower)
            if !termHit.isEmpty { removed = true; return false }
            if lower.contains("response-response-inbound") { removed = true; return false }
            if lower.hasPrefix("response - inbound message from node")
                || lower.hasPrefix("response — inbound message from node")
                || lower.hasPrefix("inbound message from node-") {
                removed = true
                return false
            }
            if lower.hasPrefix("hi node-") {
                removed = true
                return false
            }
            return true
        }

        candidate = lines.joined(separator: "\n")
        let _ = removed
        return candidate
    }

    private static func purgeSentencesContainingForbiddenSubstrings(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        var segments: [String] = []
        var buffer = ""

        func flushSentence() {
            let s = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll(keepingCapacity: true)
            guard !s.isEmpty else { return }
            if forbiddenFederationSubstrings(forScanningOnly: s.lowercased()).isEmpty {
                segments.append(s)
            }
        }

        for char in trimmed {
            buffer.append(char)
            /// Avoid splitting on "." so decimals like `$1.8M` aren't torn apart.
            if char == "!" || char == "?" || char == "\n" {
                flushSentence()
            }
        }

        flushSentence()

        guard !segments.isEmpty else { return "" }

        /// Keep light paragraph breaks via double newline cues.
        return segments.joined(separator: " ")
    }

    private static func forbiddenFederationSubstrings(forScanningOnly lowercasedText: String) -> [String] {
        forbiddenFederationSubstrings(forScanning: lowercasedText)
    }

    private static func forbiddenFederationSubstrings(forScanning lowercasedText: String) -> [String] {
        forbiddenFederationScaffoldTerms.compactMap { term in
            lowercasedText.contains(term.lowercased()) ? term : nil
        }
    }

    private static func matchedForbiddenSubstringTerms(in input: String) -> [String] {
        forbiddenFederationSubstrings(forScanning: input.lowercased())
    }

    /// Minimal outbound when autonomous inquiry draft still contains scaffolding after sanitization tries.
    public static func minimalSafeRequesterInquiryFallbackBody(
        opportunity: String,
        normalizedQuestions: [String]
    ) -> String {
        let opp = opportunity
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let trimmedOpp = opp.isEmpty ? "this opportunity" : opp

        let qs = normalizedQuestions.prefix(2)
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "?.! "))
            }
            .filter { !$0.isEmpty }

        if qs.count >= 2 {
            return "Hi — I'm checking on \(trimmedOpp). Could you confirm \(qs[0]), and \(qs[1])?"
        }
        if let only = qs.first {
            return "Hi — I'm checking on \(trimmedOpp). Could you confirm \(only)?"
        }
        return "Hi — I'm checking on \(trimmedOpp)."
    }

    private static func matchedForbiddenTerms(in input: String) -> [String] {
        matchedForbiddenSubstringTerms(in: input)
    }

    private static func stripPrefixCaseInsensitive(_ input: String, prefix: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        return String(trimmed[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rangeOfDivider(_ input: String) -> Range<String.Index>? {
        if let exact = input.range(of: "\n---\n") {
            return exact
        }
        return input.range(of: "---")
    }

    private static func looksLikeLikelyInternalScaffoldPrefix(_ input: String) -> Bool {
        let lower = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("hi node-")
            || lower.hasPrefix("response - inbound message from node")
            || lower.hasPrefix("response — inbound message from node")
            || lower.hasPrefix("inbound message from node-")
            || lower.hasPrefix("response-response-inbound")
    }

    private static func phraseReplacement(for lower: String, original: String) -> String? {
        if lower == "filed" || lower == "filed." { return "Added to conversation" }
        if lower.contains("reply filed") { return "Linked to conversation" }
        if lower == "matchfound" { return "Ready to review" }
        if lower == "awaitingproviderclarification" { return "Waiting for response" }
        if lower == "awaitingrequesterclarification" { return "Needs your reply" }
        if lower.contains("reception note") { return "New message" }
        if lower.contains("already filed") { return "Added to your exchange" }
        if lower.contains("linked thread") { return "Connected to your exchange" }
        if lower.contains("decision frame") || lower == "decision packet" { return "Ready to review" }
        if lower.contains("clarified facts") { return "Key details" }
        if lower.contains("selected counterparty") { return "Contact" }
        if lower.contains("balanced tone") { return "Draft ready" }
        if lower.contains("provider reception") && lower.count < 40 { return "New message" }

        if lower.contains("providerpartialanswerorescalation") {
            return "Needs your reply"
        }

        return nil
    }

    private static func stripKnownInternalPrefixes(_ input: String) -> String {
        var out = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns: [String] = [
            "(?i)^draft grounded on published facts:\\s*",
            "(?i)^response\\s*[—-]\\s*inbound message from node[-a-z0-9\\.]*\\s*",
            "(?i)^response-response-inbound message from node[-a-z0-9\\.]*\\s*",
            "(?i)^inbound message from node[-a-z0-9\\.]*\\s*",
            "(?i)^hi\\s+node-[a-z0-9-]+[,!]?\\s*"
        ]
        for pattern in patterns {
            out = out.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        out = out.replacingOccurrences(of: "(?i)response\\s*[—-]\\s*response\\s*[—-]\\s*", with: "Response — ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generic message for UI surfaces that must not echo `localizedDescription`.
    public static func userFacingLoadFailure(for error: Error, debugLabel: String) -> String {
        #if DEBUG
        Swift.print("[\(debugLabel)] \(String(reflecting: error)) localized=\(error.localizedDescription)")
        #endif
        if case ExchangePrivateE2EESendBlockedError.blocked = error {
            return ExchangePrivateE2EESendBlockedError.userFacingMessage
        }
        if case ExchangeFederationError.e2eeSendBlocked = error {
            return ExchangePrivateE2EESendBlockedError.userFacingMessage
        }
        if case ExchangeDMAttachmentClientError.encryptedDecryptFailed = error {
            return "Encrypted attachment could not be opened."
        }
        if error is ExchangeAttachmentOpenerError {
            return "Encrypted attachment could not be opened."
        }
        return "Something went wrong. Pull to refresh."
    }

    /// Display-only wording pass for strings that may not go through `sanitize` elsewhere.
    public static func applyExchangePersonVocabulary(_ input: String) -> String {
        var s = input
        let pairs: [(String, String)] = [
            ("Threads", "Exchanges"),
            ("threads", "exchanges"),
            ("Thread", "Exchange"),
            ("thread", "exchange"),
            ("Trusted Paths", "Connections"),
            ("Trusted paths", "Connections"),
            ("trusted paths", "connections"),
            ("Trusted path", "Connection"),
            ("trusted path", "connection"),
            (" node ", " contact "),
            ("Federation", "Network"),
            ("federation", "network"),
            ("Second-half", "Follow-up"),
            ("second-half", "follow-up"),
            ("Second half", "Follow-up"),
            ("second half", "follow-up"),
            ("public profile", "contact card"),
            ("Public profile", "Contact card"),
            ("offer ID", "offer"),
            ("Offer ID", "Offer"),
            ("profile ID", "profile"),
            ("Profile ID", "Profile"),
            ("trust edge", "saved trust"),
            ("Trust edge", "Saved trust"),
            ("Route context", "Connection context"),
            ("route context", "connection context")
        ]
        for (from, to) in pairs {
            s = s.replacingOccurrences(of: from, with: to)
        }
        s = s.replacingOccurrences(of: " a exchange", with: " an exchange")
        s = s.replacingOccurrences(of: "A exchange", with: "An exchange")
        return s
    }

    private static func looksLikeRawIdentifier(_ lower: String) -> Bool {
        guard lower.count >= 18 else { return false }
        guard !lower.contains(" ") else { return false }
        guard lower.range(of: #"^[a-z]+[a-z0-9]*([A-Z][a-z0-9]+)+$"#, options: .regularExpression) != nil else {
            return false
        }
        return true
    }

    private static func isLikelyRawNodeTitle(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("node-") && t.count <= 48 { return true }
        if t.range(of: #"^node-[a-z0-9-]{8,}$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func clip(_ line: String, field: Field) -> String {
        let max: Int
        switch field {
        case .title: max = 120
        case .subtitle: max = 220
        case .body: max = 480
        case .status: max = 140
        case .general: max = 320
        }
        if line.count <= max { return line }
        let end = line.index(line.startIndex, offsetBy: max)
        return String(line[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
