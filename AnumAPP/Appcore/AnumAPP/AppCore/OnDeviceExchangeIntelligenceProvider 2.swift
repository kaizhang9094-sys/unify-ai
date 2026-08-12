import Foundation
import LlamaCppBridge

/// Concrete intelligence provider backed by a model runner.
///
/// Why this shape:
/// - Exchange stays clean and runtime-agnostic
/// - the app can inject any local runner it wants
/// - if the runner fails, we fail open to the conservative fallback
///
/// This is the correct place to turn structured Exchange judgment into
/// model prompts and parse the structured result back out.
public struct OnDeviceExchangeIntelligenceProvider: ExchangeIntelligenceProvider, Sendable {
    private let runner: any ExchangeIntelligenceModelRunner
    private let fallback: ExchangeFallbackIntelligenceProvider

    public init(
        runner: any ExchangeIntelligenceModelRunner,
        fallback: ExchangeFallbackIntelligenceProvider = ExchangeFallbackIntelligenceProvider()
    ) {
        self.runner = runner
        self.fallback = fallback
    }

    @MainActor
    public init() {
        self.init(runner: LlamaExchangeModelRunner())
    }

    public func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let prompt = ExchangeIntelligencePromptBuilder.interpretationPrompt(for: request)

        #if DEBUG
        print(
            "[ExchangeAI][Provider][interpret] start " +
            "userChars=\(request.userText.count) " +
            "promptChars=\(prompt.count) " +
            "hasThreadContext=\(request.threadContext != nil)"
        )
        #endif

