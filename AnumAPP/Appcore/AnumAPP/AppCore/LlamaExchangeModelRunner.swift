import Foundation
import CryptoKit
import AnumCore
import LlamaCppBridge

private actor DirectChatPromptCheckpointState {
    static let shared = DirectChatPromptCheckpointState()
    private var lastFullPromptHash: String?
    private var knownScaffoldHash: String?
    private var scaffoldKnownValid: Bool = false

    func selectReplayMode(
        promptCheckpointEnabled: Bool,
        scaffoldReplayEnabled: Bool,
        fullPromptHash: String,
        scaffoldHash: String
    ) -> LlamaStreamConfig.PromptMode {
        if promptCheckpointEnabled, lastFullPromptHash == fullPromptHash {
            return .promptCheckpointRegenerate
        }
        if scaffoldReplayEnabled, scaffoldKnownValid, knownScaffoldHash == scaffoldHash {
            return .promptScaffoldCheckpointReplay
        }
        return .fullReplay
    }

    func recordSelection(fullPromptHash: String) {
        lastFullPromptHash = fullPromptHash
    }

    func noteSuccessfulScaffoldCheckpointCapture(scaffoldHash: String) {
        knownScaffoldHash = scaffoldHash
        scaffoldKnownValid = true
    }
}

public struct LlamaExchangeModelRunner: ExchangeIntelligenceModelRunner, Sendable {
    private let secretaryConstitutionProvider: @Sendable () -> String?

    public init(
        secretaryConstitutionProvider: (@Sendable () -> String?)? = nil
    ) {
        self.secretaryConstitutionProvider = secretaryConstitutionProvider ?? { nil }
    }

    public func run(_ request: ExchangeIntelligenceModelRunRequest) async throws -> String {
        let totalStart = CFAbsoluteTimeGetCurrent()

        #if DEBUG
        let directReplyPerf = request.task == .directChatReply
        var perfStreamGateWaitMs: Int = 0
        if directReplyPerf {
            print("[DirectReplyPerf] runner_enter task=\(request.task.rawValue)")
        }
        #endif

        let resolved = resolveTaskPolicy(for: request)

        let rawConstitutionText = cleanConstitutionText(secretaryConstitutionProvider())
        let rawStyleSupplement = cleanStyleSupplementText(request.representationSupplement)

        let constitutionGate = SecretaryPromptLayeringGate.shouldInjectConstitution(for: request.task)
        let representationGate = SecretaryPromptLayeringGate.shouldInjectRepresentationSupplement(for: request.task)

        let constitutionText = constitutionGate ? rawConstitutionText : ""
        let styleSupplement = representationGate ? rawStyleSupplement : ""

        #if DEBUG
        print(
            "[SecretaryInstructionInjection] task=\(request.task.rawValue) " +
            "constitutionInjected=\(!constitutionText.isEmpty) representationSupplementInjected=\(!styleSupplement.isEmpty) " +
            "constitutionChars=\(constitutionText.count) styleChars=\(styleSupplement.count) " +
            "constitutionGate=\(constitutionGate) representationGate=\(representationGate) " +
            "rawConstitutionChars=\(rawConstitutionText.count) rawStyleChars=\(rawStyleSupplement.count)"
        )
        #endif

        let finalPrompt = buildPrompt(
            rawPrompt: request.prompt,
            task: request.task,
            constitutionText: constitutionText,
            representationSupplement: styleSupplement
        )

        #if DEBUG
        if request.task == .searchIntentExtraction {
            let trimmedPayload = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let scaffoldOnly = ExchangeSecretaryPromptInstructionBlocks.exchangeRunnerInstructionScaffold(
                constitutionText: constitutionText.isEmpty ? nil : constitutionText,
                task: request.task
            )
            let systemTurn = exchangeSystemPrompt(constitutionText: constitutionText, task: request.task)
            let userTurn = composedUserTaskPayload(
                rawPrompt: trimmedPayload,
                task: request.task,
                representationSupplement: styleSupplement
            )
            let asstPrefix = qwenAssistantGenerationPrefix(task: request.task)
            let sumParts = systemTurn.count + userTurn.count + asstPrefix.count
            print(
                "[ExchangeAI][Runner][searchIntentPrompt] " +
                "rawPromptChars=\(request.prompt.count) " +
                "scaffoldChars=\(scaffoldOnly.count) " +
                "systemTurnChars=\(systemTurn.count) " +
                "userTurnChars=\(userTurn.count) " +
                "assistantPrefixChars=\(asstPrefix.count) " +
                "partsSumChars=\(sumParts) " +
                "finalPromptChars=\(finalPrompt.count) " +
                "requestedMaxTokens=\(request.maxTokens) " +
                "resolvedMaxTokens=\(resolved.maxTokens)"
            )
        }
        #endif

        let stableScaffoldPrefix = directChatStableScaffoldPrefix(constitutionText: constitutionText)
        let scaffoldIdentityHash = stableHash(stableScaffoldPrefix)

        #if DEBUG
        if request.task == .directChatReply {
            precondition(
                finalPrompt.hasPrefix(stableScaffoldPrefix),
                "Direct Chat finalPrompt must begin with the stable exchangeSystemPrompt(directChatReply) prefix."
            )
        }
        #endif

        #if DEBUG
        if directReplyPerf {
            let setupMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[DirectReplyPerf] runner_setup_done elapsedMs=\(setupMs) finalPromptChars=\(finalPrompt.count) promptChars=\(request.prompt.count)"
            )
        }
        #endif

        #if DEBUG
        debugSecretaryPromptAuditExchange(
            finalPrompt: finalPrompt,
            request: request,
            constitutionText: constitutionText,
            styleSupplement: styleSupplement
        )
        #endif

        #if DEBUG
        print(
            "[ExchangeAI][Runner] start " +
            "task=\(request.task.rawValue) " +
            "rawPromptChars=\(request.prompt.count) " +
            "constitutionChars=\(constitutionText.count) " +
            "styleSupplementChars=\(styleSupplement.count) " +
            "finalPromptChars=\(finalPrompt.count) " +
            "requestedMaxTokens=\(request.maxTokens) " +
            "resolvedMaxTokens=\(resolved.maxTokens) " +
            "outputCap=\(resolved.outputCharCap)"
        )
        print(
            "[ExchangeAI][Runner] promptPreview " +
            "task=\(request.task.rawValue) +++\n" +
            "\(String(finalPrompt.prefix(1200)))\n" +
            "+++ endPromptPreview"
        )
        #endif

        #if DEBUG
        let tBeforeModeGate = CFAbsoluteTimeGetCurrent()
        #endif

        try await AIRuntimeModeGate.shared.acquire(.secretary)

        defer {
            Task {
                await AIRuntimeModeGate.shared.release(.secretary)
            }
        }

