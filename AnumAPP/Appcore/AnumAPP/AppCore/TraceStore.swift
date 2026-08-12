import Foundation
import Combine

@MainActor
final class TraceStore: ObservableObject {
    static let shared = TraceStore()

    @Published private(set) var traces: [TurnTrace] = []

    private let fileURL: URL?

    /// Disable trace collection/persistence (UI no longer displays it).
    /// Flip to `true` if you ever want to re-enable debugging traces.
    private let isEnabled: Bool = false

    // In-memory cap when tracing is enabled.
    private let maxKeep: Int = 80

    private init() {
        if isEnabled {
            self.fileURL = TraceStore.makeFileURL()
            self.traces = loadFromDisk()
        } else {
            self.fileURL = nil
            self.traces = []
        }
    }

    func append(_ trace: TurnTrace) {
        guard isEnabled else { return }
        traces.insert(trace, at: 0)
        if traces.count > maxKeep {
            traces = Array(traces.prefix(maxKeep))
        }
        saveToDisk()
    }

    func clearAll() {
        guard isEnabled else { return }
        traces = []
        saveToDisk()
    }

    // MARK: - Disk

    private func saveToDisk() {
        guard isEnabled, let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(traces)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Don’t crash the app for trace persistence failures.
            #if DEBUG
            print("[TraceStore] save failed: \(error)")
            #endif
        }
    }

    private func loadFromDisk() -> [TurnTrace] {
        guard isEnabled, let fileURL else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([TurnTrace].self, from: data)
        } catch {
            return []
        }
    }

    private static func makeFileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Anum", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("turn_traces.json")
    }
}
