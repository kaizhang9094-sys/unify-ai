import Foundation
import AnumCore
import LlamaCppBridge

private struct AIInterpretationDTO: Decodable {
    struct ConstraintDTO: Decodable {
        let key: String
        let value: String
        let isHardConstraint: Bool?
    }

    struct PostureDTO: Decodable {
        let urgency: ExchangePosture.Urgency
        let warmth: ExchangePosture.Warmth
        let directness: ExchangePosture.Directness
        let openness: ExchangePosture.Openness
        let commitment: ExchangePosture.Commitment
        let privacy: ExchangePosture.Privacy
        let priceSensitivity: ExchangePosture.PriceSensitivity
        let flexibility: ExchangePosture.Flexibility
        let notes: String?
        let confidence: Double?
    }

    let mode: ExchangeMode
    let kind: ExchangeIntent.Kind
    let title: String
    let objective: String
    let targetDescription: String?
    let constraints: [ConstraintDTO]?
    let desiredOutcomes: [ExchangeIntent.DesiredOutcome]?
    let readiness: ExchangeIntent.Readiness
    let interpretationNotes: String?
    let confidence: Double
    let clarificationQuestion: String?

    let userSummary: String?
    let userQuestion: String?
    let userNextStep: String?

    let inferredPosture: PostureDTO?
    let needsClarification: Bool?
    let shouldDiscover: Bool?
    let shouldDraft: Bool?
}

private func decodeInterpretationDTO(from text: String) throws -> AIInterpretationDTO {
    try JSONDecoder().decode(AIInterpretationDTO.self, from: Data(text.utf8))
}

