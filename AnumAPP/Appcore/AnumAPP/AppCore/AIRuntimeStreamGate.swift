import Foundation

#if DEBUG
@inline(__always)
nonisolated private func aiRuntimeStreamGateLog(_ message: @autoclosure () -> String) {
    Swift.print("[AIRuntimeStreamGate] \(message())")
}
#else
@inline(__always)
nonisolated private func aiRuntimeStreamGateLog(_ message: @autoclosure () -> String) {}
#endif

/// Global app-level stream gate for llama.cpp access.
///
/// Purpose:
/// - Prevent overlapping calls into LlamaCppBridge.stream / streamFromState / ingest.
/// - Shared by Companion, Secretary/Exchange, identity learner, realm background, prefix prime.
/// - Complements AIRuntimeModeGate:
///   - AIRuntimeModeGate owns high-level app mode: companion vs secretary.
///   - AIRuntimeStreamGate owns actual native llama stream access.
///
/// Mobile rule:
/// Keep one active llama operation at a time.
/// Do not rely on multiple seq IDs for concurrent work on small context devices.
public actor AIRuntimeStreamGate {

    public static let shared = AIRuntimeStreamGate()

    public struct Lease: Sendable, Equatable, Hashable {
        public let id: UUID
        public let label: String
        public let acquiredAt: Date

        public init(
            id: UUID = UUID(),
            label: String,
            acquiredAt: Date = Date()
        ) {
            self.id = id
            self.label = label
            self.acquiredAt = acquiredAt
        }
    }

    public struct Snapshot: Sendable, Hashable {
        public let isLocked: Bool
        public let ownerID: UUID?
        public let ownerLabel: String?
        public let acquiredAt: Date?
        public let waiterCount: Int
    }

    private struct Waiter: Sendable {
        let label: String
        let continuation: CheckedContinuation<Lease, Never>
    }

    private var locked: Bool = false
    private var owner: Lease?
    private var waiters: [Waiter] = []

    private init() {}

    /// Waits until the stream gate is available, then returns a lease.
    public func acquire(label: String = "unspecified") async -> Lease {
        await withCheckedContinuation { continuation in
            if !locked {
                locked = true
                let lease = Lease(label: label)
                owner = lease

                aiRuntimeStreamGateLog("acquired label=\(label) owner=\(lease.id.uuidString)")
                continuation.resume(returning: lease)
            } else {
                waiters.append(
                    Waiter(
                        label: label,
                        continuation: continuation
                    )
                )

                aiRuntimeStreamGateLog(
                    "queued label=\(label) active=\(owner?.label ?? "nil") waiters=\(waiters.count)"
                )
            }
        }
    }

    /// Attempts to acquire without waiting.
    public func tryAcquire(label: String = "unspecified") async -> Lease? {
        guard !locked else {
            aiRuntimeStreamGateLog("tryAcquire denied label=\(label) active=\(owner?.label ?? "nil")")
            return nil
        }

        locked = true
        let lease = Lease(label: label)
        owner = lease

        aiRuntimeStreamGateLog("tryAcquire acquired label=\(label) owner=\(lease.id.uuidString)")
        return lease
    }

    /// Releases a lease. Mismatched releases are ignored.
    public func release(_ lease: Lease) async {
        guard locked, owner?.id == lease.id else {
            aiRuntimeStreamGateLog(
                "release ignored lease=\(lease.id.uuidString) label=\(lease.label) active=\(owner?.id.uuidString ?? "nil")"
            )
            return
        }

        let elapsedMs = Int(Date().timeIntervalSince(lease.acquiredAt) * 1000)

        if waiters.isEmpty {
            locked = false
            owner = nil

            aiRuntimeStreamGateLog(
                "released label=\(lease.label) elapsed=\(elapsedMs)ms waiters=0"
            )
            return
        }

        let next = waiters.removeFirst()
        let nextLease = Lease(label: next.label)
        owner = nextLease
        locked = true

        aiRuntimeStreamGateLog(
            "released label=\(lease.label) elapsed=\(elapsedMs)ms -> next=\(next.label) waiters=\(waiters.count)"
        )

        next.continuation.resume(returning: nextLease)
    }

    /// Emergency escape hatch. Use only on watchdog/cancel/runtime recovery.
    public func forceUnlock(reason: String) async {
        aiRuntimeStreamGateLog(
            "forceUnlock reason=\(reason) active=\(owner?.label ?? "nil") waiters=\(waiters.count)"
        )

        locked = false
        owner = nil

        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            let nextLease = Lease(label: next.label)
            locked = true
            owner = nextLease

            aiRuntimeStreamGateLog(
                "forceUnlock resumed next=\(next.label) waiters=\(waiters.count)"
            )

            next.continuation.resume(returning: nextLease)
        }
    }

    /// Severe lifecycle reset.
    ///
    /// This clears the current owner and drops queued waiters except the first.
    /// Because acquire() uses a non-throwing continuation, we cannot notify queued
    /// waiters with cancellation. To avoid giving multiple callers fake ownership,
    /// only one waiter may become the new owner.
    public func forceReset(reason: String) async {
        aiRuntimeStreamGateLog(
            "forceReset reason=\(reason) active=\(owner?.label ?? "nil") waiters=\(waiters.count)"
        )

        locked = false
        owner = nil

        guard !waiters.isEmpty else { return }

        let next = waiters.removeFirst()
        waiters.removeAll()

        let nextLease = Lease(label: next.label)
        locked = true
        owner = nextLease

        aiRuntimeStreamGateLog(
            "forceReset resumed next=\(next.label) droppedRemainingWaiters"
        )

        next.continuation.resume(returning: nextLease)
    }

    public func snapshot() async -> Snapshot {
        Snapshot(
            isLocked: locked,
            ownerID: owner?.id,
            ownerLabel: owner?.label,
            acquiredAt: owner?.acquiredAt,
            waiterCount: waiters.count
        )
    }

    public func isBusy() async -> Bool {
        locked
    }
}
