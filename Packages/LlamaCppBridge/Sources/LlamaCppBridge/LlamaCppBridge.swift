import Foundation
import LlamaCppBridgeC
import os.log
import Darwin

// MARK: - Logging

private let llamaOSLog = OSLog(subsystem: "com.anum", category: "LlamaCppBridge")

@inline(__always) private func llamaDebug(_ message: String) {
#if DEBUG
    os_log("%{public}@", log: llamaOSLog, type: .debug, message)
#endif
}

@inline(__always) private func llamaError(_ message: String) {
    os_log("%{public}@", log: llamaOSLog, type: .error, message)
}

#if DEBUG
@inline(__always)
private func llamaPerf(_ message: @autoclosure () -> String) {
    os_log("%{public}@", log: llamaOSLog, type: .debug, "[PERF] \(message())")
}
#else
@inline(__always)
private func llamaPerf(_ message: @autoclosure () -> String) { }
#endif

// MARK: - UTF-8 streaming decode helpers

@inline(__always)
private func utf8ValidPrefixLen(_ bytes: [UInt8]) -> (validPrefixLen: Int, invalidPos: Int?) {
    var i = 0
    var lastGood = 0

    @inline(__always) func isCont(_ b: UInt8) -> Bool { (b & 0b1100_0000) == 0b1000_0000 }

    while i < bytes.count {
        let b0 = bytes[i]
        if b0 <= 0x7F {
            i += 1
            lastGood = i
            continue
        }

        let need: Int
        if b0 >= 0xC2 && b0 <= 0xDF {
            need = 2
        } else if b0 >= 0xE0 && b0 <= 0xEF {
            need = 3
        } else if b0 >= 0xF0 && b0 <= 0xF4 {
            need = 4
        } else {
            return (lastGood, i)
        }

        if i + need > bytes.count {
            return (lastGood, nil)
        }

        let b1 = bytes[i + 1]
        guard isCont(b1) else { return (lastGood, i) }

        if need == 2 {
            i += 2
            lastGood = i
            continue
        }

        let b2 = bytes[i + 2]
        guard isCont(b2) else { return (lastGood, i) }

        if need == 3 {
            if b0 == 0xE0 {
                if b1 < 0xA0 || b1 > 0xBF { return (lastGood, i) }
            } else if b0 == 0xED {
                if b1 < 0x80 || b1 > 0x9F { return (lastGood, i) }
            }
            i += 3
            lastGood = i
            continue
        }

        let b3 = bytes[i + 3]
        guard isCont(b3) else { return (lastGood, i) }

        if b0 == 0xF0 {
            if b1 < 0x90 || b1 > 0xBF { return (lastGood, i) }
        } else if b0 == 0xF4 {
            if b1 < 0x80 || b1 > 0x8F { return (lastGood, i) }
        }

        i += 4
        lastGood = i
    }

    return (lastGood, nil)
}

@inline(__always)
private func drainUTF8Buffer(_ buffer: inout [UInt8]) -> String {
    var out = ""
    while !buffer.isEmpty {
        let (good, invalidPos) = utf8ValidPrefixLen(buffer)
        if good > 0 {
            let prefix = Array(buffer[0..<good])
            if let s = String(bytes: prefix, encoding: .utf8), !s.isEmpty {
                out.append(s)
            }
            buffer.removeFirst(good)
            continue
        }

        if let bad = invalidPos {
            if bad == 0 {
                buffer.removeFirst(1)
            } else {
                buffer.removeFirst(bad)
            }
            continue
        }

        break
    }
    return out
}

// MARK: - Perf tracker

private struct LlamaOpTrace: Sendable {
    let opID: UUID
    let opName: String
    let start: CFAbsoluteTime
    let mode: String
    let seqId: Int32
    let promptChars: Int
    let maxTokens: Int32
    let modelPathTail: String

    init(opName: String, cfg: LlamaStreamConfig) {
        self.opID = UUID()
        self.opName = opName
        self.start = CFAbsoluteTimeGetCurrent()
        self.mode = String(describing: cfg.promptMode)
        self.seqId = cfg.seqId
        self.promptChars = cfg.prompt.count
        self.maxTokens = cfg.maxTokens
        self.modelPathTail = URL(fileURLWithPath: cfg.modelPath).lastPathComponent
    }

    @inline(__always)
    func elapsedMs() -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    @inline(__always)
    func prefix(_ phase: String) -> String {
        "[\(opName)][\(phase)] op=\(opID.uuidString) mode=\(mode) seq=\(seqId)"
    }
}

// MARK: - Public API

public enum LlamaBridgeError: Error, LocalizedError {
    case invalidModelPath(String)
    case failedToCreateContext(modelPath: String)
    case generateFailed(code: Int32)
    case ingestFailed(code: Int32)
    case continueFailed(code: Int32)
    case runtimeBusy

    public var errorDescription: String? {
        switch self {
        case .invalidModelPath(let p):
            return "Invalid model path: \(p)"
        case .failedToCreateContext(let modelPath):
            return "Failed to initialize llama context for model: \(modelPath)"
        case .generateFailed(let code):
            return "Generation failed (llama.cpp code \(code))"
        case .ingestFailed(let code):
            return "Ingest failed (llama.cpp code \(code))"
        case .continueFailed(let code):
            return "Continue failed (llama.cpp code \(code))"
        case .runtimeBusy:
            return "Llama runtime is busy (another generation is in progress)."
        }
    }
}

public struct LlamaStreamConfig: Sendable {
    public var modelPath: String
    public var prompt: String

    public var maxTokens: Int32 = 320
    public var seqId: Int32 = 0
    public var nCtx: Int32 = 2048
    public var nThreads: Int32 = 4
    public var nBatch: Int32 = 256
    public var temperature: Float = 0.5
    public var topK: Int32 = 60
    public var topP: Float = 0.91
    public var seed: Int32 = -1

    public enum PromptMode: Sendable {
        case fullReplay
        /// Full assembled prompt passed to `anum_llama_generate_ex`, but **without** `ANUM_RESET_FULL` first so native
        /// `common_prefix_len` + `llama_memory_seq_rm` can reuse the shared prefix across calls (when enabled).
        case prefixCachedReplay
        /// Same prompt as prior Direct Chat suggest: native restores prompt-end seq snapshot (`llama_state_seq_*`), then generates.
        case promptCheckpointRegenerate
        /// Stable Direct Chat scaffold matches saved checkpoint; decode dynamic tail only.
        case promptScaffoldCheckpointReplay
        case scaffoldPrime
        case scaffoldIngest
        case warmTurnIngest
        case continueFromState
    }

    public var promptMode: PromptMode = .fullReplay
    public var promptStableKey: String = ""
    /// When true, native snapshots seq state after prompt ingest (Direct Chat experimental regenerate path).
    public var capturePromptEndCheckpoint: Bool = false
    /// When true with Direct Chat full replay, snapshot stable scaffold prefix (`llama_state_seq_*`).
    public var captureScaffoldCheckpoint: Bool = false
    /// UTF-8 prefix of `prompt` that is the stable Exchange/Direct Chat scaffold (dynamic tail follows).
    public var scaffoldPromptPrefix: String?

    public init(
        modelPath: String,
        prompt: String,
        maxTokens: Int32 = 512,
        seqId: Int32 = 0,
        promptMode: PromptMode = .fullReplay,
        promptStableKey: String = ""
    ) {
        self.modelPath = modelPath
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.seqId = seqId
        self.promptMode = promptMode
        self.promptStableKey = promptStableKey
    }
}

public enum LlamaCppBridge {
    
