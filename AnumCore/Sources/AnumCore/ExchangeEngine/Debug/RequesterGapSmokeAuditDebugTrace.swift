#if DEBUG
import Foundation

/// DEBUG-only last prompt/raw capture for on-device requester gap compare smoke audits.
public actor RequesterGapSmokeAuditDebugTrace {
    public static let shared = RequesterGapSmokeAuditDebugTrace()

    public struct Snapshot: Sendable, Hashable {
        public var promptSentToLLMExact: String?
        public var rawLLMOutputExact: String?
        /// Parsed providerQuestions from LLM JSON before output guard (DEBUG diagnostics).
        public var rawParsedProviderQuestions: [String]

        public init(
            promptSentToLLMExact: String? = nil,
            rawLLMOutputExact: String? = nil,
            rawParsedProviderQuestions: [String] = []
        ) {
            self.promptSentToLLMExact = promptSentToLLMExact
            self.rawLLMOutputExact = rawLLMOutputExact
            self.rawParsedProviderQuestions = rawParsedProviderQuestions
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

    public func recordRawParsedProviderQuestions(_ questions: [String]) {
        snapshot.rawParsedProviderQuestions = questions
    }

    public func currentSnapshot() -> Snapshot {
        snapshot
    }
}
#endif
