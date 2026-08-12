#if DEBUG
import Foundation

/// DEBUG-only last prompt/raw capture for on-device search-intent extraction smoke audits.
public actor SearchIntentExtractionDebugTrace {
    public static let shared = SearchIntentExtractionDebugTrace()

    public struct Snapshot: Sendable, Hashable {
        public var promptSentToLLMExact: String?
        public var rawLLMOutputExact: String?

        public init(
            promptSentToLLMExact: String? = nil,
            rawLLMOutputExact: String? = nil
        ) {
            self.promptSentToLLMExact = promptSentToLLMExact
            self.rawLLMOutputExact = rawLLMOutputExact
        }
    }

    private var snapshot = Snapshot()

    private init() {}

    public func reset() {
        snapshot = Snapshot()
    }

    public func recordPrompt(_ prompt: String) {
        snapshot.promptSentToLLMExact = prompt
    }

    public func recordRaw(_ raw: String) {
        snapshot.rawLLMOutputExact = raw
    }

    public func currentSnapshot() -> Snapshot {
        snapshot
    }
}
#endif