    @available(macOS 10.15, iOS 13.0, *)
    public static func warmKernelAndWait(
        modelPath: String = "",
        nCtx: Int32 = 2048,
        nThreads: Int32 = 4,
        nBatch: Int32 = 128
    ) async {
        let start = CFAbsoluteTimeGetCurrent()

        let normalizedPath = normalizeModelPath(modelPath)
        let fallback = LlamaRuntime.shared.getLoadedModelPath() ?? ""
        let effectivePath = !normalizedPath.isEmpty ? normalizedPath : fallback

        guard !effectivePath.isEmpty else {
            llamaPerf("[bridge][warmKernelAndWait] bail noEffectivePath")
            return
        }

        let key = "kernelWarm|\(effectivePath)"
        llamaPerf("[bridge][warmKernelAndWait] begin key=\(key)")

        if let reason = await prewarmGate.begin(key: key) {
            llamaPerf("[bridge][warmKernelAndWait] gateDenied reason=\(reason)")

            // Important:
            // Do NOT wait for duplicate kernel warmup.
            // If another identical kernel warmup is already running, that owner will finish it.
            // Waiting here is what created duplicate-looking launch warm logs and unnecessary boot delay.
            if reason.contains("already prewarmed") {
                return
            }

            if reason.contains("same key") {
                await prewarmGate.waitForIdle()
                return
            }

            // If prefix/scaffold warming is already running, do not interrupt or queue kernel warmup behind it.
            // Prefix/scaffold warming is more valuable and will compile the important kernels anyway.
            return
        }

        var succeeded = false

        var cfg = LlamaStreamConfig(
            modelPath: effectivePath,
            prompt: "",
            maxTokens: 0,
            seqId: 0,
            promptMode: .fullReplay,
            promptStableKey: key
        )
        cfg.nCtx = nCtx
        cfg.nThreads = nThreads
        cfg.nBatch = nBatch
        cfg.temperature = 0
        cfg.topK = 1
        cfg.topP = 1

        do {
            let ensureStart = CFAbsoluteTimeGetCurrent()
            try LlamaRuntime.shared.ensureContext(cfg: cfg, qos: QOS_CLASS_UTILITY)
            let ensureMs = Int((CFAbsoluteTimeGetCurrent() - ensureStart) * 1000)

            let warmStart = CFAbsoluteTimeGetCurrent()
            try LlamaRuntime.shared.kernelWarmup(cfg: cfg)
            let warmMs = Int((CFAbsoluteTimeGetCurrent() - warmStart) * 1000)

            succeeded = true

            let totalMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[bridge][warmKernelAndWait] OK ensure=\(ensureMs)ms warm=\(warmMs)ms total=\(totalMs)ms reset=FULL")
        } catch {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[bridge][warmKernelAndWait] ERROR total=\(totalMs)ms error=\(String(describing: error))")
        }

        await prewarmGate.finish(succeeded: succeeded)
    }
    
    private actor RuntimeState {
        private var invalidationToken: UInt64 = 0
        private var scaffoldKey: String = ""
        private var scaffoldIngested: Bool = false
        private var lastTurnKey: String = ""
        
        func invalidate() {
            invalidationToken &+= 1
            scaffoldKey = ""
            scaffoldIngested = false
            lastTurnKey = ""
        }
        
        func markScaffoldIngested(key: String) {
            scaffoldKey = key
            scaffoldIngested = true
            lastTurnKey = ""
        }
        
        func markTurnIngested(key: String) {
            lastTurnKey = key
        }
        
        func canContinue(scaffoldKey key: String) -> Bool {
            scaffoldIngested && scaffoldKey == key
        }
        
        func snapshot() -> (token: UInt64, scaffoldKey: String, scaffoldIngested: Bool, lastTurnKey: String) {
            (
                token: invalidationToken,
                scaffoldKey: scaffoldKey,
                scaffoldIngested: scaffoldIngested,
                lastTurnKey: lastTurnKey
            )
        }
    }
    
    private actor PrewarmGate {
        private var inFlight = false
        private var inFlightKey = ""
        private var warmedKey = ""
        private var waiters: [CheckedContinuation<Void, Never>] = []
        
        func invalidate() {
            inFlight = false
            inFlightKey = ""
            warmedKey = ""
            if !waiters.isEmpty {
                let ws = waiters
                waiters.removeAll()
                for w in ws { w.resume() }
            }
        }
        
        func begin(key: String) -> String? {
            if inFlight {
                if inFlightKey == key {
                    return "already in-flight (same key)"
                }
                return "already in-flight (currentKey=\(inFlightKey))"
            }
            if warmedKey == key {
                return "already prewarmed (same key)"
            }
            inFlight = true
            inFlightKey = key
            return nil
        }
        
        func finish(succeeded: Bool) {
            let finishedKey = inFlightKey
            inFlight = false
            inFlightKey = ""
            warmedKey = succeeded ? finishedKey : ""
            
            if !waiters.isEmpty {
                let ws = waiters
                waiters.removeAll()
                for w in ws { w.resume() }
            }
        }
        
        func waitForIdle() async {
            if !inFlight { return }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                waiters.append(c)
            }
        }
        