        do {
            let runnerStart = CFAbsoluteTimeGetCurrent()
            let raw = try await runner.run(
                .init(
                    task: .interpretation,
                    prompt: prompt,
                    maxTokens: 220
                )
            )
            let runnerMs = Int((CFAbsoluteTimeGetCurrent() - runnerStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][interpret] runner_ok rawChars=\(raw.count) runner=\(runnerMs)ms")
            print("[ExchangeAI][Provider][interpret] rawPreview=\(String(raw.prefix(1200)))")
            #endif

            let cleanStart = CFAbsoluteTimeGetCurrent()
            let cleaned = Self.cleanJSON(raw)
            let cleanMs = Int((CFAbsoluteTimeGetCurrent() - cleanStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][interpret] cleanedChars=\(cleaned.count) clean=\(cleanMs)ms")
            print("[ExchangeAI][Provider][interpret] cleanedPreview=\(String(cleaned.prefix(1200)))")
            #endif

            let decodeStart = CFAbsoluteTimeGetCurrent()
            let decoded = try JSONDecoder().decode(
                ExchangeIntelligenceInterpretationResponse.self,
                from: Data(cleaned.utf8)
            )
            let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)

            #if DEBUG
            print(
                "[ExchangeAI][Provider][interpret] decode_ok " +
                "mode=\(decoded.mode.rawValue) " +
                "kind=\(decoded.kind.rawValue) " +
                "readiness=\(decoded.readiness.rawValue) " +
                "confidence=\(decoded.confidence) " +
                "decode=\(decodeMs)ms"
            )
            #endif

            guard isUsable(decoded) else {
                #if DEBUG
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                print("[ExchangeAI][Provider][interpret] fallback unusable_decoded total=\(totalMs)ms")
                #endif
                return try await fallback.interpret(request)
            }

            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[ExchangeAI][Provider][interpret] success " +
                "title=\(decoded.title) " +
                "runner=\(runnerMs)ms " +
                "clean=\(cleanMs)ms " +
                "decode=\(decodeMs)ms " +
                "total=\(totalMs)ms"
            )
            #endif

            return decoded
        } catch {
            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print("[ExchangeAI][Provider][interpret] fallback error=\(error) total=\(totalMs)ms")
            #endif
            return try await fallback.interpret(request)
        }
    }

    public func modelPosture(
        _ request: ExchangeIntelligencePostureRequest
    ) async throws -> ExchangeIntelligencePostureResponse {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let prompt = ExchangeIntelligencePromptBuilder.posturePrompt(for: request)

        #if DEBUG
        print(
            "[ExchangeAI][Provider][posture] start " +
            "userChars=\(request.userText.count) " +
            "promptChars=\(prompt.count) " +
            "intentKind=\(request.intent.kind.rawValue)"
        )
        #endif

        do {
            let runnerStart = CFAbsoluteTimeGetCurrent()
            let raw = try await runner.run(
                .init(
                    task: .posture,
                    prompt: prompt,
                    maxTokens: 180
                )
            )
            let runnerMs = Int((CFAbsoluteTimeGetCurrent() - runnerStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][posture] runner_ok rawChars=\(raw.count) runner=\(runnerMs)ms")
            print("[ExchangeAI][Provider][posture] rawPreview=\(String(raw.prefix(1000)))")
            #endif

            let cleanStart = CFAbsoluteTimeGetCurrent()
            let cleaned = Self.cleanJSON(raw)
            let cleanMs = Int((CFAbsoluteTimeGetCurrent() - cleanStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][posture] cleanedChars=\(cleaned.count) clean=\(cleanMs)ms")
            print("[ExchangeAI][Provider][posture] cleanedPreview=\(String(cleaned.prefix(1000)))")
            #endif

            let decodeStart = CFAbsoluteTimeGetCurrent()
            let decoded = try JSONDecoder().decode(
                ExchangeIntelligencePostureResponse.self,
                from: Data(cleaned.utf8)
            )
            let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)

            #if DEBUG
            print(
                "[ExchangeAI][Provider][posture] decode_ok " +
                "urgency=\(decoded.urgency.rawValue) " +
                "warmth=\(decoded.warmth.rawValue) " +
                "directness=\(decoded.directness.rawValue) " +
                "confidence=\(decoded.confidence) " +
                "decode=\(decodeMs)ms"
            )
            #endif

            guard isUsable(decoded) else {
                #if DEBUG
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                print("[ExchangeAI][Provider][posture] fallback unusable_decoded total=\(totalMs)ms")
                #endif
                return try await fallback.modelPosture(request)
            }

            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[ExchangeAI][Provider][posture] success " +
                "runner=\(runnerMs)ms " +
                "clean=\(cleanMs)ms " +
                "decode=\(decodeMs)ms " +
                "total=\(totalMs)ms"
            )
            #endif

            return decoded
        } catch {
            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print("[ExchangeAI][Provider][posture] fallback error=\(error) total=\(totalMs)ms")
            #endif
            return try await fallback.modelPosture(request)
        }
    }

    public func composeDraft(
        _ request: ExchangeIntelligenceDraftRequest
    ) async throws -> ExchangeIntelligenceDraftResponse {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let prompt = ExchangeIntelligencePromptBuilder.draftPrompt(for: request)

        #if DEBUG
        print(
            "[ExchangeAI][Provider][draft] start " +
            "promptChars=\(prompt.count) " +
            "threadID=\(request.thread.id.uuidString) " +
            "counterpartyID=\(request.counterparty.id) " +
            "kind=\(request.kind.rawValue)"
        )
        #endif

        do {
            let runnerStart = CFAbsoluteTimeGetCurrent()
            let raw = try await runner.run(
                .init(
                    task: .draft,
                    prompt: prompt,
                    maxTokens: 320
                )
            )
            let runnerMs = Int((CFAbsoluteTimeGetCurrent() - runnerStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][draft] runner_ok rawChars=\(raw.count) runner=\(runnerMs)ms")
            print("[ExchangeAI][Provider][draft] rawPreview=\(String(raw.prefix(1400)))")
            #endif

            let cleanStart = CFAbsoluteTimeGetCurrent()
            let cleaned = Self.cleanJSON(raw)
            let cleanMs = Int((CFAbsoluteTimeGetCurrent() - cleanStart) * 1000)

            #if DEBUG
            print("[ExchangeAI][Provider][draft] cleanedChars=\(cleaned.count) clean=\(cleanMs)ms")
            print("[ExchangeAI][Provider][draft] cleanedPreview=\(String(cleaned.prefix(1400)))")
            #endif

            let decodeStart = CFAbsoluteTimeGetCurrent()
            let decoded = try JSONDecoder().decode(
                ExchangeIntelligenceDraftResponse.self,
                from: Data(cleaned.utf8)
            )
            let decodeMs = Int((CFAbsoluteTimeGetCurrent() - decodeStart) * 1000)

            #if DEBUG
            print(
                "[ExchangeAI][Provider][draft] decode_ok " +
                "subjectChars=\(decoded.subject?.count ?? 0) " +
                "bodyChars=\(decoded.body.count) " +
                "confidence=\(decoded.confidence) " +
                "decode=\(decodeMs)ms"
            )
            #endif

            guard isUsable(decoded) else {
                #if DEBUG
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                print("[ExchangeAI][Provider][draft] fallback unusable_decoded total=\(totalMs)ms")
                #endif
                return try await fallback.composeDraft(request)
            }

            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[ExchangeAI][Provider][draft] success " +
                "runner=\(runnerMs)ms " +
                "clean=\(cleanMs)ms " +
                "decode=\(decodeMs)ms " +
                "total=\(totalMs)ms"
            )
            #endif

            return decoded
        } catch {
            #if DEBUG
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print("[ExchangeAI][Provider][draft] fallback error=\(error) total=\(totalMs)ms")
            #endif
            return try await fallback.composeDraft(request)
        }
    }
}