actor OnDeviceExchangeIntelligenceProvider: ExchangeIntelligenceProvider {
    private let runner: LlamaExchangeModelRunner
    private let fallback: ExchangeFallbackIntelligenceProvider

    init(
        runner: LlamaExchangeModelRunner,
        fallback: ExchangeFallbackIntelligenceProvider = ExchangeFallbackIntelligenceProvider()
    ) {
        self.runner = runner
        self.fallback = fallback
    }

    @MainActor
    init() {
        self.init(runner: LlamaExchangeModelRunner())
    }

    func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        let prompt = Self.buildInterpretationPrompt(request)

        do {
            print("[ExchangeAI] interpret -> llama start")
            let raw = try await runner.run(
                prompt: prompt,
                maxTokens: 420,
                seqId: 0
            )
            print("[ExchangeAI] interpret <- llama raw chars=\(raw.count)")
            print("[ExchangeAI] interpret raw=\(String(raw.prefix(1200)))")

            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[ExchangeAI] interpret fallback: empty model output")
                return try await fallback.interpret(request)
            }

            let cleaned = Self.cleanJSON(raw)
            if !cleaned.isEmpty,
               cleaned.first == "{",
               Self.extractFirstJSONObject(from: cleaned) == nil {
                print("[ExchangeAI] interpret fallback: truncated JSON detected")
                return try await fallback.interpret(request)
            }

            let dto = try await decodeInterpretationDTO(from: cleaned)

            let inferredPosture: ExchangeIntelligencePostureResponse? = dto.inferredPosture.map {
                ExchangeIntelligencePostureResponse(
                    urgency: $0.urgency,
                    warmth: $0.warmth,
                    directness: $0.directness,
                    openness: $0.openness,
                    commitment: $0.commitment,
                    privacy: $0.privacy,
                    priceSensitivity: $0.priceSensitivity,
                    flexibility: $0.flexibility,
                    notes: $0.notes,
                    confidence: Self.clamp($0.confidence ?? 0.55)
                )
            }

            let normalizedHints = Self.normalizeExecutionHints(
                kind: dto.kind,
                readiness: dto.readiness,
                threadContext: request.threadContext,
                needsClarification: dto.needsClarification,
                shouldDiscover: dto.shouldDiscover,
                shouldDraft: dto.shouldDraft
            )

            let decoded = ExchangeIntelligenceInterpretationResponse(
                mode: dto.mode,
                kind: dto.kind,
                title: dto.title,
                objective: dto.objective,
                targetDescription: dto.targetDescription,
                constraints: (dto.constraints ?? []).map {
                    ExchangeIntent.Constraint(
                        key: $0.key,
                        value: $0.value,
                        isHardConstraint: $0.isHardConstraint ?? false
                    )
                },
                desiredOutcomes: dto.desiredOutcomes ?? [],
                readiness: dto.readiness,
                interpretationNotes: dto.interpretationNotes,
                confidence: dto.confidence,
                clarificationQuestion: dto.clarificationQuestion,
                userSummary: dto.userSummary,
                userQuestion: dto.userQuestion,
                userNextStep: dto.userNextStep,
                inferredPosture: inferredPosture,
                needsClarification: normalizedHints.needsClarification,
                shouldDiscover: normalizedHints.shouldDiscover,
                shouldDraft: normalizedHints.shouldDraft
            )

            guard Self.isUsable(decoded) else {
                print("[ExchangeAI] interpret fallback: unusable decoded response")
                return try await fallback.interpret(request)
            }

            return Self.sanitize(decoded, threadContext: request.threadContext)
        } catch {
            print("[ExchangeAI] interpret fallback: error=\(error)")
            return try await fallback.interpret(request)
        }
    }

    func modelPosture(
        _ request: ExchangeIntelligencePostureRequest
    ) async throws -> ExchangeIntelligencePostureResponse {
        let prompt = Self.buildPosturePrompt(request)

        do {
            print("[ExchangeAI] posture -> llama start")
            let raw = try await runner.run(
                prompt: prompt,
                maxTokens: 220,
                seqId: 0
            )
            print("[ExchangeAI] posture <- llama raw chars=\(raw.count)")
            print("[ExchangeAI] posture raw=\(String(raw.prefix(900)))")

            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[ExchangeAI] posture fallback: empty model output")
                return try await fallback.modelPosture(request)
            }

            let cleaned = Self.cleanJSON(raw)
            let decoded = try JSONDecoder().decode(
                ExchangeIntelligencePostureResponse.self,
                from: Data(cleaned.utf8)
            )

            guard Self.isUsable(decoded) else {
                print("[ExchangeAI] posture fallback: unusable decoded response")
                return try await fallback.modelPosture(request)
            }

            return Self.sanitize(decoded)
        } catch {
            print("[ExchangeAI] posture fallback: error=\(error)")
            return try await fallback.modelPosture(request)
        }
    }

    func composeDraft(
        _ request: ExchangeIntelligenceDraftRequest
    ) async throws -> ExchangeIntelligenceDraftResponse {
        let prompt = Self.buildDraftPrompt(request)

        do {
            print("[ExchangeAI] draft -> llama start")
            let raw = try await runner.run(
                prompt: prompt,
                maxTokens: 640,
                seqId: 0
            )
            print("[ExchangeAI] draft <- llama raw chars=\(raw.count)")
            print("[ExchangeAI] draft raw=\(String(raw.prefix(1200)))")

            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("[ExchangeAI] draft fallback: empty model output")
                return try await fallback.composeDraft(request)
            }

            let cleaned = Self.cleanJSON(raw)
            let decoded = try JSONDecoder().decode(
                ExchangeIntelligenceDraftResponse.self,
                from: Data(cleaned.utf8)
            )

            guard Self.isUsable(decoded) else {
                print("[ExchangeAI] draft fallback: unusable decoded response")
                return try await fallback.composeDraft(request)
            }

            return Self.sanitize(decoded)
        } catch {
            print("[ExchangeAI] draft fallback: error=\(error)")
            return try await fallback.composeDraft(request)
        }
    }
}

struct LlamaExchangeModelRunner: Sendable {
    init() {}