        #if DEBUG
        if directReplyPerf {
            let modeSectionMs = Int((CFAbsoluteTimeGetCurrent() - tBeforeModeGate) * 1000)
            let modeElapsedMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[DirectReplyPerf] mode_gate_acquired elapsedMs=\(modeElapsedMs) sectionMs=\(modeSectionMs)"
            )
        }
        #endif

        #if DEBUG
        let tBeforeModelAccess = CFAbsoluteTimeGetCurrent()
        #endif

        let modelURL = try await MainActor.run {
            try ModelStore.shared.beginAccessingModel()
        }

        defer {
            Task { @MainActor in
                ModelStore.shared.stopAccessing(modelURL)
            }
        }

        #if DEBUG
        if directReplyPerf {
            let modelSectionMs = Int((CFAbsoluteTimeGetCurrent() - tBeforeModelAccess) * 1000)
            let modelElapsedMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[DirectReplyPerf] model_access_done elapsedMs=\(modelElapsedMs) sectionMs=\(modelSectionMs)"
            )
        }
        #endif

        LlamaCppBridge.resumeAfterBackground(modelPath: modelURL.path)

        var output = ""
        var chunkCount = 0
        var firstChunkMs: Int?
        var truncatedByCap = false

        #if DEBUG
        let tBeforeStreamGate = CFAbsoluteTimeGetCurrent()
        #endif

        let streamLease = await AIRuntimeStreamGate.shared.acquire(
            label: "secretary.exchange.\(request.task.rawValue)"
        )

        defer {
            Task {
                await AIRuntimeStreamGate.shared.release(streamLease)
            }
        }

        #if DEBUG
        if directReplyPerf {
            perfStreamGateWaitMs = Int((CFAbsoluteTimeGetCurrent() - tBeforeStreamGate) * 1000)
            let streamGateElapsedMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
            print(
                "[DirectReplyPerf] stream_gate_acquired waitMs=\(perfStreamGateWaitMs) elapsedMs=\(streamGateElapsedMs)"
            )
        }
        #endif

        let finalPromptIdentityHash = stableHash(finalPrompt)
        let replay = await resolveSecretaryReplayMode(
            for: request.task,
            finalPromptIdentityHash: finalPromptIdentityHash,
            scaffoldIdentityHash: scaffoldIdentityHash,
            stableScaffoldPrefix: stableScaffoldPrefix
        )
        var attemptPromptMode = replay.promptMode
        var retriedFullReplayAfterMinus8 = false
        var retriedCheckpointFullReplay = false
        var retriedScaffoldFullReplay = false
        var capturePromptEndForStream = replay.capturePromptEndCheckpoint
        var captureScaffoldForStream = replay.captureScaffoldCheckpoint
        var scaffoldPromptPrefixForStream = replay.scaffoldPromptPrefix

        suggestLoop: while true {
            #if DEBUG
            if directReplyPerf {
                let resetLabel: String = {
                    switch attemptPromptMode {
                    case .prefixCachedReplay: return "NONE"
                    case .promptCheckpointRegenerate: return "PROMPT_CHECKPOINT_REGENERATE"
                    case .promptScaffoldCheckpointReplay: return "SCAFFOLD_CHECKPOINT_REPLAY"
                    default: return "FULL"
                    }
                }()
                print(
                    "[DirectReplyPerf] scaffoldCheckpointReplayEnabledEffective=\(replay.scaffoldCheckpointReplayEnabledEffective) " +
                    "scaffoldHash=\(scaffoldIdentityHash) " +
                    "checkpointRegenerateEnabledEffective=\(replay.checkpointRegenerateEnabledEffective) " +
                    "fullPromptHash=\(finalPromptIdentityHash) " +
                    "prefixCachedReplayEnabledEffective=\(replay.prefixCachedReplayEnabledEffective) " +
                    "forceFullBefore=\(replay.forceFullBefore) " +
                    "replayMode=\(attemptPromptMode) " +
                    "resetMode=\(resetLabel)"
                )
            }
            #endif

            do {
                let stream = makeSecretaryFullReplayStream(
                    modelPath: modelURL.path,
                    prompt: finalPrompt,
                    resolved: resolved,
                    task: request.task,
                    reason: "stateless_secretary_job",
                    promptMode: attemptPromptMode,
                    capturePromptEndCheckpoint: capturePromptEndForStream,
                    captureScaffoldCheckpoint: captureScaffoldForStream,
                    scaffoldPromptPrefix: scaffoldPromptPrefixForStream
                )

                #if DEBUG
                if directReplyPerf {
                    let bridgeBeginMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                    print("[DirectReplyPerf] bridge_stream_begin elapsedMs=\(bridgeBeginMs)")
                }
                #endif

                for try await chunk in stream {
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
                        if directReplyPerf, let ttft = firstChunkMs {
                            print(
                                "[DirectReplyPerf] first_chunk elapsedMs=\(ttft) timeToFirstChunkMs=\(ttft) streamGateWaitMs=\(perfStreamGateWaitMs)"
                            )
                        }
                        #endif
                    }

                    output += chunk

                    if output.count >= resolved.outputCharCap {
                        truncatedByCap = true
                        output = String(output.prefix(resolved.outputCharCap))

                        #if DEBUG
                        print(
                            "[ExchangeAI][Runner] output_truncated " +
                            "task=\(request.task.rawValue) " +
                            "cap=\(resolved.outputCharCap)"
                        )
                        #endif

                        break
                    }
                }

                let rawCharsTrimmed = output.trimmingCharacters(in: .whitespacesAndNewlines).count

                #if DEBUG
                if directReplyPerf {
                    let streamDoneMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                    print(
                        "[DirectReplyPerf] stream_done elapsedMs=\(streamDoneMs) rawChars=\(rawCharsTrimmed) rawOutputChars=\(rawCharsTrimmed)"
                    )
                }
                #endif

                let cleaned = cleanModelOutput(output, task: request.task)
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)

                if replay.forceFullBefore {
                    UserDefaults.standard.set(false, forKey: "DirectChatPrefixCachedReplayForceFullNext")
                }

                if retriedFullReplayAfterMinus8 {
                    UserDefaults.standard.set(false, forKey: "DirectChatPrefixCachedReplayForceFullNext")
                }

                if request.task == .directChatReply,
                   attemptPromptMode == .fullReplay,
                   captureScaffoldForStream {
                    await DirectChatPromptCheckpointState.shared.noteSuccessfulScaffoldCheckpointCapture(
                        scaffoldHash: scaffoldIdentityHash
                    )
                }

                if request.task == .directChatReply {
                    #if DEBUG
                    print(
                        "[DirectReplyPerf] runtimePreservedAfterRun=true task=directChatReply replayMode=\(attemptPromptMode)"
                    )
                    #endif
                } else {
                    LlamaCppBridge.invalidateRuntimeState()
                    RuntimeNotifications.postLlamaRuntimeStateInvalidated()
                }

                #if DEBUG
                if directReplyPerf {
                    print(
                        "[DirectReplyPerf] runner_done totalRunnerMs=\(totalMs) timeToFirstChunkMs=\(firstChunkMs ?? -1) streamGateWaitMs=\(perfStreamGateWaitMs) replayMode=\(attemptPromptMode)"
                    )
                }
                print(
                    "[ExchangeAI][Runner] done " +
                    "outcome=success " +
                    "task=\(request.task.rawValue) " +
                    "ttft=\(firstChunkMs ?? -1)ms " +
                    "total=\(totalMs)ms " +
                    "chunks=\(chunkCount) " +
                    "rawChars=\(output.trimmingCharacters(in: .whitespacesAndNewlines).count) " +
                    "cleanChars=\(cleaned.count) " +
                    "truncated=\(truncatedByCap) " +
                    "replayMode=\(attemptPromptMode)"
                )
                print("[ExchangeAI][Runner] full_output_begin task=\(request.task.rawValue)")
                print(cleaned)
                print("[ExchangeAI][Runner] full_output_end task=\(request.task.rawValue)")
                #endif

                return cleaned
            } catch let error as CancellationError {
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                let cooperative = Self.isStatelessSecretaryTask(request.task)
                #if DEBUG
                let cancelOutcome = cooperative ? "cooperativeCancel" : "cancelledInvalidatesRuntime"
                print(
                    "[ExchangeAI][Runner] cancelled " +
                    "outcome=\(cancelOutcome) " +
                    "task=\(request.task.rawValue) " +
                    "cooperative=\(cooperative) " +
                    "chunks=\(chunkCount) " +
                    "ttft=\(firstChunkMs ?? -1)ms " +
                    "total=\(totalMs)ms " +
                    "replayMode=\(attemptPromptMode)"
                )
                #endif
                if cooperative {
                    throw error
                }
                LlamaCppBridge.invalidateRuntimeState()
                RuntimeNotifications.postLlamaRuntimeStateInvalidated()
                throw error
            } catch {
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - totalStart) * 1000)
                let cleanedPartial = cleanModelOutput(output, task: request.task)

                let shouldRetryCheckpoint =
                    request.task == .directChatReply &&
                    attemptPromptMode == .promptCheckpointRegenerate &&
                    !retriedCheckpointFullReplay &&
                    (isLlamaGenerateFailedCode(error, code: -5) || isLlamaGenerateFailedCode(error, code: -8))

                if shouldRetryCheckpoint {
                    let failCode: Int32 = {
                        guard let bridge = error as? LlamaBridgeError else { return -999 }
                        if case .generateFailed(let c) = bridge { return c }
                        return -999
                    }()

                    #if DEBUG
                    print(
                        "[DirectReplyPerf] checkpointRegenerateRetryFullReplay reason=generateFailed code=\(failCode)"
                    )
                    #endif

                    attemptPromptMode = .fullReplay
                    retriedCheckpointFullReplay = true
                    capturePromptEndForStream = replay.baselineFullReplayCapturePromptEndCheckpoint
                    captureScaffoldForStream = replay.baselineFullReplayCaptureScaffoldCheckpoint
                    scaffoldPromptPrefixForStream = replay.baselineFullReplayScaffoldPromptPrefix
                    output = ""
                    chunkCount = 0
                    firstChunkMs = nil
                    truncatedByCap = false

                    continue suggestLoop
                }

                let shouldRetryScaffold =
                    request.task == .directChatReply &&
                    attemptPromptMode == .promptScaffoldCheckpointReplay &&
                    !retriedScaffoldFullReplay &&
                    (isLlamaGenerateFailedCode(error, code: -5) || isLlamaGenerateFailedCode(error, code: -8))

                if shouldRetryScaffold {
                    let failCode: Int32 = {
                        guard let bridge = error as? LlamaBridgeError else { return -999 }
                        if case .generateFailed(let c) = bridge { return c }
                        return -999
                    }()

                    #if DEBUG
                    print(
                        "[DirectReplyPerf] scaffoldCheckpointRetryFullReplay reason=generateFailed code=\(failCode)"
                    )
                    #endif

                    attemptPromptMode = .fullReplay
                    retriedScaffoldFullReplay = true
                    capturePromptEndForStream = replay.baselineFullReplayCapturePromptEndCheckpoint
                    captureScaffoldForStream = replay.baselineFullReplayCaptureScaffoldCheckpoint
                    scaffoldPromptPrefixForStream = replay.baselineFullReplayScaffoldPromptPrefix
                    output = ""
                    chunkCount = 0
                    firstChunkMs = nil
                    truncatedByCap = false

                    continue suggestLoop
                }

                let shouldRetryMinus8 =
                    request.task == .directChatReply &&
                    attemptPromptMode == .prefixCachedReplay &&
                    !retriedFullReplayAfterMinus8 &&
                    isLlamaGenerateFailedCode(error, code: -8)

                if shouldRetryMinus8 {
                    #if DEBUG
                    print("[DirectReplyPerf] prefixCachedReplayRetryFullReplay reason=generateFailed_-8")
                    #endif

                    UserDefaults.standard.set(true, forKey: "DirectChatPrefixCachedReplayForceFullNext")

                    attemptPromptMode = .fullReplay
                    retriedFullReplayAfterMinus8 = true
                    capturePromptEndForStream = replay.baselineFullReplayCapturePromptEndCheckpoint
                    captureScaffoldForStream = replay.baselineFullReplayCaptureScaffoldCheckpoint
                    scaffoldPromptPrefixForStream = replay.baselineFullReplayScaffoldPromptPrefix
                    output = ""
                    chunkCount = 0
                    firstChunkMs = nil
                    truncatedByCap = false

                    continue suggestLoop
                }

                if attemptPromptMode == .prefixCachedReplay {
                    UserDefaults.standard.set(true, forKey: "DirectChatPrefixCachedReplayForceFullNext")
                }

                LlamaCppBridge.invalidateRuntimeState()
                RuntimeNotifications.postLlamaRuntimeStateInvalidated()

                #if DEBUG
                if directReplyPerf {
                    print(
                        "[DirectReplyPerf] runner_failed totalRunnerMs=\(totalMs) timeToFirstChunkMs=\(firstChunkMs ?? -1) streamGateWaitMs=\(perfStreamGateWaitMs) replayMode=\(attemptPromptMode) error=\(String(describing: error))"
                    )
                }
                print(
                    "[ExchangeAI][Runner] failed " +
                    "outcome=nativeHardFailure " +
                    "task=\(request.task.rawValue) " +
                    "ttft=\(firstChunkMs ?? -1)ms " +
                    "total=\(totalMs)ms " +
                    "chunks=\(chunkCount) " +
                    "error=\(error) " +
                    "replayMode=\(attemptPromptMode)"
                )
                if !cleanedPartial.isEmpty {
                    print("[ExchangeAI][Runner] partial_output_begin task=\(request.task.rawValue)")
                    print(cleanedPartial)
                    print("[ExchangeAI][Runner] partial_output_end task=\(request.task.rawValue)")
                }
                #endif

                throw error
            }
        }
    }
}

