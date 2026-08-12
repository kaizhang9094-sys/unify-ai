import Foundation

struct TurnTrace: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?

    // Inputs
    var userText: String
    var modelPath: String
    var identityVersionId: String
    var identityName: String

    // Identity debug (fingerprints)
    // Optional for backward compatibility with existing saved traces.
    var identityBaselineId: String?
    var identityBaselineHash: String?
    // Phase 1 identity spine (baseline + overlay)
    var identityOverlayHash: String?
    var identityComposedPreview: String?
    var identityStateVersion: Int?
    var identityStateHash: String?
    /// Optional human-readable diff from previous identity state
    var identityDiff: String?

    /// Human-readable identity fingerprint for debugging & tracing
    var identityFingerprintSummary: String {
        let base = identityBaselineId ?? "—"
        let baseHash = identityBaselineHash?.prefix(8) ?? "—"
        let stateV = identityStateVersion.map(String.init) ?? "—"
        let stateHash = identityStateHash?.prefix(8) ?? "—"
        return "baseline=\(base) (\(baseHash)) • state=v\(stateV) (\(stateHash))"
    }

    mutating func setIdentityTrace(
        baselineId: String,
        baselineHash: String,
        overlayHash: String,
        composed: String
    ) {
        self.identityBaselineId = baselineId
        self.identityBaselineHash = baselineHash
        self.identityOverlayHash = overlayHash
        self.identityComposedPreview = String(composed.prefix(280))
    }

    // Memory injection (Phase 3)
    // Defaults keep backward compatibility with older saved traces.
    var memoryHitCount: Int
    var memoryQueryHash: String?
    var memoryPreview: String?
    /// How many characters of memory context we injected into the prompt (if any)
    var memoryInjectedChars: Int?
    /// Any memory subsystem error message captured for this turn (if any)
    var memoryError: String?
    
    mutating func setMemoryTrace(queryHash: String, hitCount: Int, preview: String) {
        self.memoryQueryHash = queryHash
        self.memoryHitCount = hitCount
        self.memoryPreview = String(preview.prefix(280))
        self.memoryInjectedChars = preview.count
    }

    mutating func setMemoryError(_ message: String) {
        self.memoryError = message
    }

    // Prompt stats
    var promptChars: Int
    var promptPreview: String

    // Runtime stats
    var outputChars: Int
    var error: String?

    // Extra logs/warnings you want to surface
    var warnings: [String]

    // MARK: - Codable (backward compatible)

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case endedAt
        case userText
        case modelPath
        case identityVersionId
        case identityName
        case identityBaselineId
        case identityBaselineHash
        case identityOverlayHash
        case identityComposedPreview
        case identityStateVersion
        case identityStateHash
        case identityDiff
        case memoryHitCount
        case memoryQueryHash
        case memoryPreview
        case memoryInjectedChars
        case memoryError
        case promptChars
        case promptPreview
        case outputChars
        case error
        case warnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Stable identifiers (generate defaults if missing in older payloads)
        self.id = (try c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.startedAt = (try c.decodeIfPresent(Date.self, forKey: .startedAt)) ?? Date()
        self.endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)

        // Inputs (older payloads should still have these; default defensively)
        self.userText = (try c.decodeIfPresent(String.self, forKey: .userText)) ?? ""
        self.modelPath = (try c.decodeIfPresent(String.self, forKey: .modelPath)) ?? ""
        self.identityVersionId = (try c.decodeIfPresent(String.self, forKey: .identityVersionId)) ?? ""
        self.identityName = (try c.decodeIfPresent(String.self, forKey: .identityName)) ?? ""

        // Identity debug
        self.identityBaselineId = try c.decodeIfPresent(String.self, forKey: .identityBaselineId)
        self.identityBaselineHash = try c.decodeIfPresent(String.self, forKey: .identityBaselineHash)
        self.identityOverlayHash = try c.decodeIfPresent(String.self, forKey: .identityOverlayHash)
        self.identityComposedPreview = try c.decodeIfPresent(String.self, forKey: .identityComposedPreview)
        self.identityStateVersion = try c.decodeIfPresent(Int.self, forKey: .identityStateVersion)
        self.identityStateHash = try c.decodeIfPresent(String.self, forKey: .identityStateHash)
        self.identityDiff = try c.decodeIfPresent(String.self, forKey: .identityDiff)

        // Memory debug
        self.memoryHitCount = (try c.decodeIfPresent(Int.self, forKey: .memoryHitCount)) ?? 0
        self.memoryQueryHash = try c.decodeIfPresent(String.self, forKey: .memoryQueryHash)
        self.memoryPreview = try c.decodeIfPresent(String.self, forKey: .memoryPreview)
        self.memoryInjectedChars = try c.decodeIfPresent(Int.self, forKey: .memoryInjectedChars)
        self.memoryError = try c.decodeIfPresent(String.self, forKey: .memoryError)

        // Prompt stats
        self.promptChars = (try c.decodeIfPresent(Int.self, forKey: .promptChars)) ?? 0
        self.promptPreview = (try c.decodeIfPresent(String.self, forKey: .promptPreview)) ?? ""

        // Runtime stats
        self.outputChars = (try c.decodeIfPresent(Int.self, forKey: .outputChars)) ?? 0
        self.error = try c.decodeIfPresent(String.self, forKey: .error)

        // Extra logs/warnings
        self.warnings = (try c.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(id, forKey: .id)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)

        try c.encode(userText, forKey: .userText)
        try c.encode(modelPath, forKey: .modelPath)
        try c.encode(identityVersionId, forKey: .identityVersionId)
        try c.encode(identityName, forKey: .identityName)

        try c.encodeIfPresent(identityBaselineId, forKey: .identityBaselineId)
        try c.encodeIfPresent(identityBaselineHash, forKey: .identityBaselineHash)
        try c.encodeIfPresent(identityOverlayHash, forKey: .identityOverlayHash)
        try c.encodeIfPresent(identityComposedPreview, forKey: .identityComposedPreview)
        try c.encodeIfPresent(identityStateVersion, forKey: .identityStateVersion)
        try c.encodeIfPresent(identityStateHash, forKey: .identityStateHash)
        try c.encodeIfPresent(identityDiff, forKey: .identityDiff)

        try c.encode(memoryHitCount, forKey: .memoryHitCount)
        try c.encodeIfPresent(memoryQueryHash, forKey: .memoryQueryHash)
        try c.encodeIfPresent(memoryPreview, forKey: .memoryPreview)
        try c.encodeIfPresent(memoryInjectedChars, forKey: .memoryInjectedChars)
        try c.encodeIfPresent(memoryError, forKey: .memoryError)

        try c.encode(promptChars, forKey: .promptChars)
        try c.encode(promptPreview, forKey: .promptPreview)

        try c.encode(outputChars, forKey: .outputChars)
        try c.encodeIfPresent(error, forKey: .error)

        try c.encode(warnings, forKey: .warnings)
    }

    init(
        userText: String,
        modelPath: String,
        identityVersionId: String,
        identityName: String,
        prompt: String
    ) {
        self.id = UUID()
        self.startedAt = Date()
        self.endedAt = nil

        self.userText = userText
        self.modelPath = modelPath
        self.identityVersionId = identityVersionId
        self.identityName = identityName

        // Identity debug defaults (will be populated by ChatViewModel when available)
        self.identityBaselineId = nil
        self.identityBaselineHash = nil
        self.identityOverlayHash = nil
        self.identityComposedPreview = nil
        // Memory debug defaults (will be populated by ChatViewModel when available)
        self.memoryHitCount = 0
        self.memoryQueryHash = nil
        self.memoryPreview = nil
        self.memoryInjectedChars = nil
        self.memoryError = nil

        self.identityStateVersion = nil
        self.identityStateHash = nil
        self.identityDiff = nil

        self.promptChars = prompt.count
        self.promptPreview = TurnTrace.makePreview(prompt)

        self.outputChars = 0
        self.error = nil
        self.warnings = []
    }

    mutating func finish(output: String?, error: Error?) {
        self.endedAt = Date()
        if let output { self.outputChars = output.count }
        if let error { self.error = error.localizedDescription }
    }

    var durationMs: Int {
        guard let endedAt else { return 0 }
        return Int(endedAt.timeIntervalSince(startedAt) * 1000.0)
    }

    private static func makePreview(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLen = 320
        if trimmed.count <= maxLen { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxLen)
        return String(trimmed[..<idx]) + "…"
    }
}
