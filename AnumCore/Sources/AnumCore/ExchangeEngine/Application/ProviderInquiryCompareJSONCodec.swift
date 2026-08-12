import Foundation

// MARK: - Provider inquiry compare JSON decode (flat schema; multi-candidate extraction)

/// Decodes on-device `providerInquiryCompare` model output into `ExchangeProviderInquiryCompareResult`.
public enum ProviderInquiryCompareJSONCodec: Sendable {

    public enum RejectionReason: Error, Sendable, Equatable {
        case topLevelArrayWithoutObject
        case emptyOutput
        case missingRequiredObject
        case parseFailed

        public var logTag: String {
            switch self {
            case .topLevelArrayWithoutObject: return "top_level_array_without_object"
            case .emptyOutput: return "empty_output"
            case .missingRequiredObject: return "missing_required_object"
            case .parseFailed: return "parse_failed"
            }
        }
    }

    struct FlatDTO: Decodable {
        struct KnownFactDTO: Decodable {
            let fact: String?
            let source: String?
            let confidence: Double?
        }

        let answerableFromOffer: Bool?
        let knownAnswers: [String]?
        let knownFacts: [KnownFactDTO]?
        let missingFacts: [String]?
        let needsProviderInput: Bool?
        let draftReply: String?
        let replyToSend: String?
        let reason: String?
        let intentCategory: String?
        let inquirySummary: String?
        let requesterAsk: String?
        let riskFlags: [String]?
        let recommendedDisposition: String?
        let recommendedAction: String?
        let consentBasis: String?
        let boundaryCrossingReason: String?
        let canSendWithinConsent: Bool?
        let requiresBoundaryApproval: Bool?
    }

    /// Attempts decode from raw runner text; tries every balanced `{...}` segment (last valid wins).
    public static func decode(
        raw: String,
        inboundIntent: ProviderInboundIntentExtraction? = nil,
        requesterAskFallback: String? = nil
    ) -> Result<ExchangeProviderInquiryCompareResult, RejectionReason> {
        let text = prepareTextForJSONObjectExtraction(stripJSONCodeFences(raw))
        if text.isEmpty {
            return .failure(.emptyOutput)
        }

        var candidates = collectJSONObjectCandidates(from: text)
        if candidates.isEmpty {
            let repaired = repairTruncatedJSONObject(text)
            if !repaired.isEmpty {
                candidates = collectJSONObjectCandidates(from: repaired)
            }
        }

        if candidates.isEmpty {
            return .failure(.missingRequiredObject)
        }

        // Prefer the last decodable object (models often echo schema then emit real JSON).
        for candidate in candidates.reversed() {
            if let mapped = tryDecodeFlatDTO(
                candidate,
                inboundIntent: inboundIntent,
                requesterAskFallback: requesterAskFallback
            ) {
                return .success(mapped)
            }
        }

        return .failure(.parseFailed)
    }

    // MARK: - Mapping + normalization

    static func mapFlatDTO(_ dto: FlatDTO) -> ExchangeProviderInquiryCompareResult {
        let known = normalizedLines(dto.knownAnswers, cap: 12, maxLen: 280)
        let missing = normalizedLines(dto.missingFacts, cap: 12, maxLen: 220)
        let answerable = dto.answerableFromOffer ?? false
        let needsInput = dto.needsProviderInput ?? !answerable
        let draftFromDTO = trim(dto.draftReply, limit: 1200) ?? trim(dto.replyToSend, limit: 1200)

        let mappedFacts: [ExchangeProviderInquiryCompareKnownFact] = (dto.knownFacts ?? []).compactMap { row in
            guard let f = row.fact?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty else {
                return nil
            }
            return ExchangeProviderInquiryCompareKnownFact(
                fact: String(f.prefix(360)),
                source: trim(row.source, limit: 120),
                confidence: row.confidence
            )
        }

        var mergedKnownAnswers = known
        if mergedKnownAnswers.isEmpty {
            mergedKnownAnswers = mappedFacts.map(\.fact)
        }

        let risk = normalizedLines(dto.riskFlags, cap: 12, maxLen: 120)
        let disposition =
            trim(dto.recommendedDisposition, limit: 80)
            ?? trim(dto.recommendedAction, limit: 80)

        return ExchangeProviderInquiryCompareResult(
            answerableFromOffer: answerable,
            knownAnswers: mergedKnownAnswers,
            knownFacts: mappedFacts,
            missingFacts: missing,
            needsProviderInput: needsInput,
            draftReply: draftFromDTO,
            reason: trim(dto.reason, limit: 400) ?? "",
            intentCategory: trim(dto.intentCategory, limit: 80),
            inquirySummary: trim(dto.inquirySummary, limit: 240),
            requesterAsk: trim(dto.requesterAsk, limit: 500),
            riskFlags: risk,
            recommendedDisposition: disposition,
            canSendWithinConsent: dto.canSendWithinConsent,
            requiresBoundaryApproval: dto.requiresBoundaryApproval,
            consentBasis: trim(dto.consentBasis, limit: 300),
            boundaryCrossingReason: normalizedOptionalStringField(dto.boundaryCrossingReason, limit: 300)
        )
    }