// MARK: - Stateless secretary cancellation

private extension LlamaExchangeModelRunner {
    /// JSON / classification / posture / compare tasks only; excludes drafting and direct chat.
    static func isStatelessSecretaryTask(_ task: ExchangeIntelligenceModelRunRequest.Task) -> Bool {
        switch task {
        case .interpretation, .searchIntentExtraction, .providerInboundIntentExtraction, .fastClassification,
             .posture, .inboundInquiry, .requesterMatchCompare, .providerInquiryCompare:
            return true
        case .directChatReply, .draft, .requesterDraft, .providerDraft, .neutralRewrite:
            return false
        }
    }
}

// MARK: - Direct Chat prefix-cached replay

private extension LlamaExchangeModelRunner {
    struct SecretaryReplaySelection {
        let promptMode: LlamaStreamConfig.PromptMode
        let forceFullBefore: Bool
        let prefixCachedReplayEnabledEffective: Bool
        let checkpointRegenerateEnabledEffective: Bool
        let scaffoldCheckpointReplayEnabledEffective: Bool
        let capturePromptEndCheckpoint: Bool
        let captureScaffoldCheckpoint: Bool
        let scaffoldPromptPrefix: String?
        /// Capture flags for forced `.fullReplay` after scaffold / checkpoint native misses.
        let baselineFullReplayCapturePromptEndCheckpoint: Bool
        let baselineFullReplayCaptureScaffoldCheckpoint: Bool
        let baselineFullReplayScaffoldPromptPrefix: String?
    }

