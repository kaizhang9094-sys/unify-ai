import Foundation

/// Provenance for how `ExchangeCanonicalSearchIntent` was produced.
public enum SearchIntentExtractionSource: String, Codable, Sendable, Hashable {
    case llm
    case llmFlatSummary
    case llmRepairedJSON
    case heuristicFallback
}

public enum SearchIntentExtractionFailureReason: String, Codable, Sendable, Hashable {
    case providerUnavailable
    case modelBusy
    case timeout
    case cancelled
    case invalidJSON
    case repairFailed
    case emptyDTO
    case unsafeDTO
    case nonActionableDTO
    case thrownError
}

public struct SearchIntentExtractionDiagnostics: Sendable, Hashable {
    public var attemptedLLM: Bool
    public var source: SearchIntentExtractionSource
    public var fallbackReason: SearchIntentExtractionFailureReason?
    public var repairAttempted: Bool
    public var timeoutSeconds: Double?
    public var elapsedMs: Int?
    public var decodeErrorSummary: String?
    public var compactCanonicalSummary: String?
    /// Atomic object text retained from compact flat decode even when canonical mapping/actionability failed.
    public var compactDecodedObjectHint: String?

    public init(
        attemptedLLM: Bool,
        source: SearchIntentExtractionSource,
        fallbackReason: SearchIntentExtractionFailureReason? = nil,
        repairAttempted: Bool = false,
        timeoutSeconds: Double? = nil,
        elapsedMs: Int? = nil,
        decodeErrorSummary: String? = nil,
        compactCanonicalSummary: String? = nil,
        compactDecodedObjectHint: String? = nil
    ) {
        self.attemptedLLM = attemptedLLM
        self.source = source
        self.fallbackReason = fallbackReason
        self.repairAttempted = repairAttempted
        self.timeoutSeconds = timeoutSeconds
        self.elapsedMs = elapsedMs
        self.decodeErrorSummary = decodeErrorSummary
        self.compactCanonicalSummary = compactCanonicalSummary
        self.compactDecodedObjectHint = compactDecodedObjectHint
    }
}

public actor SearchIntentExtractionDiagnosticsStore {
    private(set) var last: SearchIntentExtractionDiagnostics?

    public init() {}

    public func record(_ value: SearchIntentExtractionDiagnostics) {
        last = value
    }

    /// Clears the last recorded diagnostics (call at the start of a new extraction attempt).
    public func reset() {
        last = nil
    }
}