    /// Strips fences, then repairs Python/invalid JSON literals (`None` → `null`, etc.) and
    /// stray `,",\\n\"key\"` separators before balanced `{...}` object extraction.
    public static func prepareTextForJSONObjectExtraction(_ text: String) -> String {
        let literals = normalizeInvalidJSONLiterals(text)
        return repairCommaQuoteKeySeparatorGlitch(literals)
    }

    /// Removes a stray `"` between a value terminator and the next key: `.",\"\\n\"replyToSend\"` → `.\",\\n\"replyToSend\"`.
    /// Only runs outside JSON string values so embedded quotes in values are preserved.
    public static func repairCommaQuoteKeySeparatorGlitch(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var inString = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let ch = text[index]

            if inString {
                result.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }

            if ch == "\"" {
                inString = true
                result.append(ch)
                index = text.index(after: index)
                continue
            }

            if ch == "," {
                if let next = consumeStrayQuoteAfterComma(in: text, at: index, into: &result) {
                    index = next
                    continue
                }
            }

            result.append(ch)
            index = text.index(after: index)
        }

        return result
    }

    /// When `,\\s*"\\s*\\n\\s*\"key\":` is detected outside strings, drop the stray quote after the comma.
    private static func consumeStrayQuoteAfterComma(
        in text: String,
        at comma: String.Index,
        into result: inout String
    ) -> String.Index? {
        var cursor = text.index(after: comma)
        let whitespaceBeforeStrayStart = cursor

        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex, text[cursor] == "\"" else { return nil }

        let afterStrayQuote = text.index(after: cursor)
        var keyQuote = afterStrayQuote
        while keyQuote < text.endIndex, text[keyQuote].isWhitespace {
            keyQuote = text.index(after: keyQuote)
        }
        guard keyQuote < text.endIndex, text[keyQuote] == "\"" else { return nil }

        guard let keyClose = jsonObjectKeyClosingQuote(in: text, openingQuote: keyQuote) else {
            return nil
        }

        var afterKey = text.index(after: keyClose)
        while afterKey < text.endIndex, text[afterKey].isWhitespace {
            afterKey = text.index(after: afterKey)
        }
        guard afterKey < text.endIndex, text[afterKey] == ":" else { return nil }

        result.append(",")
        if whitespaceBeforeStrayStart < cursor {
            result.append(contentsOf: text[whitespaceBeforeStrayStart..<cursor])
        }
        if afterStrayQuote < keyQuote {
            result.append(contentsOf: text[afterStrayQuote..<keyQuote])
        }
        result.append(contentsOf: text[keyQuote..<afterKey])
        result.append(":")
        return text.index(after: afterKey)
    }

    private static func jsonObjectKeyClosingQuote(in text: String, openingQuote: String.Index) -> String.Index? {
        guard openingQuote < text.endIndex, text[openingQuote] == "\"" else { return nil }
        var index = text.index(after: openingQuote)
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\\" {
                index = text.index(after: index)
                if index < text.endIndex {
                    index = text.index(after: index)
                }
                continue
            }
            if ch == "\"" {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Rewrites Python-style literals to JSON **only outside quoted strings**.
    public static func normalizeInvalidJSONLiterals(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var inString = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let ch = text[index]

            if inString {
                result.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }

            if ch == "\"" {
                if let (replacement, next) = replaceQuotedNoneSentinel(in: text, at: index) {
                    result.append(replacement)
                    index = next
                    continue
                }
                inString = true
                result.append(ch)
                index = text.index(after: index)
                continue
            }

            if ch == ":" || ch == "," || ch == "[" {
                result.append(ch)
                index = text.index(after: index)
                index = appendWhitespace(from: text, startingAt: index, into: &result)
                if let (jsonLiteral, consumed) = matchPythonBareLiteral(text[index...]) {
                    result.append(jsonLiteral)
                    index = text.index(index, offsetBy: consumed)
                    if jsonLiteral == "null", index < text.endIndex, text[index] == "\"" {
                        // Malformed tail such as `:None"` — drop stray quote.
                        index = text.index(after: index)
                    }
                    continue
                }
                continue
            }

            result.append(ch)
            index = text.index(after: index)
        }

        return result
    }

    private static func appendWhitespace(
        from text: String,
        startingAt start: String.Index,
        into result: inout String
    ) -> String.Index {
        var index = start
        while index < text.endIndex, text[index].isWhitespace {
            result.append(text[index])
            index = text.index(after: index)
        }
        return index
    }

    /// `: "None"` (optional string absent) → `: null`
    private static func replaceQuotedNoneSentinel(
        in text: String,
        at quoteIndex: String.Index
    ) -> (replacement: String, nextIndex: String.Index)? {
        guard quoteIndex < text.endIndex, text[quoteIndex] == "\"" else { return nil }
        let afterOpen = text.index(after: quoteIndex)
        guard afterOpen < text.endIndex else { return nil }

        let slice = text[afterOpen...]
        guard slice.hasPrefix("None") else { return nil }

        let afterNone = text.index(afterOpen, offsetBy: 4)
        guard afterNone < text.endIndex, text[afterNone] == "\"" else { return nil }

        let afterClose = text.index(after: afterNone)
        guard isJSONValueTerminator(afterClose < text.endIndex ? text[afterClose] : nil) else {
            return nil
        }

        return (" null", afterClose)
    }

    private static func matchPythonBareLiteral(_ slice: Substring) -> (jsonLiteral: String, length: Int)? {
        if slice.hasPrefix("None") {
            let tail = slice.dropFirst(4)
            guard isPythonLiteralTail(tail.first) else { return nil }
            return ("null", 4)
        }
        if slice.hasPrefix("True") {
            let tail = slice.dropFirst(4)
            guard isPythonLiteralTail(tail.first) else { return nil }
            return ("true", 4)
        }
        if slice.hasPrefix("False") {
            let tail = slice.dropFirst(5)
            guard isPythonLiteralTail(tail.first) else { return nil }
            return ("false", 5)
        }
        return nil
    }

    private static func isPythonLiteralTail(_ ch: Character?) -> Bool {
        isJSONValueTerminator(ch) || ch == "\""
    }

    private static func isJSONValueTerminator(_ ch: Character?) -> Bool {
        guard let ch else { return true }
        return ch == "," || ch == "}" || ch == "]" || ch.isWhitespace
    }

    private static func normalizedOptionalStringField(_ value: String?, limit: Int) -> String? {
        guard let trimmed = trim(value, limit: limit) else { return nil }
        if trimmed.caseInsensitiveCompare("none") == .orderedSame {
            return nil
        }
        return trimmed
    }

    /// When inbound intent is openness-only, drop unrelated blocking missing-fact lines the model invented.
    public static func normalizeForInboundIntent(
        _ result: ExchangeProviderInquiryCompareResult,
        inboundIntent: ProviderInboundIntentExtraction?,
        requesterAskFallback: String?
    ) -> ExchangeProviderInquiryCompareResult {
        guard let intent = inboundIntent, intent.inquiryKind == .availabilityOrOpenness else {
            return result
        }

        let ask = [
            result.requesterAsk,
            requesterAskFallback,
            intent.rawRequesterAsk.isEmpty ? nil : intent.rawRequesterAsk
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }?
            .lowercased() ?? ""

        let askMentionsPricing =
            ask.contains("pric") || ask.contains("cost") || ask.contains("$") || ask.contains("quote")
        let askMentionsScheduling =
            ask.contains("schedul")
            || ask.contains("tomorrow")
            || ask.contains("today")
            || ask.contains("appointment")
            || ask.contains(" call")
            || ask.contains("meeting")

        var out = result
        if !askMentionsPricing && !askMentionsScheduling {
            out.missingFacts = out.missingFacts.filter { fact in
                !isInventedBlockingMissingFactForOpennessAsk(fact)
            }
        }

        let disposition = out.recommendedDisposition?.lowercased() ?? ""
        if out.answerableFromOffer,
           !out.knownAnswers.isEmpty,
           disposition == "sendwithinconsent",
           out.missingFacts.isEmpty {
            out.needsProviderInput = false
        }

        return out
    }

    private static func isInventedBlockingMissingFactForOpennessAsk(_ fact: String) -> Bool {
        let f = fact.lowercased()
        if f.contains("pric") || f.contains("cost") || f.contains("quote") {
            return true
        }
        if f.contains("schedul") || f.contains("today") || f.contains("tomorrow") {
            return true
        }
        if f.contains("service scope") || (f.contains("scope") && f.contains("detail")) {
            return true
        }
        if f.contains("exact") && (f.contains("availab") || f.contains("timing")) {
            return true
        }
        return false
    }

    // MARK: - Candidate collection

    public static func collectJSONObjectCandidates(from text: String) -> [String] {
        let normalized = prepareTextForJSONObjectExtraction(text)
        var out: [String] = []
        var search = normalized.startIndex

        while search < normalized.endIndex,
              let brace = normalized[search...].firstIndex(of: "{") {
            let slice = String(normalized[brace...])
            guard let extracted = extractFirstBalancedJSONObject(from: slice),
                  isValidJSONObject(extracted)
            else {
                search = normalized.index(after: brace)
                continue
            }
            out.append(extracted)
            if let range = normalized.range(of: extracted, range: brace..<normalized.endIndex) {
                search = range.upperBound
            } else {
                search = normalized.index(after: brace)
            }
        }

        if out.isEmpty, let fromArray = unwrapSingleObjectFromJSONArray(normalized) {
            out.append(fromArray)
        }

        return out
    }

    static func unwrapSingleObjectFromJSONArray(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        if let dict = json as? [String: Any],
           JSONSerialization.isValidJSONObject(dict),
           let encoded = try? JSONSerialization.data(withJSONObject: dict),
           let s = String(data: encoded, encoding: .utf8) {
            return s
        }

        if let array = json as? [Any], array.count == 1, let dict = array.first as? [String: Any],
           let encoded = try? JSONSerialization.data(withJSONObject: dict),
           let s = String(data: encoded, encoding: .utf8) {
            return s
        }

        return nil
    }

    static func isValidJSONObject(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
        else {
            return false
        }
        return obj is NSDictionary || obj is [String: Any]
    }

    static func tryDecodeFlatDTO(
        _ json: String,
        inboundIntent: ProviderInboundIntentExtraction?,
        requesterAskFallback: String?
    ) -> ExchangeProviderInquiryCompareResult? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let dto = try? JSONDecoder().decode(FlatDTO.self, from: data) else {
            return nil
        }
        let mapped = mapFlatDTO(dto)
        return normalizeForInboundIntent(
            mapped,
            inboundIntent: inboundIntent,
            requesterAskFallback: requesterAskFallback
        )
    }

    // MARK: - Truncation repair

    static func repairTruncatedJSONObject(_ text: String) -> String {
        let trimmed = prepareTextForJSONObjectExtraction(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("{") else { return trimmed }

        if isValidJSONObject(trimmed) {
            return trimmed
        }

        var s = trimmed
        while !s.isEmpty, s.last == "," || s.last == ":" {
            s.removeLast()
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let partial = extractFirstBalancedJSONObject(from: s), isValidJSONObject(partial) {
            return partial
        }

        let openCount = s.filter { $0 == "{" }.count
        let closeCount = s.filter { $0 == "}" }.count
        if openCount > closeCount {
            s.append(String(repeating: "}", count: openCount - closeCount))
        }

        if let partial = extractFirstBalancedJSONObject(from: s), isValidJSONObject(partial) {
            return partial
        }

        return trimmed
    }

    static func extractFirstBalancedJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false
        var endIndex: String.Index?

        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]

            if inString {
                if isEscaped {
                    isEscaped = false
                } else if ch == "\\" {
                    isEscaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = idx
                        break
                    }
                }
            }

            idx = text.index(after: idx)
        }

        guard let endIndex, depth == 0 else { return nil }
        return String(text[start...endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func stripJSONCodeFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let closing = text.range(of: "```", options: .backwards) {
                text.removeSubrange(closing)
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.lowercased().hasPrefix("json\n") {
            text = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    // MARK: - String helpers

    private static func normalizedLines(_ raw: [String]?, cap: Int, maxLen: Int) -> [String] {
        var out: [String] = []
        for s in raw ?? [] {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            out.append(String(t.prefix(maxLen)))
            if out.count >= cap { break }
        }
        return out
    }

    private static func trim(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.count <= limit { return t }
        return String(t.prefix(limit))
    }
}