    func resolveDirectChatPromptCheckpointRegenerateEnabled() -> Bool {
        #if DEBUG
        let defaultEnabled = true
        #else
        let defaultEnabled = false
        #endif

        let defaults = UserDefaults.standard
        let key = "DirectChatPromptCheckpointRegenerateEnabled"
        let wasSet = defaults.object(forKey: key) != nil
        return wasSet ? defaults.bool(forKey: key) : defaultEnabled
    }

    func resolveDirectChatScaffoldCheckpointReplayEnabled() -> Bool {
        #if DEBUG
        let defaultEnabled = true
        #else
        let defaultEnabled = false
        #endif

        let defaults = UserDefaults.standard
        let key = "DirectChatScaffoldCheckpointReplayEnabled"
        let wasSet = defaults.object(forKey: key) != nil
        return wasSet ? defaults.bool(forKey: key) : defaultEnabled
    }

    func isLlamaGenerateFailedCode(_ error: Error, code: Int32) -> Bool {
        guard let bridge = error as? LlamaBridgeError else { return false }

        if case .generateFailed(let c) = bridge {
            return c == code
        }

        return false
    }

    func resolveSecretaryReplayMode(
        for task: ExchangeIntelligenceModelRunRequest.Task,
        finalPromptIdentityHash: String,
        scaffoldIdentityHash: String,
        stableScaffoldPrefix: String
    ) async -> SecretaryReplaySelection {
        let baselineCapturePrompt = resolveDirectChatPromptCheckpointRegenerateEnabled()
        let baselineCaptureScaffold =
            resolveDirectChatScaffoldCheckpointReplayEnabled() && !stableScaffoldPrefix.isEmpty
        let baselineScaffoldPrefix: String? = baselineCaptureScaffold ? stableScaffoldPrefix : nil

        guard task == .directChatReply else {
            return SecretaryReplaySelection(
                promptMode: .fullReplay,
                forceFullBefore: false,
                prefixCachedReplayEnabledEffective: false,
                checkpointRegenerateEnabledEffective: false,
                scaffoldCheckpointReplayEnabledEffective: false,
                capturePromptEndCheckpoint: false,
                captureScaffoldCheckpoint: false,
                scaffoldPromptPrefix: nil,
                baselineFullReplayCapturePromptEndCheckpoint: false,
                baselineFullReplayCaptureScaffoldCheckpoint: false,
                baselineFullReplayScaffoldPromptPrefix: nil
            )
        }

        let checkpointEffective = resolveDirectChatPromptCheckpointRegenerateEnabled()
        let scaffoldReplayEffective = resolveDirectChatScaffoldCheckpointReplayEnabled()

        let mode = await DirectChatPromptCheckpointState.shared.selectReplayMode(
            promptCheckpointEnabled: checkpointEffective,
            scaffoldReplayEnabled: scaffoldReplayEffective,
            fullPromptHash: finalPromptIdentityHash,
            scaffoldHash: scaffoldIdentityHash
        )

        await DirectChatPromptCheckpointState.shared.recordSelection(fullPromptHash: finalPromptIdentityHash)

        switch mode {
        case .promptCheckpointRegenerate:
            return SecretaryReplaySelection(
                promptMode: .promptCheckpointRegenerate,
                forceFullBefore: false,
                prefixCachedReplayEnabledEffective: false,
                checkpointRegenerateEnabledEffective: checkpointEffective,
                scaffoldCheckpointReplayEnabledEffective: scaffoldReplayEffective,
                capturePromptEndCheckpoint: false,
                captureScaffoldCheckpoint: false,
                scaffoldPromptPrefix: nil,
                baselineFullReplayCapturePromptEndCheckpoint: baselineCapturePrompt,
                baselineFullReplayCaptureScaffoldCheckpoint: baselineCaptureScaffold,
                baselineFullReplayScaffoldPromptPrefix: baselineScaffoldPrefix
            )

        case .promptScaffoldCheckpointReplay:
            return SecretaryReplaySelection(
                promptMode: .promptScaffoldCheckpointReplay,
                forceFullBefore: false,
                prefixCachedReplayEnabledEffective: false,
                checkpointRegenerateEnabledEffective: checkpointEffective,
                scaffoldCheckpointReplayEnabledEffective: scaffoldReplayEffective,
                capturePromptEndCheckpoint: baselineCapturePrompt,
                captureScaffoldCheckpoint: false,
                scaffoldPromptPrefix: stableScaffoldPrefix,
                baselineFullReplayCapturePromptEndCheckpoint: baselineCapturePrompt,
                baselineFullReplayCaptureScaffoldCheckpoint: baselineCaptureScaffold,
                baselineFullReplayScaffoldPromptPrefix: baselineScaffoldPrefix
            )

        case .fullReplay:
            break

        default:
            break
        }

        let prefixDefaultEnabled = false

        let defaults = UserDefaults.standard

        let enabledWasSet = defaults.object(forKey: "DirectChatPrefixCachedReplayEnabled") != nil
        let prefixEnabled = enabledWasSet
            ? defaults.bool(forKey: "DirectChatPrefixCachedReplayEnabled")
            : prefixDefaultEnabled

        let forceWasSet = defaults.object(forKey: "DirectChatPrefixCachedReplayForceFullNext") != nil
        let forceFullBefore: Bool = {
            if prefixEnabled && !forceWasSet {
                return true
            }

            return defaults.bool(forKey: "DirectChatPrefixCachedReplayForceFullNext")
        }()

        let promptMode: LlamaStreamConfig.PromptMode = prefixEnabled && !forceFullBefore
            ? .prefixCachedReplay
            : .fullReplay

        let capturePrompt = promptMode == .fullReplay && baselineCapturePrompt
        let captureScaffold = promptMode == .fullReplay && baselineCaptureScaffold

        return SecretaryReplaySelection(
            promptMode: promptMode,
            forceFullBefore: forceFullBefore,
            prefixCachedReplayEnabledEffective: prefixEnabled,
            checkpointRegenerateEnabledEffective: checkpointEffective,
            scaffoldCheckpointReplayEnabledEffective: scaffoldReplayEffective,
            capturePromptEndCheckpoint: capturePrompt,
            captureScaffoldCheckpoint: captureScaffold,
            scaffoldPromptPrefix: captureScaffold ? stableScaffoldPrefix : nil,
            baselineFullReplayCapturePromptEndCheckpoint: baselineCapturePrompt,
            baselineFullReplayCaptureScaffoldCheckpoint: baselineCaptureScaffold,
            baselineFullReplayScaffoldPromptPrefix: baselineScaffoldPrefix
        )
    }

