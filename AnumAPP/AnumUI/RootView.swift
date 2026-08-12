import SwiftUI
import UIKit
import Dispatch
import Combine
import LlamaCppBridge
import CrashReporter

#if DEBUG
@inline(__always) private func launchTimingLog(_ message: String) {
    let t = Date().timeIntervalSince1970
    print("[LaunchTiming] t=\(String(format: "%.3f", t)) \(message)")
}
#endif

private enum RootViewLaunchPrewarmRace: Sendable {
    case deadline
    case accessFailed
    case prewarmFinished
    case alreadyWarmed
}

struct RootView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded: Bool = false

    @AppStorage("companionName") private var companionName: String = "Uni"
    @AppStorage("companionGenderRaw") private var companionGenderRaw: String = "na"
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userGenderRaw") private var userGenderRaw: String = "na"

    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var launch: LaunchResourceMonitor
    @Environment(\.scenePhase) private var scenePhase

    @State private var resumeTask: Task<Void, Never>? = nil
    @State private var hydrationDismissTask: Task<Void, Never>? = nil
    @State private var showHydrationShield: Bool = true

    @StateObject private var modelStore = ModelStore.shared

    @State private var showCrashUploadPrompt: Bool = false
    @State private var pendingCrashReportText: String = ""
    @State private var crashUploadError: String? = nil

    @State private var showCrashShareSheet: Bool = false
    @State private var crashReportFileURL: URL? = nil

    @State private var hasCompletedInitialAppearance: Bool = false

    @State private var launchSequenceTask: Task<Void, Never>? = nil
    /// Background launch prewarm (Metal/kernel + scaffold). Must not gate shell hydration.
    @State private var launchPrewarmTask: Task<Void, Never>? = nil
    /// Bumped when starting a new launch prewarm so a stale task does not clear `launchPrewarmTask`.
    @State private var launchPrewarmEpoch: UInt64 = 0
    @State private var didFinishLaunchSequence: Bool = false
    @State private var isLaunchSequenceRunning: Bool = false
    @State private var didStartDeferredExchangeBoot: Bool = false
    @State private var hasObservedInitialActiveScene: Bool = false
    @State private var hasEnteredBackgroundSinceLaunch: Bool = false
    @State private var launchSequenceReason: String = "cold_launch"

    private var shouldShowInstallOverlay: Bool {
        switch modelStore.installState {
        case .checking, .copying, .failed:
            return true
        case .idle, .ready:
            return false
        }
    }

    private var shouldShowHydrationOverlay: Bool {
        showHydrationShield && !shouldShowInstallOverlay
    }

    var body: some View {
        rootStack
            .alert("Send crash report?", isPresented: $showCrashUploadPrompt) {
                Button("Share", role: .none) {
                    if let url = writeCrashReportToTempFile(text: pendingCrashReportText) {
                        crashReportFileURL = url
                        showCrashShareSheet = true
                    } else {
                        crashUploadError = "Failed to create crash report file"
                    }
                }

                Button("Not now", role: .cancel) { }
            } message: {
                Text("We detected a crash from the previous run. If you send this, it helps debug launch issues. No chat content should be included, but review your privacy policy before enabling uploads.")
            }
            .sheet(isPresented: $showCrashShareSheet) {
                crashShareSheetContent
            }
            .alert(
                "Crash report",
                isPresented: Binding(
                    get: { crashUploadError != nil },
                    set: { _ in crashUploadError = nil }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(crashUploadError ?? "")
            }
            .task(id: launch.mode) {
                guard launch.mode == .ready else { return }
                guard hasCompletedInitialAppearance else { return }
                guard !isLaunchSequenceRunning else { return }
                guard !didFinishLaunchSequence else { return }

                requestLaunchSequence(
                    "task_launch_mode_ready",
                    reason: hasEnteredBackgroundSinceLaunch ? launchSequenceReason : "cold_launch"
                )
            }
            .onChange(of: modelStore.installState) { _, newState in
                handleInstallStateChange(newState)
            }
            .environmentObject(services.chat)
            .animation(.easeInOut(duration: 0.20), value: hasOnboarded)
            .onChange(of: hasOnboarded) { _, _ in
                didFinishLaunchSequence = false
                showHydrationShield = true

                if launch.mode == .ready {
                    requestLaunchSequence(
                        "onChange_hasOnboarded",
                        forceRestart: true,
                        reason: "onboarding_changed"
                    )
                }
            }
            .onAppear {
                handleAppear()
                syncCanonicalLifecycleToServices(source: "rootAppear")
            }
            .onChange(of: scenePhase) { _, newPhase in
                services.updateAppScenePhase(newPhase, source: "rootScenePhase")
                handleScenePhaseChange(newPhase)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                services.updateUIApplicationState(.active, source: "didBecomeActive")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                services.updateUIApplicationState(.inactive, source: "willResignActive")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                services.updateUIApplicationState(.background, source: "didEnterBackground")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                services.updateUIApplicationState(
                    UIApplication.shared.applicationState,
                    source: "willEnterForeground"
                )
            }
            .onChange(of: modelStore.modelPath) { oldPath, newPath in
                #if DEBUG
                print(
                    "[RootView] onChange modelPath " +
                    "oldEmpty=\(oldPath.isEmpty) newEmpty=\(newPath.isEmpty) " +
                    "running=\(isLaunchSequenceRunning) finished=\(didFinishLaunchSequence) " +
                    "oldTail=\(URL(fileURLWithPath: oldPath).lastPathComponent) " +
                    "newTail=\(URL(fileURLWithPath: newPath).lastPathComponent)"
                )
                #endif

                guard oldPath != newPath else { return }

                let stablePrefix = stableLaunchScaffoldPrompt()

                if !newPath.isEmpty {
                    LlamaCppBridge.resumeAfterBackground(modelPath: newPath)
                }

                if modelStore.isLaunchPrewarmSatisfied(prefixPrompt: stablePrefix) {
                    #if DEBUG
                    print(
                        "[RootView] onChange modelPath skip alreadyWarmedSameKey " +
                        "oldEmpty=\(oldPath.isEmpty) newTail=\(URL(fileURLWithPath: newPath).lastPathComponent)"
                    )
                    #endif
                    return
                }

                // Path settle after install (empty → staged file) must not relaunch or reset cold_launch prewarm.
                if oldPath.isEmpty, !newPath.isEmpty, didFinishLaunchSequence || isLaunchSequenceRunning {
                    #if DEBUG
                    print(
                        "[RootView] onChange modelPath skip pathSettleAfterLaunch " +
                        "finished=\(didFinishLaunchSequence) running=\(isLaunchSequenceRunning)"
                    )
                    #endif
                    return
                }

                if !oldPath.isEmpty,
                   !newPath.isEmpty,
                   modelPathsRepresentSameFile(oldPath, newPath) {
                    #if DEBUG
                    print("[RootView] onChange modelPath skip sameCanonicalFile")
                    #endif
                    return
                }

                if !oldPath.isEmpty {
                    modelStore.resetPrewarmStateForCurrentModel()
                }

                // Critical:
                // During first install/restore, modelPath changes inside the launch sequence.
                // Do NOT force-restart the launch sequence from inside its own model restore.
                if isLaunchSequenceRunning {
                    #if DEBUG
                    print("[RootView] onChange modelPath ignored because launch sequence is already running")
                    #endif
                    return
                }

                didFinishLaunchSequence = false
                didStartDeferredExchangeBoot = false

                if hasCompletedInitialAppearance, launch.mode == .ready {
                    requestLaunchSequence(
                        "onChange_modelPath",
                        forceRestart: true,
                        reason: "model_path_changed"
                    )
                }
            }
    }

    private var rootStack: some View {
        ZStack {
            backgroundLayer
            mainContentLayer
            hydrationOverlayLayer
            installOverlayLayer
        }
    }

    private var backgroundLayer: some View {
        Color.black.ignoresSafeArea()
    }

    @ViewBuilder
    private var mainContentLayer: some View {
        if hasOnboarded {
            RoomView(
                companionName: $companionName,
                userName: $userName,
                onResetOnboarding: resetOnboarding
            )
            .transition(AnyTransition.opacity)
        } else {
            UnifyOnboardingFlowView(
                hasOnboarded: $hasOnboarded,
                companionName: $companionName,
                companionGenderRaw: $companionGenderRaw,
                userName: $userName,
                userGenderRaw: $userGenderRaw
            )
            .transition(AnyTransition.opacity)
        }
    }

    @ViewBuilder
    private var hydrationOverlayLayer: some View {
        if shouldShowHydrationOverlay {
            LoadingOverlayView()
                .transition(.opacity)
                .zIndex(10)
        }
    }

    @ViewBuilder
    private var installOverlayLayer: some View {
        if shouldShowInstallOverlay {
            installOverlayView
                .transition(.opacity)
                .zIndex(20)
        }
    }

    private var installOverlayView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()

                Text("Preparing Unify")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Text(installOverlaySubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)

                installFailureText
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 28)
        }
    }

    private var installOverlaySubtitle: String {
        switch modelStore.installState {
        case .checking:
            return "Checking local model readiness…"
        case .copying:
            return "First run setup — keep the app open."
        case .failed:
            return "Setup could not complete."
        case .idle, .ready:
            return ""
        }
    }

    @ViewBuilder
    private var installFailureText: some View {
        if case .failed(let msg) = modelStore.installState {
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var crashShareSheetContent: some View {
        if let url = crashReportFileURL {
            ActivityView(items: [url])
        } else {
            Text("No crash report file")
                .padding()
        }
    }

    private func stableLaunchScaffoldPrompt() -> String? {
        let prompt = services.chat.launchStableScaffoldPrompt()

        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return prompt
    }

    private func modelPathsRepresentSameFile(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        let a = URL(fileURLWithPath: lhs).standardizedFileURL.resolvingSymlinksInPath().path
        let b = URL(fileURLWithPath: rhs).standardizedFileURL.resolvingSymlinksInPath().path
        return a == b
    }

    private func requestLaunchSequence(
        _ caller: String,
        forceRestart: Bool = false,
        reason: String? = nil
    ) {
        if let reason {
            launchSequenceReason = reason
        }

        if launchSequenceReason == "model_path_changed",
           modelStore.isLaunchPrewarmSatisfied(prefixPrompt: stableLaunchScaffoldPrompt()) {
            #if DEBUG
            print(
                "[RootView] requestLaunchSequence skipped caller=\(caller) " +
                "reason=model_path_changed alreadyWarmedSameKey"
            )
            #endif
            hideHydrationIfNeeded()
            startDeferredExchangeBootIfNeeded()
            return
        }

        #if DEBUG
        print(
            "[RootView] requestLaunchSequence caller=\(caller) " +
            "forceRestart=\(forceRestart) " +
            "launchMode=\(String(describing: launch.mode)) " +
            "scenePhase=\(String(describing: scenePhase)) " +
            "running=\(isLaunchSequenceRunning) " +
            "finished=\(didFinishLaunchSequence) " +
            "hasAppeared=\(hasCompletedInitialAppearance) " +
            "observedInitialActive=\(hasObservedInitialActiveScene) " +
            "enteredBackground=\(hasEnteredBackgroundSinceLaunch) " +
            "reason=\(launchSequenceReason)"
        )
        #endif

        startLaunchSequence(forceRestart: forceRestart)
    }

    private func startLaunchSequence(forceRestart: Bool = false) {
        #if DEBUG
        print(
            "[RootView] startLaunchSequence ENTER " +
            "forceRestart=\(forceRestart) " +
            "running=\(isLaunchSequenceRunning) " +
            "finished=\(didFinishLaunchSequence) " +
            "launchMode=\(String(describing: launch.mode)) " +
            "scenePhase=\(String(describing: scenePhase)) " +
            "reason=\(launchSequenceReason)"
        )
        #endif

        guard launch.mode == .ready else { return }

        if isLaunchSequenceRunning, !forceRestart {
            return
        }

        if didFinishLaunchSequence, !forceRestart {
            hideHydrationIfNeeded()
            startDeferredExchangeBootIfNeeded()
            return
        }

        if forceRestart,
           launchSequenceReason == "model_path_changed",
           modelStore.isLaunchPrewarmSatisfied(prefixPrompt: stableLaunchScaffoldPrompt()) {
            #if DEBUG
            print("[RootView] startLaunchSequence skipped model_path_changed alreadyWarmedSameKey")
            #endif
            hideHydrationIfNeeded()
            startDeferredExchangeBootIfNeeded()
            return
        }

        resumeTask?.cancel()
        resumeTask = nil

        hydrationDismissTask?.cancel()
        hydrationDismissTask = nil

        launchSequenceTask?.cancel()

        let preserveLaunchPrewarm =
            launchSequenceReason == "model_path_changed" &&
            modelStore.isLaunchPrewarmSatisfied(prefixPrompt: stableLaunchScaffoldPrompt())
        if !preserveLaunchPrewarm {
            launchPrewarmTask?.cancel()
            launchPrewarmTask = nil
        }

        isLaunchSequenceRunning = true
        didFinishLaunchSequence = false
        showHydrationShield = true

        let sequenceReason = launchSequenceReason

        launchSequenceTask = Task { @MainActor in
            defer {
                isLaunchSequenceRunning = false
            }

            guard launch.mode == .ready else { return }

            // Let SwiftUI paint the loading overlay first.
            await Task.yield()
            guard !Task.isCancelled else { return }

            #if DEBUG
            launchTimingLog("launch sequence start reason=\(sequenceReason)")
            #endif

            // Stage 1: model file readiness / first-install copy.
            #if DEBUG
            launchTimingLog("ensureReady start reason=\(sequenceReason)")
            #endif

            await modelStore.ensureReady()

            #if DEBUG
            launchTimingLog("ensureReady end reason=\(sequenceReason)")
            #endif

            guard !Task.isCancelled else { return }

            guard case .ready = modelStore.installState else {
                showHydrationShield = true
                return
            }

            // Stage 2: resolve model path once.
            let modelURL: URL
            do {
                modelURL = try modelStore.beginAccessingModel()
            } catch {
                #if DEBUG
                print("[RootView] launchSequence: cannot access model err=\(error)")
                #endif
                showHydrationShield = true
                return
            }

            let modelPath = modelURL.path

            // Stage 3: resume native runtime with explicit model path.
            // This only clears pause flags and stores the model path.
            LlamaCppBridge.resumeAfterBackground(modelPath: modelPath)
            modelStore.stopAccessing(modelURL)

            guard !Task.isCancelled else { return }

            // Shell readiness: model file is staged and bridge has the path.
            // Do NOT await prewarm here — hydration and Exchange boot must not wait on Metal/kernel compile.
            didFinishLaunchSequence = true

            #if DEBUG
            launchTimingLog("shell ready (model file + resume) reason=\(sequenceReason)")
            #endif

            hideHydrationIfNeeded()

            #if DEBUG
            launchTimingLog("hydration hidden reason=\(sequenceReason)")
            launchTimingLog("deferred Exchange boot start reason=\(sequenceReason)")
            #endif

            startDeferredExchangeBootIfNeeded()

            // Stage 4: best-effort scaffold prewarm (may race timeout / cancel / user send cold path).
            let stableScaffoldPrompt = stableLaunchScaffoldPrompt()
            startLaunchPrewarmIfNeeded(
                stableScaffoldPrompt: stableScaffoldPrompt,
                trigger: sequenceReason
            )
        }
    }

    /// Best-effort launch prewarm: Metal/kernel + prefix scaffold. Does not gate UI.
    private func startLaunchPrewarmIfNeeded(stableScaffoldPrompt: String?, trigger: String) {
        if modelStore.isLaunchPrewarmSatisfied(prefixPrompt: stableScaffoldPrompt) {
            #if DEBUG
            launchTimingLog(
                "prewarm skipped trigger=\(trigger) reason=alreadyWarmedSameKey " +
                "prefixChars=\(stableScaffoldPrompt?.count ?? 0)"
            )
            #endif
            return
        }

        launchPrewarmTask?.cancel()
        launchPrewarmTask = nil

        launchPrewarmEpoch &+= 1
        let prewarmEpoch = launchPrewarmEpoch

        #if DEBUG
        launchTimingLog(
            "prewarm requested trigger=\(trigger) prefixChars=\(stableScaffoldPrompt?.count ?? 0) epoch=\(prewarmEpoch)"
        )
        #endif

        launchPrewarmTask = Task(priority: .utility) { @MainActor in
            defer {
                if prewarmEpoch == launchPrewarmEpoch {
                    launchPrewarmTask = nil
                }
            }

            #if DEBUG
            launchTimingLog("prewarm start trigger=\(trigger)")
            #endif

            let timeoutSeconds: UInt64 = 12
            let timeoutNanoseconds = timeoutSeconds * 1_000_000_000

            let raceOutcome = await withTaskGroup(of: RootViewLaunchPrewarmRace.self) { group -> RootViewLaunchPrewarmRace in
                group.addTask { @MainActor in
                    var accessURL: URL?
                    defer {
                        if let url = accessURL {
                            modelStore.stopAccessing(url)
                        }
                    }

                    do {
                        accessURL = try modelStore.beginAccessingModel()
                    } catch {
                        #if DEBUG
                        launchTimingLog(
                            "prewarm failed beginAccessingModel trigger=\(trigger) err=\(String(describing: error))"
                        )
                        #endif
                        return .accessFailed
                    }

                    let outcome = await modelStore.prewarmForLaunchIfNeeded(
                        prefixPrompt: stableScaffoldPrompt
                    )

                    switch outcome {
                    case .warmedNewly:
                        #if DEBUG
                        launchTimingLog("prewarm success warmedNewly trigger=\(trigger)")
                        #endif
                        return .prewarmFinished
                    case .alreadyWarmedSameKey:
                        #if DEBUG
                        launchTimingLog(
                            "prewarm skipped trigger=\(trigger) reason=alreadyWarmedSameKey"
                        )
                        #endif
                        return .alreadyWarmed
                    case .skippedEmptyModelPath:
                        #if DEBUG
                        launchTimingLog(
                            "prewarm skipped trigger=\(trigger) reason=skippedEmptyModelPath"
                        )
                        #endif
                        return .accessFailed
                    }
                }

                group.addTask {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    return .deadline
                }

                let first = await group.next() ?? .deadline
                group.cancelAll()

                if first == .deadline {
                    #if DEBUG
                    launchTimingLog(
                        "prewarm timeout trigger=\(trigger) timeoutSeconds=\(timeoutSeconds)"
                    )
                    #endif
                    modelStore.resetPrewarmStateForCurrentModel()
                }

                for await _ in group {}

                return first
            }

            guard !Task.isCancelled else {
                #if DEBUG
                launchTimingLog("prewarm cancelled trigger=\(trigger)")
                #endif
                modelStore.resetPrewarmStateForCurrentModel()
                return
            }

            switch raceOutcome {
            case .deadline:
                #if DEBUG
                launchTimingLog(
                    "prewarm end without noteLaunchRuntimePrepared trigger=\(trigger) reason=timeout"
                )
                #endif

            case .accessFailed:
                #if DEBUG
                launchTimingLog(
                    "prewarm end without noteLaunchRuntimePrepared trigger=\(trigger) reason=accessFailed"
                )
                #endif

            case .prewarmFinished:
                if modelStore.markLaunchRuntimeNotifiedIfNeeded(prefixPrompt: stableScaffoldPrompt) {
                    services.chat.noteLaunchRuntimePrepared(trigger: trigger)
                    #if DEBUG
                    launchTimingLog("noteLaunchRuntimePrepared called trigger=\(trigger)")
                    #endif
                } else {
                    #if DEBUG
                    launchTimingLog(
                        "noteLaunchRuntimePrepared skipped trigger=\(trigger) reason=alreadyNotifiedSameKey"
                    )
                    #endif
                }

            case .alreadyWarmed:
                #if DEBUG
                launchTimingLog(
                    "prewarm end without noteLaunchRuntimePrepared trigger=\(trigger) reason=alreadyWarmedSameKey"
                )
                #endif
            }
        }
    }

    private func hideHydrationIfNeeded() {
        guard showHydrationShield else { return }

        withAnimation(.easeInOut(duration: 0.16)) {
            showHydrationShield = false
        }
    }

    private func startDeferredExchangeBootIfNeeded() {
        guard !didStartDeferredExchangeBoot else { return }
        didStartDeferredExchangeBoot = true
        services.startDeferredExchangeBoot()
    }

    private func scheduleHydrationDismiss(after delay: TimeInterval = 0.18) {
        hydrationDismissTask?.cancel()

        hydrationDismissTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else { return }
            guard didFinishLaunchSequence else { return }

            hideHydrationIfNeeded()
        }
    }

    private func handleInstallStateChange(_ newState: ModelStore.InstallState) {
        switch newState {
        case .ready:
            if hasCompletedInitialAppearance, !didFinishLaunchSequence, !isLaunchSequenceRunning {
                requestLaunchSequence(
                    "installState_ready",
                    reason: launchSequenceReason
                )
            }

        case .checking, .copying:
            showHydrationShield = true

        case .idle:
            break

        case .failed:
            launchSequenceTask?.cancel()
            launchSequenceTask = nil

            launchPrewarmTask?.cancel()
            launchPrewarmTask = nil

            didFinishLaunchSequence = false
            isLaunchSequenceRunning = false
            showHydrationShield = true
        }
    }

    private func handleAppear() {
        _ = services.orchestrator

        loadPendingCrashReportIfNeeded()

        hasCompletedInitialAppearance = true

        if !didFinishLaunchSequence {
            showHydrationShield = true
        }

        if launch.mode == .ready {
            requestLaunchSequence(
                "handleAppear",
                reason: "cold_launch"
            )
        }
    }

    private func syncCanonicalLifecycleToServices(source: String) {
        services.updateAppScenePhase(scenePhase, source: source)
        services.updateUIApplicationState(UIApplication.shared.applicationState, source: source)
    }

    private func loadPendingCrashReportIfNeeded() {
        let hadPending = CrashCapture.shared.hasPendingCrashReport()

        CrashCapture.shared.loadPendingReportIfAny { text in
            pendingCrashReportText = text
            showCrashUploadPrompt = !text.isEmpty

            if hadPending && text.isEmpty {
                crashUploadError = "Crash detected, but report text was empty (load/format may have failed)."
            }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            hasEnteredBackgroundSinceLaunch = true

            resumeTask?.cancel()
            resumeTask = nil

            launchSequenceTask?.cancel()
            launchSequenceTask = nil

            launchPrewarmTask?.cancel()
            launchPrewarmTask = nil

            isLaunchSequenceRunning = false

            hydrationDismissTask?.cancel()
            hydrationDismissTask = nil

            // Native llama state is no longer guaranteed.
            // Keep transcript continuity, but force ChatViewModel out of warm incremental mode.
            services.chat.prepareForAppBackground()

            // Best effort cancellation of any in-flight generation.
            services.chat.cancelGeneration()
            services.chat.flushTranscriptToDisk()

            // Pause native runtime. Bridge decides whether to destroy immediately or keep resident.
            LlamaCppBridge.pauseForBackground()

            // Foreground must validate/rebuild runtime state.
            didFinishLaunchSequence = false
            modelStore.resetPrewarmStateForCurrentModel()

        case .active:
            guard hasCompletedInitialAppearance else { return }

            // The first .active after cold launch is not foreground recovery.
            // Do not invalidate ChatViewModel or force full replay just because SwiftUI became active.
            if !hasObservedInitialActiveScene {
                hasObservedInitialActiveScene = true

                if launch.mode == .ready, !isLaunchSequenceRunning, !didFinishLaunchSequence {
                    requestLaunchSequence(
                        "scene_active_initial",
                        reason: "cold_launch"
                    )
                }
                return
            }

            // Only real background -> active should be treated as foreground recovery.
            guard hasEnteredBackgroundSinceLaunch else {
                if launch.mode == .ready {
                    requestLaunchSequence(
                        "scene_active_no_background",
                        reason: launchSequenceReason
                    )
                }
                return
            }

            hasEnteredBackgroundSinceLaunch = false

            services.chat.prepareForAppForeground()

            Task { @MainActor in
                #if DEBUG
                print("[RootView] foreground federation sync scheduled (syncFederationOnAppActive)")
                #endif
                await services.syncFederationOnAppActive()
            }

            if isLaunchSequenceRunning {
                return
            }

            showHydrationShield = true

            requestLaunchSequence(
                "scene_active_foreground_recovery",
                forceRestart: true,
                reason: "foreground_recovery"
            )

        case .inactive:
            services.chat.flushTranscriptToDisk()

        default:
            break
        }
    }

    private func writeCrashReportToTempFile(text: String) -> URL? {
        guard !text.isEmpty else { return nil }

        let ts = ISO8601DateFormatter().string(from: Date())
        let safeTS = ts
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")

        let fileName = "Unify_CrashReport_\(safeTS).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try text.data(using: .utf8)?.write(to: url, options: [.atomic])
            return url
        } catch {
            #if DEBUG
            print("[CrashCapture] failed to write crash report: \(error)")
            #endif
            return nil
        }
    }

    private struct ActivityView: UIViewControllerRepresentable {
        let items: [Any]

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }

    private struct LoadingOverlayView: View {
        @State private var dotPhase: Int = 0
        @State private var dotsTask: Task<Void, Never>? = nil

        private let loadingAccent = Color(red: 1.00, green: 0.86, blue: 0.45)

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .tint(loadingAccent.opacity(0.92))

                    HStack(spacing: 0) {
                        Text("Loading")
                        Text("...")
                            .opacity([0.25, 0.55, 0.85, 1.0][min(dotPhase, 3)])
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(loadingAccent.opacity(0.92))
                    .monospaced()
                }
                .padding(.horizontal, 28)
            }
            .onAppear {
                if dotsTask == nil {
                    dotsTask = Task { @MainActor in
                        while !Task.isCancelled {
                            dotPhase = (dotPhase + 1) % 4
                            try? await Task.sleep(nanoseconds: 350_000_000)
                        }
                    }
                }
            }
            .onDisappear {
                dotsTask?.cancel()
                dotsTask = nil
            }
        }
    }

    private func resetOnboarding() {
        services.chat.clearRecentChat()

        hasOnboarded = false
        companionName = "Uni"
        companionGenderRaw = "na"
        userName = ""
        userGenderRaw = "na"
        UnifyOnboardingKeys.clearV2Keys()
    }
}

