import Foundation

public protocol AsyncExchangeProviderResponseAssessmentEngine: Sendable {
    func assessProviderResponse(
        context: ExchangeSecondHalfExecutionContext,
        priorAssessment: ExchangeProviderResponseAssessment?
    ) async -> ExchangeProviderResponseAssessment?
}

public protocol AsyncProviderResponseAssessmentJSONProvider: Sendable {
    func isReadyForImmediateExtraction() async -> Bool
    func assessProviderResponseJSON(prompt: String) async throws -> String
}

public protocol ProviderResponseAssessmentProviderBusyError: Error {}
public protocol ProviderResponseAssessmentProviderUnavailableError: Error {}

public enum ProviderResponseAssessmentSource: String, Sendable, Hashable {
    case llm
    case llmRepairedJSON
    case heuristicFallback
}

public enum ProviderResponseAssessmentFailureReason: String, Sendable, Hashable {
    case providerUnavailable
    case modelBusy
    case timeout
    case cancelled
    case invalidJSON
    case repairFailed
    case emptyAssessment
    case unsafeAssessment
    case thrownError
}

public struct ProviderResponseAssessmentDiagnostics: Sendable, Hashable {
    public var source: ProviderResponseAssessmentSource
    public var fallbackReason: ProviderResponseAssessmentFailureReason?
    public var repairAttempted: Bool
    public var timeoutSeconds: Double?
    public var elapsedMs: Int?
    public var confidence: Double?
    public var conditionCount: Int
    public var contradictionCount: Int

    public init(
        source: ProviderResponseAssessmentSource,
        fallbackReason: ProviderResponseAssessmentFailureReason? = nil,
        repairAttempted: Bool = false,
        timeoutSeconds: Double? = nil,
        elapsedMs: Int? = nil,
        confidence: Double? = nil,
        conditionCount: Int = 0,
        contradictionCount: Int = 0
    ) {
        self.source = source
        self.fallbackReason = fallbackReason
        self.repairAttempted = repairAttempted
        self.timeoutSeconds = timeoutSeconds
        self.elapsedMs = elapsedMs
        self.confidence = confidence
        self.conditionCount = conditionCount
        self.contradictionCount = contradictionCount
    }
}

public actor ProviderResponseAssessmentDiagnosticsStore {
    public private(set) var last: ProviderResponseAssessmentDiagnostics?

    public init() {}

    public func record(_ value: ProviderResponseAssessmentDiagnostics) {
        last = value
    }
}

public enum ProviderResponseAssessmentTimeoutError: Error, Sendable, Hashable {
    case timedOut
}

struct LLMProviderResponseAssessmentDTO: Codable, Sendable, Hashable {
    struct ConditionDTO: Codable, Sendable, Hashable {
        var conditionText: String?
        var source: ConditionSource?
        var status: ConditionStatus?
        var confidence: Double?
        var evidence: [String]?
        var missingInfo: [String]?
        var suggestedFollowUp: String?
    }

    var conditionAssessments: [ConditionDTO]?
    var providerFitSummary: String?
    var confidenceDelta: ConfidenceDelta?
    var shortlistRecommendation: ShortlistRecommendation?
    var decisionReadiness: DecisionReadiness?
    var nextMoveRecommendation: NextMoveRecommendation?
    var missingInfo: [String]?
    var suggestedFollowUp: String?
    var requesterFacingExplanation: String?
    var requiresHumanJudgment: Bool?
    var safeForAutonomousFollowup: Bool?
    var confidence: Double?
}