    func makeSecretaryFullReplayStream(
        modelPath: String,
        prompt: String,
        resolved: TaskPolicy,
        task: ExchangeIntelligenceModelRunRequest.Task,
        reason: String,
        promptMode: LlamaStreamConfig.PromptMode,
        capturePromptEndCheckpoint: Bool,
        captureScaffoldCheckpoint: Bool,
        scaffoldPromptPrefix: String?
    ) -> AsyncThrowingStream<String, Error> {
        var cfg = LlamaStreamConfig(
            modelPath: modelPath,
            prompt: prompt,
            maxTokens: Int32(resolved.maxTokens),
            seqId: 0,
            promptMode: promptMode
        )

        cfg.capturePromptEndCheckpoint = capturePromptEndCheckpoint
        cfg.captureScaffoldCheckpoint = captureScaffoldCheckpoint
        cfg.scaffoldPromptPrefix = scaffoldPromptPrefix

        cfg.nCtx = 2048
        cfg.nThreads = 4
        cfg.nBatch = 256

        if task == .directChatReply {
            if promptMode == .promptCheckpointRegenerate {
                cfg.temperature = 0.7
            } else {
                cfg.temperature = 0.6
            }
        }
        if task == .searchIntentExtraction {
            cfg.temperature = 0.1
            cfg.topP = 0.9
        }

        #if DEBUG
        print(
            "[ExchangeAI][Runner][stateless] stream " +
            "task=\(task.rawValue) " +
            "reason=\(reason) " +
            "replayMode=\(promptMode) " +
            "promptChars=\(prompt.count) " +
            "maxTokens=\(resolved.maxTokens)"
        )
        if task == .directChatReply {
            print(
                "[DirectReplyPerf] sampling task=\(task.rawValue) replayMode=\(promptMode) " +
                "temp=\(cfg.temperature) topK=\(cfg.topK) topP=\(cfg.topP) seed=\(cfg.seed)"
            )
        }
        #endif

        return LlamaCppBridge.stream(cfg)
    }
}

// MARK: - Debug prompt audit

private extension LlamaExchangeModelRunner {
    #if DEBUG
    private static let secretaryPromptAuditSHA256DefaultsKey = "SecretaryPromptAuditLogFullPromptSHA256Enabled"