// MARK: - Concrete local runner

public struct LlamaExchangeModelRunner: ExchangeIntelligenceModelRunner, Sendable {
    public init() {}

    public func run(_ request: ExchangeIntelligenceModelRunRequest) async throws -> String {
        let totalStart = CFAbsoluteTimeGetCurrent()

        #if DEBUG
        print(
            "[ExchangeAI][Runner] start " +
            "task=\(request.task.rawValue) " +
            "promptChars=\(request.prompt.count) " +
            "maxTokens=\(request.maxTokens)"
        )
        #endif

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
            prompt: request.prompt,
            maxTokens: Int32(request.maxTokens),
            seqId: 0
        )

        LlamaCppBridge.resumeAfterBackground(modelPath: modelURL.path)

        var output = ""
        var chunkCount = 0
        var firstChunkMs: Int?

        do {
            for try await chunk in LlamaCppBridge.stream(cfg) {
                chunkCount += 1

                if firstChunkMs == nil {
                    firstChunkMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                    #if DEBUG
                    print(
                        "[ExchangeAI][Runner] first_chunk " +
                        "task=\(request.task.rawValue) " +
                        "elapsed=\(firstChunkMs ?? 0)ms " +
                        "chunkChars=\(chunk.count)"
                    )
                    #endif
                }

                output += chunk

                if output.count > 12_000 {
                    #if DEBUG
                    print("[ExchangeAI][Runner] output_truncated task=\(request.task.rawValue) atChars=\(output.count)")
                    #endif
                    break
                }
            }

            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)

            #if DEBUG
            print(
                "[ExchangeAI][Runner] done " +
                "task=\(request.task.rawValue) " +
                "ttft=\(firstChunkMs ?? -1)ms " +
                "total=\(totalMs)ms " +
                "chunks=\(chunkCount) " +
                "outputChars=\(trimmed.count)"
            )
            #endif

            return trimmed
        } catch {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)

            #if DEBUG
            print(
                "[ExchangeAI][Runner] failed " +
                "task=\(request.task.rawValue) " +
                "ttft=\(firstChunkMs ?? -1)ms " +
                "total=\(totalMs)ms " +
                "chunks=\(chunkCount) " +
                "error=\(error)"
            )
            #endif

            throw error
        }
    }
}

// MARK: - Runner boundary