    func run(
        prompt: String,
        maxTokens: Int,
        seqId: Int32
    ) async throws -> String {
        print("[ExchangeAI] runner start seqId=\(seqId) promptChars=\(prompt.count)")

        let modelURL = try await MainActor.run {
            try ModelStore.shared.beginAccessingModel()
        }
        defer {
            Task { @MainActor in
                ModelStore.shared.stopAccessing(modelURL)
            }
        }

        let cfg = LlamaStreamConfig(
            modelPath: modelURL.path,
            prompt: prompt,
            maxTokens: Int32(maxTokens),
            seqId: seqId
        )

        LlamaCppBridge.resumeAfterBackground(modelPath: modelURL.path)

        var output = ""
        var chunkCount = 0

        for try await chunk in LlamaCppBridge.stream(cfg) {
            chunkCount += 1
            if chunkCount == 1 {
                print("[ExchangeAI] runner first chunk seqId=\(seqId) chars=\(chunk.count)")
            }

            output += chunk
            if output.count > 12_000 {
                break
            }
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[ExchangeAI] runner done seqId=\(seqId) outputChars=\(trimmed.count) chunkCount=\(chunkCount)")
        return trimmed
    }
}

private extension OnDeviceExchangeIntelligenceProvider {
    struct NormalizedExecutionHints {
        let needsClarification: Bool
        let shouldDiscover: Bool
        let shouldDraft: Bool
    }

    static func buildInterpretationPrompt(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) -> String {
        let context = renderThreadContext(request.threadContext)

        let system = """
You are the intelligence layer for a private AI secretary system.

Task:
Convert a user's message into structured secretary intent and inferred secretary posture in a single pass.

Rules:
- Return JSON only.
- No markdown fences.
- Be conservative.
- If key details are missing, use readiness "needsClarification" or "underSpecified".
- Keep title short.
- Keep objective concrete.
- Confidence values must be between 0 and 1.
- userSummary should be a short, natural sentence a human can read.
- userQuestion should be present when clarification is needed.
- userNextStep should describe the next likely secretary action in plain language.
- inferredPosture should reflect the user's current coordination posture, not identity.
- needsClarification should be true only when the secretary should stop and ask before acting.
- shouldDiscover should be true when discovery / matching is the next likely system step.
- shouldDraft should be true when draft preparation is the next likely system step after interpretation.
- Do not set both shouldDiscover and shouldDraft to true unless there is a strong reason.
- Do not use internal taxonomy words in user-facing fields.
- Do not expose extraction jargon, ranking jargon, or schema language in user-facing fields.

Allowed mode values:
["transactional","cooperative","relational"]

Allowed kind values:
["requestQuote","introduce","negotiate","arrangeCall","arrangeMeeting","followUp","checkStatus","invite","source","find","message","coordinate","plan","other"]

Allowed readiness values:
["ready","needsClarification","underSpecified"]

Allowed desiredOutcomes values:
["shortlist","intro","quote","meeting","response","aligned","resolved"]

Allowed urgency:
["low","normal","high","immediate"]

Allowed warmth:
["reserved","neutral","warm"]

Allowed directness:
["soft","balanced","firm"]

Allowed openness:
["selective","exploratory"]

Allowed commitment:
["exploring","serious","committed"]

Allowed privacy:
["guarded","balanced","disclosive"]

Allowed priceSensitivity:
["notSpecified","low","moderate","high"]

Allowed flexibility:
["rigid","moderate","flexible"]

Output schema:
{
  "mode": String,
  "kind": String,
  "title": String,
  "objective": String,
  "targetDescription": String?,
  "constraints": [{"key": String, "value": String, "isHardConstraint": Bool}],
  "desiredOutcomes": [String],
  "readiness": String,
  "interpretationNotes": String?,
  "confidence": Double,
  "clarificationQuestion": String?,
  "userSummary": String?,
  "userQuestion": String?,
  "userNextStep": String?,
  "inferredPosture": {
    "urgency": String,
    "warmth": String,
    "directness": String,
    "openness": String,
    "commitment": String,
    "privacy": String,
    "priceSensitivity": String,
    "flexibility": String,
    "notes": String?,
    "confidence": Double
  }?,
  "needsClarification": Bool,
  "shouldDiscover": Bool,
  "shouldDraft": Bool
}
"""

        let user = """
Thread context:
\(context)

User request:
\(request.userText)
"""

        return gemmaPrompt(system: system, user: user)
    }