    func debugSecretaryPromptAuditExchange(
        finalPrompt: String,
        request: ExchangeIntelligenceModelRunRequest,
        constitutionText: String,
        styleSupplement: String
    ) {
        let trimmed = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let sys = exchangeSystemPrompt(constitutionText: constitutionText, task: request.task)

        let taskPayload: String = {
            if trimmed.isEmpty {
                let sup = styleSupplement.trimmingCharacters(in: .whitespacesAndNewlines)
                let emptyUserBody = "Task:\nempty\n\nTask payload:\n{}"

                if sup.isEmpty {
                    return qwenTurn(role: "user", content: emptyUserBody)
                }

                return qwenTurn(role: "user", content: sup + "\n\n---\n\n" + emptyUserBody)
            }

            return composedUserTaskPayload(
                rawPrompt: trimmed,
                task: request.task,
                representationSupplement: styleSupplement
            )
        }()

        let suffix = qwenAssistantGenerationPrefix(task: request.task)
        let systemChars = sys.count
        let payloadChars = taskPayload.count + suffix.count

        let sections = Self.secretaryPromptAuditSectionMarkers(finalPrompt)

        let identitySectionsPresent = finalPrompt.contains("## BASE")
            || finalPrompt.contains("## ADAPT")
            || finalPrompt.contains("## PROLOGUE")
            || finalPrompt.contains("### SUM")

        let styleSectionsPresent = finalPrompt.contains(ExchangeSecretaryPromptInstructionBlocks.secretaryStyleGuideMarker)
            || finalPrompt.contains("SECRETARY_STYLE_FROM_USER")
            || finalPrompt.contains("Secretary style profile")

        let factSectionsPresent = finalPrompt.contains("=== PROFILE_FACTS ===")
            || finalPrompt.contains("=== OFFER_FACTS ===")
            || finalPrompt.contains("useful_commercial:")

        let memorySectionsPresent = finalPrompt.contains("=== OPERATING_MEMORY_EXCERPT ===")
            || finalPrompt.contains("[Relevant Context]")

        let companionSectionsPresent = identitySectionsPresent

        let secretarySectionsPresent = finalPrompt.contains("You are the local Exchange intelligence worker")
            || finalPrompt.contains("Task:\n\(request.task.rawValue)")
            || finalPrompt.contains("THREAD_SURFACE_ROUTING")
            || styleSectionsPresent

        var line =
            "[SecretaryPromptAudit] mode=secretary promptKind=\(request.task.rawValue) " +
            "systemChars=\(systemChars) payloadChars=\(payloadChars) sections=\(sections) " +
            "identitySectionsPresent=\(identitySectionsPresent) styleSectionsPresent=\(styleSectionsPresent) " +
            "factSectionsPresent=\(factSectionsPresent) memorySectionsPresent=\(memorySectionsPresent) " +
            "companionSectionsPresent=\(companionSectionsPresent) secretarySectionsPresent=\(secretarySectionsPresent)"

        if UserDefaults.standard.bool(forKey: Self.secretaryPromptAuditSHA256DefaultsKey) {
            let digest = SHA256.hash(data: Data(finalPrompt.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            line += " promptSHA256=\(hex)"
        }

        print(line)

        let hasUserConstitution = !constitutionText.isEmpty
        let hasStyleGuide = !styleSupplement.isEmpty
            || finalPrompt.contains(ExchangeSecretaryPromptInstructionBlocks.secretaryStyleGuideMarker)

        print(
            "[SecretaryInstructionInjection] task=\(request.task.rawValue) " +
            "hasUserConstitution=\(hasUserConstitution) hasStyleGuide=\(hasStyleGuide) " +
            "duplicated=false constitutionChars=\(constitutionText.count) styleChars=\(styleSupplement.count)"
        )

        if request.task == .providerInquiryCompare {
            let hasTypedPayload = request.prompt.contains("Secretary style profile (typed defaults")
            print(
                "[SecretaryStyleInjection] task=providerInquiryCompare " +
                "hasUserConstitution=\(hasUserConstitution) " +
                "hasTypedStyleInPayload=\(hasTypedPayload) " +
                "hasStyleSupplement=\(!styleSupplement.isEmpty) " +
                "companionStylePresent=false duplicated=false"
            )
        }
    }

    static func secretaryPromptAuditSectionMarkers(_ text: String) -> String {
        var tags: [String] = []

        if text.contains(ExchangeSecretaryPromptInstructionBlocks.searchIntentExtractionJSONMarker) {
            tags.append("SEARCH_INTENT_JSON_TASK")
        }
        if text.contains(ExchangeSecretaryPromptInstructionBlocks.hiddenExchangeSafetyMarker) {
            tags.append("HIDDEN_EXCHANGE_SAFETY")
        }
        if text.contains(ExchangeSecretaryPromptInstructionBlocks.directChatSafetyMarker) {
            tags.append("DIRECT_CHAT_SAFETY")
        }
        if text.contains(ExchangeSecretaryPromptInstructionBlocks.userSecretaryConstitutionMarker) {
            tags.append("USER_SECRETARY_CONSTITUTION")
        }
        if text.contains(ExchangeSecretaryPromptInstructionBlocks.providerTaskPostureMarker) {
            tags.append("PROVIDER_TASK_POSTURE")
        }
        if text.contains(ExchangeSecretaryPromptInstructionBlocks.requesterTaskPostureMarker) {
            tags.append("REQUESTER_TASK_POSTURE")
        }
        if text.contains(ExchangeSecretaryPromptInstructionBlocks.providerDraftTaskPostureMarker) {
            tags.append("PROVIDER_DRAFT_TASK_POSTURE")
        }
        if text.contains(ExchangeSecretaryPromptInstructionBlocks.neutralRewriteTaskPostureMarker) {
            tags.append("NEUTRAL_REWRITE_TASK_POSTURE")
        }
        if text.contains(ExchangeSecretaryPromptInstructionBlocks.neutralJSONTaskPostureMarker) {
            tags.append("NEUTRAL_JSON_TASK_POSTURE")
        }
        if text.contains("THREAD_SURFACE_ROUTING") {
            tags.append("THREAD_SURFACE_ROUTING")
        }
        if text.contains("STRUCTURED_SELLER_SURFACES") {
            tags.append("STRUCTURED_SELLER_SURFACES")
        }
        if text.contains(ExchangeSecretaryPromptInstructionBlocks.secretaryStyleGuideMarker) {
            tags.append("SECRETARY_STYLE_GUIDE")
        }
        if text.contains("SECRETARY_STYLE_FROM_USER") {
            tags.append("SECRETARY_STYLE_FROM_USER")
        }
        if text.contains("Task:") {
            tags.append("Task")
        }
        if text.contains("## BASE") {
            tags.append("BASE")
        }
        if text.contains("## ADAPT") {
            tags.append("ADAPT")
        }
        if text.contains("## PROLOGUE") {
            tags.append("PROLOGUE")
        }
        if text.contains("### SUM") {
            tags.append("SUM")
        }
        if text.contains("[Relevant Context]") {
            tags.append("Relevant_Context")
        }

        return tags.joined(separator: ",")
    }
    #endif
}

// MARK: - Task policy / prompt construction

private extension LlamaExchangeModelRunner {
    struct TaskPolicy: Sendable {
        let maxTokens: Int
        let outputCharCap: Int
    }
    
    enum ExchangePromptFamily {
        case qwen
        case gemma
    }
    
    func currentPromptFamilyForExchange() -> ExchangePromptFamily {
        return .qwen
    }
    
    func resolveTaskPolicy(
        for request: ExchangeIntelligenceModelRunRequest
    ) -> TaskPolicy {
        switch request.task {
        case .fastClassification:
            return TaskPolicy(
                maxTokens: minPositive(request.maxTokens, fallback: 48),
                outputCharCap: 1000
            )
            
        case .interpretation:
            return TaskPolicy(
                maxTokens: minPositive(request.maxTokens, fallback: 420),
                outputCharCap: 12000
            )
            
        case .searchIntentExtraction:
            return TaskPolicy(
                maxTokens: minPositive(
                    request.maxTokens,
                    fallback: ExchangeIntelligenceTaskTokenBudget.searchIntentExtractionMaxTokens
                ),
                outputCharCap: 4000
            )
            
        case .posture:
            return TaskPolicy(
                maxTokens: minPositive(request.maxTokens, fallback: 220),
                outputCharCap: 4000
            )
            
        case .draft,
                .requesterDraft,
                .providerDraft,
                .neutralRewrite:
            return TaskPolicy(
                maxTokens: minPositive(request.maxTokens, fallback: 420),
                outputCharCap: 10000
            )
            
        case .directChatReply:
            return TaskPolicy(
                maxTokens: minPositive(request.maxTokens, fallback: 420),
                outputCharCap: 10000
            )
            
        case .inboundInquiry:
            return TaskPolicy(
                maxTokens: minPositive(request.maxTokens, fallback: 280),
                outputCharCap: 6000
            )
            
        case .requesterMatchCompare:
            return TaskPolicy(
                maxTokens: minPositive(request.maxTokens, fallback: 420),
                outputCharCap: 8000
            )
            
        case .providerInquiryCompare:
            return TaskPolicy(
                maxTokens: minPositive(request.maxTokens, fallback: 420),
                outputCharCap: 8000
            )

        case .providerInboundIntentExtraction:
            return TaskPolicy(
                maxTokens: minPositive(
                    request.maxTokens,
                    fallback: ExchangeIntelligenceTaskTokenBudget.providerInboundIntentExtractionMaxTokens
                ),
                outputCharCap: 3500
            )
        }
    }
    
    func buildPrompt(
        rawPrompt: String,
        task: ExchangeIntelligenceModelRunRequest.Task,
        constitutionText: String,
        representationSupplement: String
    ) -> String {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return emptyPrompt(
                constitutionText: constitutionText,
                task: task,
                representationSupplement: representationSupplement
            )
        }
        
        switch currentPromptFamilyForExchange() {
        case .qwen:
            var out = ""
            out.reserveCapacity(trimmed.count + constitutionText.count + representationSupplement.count + 1200)
            out += exchangeSystemPrompt(constitutionText: constitutionText, task: task)
            out += composedUserTaskPayload(
                rawPrompt: trimmed,
                task: task,
                representationSupplement: representationSupplement
            )
            out += qwenAssistantGenerationPrefix(task: task)
            return out
            
        case .gemma:
            var out = ""
            out.reserveCapacity(trimmed.count + constitutionText.count + representationSupplement.count + 1200)
            out += exchangeSystemPrompt(constitutionText: constitutionText, task: task)
            out += composedUserTaskPayload(
                rawPrompt: trimmed,
                task: task,
                representationSupplement: representationSupplement
            )
            out += assistantGenerationPrefix(task: task)
            return out
        }
    }
    
    func emptyPrompt(
        constitutionText: String,
        task: ExchangeIntelligenceModelRunRequest.Task,
        representationSupplement: String
    ) -> String {
        let supplement = representationSupplement.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch currentPromptFamilyForExchange() {
        case .qwen:
            var out = ""
            out += exchangeSystemPrompt(constitutionText: constitutionText, task: task)
            
            let emptyUserBody = "Task:\nempty\n\nTask payload:\n{}"
            
            if supplement.isEmpty {
                out += qwenTurn(role: "user", content: emptyUserBody)
            } else {
                out += qwenTurn(role: "user", content: supplement + "\n\n---\n\n" + emptyUserBody)
            }
            
            out += qwenAssistantGenerationPrefix(task: task)
            return out
            
        case .gemma:
            var out = ""
            out += exchangeSystemPrompt(constitutionText: constitutionText, task: task)
            
            let emptyUserBody = """
            Task:
            empty
            
            Task payload:
            {}
            """
            
            if supplement.isEmpty {
                out += """
                <start_of_turn>user
                \(emptyUserBody.trimmingCharacters(in: .whitespacesAndNewlines))
                <end_of_turn>
                """
            } else {
                out += """
                <start_of_turn>user
                \(supplement)
                
                ---
                
                \(emptyUserBody.trimmingCharacters(in: .whitespacesAndNewlines))
                <end_of_turn>
                """
            }
            
            out += assistantGenerationPrefix(task: task)
            return out
        }
    }
    
    func exchangeSystemPrompt(
        constitutionText: String,
        task: ExchangeIntelligenceModelRunRequest.Task
    ) -> String {
        let scaffold = ExchangeSecretaryPromptInstructionBlocks.exchangeRunnerInstructionScaffold(
            constitutionText: constitutionText.isEmpty ? nil : constitutionText,
            task: task
        )
        
        switch currentPromptFamilyForExchange() {
        case .qwen:
            var content: String
            
            if task == .searchIntentExtraction {
                content = """
                JSON only. Follow the user task payload exactly (one flat object, all keys).
                No markdown, no explanation, no trailing text.
                """
            } else if task == .directChatReply {
                content = """
                Return only valid JSON for the task schema.
                No markdown, no explanation, no trailing text.
                Follow the task payload.
                """
            } else {
                content = """
                You are the local Exchange intelligence worker.
                
                You perform narrow structured-output tasks for a private AI secretary system.
                
                Global rules:
                - Return only valid JSON requested by the current task.
                - Do not reveal reasoning.
                - Do not add markdown.
                - Do not add explanation.
                - Do not add trailing text.
                - Follow the current task payload exactly.
                
                Instruction layering:
                - System messages may include hidden Exchange safety rules and the user's secretary constitution; safety and policy always win over constitution.
                - The user task payload may include a labeled style guide; style affects wording, rhythm, warmth, and personality only — not facts, authority, disclosure, or commitments.
                """
            }
            
            if !scaffold.isEmpty {
                content += "\n\n\(scaffold)"
            }
            
            return qwenTurn(role: "system", content: content)
            
        case .gemma:
            var out: String
            
            if task == .searchIntentExtraction {
                out = """
                <start_of_turn>user
                [Instruction Context]
                JSON only. Follow the user task payload exactly (one flat object, all keys).
                No markdown, no explanation, no trailing text.
                """
            } else if task == .directChatReply {
                out = """
                <start_of_turn>user
                [Instruction Context]
                Return only valid JSON for the task schema.
                No markdown, no explanation, no trailing text.
                Follow the task payload.
                """
            } else {
                out = """
                <start_of_turn>user
                [Instruction Context]
                You are the local Exchange intelligence worker.
                
                You perform narrow structured-output tasks for a private AI secretary system.
                
                Global rules:
                - Return only valid JSON requested by the current task.
                - Do not reveal reasoning.
                - Do not add markdown.
                - Do not add explanation.
                - Do not add trailing text.
                - Follow the current task payload exactly.
                
                Instruction layering:
                - System messages may include hidden Exchange safety rules and the user's secretary constitution; safety and policy always win over constitution.
                - The user task payload may include a labeled style guide; style affects wording, rhythm, warmth, and personality only — not facts, authority, disclosure, or commitments.
                """
            }
            
            if !scaffold.isEmpty {
                out += "\n\n\(scaffold)"
            }
            
            out += """
            
            <end_of_turn>
            <start_of_turn>model
            Understood.
            <end_of_turn>
            """
            
            return out
        }
    }
    
    /// Stable Direct Chat prefix: ChatML system turn + Exchange runner scaffold for `.directChatReply` only (no user payload).
    func directChatStableScaffoldPrefix(constitutionText: String) -> String {
        exchangeSystemPrompt(constitutionText: constitutionText, task: .directChatReply)
    }
    
    func composedUserTaskPayload(
        rawPrompt: String,
        task: ExchangeIntelligenceModelRunRequest.Task,
        representationSupplement: String
    ) -> String {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let supplement = representationSupplement.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let merged: String = {
            if supplement.isEmpty {
                return trimmed
            }
            
            if trimmed.isEmpty {
                return supplement
            }
            
            return supplement + "\n\n---\n\n" + trimmed
        }()
        
        return buildSecretaryTaskPayload(rawPrompt: merged, task: task)
    }
    
    func buildSecretaryTaskPayload(
        rawPrompt: String,
        task: ExchangeIntelligenceModelRunRequest.Task
    ) -> String {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let taskName: String = {
            switch task {
            case .fastClassification:
                return "fastClassification"
            case .interpretation:
                return "interpretation"
            case .searchIntentExtraction:
                return "searchIntentExtraction"
            case .posture:
                return "posture"
            case .draft:
                return "draft"
            case .requesterDraft:
                return "requesterDraft"
            case .providerDraft:
                return "providerDraft"
            case .neutralRewrite:
                return "neutralRewrite"
            case .directChatReply:
                return "directChatReply"
            case .inboundInquiry:
                return "inboundInquiry"
            case .requesterMatchCompare:
                return "requesterMatchCompare"
            case .providerInquiryCompare:
                return "providerInquiryCompare"
            case .providerInboundIntentExtraction:
                return "providerInboundIntentExtraction"
            }
        }()
        
        let payload = """
        Task:
        \(taskName)
        
        Task payload:
        \(trimmed)
        """
        
        switch currentPromptFamilyForExchange() {
        case .qwen:
            return qwenTurn(role: "user", content: payload)
            
        case .gemma:
            return """
            <start_of_turn>user
            \(payload.trimmingCharacters(in: .whitespacesAndNewlines))
            <end_of_turn>
            """
        }
    }
    
    func assistantGenerationPrefix(task: ExchangeIntelligenceModelRunRequest.Task) -> String {
        switch currentPromptFamilyForExchange() {
        case .qwen:
            return qwenAssistantGenerationPrefix(task: task)
            
        case .gemma:
            return "<start_of_turn>model\n"
        }
    }
    
    func qwenTurn(role: String, content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return "<|im_start|>\(role)\n\(trimmed)\n<|im_end|>\n"
    }
    
    func qwenAssistantGenerationPrefix(task: ExchangeIntelligenceModelRunRequest.Task? = nil) -> String {
        let base = "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        return base
    }
}

// MARK: - Cleanup / parsing helpers

private extension LlamaExchangeModelRunner {
    func cleanConstitutionText(_ raw: String?) -> String {
        clipCollapsedWhitespace(raw, maxCharacters: 3000)
    }