enum ExchangeProviderResponseAssessmentPromptBuilder {
    static func buildPrompt(
        context: ExchangeSecondHalfExecutionContext,
        priorAssessment: ExchangeProviderResponseAssessment?
    ) -> String {
        let prior = priorAssessment?.summary ?? priorAssessment?.providerFitSummary
        return """
        Assess a provider response for requester-side second-half coordination.

        Safety constraints:
        - Do not make commitment decisions.
        - Do not approve sending.
        - Do not override policy, boundary, or state legality.
        - Only assess semantic coverage and what's missing.

        Evaluate whether the provider response substantively addresses requester conditions.
        Preserve nuanced statuses:
        satisfied, partiallySatisfied, impliedFlexible, notAnswered, contradicted, needsFollowUp, unknown.
        For commercial conditions like vendor take-back / seller financing, assess evidence and missing terms rather than binary yes/no.

        Return compact JSON only (no prose/markdown) using:
        {
          "conditionAssessments": [{
            "conditionText": String,
            "source": "canonicalIntent|gapFill|userPreference|commercialConstraint|timingConstraint|providerReply|operatingMemory|unknown",
            "status": "satisfied|partiallySatisfied|impliedFlexible|notAnswered|contradicted|needsFollowUp|unknown",
            "confidence": Number,
            "evidence": [String],
            "missingInfo": [String],
            "suggestedFollowUp": String
          }],
          "providerFitSummary": String,
          "confidenceDelta": "stronglyNegative|negative|stable|positive|stronglyPositive",
          "shortlistRecommendation": "noChange|promote|demote|remove|compareWithAlternatives",
          "decisionReadiness": "notReady|needsFollowUp|readyForDecisionFrame|blockedByContradiction",
          "nextMoveRecommendation": "askClarification|frameDecision|recommendNextMove|compareOptions|requestUserInput|escalateForApproval|pause",
          "missingInfo": [String],
          "suggestedFollowUp": String,
          "requesterFacingExplanation": String,
          "requiresHumanJudgment": Bool,
          "safeForAutonomousFollowup": Bool,
          "confidence": Number
        }

        Thread role: \(context.role.rawValue)
        Second-half state: \(context.currentState.rawValue)
        Subject/request: \(json(context.subjectMatter))
        Requested items: \(jsonArray(context.requestedItems))
        Current constraints: \(jsonArray(context.currentConstraints))
        Clarified facts: \(jsonArray(context.clarifiedFacts))
        Known facts: \(jsonArray(context.knownFacts))
        Unresolved issues: \(jsonArray(context.unresolvedIssues))
        Latest provider response: \(json(context.latestCounterpartyReplyText))
        Prior assessment summary: \(json(prior))
        """
    }

