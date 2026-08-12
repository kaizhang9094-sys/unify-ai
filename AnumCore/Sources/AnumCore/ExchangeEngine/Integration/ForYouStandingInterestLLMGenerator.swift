import Foundation

// MARK: - Phase 3: LLM-backed standing interest (public profile only; heuristic fallback)

/// On-device JSON generation via `ExchangeIntelligenceModelRunner` + `.interpretation`
/// (constitution/style injection is disabled for that task in `LlamaExchangeModelRunner`).
public struct ForYouStandingInterestLLMGenerator: ForYouStandingInterestGenerating {
    private let runner: any ExchangeIntelligenceModelRunner
    private let fallback: ForYouStandingInterestHeuristicGenerator
    private let timeoutSeconds: TimeInterval
    private let maxTokens: Int

    public init(
        runner: any ExchangeIntelligenceModelRunner,
        fallback: ForYouStandingInterestHeuristicGenerator = ForYouStandingInterestHeuristicGenerator(),
        timeoutSeconds: TimeInterval = 8.0,
        maxTokens: Int = 384
    ) {
        self.runner = runner
        self.fallback = fallback
        self.timeoutSeconds = max(1.0, timeoutSeconds)
        self.maxTokens = max(128, maxTokens)
    }

    public func generate(from profile: ExchangePublicNodeProfile) async throws -> ForYouStandingInterest {
        let fingerprint = ForYouStandingInterestProfileFingerprint.make(for: profile)

        guard ForYouStandingInterestSanitizer.profileHasPublicDiscoverySignal(profile) else {
            #if DEBUG
            print("[ForYouStandingInterest][LLM] skip_llm reason=no_public_discovery_signal")
            #endif
            return try await fallback.generate(from: profile)
        }

        let prompt: String
        do {
            let profileJSON = try Self.encodePublicProfileJSON(profile: profile)
            prompt = Self.buildPrompt(publicProfileJSON: profileJSON)
        } catch {
            #if DEBUG
            print("[ForYouStandingInterest][LLM] fallback=heuristic reason=prompt_encode")
            #endif
            return try await fallback.generate(from: profile)
        }

        do {
            let raw = try await runWithTimeout(prompt: prompt)
            if let draft = Self.materializeFromModelOutput(raw, fingerprint: fingerprint, now: Date()),
               let sanitized = ForYouStandingInterestSanitizer.sanitizedForPersist(
                   draft,
                   profile: profile,
                   expectedFingerprint: fingerprint
               ) {
                #if DEBUG
                let tagCount =
                    sanitized.searchTags.count
                    + sanitized.lookingForTags.count
                    + sanitized.interestTags.count
                    + sanitized.roleTags.count
                    + sanitized.regionTags.count
                    + sanitized.excludedTags.count
                print(
                    "[ForYouStandingInterest][LLM] success tags=\(tagCount) confidence=\(sanitized.confidence) queryChars=\(sanitized.queryText.count)"
                )
                #endif
                return sanitized
            }
            #if DEBUG
            print("[ForYouStandingInterest][LLM] fallback=heuristic reason=parse_or_sanitize_reject")
            #endif
        } catch {
            #if DEBUG
            print("[ForYouStandingInterest][LLM] fallback=heuristic reason=\(String(describing: error))")
            #endif
        }

        return try await fallback.generate(from: profile)
    }

    private enum FirstComplete: Sendable {
        case model(String)
        case tick
    }