public protocol ExchangeIntelligenceModelRunner: Sendable {
    func run(_ request: ExchangeIntelligenceModelRunRequest) async throws -> String
}

public struct ExchangeIntelligenceModelRunRequest: Sendable, Hashable {
    public enum Task: String, Sendable, Hashable {
        case interpretation
        case posture
        case draft
    }

    public var task: Task
    public var prompt: String
    public var maxTokens: Int

    public init(
        task: Task,
        prompt: String,
        maxTokens: Int
    ) {
        self.task = task
        self.prompt = prompt
        self.maxTokens = maxTokens
    }
}

// MARK: - Prompt builder

private enum ExchangeIntelligencePromptBuilder {
    static func interpretationPrompt(
        for request: ExchangeIntelligenceInterpretationRequest
    ) -> String {
        let contextBlock: String = {
            guard let ctx = request.threadContext else { return "null" }

            let threadID = ctx.threadID?.uuidString ?? "null"
            let modeHint = ctx.modeHint?.rawValue ?? "null"
            let priorIntentTitle = escaped(ctx.priorIntentTitle) ?? "null"
            let selectedCounterpartyID = escaped(ctx.selectedCounterpartyID) ?? "null"

            return """
            {
              "threadID": "\(threadID)",
              "modeHint": "\(modeHint)",
              "priorIntentTitle": \(priorIntentTitle),
              "selectedCounterpartyID": \(selectedCounterpartyID)
            }
            """
        }()

        return """
        You are the intelligence layer for a private AI secretary system.

        Your job is to interpret a user's natural-language coordination request into structured Exchange intent.

        Rules:
        - Return JSON only.
        - Do not wrap in markdown fences.
        - Be conservative.
        - If details are missing, set readiness to "needsClarification" or "underSpecified".
        - Keep title short.
        - Keep objective concrete.
        - Keep clarificationQuestion useful and specific when needed.
        - Confidence must be between 0 and 1.

        Allowed mode values:
        - transactional
        - cooperative
        - relational

        Allowed kind values:
        - requestQuote
        - introduce
        - negotiate
        - arrangeCall
        - arrangeMeeting
        - followUp
        - checkStatus
        - invite
        - source
        - find
        - message
        - coordinate
        - plan
        - other

        Allowed readiness values:
        - ready
        - needsClarification
        - underSpecified

        Output schema:
        {
          "mode": String,
          "kind": String,
          "title": String,
          "objective": String,
          "targetDescription": String?,
          "constraints": [
            {
              "key": String,
              "value": String,
              "isHardConstraint": Bool
            }
          ],
          "desiredOutcomes": [String],
          "readiness": String,
          "interpretationNotes": String?,
          "confidence": Double,
          "clarificationQuestion": String?
        }

        Thread context:
        \(contextBlock)

        User request:
        \(request.userText)
        """
    }

