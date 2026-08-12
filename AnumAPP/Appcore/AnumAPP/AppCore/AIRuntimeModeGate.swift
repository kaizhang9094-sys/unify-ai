import Foundation

#if DEBUG
@inline(__always)
nonisolated private func aiRuntimeGateLog(_ message: String) {
    Swift.print("[AIRuntimeModeGate] \(message)")
}
#else
@inline(__always)
nonisolated private func aiRuntimeGateLog(_ message: String) {}
#endif
/// Global app-level ownership gate for local AI runtime use.
///
/// Purpose:
/// - Prevent Companion and Secretary/Exchange from driving llama at the same time.
/// - Keep runtime ownership explicit as the app grows toward multi-step secretary work.
/// - Avoid adding extra llama seq IDs on mobile.
/// - Preserve the current single-sequence, runtime-owned conversation strategy.
///
/// This is not a prompt builder.
/// This is not a model runner.
/// This is only the high-level mode ownership lock.
///
/// Recommended usage:
///
/// Companion:
///     try await AIRuntimeModeGate.shared.acquire(.companion)
///     defer { Task { await AIRuntimeModeGate.shared.release(.companion) } }
///
/// Secretary:
///     try await AIRuntimeModeGate.shared.acquire(.secretary)
///     defer { Task { await AIRuntimeModeGate.shared.release(.secretary) } }
public actor AIRuntimeModeGate {

    public static let shared = AIRuntimeModeGate()

    public enum Mode: String, Sendable, Hashable {
        case companion
        case secretary
    }

    public enum GateError: Error, LocalizedError, Sendable {
        case busy(activeMode: Mode, requestedMode: Mode)
        case releaseMismatch(activeMode: Mode?, releasingMode: Mode)

        public var errorDescription: String? {
            switch self {
            case .busy(let activeMode, let requestedMode):
                return "AI runtime is busy. Active mode: \(activeMode.rawValue), requested mode: \(requestedMode.rawValue)."

            case .releaseMismatch(let activeMode, let releasingMode):
                return "AI runtime release mismatch. Active mode: \(activeMode?.rawValue ?? "none"), releasing mode: \(releasingMode.rawValue)."
            }
        }
    }

    public struct Snapshot: Sendable, Hashable {
        public let activeMode: Mode?
        public let ownerID: UUID?
        public let acquiredAt: Date?
        public let depth: Int

        public var isBusy: Bool {
            activeMode != nil
        }
    }

    private var activeMode: Mode?
    private var ownerID: UUID?
    private var acquiredAt: Date?
    private var depth: Int = 0

    private init() {}

    /// Acquires runtime ownership for one app mode.
    ///
    /// Same-mode nested acquisition is allowed.
    /// Cross-mode acquisition throws immediately.
    public func acquire(_ mode: Mode) async throws {
        if let activeMode {
            if activeMode == mode {
                depth += 1
                aiRuntimeGateLog("reentrant acquire mode=\(mode.rawValue) depth=\(depth)")
                return
            }

            aiRuntimeGateLog("blocked requested=\(mode.rawValue) active=\(activeMode.rawValue)")
            throw GateError.busy(activeMode: activeMode, requestedMode: mode)
        }

        let id = UUID()
        self.activeMode = mode
        self.ownerID = id
        self.acquiredAt = Date()
        self.depth = 1

        aiRuntimeGateLog("acquired mode=\(mode.rawValue) owner=\(id.uuidString)")
    }

    /// Attempts runtime ownership without throwing.
    public func tryAcquire(_ mode: Mode) async -> Bool {
        do {
            try await acquire(mode)
            return true
        } catch {
            return false
        }
    }

    /// Releases runtime ownership.
    ///
    /// Same-mode nested ownership decrements depth.
    /// Final release clears ownership.
    public func release(_ mode: Mode) async {
        guard let activeMode else {
            aiRuntimeGateLog("release ignored no active mode releasing=\(mode.rawValue)")
            return
        }

        guard activeMode == mode else {
            aiRuntimeGateLog("release mismatch active=\(activeMode.rawValue) releasing=\(mode.rawValue)")
            return
        }

        if depth > 1 {
            depth -= 1
            aiRuntimeGateLog("release decrement mode=\(mode.rawValue) depth=\(depth)")
            return
        }

        let elapsedMs: Int = {
            guard let acquiredAt else { return 0 }
            return Int(Date().timeIntervalSince(acquiredAt) * 1000)
        }()

        aiRuntimeGateLog("released mode=\(mode.rawValue) elapsed=\(elapsedMs)ms")

        self.activeMode = nil
        self.ownerID = nil
        self.acquiredAt = nil
        self.depth = 0
    }

    /// Emergency reset. Use only on watchdog/cancel recovery.
    public func forceReset(reason: String) async {
        aiRuntimeGateLog(
            "forceReset reason=\(reason) active=\(activeMode?.rawValue ?? "nil") depth=\(depth)"
        )

        activeMode = nil
        ownerID = nil
        acquiredAt = nil
        depth = 0
    }

    public func snapshot() async -> Snapshot {
        Snapshot(
            activeMode: activeMode,
            ownerID: ownerID,
            acquiredAt: acquiredAt,
            depth: depth
        )
    }

    public func isBusy() async -> Bool {
        activeMode != nil
    }

    public func activeRuntimeMode() async -> Mode? {
        activeMode
    }
}
