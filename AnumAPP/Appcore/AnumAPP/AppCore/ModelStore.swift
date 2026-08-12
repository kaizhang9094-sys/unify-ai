import Foundation
import Combine
import UniformTypeIdentifiers
import LlamaCppBridge
import OSLog

#if canImport(AppKit)
import AppKit
#endif

// MARK: - DEBUG Logging

#if DEBUG
@inline(__always) private func msLog(_ msg: String) { print("[ModelStore] \(msg)") }
#else
@inline(__always) private func msLog(_ msg: String) { }
#endif

@MainActor
final class ModelStore: ObservableObject {
    static let shared = ModelStore()
    private let runtimeLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AnumAPP",
        category: "ModelStoreRuntime"
    )

    // MARK: - Bundled model (prepacked)

    // Current bundled model:
    // Qwen3.5 2B Q4_K_M, app-renamed as "Unify1.0.gguf".
    private let bundledModelResourceName = "Unify1.0"
    private let bundledModelExtension = "gguf"

    enum InstallState: Equatable {
        case idle
        case checking
        case copying
        case ready
        case failed(String)
    }

    // First-install robustness.
    // Current bundled model is ~1.28 GB. Keep enough room for bundle copy,
    // temporary file movement, Application Support staging, and OS pressure.
    private let minFreeSpaceBytes: Int64 = 3_000_000_000      // ~3 GB recommended
    private let minFreeSpaceHardBytes: Int64 = 2_000_000_000  // hard fail below this

    @Published private(set) var installState: InstallState = .idle

    @Published private(set) var modelDisplayName: String = "No model selected"
    @Published private(set) var modelURL: URL? = nil
    @Published private(set) var modelPath: String = ""   // convenience for llama.cpp

    // macOS bookmark persistence
    private let bookmarkKey = "Anum.selectedModel.bookmark"

    // iOS/macOS fallback: persist copied path
    private let pathKey = "Anum.selectedModel.path"

    // MARK: - Prewarm

    private enum PrewarmState: Equatable {
        case idle
        case warming(String)
        case warmed(String)
    }

    private var prewarmState: PrewarmState = .idle
    private var prewarmTask: Task<Void, Never>? = nil
    /// Guards `ChatViewModel.noteLaunchRuntimePrepared` to once per launch prewarm key.
    private var launchRuntimeNotifiedKey: String?

    /// Result of `prewarmForLaunchIfNeeded` for caller-level idempotency (bridge may already be warm).
    enum LaunchPrewarmOutcome: Sendable, Equatable {
        case warmedNewly
        case alreadyWarmedSameKey
        case skippedEmptyModelPath
    }

    /// Fire-and-forget compatibility API.
    /// Use this from non-launch paths only.
    ///
    /// Important:
    /// This now uses AIRuntimeStreamGate so non-launch kernel prewarm cannot overlap
    /// with companion generation, secretary generation, launch prewarm, identity learner,
    /// realm background, or any other llama.cpp call.
    func requestPrewarmIfNeeded() {
        let p = self.modelPath
        guard !p.isEmpty else { return }

        let key = prewarmKey(path: p, prefixPrompt: nil)

        switch prewarmState {
        case .warmed(let warmedKey) where warmedKey == key:
            return

        case .warming(let warmingKey) where warmingKey == key:
            return

        default:
            break
        }

        prewarmState = .warming(key)
        msLog("requestPrewarmIfNeeded() key=\(key) path=\(p)")

        prewarmTask?.cancel()
        prewarmTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            let streamLease = await AIRuntimeStreamGate.shared.acquire(
                label: "modelStore.kernelPrewarm"
            )

            defer {
                Task {
                    await AIRuntimeStreamGate.shared.release(streamLease)
                }
            }

            LlamaCppBridge.prewarm(modelPath: p)

            await MainActor.run {
                if case .warming(let warmingKey) = self.prewarmState,
                   warmingKey == key {
                    self.prewarmState = .warmed(key)
                    msLog("requestPrewarmIfNeeded() completed key=\(key)")
                }
            }
        }
    }

    /// True when launch prewarm already completed or is in-flight for the current model path + prefix key.
    func isLaunchPrewarmSatisfied(prefixPrompt: String? = nil) -> Bool {
        let p = modelPath
        guard !p.isEmpty else { return false }
        let key = prewarmKey(path: p, prefixPrompt: prefixPrompt)
        switch prewarmState {
        case .warmed(let warmedKey) where warmedKey == key:
            return true
        case .warming(let warmingKey) where warmingKey == key:
            return true
        default:
            return false
        }
    }

    /// Awaitable launch-path prewarm (Metal/kernel + optional scaffold prefix).
    /// RootView runs this from a non-blocking utility task after shell readiness; hydration does not await it.
    ///
    /// Important:
    /// This now uses AIRuntimeStreamGate so launch scaffold prewarm cannot overlap with
    /// companion / secretary / Exchange model calls.
    ///
    /// Do NOT acquire AIRuntimeModeGate here.
    /// Prewarm is native runtime maintenance, not companion or secretary product mode.
    @discardableResult
    func prewarmForLaunchIfNeeded(prefixPrompt: String? = nil) async -> LaunchPrewarmOutcome {
        let p = self.modelPath
        guard !p.isEmpty else { return .skippedEmptyModelPath }

        let key = prewarmKey(path: p, prefixPrompt: prefixPrompt)

        switch prewarmState {
        case .warmed(let warmedKey) where warmedKey == key:
            msLog("prewarmForLaunchIfNeeded() skip alreadyWarmedSameKey key=\(key)")
            return .alreadyWarmedSameKey

        case .warming(let warmingKey) where warmingKey == key:
            msLog("prewarmForLaunchIfNeeded() already warming key=\(key)")
            await prewarmTask?.value
            return .alreadyWarmedSameKey

        default:
            break
        }

        prewarmState = .warming(key)
        let pwT0 = Date()
        msLog("prewarmForLaunchIfNeeded() BEGIN key=\(key) path=\(p) prefixChars=\(prefixPrompt?.count ?? 0)")
        runtimeLog.info(
            "launch prewarm begin key=\(key, privacy: .public) prefixChars=\(prefixPrompt?.count ?? 0, privacy: .public)"
        )

        let prompt = prefixPrompt

        let task = Task.detached(priority: .utility) {
            let streamLease = await AIRuntimeStreamGate.shared.acquire(
                label: "launch.prewarm"
            )

            defer {
                Task {
                    await AIRuntimeStreamGate.shared.release(streamLease)
                }
            }

            await LlamaCppBridge.prewarmAndWait(
                modelPath: p,
                prefixPrompt: prompt,
                nCtx: 2048,
                nThreads: 4,
                nBatch: 256
            )
        }

        prewarmTask = task
        await task.value

        let pwElapsed = Date().timeIntervalSince(pwT0)

        if case .warming(let warmingKey) = prewarmState,
           warmingKey == key {
            prewarmState = .warmed(key)
            msLog(
                "prewarmForLaunchIfNeeded() END warmed key=\(key) elapsedSeconds=\(String(format: "%.3f", pwElapsed))"
            )
            runtimeLog.info("launch prewarm end key=\(key, privacy: .public) result=warmed")
            return .warmedNewly
        }

        msLog(
            "prewarmForLaunchIfNeeded() END without warmed state key=\(key) elapsedSeconds=\(String(format: "%.3f", pwElapsed)) prewarmState=\(String(describing: prewarmState))"
        )
        if case .warmed(let warmedKey) = prewarmState, warmedKey == key {
            return .alreadyWarmedSameKey
        }
        return .skippedEmptyModelPath
    }

    /// Returns true the first time per launch prewarm key; suppresses duplicate runtime-prepared notifications.
    func markLaunchRuntimeNotifiedIfNeeded(prefixPrompt: String? = nil) -> Bool {
        let p = modelPath
        guard !p.isEmpty else { return false }
        let key = prewarmKey(path: p, prefixPrompt: prefixPrompt)
        if launchRuntimeNotifiedKey == key {
            return false
        }
        launchRuntimeNotifiedKey = key
        return true
    }

    /// Use this if the model path changes or a debug reset invalidates llama state.
    func resetPrewarmStateForCurrentModel() {
        prewarmTask?.cancel()
        prewarmTask = nil
        prewarmState = .idle
        launchRuntimeNotifiedKey = nil
    }

    private init() {
        // IMPORTANT:
        // Do not auto-run ensureReady() from init.
        // First-run staging should be gated by UI preflight so low-storage /
        // memory-pressure devices fail-soft instead of crashing on first frame.
    }

    // MARK: - Public API

    private func diskCaps() -> (important: Int64, opportunistic: Int64, general: Int64) {
        // Prefer iOS capacity signals that account for purgeable space.
        // If nil, fall back to general available capacity.
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityForOpportunisticUsageKey,
                .volumeAvailableCapacityKey
            ])

            let general = Int64(values.volumeAvailableCapacity ?? 0)
            let important = values.volumeAvailableCapacityForImportantUsage ?? general
            let opportunistic = values.volumeAvailableCapacityForOpportunisticUsage ?? general

            return (
                important: important,
                opportunistic: opportunistic,
                general: general
            )
        } catch {
            return (
                important: -1,
                opportunistic: -1,
                general: -1
            )
        }
    }

    private func freeDiskBytes() -> Int64 {
        // Backward-compatible helper used by older call sites.
        let caps = diskCaps()
        return caps.important
    }

    private func prewarmKey(path: String, prefixPrompt: String?) -> String {
        let prefix = prefixPrompt ?? ""
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return "kernel|\(path)"
        }

        return "prefix|\(path)|\(abs(prefix.hashValue))|len=\(prefix.count)"
    }

    private func canProceedWithInstall() -> Bool {
        let caps = diskCaps()

        // If unknown, fail-open. Caller still handles copy/read errors.
        if caps.important < 0 || caps.opportunistic < 0 {
            return true
        }

        // Hard gate on both important + opportunistic usage to reduce partial-copy failures.
        return caps.important >= minFreeSpaceHardBytes &&
               caps.opportunistic >= minFreeSpaceHardBytes
    }

    private func insufficientStorageMessage(
        caps: (important: Int64, opportunistic: Int64, general: Int64)
    ) -> String {
        "Not enough free storage to prepare the on-device model. Unify needs about 2–3 GB free for first-run setup with the current model. Free space and reopen. (Important: \(caps.important) bytes, Opportunistic: \(caps.opportunistic) bytes)"
    }

    /// Ensures the bundled model is staged and readable. Safe to call multiple times.
    func ensureReady() async {
        if case .ready = installState, modelURL != nil { return }
        if case .copying = installState { return }

        let ensureT0 = Date()
        msLog("ensureReady() BEGIN state=\(installState) modelURL=\(modelURL?.path ?? "nil")")

        installState = .checking
        msLog("installState -> checking")

        let caps = diskCaps()
        msLog("diskCaps important=\(caps.important) opportunistic=\(caps.opportunistic) general=\(caps.general)")

        guard canProceedWithInstall() else {
            let msg = insufficientStorageMessage(caps: caps)
            msLog("installState -> failed (insufficient storage)")
            installState = .failed(msg)
            msLog("ensureReady() END state=\(installState) modelURL=\(modelURL?.path ?? "nil")")
            return
        }

        if caps.important > 0, caps.important < minFreeSpaceBytes {
            // Soft warning only. Copy may still succeed depending on purgeable space.
            msLog("WARNING: low free storage for first install (important=\(caps.important) < recommended=\(minFreeSpaceBytes))")
        }

        installState = .copying
        msLog("installState -> copying")

        // Restore prefers bundled model. On iOS this stages bundle -> Application Support.
        restore()

        msLog("restore() finished; modelURL=\(modelURL?.path ?? "nil") modelDisplayName=\(modelDisplayName)")

        if modelURL != nil {
            installState = .ready
        } else {
            installState = .failed(modelDisplayName)
        }

        let ensureElapsed = Date().timeIntervalSince(ensureT0)
        msLog(
            "ensureReady() END state=\(installState) modelURL=\(modelURL?.path ?? "nil") elapsedSeconds=\(String(format: "%.3f", ensureElapsed))"
        )

        // Prewarm is intentionally not triggered here.
        // RootView / LaunchGate should call requestPrewarmIfNeeded() or prewarmForLaunchIfNeeded()
        // only when viable.
    }

    /// Start access to model URL if needed and return a usable URL.
    ///
    /// macOS: returns security-scoped URL; caller must call stopAccessing(_:).
    /// iOS: returns sandbox URL; stopAccessing is a no-op.
    func beginAccessingModel() throws -> URL {
        if case .checking = installState {
            msLog("beginAccessingModel(): install in progress (checking)")
            throw ModelStoreError.installInProgress
        }

        if case .copying = installState {
            msLog("beginAccessingModel(): install in progress (copying)")
            throw ModelStoreError.installInProgress
        }

        if modelURL == nil {
            // Policy: never trigger bundled-model staging/copy unless storage is viable.
            // beginAccessingModel() can be called from multiple paths; keep it safe.
            let caps = diskCaps()
            if !canProceedWithInstall() {
                let msg = insufficientStorageMessage(caps: caps)
                installState = .failed(msg)
                throw ModelStoreError.insufficientStorage(msg)
            }

            // Self-heal: restore bundled/saved model if possible.
            restore()
        }

        guard let url = modelURL else {
            throw ModelStoreError.noModelSelected
        }

        #if canImport(AppKit)
        guard url.startAccessingSecurityScopedResource() else {
            throw ModelStoreError.failedToStartSecurityScope
        }
        return url
        #else
        return url
        #endif
    }

    func stopAccessing(_ url: URL) {
        #if canImport(AppKit)
        url.stopAccessingSecurityScopedResource()
        #else
        _ = url
        #endif
    }

    // MARK: - Picking

    #if canImport(AppKit)
    /// macOS file picker using NSOpenPanel + security-scoped bookmark.
    func pickModel() {
        let panel = NSOpenPanel()
        panel.title = "Choose a GGUF model"
        panel.message = "Select a .gguf model file for Anūm to run locally."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if let gguf = UTType(filenameExtension: "gguf") {
            panel.allowedContentTypes = [gguf]
        } else {
            panel.allowedContentTypes = [.data]
        }

        panel.directoryURL = URL(fileURLWithPath: "/Users/Shared/AnumModels", isDirectory: true)

        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { return }

            guard url.pathExtension.lowercased() == "gguf" else {
                self.modelDisplayName = "Please select a .gguf file"
                return
            }

            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw ModelStoreError.failedToStartSecurityScope
                }
                defer { url.stopAccessingSecurityScopedResource() }

                try self.assertReadable(url: url)
                try self.saveBookmark(for: url)

                self.modelURL = url
                self.modelPath = url.path
                self.modelDisplayName = url.lastPathComponent
                UserDefaults.standard.set(self.modelPath, forKey: self.pathKey)
                self.resetPrewarmStateForCurrentModel()
            } catch {
                self.clearState(message: "Failed to save model: \(error.localizedDescription)")
            }
        }
    }
    #else
    /// iOS: call this from SwiftUI .fileImporter completion.
    /// Copies the selected model into Application Support so it is always accessible.
    func acceptPickedModel(fromSecurityScopedURL url: URL) {
        Task { @MainActor in
            do {
                guard url.pathExtension.lowercased() == "gguf" else {
                    throw ModelStoreError.notAGGUF(url.lastPathComponent)
                }

                let started = url.startAccessingSecurityScopedResource()
                defer {
                    if started {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                try assertReadable(url: url)

                let dest = try copyIntoAppContainer(url: url)

                self.modelURL = dest
                self.modelPath = dest.path
                self.modelDisplayName = dest.lastPathComponent
                UserDefaults.standard.set(self.modelPath, forKey: self.pathKey)
                self.resetPrewarmStateForCurrentModel()
            } catch {
                self.clearState(message: "Failed to import model: \(error.localizedDescription)")
            }
        }
    }
    #endif

    // MARK: - Restore

    private func restore() {
        msLog("restore() BEGIN")

        // 0) Prefer bundled model. Users do not have to pick anything.
        if restoreFromBundledModel() {
            return
        }

        #if canImport(AppKit)
        // 1) macOS: prefer bookmark if user previously picked a different model.
        if restoreBookmark() { return }

        // 2) Fall back to saved path.
        restoreFromSavedPath()
        #else
        // iOS: restore from saved path in app container.
        restoreFromSavedPath()

        // If saved path is empty/missing, make one more best-effort attempt to restore bundled.
        if self.modelURL == nil {
            _ = restoreFromBundledModel()
        }
        #endif
    }

    /// Loads the bundled model.
    /// macOS: use bundle URL directly.
    /// iOS: copy bundle -> Application Support/Models once, then use that URL.
    private func restoreFromBundledModel() -> Bool {
        msLog("restoreFromBundledModel() BEGIN")

        let bundledURL: URL?

        if let exact = Bundle.main.url(
            forResource: bundledModelResourceName,
            withExtension: bundledModelExtension
        ) {
            bundledURL = exact
        } else {
            // Fallback exists only to make dev builds less brittle.
            // Production should package the exact Unify1.0.gguf resource.
            bundledURL = Bundle.main
                .urls(forResourcesWithExtension: bundledModelExtension, subdirectory: nil)?
                .first
        }

        guard let bundledURL else {
            self.modelDisplayName = "Bundled model missing — check Copy Bundle Resources"
            self.modelURL = nil
            self.modelPath = ""
            return false
        }

        #if canImport(AppKit)
        do {
            try assertReadable(url: bundledURL)

            modelURL = bundledURL
            modelPath = bundledURL.path
            modelDisplayName = bundledURL.lastPathComponent

            UserDefaults.standard.set(modelPath, forKey: pathKey)
            resetPrewarmStateForCurrentModel()

            return true
        } catch {
            self.modelDisplayName = "Bundled model unreadable: \(error.localizedDescription)"
            self.modelURL = nil
            self.modelPath = ""
            return false
        }
        #else
        do {
            let copied = try ensureBundledModelCopiedToAppSupport(bundledURL: bundledURL)
            try assertReadable(url: copied)

            modelURL = copied
            modelPath = copied.path
            modelDisplayName = copied.lastPathComponent

            msLog("restoreFromBundledModel() OK modelURL=\(copied.path)")

            UserDefaults.standard.set(modelPath, forKey: pathKey)
            resetPrewarmStateForCurrentModel()

            return true
        } catch {
            self.modelDisplayName = "Bundled model restore failed: \(error.localizedDescription)"
            self.modelURL = nil
            self.modelPath = ""
            return false
        }
        #endif
    }

    private func restoreFromSavedPath() {
        msLog("restoreFromSavedPath() BEGIN")

        let savedPath = UserDefaults.standard.string(forKey: pathKey) ?? ""
        guard !savedPath.isEmpty else {
            modelURL = nil
            modelPath = ""
            modelDisplayName = "No model selected"
            return
        }

        let url = URL(fileURLWithPath: savedPath)

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                try assertReadable(url: url)

                modelURL = url
                modelPath = url.path
                modelDisplayName = url.lastPathComponent
            } catch {
                clearState(message: "Model looks corrupted — restoring bundled model")
            }
        } else {
            clearState(message: "Model not found — restoring bundled model")
        }
    }

    // MARK: - macOS bookmark persistence

    #if canImport(AppKit)
    private func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.synchronize()
    }

    /// Returns true if restored.
    private func restoreBookmark() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return false
        }

        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                guard url.startAccessingSecurityScopedResource() else {
                    throw ModelStoreError.failedToStartSecurityScope
                }
                defer { url.stopAccessingSecurityScopedResource() }

                try saveBookmark(for: url)
            }

            try assertReadable(url: url)

            modelURL = url
            modelPath = url.path
            modelDisplayName = url.lastPathComponent

            UserDefaults.standard.set(modelPath, forKey: pathKey)
            resetPrewarmStateForCurrentModel()

            return true
        } catch {
            return false
        }
    }
    #endif

    // MARK: - iOS copy into sandbox

    #if !canImport(AppKit)
    private func ensureBundledModelCopiedToAppSupport(bundledURL: URL) throws -> URL {
        let fm = FileManager.default

        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let modelsDir = appSupport.appendingPathComponent("Models", isDirectory: true)

        if !fm.fileExists(atPath: modelsDir.path) {
            try fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }

        let dest = modelsDir.appendingPathComponent(
            "\(bundledModelResourceName).\(bundledModelExtension)"
        )

        let bundledSize = try fileSizeBytes(bundledURL)

        // If already copied, validate it.
        if fm.fileExists(atPath: dest.path) {
            do {
                try assertReadable(url: dest)

                let existingSize = try fileSizeBytes(dest)
                if existingSize != bundledSize {
                    throw ModelStoreError.sizeMismatch(
                        dest.lastPathComponent,
                        expected: bundledSize,
                        got: existingSize
                    )
                }

                return dest
            } catch {
                try? fm.removeItem(at: dest)
            }
        }

        // Copy from bundle -> app support atomically.
        let uuidSuffix = UUID().uuidString.prefix(8)
        let tempName = "\(bundledModelResourceName).\(bundledModelExtension).\(uuidSuffix).tmp"
        let tempURL = modelsDir.appendingPathComponent(tempName)

        do {
            try fm.copyItem(at: bundledURL, to: tempURL)
        } catch {
            try? fm.removeItem(at: tempURL)
            throw error
        }

        if fm.fileExists(atPath: dest.path) {
            do {
                _ = try fm.replaceItemAt(dest, withItemAt: tempURL)
            } catch {
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: tempURL, to: dest)
            }
        } else {
            try fm.moveItem(at: tempURL, to: dest)
        }

        let finalSize = try fileSizeBytes(dest)

        if finalSize != bundledSize {
            try? fm.removeItem(at: dest)

            throw ModelStoreError.sizeMismatch(
                dest.lastPathComponent,
                expected: bundledSize,
                got: finalSize
            )
        }

        try assertReadable(url: dest)

        return dest
    }

    private func copyIntoAppContainer(url: URL) throws -> URL {
        let fm = FileManager.default

        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let modelsDir = appSupport.appendingPathComponent("Models", isDirectory: true)

        if !fm.fileExists(atPath: modelsDir.path) {
            try fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }

        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var dest = modelsDir.appendingPathComponent("\(baseName).\(ext)")

        if fm.fileExists(atPath: dest.path) {
            let suffix = UUID().uuidString.prefix(8)
            dest = modelsDir.appendingPathComponent("\(baseName)-\(suffix).\(ext)")
        }

        let uuidSuffix = UUID().uuidString.prefix(8)
        let tempName = "\(baseName).\(ext).\(uuidSuffix).tmp"
        let tempURL = modelsDir.appendingPathComponent(tempName)

        let sourceSize = try fileSizeBytes(url)

        do {
            do {
                try fm.copyItem(at: url, to: tempURL)
            } catch {
                try? fm.removeItem(at: tempURL)
                throw error
            }

            if fm.fileExists(atPath: dest.path) {
                do {
                    _ = try fm.replaceItemAt(dest, withItemAt: tempURL)
                } catch {
                    try? fm.removeItem(at: dest)
                    try fm.moveItem(at: tempURL, to: dest)
                }
            } else {
                try fm.moveItem(at: tempURL, to: dest)
            }

            let destSize = try fileSizeBytes(dest)

            if destSize != sourceSize {
                try? fm.removeItem(at: dest)

                throw ModelStoreError.sizeMismatch(
                    dest.lastPathComponent,
                    expected: sourceSize,
                    got: destSize
                )
            }

            try assertReadable(url: dest)

            return dest
        } catch {
            try? fm.removeItem(at: tempURL)
            try? fm.removeItem(at: dest)

            throw error
        }
    }
    #endif

    // MARK: - Helpers

    private func fileSizeBytes(_ url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func assertReadable(url: URL) throws {
        if !FileManager.default.isReadableFile(atPath: url.path) {
            throw ModelStoreError.notReadable(url.path)
        }

        // Validate GGUF header.
        var handle: FileHandle?

        do {
            handle = try FileHandle(forReadingFrom: url)

            let data = try handle?.read(upToCount: 4)

            try handle?.close()
            handle = nil

            guard let data, data.count == 4 else {
                throw ModelStoreError.invalidGGUFHeader(url.lastPathComponent)
            }

            let magic = String(data: data, encoding: .ascii)

            guard magic == "GGUF" else {
                throw ModelStoreError.invalidGGUFHeader(url.lastPathComponent)
            }
        } catch let error as ModelStoreError {
            throw error
        } catch {
            try? handle?.close()

            throw ModelStoreError.openFailed(
                url.path,
                underlying: error.localizedDescription
            )
        }

        // Basic sanity check: model file should not be tiny.
        do {
            let size = try fileSizeBytes(url)

            if size < 10_000_000 {
                throw ModelStoreError.tooSmall(url.lastPathComponent, bytes: size)
            }

            if url.pathExtension.lowercased() == "gguf", size < 100_000_000 {
                throw ModelStoreError.tooSmall(url.lastPathComponent, bytes: size)
            }
        } catch let error as ModelStoreError {
            throw error
        } catch {
            // Ignore metadata failure after header validation.
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
        } catch {
            throw ModelStoreError.openFailed(
                url.path,
                underlying: error.localizedDescription
            )
        }
    }

    private func clearState(message: String) {
        modelURL = nil
        modelPath = ""
        modelDisplayName = message

        UserDefaults.standard.set("", forKey: pathKey)

        resetPrewarmStateForCurrentModel()

        // If a bundled model exists, immediately fall back to it.
        _ = restoreFromBundledModel()
    }
}