    static func posturePrompt(
        for request: ExchangeIntelligencePostureRequest
    ) -> String {
        let priorBlock: String = {
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
              "notes": \(escaped(prior.notes) ?? "null")
            }
            """
        }()

        return """
        You are the intelligence layer for a private AI secretary system.

        Your job is to model user posture for an Exchange thread.

        Posture is not identity.
        It is how the secretary should currently carry the user into this coordination.

        Rules:
        - Return JSON only.
        - Do not wrap in markdown fences.
        - Be conservative.
        - Respect the interpreted intent.
        - Confidence must be between 0 and 1.
        - Notes should be short.

        Allowed urgency values:
        - low
        - normal
        - high
        - immediate

        Allowed warmth values:
        - reserved
        - neutral
        - warm

        Allowed directness values:
        - soft
        - balanced
        - firm

        Allowed openness values:
        - selective
        - exploratory

        Allowed commitment values:
        - exploring
        - serious
        - committed

        Allowed privacy values:
        - guarded
        - balanced
        - disclosive

        Allowed priceSensitivity values:
        - notSpecified
        - low
        - moderate
        - high

        Allowed flexibility values:
        - rigid
        - moderate
        - flexible

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

        Interpreted intent:
        {
          "mode": "\(request.intent.mode.rawValue)",
          "kind": "\(request.intent.kind.rawValue)",
          "title": "\(request.intent.title)",
          "objective": "\(request.intent.objective)",
          "targetDescription": \(escaped(request.intent.targetDescription) ?? "null"),
          "readiness": "\(request.intent.readiness.rawValue)"
        }

        Prior posture:
        \(priorBlock)

        User request:
        \(request.userText)
        """
    }

    static func draftPrompt(
        for request: ExchangeIntelligenceDraftRequest
    ) -> String {
        let supersedingBlock: String = {
            guard let draft = request.supersedingDraft else { return "null" }

            return """
            {
              "subject": \(escaped(draft.subject) ?? "null"),
              "body": \(escaped(draft.body) ?? "null"),
              "strategyNote": \(escaped(draft.strategyNote) ?? "null")
            }
            """
        }()

        return """
        You are the intelligence layer for a private AI secretary system.

        Your job is to produce an outbound draft for a selected counterparty.

        Rules:
        - Return JSON only.
        - Do not wrap in markdown fences.
        - No fake certainty.
        - No over-commitment.
        - No unnecessary disclosure.
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

        Thread:
        {
          "mode": "\(request.thread.mode.rawValue)",
          "intentKind": "\(request.thread.intent.kind.rawValue)",
          "intentTitle": "\(request.thread.intent.title)",
          "objective": "\(request.thread.intent.objective)",
          "targetDescription": \(escaped(request.thread.intent.targetDescription) ?? "null"),
          "constraints": \(renderConstraints(request.thread.intent.constraints)),
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
          "id": "\(request.counterparty.id)",
          "displayName": \(escaped(request.counterparty.displayName) ?? "null"),
          "bestDisplayLine": "\(request.counterparty.bestDisplayLine)",
          "kind": "\(request.counterparty.kind.rawValue)"
        }

        Draft kind:
        \(request.kind.rawValue)

        Superseded draft:
        \(supersedingBlock)
        """
    }

    private static func escaped(_ value: String?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return encoded
    }

    private static func renderConstraints(
        _ constraints: [ExchangeIntent.Constraint]
    ) -> String {
        guard !constraints.isEmpty else { return "[]" }

        let items = constraints.map { constraint in
            """
            {"key":"\(constraint.key)","value":"\(constraint.value)","isHardConstraint":\(constraint.isHardConstraint ? "true" : "false")}
            """
        }

        return "[\(items.joined(separator: ","))]"
    }
}

// MARK: - Validation / cleanup

private extension OnDeviceExchangeIntelligenceProvider {
    static func cleanJSON(_ raw: String) -> String {
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

        #if DEBUG
        print("[ExchangeAI][Provider] cleanJSON inChars=\(raw.count) outChars=\(text.count)")
        #endif

        return text
    }

    func isUsable(_ response: ExchangeIntelligenceInterpretationResponse) -> Bool {
        let title = response.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let objective = response.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = !title.isEmpty && !objective.isEmpty

        #if DEBUG
        print(
            "[ExchangeAI][Provider][interpret] usability " +
            "ok=\(ok) " +
            "titleEmpty=\(title.isEmpty) " +
            "objectiveEmpty=\(objective.isEmpty)"
        )
        #endif

        return ok
    }

    func isUsable(_ response: ExchangeIntelligencePostureResponse) -> Bool {
        let ok = response.confidence >= 0.20

        #if DEBUG
        print("[ExchangeAI][Provider][posture] usability ok=\(ok) confidence=\(response.confidence)")
        #endif

        return ok
    }

    func isUsable(_ response: ExchangeIntelligenceDraftResponse) -> Bool {
        let body = response.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = !body.isEmpty

        #if DEBUG
        print("[ExchangeAI][Provider][draft] usability ok=\(ok) bodyChars=\(body.count)")
        #endif

        return ok
    }
}