    static func buildPosturePrompt(
        _ request: ExchangeIntelligencePostureRequest
    ) -> String {
        let intent = """
{
  "mode": "\(request.intent.mode.rawValue)",
  "kind": "\(request.intent.kind.rawValue)",
  "title": \(jsonString(request.intent.title)),
  "objective": \(jsonString(request.intent.objective)),
  "targetDescription": \(jsonOptionalString(request.intent.targetDescription)),
  "readiness": "\(request.intent.readiness.rawValue)"
}
"""

        let prior: String = {
            guard let prior = request.priorPosture else { return "null" }
            return """
{
  "urgency": "\(prior.urgency.rawValue)",
  "warmth": "\(prior.warmth.rawValue)",
  "directness": "\(prior.directness.rawValue)",
  "openness": "\(prior.openness.rawValue)",
  "commitment": "\(prior.commitment.rawValue)",
  "privacy": "\(prior.privacy.rawValue)",
  "priceSensitivity": "\(prior.priceSensitivity.rawValue)",
  "flexibility": "\(prior.flexibility.rawValue)",
  "notes": \(jsonOptionalString(prior.notes))
}
"""
        }()

        let system = """
You are the intelligence layer for a private AI secretary system.

Task:
Infer the user's current secretary posture for this thread.

Rules:
- Return JSON only.
- No markdown fences.
- Posture is not identity.
- Be conservative.
- Confidence must be between 0 and 1.
- Notes should be short.

Allowed urgency:
["low","normal","high","immediate"]

Allowed warmth:
["reserved","neutral","warm"]

Allowed directness:
["soft","balanced","firm"]

Allowed openness:
["selective","exploratory"]

Allowed commitment:
["exploring","serious","committed"]

Allowed privacy:
["guarded","balanced","disclosive"]

Allowed priceSensitivity:
["notSpecified","low","moderate","high"]

Allowed flexibility:
["rigid","moderate","flexible"]

Output schema:
{
  "urgency": String,
  "warmth": String,
  "directness": String,
  "openness": String,
  "commitment": String,
  "privacy": String,
  "priceSensitivity": String,
  "flexibility": String,
  "notes": String?,
  "confidence": Double
}
"""

        let user = """
Intent:
\(intent)

Prior posture:
\(prior)

User request:
\(request.userText)
"""

        return gemmaPrompt(system: system, user: user)
    }

    static func buildDraftPrompt(
        _ request: ExchangeIntelligenceDraftRequest
    ) -> String {
        let constraints = request.thread.intent.constraints.map {
            """
{"key": \(jsonString($0.key)), "value": \(jsonString($0.value)), "isHardConstraint": \($0.isHardConstraint ? "true" : "false")}
"""
        }.joined(separator: ",")

        let superseding: String = {
            guard let draft = request.supersedingDraft else { return "null" }
            return """
{
  "subject": \(jsonOptionalString(draft.subject)),
  "body": \(jsonString(draft.body)),
  "strategyNote": \(jsonOptionalString(draft.strategyNote))
}
"""
        }()

        let system = """
You are the intelligence layer for a private AI secretary system.

Task:
Write a careful outbound draft for the selected counterparty.

Rules:
- Return JSON only.
- No markdown fences.
- No fake certainty.
- No unnecessary disclosure.
- No over-commitment.
- Keep it practical and human.
- Subject may be null.
- Confidence must be between 0 and 1.

Output schema:
{
  "subject": String?,
  "body": String,
  "strategyNote": String?,
  "confidence": Double
}
"""

        let user = """
Thread:
{
  "mode": "\(request.thread.mode.rawValue)",
  "intentKind": "\(request.thread.intent.kind.rawValue)",
  "intentTitle": \(jsonString(request.thread.intent.title)),
  "objective": \(jsonString(request.thread.intent.objective)),
  "targetDescription": \(jsonOptionalString(request.thread.intent.targetDescription)),
  "constraints": [\(constraints)],
  "posture": {
    "urgency": "\(request.thread.posture.urgency.rawValue)",
    "warmth": "\(request.thread.posture.warmth.rawValue)",
    "directness": "\(request.thread.posture.directness.rawValue)",
    "openness": "\(request.thread.posture.openness.rawValue)",
    "commitment": "\(request.thread.posture.commitment.rawValue)",
    "privacy": "\(request.thread.posture.privacy.rawValue)",
    "priceSensitivity": "\(request.thread.posture.priceSensitivity.rawValue)",
    "flexibility": "\(request.thread.posture.flexibility.rawValue)"
  }
}

Counterparty:
{
  "id": \(jsonString(request.counterparty.id)),
  "displayName": \(jsonOptionalString(request.counterparty.displayName)),
  "bestDisplayLine": \(jsonString(request.counterparty.bestDisplayLine)),
  "kind": "\(request.counterparty.kind.rawValue)"
}

Draft kind:
"\(request.kind.rawValue)"

Superseding draft:
\(superseding)
"""

        return gemmaPrompt(system: system, user: user)
    }