        func currentInFlightKey() -> String {
            inFlightKey
        }
    }
    
    private static let runtimeState = RuntimeState()
    private static let prewarmGate = PrewarmGate()
    
    private static func normalizeModelPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let url = URL(fileURLWithPath: trimmed)
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }
    
    @available(macOS 10.15, iOS 13.0, *)
    public static func stream(_ cfg: LlamaStreamConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            let trace = LlamaOpTrace(opName: "stream", cfg: cfg)
            
            llamaPerf(
                "\(trace.prefix("begin")) model=\(trace.modelPathTail) " +
                "promptChars=\(trace.promptChars) maxTokens=\(trace.maxTokens) " +
                "nCtx=\(cfg.nCtx) nThreads=\(cfg.nThreads) nBatch=\(cfg.nBatch) " +
                "temp=\(cfg.temperature) topK=\(cfg.topK) topP=\(cfg.topP)"
            )
            
            let normalizedPath = normalizeModelPath(cfg.modelPath)
            llamaPerf("\(trace.prefix("normalizePath")) elapsed=\(trace.elapsedMs())ms normalizedTail=\(URL(fileURLWithPath: normalizedPath).lastPathComponent)")
            guard !normalizedPath.isEmpty else {
                cont.finish(throwing: LlamaBridgeError.invalidModelPath(cfg.modelPath))
                return
            }
            
            var localCfg = cfg
            localCfg.modelPath = normalizedPath
            
            let gate = FinishGate(cont)
            let box = ContinuationBox(cont)
            let cbCtx = CallbackContext(box: box, gate: gate, trace: trace)
            let unmanaged = Unmanaged.passRetained(cbCtx)
            let userData = unmanaged.toOpaque()
            
            let producer = Task.detached(priority: .userInitiated) {
                pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0)
                
                defer {
                    unmanaged.release()
                    gate.finish()
                    llamaPerf("\(trace.prefix("producerEnd")) elapsed=\(trace.elapsedMs())ms")
                }
                
                do {
                    let ensureStart = CFAbsoluteTimeGetCurrent()
                    try LlamaRuntime.shared.ensureContext(cfg: localCfg, qos: QOS_CLASS_USER_INITIATED)
                    let ensureMs = Int((CFAbsoluteTimeGetCurrent() - ensureStart) * 1000)
                    llamaPerf("\(trace.prefix("ensureContext")) elapsed=\(trace.elapsedMs())ms step=\(ensureMs)ms")
                    
                    let rc: Int32
                    switch localCfg.promptMode {
                    case .continueFromState:
                        let opStart = CFAbsoluteTimeGetCurrent()
                        llamaPerf("\(trace.prefix("continueBegin")) elapsed=\(trace.elapsedMs())ms")
                        rc = try LlamaRuntime.shared.continueGeneration(cfg: localCfg, userData: userData)
                        let stepMs = Int((CFAbsoluteTimeGetCurrent() - opStart) * 1000)
                        llamaPerf("\(trace.prefix("continueEnd")) elapsed=\(trace.elapsedMs())ms rc=\(rc) step=\(stepMs)ms")
                        
                    case .fullReplay, .scaffoldPrime, .prefixCachedReplay, .promptCheckpointRegenerate,
                         .promptScaffoldCheckpointReplay:
                        let opStart = CFAbsoluteTimeGetCurrent()
                        llamaPerf("\(trace.prefix("generateBegin")) elapsed=\(trace.elapsedMs())ms")
                        rc = try LlamaRuntime.shared.generate(cfg: localCfg, userData: userData)
                        let stepMs = Int((CFAbsoluteTimeGetCurrent() - opStart) * 1000)
                        llamaPerf("\(trace.prefix("generateEnd")) elapsed=\(trace.elapsedMs())ms rc=\(rc) step=\(stepMs)ms")
                        
                    case .scaffoldIngest:
                        let opStart = CFAbsoluteTimeGetCurrent()
                        llamaPerf("\(trace.prefix("ingestScaffoldBegin")) elapsed=\(trace.elapsedMs())ms")
                        try LlamaRuntime.shared.ingestScaffold(cfg: localCfg, scaffold: localCfg.prompt)
                        await runtimeState.markScaffoldIngested(key: localCfg.promptStableKey)
                        rc = 0
                        let stepMs = Int((CFAbsoluteTimeGetCurrent() - opStart) * 1000)
                        llamaPerf("\(trace.prefix("ingestScaffoldEnd")) elapsed=\(trace.elapsedMs())ms rc=\(rc) step=\(stepMs)ms")
                        
                    case .warmTurnIngest:
                        let opStart = CFAbsoluteTimeGetCurrent()
                        llamaPerf("\(trace.prefix("ingestTurnBegin")) elapsed=\(trace.elapsedMs())ms")
                        try LlamaRuntime.shared.ingestTurn(cfg: localCfg, turnText: localCfg.prompt)
                        await runtimeState.markTurnIngested(key: localCfg.promptStableKey)
                        rc = 0
                        let stepMs = Int((CFAbsoluteTimeGetCurrent() - opStart) * 1000)
                        llamaPerf("\(trace.prefix("ingestTurnEnd")) elapsed=\(trace.elapsedMs())ms rc=\(rc) step=\(stepMs)ms")
                    }
                    
                    if rc == -9 {
                        if Task.isCancelled {
                            throw CancellationError()
                        } else {
                            llamaPerf("\(trace.prefix("nativeAbortNoSwiftCancel")) elapsed=\(trace.elapsedMs())ms")
                            return
                        }
                    }
                    
                    if rc != 0 {
                        switch localCfg.promptMode {
                        case .continueFromState:
                            throw LlamaBridgeError.continueFailed(code: rc)
                        case .scaffoldIngest, .warmTurnIngest:
                            throw LlamaBridgeError.ingestFailed(code: rc)
                        default:
                            throw LlamaBridgeError.generateFailed(code: rc)
                        }
                    }
                } catch {
                    llamaError("producer ERROR: \(String(describing: error))")
                    llamaPerf("\(trace.prefix("producerError")) elapsed=\(trace.elapsedMs())ms error=\(String(describing: error))")
                    gate.finish(throwing: error)
                }
            }
            
            cont.onTermination = { @Sendable term in
                switch term {
                case .finished:
                    llamaPerf("\(trace.prefix("terminationFinished")) elapsed=\(trace.elapsedMs())ms")
                case .cancelled:
                    llamaPerf(
                        "\(trace.prefix("terminationCancelled")) elapsed=\(trace.elapsedMs())ms -> abort " +
                        "finishThrowing=CancellationError"
                    )
                    cbCtx.box.cancel()
                    LlamaRuntime.shared.requestAbort()
                    producer.cancel()
                    cbCtx.gate.finish(throwing: CancellationError())
                @unknown default:
                    llamaPerf("\(trace.prefix("terminationUnknown")) elapsed=\(trace.elapsedMs())ms")
                }
            }
        }
    }
    
    public static func pauseForBackground() {
        llamaDebug("pauseForBackground()")
        llamaPerf("[bridge][pauseForBackground] begin")
        
        LlamaRuntime.shared.pauseForBackground()
        Task {
            await prewarmGate.invalidate()
            await runtimeState.invalidate()
            llamaPerf("[bridge][pauseForBackground] invalidated runtime+prewarm")
        }
    }
    
    public static func resumeAfterBackground(modelPath: String? = nil) {
        llamaDebug("resumeAfterBackground(modelPath: \(modelPath ?? "nil"))")
        llamaPerf("[bridge][resumeAfterBackground] begin modelPath=\(modelPath ?? "nil")")
        
        // Resume should only clear pause flags and remember the model path.
        // Do NOT auto-prewarm here. Prewarm must be explicitly owned by RootView/ModelStore,
        // otherwise foreground resume can race with the next user generation.
        LlamaRuntime.shared.resumeAfterBackground(modelPath: modelPath)
        
        llamaPerf("[bridge][resumeAfterBackground] end noAutoPrewarm")
    }
    
    public static func prewarm(
        modelPath: String = "",
        prefixPrompt: String? = nil,
        nCtx: Int32 = 2048,
        nThreads: Int32 = 4,
        nBatch: Int32 = 256
    ) {
        _prewarm(
            modelPath: modelPath,
            prefixPrompt: prefixPrompt,
            nCtx: nCtx,
            nThreads: nThreads,
            nBatch: nBatch,
            allowQueueAfterInFlight: true
        )
    }
    
    @available(macOS 10.15, iOS 13.0, *)
    public static func prewarmAndWait(
        modelPath: String = "",
        prefixPrompt: String? = nil,
        nCtx: Int32 = 2048,
        nThreads: Int32 = 4,
        nBatch: Int32 = 256
    ) async {
        let start = CFAbsoluteTimeGetCurrent()

        let normalizedPath = normalizeModelPath(modelPath)
        let fallback = LlamaRuntime.shared.getLoadedModelPath() ?? ""
        let effectivePath = !normalizedPath.isEmpty ? normalizedPath : fallback

        guard !effectivePath.isEmpty else {
            llamaPerf("[bridge][prewarmAndWait] bail noEffectivePath")
            return
        }

        let ppRaw = prefixPrompt ?? ""
        let wantsPrefix = !ppRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard wantsPrefix else {
            llamaPerf("[bridge][prewarmAndWait] no prefix -> redirect kernel warm")
            await warmKernelAndWait(
                modelPath: effectivePath,
                nCtx: nCtx,
                nThreads: nThreads,
                nBatch: min(nBatch, 128)
            )
            return
        }

        let modeKey = "prefix|\(effectivePath)|\(abs(ppRaw.hashValue))|len=\(ppRaw.count)"
        llamaPerf("[bridge][prewarmAndWait] begin key=\(modeKey) wantsPrefix=true")

        var ownsGate = false

        while !ownsGate {
            if let reason = await prewarmGate.begin(key: modeKey) {
                llamaPerf("[bridge][prewarmAndWait] gateDenied reason=\(reason)")

                if reason.contains("already prewarmed") {
                    let totalMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    llamaPerf("[bridge][prewarmAndWait] alreadyDone total=\(totalMs)ms")
                    return
                }

                if reason.contains("same key") {
                    await prewarmGate.waitForIdle()
                    let waitedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    llamaPerf("[bridge][prewarmAndWait] waitedForSameKey total=\(waitedMs)ms")
                    return
                }

                // Different in-flight work, usually kernel warm.
                // Wait for it, then retry acquiring the prefix gate.
                if reason.hasPrefix("already in-flight") {
                    await prewarmGate.waitForIdle()
                    let waitedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    llamaPerf("[bridge][prewarmAndWait] waitedForIdle retrying total=\(waitedMs)ms")
                    continue
                }

                return
            } else {
                ownsGate = true
            }
        }

        var succeeded = false

        var cfg = LlamaStreamConfig(
            modelPath: effectivePath,
            prompt: "",
            maxTokens: 0,
            seqId: 0,
            promptMode: .scaffoldPrime,
            promptStableKey: modeKey
        )
        cfg.nCtx = nCtx
        cfg.nThreads = nThreads
        cfg.nBatch = nBatch
        cfg.temperature = 0
        cfg.topK = 1
        cfg.topP = 1

        do {
            let ensureStart = CFAbsoluteTimeGetCurrent()
            try LlamaRuntime.shared.ensureContext(cfg: cfg, qos: QOS_CLASS_UTILITY)
            let ensureMs = Int((CFAbsoluteTimeGetCurrent() - ensureStart) * 1000)

            // Do not run dummy kernel warmup here.
            // Scaffold ingest is the real reusable state.
            let warmStart = CFAbsoluteTimeGetCurrent()
            try LlamaRuntime.shared.warmup(cfg: cfg, promptOverride: ppRaw)
            let warmMs = Int((CFAbsoluteTimeGetCurrent() - warmStart) * 1000)

            succeeded = true

            let totalMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[bridge][prewarmAndWait] OK ensure=\(ensureMs)ms scaffoldWarm=\(warmMs)ms total=\(totalMs)ms")
        } catch {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[bridge][prewarmAndWait] ERROR total=\(totalMs)ms error=\(String(describing: error))")
        }

        await prewarmGate.finish(succeeded: succeeded)
    }
    
    @available(macOS 10.15, iOS 13.0, *)
    public static func primePrefixAndWait(
        modelPath: String = "",
        prefixPrompt: String,
        nCtx: Int32 = 2048,
        nThreads: Int32 = 4,
        nBatch: Int32 = 256
    ) async {
        let trimmed = prefixPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            llamaPerf("[bridge][primePrefixAndWait] bail emptyPrefix")
            return
        }

        llamaPerf("[bridge][primePrefixAndWait] redirect prewarmAndWait prefixChars=\(prefixPrompt.count)")

        await prewarmAndWait(
            modelPath: modelPath,
            prefixPrompt: prefixPrompt,
            nCtx: nCtx,
            nThreads: nThreads,
            nBatch: nBatch
        )
    }
    
    private static func _prewarm(
        modelPath: String,
        prefixPrompt: String?,
        nCtx: Int32,
        nThreads: Int32,
        nBatch: Int32,
        allowQueueAfterInFlight: Bool
    ) {
        let raw = modelPath
        let normalizedPath = normalizeModelPath(raw)
        let fallback = LlamaRuntime.shared.getLoadedModelPath() ?? ""
        let effectivePath = !normalizedPath.isEmpty ? normalizedPath : fallback

        let ppRaw = prefixPrompt ?? ""
        let wantsPrefix = !ppRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard !effectivePath.isEmpty else {
            llamaPerf("[bridge][_prewarm] bail noEffectivePath")
            return
        }

        Task.detached(priority: .utility) {
            llamaPerf("[bridge][_prewarm] redirect wantsPrefix=\(wantsPrefix) allowQueueAfterInFlight=\(allowQueueAfterInFlight)")

            if wantsPrefix {
                await prewarmAndWait(
                    modelPath: effectivePath,
                    prefixPrompt: ppRaw,
                    nCtx: nCtx,
                    nThreads: nThreads,
                    nBatch: nBatch
                )
            } else {
                await warmKernelAndWait(
                    modelPath: effectivePath,
                    nCtx: nCtx,
                    nThreads: nThreads,
                    nBatch: min(nBatch, 128)
                )
            }
        }
    }
    
    public static func abortCurrentGeneration() {
        llamaPerf("[bridge][abortCurrentGeneration] request")
        LlamaRuntime.shared.requestAbort()
    }
    
    public static func invalidateRuntimeState() {
        llamaPerf("[bridge][invalidateRuntimeState] request")
        Task { await runtimeState.invalidate() }
    }
    
    @available(macOS 10.15, iOS 13.0, *)
    public static func streamFromState(_ cfg: LlamaStreamConfig) -> AsyncThrowingStream<String, Error> {
        var local = cfg
        local.promptMode = .continueFromState
        llamaPerf("[bridge][streamFromState] redirect mode=continueFromState seq=\(local.seqId)")
        return stream(local)
    }
    
    @available(macOS 10.15, iOS 13.0, *)
    public static func ingestTurnAndWait(
        modelPath: String = "",
        turnText: String,
        seqId: Int32 = 0,
        nCtx: Int32 = 2048,
        nThreads: Int32 = 4,
        nBatch: Int32 = 256
    ) async -> Bool {
        let start = CFAbsoluteTimeGetCurrent()
        let normalizedPath = normalizeModelPath(modelPath)
        let fallback = LlamaRuntime.shared.getLoadedModelPath() ?? ""
        let effectivePath = !normalizedPath.isEmpty ? normalizedPath : fallback
        
        guard !effectivePath.isEmpty else {
            llamaPerf("[bridge][ingestTurnAndWait] bail noEffectivePath")
            return false
        }
        
        let rawTurnText = turnText
        
        guard !rawTurnText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            llamaPerf("[bridge][ingestTurnAndWait] bail emptyTurn")
            return false
        }
        
        let turnKey = "turn|\(effectivePath)|\(abs(rawTurnText.hashValue))|len=\(rawTurnText.count)|seq=\(seqId)"
        llamaPerf("[bridge][ingestTurnAndWait] begin key=\(turnKey)")
        
        do {
            var cfg = LlamaStreamConfig(
                modelPath: effectivePath,
                prompt: rawTurnText,
                maxTokens: 0,
                seqId: seqId,
                promptMode: .warmTurnIngest,
                promptStableKey: turnKey
            )
            cfg.nCtx = nCtx
            cfg.nThreads = nThreads
            cfg.nBatch = nBatch
            cfg.temperature = 0
            cfg.topK = 1
            cfg.topP = 1
            
            let ensureStart = CFAbsoluteTimeGetCurrent()
            try LlamaRuntime.shared.ensureContext(cfg: cfg, qos: QOS_CLASS_UTILITY)
            let ensureMs = Int((CFAbsoluteTimeGetCurrent() - ensureStart) * 1000)
            
            let ingestStart = CFAbsoluteTimeGetCurrent()
            try LlamaRuntime.shared.ingestTurn(cfg: cfg, turnText: rawTurnText)
            let ingestMs = Int((CFAbsoluteTimeGetCurrent() - ingestStart) * 1000)
            
            await runtimeState.markTurnIngested(key: turnKey)
            
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[bridge][ingestTurnAndWait] OK ensure=\(ensureMs)ms ingest=\(ingestMs)ms total=\(totalMs)ms key=\(turnKey)")
            return true
        } catch {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[bridge][ingestTurnAndWait] ERROR total=\(totalMs)ms error=\(String(describing: error)) key=\(turnKey)")
            return false
        }
    }
    
    @available(macOS 10.15, iOS 13.0, *)
    public static func ingestScaffoldAndWait(
        modelPath: String = "",
        scaffoldPrompt: String,
        nCtx: Int32 = 2048,
        nThreads: Int32 = 4,
        nBatch: Int32 = 256
    ) async -> Bool {
        let start = CFAbsoluteTimeGetCurrent()
        let normalizedPath = normalizeModelPath(modelPath)
        let fallback = LlamaRuntime.shared.getLoadedModelPath() ?? ""
        let effectivePath = !normalizedPath.isEmpty ? normalizedPath : fallback
        
        guard !effectivePath.isEmpty else {
            llamaPerf("[bridge][ingestScaffoldAndWait] bail noEffectivePath")
            return false
        }
        
        let rawScaffoldPrompt = scaffoldPrompt
        
        guard !rawScaffoldPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            llamaPerf("[bridge][ingestScaffoldAndWait] bail emptyScaffold")
            return false
        }
        
        let scaffoldKey = "scaffold|\(effectivePath)|\(abs(rawScaffoldPrompt.hashValue))|len=\(rawScaffoldPrompt.count)"
        llamaPerf("[bridge][ingestScaffoldAndWait] begin key=\(scaffoldKey)")
        
        do {
            var cfg = LlamaStreamConfig(
                modelPath: effectivePath,
                prompt: rawScaffoldPrompt,
                maxTokens: 0,
                seqId: 0,
                promptMode: .scaffoldIngest,
                promptStableKey: scaffoldKey
            )
            cfg.nCtx = nCtx
            cfg.nThreads = nThreads
            cfg.nBatch = nBatch
            cfg.temperature = 0
            cfg.topK = 1
            cfg.topP = 1
            
            let ensureStart = CFAbsoluteTimeGetCurrent()
            try LlamaRuntime.shared.ensureContext(cfg: cfg, qos: QOS_CLASS_UTILITY)
            let ensureMs = Int((CFAbsoluteTimeGetCurrent() - ensureStart) * 1000)
            
            let ingestStart = CFAbsoluteTimeGetCurrent()
            try LlamaRuntime.shared.ingestScaffold(cfg: cfg, scaffold: rawScaffoldPrompt)
            let ingestMs = Int((CFAbsoluteTimeGetCurrent() - ingestStart) * 1000)
            
            await runtimeState.markScaffoldIngested(key: scaffoldKey)
            
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[bridge][ingestScaffoldAndWait] OK ensure=\(ensureMs)ms ingest=\(ingestMs)ms total=\(totalMs)ms key=\(scaffoldKey)")
            return true
        } catch {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[bridge][ingestScaffoldAndWait] ERROR total=\(totalMs)ms error=\(String(describing: error)) key=\(scaffoldKey)")
            return false
        }
    }
}