    private static func json(_ value: String?) -> String {
        guard let value else { return "null" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func jsonArray(_ values: [String]) -> String {
        "[\(values.map { json($0) }.joined(separator: ", "))]"
    }
}

public struct LLMExchangeProviderResponseAssessmentEngine: AsyncExchangeProviderResponseAssessmentEngine, Sendable {
    public struct Configuration: Sendable, Hashable {
        public var timeoutSeconds: Double
        public var maxConditions: Int
        public var maxListItems: Int
        public var maxTextLength: Int

        public init(
            timeoutSeconds: Double = 2.0,
            maxConditions: Int = 20,
            maxListItems: Int = 24,
            maxTextLength: Int = 240
        ) {
            self.timeoutSeconds = timeoutSeconds
            self.maxConditions = maxConditions
            self.maxListItems = maxListItems
            self.maxTextLength = maxTextLength
        }
    }

    private let provider: (any AsyncProviderResponseAssessmentJSONProvider)?
    private let fallback: ExchangeHeuristicProviderResponseAssessmentEngine
    private let diagnosticsStore: ProviderResponseAssessmentDiagnosticsStore?
    private let config: Configuration

    public init(
        provider: (any AsyncProviderResponseAssessmentJSONProvider)?,
        fallback: ExchangeHeuristicProviderResponseAssessmentEngine = .init(),
        diagnosticsStore: ProviderResponseAssessmentDiagnosticsStore? = nil,
        config: Configuration = .init()
    ) {
        self.provider = provider
        self.fallback = fallback
        self.diagnosticsStore = diagnosticsStore
        self.config = config
    }

    public func assessProviderResponse(
        context: ExchangeSecondHalfExecutionContext,
        priorAssessment: ExchangeProviderResponseAssessment?
    ) async -> ExchangeProviderResponseAssessment? {
        guard let provider else {
            return await fallbackWith(context: context, priorAssessment: priorAssessment, reason: .providerUnavailable)
        }

        guard await provider.isReadyForImmediateExtraction() else {
            return await fallbackWith(context: context, priorAssessment: priorAssessment, reason: .modelBusy)
        }

        let prompt = ExchangeProviderResponseAssessmentPromptBuilder.buildPrompt(
            context: context,
            priorAssessment: priorAssessment
        )
        let start = CFAbsoluteTimeGetCurrent()
        let raw: String
        do {
            raw = try await withTimeout(seconds: max(0.05, config.timeoutSeconds)) {
                try await provider.assessProviderResponseJSON(prompt: prompt)
            }
        } catch is CancellationError {
            return await fallbackWith(
                context: context,
                priorAssessment: priorAssessment,
                reason: .cancelled,
                elapsedMs: elapsedMs(from: start)
            )
        } catch is ProviderResponseAssessmentTimeoutError {
            return await fallbackWith(
                context: context,
                priorAssessment: priorAssessment,
                reason: .timeout,
                elapsedMs: elapsedMs(from: start)
            )
        } catch is any ProviderResponseAssessmentProviderBusyError {
            return await fallbackWith(
                context: context,
                priorAssessment: priorAssessment,
                reason: .modelBusy,
                elapsedMs: elapsedMs(from: start)
            )
        } catch is any ProviderResponseAssessmentProviderUnavailableError {
            return await fallbackWith(
                context: context,
                priorAssessment: priorAssessment,
                reason: .providerUnavailable,
                elapsedMs: elapsedMs(from: start)
            )
        } catch {
            return await fallbackWith(
                context: context,
                priorAssessment: priorAssessment,
                reason: .thrownError,
                elapsedMs: elapsedMs(from: start)
            )
        }

        if let dto = decode(raw),
           let mapped = sanitizeAndMap(dto: dto, now: Date()) {
            await record(
                source: .llm,
                reason: nil,
                repairAttempted: false,
                elapsedMs: elapsedMs(from: start),
                mapped: mapped,
                confidence: dto.confidence
            )
            return mapped
        }

        let repaired = deterministicJSONRepair(raw)
        if let repaired,
           let dto = decode(repaired),
           let mapped = sanitizeAndMap(dto: dto, now: Date()) {
            await record(
                source: .llmRepairedJSON,
                reason: nil,
                repairAttempted: true,
                elapsedMs: elapsedMs(from: start),
                mapped: mapped,
                confidence: dto.confidence
            )
            return mapped
        }

        return await fallbackWith(
            context: context,
            priorAssessment: priorAssessment,
            reason: repaired == nil ? .invalidJSON : .repairFailed,
            repairAttempted: true,
            elapsedMs: elapsedMs(from: start)
        )
    }
}

private extension LLMExchangeProviderResponseAssessmentEngine {
    func fallbackWith(
        context: ExchangeSecondHalfExecutionContext,
        priorAssessment: ExchangeProviderResponseAssessment?,
        reason: ProviderResponseAssessmentFailureReason,
        repairAttempted: Bool = false,
        elapsedMs: Int? = nil
    ) async -> ExchangeProviderResponseAssessment? {
        let fallbackAssessment = fallback.assessProviderResponse(context: context, priorAssessment: priorAssessment)
        await record(
            source: .heuristicFallback,
            reason: reason,
            repairAttempted: repairAttempted,
            elapsedMs: elapsedMs,
            mapped: fallbackAssessment,
            confidence: nil
        )
        return fallbackAssessment
    }

    func record(
        source: ProviderResponseAssessmentSource,
        reason: ProviderResponseAssessmentFailureReason?,
        repairAttempted: Bool,
        elapsedMs: Int?,
        mapped: ExchangeProviderResponseAssessment?,
        confidence: Double?
    ) async {
        await diagnosticsStore?.record(
            .init(
                source: source,
                fallbackReason: reason,
                repairAttempted: repairAttempted,
                timeoutSeconds: reason == .timeout ? config.timeoutSeconds : nil,
                elapsedMs: elapsedMs,
                confidence: confidence,
                conditionCount: mapped?.conditionAssessments.count ?? 0,
                contradictionCount: mapped?.conditionAssessments.filter { $0.status == .contradicted }.count ?? 0
            )
        )
    }

    func decode(_ raw: String) -> LLMProviderResponseAssessmentDTO? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMProviderResponseAssessmentDTO.self, from: data)
    }