enum ModelStoreError: LocalizedError {
    case noModelSelected
    case installInProgress
    case insufficientStorage(String)
    case failedToStartSecurityScope
    case notAGGUF(String)
    case notReadable(String)
    case openFailed(String, underlying: String)
    case tooSmall(String, bytes: Int64)
    case sizeMismatch(String, expected: Int64, got: Int64)
    case invalidGGUFHeader(String)

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No model selected. Please pick a GGUF file."

        case .installInProgress:
            return "Preparing the on-device model. Please keep the app open."

        case .insufficientStorage(let msg):
            return msg

        case .failedToStartSecurityScope:
            return "Failed to access the selected file under sandbox permissions. Pick again."

        case .notAGGUF(let name):
            return "Please select a .gguf file (got: \(name))."

        case .notReadable(let path):
            return "Selected file is not readable: \(path)"

        case .openFailed(let path, let underlying):
            return "Could not open file: \(path) (\(underlying))"

        case .tooSmall(let name, let bytes):
            return "Bundled model looks incomplete (\(name), \(bytes) bytes). Check Copy Bundle Resources."

        case .sizeMismatch(let name, let expected, let got):
            return "Model copy looks incomplete (\(name)). Expected \(expected) bytes, got \(got) bytes."

        case .invalidGGUFHeader(let name):
            return "File does not look like a GGUF model: \(name)"
        }
    }
}