// MARK: - Internal runtime

@available(macOS 10.15, iOS 13.0, *)
private final class FinishGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var cont: AsyncThrowingStream<String, Error>.Continuation?

    init(_ cont: AsyncThrowingStream<String, Error>.Continuation) {
        self.cont = cont
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        cont?.finish()
        cont = nil
    }

    func finish(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        cont?.finish(throwing: error)
        cont = nil
    }
}

@available(macOS 10.15, iOS 13.0, *)
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var cont: AsyncThrowingStream<String, Error>.Continuation?

    init(_ cont: AsyncThrowingStream<String, Error>.Continuation) {
        self.cont = cont
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        cont = nil
        lock.unlock()
    }

    func yield(_ s: String) {
        lock.lock()
        let c = cont
        let cancelled = isCancelled
        lock.unlock()

        guard !cancelled else { return }
        c?.yield(s)
    }
}

@available(macOS 10.15, iOS 13.0, *)
private final class CallbackContext: @unchecked Sendable {
    let box: ContinuationBox
    let gate: FinishGate
    let trace: LlamaOpTrace
    var sawFirstToken = false
    var utf8Carry: [UInt8] = []

    init(box: ContinuationBox, gate: FinishGate, trace: LlamaOpTrace) {
        self.box = box
        self.gate = gate
        self.trace = trace
    }
}