    func sanitizeAndMap(
        dto: LLMProviderResponseAssessmentDTO,
        now: Date
    ) -> ExchangeProviderResponseAssessment? {
        let mappedConditions = (dto.conditionAssessments ?? [])
            .compactMap { item -> ConditionAssessment? in
                guard let text = item.conditionText?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty,
                      let status = item.status else {
                    return nil
                }
                return ConditionAssessment(
                    conditionText: String(text.prefix(config.maxTextLength)),
                    source: item.source ?? .unknown,
                    status: status,
                    confidence: item.confidence,
                    evidence: sanitizeList(item.evidence ?? []),
                    missingInfo: sanitizeList(item.missingInfo ?? []),
                    suggestedFollowUp: item.suggestedFollowUp?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                )
            }
            .prefix(config.maxConditions)
            .map { $0 }

        guard !mappedConditions.isEmpty else { return nil }

        let missingInfo = sanitizeList(dto.missingInfo ?? mappedConditions.flatMap(\.missingInfo))
        let contradictionCount = mappedConditions.filter { $0.status == .contradicted }.count
        let requiresHumanJudgment = dto.requiresHumanJudgment ?? (contradictionCount > 0)
        let safeFollowUpRaw = dto.safeForAutonomousFollowup ?? mappedConditions.contains {
            $0.status == .needsFollowUp || $0.status == .notAnswered || $0.status == .impliedFlexible
        }

        return ExchangeProviderResponseAssessment(
            conditionAssessments: mappedConditions,
            providerFitSummary: dto.providerFitSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            confidenceDelta: dto.confidenceDelta ?? .stable,
            shortlistRecommendation: dto.shortlistRecommendation ?? .noChange,
            decisionReadiness: dto.decisionReadiness ?? .needsFollowUp,
            nextMoveRecommendation: dto.nextMoveRecommendation,
            missingInfo: missingInfo,
            suggestedFollowUp: dto.suggestedFollowUp?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            requesterFacingExplanation: dto.requesterFacingExplanation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            requiresHumanJudgment: requiresHumanJudgment,
            safeForAutonomousFollowup: safeFollowUpRaw && !requiresHumanJudgment,
            assessedAt: now,
            summary: dto.providerFitSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
    }

    func sanitizeList(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(config.maxTextLength)) }
            .reduce(into: [String]()) { acc, item in
                guard !acc.contains(item) else { return }
                acc.append(item)
            }
            .prefix(config.maxListItems)
            .map { $0 }
    }

    func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ProviderResponseAssessmentTimeoutError.timedOut
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    func deterministicJSONRepair(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}") else {
            return nil
        }
        var candidate = String(text[first...last])
        if let balanced = extractFirstBalancedJSONObject(candidate) {
            candidate = balanced
        }
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractFirstBalancedJSONObject(_ value: String) -> String? {
        var depth = 0
        var start: String.Index?
        for idx in value.indices {
            let ch = value[idx]
            if ch == "{" {
                if start == nil { start = idx }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let start {
                    return String(value[start...idx])
                }
                if depth < 0 { return nil }
            }
        }
        return nil
    }

    func elapsedMs(from start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