// MARK: - Onboarding v2 keys (shared with UnifyOnboardingFlowView / RoomOptionsSheet)

enum UnifyOnboardingKeys {
    static let completedVersion = "onboarding.completedVersion"
    static let sawAutonomyExplainer = "onboarding.sawAutonomyExplainer"
    static let aiName = "onboarding.aiName"
    static let secretaryMode = "Anum.room.isSecretaryMode"

    /// Clears v2-only keys (used when resetting onboarding).
    static func clearV2Keys() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: completedVersion)
        ud.removeObject(forKey: sawAutonomyExplainer)
        ud.removeObject(forKey: aiName)
    }
}

// MARK: - Crash Capture (PLCrashReporter)

final class CrashCapture {
    static let shared = CrashCapture()

    private lazy var reporter: PLCrashReporter? = {
        let cfg = PLCrashReporterConfig(
            signalHandlerType: .BSD,
            symbolicationStrategy: .all
        )

        return PLCrashReporter(configuration: cfg)
    }()

    private init() {}

    func enable() {
        guard let reporter else { return }

        do {
            try reporter.enableAndReturnError()
        } catch {
            #if DEBUG
            print("[CrashCapture] enable failed: \(error)")
            #endif
        }
    }

    func hasPendingCrashReport() -> Bool {
        guard let reporter else { return false }
        return reporter.hasPendingCrashReport()
    }

    func loadPendingReportIfAny(_ onMain: @escaping (String) -> Void) {
        guard let reporter else {
            Task { @MainActor in onMain("") }
            return
        }

        DispatchQueue.global(qos: .utility).async {
            guard reporter.hasPendingCrashReport() else {
                Task { @MainActor in onMain("") }
                return
            }

            do {
                let data = try reporter.loadPendingCrashReportDataAndReturnError()
                reporter.purgePendingCrashReport()

                let report = try PLCrashReport(data: data)

                let text = PLCrashReportTextFormatter.stringValue(
                    for: report,
                    with: PLCrashReportTextFormatiOS
                ) ?? ""

                Task { @MainActor in onMain(text) }
            } catch {
                #if DEBUG
                print("[CrashCapture] load failed: \(error)")
                #endif

                Task { @MainActor in onMain("") }
            }
        }
    }
}