@available(macOS 10.15, iOS 13.0, *)
private final class LlamaRuntime: @unchecked Sendable {
    static let shared = LlamaRuntime()

    private let workQueue = DispatchQueue(
        label: "com.anum.llama.runtime",
        qos: .userInitiated,
        target: DispatchQueue.global(qos: .userInitiated)
    )

    private var isGenerating = false
    private var destroyWhenIdle = false
    private var pauseRequested = false

    // Delayed background destroy.
    // Quick background/foreground transitions should not immediately unload the model,
    // because that causes expensive reload, heat, and foreground TTFT spikes.
    private var backgroundDestroyWorkItem: DispatchWorkItem?

    private let lock = NSLock()
    private var ctx: anum_llama_t? = nil
    private var loadedModelPath: String? = nil
    private var seq0StateIsReusable = false
    /// True after `ensureContext` creates a new native handle with no prompt/KV state yet.
    private var contextIsFreshForScaffoldIngest = false

    private init() {}

    /// Pre-scaffold reset: fresh contexts skip `ANUM_RESET_FULL` (which frees/recreates llama_context).
    private func preResetForScaffoldIngest(localCtx: anum_llama_t, callSite: String) -> Int32 {
        let useFreshContext: Bool = {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.contextIsFreshForScaffoldIngest
        }()

        if useFreshContext {
            self.lock.lock()
            self.contextIsFreshForScaffoldIngest = false
            self.lock.unlock()

            llamaPerf(
                "[RuntimeContextReuse] action=reuseFreshContext reason=prewarmFreshCreate site=\(callSite)"
            )
            let rc = anum_llama_reset(localCtx, ANUM_RESET_NONE)
            if rc != 0 {
                llamaPerf(
                    "[RuntimeContextReuse] action=reuseFreshContext fallback=KV site=\(callSite) rc=\(rc)"
                )
                return anum_llama_reset(localCtx, ANUM_RESET_KV)
            }
            return rc
        }

        llamaPerf(
            "[RuntimeContextReuse] action=recreate reason=staleNativeState site=\(callSite)"
        )
        self.lock.lock()
        self.contextIsFreshForScaffoldIngest = false
        self.lock.unlock()
        return anum_llama_reset(localCtx, ANUM_RESET_FULL)
    }

    deinit {
        backgroundDestroyWorkItem?.cancel()
        backgroundDestroyWorkItem = nil

        workQueue.sync {
            if let c = ctx {
                anum_llama_destroy(c)
                ctx = nil
            }
        }
    }

    private func withQueue<T>(qos: qos_class_t, _ body: () throws -> T) throws -> T {
        var result: Result<T, Error>!
        workQueue.sync {
            pthread_set_qos_class_self_np(qos, 0)
            result = Result { try body() }
        }
        return try result.get()
    }

    private func withQueue<T>(_ body: () throws -> T) throws -> T {
        try withQueue(qos: QOS_CLASS_USER_INITIATED, body)
    }

    func pauseForBackground() {
        let start = CFAbsoluteTimeGetCurrent()
        llamaDebug("pauseForBackground()")

        lock.lock()

        if pauseRequested {
            lock.unlock()
            llamaDebug("pauseForBackground() noop: already requested")
            llamaPerf("[runtime][pauseForBackground] noop alreadyRequested")
            return
        }

        pauseRequested = true

        // Do not hard-destroy immediately.
        // If the app foregrounds quickly, keeping the context resident avoids a full model reload.
        destroyWhenIdle = false

        // Cancel any older pending destroy and schedule a fresh one.
        backgroundDestroyWorkItem?.cancel()
        backgroundDestroyWorkItem = nil

        let localCtx = ctx
        let wasGenerating = isGenerating

        lock.unlock()

        if wasGenerating, let c = localCtx {
            anum_llama_abort(c)
        }

        let delaySeconds: TimeInterval = 45.0

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.workQueue.async {
                self.lock.lock()
                defer { self.lock.unlock() }

                guard self.pauseRequested else {
                    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    llamaPerf("[runtime][pauseForBackground] delayedDestroy cancelledByResume elapsed=\(elapsedMs)ms")
                    return
                }

                if self.isGenerating {
                    // If native generation is still unwinding, destroy when it exits.
                    self.destroyWhenIdle = true
                    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    llamaPerf("[runtime][pauseForBackground] delayedDestroy deferredStillGenerating elapsed=\(elapsedMs)ms")
                    return
                }

                if let c = self.ctx {
                    anum_llama_destroy(c)
                    self.ctx = nil
                }

                self.loadedModelPath = nil
                self.seq0StateIsReusable = false
                self.contextIsFreshForScaffoldIngest = false
                self.destroyWhenIdle = false
                self.backgroundDestroyWorkItem = nil

                let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                llamaPerf("[runtime][pauseForBackground] delayedDestroyed elapsed=\(elapsedMs)ms delay=\(Int(delaySeconds))s")
            }
        }