    /// Waits for model output, but if the wall-clock timeout elapses first, still accepts a **completed**
    /// model result when it arrives (avoids discarding valid output that finishes just after the tick).
    private func runWithTimeout(prompt: String) async throws -> String {
        try await withThrowingTaskGroup(of: FirstComplete.self) { group in
            group.addTask {
                let request = ExchangeIntelligenceModelRunRequest(
                    task: .interpretation,
                    prompt: prompt,
                    maxTokens: self.maxTokens
                )
                let s = try await self.runner.run(request)
                return .model(s)
            }
            group.addTask {
                let ns = UInt64(self.timeoutSeconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                return .tick
            }
            guard let first = try await group.next() else {
                throw ForYouStandingInterestLLMTimeout()
            }
            switch first {
            case .model(let s):
                group.cancelAll()
                return s
            case .tick:
                guard let second = try await group.next() else {
                    group.cancelAll()
                    throw ForYouStandingInterestLLMTimeout()
                }
                switch second {
                case .model(let s):
                    group.cancelAll()
                    return s
                case .tick:
                    group.cancelAll()
                    throw ForYouStandingInterestLLMTimeout()
                }
            }
        }
    }

    // MARK: - Prompt (no logging of prompt or raw profile body)

    private static func encodePublicProfileJSON(profile: ExchangePublicNodeProfile) throws -> String {
        let payload = ForYouPublicDiscoveryPayload(
            headline: profile.headline,
            summary: profile.summary,
            interests: profile.interests,
            openTo: profile.openTo,
            activityTags: profile.activityTags,
            regionTags: profile.regionTags,
            semanticDomains: profile.semantic.domains,
            semanticIntentKinds: profile.semantic.intentKinds,
            excludedTopics: profile.excludedTopics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard let s = String(data: data, encoding: .utf8) else {
            throw ForYouStandingInterestLLMGeneratorError.encodingFailed
        }
        return s
    }

    private static func buildPrompt(publicProfileJSON: String) -> String {
        """
        Output only JSON. No markdown fences. No explanation. No trailing text.

        You are generating discovery-oriented standing interest for a federated profile directory ("For You").
        Use ONLY the supplied public profile JSON object. Do not invent private facts, contact details, or sensitive traits.
        Do not use emails, phone numbers, URLs as tags, or long prose paragraphs.

        Goal: short tags and a compact query line describing people/profiles this user may want to connect with or discover — interests and meeting intent, not what they sell.
        Do not emit commercial offer tags, product SKUs, pricing, or sales pitches.

        If the profile is sparse, emit broad, public-safe discovery tags and keep confidence low (for example 0.25–0.45).

        Required JSON shape (camelCase keys, all keys present):
        {
          "queryText": "single line <= 720 characters",
          "canonicalEnglishQuery": "English directory line when queryText is not English; null if already English",
          "searchTags": [],
          "lookingForTags": [],
          "interestTags": [],
          "roleTags": [],
          "regionTags": [],
          "excludedTags": [],
          "confidence": 0.0,
          "debugSummary": "one short line, no PII"
        }

        Rules:
        - Each tag string length <= 64 characters; keep tags short.
        - Arrays: dedupe mentally; prefer tens of tags total across arrays, not hundreds.
        - confidence is a number from 0 through 1.
        - queryText should read like a directory discovery line, not a biography.

        Field mapping rules (preserve user-provided literal terms; do not invent synonyms or related terms):
        - `openTo` is what the user is looking for. Copy relevant literal `openTo` entries into `lookingForTags` unless unsafe.
        - `summary` holds capability/context. Important literal phrases from `summary` may appear in `searchTags` and/or `queryText`.
        - Put `interests` into `interestTags` only, unless an interest is also explicit discovery intent stated elsewhere.
        - `activityTags`, `semanticDomains`, and `semanticIntentKinds` may map to `roleTags` or `searchTags` when they describe role or discovery posture.
        - Treat `headline` as weak context; do not set `queryText` to the headline alone when `summary` or `openTo` contains meaningful literal terms—blend discovery intent compactly.
        - `queryText` must be a short directory-style line, not a biography and not only a poetic intro when clearer signals exist.

        Public profile JSON (only source of truth):
        \(publicProfileJSON)
        """
    }

    // MARK: - Parse

    private static func materializeFromModelOutput(
        _ raw: String,
        fingerprint: String,
        now: Date
    ) -> ForYouStandingInterest? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromArray = materializeFromTopLevelJSONArray(trimmed, fingerprint: fingerprint, now: now) {
            return fromArray
        }
        guard let data = extractJSONObjectData(trimmed) else { return nil }

        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let root = obj as? [String: Any]
        else { return nil }

        var queryText = ForYouStandingInterestNormalizer.trimToken(stringValue(root["queryText"]))
        if queryText.count > ForYouStandingInterestSanitizer.maxPersistQueryChars {
            queryText = String(queryText.prefix(ForYouStandingInterestSanitizer.maxPersistQueryChars))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let confidence = min(1, max(0, doubleValue(root["confidence"])))

        let summaryRaw = ForYouStandingInterestNormalizer.trimToken(stringValue(root["debugSummary"]))
        let clippedSummary: String? = {
            guard !summaryRaw.isEmpty else { return nil }
            if summaryRaw.count > 200 { return String(summaryRaw.prefix(200)) }
            return summaryRaw
        }()

        var canonicalEnglishQuery = ForYouStandingInterestNormalizer.trimToken(
            stringValue(root["canonicalEnglishQuery"])
        )
        if canonicalEnglishQuery.count > ForYouStandingInterestSanitizer.maxPersistQueryChars {
            canonicalEnglishQuery = String(canonicalEnglishQuery.prefix(ForYouStandingInterestSanitizer.maxPersistQueryChars))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if canonicalEnglishQuery.isEmpty {
            canonicalEnglishQuery = ""
        }

        return ForYouStandingInterest(
            queryText: queryText,
            canonicalEnglishQuery: canonicalEnglishQuery.isEmpty ? nil : canonicalEnglishQuery,
            searchTags: stringArray(root["searchTags"]),
            lookingForTags: stringArray(root["lookingForTags"]),
            interestTags: stringArray(root["interestTags"]),
            roleTags: stringArray(root["roleTags"]),
            regionTags: stringArray(root["regionTags"]),
            excludedTags: stringArray(root["excludedTags"]),
            confidence: confidence,
            generatedAt: now,
            sourceProfileFingerprint: fingerprint,
            debugSummary: clippedSummary
        )
    }

    /// Tolerates models that emit only a JSON string array (e.g. `["computer","enthusiast"]`) instead of the full object.
    private static func materializeFromTopLevelJSONArray(
        _ trimmed: String,
        fingerprint: String,
        now: Date
    ) -> ForYouStandingInterest? {
        guard trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any]
        else { return nil }
        let tags = stringArray(arr)
        guard !tags.isEmpty else { return nil }
        let joined = tags.map { ForYouStandingInterestNormalizer.trimToken($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        guard !joined.isEmpty else { return nil }
        return ForYouStandingInterest(
            queryText: joined,
            searchTags: tags,
            lookingForTags: [],
            interestTags: [],
            roleTags: [],
            regionTags: [],
            excludedTags: [],
            confidence: 0.35,
            generatedAt: now,
            sourceProfileFingerprint: fingerprint,
            debugSummary: "llm:array_tags_only"
        )
    }

    private static func stringValue(_ any: Any?) -> String {
        guard let any else { return "" }
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    private static func doubleValue(_ any: Any?) -> Double {
        guard let any else { return 0 }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s) { return d }
        return 0
    }

    private static func stringArray(_ any: Any?) -> [String] {
        guard let arr = any as? [Any] else { return [] }
        return arr.compactMap { el -> String? in
            if let s = el as? String { return s }
            if let n = el as? NSNumber { return n.stringValue }
            return nil
        }
    }

    private static func extractJSONObjectData(_ raw: String) -> Data? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}")
        else { return nil }
        let slice = raw[start ... end]
        return String(slice).data(using: .utf8)
    }
}

// MARK: - Supporting types

private struct ForYouPublicDiscoveryPayload: Encodable, Sendable {
    var headline: String?
    var summary: String?
    var interests: [String]
    var openTo: [String]
    var activityTags: [String]
    var regionTags: [String]
    var semanticDomains: [String]
    var semanticIntentKinds: [String]
    var excludedTopics: [String]
}

private struct ForYouStandingInterestLLMTimeout: Error, Sendable {}

private enum ForYouStandingInterestLLMGeneratorError: Error, Sendable {
    case encodingFailed
}