    func cleanStyleSupplementText(_ raw: String?) -> String {
        clipCollapsedWhitespace(raw, maxCharacters: 1400)
    }

    func clipCollapsedWhitespace(_ raw: String?, maxCharacters: Int) -> String {
        let trimmed = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmed.isEmpty else {
            return ""
        }

        let collapsed = trimmed
            .replacingOccurrences(
                of: #"\n{3,}"#,
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if collapsed.count <= maxCharacters {
            return collapsed
        }

        return String(collapsed.prefix(maxCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanModelOutput(
        _ raw: String,
        task: ExchangeIntelligenceModelRunRequest.Task
    ) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        value = value.replacingOccurrences(
            of: #"(?is)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )

        value = value.replacingOccurrences(
            of: #"(?is)<\|im_start\|>assistant\s*"#,
            with: "",
            options: .regularExpression
        )

        if let start = value.range(of: "<think>", options: [.caseInsensitive]) {
            if let end = value.range(
                of: "</think>",
                options: [.caseInsensitive],
                range: start.upperBound..<value.endIndex
            ) {
                value.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                value.removeSubrange(value.startIndex..<start.upperBound)
            }
        }

        value = value
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let stopMarkers = [
            "<|im_end|>",
            "<|endoftext|>",
            "<|im_start|>",
            "<|vision_pad|>"
        ]

        for marker in stopMarkers {
            if let range = value.range(of: marker, options: [.caseInsensitive]) {
                value = String(value[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        value = stripMarkdownCodeFence(value)

        switch task {
        case .searchIntentExtraction:
            let beforeRepair = value
            let (repaired, didRepair) = SearchIntentExtractionOutputPrefixRepair.reconstructJSONIfNeeded(value)
            #if DEBUG
            if didRepair {
                print(
                    "[ExchangeAI][Runner][searchIntentPrefixRepair] applied=true " +
                    "beforeChars=\(beforeRepair.trimmingCharacters(in: .whitespacesAndNewlines).count) " +
                    "afterChars=\(repaired.trimmingCharacters(in: .whitespacesAndNewlines).count)"
                )
            }
            #endif
            value = repaired.trimmingCharacters(in: .whitespacesAndNewlines)

            if let object = extractBalancedJSON(from: value, open: "{", close: "}") {
                return object
            }

            return value.trimmingCharacters(in: .whitespacesAndNewlines)

        case .providerInboundIntentExtraction,
             .fastClassification,
             .interpretation,
             .posture,
             .draft,
             .requesterDraft,
             .providerDraft,
             .neutralRewrite,
             .directChatReply,
             .inboundInquiry,
             .requesterMatchCompare,
             .providerInquiryCompare:
            if let json = extractLikelyJSON(from: value) {
                return json
            }

            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func stripMarkdownCodeFence(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("```") {
            if let firstNewline = value.firstIndex(of: "\n") {
                value = String(value[value.index(after: firstNewline)...])
            }

            if let closingRange = value.range(of: "```", options: .backwards) {
                value = String(value[..<closingRange.lowerBound])
            }
        }

        if value.lowercased().hasPrefix("json\n") {
            value = String(value.dropFirst(5))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractLikelyJSON(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }

        if trimmed.first == "[", trimmed.last == "]" {
            return trimmed
        }

        if let object = extractBalancedJSON(from: trimmed, open: "{", close: "}") {
            return object
        }

        if let array = extractBalancedJSON(from: trimmed, open: "[", close: "]") {
            return array
        }

        return nil
    }

    func extractBalancedJSON(
        from text: String,
        open: Character,
        close: Character
    ) -> String? {
        guard let startIndex = text.firstIndex(of: open) else {
            return nil
        }

        var depth = 0
        var inString = false
        var isEscaped = false
        var index = startIndex

        while index < text.endIndex {
            let ch = text[index]

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
                } else if ch == open {
                    depth += 1
                } else if ch == close {
                    depth -= 1

                    if depth == 0 {
                        return String(text[startIndex...index])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    func minPositive(_ value: Int, fallback: Int) -> Int {
        value > 0 ? min(value, fallback) : fallback
    }

    func stableHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Task-gated secretary layering (constitution / representation supplement)

private enum SecretaryPromptLayeringGate {
    /// User constitution from storage — off for lean JSON/tool tasks.
    nonisolated static func shouldInjectConstitution(for task: ExchangeIntelligenceModelRunRequest.Task) -> Bool {
        switch task {
        case .fastClassification,
             .interpretation,
             .searchIntentExtraction,
             .providerInboundIntentExtraction,
             .posture,
             .directChatReply:
            return false
        case .requesterDraft,
             .providerDraft,
             .neutralRewrite,
             .requesterMatchCompare,
             .providerInquiryCompare,
             .inboundInquiry,
             .draft:
            return true
        }
    }

    /// Request `representationSupplement` merge in runner — same policy as constitution.
    nonisolated static func shouldInjectRepresentationSupplement(for task: ExchangeIntelligenceModelRunRequest.Task) -> Bool {
        switch task {
        case .fastClassification,
             .interpretation,
             .searchIntentExtraction,
             .providerInboundIntentExtraction,
             .posture,
             .directChatReply:
            return false
        case .requesterDraft,
             .providerDraft,
             .neutralRewrite,
             .requesterMatchCompare,
             .providerInquiryCompare,
             .inboundInquiry,
             .draft:
            return true
        }
    }
}
