import Foundation

// MARK: - Compact flat-summary normalization (social/affinity, budget, shipping)

extension SecretaryCompactSearchSummaryDTO {
    /// Accepts `budget` as JSON string or number from on-device models.
    static func decodeFlexibleBudget(from container: KeyedDecodingContainer<CodingKeys>) throws -> String? {
        guard container.contains(.budget) else { return nil }
        if let text = try? container.decode(String.self, forKey: .budget) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let value = try? container.decode(Double.self, forKey: .budget) {
            return Self.budgetString(from: value)
        }
        if let value = try? container.decode(Int.self, forKey: .budget) {
            return String(value)
        }
        return nil
    }

    private static func budgetString(from number: Double) -> String {
        if number.rounded(.towardZero) == number {
            return String(Int(number))
        }
        return String(number)
    }
}

extension LLMOpenEndedSearchIntentExtractor {
    /// Deterministic compact-summary repairs before expand/validate (no prompt changes).
    func enrichCompactSearchSummary(
        _ compact: SecretaryCompactSearchSummaryDTO,
        userText: String
    ) -> SecretaryCompactSearchSummaryDTO {
        var copy = compact
        let normalizedUser = normalizeInput(userText)

        copy = preserveShippingDestinationIfNeeded(compact: copy, userText: normalizedUser)

        guard !isVagueFlatDiscoveryRequest(normalizedUser.lowercased()) else { return copy }

        if compactObjectIsEmpty(copy.object) {
            if let synthesized = synthesizeSocialActivityObject(compact: copy, userText: normalizedUser) {
                copy.object = synthesized
            }
        }

        if compactPlaceIsEmpty(copy.place) {
            if let proximity = extractProximityPlace(compact: copy, userText: normalizedUser) {
                copy.place = proximity
            } else if let destination = extractShippingDestinationPhrase(
                compact: copy,
                userText: normalizedUser
            ) {
                copy.place = destination
            }
        }

        if compactTimeIsEmpty(copy.time) {
            if let schedule = extractScheduleHint(compact: copy, userText: normalizedUser) {
                copy.time = schedule
            }
        }

        return copy
    }

    func detectsSocialAffinityDiscovery(
        compact: SecretaryCompactSearchSummaryDTO,
        userText: String
    ) -> Bool {
        if isVagueFlatDiscoveryRequest(normalizeInput(userText).lowercased()) { return false }
        let blob = compactFlatSignalBlob(compact: compact, userText: userText)
        return hasSocialPersonAffinitySignal(blob)
    }

    func applySocialAffinityHintsToExpandedSummary(
        _ summary: SecretarySearchRequestSummaryDTO,
        compact: SecretaryCompactSearchSummaryDTO,
        userText: String
    ) -> SecretarySearchRequestSummaryDTO {
        if compact.routeClass != nil {
            return summary
        }

        guard detectsSocialAffinityDiscovery(compact: compact, userText: userText) else {
            return summary
        }

        var copy = summary
        copy.surfacePreferenceHint = "affinity"
        if copy.categoryHint == nil
            || normalizeCategoryHintForDomain(copy.categoryHint) == "general" {
            copy.categoryHint = "general"
        }

        let activityTokens = normalizeFlatStringList(
            compact.soft + compact.hard + compact.mods
                + [compact.object, compact.need].compactMap { SearchIntentSentinelFilter.nilIfSentinel($0) },
            maxCount: 16
        )
        copy.semanticTexts = normalizeFlatStringList(
            copy.semanticTexts + activityTokens,
            maxCount: 20
        )
        copy.broadRecallTokens = normalizeFlatStringList(
            copy.broadRecallTokens + activityTokens,
            maxCount: 24
        )
        return copy
    }

    private func synthesizeSocialActivityObject(
        compact: SecretaryCompactSearchSummaryDTO,
        userText: String
    ) -> String? {
        let blob = compactFlatSignalBlob(compact: compact, userText: userText)
        guard hasSocialPersonAffinitySignal(blob) else { return nil }

        for phrase in preferredActivityPhrases(from: compact) {
            if let object = objectTypeFromActivityPhrase(phrase, userText: userText) {
                return object
            }
        }

        return defaultSocialObjectLabel(userText: userText)
    }

    private func preferredActivityPhrases(from compact: SecretaryCompactSearchSummaryDTO) -> [String] {
        var ordered: [String] = []
        ordered.append(contentsOf: compact.soft)
        ordered.append(contentsOf: compact.hard)
        ordered.append(contentsOf: compact.mods)
        if let need = compact.need { ordered.append(need) }
        if let object = compact.object { ordered.append(object) }
        return ordered
    }

    private func objectTypeFromActivityPhrase(_ phrase: String, userText: String) -> String? {
        let trimmed = normalizeInput(phrase)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        if containsAny(lower, ["partner", "group", "team", "friend", "people", "person"]) {
            return String(trimmed.prefix(140))
        }
        if lower.contains("网球") {
            if trimmed.contains("人") { return String(trimmed.prefix(140)) }
            if userText.contains("一起") { return "一起打网球的人" }
            return "网球伙伴"
        }
        if containsAny(trimmed, ["一起", "朋友", "伙伴", "搭子", "小组", "社群"]) {
            if trimmed.contains("一起"), !trimmed.contains("人") {
                return "\(trimmed)的人"
            }
            return String(trimmed.prefix(140))
        }
        if containsAny(lower, ["hiking", "tennis", "swim", "movie", "yoga"]) {
            if lower.contains("group") { return String(trimmed.prefix(140)) }
            return "\(trimmed) partner"
        }
        return nil
    }

