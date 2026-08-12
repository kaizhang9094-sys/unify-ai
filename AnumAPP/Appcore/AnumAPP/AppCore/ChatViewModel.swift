import Foundation
import Combine
import AnumCore
import LlamaCppBridge
import InnerSelfCore
import CryptoKit
import os

#if canImport(UIKit)
import UIKit
#endif

// MARK: - DEBUG helpers
@inline(__always) private func dbgFlag(_ key: String) -> Bool {
    #if DEBUG
    return UserDefaults.standard.bool(forKey: key)
    #else
    return false
    #endif
}

@inline(__always) private func secretaryDebugLog(_ s: String) {
    #if DEBUG
    print("[SEC][Chat] \(s)")
    #endif
}

@inline(__always) private func dbgPrint(_ s: String) {
    #if DEBUG
    print(s)
    #endif
}


@inline(__always) private func dbgClip(_ s: String, _ max: Int) -> String {
    if s.count <= max { return s }
    return String(s.prefix(max)) + "…"
}

private extension String {
    /// Extracts the first valid JSON object/array from noisy model output.
    /// Important: this does NOT know about, remove, or special-case Qwen <think> tags.
    /// It only looks for a syntactically valid JSON payload.
    @inline(__always) func extractingFirstJSONPayload() -> String {
        let source = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }

        let chars = Array(source)
        let starts: [Character] = ["{", "["]

        for startIndex in chars.indices where starts.contains(chars[startIndex]) {
            let open = chars[startIndex]
            let close: Character = (open == "{") ? "}" : "]"

            var depth = 0
            var inString = false
            var escaping = false

            var i = startIndex
            while i < chars.count {
                let ch = chars[i]

                if inString {
                    if escaping {
                        escaping = false
                    } else if ch == "\\" {
                        escaping = true
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
                            let candidate = String(chars[startIndex...i])
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            if let data = candidate.data(using: .utf8),
                               (try? JSONSerialization.jsonObject(with: data)) != nil {
                                return candidate
                            }

                            break
                        }
                    }
                }

                i += 1
            }
        }

        return source
    }
}

private extension String {
    /// Strips common markdown code fences (``` / ```json) from model outputs so we can decode raw JSON.
    /// Safe to call from detached/background tasks.
    @inline(__always) func strippingModelJSONFences() -> String {
        var t = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading ``` or ```json fence
        if t.hasPrefix("```") {
            // Drop first line (``` or ```json)
            if let firstNewline = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: firstNewline)...])
            } else {
                // If it's only a fence, return empty
                return ""
            }

            // Drop trailing ``` fence (if present)
            if let r = t.range(of: "```", options: .backwards) {
                t.removeSubrange(r)
            }

            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Some models might emit a leading `json` token on its own line.
        if t.lowercased().hasPrefix("json\n") {
            t = String(t.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if t.lowercased() == "json" {
            t = ""
        }

        return t
    }
}