    static func gemmaPrompt(system: String, user: String) -> String {
        """
<start_of_turn>user
[Instruction Context]
\(system)

\(user)
<end_of_turn>
<start_of_turn>model
"""
    }

    static func renderThreadContext(
        _ context: ExchangeInterpreter.ThreadContext?
    ) -> String {
        guard let context else { return "null" }

        return """
{
  "threadID": \(jsonOptionalString(context.threadID?.uuidString)),
  "modeHint": \(jsonOptionalString(context.modeHint?.rawValue)),
  "priorIntentTitle": \(jsonOptionalString(context.priorIntentTitle)),
  "selectedCounterpartyID": \(jsonOptionalString(context.selectedCounterpartyID))
}
"""
    }

    static func cleanJSON(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            } else {
                return ""
            }

            if let closing = text.range(of: "```", options: .backwards) {
                text.removeSubrange(closing)
            }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.lowercased().hasPrefix("json\n") {
            text = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return extractFirstJSONObject(from: text) ?? text
    }

    static func extractFirstJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaping = false

        var i = start
        while i < text.endIndex {
            let ch = text[i]

            if escaping {
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...i]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            i = text.index(after: i)
        }

        return nil
    }

    static func isUsable(_ response: ExchangeIntelligenceInterpretationResponse) -> Bool {
        let title = response.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let objective = response.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && !objective.isEmpty
    }

    static func isUsable(_ response: ExchangeIntelligencePostureResponse) -> Bool {
        response.confidence >= 0.20
    }