    private func defaultSocialObjectLabel(userText: String) -> String {
        userText.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil ? "人" : "people"
    }

    private func hasSocialPersonAffinitySignal(_ blob: String) -> Bool {
        let english = [
            "people", "person", "someone", "partner", "group", "community", "friend",
            "teammate", "who want", "who likes", "join a", "join "
        ]
        let chinese = ["人", "的朋友", "朋友", "伙伴", "搭子", "小组", "社群", "一起"]
        return containsAny(blob, english) || containsAny(blob, chinese)
    }

    private func isVagueFlatDiscoveryRequest(_ userLower: String) -> Bool {
        let vagueEnglish = [
            "find something interesting",
            "something interesting",
            "show me stuff",
            "stuff nearby",
            "find stuff",
            "anything interesting"
        ]
        let vagueChinese = ["找点东西", "一些东西", "随便", "有趣的事"]
        return containsAny(userLower, vagueEnglish) || containsAny(userLower, vagueChinese)
    }

    private func preserveShippingDestinationIfNeeded(
        compact: SecretaryCompactSearchSummaryDTO,
        userText: String
    ) -> SecretaryCompactSearchSummaryDTO {
        var copy = compact
        guard compactPlaceIsEmpty(copy.place) else { return copy }
        if let destination = extractShippingDestinationPhrase(compact: copy, userText: userText) {
            copy.place = destination
            if compactCommercialIsEmpty(copy.commercial) {
                if userText.lowercased().contains("ship") || userText.contains("邮寄") {
                    copy.commercial = userText.contains("邮寄") ? "邮寄" : "shipped"
                }
            }
        }
        return copy
    }

    private func extractShippingDestinationPhrase(
        compact: SecretaryCompactSearchSummaryDTO,
        userText: String
    ) -> String? {
        let sources = [userText, compact.raw, compact.commercial]
            .compactMap { $0 }
            .map { normalizeInput($0) }
            .filter { !$0.isEmpty }
        for source in sources {
            if let dest = matchShippingDestination(in: source) { return dest }
        }
        for phrase in compact.hard + compact.soft {
            if let dest = matchShippingDestination(in: normalizeInput(phrase)) { return dest }
        }
        return nil
    }

    private func matchShippingDestination(in text: String) -> String? {
        let patterns: [String] = [
            #"(?i)shipped?\s+to\s+([A-Za-z\u4e00-\u9fff][A-Za-z\u4e00-\u9fff\s\-]{0,40})"#,
            #"(?i)ship\s+to\s+([A-Za-z\u4e00-\u9fff][A-Za-z\u4e00-\u9fff\s\-]{0,40})"#,
            #"邮寄到\s*([^\s，,。.!?；;]{1,24})"#,
            #"邮寄\s*([^\s，,。.!?；;]{1,24})"#
        ]
        let ns = text as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges >= 2 else { continue }
            let captured = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !captured.isEmpty { return captured }
        }
        return nil
    }

    private func extractProximityPlace(compact: SecretaryCompactSearchSummaryDTO, userText: String) -> String? {
        let candidates = compact.hard + compact.soft + [compact.place, compact.raw].compactMap { $0 }
        for candidate in candidates {
            let normalized = normalizeInput(candidate).lowercased()
            if normalized == "nearby" || normalized == "附近" {
                return normalizeInput(candidate)
            }
        }
        if userText.lowercased().contains("nearby") { return "nearby" }
        if userText.contains("附近") { return "附近" }
        return nil
    }

    private func extractScheduleHint(compact: SecretaryCompactSearchSummaryDTO, userText: String) -> String? {
        if let time = compact.time.map({ normalizeInput($0) }), !time.isEmpty,
           timeTextLooksLikeTimeOrDate(time, userText: userText) {
            return time
        }
        let lowered = userText.lowercased()
        let markers = ["weekday evenings", "weekend", "tonight", "tomorrow", "morning", "afternoon", "evening"]
        for marker in markers where lowered.contains(marker) { return marker }
        if userText.contains("晚上") { return "晚上" }
        if userText.contains("周末") { return "周末" }
        if let loose = extractLooseScheduleSnippet(from: userText) { return loose }
        for phrase in compact.hard {
            let normalized = normalizeInput(phrase)
            if timeTextLooksLikeTimeOrDate(normalized, userText: userText) { return normalized }
        }
        return nil
    }

    private func compactFlatSignalBlob(compact: SecretaryCompactSearchSummaryDTO, userText: String) -> String {
        (
            [userText, compact.raw, compact.object, compact.need, compact.place, compact.time, compact.commercial]
                + compact.soft + compact.hard + compact.mods
        )
        .compactMap { $0 }
        .map { normalizeInput($0).lowercased() }
        .joined(separator: " ")
    }

    private func compactObjectIsEmpty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private func compactPlaceIsEmpty(_ value: String?) -> Bool {
        compactObjectIsEmpty(value)
    }

    private func compactTimeIsEmpty(_ value: String?) -> Bool {
        compactObjectIsEmpty(value)
    }

    private func compactCommercialIsEmpty(_ value: String?) -> Bool {
        compactObjectIsEmpty(value)
    }
}