        lock.lock()
        backgroundDestroyWorkItem = item
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delaySeconds,
            execute: item
        )

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        llamaPerf("[runtime][pauseForBackground] pausedResident elapsed=\(elapsedMs)ms wasGenerating=\(wasGenerating) delayedDestroy=\(Int(delaySeconds))s")
    }

    func resumeAfterBackground(modelPath: String? = nil) {
        let start = CFAbsoluteTimeGetCurrent()
        llamaDebug("resumeAfterBackground(modelPath: \(modelPath ?? "nil"))")

        lock.lock()
        defer { lock.unlock() }

        // Foreground cancels delayed unload.
        backgroundDestroyWorkItem?.cancel()
        backgroundDestroyWorkItem = nil

        pauseRequested = false
        destroyWhenIdle = false

        if let mp = modelPath?.trimmingCharacters(in: .whitespacesAndNewlines), !mp.isEmpty {
            let normalized = URL(fileURLWithPath: mp)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path

            loadedModelPath = normalized
        }

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        llamaPerf("[runtime][resumeAfterBackground] done elapsed=\(elapsedMs)ms loaded=\(loadedModelPath ?? "nil") ctxResident=\(ctx != nil)")
    }

    func ensureContext(cfg: LlamaStreamConfig, qos: qos_class_t = QOS_CLASS_USER_INITIATED) throws {
        let start = CFAbsoluteTimeGetCurrent()

        let path = URL(fileURLWithPath: cfg.modelPath.trimmingCharacters(in: .whitespacesAndNewlines))
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path

        try withQueue(qos: qos) {
            self.lock.lock()
            defer { self.lock.unlock() }

            if let current = self.loadedModelPath, current == path, self.ctx != nil {
                let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                llamaPerf(
                    "[runtime][ensureContext] reuse elapsed=\(elapsedMs)ms " +
                    "path=\(URL(fileURLWithPath: path).lastPathComponent) freshForScaffold=\(self.contextIsFreshForScaffoldIngest)"
                )
                return
            }

            if self.isGenerating {
                let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                llamaPerf("[runtime][ensureContext] runtimeBusy elapsed=\(elapsedMs)ms")
                throw LlamaBridgeError.runtimeBusy
            }

            if let old = self.ctx {
                llamaPerf(
                    "[RuntimeContextReuse] action=recreate reason=keyChanged site=ensureContext " +
                    "from=\(self.loadedModelPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "nil") " +
                    "to=\(URL(fileURLWithPath: path).lastPathComponent)"
                )
                anum_llama_destroy(old)
                self.ctx = nil
                self.loadedModelPath = nil
                self.seq0StateIsReusable = false
                self.contextIsFreshForScaffoldIngest = false
            }

            var p = anum_llama_params_t()
            p.n_ctx = cfg.nCtx
            p.n_threads = cfg.nThreads
            p.n_batch = cfg.nBatch
            p.temperature = cfg.temperature
            p.top_k = cfg.topK
            p.top_p = cfg.topP
            p.seed = cfg.seed

            let createStart = CFAbsoluteTimeGetCurrent()
            var created: anum_llama_t? = path.withCString { cstr in
                anum_llama_create(cstr, p)
            }
            var usedFallbackBatch = false

            if created == nil, p.n_batch > 128 {
                p.n_batch = 128
                usedFallbackBatch = true
                created = path.withCString { cstr in
                    anum_llama_create(cstr, p)
                }
            }

            let createMs = Int((CFAbsoluteTimeGetCurrent() - createStart) * 1000)

            guard let created else {
                let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                llamaPerf("[runtime][ensureContext] createFailed elapsed=\(elapsedMs)ms create=\(createMs)ms")
                throw LlamaBridgeError.failedToCreateContext(modelPath: path)
            }

            self.ctx = created
            self.loadedModelPath = path
            self.seq0StateIsReusable = false
            self.contextIsFreshForScaffoldIngest = true

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf(
                "[runtime][ensureContext] created elapsed=\(elapsedMs)ms create=\(createMs)ms " +
                "path=\(URL(fileURLWithPath: path).lastPathComponent) nCtx=\(cfg.nCtx) nBatch=\(p.n_batch) " +
                "fallbackBatch=\(usedFallbackBatch) freshForScaffold=true"
            )
        }
    }

    func generate(cfg: LlamaStreamConfig, userData: UnsafeMutableRawPointer) throws -> Int32 {
        let start = CFAbsoluteTimeGetCurrent()

        let cb: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer) -> Void = { cstr, ud in
            let ctx = Unmanaged<CallbackContext>.fromOpaque(ud).takeUnretainedValue()

            guard let cstr else {
                let flushed = drainUTF8Buffer(&ctx.utf8Carry)
                if !flushed.isEmpty { ctx.box.yield(flushed) }
                ctx.utf8Carry.removeAll(keepingCapacity: true)
                ctx.box.cancel()
                ctx.gate.finish()
                return
            }

            if cstr.pointee == 0 {
                let flushed = drainUTF8Buffer(&ctx.utf8Carry)
                if !flushed.isEmpty { ctx.box.yield(flushed) }
                ctx.utf8Carry.removeAll(keepingCapacity: true)
                ctx.box.cancel()
                ctx.gate.finish()
                return
            }

            if !ctx.sawFirstToken {
                ctx.sawFirstToken = true
                let len = strnlen(cstr, 4096)
                let ttftMs = ctx.trace.elapsedMs()
                llamaDebug("cb: first token received (len=\(len))")
                llamaPerf("\(ctx.trace.prefix("ttft")) ttft=\(ttftMs)ms firstChunkBytes=\(len)")
            }

            let len = Int(strnlen(cstr, 16384))
            if len > 0 {
                let data = Data(bytes: cstr, count: len)
                ctx.utf8Carry.append(contentsOf: data)
                let drained = drainUTF8Buffer(&ctx.utf8Carry)
                if !drained.isEmpty {
                    ctx.box.yield(drained)
                }
            }
        }

        return try withQueue(qos: QOS_CLASS_USER_INITIATED) {
            self.lock.lock()

            guard let localCtx = self.ctx else {
                self.lock.unlock()
                throw LlamaBridgeError.failedToCreateContext(modelPath: cfg.modelPath)
            }

            if self.isGenerating {
                self.lock.unlock()
                throw LlamaBridgeError.runtimeBusy
            }

            self.isGenerating = true
            self.lock.unlock()

            var preResetRC: Int32 = 0

            // Critical:
            // fullReplay/scaffoldPrime must start from a clean native sequence.
            // invalidateRuntimeState() only clears Swift-side bookkeeping; it does not synchronously
            // clear llama.cpp KV / recurrent / M-RoPE position state.
            //
            // Without this, the next fullReplay can start token ingestion at Y lower than the
            // previous stored sequence position X, causing:
            // "for M-RoPE, it is required that X < Y"
            //
            // prefixCachedReplay intentionally skips FULL reset so `anum_llama_generate_ex` can reuse
            // the stable prompt prefix via common_prefix_len + llama_memory_seq_rm (same full prompt each call).
            switch cfg.promptMode {
            case .fullReplay, .scaffoldPrime:
                preResetRC = self.preResetForScaffoldIngest(
                    localCtx: localCtx,
                    callSite: "generate.\(cfg.promptMode)"
                )

                if preResetRC != 0 {
                    self.lock.lock()
                    self.isGenerating = false
                    if cfg.seqId == 0 {
                        self.seq0StateIsReusable = false
                    }

                    if self.destroyWhenIdle {
                        self.destroyWhenIdle = false
                        self.backgroundDestroyWorkItem?.cancel()
                        self.backgroundDestroyWorkItem = nil

                        if let c = self.ctx {
                            anum_llama_destroy(c)
                            self.ctx = nil
                        }

                        self.loadedModelPath = nil
                        self.seq0StateIsReusable = false
                    }

                    self.lock.unlock()

                    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    llamaPerf("[runtime][generate] preReset FAILED rc=\(preResetRC) elapsed=\(elapsedMs)ms mode=\(cfg.promptMode)")

                    throw LlamaBridgeError.generateFailed(code: preResetRC)
                }

            case .promptCheckpointRegenerate:
                llamaPerf("[runtime][generate] resetMode=PROMPT_CHECKPOINT_REGENERATE mode=\(cfg.promptMode)")
                preResetRC = anum_llama_reset(localCtx, ANUM_RESET_PROMPT_CHECKPOINT_REGENERATE)

                if preResetRC != 0 {
                    self.lock.lock()
                    self.isGenerating = false
                    if cfg.seqId == 0 {
                        self.seq0StateIsReusable = false
                    }

                    if self.destroyWhenIdle {
                        self.destroyWhenIdle = false
                        self.backgroundDestroyWorkItem?.cancel()
                        self.backgroundDestroyWorkItem = nil

                        if let c = self.ctx {
                            anum_llama_destroy(c)
                            self.ctx = nil
                        }

                        self.loadedModelPath = nil
                        self.seq0StateIsReusable = false
                    }

                    self.lock.unlock()

                    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    llamaPerf("[runtime][generate] preReset FAILED rc=\(preResetRC) elapsed=\(elapsedMs)ms mode=\(cfg.promptMode)")

                    throw LlamaBridgeError.generateFailed(code: preResetRC)
                }

            case .promptScaffoldCheckpointReplay:
                llamaPerf("[runtime][generate] resetMode=SCAFFOLD_CHECKPOINT_REPLAY mode=\(cfg.promptMode)")
                preResetRC = anum_llama_reset(localCtx, ANUM_RESET_SCAFFOLD_CHECKPOINT_REPLAY)

                if preResetRC != 0 {
                    self.lock.lock()
                    self.isGenerating = false
                    if cfg.seqId == 0 {
                        self.seq0StateIsReusable = false
                    }

                    if self.destroyWhenIdle {
                        self.destroyWhenIdle = false
                        self.backgroundDestroyWorkItem?.cancel()
                        self.backgroundDestroyWorkItem = nil

                        if let c = self.ctx {
                            anum_llama_destroy(c)
                            self.ctx = nil
                        }

                        self.loadedModelPath = nil
                        self.seq0StateIsReusable = false
                    }

                    self.lock.unlock()

                    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    llamaPerf("[runtime][generate] preReset FAILED rc=\(preResetRC) elapsed=\(elapsedMs)ms mode=\(cfg.promptMode)")

                    throw LlamaBridgeError.generateFailed(code: preResetRC)
                }

            case .prefixCachedReplay:
                llamaPerf("[runtime][generate] resetMode=NONE mode=prefixCachedReplay")

            case .scaffoldIngest, .warmTurnIngest, .continueFromState:
                break
            }

            llamaPerf(
                "[runtime][generate] nativeBegin seq=\(cfg.seqId) " +
                "promptChars=\(cfg.prompt.count) maxTokens=\(cfg.maxTokens) " +
                "mode=\(cfg.promptMode) preResetRC=\(preResetRC)"
            )

            var captureFlag = UInt32(0)
            if cfg.capturePromptEndCheckpoint {
                captureFlag |= UInt32(ANUM_GENERATE_EX_FLAG_CAPTURE_PROMPT_CHECKPOINT)
            }
            if cfg.captureScaffoldCheckpoint {
                captureFlag |= UInt32(ANUM_GENERATE_EX_FLAG_CAPTURE_SCAFFOLD_CHECKPOINT)
            }

            let scaffoldPrefix = cfg.scaffoldPromptPrefix
            let rc: Int32 = cfg.prompt.withCString { promptC in
                if let sp = scaffoldPrefix, !sp.isEmpty {
                    return sp.withCString { scaffoldC in
                        anum_llama_generate_ex_flags_ext(
                            localCtx,
                            promptC,
                            scaffoldC,
                            cfg.maxTokens,
                            cfg.seqId,
                            captureFlag,
                            cb,
                            userData
                        )
                    }
                }
                return anum_llama_generate_ex_flags_ext(
                    localCtx,
                    promptC,
                    nil,
                    cfg.maxTokens,
                    cfg.seqId,
                    captureFlag,
                    cb,
                    userData
                )
            }

            self.lock.lock()
            self.isGenerating = false

            if cfg.seqId == 0 {
                self.seq0StateIsReusable = (rc == 0)
            }

            if self.destroyWhenIdle {
                self.destroyWhenIdle = false
                self.backgroundDestroyWorkItem?.cancel()
                self.backgroundDestroyWorkItem = nil

                if let c = self.ctx {
                    anum_llama_destroy(c)
                    self.ctx = nil
                }

                self.loadedModelPath = nil
                self.seq0StateIsReusable = false
            }

            let reusable = self.seq0StateIsReusable
            self.lock.unlock()

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf(
                "[runtime][generate] nativeEnd rc=\(rc) elapsed=\(elapsedMs)ms " +
                "seqReusable=\(reusable) preResetRC=\(preResetRC) mode=\(cfg.promptMode)"
            )

            return rc
        }
    }

    func ingestScaffold(cfg: LlamaStreamConfig, scaffold: String) throws {
        let start = CFAbsoluteTimeGetCurrent()

        try withQueue(qos: QOS_CLASS_UTILITY) {
            self.lock.lock()

            guard let localCtx = self.ctx else {
                self.lock.unlock()
                throw LlamaBridgeError.failedToCreateContext(modelPath: cfg.modelPath)
            }

            if self.isGenerating {
                self.lock.unlock()
                throw LlamaBridgeError.runtimeBusy
            }

            self.isGenerating = true
            self.lock.unlock()

            let preResetRC = self.preResetForScaffoldIngest(
                localCtx: localCtx,
                callSite: "ingestScaffold"
            )

            if preResetRC != 0 {
                self.lock.lock()
                self.isGenerating = false

                if cfg.seqId == 0 {
                    self.seq0StateIsReusable = false
                }

                if self.destroyWhenIdle {
                    self.destroyWhenIdle = false
                    self.backgroundDestroyWorkItem?.cancel()
                    self.backgroundDestroyWorkItem = nil

                    if let c = self.ctx {
                        anum_llama_destroy(c)
                        self.ctx = nil
                    }

                    self.loadedModelPath = nil
                    self.seq0StateIsReusable = false
                }

                self.lock.unlock()

                let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                llamaPerf(
                    "[runtime][ingestScaffold] preReset FAILED " +
                    "rc=\(preResetRC) elapsed=\(elapsedMs)ms seq=\(cfg.seqId)"
                )

                throw LlamaBridgeError.ingestFailed(code: preResetRC)
            }

            llamaPerf(
                "[runtime][ingestScaffold] nativeBegin seq=\(cfg.seqId) " +
                "chars=\(scaffold.count) preResetRC=\(preResetRC)"
            )

            let rc: Int32 = scaffold.withCString { promptC in
                anum_llama_ingest_ex(localCtx, promptC, cfg.seqId)
            }

            self.lock.lock()
            self.isGenerating = false

            if cfg.seqId == 0 {
                self.seq0StateIsReusable = (rc == 0)
            }

            if self.destroyWhenIdle {
                self.destroyWhenIdle = false
                self.backgroundDestroyWorkItem?.cancel()
                self.backgroundDestroyWorkItem = nil

                if let c = self.ctx {
                    anum_llama_destroy(c)
                    self.ctx = nil
                }

                self.loadedModelPath = nil
                self.seq0StateIsReusable = false
            }

            let reusable = self.seq0StateIsReusable
            self.lock.unlock()

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf(
                "[runtime][ingestScaffold] nativeEnd rc=\(rc) elapsed=\(elapsedMs)ms " +
                "seqReusable=\(reusable) preResetRC=\(preResetRC)"
            )

            if rc != 0 {
                throw LlamaBridgeError.ingestFailed(code: rc)
            }
        }
    }

    func ingestTurn(cfg: LlamaStreamConfig, turnText: String) throws {
        let start = CFAbsoluteTimeGetCurrent()

        try withQueue(qos: QOS_CLASS_UTILITY) {
            self.lock.lock()
            guard let localCtx = self.ctx else {
                self.lock.unlock()
                throw LlamaBridgeError.failedToCreateContext(modelPath: cfg.modelPath)
            }

            if self.isGenerating {
                self.lock.unlock()
                throw LlamaBridgeError.runtimeBusy
            }

            if cfg.seqId == 0 && !self.seq0StateIsReusable {
                self.lock.unlock()
                throw LlamaBridgeError.ingestFailed(code: -7)
            }

            self.isGenerating = true
            self.lock.unlock()

            llamaPerf("[runtime][ingestTurn] nativeBegin seq=\(cfg.seqId) chars=\(turnText.count)")

            let rc: Int32 = turnText.withCString { promptC in
                anum_llama_ingest_ex(localCtx, promptC, cfg.seqId)
            }

            self.lock.lock()
            self.isGenerating = false
            if cfg.seqId == 0 {
                self.seq0StateIsReusable = (rc == 0)
            }

            if self.destroyWhenIdle {
                self.destroyWhenIdle = false
                self.backgroundDestroyWorkItem?.cancel()
                self.backgroundDestroyWorkItem = nil

                if let c = self.ctx {
                    anum_llama_destroy(c)
                    self.ctx = nil
                }

                self.loadedModelPath = nil
                self.seq0StateIsReusable = false
            }
            self.lock.unlock()

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[runtime][ingestTurn] nativeEnd rc=\(rc) elapsed=\(elapsedMs)ms seqReusable=\(self.seq0StateIsReusable)")

            if rc != 0 {
                throw LlamaBridgeError.ingestFailed(code: rc)
            }
        }
    }

    func continueGeneration(cfg: LlamaStreamConfig, userData: UnsafeMutableRawPointer) throws -> Int32 {
        let start = CFAbsoluteTimeGetCurrent()

        let cb: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer) -> Void = { cstr, ud in
            let ctx = Unmanaged<CallbackContext>.fromOpaque(ud).takeUnretainedValue()

            guard let cstr else {
                let flushed = drainUTF8Buffer(&ctx.utf8Carry)
                if !flushed.isEmpty { ctx.box.yield(flushed) }
                ctx.utf8Carry.removeAll(keepingCapacity: true)
                ctx.box.cancel()
                ctx.gate.finish()
                return
            }

            if cstr.pointee == 0 {
                let flushed = drainUTF8Buffer(&ctx.utf8Carry)
                if !flushed.isEmpty { ctx.box.yield(flushed) }
                ctx.utf8Carry.removeAll(keepingCapacity: true)
                ctx.box.cancel()
                ctx.gate.finish()
                return
            }

            if !ctx.sawFirstToken {
                ctx.sawFirstToken = true
                let len = strnlen(cstr, 4096)
                let ttftMs = ctx.trace.elapsedMs()
                llamaDebug("cb: first token received (continue len=\(len))")
                llamaPerf("\(ctx.trace.prefix("ttft")) ttft=\(ttftMs)ms firstChunkBytes=\(len)")
            }

            let len = Int(strnlen(cstr, 16384))
            if len > 0 {
                let data = Data(bytes: cstr, count: len)
                ctx.utf8Carry.append(contentsOf: data)
                let drained = drainUTF8Buffer(&ctx.utf8Carry)
                if !drained.isEmpty {
                    ctx.box.yield(drained)
                }
            }
        }

        return try withQueue(qos: QOS_CLASS_USER_INITIATED) {
            self.lock.lock()
            guard let localCtx = self.ctx else {
                self.lock.unlock()
                throw LlamaBridgeError.failedToCreateContext(modelPath: cfg.modelPath)
            }

            if self.isGenerating {
                self.lock.unlock()
                throw LlamaBridgeError.runtimeBusy
            }

            if cfg.seqId == 0 && !self.seq0StateIsReusable {
                self.lock.unlock()
                throw LlamaBridgeError.continueFailed(code: -8)
            }

            self.isGenerating = true
            self.lock.unlock()

            llamaPerf("[runtime][continueGeneration] nativeBegin seq=\(cfg.seqId) promptChars=\(cfg.prompt.count) maxTokens=\(cfg.maxTokens)")

            let rc = cfg.prompt.withCString { promptC in
                anum_llama_continue_ex(
                    localCtx,
                    promptC,
                    cfg.maxTokens,
                    cfg.seqId,
                    cb,
                    userData
                )
            }

            self.lock.lock()
            self.isGenerating = false
            if cfg.seqId == 0 {
                self.seq0StateIsReusable = (rc == 0)
            }

            if self.destroyWhenIdle {
                self.destroyWhenIdle = false
                self.backgroundDestroyWorkItem?.cancel()
                self.backgroundDestroyWorkItem = nil

                if let c = self.ctx {
                    anum_llama_destroy(c)
                    self.ctx = nil
                }

                self.loadedModelPath = nil
                self.seq0StateIsReusable = false
            }
            self.lock.unlock()

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[runtime][continueGeneration] nativeEnd rc=\(rc) elapsed=\(elapsedMs)ms seqReusable=\(self.seq0StateIsReusable)")
            return rc
        }
    }
    
    func kernelWarmup(cfg: LlamaStreamConfig) throws {
        let start = CFAbsoluteTimeGetCurrent()

        let cb: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer) -> Void = { _, _ in
            // Intentionally discard all callback output.
            // This pass exists only to wake tokenizer/context/Metal/runtime paths.
        }

        final class DummyCallbackBox {
            var value: Int = 0
        }

        let dummy = Unmanaged.passRetained(DummyCallbackBox())
        defer { dummy.release() }

        try withQueue(qos: QOS_CLASS_UTILITY) {
            self.lock.lock()
            guard let localCtx = self.ctx else {
                self.lock.unlock()
                throw LlamaBridgeError.failedToCreateContext(modelPath: cfg.modelPath)
            }

            if self.isGenerating {
                self.lock.unlock()
                throw LlamaBridgeError.runtimeBusy
            }

            self.isGenerating = true
            self.lock.unlock()

            // Valid tiny ChatML prompt.
            // Do not use raw " " because that dirties seq state with meaningless text
            // and triggers "missing recognized chat markers".
            let prompt = """
    <|im_start|>system
    warmup
    <|im_end|>
    <|im_start|>assistant

    """

            llamaPerf("[runtime][kernelWarmup] nativeBegin seq=\(cfg.seqId) promptChars=\(prompt.count) maxTokens=0")

            let rc: Int32 = prompt.withCString { promptC in
                anum_llama_generate_ex(
                    localCtx,
                    promptC,
                    0,
                    cfg.seqId,
                    cb,
                    dummy.toOpaque()
                )
            }

            // Critical:
            // Qwen3.5 has recurrent/SSM state. KV reset may not fully clean the dummy prompt.
            // FULL reset frees/recreates llama_context while keeping the loaded model alive.
            // This preserves compiled Metal pipelines but guarantees real scaffold starts clean.
            let resetRC = anum_llama_reset(localCtx, ANUM_RESET_FULL)

            self.lock.lock()
            self.isGenerating = false
            // Native handle was recreated; treat like a fresh context for the next scaffold ingest.
            self.contextIsFreshForScaffoldIngest = (resetRC == 0)

            // Kernel warmup must never make seq0 reusable.
            // Only a real scaffold ingest/full replay should mark seq0 reusable.
            if cfg.seqId == 0 {
                self.seq0StateIsReusable = false
            }

            if self.destroyWhenIdle {
                self.destroyWhenIdle = false
                self.backgroundDestroyWorkItem?.cancel()
                self.backgroundDestroyWorkItem = nil

                if let c = self.ctx {
                    anum_llama_destroy(c)
                    self.ctx = nil
                }

                self.loadedModelPath = nil
                self.seq0StateIsReusable = false
            }

            self.lock.unlock()

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            llamaPerf("[runtime][kernelWarmup] nativeEnd rc=\(rc) resetRC=\(resetRC) elapsed=\(elapsedMs)ms reset=FULL seqReusable=false")

            if resetRC != 0 {
                throw LlamaBridgeError.generateFailed(code: resetRC)
            }

            if rc != 0 && rc != -9 {
                throw LlamaBridgeError.generateFailed(code: rc)
            }
        }
    }

    func warmup(cfg: LlamaStreamConfig, promptOverride: String? = nil) throws {
        let start = CFAbsoluteTimeGetCurrent()
        let overrideRaw = promptOverride ?? ""
        let overrideIsEffectivelyEmpty = overrideRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !overrideIsEffectivelyEmpty else {
            llamaDebug("warmup() skip: no promptOverride")
            llamaPerf("[runtime][warmup] skip noPromptOverride")
            return
        }

        try ingestScaffold(cfg: cfg, scaffold: overrideRaw)
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        llamaPerf("[runtime][warmup] done elapsed=\(elapsedMs)ms chars=\(overrideRaw.count)")
    }

    func requestAbort() {
        let start = CFAbsoluteTimeGetCurrent()
        self.lock.lock()
        let local = self.ctx
        self.lock.unlock()

        if let c = local {
            anum_llama_abort(c)
        }

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        llamaPerf("[runtime][requestAbort] done elapsed=\(elapsedMs)ms hasCtx=\(local != nil)")
    }

    func requestAbortAndDrain(timeout: TimeInterval) {
        let start = CFAbsoluteTimeGetCurrent()
        requestAbort()

        let sem = DispatchSemaphore(value: 0)
        workQueue.async {
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + timeout)

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        llamaPerf("[runtime][requestAbortAndDrain] done elapsed=\(elapsedMs)ms timeoutMs=\(Int(timeout * 1000))")
    }

    fileprivate func getLoadedModelPath() -> String? {
        lock.lock()
        let p = loadedModelPath
        lock.unlock()
        return p
    }
}