    static func isUsable(_ response: ExchangeIntelligenceDraftResponse) -> Bool {
        !response.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func sanitize(
        _ response: ExchangeIntelligenceInterpretationResponse,
        threadContext: ExchangeInterpreter.ThreadContext?
    ) -> ExchangeIntelligenceInterpretationResponse {
        let normalizedHints = normalizeExecutionHints(
            kind: response.kind,
            readiness: response.readiness,
            threadContext: threadContext,
            needsClarification: response.needsClarification,
            shouldDiscover: response.shouldDiscover,
            shouldDraft: response.shouldDraft
        )

        return ExchangeIntelligenceInterpretationResponse(
            mode: response.mode,
            kind: response.kind,
            title: String(response.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
            objective: String(response.objective.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280)),
            targetDescription: trimmed(response.targetDescription, limit: 120),
            constraints: Array(response.constraints.prefix(8)).filter {
                !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            desiredOutcomes: response.desiredOutcomes.isEmpty
                ? [.resolved]
                : Array(response.desiredOutcomes.prefix(5)),
            readiness: response.readiness,
            interpretationNotes: trimmed(response.interpretationNotes, limit: 240),
            confidence: clamp(response.confidence),
            clarificationQuestion: trimmed(response.clarificationQuestion, limit: 180),
            userSummary: trimmed(response.userSummary, limit: 220),
            userQuestion: trimmed(response.userQuestion, limit: 180),
            userNextStep: trimmed(response.userNextStep, limit: 220),
            inferredPosture: response.inferredPosture.map {
                ExchangeIntelligencePostureResponse(
                    urgency: $0.urgency,
                    warmth: $0.warmth,
                    directness: $0.directness,
                    openness: $0.openness,
                    commitment: $0.commitment,
                    privacy: $0.privacy,
                    priceSensitivity: $0.priceSensitivity,
                    flexibility: $0.flexibility,
                    notes: trimmed($0.notes, limit: 240),
                    confidence: clamp($0.confidence)
                )
            },
            needsClarification: normalizedHints.needsClarification,
            shouldDiscover: normalizedHints.shouldDiscover,
            shouldDraft: normalizedHints.shouldDraft
        )
    }

    static func sanitize(
        _ response: ExchangeIntelligencePostureResponse
    ) -> ExchangeIntelligencePostureResponse {
        ExchangeIntelligencePostureResponse(
            urgency: response.urgency,
            warmth: response.warmth,
            directness: response.directness,
            openness: response.openness,
            commitment: response.commitment,
            privacy: response.privacy,
            priceSensitivity: response.priceSensitivity,
            flexibility: response.flexibility,
            notes: trimmed(response.notes, limit: 240),
            confidence: clamp(response.confidence)
        )
    }

    static func sanitize(
        _ response: ExchangeIntelligenceDraftResponse
    ) -> ExchangeIntelligenceDraftResponse {
        ExchangeIntelligenceDraftResponse(
            subject: trimmed(response.subject, limit: 120),
            body: String(response.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2400)),
            strategyNote: trimmed(response.strategyNote, limit: 300),
            confidence: clamp(response.confidence)
        )
    }

    static func trimmed(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    static func defaultNeedsClarification(
        readiness: ExchangeIntent.Readiness
    ) -> Bool {
        switch readiness {
        case .ready:
            return false
        case .needsClarification, .underSpecified:
            return true
        }
    }

    static func defaultShouldDiscover(
        kind: ExchangeIntent.Kind,
        readiness: ExchangeIntent.Readiness,
        threadContext: ExchangeInterpreter.ThreadContext?
    ) -> Bool {
        if defaultNeedsClarification(readiness: readiness) {
            return false
        }

        switch kind {
        case .find, .source, .introduce, .requestQuote:
            return true
        case .message, .followUp, .checkStatus, .arrangeCall, .arrangeMeeting, .invite, .coordinate, .plan, .negotiate:
            return threadContext?.selectedCounterpartyID == nil
        case .other:
            return false
        }
    }

    static func defaultShouldDraft(
        kind: ExchangeIntent.Kind,
        readiness: ExchangeIntent.Readiness,
        threadContext: ExchangeInterpreter.ThreadContext?
    ) -> Bool {
        if defaultNeedsClarification(readiness: readiness) {
            return false
        }

        switch kind {
        case .message, .followUp, .checkStatus, .arrangeCall, .arrangeMeeting, .invite, .coordinate, .plan, .negotiate:
            return threadContext?.selectedCounterpartyID != nil
        case .introduce, .requestQuote, .find, .source, .other:
            return false
        }
    }

    static func normalizeExecutionHints(
        kind: ExchangeIntent.Kind,
        readiness: ExchangeIntent.Readiness,
        threadContext: ExchangeInterpreter.ThreadContext?,
        needsClarification: Bool?,
        shouldDiscover: Bool?,
        shouldDraft: Bool?
    ) -> NormalizedExecutionHints {
        let normalizedNeedsClarification = needsClarification ?? defaultNeedsClarification(readiness: readiness)

        var normalizedShouldDiscover = shouldDiscover ?? defaultShouldDiscover(
            kind: kind,
            readiness: readiness,
            threadContext: threadContext
        )

        var normalizedShouldDraft = shouldDraft ?? defaultShouldDraft(
            kind: kind,
            readiness: readiness,
            threadContext: threadContext
        )

        if normalizedNeedsClarification {
            normalizedShouldDiscover = false
            normalizedShouldDraft = false
        }

        if readiness != .ready {
            normalizedShouldDraft = false
        }

        if normalizedShouldDraft {
            normalizedShouldDiscover = false
        }

        return NormalizedExecutionHints(
            needsClarification: normalizedNeedsClarification,
            shouldDiscover: normalizedShouldDiscover,
            shouldDraft: normalizedShouldDraft
        )
    }

    static func jsonString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return String(data: data ?? Data("\"\"".utf8), encoding: .utf8) ?? "\"\""
    }

    static func jsonOptionalString(_ value: String?) -> String {
        guard let value else { return "null" }
        return jsonString(value)
    }
}