extension Notification.Name {
    static let secretaryWorkspaceShouldRefresh = Notification.Name("secretaryWorkspaceShouldRefresh")
}

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Equatable, Codable {
    var id: UUID
    let role: ChatRole
    var text: String
    
    init(id: UUID = UUID(), role: ChatRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

// Background realm-state shaper DTO (kept out of @MainActor types so it can be decoded off-main).
struct RealmBackgroundDTO: Codable, Sendable {
    var noop: Bool?
    var confidence: Double?
    var statePatch: StatePatch?

    struct StatePatch: Codable, Sendable {
        var location: String?
        var motif: String?
        var arc: String?
    }
}


// Transcript persistence DTO (kept out of @MainActor so it can be encoded/decoded off-main).
private struct TranscriptEnvelope: Codable, Sendable {
    var version: Int
    var savedAt: Date
    var messages: [ChatMessage]
    var sessionSummary: String?
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var input: String = ""
    @Published private(set) var messages: [ChatMessage] = [
        .init(role: .assistant, text: "I'm here.")
    ]
    @Published private(set) var isBusy: Bool = false

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AnumAPP",
                             category: "ChatViewModel")

    private let orchestrator: Orchestrator
    
    private let useLlamaBridge: Bool = true

    private let modelStore = ModelStore.shared
    private let identityVault = IdentityVault.shared

    private var generationTask: Task<Void, Never>?
    
    // MARK: - Post-turn maintenance control

    /// Handle for post-turn maintenance so we can cancel it when a new user turn starts.
    private var postTurnTask: Task<Void, Never>?

    /// Dedup guard so postTurn is not scheduled multiple times for the same (turnId, epoch).
    private var lastPostTurnKey: String = ""
    
    /// Handle for the post-turn IdentityLearner task so we can cancel it when a new user turn starts.
    private var identityLearnerTask: Task<Void, Never>?

    /// Dedup guard so IdentityLearner is not started multiple times for the same (turnId, epoch).
    private var lastIdentityLearnerKey: String = ""

    // Finish-once guard (prevents double turnFinished across watchdog + normal paths)
    private var finishedTurnIds: Set<UUID> = []
    private var finishedTurnOrder: [UUID] = []
    private let finishedTurnMax: Int = 32
    
    // MARK: - Symbiotic Realm (proactive seed; TTFT-safe)

    /// Use a VM-wired store (NOT `.shared`) so the realm can derive from session summary + identity + memory hints.
    private lazy var realmStore: SymbioticRealmStore = SymbioticRealmStore(contextProvider: self)

    /// Cached tiny hints reused from already-built artifacts (no extra model calls, no extra TTFT).
    private var lastMemoryHint: String = ""
    private var lastIdentityHint: String = ""

    /// Realm seed cadence: allow one seed per finished turn (no global cooldown).
    /// We rely on RealmStore’s own trimming/caps to avoid unbounded growth.
    private var lastRealmSeedTurnId: UUID?

    /// Background realm state shaping cadence (rare; must not affect TTFT).
    private var lastRealmBackgroundAt: Date = .distantPast
    /// Handle for the background realm task so we can cancel it when a new user turn starts.
    private var realmBackgroundTask: Task<Void, Never>?
    
    // MARK: - Rehydration (Phase: 3)

    // ---- Session Summary for continuity ----
    /// Stores a compact session summary for continuity injection.
    private var sessionSummary: String = ""

    // MARK: - Transcript persistence (Phase: 1)

    private var saveTask: Task<Void, Never>?
    private let saveDebounceNanos: UInt64 = 500_000_000 // 0.5s

    /// Cached transcript file URL to avoid repeated directory work on the main thread.
    private var cachedTranscriptURL: URL?

    /// Last in-flight background write task (best-effort ordering).
    private var backgroundSaveTask: Task<Void, Never>?

    // MARK: - Generation lifecycle safety (Phase: 2)

    private var generationEpoch: UInt64 = 0
    private var isCancelling: Bool = false
    
    // MARK: - Runtime-owned prompt state (hot-path stability)

    private enum RuntimeStateMode: Equatable {
        case cold
        case warm
        case invalidated
    }

    private struct RuntimeScaffoldSnapshot {
        let scaffoldText: String
        let scaffoldHash: String
        let hotHeaderText: String
        let hotHeaderHash: String
        let composedSystemText: String
    }

    private var runtimeStateMode: RuntimeStateMode = .cold

    // Tiny hot-path continuation cache
    private var lastLateAugmentationHash: String = ""

    /// Last scaffold hash successfully ingested into the warm runtime (prefix prime or post-turn warm).
    /// Used to block warm incremental turns when the composed scaffold changed without a matching ingest.
    private var lastCompanionIngestedScaffoldHash: String = ""

    private enum CompanionEntryReason: String {
        case bootstrap = "ui_bootstrap_companion"
        case afterSecretary = "ui_enter_companion_after_secretary"
    }
    
    // MARK: - Bridge hard reset (for watchdog stalls)

    /// Best-effort hard reset for llama.cpp streaming when cancellation doesn’t unwind the underlying bridge.
    /// This is only invoked on user cancel / watchdog stall paths.
    private func forceResetBridge(reason: String) async {
        #if DEBUG
        print("[ChatViewModel] bridge RESET reason=\(reason)")
        #endif

        // Ensure we resume with a valid modelPath so prewarm/resume never fails due to missing path.
        // Try to resolve the model path (best-effort). If it cannot be resolved, do not mutate bridge state.
        var modelURL: URL? = nil

        do {
            modelURL = try self.modelStore.beginAccessingModel()
        } catch {
            // If first-install staging is in progress, wait once and retry.
            await self.modelStore.ensureReady()
            do {
                modelURL = try self.modelStore.beginAccessingModel()
            } catch {
                #if DEBUG
                print("[ChatViewModel] bridge RESET aborted: cannot access model err=\(error)")
                #endif
                return
            }
        }

        let path = modelURL!.path
        defer { self.modelStore.stopAccessing(modelURL!) }

        // Interrupt a stuck stream and restore forward progress.
        LlamaCppBridge.pauseForBackground()
        LlamaCppBridge.resumeAfterBackground(modelPath: path)
        self.invalidateWarmRuntime(reason: reason)
    }

    private func performGuardedRecovery(
        reason: String,
        expectedStreamLabelPrefix: String? = nil,
        allowLastResort: Bool = false
    ) async {
        let streamSnapshotBefore = await AIRuntimeStreamGate.shared.snapshot()
        let modeSnapshotBefore = await AIRuntimeModeGate.shared.snapshot()

        let streamLabel = streamSnapshotBefore.ownerLabel ?? "nil"
        let streamOwner = streamSnapshotBefore.ownerID?.uuidString ?? "nil"
        let modeLabel = modeSnapshotBefore.activeMode?.rawValue ?? "nil"
        let modeOwner = modeSnapshotBefore.ownerID?.uuidString ?? "nil"

        let streamMatchesExpected: Bool = {
            guard let expectedStreamLabelPrefix else { return true }
            guard let ownerLabel = streamSnapshotBefore.ownerLabel else { return false }
            return ownerLabel.hasPrefix(expectedStreamLabelPrefix)
        }()

        let shouldForce = allowLastResort || streamMatchesExpected

        log.notice(
            "recovery start reason=\(reason, privacy: .public) streamLabel=\(streamLabel, privacy: .public) streamOwner=\(streamOwner, privacy: .public) mode=\(modeLabel, privacy: .public) modeOwner=\(modeOwner, privacy: .public) action=\(shouldForce ? "force" : "skip", privacy: .public)"
        )

        if !shouldForce {
            return
        }

        await AIRuntimeStreamGate.shared.forceUnlock(reason: reason)
        await AIRuntimeModeGate.shared.forceReset(reason: reason)

        let streamSnapshotAfter = await AIRuntimeStreamGate.shared.snapshot()
        let modeSnapshotAfter = await AIRuntimeModeGate.shared.snapshot()
        let streamAfter = streamSnapshotAfter.ownerLabel ?? "nil"
        let modeAfter = modeSnapshotAfter.activeMode?.rawValue ?? "nil"
        log.notice(
            "recovery done reason=\(reason, privacy: .public) streamLabel=\(streamAfter, privacy: .public) mode=\(modeAfter, privacy: .public)"
        )
    }

    // MARK: - Turn watchdog (fundamental fix for missing turnFinished)

    private var activeTurnId: UUID?
    private var activeTurnEpoch: UInt64 = 0
    private var activeTurnStartedAt: Date = .distantPast
    private var activeTurnLastChunkAt: Date = .distantPast
    private var turnWatchdogTask: Task<Void, Never>?

    // MARK: - ExchangeEngine

    var exchangeChatBridge: ExchangeChatBridge?
    var exchangeFacade: ExchangeFacade?
    weak var appServices: AppServices?
    private var activeExchangeThreadID: ExchangeThread.ID?
    private var secretaryTask: Task<Void, Never>?
    @Published private(set) var isSecretaryBusy: Bool = false
    
    private var secretaryEpoch: UInt64 = 0
    private var secretaryWarmThreadID: ExchangeThread.ID?

    /// Retains the Combine subscription that watches IdentityVault for external scaffold changes.
    /// When the prologue or onboarding fields change, the warm KV state is stale and must be invalidated.
    private var scaffoldVersionCancellable: AnyCancellable?

    /// Retains the Combine subscription for LlamaExchangeModelRunner's native state invalidation.
    /// Most secretary jobs invalidate runtime state after completion; successful Direct Chat reply
    /// suggestions preserve checkpoint state for fast reuse. When posted, this keeps the Swift-side
    /// runtimeStateMode in sync so companion warm-path attempts don't fail silently.
    private var nativeStateInvalidationCancellable: AnyCancellable?
    
    init() {
        // NOTE: Do not use a default-argument expression here.
        // Default arguments are evaluated outside the actor context,
        // which triggers “Call to main actor-isolated initializer …”.
        self.orchestrator = AppOrchestrator(model: StubModelProvider())
        
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif

        self.bootstrapTranscriptAsync()
        log.info("loadTranscript scheduled")

        // When IdentityVault detects a real external scaffold input change (companionPrologue,
        // onboarding fields, etc.), the llama warm KV cache is stale. Force a full replay on
        // the next companion send so the updated scaffold is re-ingested from scratch.
        scaffoldVersionCancellable = identityVault.$externalScaffoldVersion
            .dropFirst()
            .sink { [weak self] _ in
                self?.invalidateWarmRuntime(reason: "identity_scaffold_changed")
            }

        // When LlamaExchangeModelRunner invalidates after most secretary jobs (not successful
        // Direct Chat reply), sync the Swift-side warm flag so the next companion send skips the warm
        // path attempt and goes straight to full replay, avoiding a latency-adding fallback.
        nativeStateInvalidationCancellable = NotificationCenter.default
            .publisher(for: RuntimeNotifications.llamaRuntimeStateInvalidatedName)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.log.info("runtime invalidation notification received source=secretary_runner")
                self?.invalidateWarmRuntime(reason: "native_runtime_invalidated_by_secretary")
            }

        // Phase 6: opportunistic memory map refresh on launch (no-op if not eligible).
        Task { [weak self] in
            guard let self else { return }
            await self.kickMemoryMapRefresh(force: false)
            // Phase 7: proposal engine is input-driven; launch run is a no-op unless recentText is provided.
            await self.kickIdentityProposal(force: false, recentUserText: "", recentAssistantText: "", turnId: nil)
        }
    }

    init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator

        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif

        self.bootstrapTranscriptAsync()
        log.info("loadTranscript scheduled")

        // Same scaffold-version wiring as the primary init.
        scaffoldVersionCancellable = identityVault.$externalScaffoldVersion
            .dropFirst()
            .sink { [weak self] _ in
                self?.invalidateWarmRuntime(reason: "identity_scaffold_changed")
            }

        // When LlamaExchangeModelRunner invalidates after most secretary jobs (not successful
        // Direct Chat reply), sync the Swift-side warm flag so the next companion send skips the warm
        // path attempt and goes straight to full replay, avoiding a latency-adding fallback.
        nativeStateInvalidationCancellable = NotificationCenter.default
            .publisher(for: RuntimeNotifications.llamaRuntimeStateInvalidatedName)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.log.info("runtime invalidation notification received source=secretary_runner")
                self?.invalidateWarmRuntime(reason: "native_runtime_invalidated_by_secretary")
            }

        // Phase 6: opportunistic memory map refresh on launch (no-op if not eligible).
        Task { [weak self] in
            guard let self else { return }
            await self.kickMemoryMapRefresh(force: false)
            // Phase 7: proposal engine is input-driven; launch run is a no-op unless recentText is provided.
            await self.kickIdentityProposal(force: false, recentUserText: "", recentAssistantText: "", turnId: nil)
        }
    }

    var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var statusText: String {
        isBusy ? "Thinking…" : "Ready"
    }

    var isAnyBusy: Bool {
        isBusy || isSecretaryBusy
    }

    var currentSecretaryThreadID: ExchangeThread.ID? {
        activeExchangeThreadID
    }
    
    private func requestSecretaryWorkspaceRefresh(
        threadID: ExchangeThread.ID? = nil,
        userText: String? = nil,
        source: String? = nil
    ) {
        var userInfo: [String: Any] = [:]
        if let threadID {
            userInfo["threadID"] = threadID.uuidString
            userInfo["secretaryRefreshReason"] = SecretaryRefreshReason.threadChanged.rawValue
        }
        if let source {
            userInfo["source"] = source
        }
        if let userText {
            let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                userInfo["userText"] = String(trimmed.prefix(200))
            }
        }
        NotificationCenter.default.post(
            name: .secretaryWorkspaceShouldRefresh,
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }

    @MainActor
    private func recordSuccessfulExchangeSubmit(
        threadID: ExchangeThread.ID,
        userText: String,
        detail: ExchangeModels.ThreadDetail,
        progressGeneration: UInt64
    ) {
        #if DEBUG
        let preview = userText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        print(
            "[RecentSearchTrace][submit] threadID=\(threadID.uuidString) " +
            "userText=\(String(preview.prefix(120))) reason=localSubmit"
        )
        #endif
        let stripItem: ExchangeModels.InboxItem? = Self.isTerminalStripSearchState(detail.thread.state)
            ? SecretarySearchResultProjection.buildImmediateStripInboxItem(
                detail: detail,
                capturedRequestText: userText
            )
            : nil
        appServices?.recordLocalSearchSubmitHandoff(
            threadID: threadID,
            userText: userText,
            stripItem: stripItem
        )
        if Self.isTerminalStripSearchState(detail.thread.state) {
            appServices?.endDiscoveryHeroProgress(
                generation: progressGeneration,
                reason: "submitTerminalResult"
            )
        }
        requestSecretaryWorkspaceRefresh(
            threadID: threadID,
            userText: userText,
            source: "localSubmit"
        )
    }

    private static func isTerminalStripSearchState(_ state: ExchangeState) -> Bool {
        switch state {
        case .noViableMatch, .matchCandidatesWeak, .matchFound:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Phase 6 wiring (Memory Map)

    #if canImport(UIKit)
    private var isDeviceCharging: Bool {
        let s = UIDevice.current.batteryState
        return s == .charging || s == .full
    }
    #else
    private var isDeviceCharging: Bool { true }
    #endif

    private func kickMemoryMapRefresh(force: Bool) async {
        // Default behavior: charging-only, daily cadence.
        // In DEBUG you may allow on-battery builds for quicker iteration.
        #if DEBUG
        let allowOnBattery = true
        #else
        let allowOnBattery = false
        #endif

        await MemoryStore.shared.runMemoryMapIfEligible(
            isCharging: isDeviceCharging,
            allowOnBattery: allowOnBattery,
            cadenceHours: 24.0,
            force: force
        )
    }

    // MARK: - Phase 7 wiring (Identity proposals)

    private func kickIdentityProposal(force: Bool, recentUserText: String, recentAssistantText: String, turnId: UUID?) async {
        // Self-learning behavior: we pass a compact “evidence bundle” to IdentityVault.
        // IdentityVault can use an LLM-powered proposer to decide what (if anything) to propose.
        // ChatViewModel only supplies evidence + gating inputs; it does NOT auto-apply.

        // Default behavior: charging-only, daily cadence.
        // In DEBUG we shorten cadence so you can see proposals during active iteration.
        #if DEBUG
        let allowOnBattery = true
        // Keep a non-zero cadence in practice to avoid thrash; IdentityVault should only stamp cadence when it actually enqueues a proposal.
        let cadenceHours: Double = (1.0 / 60.0) // 1 minute
        #else
        let allowOnBattery = false
        let cadenceHours: Double = 24.0
        #endif

        // Evidence bundle: keep it small and deterministic.
        let u = recentUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = recentAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Guard: if there's no new user text, there is no evidence.
        // (IdentityVault will treat empty as a no-op anyway, but this keeps logs cleaner.)
        if u.isEmpty {
            #if DEBUG
            let tid = turnId?.uuidString ?? "nil"
            print("[ChatViewModel] kickIdentityProposal skip: empty userText force=\(force) turnId=\(tid)")
            #endif
            return
        }

        // Clip evidence sizes so it never dominates prompt-building inside the proposer.
        let uClip = String(u.prefix(300))
        let aClip = String(a.prefix(600))

        let evidence = """
[Evidence]
- TurnId: \(turnId?.uuidString ?? "-")
- User: \(uClip)
- Assistant: \(aClip)
[EndEvidence]
"""

        if dbgFlag("debug.identity.dumpEvidence") {
            dbgPrint("[ChatViewModel] IdentityEvidence turnId=\(turnId?.uuidString ?? "nil")\n" + dbgClip(evidence, 2000))
        }
        #if DEBUG
        let tid = turnId?.uuidString ?? "nil"
        print("[ChatViewModel] kickIdentityProposal force=\(force) uChars=\(u.count) aChars=\(a.count) turnId=\(tid) charging=\(isDeviceCharging) allowOnBattery=\(allowOnBattery) cadenceHours=\(cadenceHours)")
        #endif

        // Propose only (do not auto-apply). Stored in IdentityVault for later review/apply.
        self.identityVault.proposeOverlayIfEligible(
            recentText: evidence,
            evidenceTurnId: turnId,
            isCharging: isDeviceCharging,
            allowOnBattery: allowOnBattery,
            cadenceHours: cadenceHours,
            force: force
        )
        #if DEBUG
        print("[ChatViewModel] kickIdentityProposal DONE turnId=\(turnId?.uuidString ?? "nil") chars=\(u.count)")
        #endif
    }
    
    // MARK: - Prefix prefill (KV prefix cache priming)

    private var prefixPrimeTask: Task<Void, Never>? = nil
    private var lastPrefixPrimeKey: String = ""
    private var lastPrefixPrimeAt: Date = .distantPast
    private var hasPrimedPrefixThisLaunch: Bool = false
    private var companionReprimePending: Bool = false
    private var pendingCompanionPrimeTrigger: String?
    
    /// Prime the reusable companion scaffold using the bridge ingest path.
    ///
    /// Runs AFTER transcript restore / launch model readiness.
    /// Never blocks UI/TTFT and never contends with an in-flight generation.
    ///
    /// Important:
    /// - This primes scaffold only.
    /// - It does NOT include user turn.
    /// - It does NOT include assistant generation prefix.
    /// - It does NOT use `stream(maxTokens: 0)` anymore.
    /// - It uses `ingestScaffoldAndWait`, which matches runtime-owned conversation better.
    private func primePrefixCacheIfNeeded(trigger: String) {
        let modeLabel: String = {
            switch runtimeStateMode {
            case .cold: return "cold"
            case .warm: return "warm"
            case .invalidated: return "invalidated"
            }
        }()
        let hasModelPath = !self.modelStore.modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        log.info(
            "prefix prime start trigger=\(trigger, privacy: .public) mode=\(modeLabel, privacy: .public) isBusy=\(self.isBusy, privacy: .public) isSecretaryBusy=\(self.isSecretaryBusy, privacy: .public) isCancelling=\(self.isCancelling, privacy: .public) modelPathAvailable=\(hasModelPath, privacy: .public)"
        )
        // Do not prime while a turn is running/cancelling.
        if isBusy || isSecretaryBusy || isCancelling {
            log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=busy")
            companionReprimePending = false
            pendingCompanionPrimeTrigger = nil
            return
        }
        if !hasModelPath {
            log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=model_missing")
            companionReprimePending = false
            pendingCompanionPrimeTrigger = nil
            return
        }
        if !useLlamaBridge {
            log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=model_missing")
            companionReprimePending = false
            pendingCompanionPrimeTrigger = nil
            return
        }
        if runtimeStateMode == .warm {
            log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=already_warm")
            companionReprimePending = false
            pendingCompanionPrimeTrigger = nil
            return
        }

        if hasPrimedPrefixThisLaunch && trigger != "onboarding" && trigger != "rehydrate" && trigger != "mode_switch_companion" {
            log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=already_primed_this_launch")
            companionReprimePending = false
            pendingCompanionPrimeTrigger = nil
            return
        }

        let history = self.messages

        // Dedup: identity hashes + tiny transcript tail snapshot.
        let hashes = self.identityVault.identityHashes()
        let tailSnap = history.suffix(6)
            .map { "\($0.role):" + String($0.text.prefix(120)) }
            .joined(separator: "\n")

        let key = "id=\(hashes.baselineHash)|\(hashes.overlayHash)|sum=\(String(sessionSummary.prefix(200)))|tail=\(tailSnap)|trigger=\(trigger)"

        if key == lastPrefixPrimeKey {
            log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=dedup_key")
            companionReprimePending = false
            pendingCompanionPrimeTrigger = nil
            return
        }
        lastPrefixPrimeKey = key

        prefixPrimeTask?.cancel()
        prefixPrimeTask = nil
        companionReprimePending = false
        pendingCompanionPrimeTrigger = nil

        #if DEBUG
        print("[PrefixPrime] schedule trigger=\(trigger) historyMsgs=\(history.count)")
        #endif

        prefixPrimeTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            self.log.info("prefix prime task entered trigger=\(trigger, privacy: .public)")
            #if DEBUG
            print("[PrefixPrime] task entered trigger=\(trigger)")
            #endif
            if Task.isCancelled {
                self.log.info("prefix prime cancelled trigger=\(trigger, privacy: .public) phase=task_start")
                await MainActor.run {
                    self.companionReprimePending = false
                    self.pendingCompanionPrimeTrigger = nil
                }
                return
            }

            // Give transcript / identity / RootView mode switch a moment to settle.
            try? await Task.sleep(nanoseconds: 350_000_000)

            let stillIdle = await MainActor.run {
                !self.isBusy && !self.isCancelling && !self.isSecretaryBusy
            }

            if !stillIdle || Task.isCancelled {
                self.log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=cancelled_or_not_idle")
                await MainActor.run {
                    self.companionReprimePending = false
                    self.pendingCompanionPrimeTrigger = nil
                }
                #if DEBUG
                await MainActor.run {
                    print("[PrefixPrime] skip: not idle after delay trigger=\(trigger)")
                }
                #endif
                return
            }

            let gate = AIRuntimeStreamGate.shared
            var gateLease: AIRuntimeStreamGate.Lease? = nil
            let acquireStart = Date()
            let maxWaitSeconds: Double = 2.0
            var loggedGateDeny = false

            while gateLease == nil {
                if Task.isCancelled {
                    self.log.info("prefix prime cancelled trigger=\(trigger, privacy: .public) phase=acquire_gate")
                    await MainActor.run {
                        self.companionReprimePending = false
                        self.pendingCompanionPrimeTrigger = nil
                    }
                    return
                }

                let ok = await MainActor.run {
                    !self.isBusy && !self.isCancelling && !self.isSecretaryBusy
                }

                if !ok {
                    self.log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=became_busy_before_gate")
                    await MainActor.run {
                        self.companionReprimePending = false
                        self.pendingCompanionPrimeTrigger = nil
                    }
                    #if DEBUG
                    await MainActor.run {
                        print("[PrefixPrime] skip: became busy before gate trigger=\(trigger)")
                    }
                    #endif
                    return
                }

                gateLease = await gate.tryAcquire(label: "companion.scaffoldIngestPrime")
                if gateLease != nil { break }
                if !loggedGateDeny {
                    loggedGateDeny = true
                    self.log.notice("prefix prime stream gate denied trigger=\(trigger, privacy: .public)")
                }

                let waited = Date().timeIntervalSince(acquireStart)
                if waited >= maxWaitSeconds {
                    self.log.notice(
                        "prefix prime stream gate timeout trigger=\(trigger, privacy: .public) waitedSeconds=\(String(format: "%.1f", waited), privacy: .public)"
                    )
                    await MainActor.run {
                        self.companionReprimePending = false
                        self.pendingCompanionPrimeTrigger = nil
                    }
                    #if DEBUG
                    await MainActor.run {
                        print("[PrefixPrime] skip: gate busy timedOut=\(String(format: "%.1f", waited))s trigger=\(trigger)")
                    }
                    #endif
                    return
                }

                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            func releaseGateIfNeeded() async {
                if let lease = gateLease {
                    await gate.release(lease)
                    gateLease = nil
                }
            }

            var modelURL: URL?

            do {
                modelURL = try await MainActor.run {
                    try self.modelStore.beginAccessingModel()
                }
            } catch {
                let shouldRetry = await MainActor.run {
                    if case .checking = self.modelStore.installState { return true }
                    if case .copying = self.modelStore.installState { return true }
                    return false
                }

                if shouldRetry {
                    await self.modelStore.ensureReady()

                    do {
                        modelURL = try await MainActor.run {
                            try self.modelStore.beginAccessingModel()
                        }
                    } catch {
                        self.log.error("prefix prime failed trigger=\(trigger, privacy: .public) reason=model_access_after_ensure_ready error=\(error.localizedDescription, privacy: .public)")
                        #if DEBUG
                        await MainActor.run {
                            print("[PrefixPrime] failed: cannot access model after ensureReady err=\(error)")
                        }
                        #endif

                        await releaseGateIfNeeded()
                        await MainActor.run {
                            self.companionReprimePending = false
                            self.pendingCompanionPrimeTrigger = nil
                        }
                        return
                    }
                } else {
                    self.log.error("prefix prime failed trigger=\(trigger, privacy: .public) reason=model_access error=\(error.localizedDescription, privacy: .public)")
                    #if DEBUG
                    await MainActor.run {
                        print("[PrefixPrime] failed: cannot access model err=\(error)")
                    }
                    #endif

                    await releaseGateIfNeeded()
                    await MainActor.run {
                        self.companionReprimePending = false
                        self.pendingCompanionPrimeTrigger = nil
                    }
                    return
                }
            }

            guard let modelURL else {
                self.log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=model_missing_after_access")
                await releaseGateIfNeeded()
                await MainActor.run {
                    self.companionReprimePending = false
                    self.pendingCompanionPrimeTrigger = nil
                }
                return
            }

            let resolvedModelPath = modelURL.path

            defer {
                Task { @MainActor [weak self] in
                    self?.modelStore.stopAccessing(modelURL)
                }
            }

            let scaffoldPrompt: String = await MainActor.run {
                self.launchStableScaffoldPrompt()
            }

            guard !scaffoldPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.log.info("prefix prime skipped trigger=\(trigger, privacy: .public) reason=empty_scaffold")
                #if DEBUG
                await MainActor.run {
                    print("[PrefixPrime] skip: empty scaffold trigger=\(trigger)")
                }
                #endif

                await releaseGateIfNeeded()
                await MainActor.run {
                    self.companionReprimePending = false
                    self.pendingCompanionPrimeTrigger = nil
                }
                return
            }
            self.log.info("prefix prime ingest begin trigger=\(trigger, privacy: .public) chars=\(scaffoldPrompt.count, privacy: .public)")

            #if DEBUG
            await MainActor.run {
                print(
                    "[PrefixPrime] CALL ingestScaffoldAndWait " +
                    "trigger=\(trigger) " +
                    "chars=\(scaffoldPrompt.count)"
                )
            }
            #endif

            LlamaCppBridge.resumeAfterBackground(modelPath: resolvedModelPath)

            let ok = await LlamaCppBridge.ingestScaffoldAndWait(
                modelPath: resolvedModelPath,
                scaffoldPrompt: scaffoldPrompt,
                nCtx: 2048,
                nThreads: 4,
                nBatch: 256
            )

            await releaseGateIfNeeded()

            guard ok else {
                self.log.error("prefix prime ingest failed trigger=\(trigger, privacy: .public)")
                #if DEBUG
                await MainActor.run {
                    print("[PrefixPrime] ingest scaffold failed trigger=\(trigger)")
                }
                #endif

                await MainActor.run {
                    self.invalidateWarmRuntime(reason: "prefix_prime_ingest_failed")
                    self.companionReprimePending = false
                    self.pendingCompanionPrimeTrigger = nil
                }
                return
            }

            await MainActor.run {
                self.lastPrefixPrimeAt = Date()
                self.hasPrimedPrefixThisLaunch = true
                self.noteLaunchRuntimePrepared(trigger: trigger)
                self.companionReprimePending = false
                self.pendingCompanionPrimeTrigger = nil
            }
            self.log.info("prefix prime ingest success trigger=\(trigger, privacy: .public)")
            self.log.info("prefix prime runtime mode warm trigger=\(trigger, privacy: .public)")

            #if DEBUG
            await MainActor.run {
                print("[PrefixPrime] done scaffoldIngest trigger=\(trigger)")
            }
            #endif
        }
    }

    // MARK: - Post-turn maintenance (must not affect TTFT)

    /// Runs maintenance tasks after streaming finishes. Must never block TTFT.
    private func runPostTurnMaintenance(
        forceIdentityProposal: Bool,
        userText: String,
        assistantText: String,
        turnId: UUID,
        scheduledEpoch: UInt64
    ) {
        let key = "\(turnId.uuidString)|\(scheduledEpoch)"
        if lastPostTurnKey == key {
            #if DEBUG
            print("[ChatViewModel] postTurn SKIP dedup turnId=\(turnId.uuidString) epoch=\(scheduledEpoch)")
            #endif
            return
        }
        lastPostTurnKey = key

        postTurnTask?.cancel()
        postTurnTask = nil

        #if DEBUG
        print("[ChatViewModel] postTurn SCHEDULED lightweight turnId=\(turnId.uuidString) uChars=\(userText.count) aChars=\(assistantText.count)")
        #endif

        postTurnTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if Task.isCancelled {
                self.postTurnTask = nil
                return
            }

            guard scheduledEpoch == self.generationEpoch else {
                self.postTurnTask = nil
                return
            }

            #if DEBUG
            print("[ChatViewModel] postTurn START lightweight-only turnId=\(turnId.uuidString)")
            #endif

            // Cheap/non-LLM maintenance only.
            await self.kickMemoryMapRefresh(force: false)

            guard scheduledEpoch == self.generationEpoch else {
                self.postTurnTask = nil
                return
            }

            await self.kickIdentityProposal(
                force: forceIdentityProposal,
                recentUserText: userText,
                recentAssistantText: assistantText,
                turnId: turnId
            )

            guard scheduledEpoch == self.generationEpoch else {
                self.postTurnTask = nil
                return
            }

            // Deterministic realm seed only. No llama call.
            self.maybeEnqueueRealmSeed(turnId: turnId)

            // Disabled during Qwen optimization:
            // - runIdentityLearner(...)
            // - scheduleRealmBackgroundStateGeneration(...)
            //
            // Reason: background llama calls can compete with the main chat stream,
            // confuse timing, and make TTFT/debugging harder. Re-enable later only
            // after the main warm-path is proven stable.

            self.log.info("postTurn lightweight DONE turnId=\(turnId.uuidString, privacy: .public)")

            #if DEBUG
            print("[ChatViewModel] postTurn lightweight DONE turnId=\(turnId.uuidString)")
            #endif

            self.postTurnTask = nil
        }
    }

    // MARK: - Self-learning Identity Learner (Phase 7.5)


    /// Runs a lightweight post-turn learner pass to infer stable user preferences.
    /// This MUST NOT block TTFT: call it only after the assistant finishes streaming.
    private func runIdentityLearner(
        recentText: String,
        assistantText: String,
        turnId: UUID,
        scheduledEpoch: UInt64
    ) async {
        let rt = recentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rt.isEmpty else {
            #if DEBUG
            print("[IdentityLearner] skip: empty recentText")
            #endif
            return
        }

        if scheduledEpoch != self.generationEpoch { return }

        let key = "\(turnId.uuidString)|\(scheduledEpoch)"
        if lastIdentityLearnerKey == key {
            #if DEBUG
            print("[IdentityLearner] SKIP (dedup) turn=\(turnId.uuidString) epoch=\(scheduledEpoch)")
            #endif
            return
        }
        lastIdentityLearnerKey = key

        identityLearnerTask?.cancel()
        identityLearnerTask = nil

        #if DEBUG
        print("[IdentityLearner] start turn=\(turnId.uuidString) userChars=\(rt.count) asstChars=\(assistantText.count)")
        #endif

        let learnerSystemPrompt = """
    You are an Identity Learning Engine.

    Task: infer stable, cross-session user preferences from the USER + ASSISTANT snippets. You do NOT chat.

    Rules:
    - Output JSON only (no markdown, no fences).
    - If nothing stable is learned, output {"noop": true, "proposals": []}.
    - Do NOT invent facts. Prefer stable preferences over transient mood.
    - Treat explicit user requests (e.g., “use fewer emojis”) as high-signal.
    - Keep output short (<= 120 tokens). Prefer simple categorical values.

    JSON schema (STRICT):
    {
      "noop": Bool,
      "proposals": [
        {
          "type": String,
          "key": String,
          "value": String,
          "confidence": Float
        }
      ]
    }

    """

        let asstClip = String(assistantText.prefix(400))
        let learnerUserBlock = """
    <USER>
    \(rt)
    </USER>

    <ASSISTANT>
    \(asstClip)
    </ASSISTANT>
    """

        let learnerPrompt = self.buildModelPrompt(
            system: learnerSystemPrompt,
            history: [],
            newUserText: learnerUserBlock,
            maxHistoryTurns: 0
        )

        #if DEBUG
        let hasModelPrefix: Bool
        let endsWithModel: Bool

        switch currentPromptFamily() {
        case .qwen:
            let qwenPrefix = self.qwenAssistantGenerationPrefix()
            hasModelPrefix = learnerPrompt.contains(qwenPrefix)
            endsWithModel = learnerPrompt.hasSuffix(qwenPrefix)

        case .gemma:
            hasModelPrefix = learnerPrompt.contains("<start_of_turn>model\n")
            endsWithModel = learnerPrompt.hasSuffix("<start_of_turn>model\n")
        }

        print("[IdentityLearner] prompt template ok=\(hasModelPrefix) endsWithModel=\(endsWithModel) chars=\(learnerPrompt.count)")
        #endif

        let modelURL: URL
        do {
            modelURL = try await MainActor.run {
                try self.modelStore.beginAccessingModel()
            }
        } catch {
            let shouldRetry = await MainActor.run {
                if case .checking = self.modelStore.installState { return true }
                if case .copying = self.modelStore.installState { return true }
                return false
            }

            if shouldRetry {
                await self.modelStore.ensureReady()
                do {
                    modelURL = try await MainActor.run {
                        try self.modelStore.beginAccessingModel()
                    }
                } catch {
                    #if DEBUG
                    print("[IdentityLearner] failed: cannot access model after ensureReady err=\(error)")
                    #endif
                    return
                }
            } else {
                #if DEBUG
                print("[IdentityLearner] failed: cannot access model err=\(error)")
                #endif
                return
            }
        }

        let cfg = LlamaStreamConfig(
            modelPath: modelURL.path,
            prompt: learnerPrompt,
            maxTokens: 120,
            seqId: 1
        )

        let task: Task<Void, Never> = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor [weak self] in
                    self?.modelStore.stopAccessing(modelURL)
                    self?.identityLearnerTask = nil
                }
            }

            let stillSameEpoch = await MainActor.run {
                scheduledEpoch == self.generationEpoch
            }
            if !stillSameEpoch || Task.isCancelled { return }

            let gate = AIRuntimeStreamGate.shared
            var gateLease: AIRuntimeStreamGate.Lease? = nil
            let acquireStart = Date()
            let maxWaitSeconds: Double = 1.5

            while gateLease == nil {
                if Task.isCancelled { return }

                let okEpoch = await MainActor.run {
                    scheduledEpoch == self.generationEpoch
                }
                if !okEpoch { return }

                gateLease = await gate.tryAcquire(label: "companion.identityLearner")
                if gateLease != nil { break }

                let waited = Date().timeIntervalSince(acquireStart)
                if waited >= maxWaitSeconds {
                    #if DEBUG
                    let waitedStr = String(format: "%.1f", waited)
                    print("[IdentityLearner] skip: bridge busy (timed out after \(waitedStr)s) turn=\(turnId.uuidString)")
                    #endif
                    return
                }

                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            func releaseGateIfNeeded() async {
                if let lease = gateLease {
                    await gate.release(lease)
                    gateLease = nil
                }
            }

            if Task.isCancelled {
                await releaseGateIfNeeded()
                return
            }

            let okAfterAcquire = await MainActor.run {
                scheduledEpoch == self.generationEpoch
            }
            if !okAfterAcquire {
                await releaseGateIfNeeded()
                return
            }

            #if DEBUG
            print("[IdentityLearner] CALL LlamaCppBridge.stream turn=\(turnId.uuidString) promptChars=\(learnerPrompt.count)")
            #endif

            do {
                var out = ""
                var aborted = false

                for try await chunk in LlamaCppBridge.stream(cfg) {
                    if Task.isCancelled {
                        aborted = true
                        break
                    }

                    let ok = await MainActor.run {
                        scheduledEpoch == self.generationEpoch
                    }
                    if !ok {
                        aborted = true
                        break
                    }

                    out += chunk
                    if out.count > 4096 { break }
                }

                await releaseGateIfNeeded()
                if aborted { return }

                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = await MainActor.run {
                    trimmed
                        .strippingModelJSONFences()
                        .extractingFirstJSONPayload()
                        .strippingModelJSONFences()
                }

                await MainActor.run {
                    if dbgFlag("debug.identity.dumpLearnerOutput") {
                        dbgPrint("[IdentityLearner] output(raw) turn=\(turnId.uuidString)\n" + dbgClip(trimmed, 2400))
                        if cleaned != trimmed {
                            dbgPrint("[IdentityLearner] output(clean) turn=\(turnId.uuidString)\n" + dbgClip(cleaned, 2400))
                        }
                    }
                }

                guard !cleaned.isEmpty else {
                    #if DEBUG
                    print("[IdentityLearner] completed: empty output")
                    #endif
                    return
                }

                await MainActor.run {
                    self.identityVault.ingestIdentityLearnerJSON(cleaned, evidenceTurnId: turnId)
                }

                #if DEBUG
                if cleaned == trimmed {
                    print("[IdentityLearner] completed JSON=\(trimmed)")
                } else {
                    print("[IdentityLearner] completed JSON(raw)=\(trimmed)")
                    print("[IdentityLearner] completed JSON(clean)=\(cleaned)")
                }
                #endif
            } catch {
                await releaseGateIfNeeded()
                #if DEBUG
                print("[IdentityLearner] failed err=\(error)")
                #endif
            }
        }

        identityLearnerTask = task
        await task.value
    }

    // Persist the last injected seed so short history windows still retain roleplay continuity.
    // This is purely local state (no extra model calls) and is TTFT-cheap.
    private var lastInjectedSeedText: String = ""
    private var lastInjectedSeedKind: String = ""
    private var lastInjectedSeedConfidence: Double = 0.0
    private var lastInjectedSeedUpdatedAt: Date = .distantPast

    // MARK: - Symbiotic Realm seed generation (fast, deterministic, post-turn)

    /// Creates at most one queued proactive seed using already-available hints.
    /// No embeddings, no network, no model calls.
    private func maybeEnqueueRealmSeed(turnId: UUID) {
        let now = Date()

        // Allow multiple queued seeds so the system can adapt turn-by-turn.
        // Only guard against accidental double-enqueue for the same finished turn.
        if lastRealmSeedTurnId == turnId { return }

        // We only use already-built artifacts (TTFT-safe):
        // - lastIdentityHint: composed system text (includes adaptive overlays)
        // - lastMemoryHint: memory injection block built during the turn
        // - sessionSummary: deterministic continuity summary
        func cleanTiny(_ s: String) -> String {
            s.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Parse a single-line overlay token like `relationship_status=companion` if present.
        func parseOverlayToken(_ token: String, from text: String) -> String? {
            // Look for `token=` anywhere in the composed text.
            let needle = token + "="
            guard let r = text.range(of: needle) else { return nil }
            let after = text[r.upperBound...]
            // Stop at whitespace / newline / bullet-ish separators.
            let stopChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "•|-[]"))
            if let stop = after.rangeOfCharacter(from: stopChars) {
                let raw = String(after[..<stop.lowerBound])
                let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }
            let v = String(after).trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        // We intentionally keep these tiny and stable.
        let idText = cleanTiny(lastIdentityHint)
        let memText = cleanTiny(lastMemoryHint)
        let sessionSummary = self.sessionSummary

        let relationship = parseOverlayToken("relationship_status", from: idText)
        let persona = parseOverlayToken("persona_traits", from: idText)
        let values = parseOverlayToken("values_top", from: idText)

        // Build a compact continuity capsule (roleplay-friendly): canon + scene + threads + constraints.
        // Keep it deterministic and small; do NOT rely on additional model calls.
        func extractSummaryLine(_ prefix: String) -> String? {
            // sessionSummary lines are like: "- Current Thread: ..."
            let needle = prefix
            let ssLines = sessionSummary
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            for line in ssLines {
                if line.hasPrefix(needle) {
                    let v = line.dropFirst(needle.count).trimmingCharacters(in: .whitespacesAndNewlines)
                    if v.isEmpty || v == "—" { return nil }
                    return String(v)
                }
            }
            return nil
        }

        let curThread = extractSummaryLine("- Current Thread:")
        let nextStep = extractSummaryLine("- Next Step:")
        let activeFrame = extractSummaryLine("- Active Frame:")
        let openThreads = extractSummaryLine("- Open Threads:")
        let constraints = extractSummaryLine("- Constraints:")
        let lastAnswer = extractSummaryLine("- Last Answer Snapshot:")

        // Scene cue: prefer realm state arc if available; otherwise fallback to last answer snapshot.
        let st = realmStore.loadState()
        let sceneCue: String? = {
            let arc = cleanTiny(st.arc ?? "")
            if !arc.isEmpty { return String(arc.prefix(180)) }
            if let la = lastAnswer, !la.isEmpty { return String(la.prefix(180)) }
            return nil
        }()

        // Canon cue: keep this stable.
        var canonBits: [String] = []
        if let r = relationship, !r.isEmpty { canonBits.append("relationship=\(r)") }
        if let p = persona, !p.isEmpty { canonBits.append("persona=\(p)") }
        if let v = values, !v.isEmpty { canonBits.append("values=\(v)") }

        // Memory cue: use the beginning of the already-built memory hint. No extra retrieval.
        let memCue = memText.isEmpty ? nil : String(memText.prefix(220))

        var lines: [String] = []
        if !canonBits.isEmpty { lines.append("canon: \(canonBits.joined(separator: " | "))") }
        if let th = curThread { lines.append("thread: \(String(th.prefix(140)))") }
        if let ns = nextStep { lines.append("next: \(String(ns.prefix(140)))") }
        if let fr = activeFrame { lines.append("frame: \(String(fr.prefix(140)))") }
        if let sc = sceneCue { lines.append("scene_now: \(String(sc.prefix(200)))") }
        if let ot = openThreads { lines.append("open_threads: \(String(ot.prefix(180)))") }
        if let c = constraints { lines.append("constraints: \(String(c.prefix(180)))") }
        // (memory line removed as per instructions)

        guard !lines.isEmpty else { return }

        // Short, roleplay-safe continuity directive (keeps the model from pivoting topics).
        lines.append("continuity: remain aligned with the current scene/thread; pivot only when the user pivots.")

        let seedText = lines.joined(separator: "\n")

        let kind: ProactiveSeed.Kind = (memCue == nil) ? .reflection : .memoryLink

        let seed = ProactiveSeed(
            id: UUID().uuidString,
            createdAt: now,
            kind: kind,
            text: seedText,
            mood: nil,
            confidence: 0.65,
            turnId: turnId.uuidString
        )

        realmStore.enqueue(seed)
        lastRealmSeedTurnId = turnId

        #if DEBUG
        print("[SymbioticRealm] enqueued seed kind=\(seed.kind.rawValue) chars=\(seed.text.count) turn=\(turnId.uuidString)")
        #endif
        if dbgFlag("debug.realm.dumpEnqueuedSeed") {
            dbgPrint("[SymbioticRealm] enqueuedSeedFull turn=\(turnId.uuidString)\n" + dbgClip(seed.text, 2600))
        }
    }


    /// Schedules a rare background pass to evolve realm state using ONLY the realm hint ring buffer as compressed context.
    /// This must never block TTFT and must not contend with the main generation path.
    private func scheduleRealmBackgroundStateGeneration(turnId: UUID, scheduledEpoch: UInt64) {
        if isCancelling { return }
        if scheduledEpoch != self.generationEpoch { return }

        #if DEBUG
        let allowOnBattery = true
        let cadenceHours: Double = 0.25
        #else
        let allowOnBattery = false
        let cadenceHours: Double = 24.0
        #endif

        if !isDeviceCharging && !allowOnBattery {
            #if DEBUG
            print("[RealmBG] skip: not charging (allowOnBattery=\(allowOnBattery))")
            #endif
            return
        }

        let now = Date()
        let minSeconds = cadenceHours * 3600.0
        let dt = now.timeIntervalSince(lastRealmBackgroundAt)

        guard dt >= minSeconds else {
            #if DEBUG
            print("[RealmBG] skip: cadence not met dt=\(Int(dt))s < min=\(Int(minSeconds))s")
            #endif
            return
        }

        var hints: [String] = realmStore.recentHints(limit: 10)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if hints.isEmpty {
            hints = self.memoryHintsFast()
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            #if DEBUG
            if !hints.isEmpty {
                print("[RealmBG] bootstrap: using VM-fast hints count=\(hints.count)")
            }
            #endif
        }

        #if DEBUG
        if dbgFlag("debug.realm.dumpHints") {
            let joined = hints.prefix(10)
                .enumerated()
                .map { "\($0.offset + 1). " + dbgClip($0.element, 240) }
                .joined(separator: "\n")
            dbgPrint("[RealmBG] hints turn=\(turnId.uuidString) count=\(hints.count)\n" + joined)
        }
        #endif

        guard !hints.isEmpty else {
            #if DEBUG
            print("[RealmBG] skip: no hints")
            #endif
            return
        }

        let bgSystem = """
    You are a background realm state shaper. You do NOT chat.

    Task: propose a minimal, stable statePatch {location, motif, arc} using ONLY the provided hint strings.

    Rules:
    - Output JSON only (no markdown/fences).
    - If insufficient signal, output {"noop": true}.
    - Keep updates stable (avoid churn).
    - Keep each string <= 32 chars.

    JSON schema:
    {
      "noop": Bool,
      "confidence": Float,
      "statePatch": {
        "location": String?,
        "motif": String?,
        "arc": String?
      }
    }
    """

        let hintBlock = hints.prefix(10).map { "- \($0)" }.joined(separator: "\n")
        let bgUser = """
    <HINTS>
    \(hintBlock)
    </HINTS>
    """

        let bgPrompt = buildModelPrompt(
            system: bgSystem,
            history: [],
            newUserText: bgUser,
            maxHistoryTurns: 0
        )

        realmBackgroundTask?.cancel()
        realmBackgroundTask = nil

        realmBackgroundTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            defer {
                Task { @MainActor [weak self] in
                    self?.realmBackgroundTask = nil
                }
            }

            if Task.isCancelled { return }

            let stillSameEpoch = await MainActor.run {
                scheduledEpoch == self.generationEpoch
            }
            if !stillSameEpoch { return }

            let gate = AIRuntimeStreamGate.shared
            var gateLease: AIRuntimeStreamGate.Lease? = nil
            let acquireStart = Date()
            let maxWaitSeconds: Double = 1.5

            while gateLease == nil {
                if Task.isCancelled { return }

                let stillSameEpoch = await MainActor.run {
                    scheduledEpoch == self.generationEpoch
                }
                if !stillSameEpoch { return }

                gateLease = await gate.tryAcquire(label: "companion.realmBackground")
                if gateLease != nil { break }

                let waited = Date().timeIntervalSince(acquireStart)
                if waited >= maxWaitSeconds {
                    #if DEBUG
                    print("[RealmBG] skip: bridge busy (timed out after \(String(format: "%.1f", waited))s)")
                    #endif
                    return
                }

                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            await MainActor.run {
                self.lastRealmBackgroundAt = Date()
            }

            func releaseGateIfNeeded() async {
                if let lease = gateLease {
                    await gate.release(lease)
                    gateLease = nil
                }
            }

            var modelURL: URL?
            do {
                modelURL = try await MainActor.run {
                    try self.modelStore.beginAccessingModel()
                }
            } catch {
                #if DEBUG
                print("[RealmBG] failed: cannot access model err=\(error)")
                #endif
                await releaseGateIfNeeded()
                return
            }

            let resolvedModelPath = modelURL!.path

            defer {
                if let url = modelURL {
                    Task { @MainActor [weak self] in
                        self?.modelStore.stopAccessing(url)
                    }
                }
            }

            let cfg = LlamaStreamConfig(
                modelPath: resolvedModelPath,
                prompt: bgPrompt,
                maxTokens: 96,
                seqId: 2
            )

            #if DEBUG
            print("[RealmBG] CALL LlamaCppBridge.stream turn=\(turnId.uuidString) promptChars=\(bgPrompt.count)")
            #endif

            do {
                var out = ""
                var aborted = false

                for try await chunk in LlamaCppBridge.stream(cfg) {
                    if Task.isCancelled {
                        aborted = true
                        break
                    }

                    let okEpoch = await MainActor.run {
                        scheduledEpoch == self.generationEpoch
                    }
                    if !okEpoch {
                        aborted = true
                        break
                    }

                    out += chunk
                    if out.count > 4096 { break }
                }

                await releaseGateIfNeeded()
                if aborted { return }

                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = await MainActor.run {
                    trimmed
                        .strippingModelJSONFences()
                        .extractingFirstJSONPayload()
                        .strippingModelJSONFences()
                }

                #if DEBUG
                await MainActor.run {
                    if dbgFlag("debug.realm.dumpBGOutput") {
                        dbgPrint("[RealmBG] output(raw) turn=\(turnId.uuidString)\n" + dbgClip(trimmed, 2400))
                        if cleaned != trimmed {
                            dbgPrint("[RealmBG] output(clean) turn=\(turnId.uuidString)\n" + dbgClip(cleaned, 2400))
                        }
                    }
                }
                #endif

                guard !cleaned.isEmpty else {
                    #if DEBUG
                    print("[RealmBG] completed: empty output")
                    #endif
                    return
                }

                let data = Data(cleaned.utf8)
                let decoded: RealmBackgroundDTO = try await MainActor.run {
                    try JSONDecoder().decode(RealmBackgroundDTO.self, from: data)
                }

                if decoded.noop == true {
                    #if DEBUG
                    print("[RealmBG] noop")
                    #endif
                    return
                }

                let conf = decoded.confidence ?? 0.0
                guard conf >= 0.60, let patch = decoded.statePatch else {
                    #if DEBUG
                    print("[RealmBG] skip: low confidence conf=\(conf)")
                    #endif
                    return
                }

                await MainActor.run {
                    var st = self.realmStore.loadState()

                    func clean(_ s: String?) -> String? {
                        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (t?.isEmpty ?? true) ? nil : t
                    }

                    if let v = clean(patch.location) { st.location = v }
                    if let v = clean(patch.motif) { st.motif = v }
                    if let v = clean(patch.arc) { st.arc = v }

                    st.updatedAt = Date()
                    self.realmStore.saveState(st)

                    #if DEBUG
                    print("[RealmBG] applied location=\(st.location ?? "-") motif=\(st.motif ?? "-") arc=\(st.arc ?? "-") conf=\(conf)")
                    #endif
                }
            } catch {
                await releaseGateIfNeeded()
                #if DEBUG
                print("[RealmBG] failed err=\(error)")
                #endif
            }
        }
    }
    
    /// Called right after onboarding commits AppStorage/UserDefaults so the identity layer can react on the first turn.
    /// This does not block UI/TTFT.
    func applyOnboardingProfileNow() {
        Task { [weak self] in
            guard let self else { return }
            // Provide a tiny non-empty evidence string so the proposal engine can run.
            await self.kickIdentityProposal(
                force: true,
                recentUserText: "[Onboarding] profile committed",
                recentAssistantText: "",
                turnId: nil
            )
        }
    }


    func cancelGeneration() {
        // Non-async convenience for UI.
        Task { [weak self] in
            await self?.cancelGenerationAndWait()
        }
    }


    // MARK: - Memory page actions

    /// Clears the visible chat history and removes the persisted transcript file.
    /// Intended for the Room Options → Memory page.
    func clearRecentChat() {
        Task { [weak self] in
            await self?.clearRecentChatAndWait()
        }
    }

    private func clearRecentChatAndWait() async {
        await cancelGenerationAndWait()
        await AIRuntimeModeGate.shared.forceReset(reason: "clear_recent_chat")

        postTurnTask?.cancel(); postTurnTask = nil
        identityLearnerTask?.cancel(); identityLearnerTask = nil
        realmBackgroundTask?.cancel(); realmBackgroundTask = nil
        
        if let tid = self.activeTurnId {
            self.stopTurnWatchdog(turnId: tid)
        } else {
            self.turnWatchdogTask?.cancel()
            self.turnWatchdogTask = nil
        }
        self.activeTurnId = nil

        self.messages = [.init(role: .assistant, text: "I'm here.")]
        self.sessionSummary = ""
        self.input = ""
        self.isBusy = false
        self.resetRuntimeStateToCold()

        let url = self.cachedTranscriptURL ?? Self.computeTranscriptURL()
        self.cachedTranscriptURL = url
        if let url {
            try? FileManager.default.removeItem(at: url)
        }

        self.scheduleTranscriptSave(immediate: true)
        self.requestSecretaryWorkspaceRefresh()

        #if DEBUG
        print("[ChatViewModel] clearRecentChat done")
        #endif
    }

    private func cancelGenerationAndWait() async {
        secretaryTask?.cancel()
        secretaryTask = nil
        let endingEpoch = secretaryEpoch
        isSecretaryBusy = false
        secretaryEpoch &+= 1
        appServices?.endDiscoveryHeroProgress(generation: endingEpoch, reason: "cancelled")
        secretaryWarmThreadID = nil

        await AIRuntimeModeGate.shared.forceReset(reason: "cancel_generation_begin")

        guard let task = generationTask else {
            isBusy = false
            isCancelling = false
            return
        }

        isCancelling = true
        task.cancel()

        await forceResetBridge(reason: "user_cancel")
        await AIRuntimeModeGate.shared.forceReset(reason: "chat_cancel_generation")

        Task.detached { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            let shouldForce = await MainActor.run { self.isBusy && self.isCancelling }
            if shouldForce {
                await self.performGuardedRecovery(
                    reason: "chat_cancel_watchdog_force_unlock",
                    expectedStreamLabelPrefix: "companion.",
                    allowLastResort: true
                )
            }
        }

        postTurnTask?.cancel()
        postTurnTask = nil
        identityLearnerTask?.cancel()
        identityLearnerTask = nil
        realmBackgroundTask?.cancel()
        realmBackgroundTask = nil

        if let tid = self.activeTurnId {
            self.stopTurnWatchdog(turnId: tid)
        } else {
            self.turnWatchdogTask?.cancel()
            self.turnWatchdogTask = nil
        }

        self.activeTurnId = nil

        await task.value

        generationTask = nil
        isBusy = false
        isCancelling = false
        companionReprimePending = false
        pendingCompanionPrimeTrigger = nil

        await AIRuntimeModeGate.shared.forceReset(reason: "cancel_generation_done")

        self.requestSecretaryWorkspaceRefresh()
        scheduleTranscriptSave()
    }

    @discardableResult
    private func emitTurnFinishedOnce(turnId: UUID, outputChars: Int) -> Bool {
        if finishedTurnIds.contains(turnId) { return false }
        finishedTurnIds.insert(turnId)
        finishedTurnOrder.append(turnId)

        if finishedTurnOrder.count > finishedTurnMax {
            let overflow = finishedTurnOrder.count - finishedTurnMax
            for _ in 0..<overflow {
                let old = finishedTurnOrder.removeFirst()
                finishedTurnIds.remove(old)
            }
        }

        EventBus.shared.emit(.turnFinished(turnId: turnId, outputChars: outputChars))
        return true
    }

    // MARK: - Turn watchdog helpers

    private func startTurnWatchdog(turnId: UUID, assistantIndex: Int, epoch: UInt64) {
        // Cancel any prior watchdog.
        turnWatchdogTask?.cancel()

        activeTurnId = turnId
        activeTurnEpoch = epoch
        activeTurnStartedAt = Date()
        activeTurnLastChunkAt = Date()

        // Watchdog runs off-main and only hops to MainActor for snapshots/actions.
        turnWatchdogTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            while true {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s

                if Task.isCancelled { return }

                let snap = await MainActor.run { () -> (isBusy: Bool, isCancelling: Bool, curTurnId: UUID?, curEpoch: UInt64, startedAt: Date, lastChunkAt: Date, outChars: Int, generationEpoch: UInt64) in
                    let out = (assistantIndex < self.messages.count) ? self.messages[assistantIndex].text : ""
                    return (
                        isBusy: self.isBusy,
                        isCancelling: self.isCancelling,
                        curTurnId: self.activeTurnId,
                        curEpoch: self.activeTurnEpoch,
                        startedAt: self.activeTurnStartedAt,
                        lastChunkAt: self.activeTurnLastChunkAt,
                        outChars: out.count,
                        generationEpoch: self.generationEpoch
                    )
                }

                // If the app is no longer busy, or turn changed, stop.
                if !snap.isBusy { return }
                if snap.isCancelling { continue }
                guard snap.curTurnId == turnId, snap.curEpoch == epoch else { return }

                let now = Date()
                let sinceStart = now.timeIntervalSince(snap.startedAt)
                let sinceChunk = now.timeIntervalSince(snap.lastChunkAt)

                // Two-stage stall detection:
                // - Before first token arrives: allow a longer window (Metal compile / prompt eval).
                // - After tokens begin: allow shorter gaps.
                let hasAnyOutput = snap.outChars > 0
                let stall = hasAnyOutput ? (sinceChunk > 20.0) : (sinceStart > 45.0)

                if stall {
                    await MainActor.run {
                        // Re-check under MainActor to avoid racing normal completion.
                        guard self.isBusy, !self.isCancelling,
                              self.activeTurnId == turnId,
                              self.activeTurnEpoch == epoch else { return }

                        // Mark this turn as no longer active so we don't double-close.
                        self.activeTurnId = nil

                        // Cancel generation task (best effort).
                        self.generationTask?.cancel()
                        // If the underlying stream ignores cancellation, force-reset the bridge so subsequent turns don’t hang.
                        Task { await self.forceResetBridge(reason: "watchdog_stall") }
                        Task.detached { [weak self] in
                            guard let self else { return }
                            try? await Task.sleep(nanoseconds: 750_000_000)
                            await self.performGuardedRecovery(
                                reason: "watchdog_stall_recovery",
                                expectedStreamLabelPrefix: "companion.",
                                allowLastResort: true
                            )
                        }
                        let out = (assistantIndex < self.messages.count) ? self.messages[assistantIndex].text : ""

                        // Emit a diagnostic error AND a turnFinished so downstream pipelines are unblocked.
                        EventBus.shared.emit(.turnError(turnId: turnId, message: "Watchdog: stream stalled"))
                        _ = self.emitTurnFinishedOnce(turnId: turnId, outputChars: out.count)

                        // Bring UI back to a sane state.
                        self.isBusy = false
                        self.generationTask = nil
                        self.scheduleTranscriptSave()

                        // Even if we had to watchdog-close the stream, still run post-turn maintenance so
                        // adaptive layers (identity proposals / learner / realm seed) can fire.
                        let uText = (assistantIndex - 1 >= 0 && assistantIndex - 1 < self.messages.count)
                          ? self.messages[assistantIndex - 1].text
                          : ""

                        let trimmedU = uText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedU.isEmpty {
                            // Best-effort: update deterministic session summary based on the user input.
                            self.updateSessionSummary(userText: trimmedU, assistantText: String(out.prefix(320)))
                            self.scheduleTranscriptSave()

                            // Recompute forceIdentityProposal using the same rule as the main path.
                            let forceRemember = Self.isExplicitRememberDirective(trimmedU)
                            let forceIdentityProposal = forceRemember
                              || trimmedU.lowercased().contains("update my preferences")
                              || trimmedU.lowercased().contains("update my identity")

                            self.runPostTurnMaintenance(
                                forceIdentityProposal: forceIdentityProposal,
                                userText: trimmedU,
                                assistantText: out,
                                turnId: turnId,
                                scheduledEpoch: epoch
                            )

                            #if DEBUG
                            print("[ChatViewModel] WATCHDOG scheduled postTurn turnId=\(turnId.uuidString) uChars=\(trimmedU.count) aChars=\(out.count)")
                            #endif
                        }

                        #if DEBUG
                        print("[ChatViewModel] WATCHDOG closed stalled turn turnId=\(turnId.uuidString) outChars=\(out.count) sinceStart=\(Int(sinceStart))s sinceChunk=\(Int(sinceChunk))s")
                        #endif
                    }

                    return
                }
            }
        }
    }

    private func stopTurnWatchdog(turnId: UUID) {
        if activeTurnId == turnId {
            activeTurnId = nil
        }
        turnWatchdogTask?.cancel()
        turnWatchdogTask = nil
    }

    private func touchTurnWatchdogChunk(turnId: UUID) {
        guard activeTurnId == turnId else { return }
        activeTurnLastChunkAt = Date()
    }

    // MARK: - Model-aware prompt composer

    private enum PromptFamily {
        case qwen
        case gemma
    }

    private func currentPromptFamily() -> PromptFamily {
        // Current bundled model is Qwen3.5 2B Q4_K_M, renamed as Unify1.0.gguf.
        // Use Qwen ChatML formatting while keeping the existing prompt injection/runtime logic unchanged.
        return .qwen
    }

    // ---- Qwen ----
    
    private func qwenAssistantGenerationPrefix() -> String {
        // Matches Qwen3.5 GGUF embedded chat_template with enable_thinking = false.
        //
        // Official template emits:
        // <|im_start|>assistant
        // <think>
        //
        // </think>
        //
        //
        // This prevents the model from entering open-ended visible thinking mode.
        return "<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    private func chatMLBlock(role: String, content: String) -> String {
        "<|im_start|>\(role)\n\(content)\n<|im_end|>\n"
    }

    private func buildQwenChatMLPrompt(
        system: String,
        extraSystemBlocks: [String] = [],
        history: [ChatMessage],
        newUserText: String,
        maxHistoryTurns: Int = 2
    ) -> String {
        var out = ""
        out.reserveCapacity(4096)

        let trimmedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            out += chatMLBlock(role: "system", content: trimmedSystem)
        }

        let cleaned = history
            .map {
                ChatMessage(
                    role: $0.role,
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.text.isEmpty }

        let maxMsgs = max(0, maxHistoryTurns * 2)
        let tail = cleaned.suffix(maxMsgs)

        for message in tail {
            let clipped = String(message.text.prefix(420))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !clipped.isEmpty else { continue }

            switch message.role {
            case .user:
                out += chatMLBlock(role: "user", content: clipped)

            case .assistant:
                // Do not hard-strip <think> here.
                // Assistant transcript history should already contain UI-visible assistant text.
                out += chatMLBlock(role: "assistant", content: clipped)
            }
        }

        for block in extraSystemBlocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            out += chatMLBlock(role: "system", content: trimmed)
        }

        let trimmedNewUser = newUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        out += chatMLBlock(role: "user", content: trimmedNewUser)
        out += qwenAssistantGenerationPrefix()

        return out
    }

    // ---- Gemma ----

    private func gemmaTurn(role: String, content: String) -> String {
        "<start_of_turn>\(role)\n\(content)\n<end_of_turn>\n"
    }

    private func buildGemmaPrompt(
        system: String,
        extraSystemBlocks: [String] = [],
        history: [ChatMessage],
        newUserText: String,
        maxHistoryTurns: Int = 2
    ) -> String {
        var out = ""
        out.reserveCapacity(4096)

        let cleaned = history
            .map { ChatMessage(role: $0.role, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }

        let maxMsgs = max(0, maxHistoryTurns * 2)
        let tail = Array(cleaned.suffix(maxMsgs))

        let trimmedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExtras = extraSystemBlocks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Keep system/context separate from the actual user message.
        // For Gemma, safest fallback is a dedicated first user turn carrying instruction context.
        var preambleParts: [String] = []
        if !trimmedSystem.isEmpty {
            preambleParts.append(trimmedSystem)
        }
        if !trimmedExtras.isEmpty {
            preambleParts.append(contentsOf: trimmedExtras)
        }

        if !preambleParts.isEmpty {
            out += gemmaTurn(
                role: "user",
                content: "[Instruction Context]\n" + preambleParts.joined(separator: "\n\n")
            )
            out += gemmaTurn(
                role: "model",
                content: "Understood."
            )
        }

        for m in tail {
            let clipped = String(m.text.prefix(420))
            switch m.role {
            case .user:
                out += gemmaTurn(role: "user", content: clipped)
            case .assistant:
                out += gemmaTurn(role: "model", content: clipped)
            }
        }

        let trimmedNewUser = newUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        out += gemmaTurn(role: "user", content: trimmedNewUser)

        // Final generation prefix
        out += "<start_of_turn>model\n"
        return out
    }

    private func buildModelPrompt(
        system: String,
        extraSystemBlocks: [String] = [],
        history: [ChatMessage],
        newUserText: String,
        maxHistoryTurns: Int = 2
    ) -> String {
        switch currentPromptFamily() {
        case .qwen:
            return buildQwenChatMLPrompt(
                system: system,
                extraSystemBlocks: extraSystemBlocks,
                history: history,
                newUserText: newUserText,
                maxHistoryTurns: maxHistoryTurns
            )

        case .gemma:
            return buildGemmaPrompt(
                system: system,
                extraSystemBlocks: extraSystemBlocks,
                history: history,
                newUserText: newUserText,
                maxHistoryTurns: maxHistoryTurns
            )
        }
    }
    
    // MARK: - Launch scaffold prime

    /// Builds the exact stable scaffold prefix used to warm/prime llama state at launch.
    ///
    /// Important:
    /// This should match the reusable prefix before a normal user turn is ingested.
    /// Do NOT include the current user message.
    /// Do NOT include the final assistant/model generation prefix.
    /// Do NOT include late memory/session augmentation.
    func launchStableScaffoldPrompt() -> String {
        let snap = currentRuntimeScaffoldSnapshot()
        let system = snap.composedSystemText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !system.isEmpty else { return "" }

        switch currentPromptFamily() {
        case .qwen:
            return buildQwenScaffoldPrompt(
                system: system,
                extraSystemBlocks: []
            )

        case .gemma:
            return buildGemmaScaffoldPrompt(
                system: system,
                extraSystemBlocks: []
            )
        }
    }

    private func buildQwenScaffoldPrompt(
        system: String,
        extraSystemBlocks: [String] = []
    ) -> String {
        var out = ""
        out.reserveCapacity(2048)

        let trimmedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            out += chatMLBlock(role: "system", content: trimmedSystem)
        }

        for block in extraSystemBlocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            out += chatMLBlock(role: "system", content: trimmed)
        }

        return out
    }

    private func buildGemmaScaffoldPrompt(
        system: String,
        extraSystemBlocks: [String] = []
    ) -> String {
        var out = ""
        out.reserveCapacity(2048)

        let trimmedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExtras = extraSystemBlocks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var preambleParts: [String] = []

        if !trimmedSystem.isEmpty {
            preambleParts.append(trimmedSystem)
        }

        if !trimmedExtras.isEmpty {
            preambleParts.append(contentsOf: trimmedExtras)
        }

        guard !preambleParts.isEmpty else { return "" }

        out += gemmaTurn(
            role: "user",
            content: "[Instruction Context]\n" + preambleParts.joined(separator: "\n\n")
        )

        out += gemmaTurn(
            role: "model",
            content: "Understood."
        )

        return out
    }
    
    func configureExchange(
        bridge: ExchangeChatBridge,
        facade: ExchangeFacade
    ) {
        self.exchangeChatBridge = bridge
        self.exchangeFacade = facade
    }
    
    // MARK: - UI mode → runtime ownership

    func enterSecretaryRuntimeMode() {
        log.info(
            "enterSecretaryRuntimeMode begin isBusy=\(self.isBusy, privacy: .public) isSecretaryBusy=\(self.isSecretaryBusy, privacy: .public) isCancelling=\(self.isCancelling, privacy: .public)"
        )
        #if DEBUG
        secretaryDebugLog(
            "enterSecretaryRuntimeMode | isBusy=\(isBusy) isSecretaryBusy=\(isSecretaryBusy) runtimeMode=\(String(describing: runtimeStateMode))"
        )
        #endif

        // Do not kill an active companion generation here.
        // The runtime gate already prevents overlap.
        // This function is a mode/lifecycle hint, not a destructive cancel.
        prefixPrimeTask?.cancel()
        prefixPrimeTask = nil
        companionReprimePending = false
        pendingCompanionPrimeTrigger = nil

        // Companion warm state should not be trusted after switching modes because
        // Secretary uses the same native seq0 through LlamaExchangeModelRunner.
        invalidateWarmRuntime(reason: "ui_enter_secretary")

        // Keep secretary thread continuity separate from llama KV/runtime continuity.
        requestSecretaryWorkspaceRefresh()

        // Secretary mode is intentionally stateless between jobs.
        // Warm only the resident model / Metal kernels after mode switch.
        // Do NOT ingest secretary scaffold here.
        scheduleSecretaryKernelWarmup(trigger: "mode_switch_secretary")
        log.info("enterSecretaryRuntimeMode end reason=ui_enter_secretary")
    }

    func enterCompanionRuntimeMode(afterSecretary: Bool = true) {
        let reason: CompanionEntryReason = afterSecretary ? .afterSecretary : .bootstrap
        log.info(
            "enterCompanionRuntimeMode begin reason=\(reason.rawValue, privacy: .public) isBusy=\(self.isBusy, privacy: .public) isSecretaryBusy=\(self.isSecretaryBusy, privacy: .public) isCancelling=\(self.isCancelling, privacy: .public)"
        )
        #if DEBUG
        print(
            "[ChatViewModel] enterCompanionRuntimeMode | isBusy=\(isBusy) isSecretaryBusy=\(isSecretaryBusy) runtimeMode=\(String(describing: runtimeStateMode))"
        )
        #endif

        // Secretary may have used fullReplay/stateless jobs on seq0.
        // Companion warm state is therefore no longer safe.
        invalidateWarmRuntime(reason: reason.rawValue)

        // Do not immediately prime here if Secretary or Companion is still busy.
        guard !isBusy, !isSecretaryBusy, !isCancelling else {
            companionReprimePending = false
            pendingCompanionPrimeTrigger = nil
            #if DEBUG
            print(
                "[PrefixPrime] skip trigger=mode_switch_companion reason=busy isBusy=\(isBusy) isSecretaryBusy=\(isSecretaryBusy) isCancelling=\(isCancelling)"
            )
            #endif
            log.info("enterCompanionRuntimeMode end reason=\(reason.rawValue, privacy: .public) result=skipped_busy")
            return
        }

        // Best-effort companion scaffold recovery.
        // This does not block the UI.
        if afterSecretary {
            companionReprimePending = true
            pendingCompanionPrimeTrigger = "mode_switch_companion"
        } else {
            companionReprimePending = false
            pendingCompanionPrimeTrigger = nil
        }
        primePrefixCacheIfNeeded(trigger: "mode_switch_companion")
        log.info("enterCompanionRuntimeMode end reason=\(reason.rawValue, privacy: .public) result=prime_scheduled")
    }

    private func scheduleSecretaryKernelWarmup(trigger: String) {
        guard !isBusy, !isSecretaryBusy, !isCancelling else {
            #if DEBUG
            secretaryDebugLog(
                "secretary kernel warm skip | trigger=\(trigger) reason=busy isBusy=\(isBusy) isSecretaryBusy=\(isSecretaryBusy) isCancelling=\(isCancelling)"
            )
            #endif
            return
        }

        prefixPrimeTask?.cancel()

        prefixPrimeTask = Task { [weak self] in
            guard let self else { return }

            #if DEBUG
            secretaryDebugLog("secretary kernel warm scheduled | trigger=\(trigger)")
            #endif

            // Let the mode transition, workspace refresh, and keyboard/candidate UI settle first.
            // Warming immediately after the toggle competes with SwiftUI rebuild + iOS text input.
            try? await Task.sleep(nanoseconds: 650_000_000)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                #if DEBUG
                secretaryDebugLog(
                    "secretary kernel warm preflight | trigger=\(trigger) isBusy=\(self.isBusy) isSecretaryBusy=\(self.isSecretaryBusy) isCancelling=\(self.isCancelling)"
                )
                #endif
            }

            guard await MainActor.run(body: {
                !self.isBusy && !self.isSecretaryBusy && !self.isCancelling
            }) else {
                #if DEBUG
                await MainActor.run {
                    secretaryDebugLog("secretary kernel warm cancelled | trigger=\(trigger) reason=becameBusy")
                }
                #endif
                return
            }

            guard let lease = await AIRuntimeStreamGate.shared.tryAcquire(
                label: "secretary.kernelWarm.\(trigger)"
            ) else {
                #if DEBUG
                await MainActor.run {
                    secretaryDebugLog("secretary kernel warm skipped | trigger=\(trigger) reason=streamGateBusy")
                }
                #endif
                return
            }

            defer {
                Task {
                    await AIRuntimeStreamGate.shared.release(lease)
                }
            }

            do {
                let modelURL = try await MainActor.run {
                    try ModelStore.shared.beginAccessingModel()
                }

                defer {
                    Task { @MainActor in
                        ModelStore.shared.stopAccessing(modelURL)
                    }
                }

                #if DEBUG
                await MainActor.run {
                    secretaryDebugLog(
                        "secretary kernel warm CALL | trigger=\(trigger) model=\(modelURL.lastPathComponent)"
                    )
                }
                #endif

                LlamaCppBridge.resumeAfterBackground(modelPath: modelURL.path)

                await LlamaCppBridge.warmKernelAndWait(
                    modelPath: modelURL.path,
                    nCtx: 2048,
                    nThreads: 4,
                    nBatch: 128
                )

                #if DEBUG
                await MainActor.run {
                    secretaryDebugLog("secretary kernel warm DONE | trigger=\(trigger)")
                }
                #endif
            } catch {
                #if DEBUG
                await MainActor.run {
                    secretaryDebugLog(
                        "secretary kernel warm ERROR | trigger=\(trigger) error=\(error.localizedDescription)"
                    )
                }
                #endif
            }
        }
    }
    
    func sendAsSecretary() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let userText = trimmedInput

        guard !userText.isEmpty else {
            #if DEBUG
            secretaryDebugLog("send blocked | empty input")
            #endif
            return
        }

        guard !isSecretaryBusy, !isBusy, !isCancelling else {
            #if DEBUG
            secretaryDebugLog("send blocked | isSecretaryBusy=\(isSecretaryBusy) isBusy=\(isBusy) isCancelling=\(isCancelling)")
            #endif
            return
        }

        guard let exchangeChatBridge else {
            #if DEBUG
            secretaryDebugLog("send blocked | exchangeChatBridge missing")
            #endif
            return
        }

        #if DEBUG
        secretaryDebugLog(
            "send begin | chars=\(userText.count) activeThread=\(activeExchangeThreadID?.uuidString ?? "nil") warmThread=\(secretaryWarmThreadID?.uuidString ?? "nil") runtimeMode=\(String(describing: runtimeStateMode))"
        )
        #endif

        let currentThreadID = activeExchangeThreadID

        secretaryTask?.cancel()
        secretaryTask = nil

        secretaryEpoch &+= 1
        let epoch = secretaryEpoch

        input = ""
        isSecretaryBusy = true
        appServices?.beginDiscoveryHeroProgress(originalText: userText, generation: epoch)

        #if DEBUG
        secretaryDebugLog("secretary input accepted without companion transcript append")
        #endif

        secretaryTask = Task { [weak self] in
            guard let self else { return }

            #if DEBUG
            secretaryDebugLog("task entered | epoch=\(epoch)")
            #endif

            guard epoch == self.secretaryEpoch else {
                #if DEBUG
                secretaryDebugLog("task exit | stale epoch taskEpoch=\(epoch) currentEpoch=\(self.secretaryEpoch)")
                #endif
                return
            }

            var didAcquireRuntimeMode = false

            do {
                try await AIRuntimeModeGate.shared.acquire(.secretary)
                didAcquireRuntimeMode = true

                #if DEBUG
                secretaryDebugLog("runtime gate acquired | mode=secretary epoch=\(epoch)")
                #endif
            } catch {
                await MainActor.run {
                    guard epoch == self.secretaryEpoch else { return }

                    #if DEBUG
                    secretaryDebugLog("runtime gate blocked | error=\(error.localizedDescription)")
                    #endif

                    self.isSecretaryBusy = false
                    self.secretaryTask = nil
                    self.appServices?.endDiscoveryHeroProgress(generation: epoch, reason: "runtime_gate_blocked")
                    self.input = userText

                    #if DEBUG
                    secretaryDebugLog("runtime gate blocked; restored input without companion transcript append")
                    #endif

                    self.requestSecretaryWorkspaceRefresh()
                }
                return
            }

            defer {
                if didAcquireRuntimeMode {
                    Task {
                        await AIRuntimeModeGate.shared.release(.secretary)
                    }
                }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard epoch == self.secretaryEpoch else { return }

                    #if DEBUG
                    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                    secretaryDebugLog("task finalize | epoch=\(epoch) elapsed=\(elapsedMs)ms")
                    #endif

                    self.isSecretaryBusy = false
                    self.secretaryTask = nil
                    self.appServices?.endDiscoveryHeroProgress(generation: epoch, reason: "completed")
                }
            }

            do {
                let effectiveThreadID = self.secretaryWarmThreadID ?? currentThreadID

                #if DEBUG
                let preRouteMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                secretaryDebugLog(
                    "route begin | effectiveThread=\(effectiveThreadID?.uuidString ?? "nil") currentThread=\(currentThreadID?.uuidString ?? "nil") warmThread=\(self.secretaryWarmThreadID?.uuidString ?? "nil") elapsed=\(preRouteMs)ms"
                )
                #endif

                guard epoch == self.secretaryEpoch, !Task.isCancelled else {
                    #if DEBUG
                    secretaryDebugLog("route skipped | stale/cancelled before route")
                    #endif
                    return
                }

                let progressContext = DiscoveryHeroProgressContext(
                    generation: epoch,
                    originalText: userText
                )

                let result = try await exchangeChatBridge.route(
                    userText: userText,
                    currentThreadID: effectiveThreadID,
                    progressContext: progressContext,
                    now: Date()
                )

                #if DEBUG
                let postRouteMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                secretaryDebugLog("route returned | elapsed=\(postRouteMs)ms")
                #endif

                guard epoch == self.secretaryEpoch, !Task.isCancelled else {
                    #if DEBUG
                    secretaryDebugLog("route result dropped | stale/cancelled after route")
                    #endif
                    return
                }

                await MainActor.run {
                    guard epoch == self.secretaryEpoch else {
                        #if DEBUG
                        secretaryDebugLog("mainactor apply skipped | stale epoch")
                        #endif
                        return
                    }

                    switch result {
                    case .chatOnly(let reason):
                        #if DEBUG
                        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                        secretaryDebugLog("result chatOnly | reason=\(reason) elapsed=\(elapsedMs)ms")
                        #endif

                        self.secretaryWarmThreadID = nil

                        #if DEBUG
                        secretaryDebugLog(
                            "chatOnly handled without companion transcript append | reason=\(reason)"
                        )
                        #endif

                        self.requestSecretaryWorkspaceRefresh()

                    case .exchange(let response, let detail, _):
                        #if DEBUG
                        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                        secretaryDebugLog(
                            "result exchange | thread=\(response.thread.id.uuidString) state=\(response.thread.state.phaseTitle) action=\(response.handoff.latestAction?.rawValue ?? "nil") summary=\(response.summary) elapsed=\(elapsedMs)ms"
                        )
                        #endif

                        self.activeExchangeThreadID = detail.thread.id
                        self.secretaryWarmThreadID = detail.thread.id

                        #if DEBUG
                        secretaryDebugLog(
                            "exchange result stored in Exchange only | thread=\(detail.thread.id.uuidString)"
                        )
                        #endif

                        self.recordSuccessfulExchangeSubmit(
                            threadID: detail.thread.id,
                            userText: userText,
                            detail: detail,
                            progressGeneration: epoch
                        )

                    case .threadDetail(let detail, _):
                        #if DEBUG
                        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                        secretaryDebugLog(
                            "result threadDetail | thread=\(detail.thread.id.uuidString) state=\(detail.thread.state.phaseTitle) summary=\(detail.summary) elapsed=\(elapsedMs)ms"
                        )
                        #endif

                        self.activeExchangeThreadID = detail.thread.id
                        self.secretaryWarmThreadID = detail.thread.id

                        #if DEBUG
                        secretaryDebugLog(
                            "threadDetail result stored in Exchange only | thread=\(detail.thread.id.uuidString)"
                        )
                        #endif

                        self.recordSuccessfulExchangeSubmit(
                            threadID: detail.thread.id,
                            userText: userText,
                            detail: detail,
                            progressGeneration: epoch
                        )
                    }
                }
            } catch is CancellationError {
                #if DEBUG
                let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                secretaryDebugLog("task cancelled | epoch=\(epoch) elapsed=\(elapsedMs)ms")
                #endif
                return
            } catch {
                await MainActor.run {
                    #if DEBUG
                    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                    secretaryDebugLog(
                        "task error | err=\(error.localizedDescription) activeThread=\(self.activeExchangeThreadID?.uuidString ?? "nil") warmThread=\(self.secretaryWarmThreadID?.uuidString ?? "nil") elapsed=\(elapsedMs)ms"
                    )
                    #endif

                    self.secretaryWarmThreadID = nil
                    self.input = userText
                    self.appServices?.endDiscoveryHeroProgress(generation: epoch, reason: "error")

                    #if DEBUG
                    secretaryDebugLog("exchange request failed without companion transcript append: \(error.localizedDescription)")
                    #endif

                    self.requestSecretaryWorkspaceRefresh()
                }
            }
        }
    }
    
    private func exchangeAssistantSummary(
        from response: ExchangeOrchestrator.Response
    ) -> String {
        response.summary
    }

    private func exchangeThreadDetailSummary(
        _ detail: ExchangeModels.ThreadDetail
    ) -> String {
        detail.summary
    }

    private func secretaryChatOnlyFallback(
        for userText: String,
        reason: String
    ) -> String {
        """
    I did not start an exchange thread.

    What happened: your message did not clearly map to a coordination action.
    What did not happen: no thread was created and nothing was sent externally.
    Next step: ask me to find, contact, approve, reject, or show the status of an exchange. \(reason)
    """
    }
    
    // MARK: - Runtime scaffold helpers

    private struct TurnPreparedPrompt {
        let runtimeMode: RuntimeStateMode
        let scaffold: RuntimeScaffoldSnapshot
        let identityBefore: String
        let lateAugmentation: String
        let userTurnPayload: String
        let history: [ChatMessage]
        let historyTurns: Int
        let prompt: String
    }

    private func currentRuntimeScaffoldSnapshot() -> RuntimeScaffoldSnapshot {
        let snap = identityVault.currentScaffoldSnapshot()
        return RuntimeScaffoldSnapshot(
            scaffoldText: snap.scaffoldText,
            scaffoldHash: snap.scaffoldHash,
            hotHeaderText: snap.hotHeaderText,
            hotHeaderHash: snap.hotHeaderHash,
            composedSystemText: snap.composedSystemText
        )
    }
    
    // MARK: - App lifecycle runtime recovery

    /// Called when iOS backgrounds the app or when native llama state is no longer trustworthy.
    /// This must keep transcript/session continuity but force the next user turn through full replay,
    /// not warm incremental ingest.
    func prepareForAppBackground() {
        generationEpoch &+= 1

        postTurnTask?.cancel()
        postTurnTask = nil

        identityLearnerTask?.cancel()
        identityLearnerTask = nil

        realmBackgroundTask?.cancel()
        realmBackgroundTask = nil

        prefixPrimeTask?.cancel()
        prefixPrimeTask = nil

        if let tid = activeTurnId {
            stopTurnWatchdog(turnId: tid)
        } else {
            turnWatchdogTask?.cancel()
            turnWatchdogTask = nil
        }

        activeTurnId = nil
        activeTurnEpoch = 0
        activeTurnStartedAt = .distantPast
        activeTurnLastChunkAt = .distantPast

        isCancelling = false
        isBusy = false

        invalidateWarmRuntime(reason: "app_background")
        flushTranscriptToDisk()

        #if DEBUG
        print("[ChatViewModel] prepareForAppBackground: warm runtime invalidated")
        #endif
    }

    /// Called after foreground resume.
    /// Do not mark warm here. Foreground only means the app is active again.
    /// The next successful full replay can mark runtime warm.
    func prepareForAppForeground() {
        invalidateWarmRuntime(reason: "app_foreground")

        #if DEBUG
        print("[ChatViewModel] prepareForAppForeground: next turn will use recovery/full replay")
        #endif
    }
    
    /// Called by RootView after launch/foreground scaffold prewarm has completed.
    /// This tells the chat layer that native seq0 should now contain the reusable scaffold.
    func noteLaunchRuntimePrepared(trigger: String) {
        guard !isBusy, !isCancelling else {
            #if DEBUG
            print("[ChatViewModel] noteLaunchRuntimePrepared ignored trigger=\(trigger) isBusy=\(isBusy) isCancelling=\(isCancelling)")
            #endif
            return
        }

        runtimeStateMode = .warm
        lastLateAugmentationHash = ""
        lastCompanionIngestedScaffoldHash = currentRuntimeScaffoldSnapshot().scaffoldHash
        log.info("noteLaunchRuntimePrepared trigger=\(trigger, privacy: .public) mode=warm")

        #if DEBUG
        print("[ChatViewModel] runtime prepared trigger=\(trigger) mode=warm")
        #endif
    }

    private func invalidateWarmRuntime(reason: String) {
        runtimeStateMode = .invalidated
        lastLateAugmentationHash = ""
        lastCompanionIngestedScaffoldHash = ""
        #if DEBUG
        print("[ChatViewModel] runtime invalidated reason=\(reason)")
        #endif
    }

    private func markWarmRuntimeReady() {
        runtimeStateMode = .warm
        lastCompanionIngestedScaffoldHash = currentRuntimeScaffoldSnapshot().scaffoldHash
    }

    private func resetRuntimeStateToCold() {
        runtimeStateMode = .cold
        lastLateAugmentationHash = ""
        lastCompanionIngestedScaffoldHash = ""
    }

    private func shouldInjectSessionSummaryHotPath(for userText: String, mode: RuntimeStateMode) -> Bool {
        let u = userText.lowercased()

        switch mode {
        case .cold, .invalidated:
            return Self.shouldInjectSessionSummary(sessionSummary)

        case .warm:
            if u.contains("earlier")
                || u.contains("before")
                || u.contains("last time")
                || u.contains("you said")
                || u.contains("we said")
                || u.contains("what was")
                || u.contains("what were")
                || u.contains("recall")
                || u.contains("remember")
            {
                return Self.shouldInjectSessionSummary(sessionSummary)
            }
            return false
        }
    }

    private func shouldInjectSceneHotPath(for userText: String) -> Bool {
        let u = userText.lowercased()
        return u.contains("scene")
            || u.contains("roleplay")
            || u.contains("prologue")
            || u.contains("setting")
            || u.contains("character")
            || u.contains("i walk")
            || u.contains("i open")
            || u.contains("i look")
            || u.contains("we enter")
            || u.contains("we walk")
            || u.contains("we look")
    }

    private func shouldInjectSeedHotPath(for userText: String) -> Bool {
        let u = userText.lowercased()
        let pivotCues = ["new topic", "switch", "actually", "forget that", "change topic", "different topic", "instead"]
        if pivotCues.contains(where: { u.contains($0) }) { return false }
        return shouldInjectSceneHotPath(for: userText)
    }

    private func historyTurns(for mode: RuntimeStateMode) -> Int {
        switch mode {
        case .cold:
            return 2
        case .invalidated:
            return 2
        case .warm:
            return 0
        }
    }

    private func composeUserTurnPayload(userText: String, lateAugmentation: String) -> String {
        let aug = lateAugmentation.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !aug.isEmpty else { return user }

        return """
    [Relevant Context]
    \(aug)

    [User]
    \(user)
    """
    }

    private func compressLateBlock(_ s: String, maxChars: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if t.count <= maxChars { return t }
        return String(t.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentSceneBlockForHotPath() -> String? {
        let st = self.realmStore.loadState()

        func clean(_ s: String?, max: Int) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let t, !t.isEmpty else { return nil }
            return String(t.prefix(max))
        }

        var parts: [String] = []
        if let v = clean(st.location, max: 48) { parts.append("location=\(v)") }
        if let v = clean(st.motif, max: 48) { parts.append("motif=\(v)") }
        if let v = clean(st.arc, max: 120) { parts.append("arc=\(v)") }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    private func currentSeedBlockForHotPath(userText: String) -> String? {
        guard shouldInjectSeedHotPath(for: userText) else { return nil }

        let age = Date().timeIntervalSince(self.lastInjectedSeedUpdatedAt)
        guard !self.lastInjectedSeedText.isEmpty, age <= 15.0 * 60.0 else { return nil }

        let compact = compressRealmSeedForPrompt(self.lastInjectedSeedText, maxChars: 280)
        let finalText = compact.isEmpty ? String(self.lastInjectedSeedText.prefix(220)) : compact
        guard !finalText.isEmpty else { return nil }

        return "kind=\(self.lastInjectedSeedKind)\n\(finalText)"
    }

    private func compressRealmSeedForPrompt(_ s: String, maxChars: Int) -> String {
        let raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let hasKV = lines.contains(where: { $0.contains(":") && !$0.hasPrefix("-") })

        var compact: String
        if hasKV {
            compact = lines.prefix(6).joined(separator: "\n")
        } else {
            compact = raw
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if compact.count > maxChars {
            compact = String(compact.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return compact
    }

    private func awaitWithTimeout<T>(nanoseconds: UInt64, _ op: @escaping () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await op() }
            group.addTask {
                try? await Task.sleep(nanoseconds: nanoseconds)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func shouldFetchMemoryHotPath(for userText: String, mode: RuntimeStateMode) -> Bool {
        switch mode {
        case .cold, .invalidated:
            return Self.shouldFetchMemory(for: userText)
        case .warm:
            return Self.shouldFetchMemory(for: userText)
        }
    }

    private func buildLateTurnAugmentation(userText: String, mode: RuntimeStateMode) async -> String {
        var blocks: [String] = []
        let u = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldInjectSessionSummaryHotPath(for: u, mode: mode) {
            let ss = sessionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.shouldInjectSessionSummary(ss) {
                blocks.append("### SUM\n" + compressLateBlock(ss, maxChars: 320))
            }
        }

        if shouldInjectSceneHotPath(for: u), let scene = currentSceneBlockForHotPath() {
            blocks.append("### SCENE\n" + scene)
        }

        if let seed = currentSeedBlockForHotPath(userText: u) {
            blocks.append("### SEED\n" + seed)
        }

        if shouldFetchMemoryHotPath(for: u, mode: mode) {
            let memTask = Task.detached(priority: .utility) { () -> String in
                do {
                    return try await MemoryStore.shared.buildInjectionBlock(
                        query: u,
                        maxItems: 2,
                        maxChars: 260
                    )
                } catch {
                    return ""
                }
            }

            if let mem = await awaitWithTimeout(nanoseconds: 60_000_000, { await memTask.value }) {
                let trimmed = mem.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(trimmed)
                }
                self.lastMemoryHint = String(trimmed.prefix(240))
            } else {
                self.lastMemoryHint = ""
            }

            memTask.cancel()
        } else {
            self.lastMemoryHint = ""
        }

        let merged = blocks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        if merged.isEmpty {
            lastLateAugmentationHash = ""
            return ""
        }

        let maxChars: Int
        switch mode {
        case .cold, .invalidated:
            maxChars = 520
        case .warm:
            maxChars = 380
        }

        let clipped = compressLateBlock(merged, maxChars: maxChars)
        lastLateAugmentationHash = sha256Hex(clipped)
        return clipped
    }

    private func prepareTurnPrompt(userText: String, historyBase: [ChatMessage]) async -> TurnPreparedPrompt {
        let mode = runtimeStateMode
        let snap = currentRuntimeScaffoldSnapshot()
        let identityBefore = snap.composedSystemText

        self.lastIdentityHint = String(snap.hotHeaderText.prefix(240))

        let lateAugmentation = await buildLateTurnAugmentation(userText: userText, mode: mode)
        let userTurnPayload = composeUserTurnPayload(
            userText: userText,
            lateAugmentation: lateAugmentation
        )

        let historyTurns = historyTurns(for: mode)
        let promptHistory: [ChatMessage]
        if historyTurns > 0 {
            promptHistory = historyBase
        } else {
            promptHistory = []
        }

        let prompt = buildModelPrompt(
            system: snap.composedSystemText,
            extraSystemBlocks: [],
            history: promptHistory,
            newUserText: userTurnPayload,
            maxHistoryTurns: historyTurns
        )

        #if DEBUG
        debugSecretaryPromptAuditCompanion(
            prompt: prompt,
            identitySystemChars: identityBefore.count
        )
        #endif

        return TurnPreparedPrompt(
            runtimeMode: mode,
            scaffold: snap,
            identityBefore: identityBefore,
            lateAugmentation: lateAugmentation,
            userTurnPayload: userTurnPayload,
            history: promptHistory,
            historyTurns: historyTurns,
            prompt: prompt
        )
    }
    
    private func warmTurnStableKey(
        scaffoldHash: String,
        hotHeaderHash: String,
        lateAugmentationHash: String
    ) -> String {
        "\(scaffoldHash)|\(hotHeaderHash)|\(lateAugmentationHash)"
    }

    private func makeBaseStreamConfig(
        modelPath: String,
        prompt: String,
        seqId: Int32 = 0
    ) -> LlamaStreamConfig {
        var cfg = LlamaStreamConfig(
            modelPath: modelPath,
            prompt: prompt,
            maxTokens: 512,
            seqId: seqId
        )

        let cores = ProcessInfo.processInfo.activeProcessorCount
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        var threads = max(2, min(6, cores))
        if lowPower { threads = min(4, threads) }

        cfg.nThreads = Int32(threads)
        cfg.nBatch = 256
        return cfg
    }

    private func makeWarmTurnIngestPayload(userTurnPayload: String) -> String {
        switch currentPromptFamily() {
        case .qwen:
            return chatMLBlock(role: "user", content: userTurnPayload)

        case .gemma:
            return gemmaTurn(role: "user", content: userTurnPayload)
        }
    }

    private func makeWarmTurnContinuePrefix() -> String {
        switch currentPromptFamily() {
        case .qwen:
            return qwenAssistantGenerationPrefix()
        case .gemma:
            return "<start_of_turn>model\n"
        }
    }
    
    private func streamWarmTurnViaBridgeState(
        modelPath: String,
        prepared: TurnPreparedPrompt,
        turnId: UUID,
        epoch: UInt64,
        assistantIndex: Int,
        ttftMark: ((String) -> Void)? = nil,
        ttftFirstChunkSeen: inout Bool,
        scheduleIngestOnce: @escaping (String) -> Void
    ) async throws -> (finalOut: String, cancelledDuringStream: Bool) {
        let scaffold = prepared.scaffold
        let stableKey = warmTurnStableKey(
            scaffoldHash: scaffold.scaffoldHash,
            hotHeaderHash: scaffold.hotHeaderHash,
            lateAugmentationHash: lastLateAugmentationHash
        )

        let gate = AIRuntimeStreamGate.shared
        let gateLease = await gate.acquire(label: "companion.warmTurn")

        #if DEBUG
        print("[ChatViewModel] warm WAIT/ACQUIRED gate turnId=\(turnId.uuidString)")
        #endif

        defer {
            Task {
                await gate.release(gateLease)
            }
        }

        if Task.isCancelled || epoch != self.generationEpoch {
            return ("", true)
        }

        let ingestPayload = makeWarmTurnIngestPayload(
            userTurnPayload: prepared.userTurnPayload
        )

        let ingestOK = await LlamaCppBridge.ingestTurnAndWait(
            modelPath: modelPath,
            turnText: ingestPayload,
            seqId: 0,
            nCtx: 2048,
            nThreads: 4,
            nBatch: 256
        )

        guard ingestOK else {
            self.invalidateWarmRuntime(reason: "warm_ingest_failed")
            throw LlamaBridgeError.ingestFailed(code: -5)
        }

        var cfg = makeBaseStreamConfig(
            modelPath: modelPath,
            prompt: makeWarmTurnContinuePrefix(),
            seqId: 0
        )
        cfg.promptMode = .continueFromState
        cfg.promptStableKey = stableKey

        var rawOut = ""
        var cancelledDuringStream = false

        for try await chunk in LlamaCppBridge.streamFromState(cfg) {
            if Task.isCancelled {
                cancelledDuringStream = true
                break
            }

            if epoch != self.generationEpoch {
                cancelledDuringStream = true
                break
            }

            if !ttftFirstChunkSeen {
                ttftFirstChunkSeen = true
                self.log.info("first chunk applied path=warmTurn")
            }

            self.touchTurnWatchdogChunk(turnId: turnId)
            scheduleIngestOnce("first_chunk")

            #if DEBUG
            if rawOut.isEmpty {
                ttftMark?("first_chunk")
            }
            print("[ChunkRaw]", chunk.debugDescription)
            #endif

            EventBus.shared.emit(.chunk(turnId: turnId, chars: chunk.count))

            rawOut += chunk

            if assistantIndex < self.messages.count {
                let currentVisible = self.messages[assistantIndex].text
                self.messages[assistantIndex].text = self.renderAssistantVisibleTextForStreaming(
                    raw: rawOut,
                    currentVisible: currentVisible
                )
            }
        }

        let finalVisibleOut = self.finalAssistantVisibleText(rawOut)

        if assistantIndex < self.messages.count, !finalVisibleOut.isEmpty {
            self.messages[assistantIndex].text = finalVisibleOut
            self.log.info("final chunk applied path=warmTurn chars=\(finalVisibleOut.count, privacy: .public)")
        }

        return (finalVisibleOut, cancelledDuringStream)
    }
    
    private func streamTurnViaFullPromptReplay(
        modelPath: String,
        prompt: String,
        turnId: UUID,
        epoch: UInt64,
        assistantIndex: Int,
        ttftMark: ((String) -> Void)? = nil,
        ttftFirstChunkSeen: inout Bool,
        scheduleIngestOnce: @escaping (String) -> Void
    ) async throws -> (finalOut: String, cancelledDuringStream: Bool) {
        var cfg = makeBaseStreamConfig(
            modelPath: modelPath,
            prompt: prompt,
            seqId: 0
        )
        cfg.promptMode = .fullReplay
        
        let gate = AIRuntimeStreamGate.shared
        let gateLease = await gate.acquire(label: "companion.fullReplay")

        defer {
            Task {
                await gate.release(gateLease)
            }
        }

        if Task.isCancelled || epoch != self.generationEpoch {
            return ("", true)
        }

        var rawOut = ""
        var cancelledDuringStream = false

        for try await chunk in LlamaCppBridge.stream(cfg) {
            if Task.isCancelled {
                cancelledDuringStream = true
                break
            }

            if epoch != self.generationEpoch {
                cancelledDuringStream = true
                break
            }

            if !ttftFirstChunkSeen {
                ttftFirstChunkSeen = true
                self.log.info("first chunk applied path=fullReplay")
            }

            self.touchTurnWatchdogChunk(turnId: turnId)
            scheduleIngestOnce("first_chunk")

            #if DEBUG
            if rawOut.isEmpty {
                ttftMark?("first_chunk")
            }
            print("[ChunkRaw]", chunk.debugDescription)
            #endif

            EventBus.shared.emit(.chunk(turnId: turnId, chars: chunk.count))

            rawOut += chunk

            if assistantIndex < self.messages.count {
                let currentVisible = self.messages[assistantIndex].text
                self.messages[assistantIndex].text = self.renderAssistantVisibleTextForStreaming(
                    raw: rawOut,
                    currentVisible: currentVisible
                )
            }
        }

        let finalVisibleOut = self.finalAssistantVisibleText(rawOut)

        if assistantIndex < self.messages.count, !finalVisibleOut.isEmpty {
            self.messages[assistantIndex].text = finalVisibleOut
            self.log.info("final chunk applied path=fullReplay chars=\(finalVisibleOut.count, privacy: .public)")
        }

        return (finalVisibleOut, cancelledDuringStream)
    }

    func send() {
        let userText = trimmedInput
        guard !userText.isEmpty, !isBusy, !isSecretaryBusy, !isCancelling else { return }
        log.info("send() start userChars=\(userText.count, privacy: .public)")

        generationTask?.cancel()
        generationTask = nil
        postTurnTask?.cancel()
        postTurnTask = nil
        identityLearnerTask?.cancel()
        identityLearnerTask = nil
        realmBackgroundTask?.cancel()
        realmBackgroundTask = nil
        if !companionReprimePending {
            prefixPrimeTask?.cancel()
            prefixPrimeTask = nil
        }

        if let oldTurnId = self.activeTurnId {
            self.stopTurnWatchdog(turnId: oldTurnId)
        } else {
            self.turnWatchdogTask?.cancel()
            self.turnWatchdogTask = nil
        }
        self.activeTurnId = nil
        self.activeTurnEpoch = 0
        self.activeTurnStartedAt = .distantPast
        self.activeTurnLastChunkAt = .distantPast

        generationEpoch &+= 1
        let epoch = generationEpoch

        input = ""
        isBusy = true

        messages.append(.init(role: .user, text: userText))
        messages.append(.init(role: .assistant, text: ""))
        let assistantIndex = messages.count - 1

        generationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if epoch != self.generationEpoch { return }

            var didAcquireRuntimeMode = false

            do {
                try await AIRuntimeModeGate.shared.acquire(.companion)
                didAcquireRuntimeMode = true

                #if DEBUG
                print("[ChatViewModel] runtime gate acquired mode=companion epoch=\(epoch)")
                #endif
            } catch {
                await MainActor.run {
                    if assistantIndex < self.messages.count {
                        self.messages[assistantIndex].text = "The local AI runtime is busy with Secretary mode. Try again after it finishes."
                    }

                    self.isBusy = false
                    self.generationTask = nil
                    self.input = userText
                    self.scheduleTranscriptSave()
                }
                return
            }

            defer {
                if didAcquireRuntimeMode {
                    Task {
                        await AIRuntimeModeGate.shared.release(.companion)
                    }
                }
            }

            var ttft_gotFirstChunk = false
            #if DEBUG
            let ttft_t0 = CFAbsoluteTimeGetCurrent()
            var ttft_last = ttft_t0
            func ttftMark(_ label: String) {
                let now = CFAbsoluteTimeGetCurrent()
                let stepMs = (now - ttft_last) * 1000.0
                let totalMs = (now - ttft_t0) * 1000.0
                ttft_last = now
                print(String(format: "[TTFT] %@ step=%.0fms total=%.0fms", label, stepMs, totalMs))
            }
            ttftMark("task_start")
            #endif

            let identity = self.identityVault.selected
            let identityId = identity.id
            let identityName = identity.name

            if self.runtimeStateMode == .invalidated,
               self.companionReprimePending,
               !self.isSecretaryBusy,
               !self.isCancelling
            {
                self.log.info(
                    "companion reprime wait begin trigger=\(self.pendingCompanionPrimeTrigger ?? "nil", privacy: .public)"
                )
                if let primeTask = self.prefixPrimeTask {
                    _ = await self.awaitWithTimeout(nanoseconds: 800_000_000) {
                        await primeTask.value
                        return true
                    }
                }
                if self.runtimeStateMode == .invalidated {
                    self.log.notice("companion reprime wait expired; falling back fullReplay")
                    self.companionReprimePending = false
                    self.pendingCompanionPrimeTrigger = nil
                } else {
                    self.log.info("companion reprime wait completed mode=warm")
                }
            }

            let historyBase = Array(self.messages.dropLast(2))
            var prepared = await self.prepareTurnPrompt(userText: userText, historyBase: historyBase)
            if prepared.runtimeMode == .warm,
               !lastCompanionIngestedScaffoldHash.isEmpty,
               prepared.scaffold.scaffoldHash != lastCompanionIngestedScaffoldHash {
                self.invalidateWarmRuntime(reason: "companion_scaffold_hash_drift")
                prepared = await self.prepareTurnPrompt(userText: userText, historyBase: historyBase)
            }

            #if DEBUG
            ttftMark("late_augmentation_done chars=\(prepared.lateAugmentation.count)")
            #endif

            var modelURL: URL?
            do {
                modelURL = try self.modelStore.beginAccessingModel()
                #if DEBUG
                ttftMark("model_access_ok")
                #endif
            } catch {
                if assistantIndex < self.messages.count {
                    self.messages[assistantIndex].text = "Error: \(error.localizedDescription)"
                    self.scheduleTranscriptSave()
                }
                self.isBusy = false
                self.generationTask = nil
                self.scheduleTranscriptSave()
                self.invalidateWarmRuntime(reason: "model_access_failed")
                return
            }

            let modelPath = modelURL!.path
            defer {
                if let url = modelURL { self.modelStore.stopAccessing(url) }
                self.isBusy = false
                self.generationTask = nil
                self.scheduleTranscriptSave()
            }

            let prompt = prepared.prompt

            #if DEBUG
            ttftMark("prompt_built chars=\(prompt.count)")
            #endif

            #if DEBUG
            let hasModelPrefix: Bool
            let endsWithModel: Bool

            switch self.currentPromptFamily() {
            case .qwen:
                let qwenPrefix = self.qwenAssistantGenerationPrefix()
                hasModelPrefix = prompt.contains(qwenPrefix)
                endsWithModel = prompt.hasSuffix(qwenPrefix)

            case .gemma:
                hasModelPrefix = prompt.contains("<start_of_turn>model\n")
                endsWithModel = prompt.hasSuffix("<start_of_turn>model\n")
            }

            print("[ChatViewModel] prompt template ok=\(hasModelPrefix) endsWithModel=\(endsWithModel) chars=\(prompt.count) mode=\(String(describing: prepared.runtimeMode)) histTurns=\(prepared.historyTurns)")
            #endif

            var trace = TurnTrace(
                userText: userText,
                modelPath: modelPath,
                identityVersionId: identityId,
                identityName: identityName,
                prompt: prompt
            )
            let turnId = trace.id

            let forceRemember = Self.isExplicitRememberDirective(userText)
            let forceIdentityProposal = forceRemember
                || userText.lowercased().contains("update my preferences")
                || userText.lowercased().contains("update my identity")

            var didScheduleIngest = false
            func scheduleIngestOnce(reason: String) {
                if didScheduleIngest { return }
                didScheduleIngest = true

                Task.detached(priority: .utility) {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    do {
                        _ = try await MemoryStore.shared.ingestUserText(userText, sourceTurnId: turnId)
                        #if DEBUG
                        await MainActor.run {
                            dbgPrint("[ChatViewModel] mem ingestUserText ok chars=\(userText.count) force=\(forceRemember) turnId=\(turnId.uuidString) reason=\(reason)")
                        }
                        #endif
                    } catch {
                        #if DEBUG
                        await MainActor.run {
                            dbgPrint("[ChatViewModel] mem ingestUserText FAILED err=\(error) reason=\(reason)")
                        }
                        #endif
                    }
                }
            }

            trace.identityBaselineId = identityId
            trace.identityBaselineHash = prepared.scaffold.scaffoldHash
            trace.identityOverlayHash = prepared.scaffold.hotHeaderHash
            trace.identityComposedPreview = String(prepared.scaffold.composedSystemText.prefix(800))
            trace.identityStateHash = sha256Hex(prepared.scaffold.composedSystemText)

            var didEmitTurnStarted = false
            var didEmitTurnEnded = false

            defer {
                self.stopTurnWatchdog(turnId: turnId)

                if didEmitTurnStarted && !didEmitTurnEnded {
                    let out = (assistantIndex < self.messages.count) ? self.messages[assistantIndex].text : ""
                    let didEmit = self.emitTurnFinishedOnce(turnId: turnId, outputChars: out.count)
                    if didEmit {
                        #if DEBUG
                        print("[ChatViewModel] WARNING: forced turnFinished from defer turnId=\(turnId.uuidString) outChars=\(out.count)")
                        #endif
                    }
                }
            }

            EventBus.shared.emit(.turnStarted(turnId: turnId))
            didEmitTurnStarted = true
            EventBus.shared.emit(.promptBuilt(turnId: turnId, chars: prompt.count))
            self.startTurnWatchdog(turnId: turnId, assistantIndex: assistantIndex, epoch: epoch)

            do {
                if self.useLlamaBridge {
                    let streamResult: (finalOut: String, cancelledDuringStream: Bool)

                    switch prepared.runtimeMode {
                    case .warm:
                    self.log.info("send path chosen path=warmTurn runtimeMode=warm")
                        #if DEBUG
                        print("[ChatViewModel] warm path via bridge state turnId=\(turnId.uuidString)")
                        #endif

                        do {
                            streamResult = try await self.streamWarmTurnViaBridgeState(
                                modelPath: modelPath,
                                prepared: prepared,
                                turnId: turnId,
                                epoch: epoch,
                                assistantIndex: assistantIndex,
                                ttftMark: { label in
                                    #if DEBUG
                                    ttftMark(label)
                                    #endif
                                },
                                ttftFirstChunkSeen: &ttft_gotFirstChunk,
                                scheduleIngestOnce: scheduleIngestOnce
                            )
                        } catch {
                            #if DEBUG
                            print("[ChatViewModel] warm path failed; falling back to full replay err=\(error)")
                            #endif

                            self.invalidateWarmRuntime(reason: "warm_path_failed_fallback_full_replay")

                            streamResult = try await self.streamTurnViaFullPromptReplay(
                                modelPath: modelPath,
                                prompt: prompt,
                                turnId: turnId,
                                epoch: epoch,
                                assistantIndex: assistantIndex,
                                ttftMark: { label in
                                    #if DEBUG
                                    ttftMark("fallback_" + label)
                                    #endif
                                },
                                ttftFirstChunkSeen: &ttft_gotFirstChunk,
                                scheduleIngestOnce: scheduleIngestOnce
                            )
                        }

                    case .cold, .invalidated:
                    self.log.info(
                        "send path chosen path=fullReplay runtimeMode=\(String(describing: prepared.runtimeMode), privacy: .public)"
                    )
                        #if DEBUG
                        print("[ChatViewModel] replay path mode=\(String(describing: prepared.runtimeMode)) turnId=\(turnId.uuidString)")
                        #endif

                        streamResult = try await self.streamTurnViaFullPromptReplay(
                            modelPath: modelPath,
                            prompt: prompt,
                            turnId: turnId,
                            epoch: epoch,
                            assistantIndex: assistantIndex,
                            ttftMark: { label in
                                #if DEBUG
                                ttftMark(label)
                                #endif
                            },
                            ttftFirstChunkSeen: &ttft_gotFirstChunk,
                            scheduleIngestOnce: scheduleIngestOnce
                        )
                    }

                    let identityAfter = self.currentRuntimeScaffoldSnapshot().composedSystemText
                    trace.identityDiff = computeIdentityDiff(before: prepared.identityBefore, after: identityAfter)

                    let finalOut = streamResult.finalOut
                    let cancelledDuringStream = streamResult.cancelledDuringStream

                    scheduleIngestOnce(reason: "turn_end")
                    let finishError: Error? = cancelledDuringStream ? CancellationError() : nil
                    trace.finish(output: finalOut, error: finishError)
                    TraceStore.shared.append(trace)
                    didEmitTurnEnded = self.emitTurnFinishedOnce(turnId: turnId, outputChars: finalOut.count)
                    self.stopTurnWatchdog(turnId: turnId)

                    self.scheduleTranscriptSave()

                    if !cancelledDuringStream {
                        self.updateSessionSummary(userText: userText, assistantText: String(finalOut.prefix(320)))
                        self.scheduleTranscriptSave()
                        self.markWarmRuntimeReady()

                        self.runPostTurnMaintenance(
                            forceIdentityProposal: forceIdentityProposal,
                            userText: userText,
                            assistantText: finalOut,
                            turnId: turnId,
                            scheduledEpoch: epoch
                        )
                    } else {
                        #if DEBUG
                        print("[ChatViewModel] turn cancelled turnId=\(turnId.uuidString) outChars=\(finalOut.count)")
                        #endif
                    }
                }
            } catch {
                let isCancel = (error is CancellationError) || Task.isCancelled

                let identityAfter = self.currentRuntimeScaffoldSnapshot().composedSystemText
                trace.identityDiff = computeIdentityDiff(before: prepared.identityBefore, after: identityAfter)

                let traceOut = (assistantIndex < self.messages.count) ? self.messages[assistantIndex].text : ""
                let finishErr: Error? = isCancel ? CancellationError() : error
                trace.finish(output: traceOut, error: finishErr)
                TraceStore.shared.append(trace)

                if isCancel {
                    didEmitTurnEnded = self.emitTurnFinishedOnce(turnId: turnId, outputChars: traceOut.count)
                    self.stopTurnWatchdog(turnId: turnId)
                    self.scheduleTranscriptSave()
                    #if DEBUG
                    print("[ChatViewModel] caught cancellation turnId=\(turnId.uuidString) outChars=\(traceOut.count)")
                    #endif
                    return
                }

                EventBus.shared.emit(.turnError(turnId: turnId, message: error.localizedDescription))
                didEmitTurnEnded = self.emitTurnFinishedOnce(turnId: turnId, outputChars: traceOut.count)
                self.stopTurnWatchdog(turnId: turnId)

                if assistantIndex < self.messages.count {
                    self.messages[assistantIndex].text = "Error: \(error.localizedDescription)"
                }

                self.updateSessionSummary(userText: userText, assistantText: String(traceOut.prefix(320)))
                self.scheduleTranscriptSave()
                self.invalidateWarmRuntime(reason: "turn_error")

                let bestEffortOut = (assistantIndex < self.messages.count) ? self.messages[assistantIndex].text : ""
                self.runPostTurnMaintenance(
                    forceIdentityProposal: forceIdentityProposal,
                    userText: userText,
                    assistantText: bestEffortOut,
                    turnId: turnId,
                    scheduledEpoch: epoch
                )
            }
        }
    }
    // MARK: - Transcript persistence helpers

    /// Force an immediate transcript save (used when app backgrounds).
    func flushTranscriptToDisk() {
        // Best-effort: schedule an immediate background save.
        scheduleTranscriptSave(immediate: true)
    }

    private func transcriptURL() -> URL? {
        // Main-thread safe: only return cached value.
        cachedTranscriptURL
    }

    /// Computes/creates the transcript directory and returns the transcript file URL. MUST be called off-main.
    private nonisolated static func computeTranscriptURL() -> URL? {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = base.appendingPathComponent("AnumAPP", isDirectory: true)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir.appendingPathComponent("chat_transcript_v1.json")
        } catch {
            return nil
        }
    }

    /// Loads transcript off-main and applies it on the MainActor.
    private func bootstrapTranscriptAsync() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            // Resolve URL off-main.
            let url = Self.computeTranscriptURL()

            // Read data off-main.
            let data: Data?
            if let url {
                data = try? Data(contentsOf: url)
            } else {
                data = nil
            }

            await MainActor.run {
                self.cachedTranscriptURL = url
                guard let data else { return }
                if let env = try? JSONDecoder().decode(TranscriptEnvelope.self, from: data), !env.messages.isEmpty {
                    let hasActiveTurn = self.activeTurnId != nil || self.activeTurnEpoch != 0
                    if self.isBusy || self.isSecretaryBusy || hasActiveTurn {
                        self.log.info(
                            "transcript restore skipped reason=active_turn isBusy=\(self.isBusy, privacy: .public) isSecretaryBusy=\(self.isSecretaryBusy, privacy: .public) hasActiveTurn=\(hasActiveTurn, privacy: .public)"
                        )
                        return
                    }
                    self.messages = env.messages
                    self.sessionSummary = env.sessionSummary ?? ""
                    self.log.info("loadTranscript applied messages=\(env.messages.count, privacy: .public)")
                    // RootView now owns launch-time model prewarm / scaffold prime.
                    // Do not also prime from transcript restore, or launch can double-warm.
                    #if DEBUG
                    print("[ChatViewModel] transcript restored; prefix prime deferred to RootView launch sequence")
                    #endif
                }
            }
        }
    }

    /// Schedules a KV prefix-prime after transcript restore.
    /// Important: this runs slightly later so IdentityVault/MemoryStore boot wiring has time to finish.
    /// It is safe to call multiple times; it dedups/cancels via `prefixPrimeTask`.
    private func schedulePrefixPrimeAfterRestore(trigger: String) {
        // Cancel any pending prime so we only run the latest.
        prefixPrimeTask?.cancel()

        prefixPrimeTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Give boot wiring (identity overlays, memory init, etc.) a moment to settle.
            // This prevents priming against an early/partial system prompt.
            try? await Task.sleep(nanoseconds: 450_000_000) // 450ms

            // If the user has already started a turn or a cancel is in-flight, skip.
            if self.isBusy || self.isCancelling { return }

            // Prime using the *current* composed prompt prefix (identity + restored history).
            self.primePrefixCacheIfNeeded(trigger: trigger)
        }
    }

    private func scheduleTranscriptSave(immediate: Bool = false) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                // Debounce to avoid heavy I/O during streaming.
                try? await Task.sleep(nanoseconds: self.saveDebounceNanos)
            }
            self.saveTranscriptNow()
        }
    }

    private func saveTranscriptNow() {
        // Avoid saving while cancellation is in-flight; wait for stable state.
        if isCancelling { return }

        // Snapshot on MainActor.
        let env = TranscriptEnvelope(
            version: 1,
            savedAt: Date(),
            messages: self.messages,
            sessionSummary: self.sessionSummary
        )

        let encoded = try? JSONEncoder().encode(env)

        // Snapshot MainActor-only state for use in detached task.
        let cachedURL = self.cachedTranscriptURL

        // Cancel any in-flight background write (best effort).
        backgroundSaveTask?.cancel()

        backgroundSaveTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            // Ensure URL exists off-main.
            let url = cachedURL ?? Self.computeTranscriptURL()

            // Persist cache back on MainActor if needed.
            if cachedURL == nil {
                await MainActor.run { self.cachedTranscriptURL = url }
            }

            guard let url else { return }
            guard let encoded else { return }

            do {
                try encoded.write(to: url, options: [.atomic])
            } catch {
                // Fail-open
            }
        }
    }
    private func sha256Hex(_ s: String) -> String {
        let data = Data(s.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    #if DEBUG
    private static let secretaryPromptAuditSHA256DefaultsKey = "SecretaryPromptAuditLogFullPromptSHA256Enabled"

    private func debugSecretaryPromptAuditCompanion(prompt: String, identitySystemChars: Int) {
        let systemChars: Int
        let payloadChars: Int
        switch currentPromptFamily() {
        case .qwen:
            if let start = prompt.range(of: "<|im_start|>system"),
               let end = prompt.range(of: "<|im_end|>", range: start.lowerBound..<prompt.endIndex) {
                systemChars = prompt.distance(from: start.lowerBound, to: end.upperBound)
                payloadChars = max(0, prompt.count - systemChars)
            } else {
                systemChars = identitySystemChars
                payloadChars = max(0, prompt.count - systemChars)
            }
        case .gemma:
            systemChars = identitySystemChars
            payloadChars = max(0, prompt.count - systemChars)
        }

        let sections = Self.secretaryPromptAuditSectionMarkers(prompt)
        let identitySectionsPresent = prompt.contains("## BASE")
            || prompt.contains("## ADAPT")
            || prompt.contains("## PROLOGUE")
            || prompt.contains("### SUM")
        let styleSectionsPresent = prompt.contains("SECRETARY_STYLE_FROM_USER")
        let factSectionsPresent = prompt.contains("=== PROFILE_FACTS ===")
            || prompt.contains("=== OFFER_FACTS ===")
            || prompt.contains("useful_commercial:")
        let memorySectionsPresent = prompt.contains("=== OPERATING_MEMORY_EXCERPT ===")
            || prompt.contains("[Relevant Context]")
        let companionSectionsPresent = identitySectionsPresent
        let secretarySectionsPresent = prompt.contains("You are the local Exchange intelligence worker")
            || prompt.contains("THREAD_SURFACE_ROUTING")

        var line =
            "[SecretaryPromptAudit] mode=companion promptKind=chat " +
            "systemChars=\(systemChars) payloadChars=\(payloadChars) sections=\(sections) " +
            "identitySectionsPresent=\(identitySectionsPresent) styleSectionsPresent=\(styleSectionsPresent) " +
            "factSectionsPresent=\(factSectionsPresent) memorySectionsPresent=\(memorySectionsPresent) " +
            "companionSectionsPresent=\(companionSectionsPresent) secretarySectionsPresent=\(secretarySectionsPresent)"

        if UserDefaults.standard.bool(forKey: Self.secretaryPromptAuditSHA256DefaultsKey) {
            let digest = SHA256.hash(data: Data(prompt.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            line += " promptSHA256=\(hex)"
        }

        print(line)
    }

    private static func secretaryPromptAuditSectionMarkers(_ text: String) -> String {
        var tags: [String] = []
        if text.contains("THREAD_SURFACE_ROUTING") { tags.append("THREAD_SURFACE_ROUTING") }
        if text.contains("STRUCTURED_SELLER_SURFACES") { tags.append("STRUCTURED_SELLER_SURFACES") }
        if text.contains("SECRETARY_STYLE_FROM_USER") { tags.append("SECRETARY_STYLE_FROM_USER") }
        if text.contains("User representation note:") { tags.append("User_representation_note") }
        if text.contains("Task:") { tags.append("Task") }
        if text.contains("## BASE") { tags.append("BASE") }
        if text.contains("## ADAPT") { tags.append("ADAPT") }
        if text.contains("## PROLOGUE") { tags.append("PROLOGUE") }
        if text.contains("### SUM") { tags.append("SUM") }
        if text.contains("[Relevant Context]") { tags.append("Relevant_Context") }
        return tags.joined(separator: ",")
    }
    #endif
    
    private struct QwenVisibleRender {
        let visible: String
        let hasOpenThinkBlock: Bool
        let hadThinkBlock: Bool
    }

    private func renderQwenVisibleAnswer(_ raw: String) -> QwenVisibleRender {
        var text = raw
        var hadThinkBlock = false
        var hasOpenThinkBlock = false

        while let start = text.range(of: "<think>") {
            hadThinkBlock = true

            if let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                // UI boundary only:
                // hide incomplete internal-thinking/template content from the visible chat bubble.
                text.removeSubrange(start.lowerBound..<text.endIndex)
                hasOpenThinkBlock = true
                break
            }
        }

        text = text.replacingOccurrences(of: "</think>", with: "")

        return QwenVisibleRender(
            visible: text.trimmingCharacters(in: .whitespacesAndNewlines),
            hasOpenThinkBlock: hasOpenThinkBlock,
            hadThinkBlock: hadThinkBlock
        )
    }

    private func renderAssistantVisibleText(_ raw: String) -> String {
        switch currentPromptFamily() {
        case .qwen:
            return renderQwenVisibleAnswer(raw).visible

        case .gemma:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func renderAssistantVisibleTextForStreaming(
        raw: String,
        currentVisible: String
    ) -> String {
        switch currentPromptFamily() {
        case .qwen:
            let parsed = renderQwenVisibleAnswer(raw)
            if parsed.hasOpenThinkBlock,
               parsed.visible.isEmpty,
               !currentVisible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                #if DEBUG
                print(
                    "[ChatViewModel] stream-visible hold: prevented regression to empty during open <think> span"
                )
                #endif
                return currentVisible
            }
            return parsed.visible

        case .gemma:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func finalAssistantVisibleText(_ raw: String) -> String {
        let visible = renderAssistantVisibleText(raw)
        if !visible.isEmpty {
            return visible
        }

        switch currentPromptFamily() {
        case .qwen:
            let parsed = renderQwenVisibleAnswer(raw)

            if parsed.hasOpenThinkBlock || parsed.hadThinkBlock {
                return ""
            }

            return ""

        case .gemma:
            return ""
        }
    }
    
    private func appendAssistantMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(.init(role: .assistant, text: trimmed))
        scheduleTranscriptSave()
    }

    private func appendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(.init(role: .user, text: trimmed))
        scheduleTranscriptSave()
    }
    
    // Step 5: record whether the composed identity changed during a turn.
    // We'll evolve this into a structured diff later.
    private func computeIdentityDiff(before: String, after: String) -> String? {
        guard before != after else { return nil }
        return "Identity state changed during turn"
    }


    // MARK: - Deterministic Session Summary (semantic-only)

    private func updateSessionSummary(userText: String) {
        updateSessionSummary(userText: userText, assistantText: "")
    }
    
private func updateSessionSummary(userText: String, assistantText: String) {
    // Initialize if empty, but continue so we can capture the first turn immediately.
    if sessionSummary.isEmpty {
        sessionSummary = defaultSessionSummary()
    }

    var lines = sessionSummary
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)

    // Helper: get value after prefix (trimmed)
    func getLineValue(prefix: String) -> String {
        if let idx = lines.firstIndex(where: { $0.hasPrefix(prefix) }) {
            let line = lines[idx]
            let val = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return String(val)
        }
        return ""
    }

    // Helper: set value for line with prefix
    func setLineValue(prefix: String, value: String) {
        if let idx = lines.firstIndex(where: { $0.hasPrefix(prefix) }) {
            lines[idx] = prefix + " " + value
        }
    }

    // Helper: add item to delimited list (maxItems), dedupe, keep last maxItems
    func addItem(prefix: String, item: String, maxItems: Int) {
        let normalizedItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedItem.isEmpty else { return }

        var cur = getLineValue(prefix: prefix)
        if cur == "—" || cur.isEmpty { cur = "" }

        var items = cur.isEmpty ? [] : cur.components(separatedBy: " | ")
        items = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let lowerItem = normalizedItem.lowercased()
        items = items.filter { $0.lowercased() != lowerItem }
        items.append(normalizedItem)

        if items.count > maxItems {
            items = Array(items.suffix(maxItems))
        }

        let joined = items.joined(separator: " | ")
        setLineValue(prefix: prefix, value: joined.isEmpty ? "—" : joined)
    }

    func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Deterministic NL rules
    let t = userText.trimmingCharacters(in: .whitespacesAndNewlines)
    let tl = t.lowercased()

    // --- A) Session Focus (operational classifier; does NOT override identity/memory) ---
    // Keep this tiny and stable so it doesn't fight IdentityVault.
    var focus: String? = nil
    if tl.contains("roleplay") || tl.contains("prologue") || tl.contains("scene") || tl.contains("character") {
        focus = "roleplay"
    } else if tl.contains("tone") || tl.contains("style") || tl.contains("poetic") || tl.contains("conversational") || tl.contains("emoji") {
        focus = "tone"
    } else if tl.contains("act as") || tl.contains("you are ") || tl.contains("pretend") {
        focus = "role"
    } else if tl.contains("goal") || tl.contains("plan") || tl.contains("ship") || tl.contains("testflight") {
        focus = "goals"
    } else if tl.contains("bug") || tl.contains("crash") || tl.contains("ttft") || tl.contains("latency") || tl.contains("jetsam") || tl.contains("memory") {
        focus = "debugging"
    } else if tl.contains("onboarding") {
        focus = "onboarding"
    }
    if let focus {
        setLineValue(prefix: "- Session Focus:", value: focus)
    }

    // --- B) Current Thread (what we're doing right now) ---
    // Prefer short extraction after high-signal directives.
    let threadPatterns: [(String, Bool)] = [
        ("let's ", true),
        ("lets ", true),
        ("i want to ", true),
        ("we should ", true),
        ("help me ", true),
        ("can you ", true)
    ]

    for (pat, isPrefix) in threadPatterns {
        if (isPrefix && tl.hasPrefix(pat)) || (!isPrefix && tl.contains(pat)) {
            guard let range = tl.range(of: pat) else { continue }
            let idx = range.upperBound
            let after = t[t.index(t.startIndex, offsetBy: t.distance(from: tl.startIndex, to: idx))...]
            let extracted = oneLine(String(after.prefix(120)))
            if !extracted.isEmpty {
                setLineValue(prefix: "- Current Thread:", value: extracted)
            }
            break
        }
    }

    // Roleplay-friendly fallback: if the user is describing actions/scenes and we still have no thread,
    // capture a compact version of the user input as the current thread.
    let curThreadVal = getLineValue(prefix: "- Current Thread:")
    if curThreadVal.isEmpty || curThreadVal == "—" {
        let rpMarkers = ["scene:", "setting:", "\"", "*", "we enter", "we walk", "i walk", "i open", "i step", "we step", "i look", "we look", "at the ", "in the "]
        let actionVerbs = ["walk", "enter", "open", "look", "step", "turn", "sit", "stand", "reach", "pull", "push", "whisper", "smile", "nod", "run", "hide", "follow"]

        let startsWithAction: Bool = {
            let tl2 = tl
            if tl2.hasPrefix("i ") {
                for v in actionVerbs { if tl2.hasPrefix("i \(v)") { return true } }
            }
            if tl2.hasPrefix("we ") {
                for v in actionVerbs { if tl2.hasPrefix("we \(v)") { return true } }
            }
            return false
        }()

        let looksRoleplay = startsWithAction || rpMarkers.contains(where: { tl.contains($0) })
        if looksRoleplay {
            let extracted = oneLine(String(t.prefix(120)))
            if !extracted.isEmpty {
                setLineValue(prefix: "- Current Thread:", value: extracted)
            }
        }
    }

    // --- C) Next Step (immediate next action; overwrite, don't append) ---
    // Only set when the user explicitly asks for "next" or provides a sequential instruction.
    var nextStep: String? = nil
    if tl.contains("what do i do next") || tl.contains("what next") || tl.hasPrefix("next") || tl.contains("next:") {
        if let r = tl.range(of: "next") {
            let after = t[r.upperBound...]
            let extracted = oneLine(String(after.prefix(120)))
            nextStep = extracted.isEmpty ? "follow up" : extracted
        }
    } else if tl.contains("then ") || tl.contains("after that") || tl.contains("last thing") {
        // Best effort: store a compact version of the instruction as the next step.
        nextStep = oneLine(String(t.prefix(120)))
    }
    if let nextStep, !nextStep.isEmpty {
        setLineValue(prefix: "- Next Step:", value: nextStep)
    }

    // --- D) Active Frame (stable continuity guard; do NOT restate relationship/tone/role/goals) ---
    // Set once if missing; keep generic so it doesn't compete with IdentityVault.
    let curFrame = getLineValue(prefix: "- Active Frame:")
    if curFrame.isEmpty || curFrame == "—" {
        setLineValue(prefix: "- Active Frame:", value: "Continue the current thread/scene; avoid restarting/greeting; respond in the same mode (roleplay vs practical).")
    }

    // --- E) Open Threads (up to 3 short items) ---
    let openPatterns: [(String, Bool)] = [
        ("we still need to ", false),
        ("todo", false),
        ("to do", false),
        ("tomorrow", false),
        ("later", false)
    ]

    for (pat, isPrefix) in openPatterns {
        if (isPrefix && tl.hasPrefix(pat)) || (!isPrefix && tl.contains(pat)) {
            var phrase = ""
            if let range = tl.range(of: pat) {
                let after = t[range.upperBound...]
                phrase = oneLine(String(after.prefix(120)))
            }
            if phrase.isEmpty { phrase = "follow up" }
            addItem(prefix: "- Open Threads:", item: phrase, maxItems: 3)
            break
        }
    }

    // --- F) Constraints (only capture app/system constraints, not personal preferences) ---
    let constraintPatterns = ["must", "has to", "never", "do not", "don't "]
    let systemConstraintWords: Set<String> = ["continuity", "ttft", "kv", "cache", "memory", "jetsam", "crash", "latency", "performance", "privacy", "battery", "heat"]

    for pat in constraintPatterns {
        if let range = tl.range(of: pat) {
            let window = oneLine(String(t[range.lowerBound...].prefix(140))).lowercased()
            var found = false
            for scw in systemConstraintWords {
                if window.contains(scw) {
                    found = true
                    break
                }
            }
            if found {
                let phrase = oneLine(String(t[range.lowerBound...].prefix(140)))
                addItem(prefix: "- Constraints:", item: phrase, maxItems: 3)
                break
            }
        }
    }

    // --- G) Last Answer Snapshot (tiny; helps continuity after silent restart) ---
    let a = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !a.isEmpty {
        let aOneLine = oneLine(a)
        // Avoid boot greeting and generic error placeholders.
        if aOneLine != "I'm here." && !aOneLine.hasPrefix("Error:") {
            let extracted = oneLine(String(aOneLine.prefix(140)))
            if !extracted.isEmpty {
                setLineValue(prefix: "- Last Answer Snapshot:", value: extracted)
            }
        }
    }

    // Hard cap total size
    sessionSummary = String(lines.joined(separator: "\n").prefix(1200))
}

    private func defaultSessionSummary() -> String {
        return """
- Project / Domain: Local on-device companion.
- Session Focus: —
- Current Thread: —
- Next Step: —
- Active Frame: —
- Open Threads: —
- Constraints: —
- Last Answer Snapshot: —
"""
    }
    
    private static func shouldFetchMemory(for text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return false }

        let cues = [
            "remember",
            "recall",
            "earlier",
            "before",
            "last time",
            "you said",
            "we said",
            "my preference",
            "my preferences",
            "my style",
            "my tone",
            "what was",
            "what were",
            "update my preferences",
            "update my identity"
        ]

        return cues.contains(where: { t.contains($0) })
    }
    
    // MARK: - Memory directive helpers

    /// Avoid injecting the session summary when it is still at its default placeholders.
    private static func shouldInjectSessionSummary(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }

        // If ALL placeholder lines are present, the summary is still default / low-signal.
        // If any placeholder is missing, we assume the summary carries real information.
        let placeholders = [
            "- Session Focus: —",
            "- Current Thread: —",
            "- Next Step: —",
            "- Active Frame: —",
            "- Open Threads: —",
            "- Constraints: —",
            "- Last Answer Snapshot: —"
        ]

        for p in placeholders {
            if !t.contains(p) { return true }
        }
        return false
    }

    /// Returns true if the user is explicitly asking the app to remember something.
    /// This is intentionally simple; MemoryStore should do the deeper parsing.
    private static func isExplicitRememberDirective(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("/remember ") || t.hasPrefix("/remember:") { return true }
        if t.hasPrefix("remember ") || t.hasPrefix("remember:") { return true }
        if t.hasPrefix("please remember") { return true }
        if t.contains("remember this") { return true }
        return false
    }
}

extension ChatViewModel: RealmContextProviding {
    func initialRealmStateFast() -> SymbioticRealmStore.RealmState? {
        // Keep nil for now; SymbioticRealmStore will derive from hints + recent seeds.
        return nil
    }

    func memoryHintsFast() -> [String] {
        var out: [String] = []

        let s = sessionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty { out.append(String(s.prefix(400))) }

        let idh = lastIdentityHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !idh.isEmpty { out.append(String(idh.prefix(400))) }

        let mh = lastMemoryHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mh.isEmpty { out.append(String(mh.prefix(400))) }

        return out
    }
}
