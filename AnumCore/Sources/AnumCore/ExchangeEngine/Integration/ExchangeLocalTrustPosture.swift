import Foundation

/// Local-only, user-owned trust posture derived from trust graph and thread evidence.
///
/// This read model is intentionally explainable and UI-safe. Internal scoring is kept
/// local and should not be published to federation surfaces.
public struct ExchangeLocalTrustPosture: Sendable, Hashable {
    public enum Level: String, Codable, Sendable, CaseIterable, Hashable {
        case blocked
        case caution
        case new
        case known
        case reliable
        case trusted
    }

    public enum Confidence: String, Codable, Sendable, CaseIterable, Hashable {
        case unknown
        case low
        case medium
        case high
    }

    public var nodeID: String
    public var level: Level
    public var confidence: Confidence
    /// Internal-only scalar. Do not render in release UI.
    public var score: Double
    public var evidenceCount: Int
    public var positiveEvidenceCount: Int
    public var negativeEvidenceCount: Int
    public var lastInteractionAt: Date?
    public var title: String
    public var summary: String
    public var evidenceLines: [String]
    public var cautionLines: [String]
    public var isLedgerBacked: Bool
    public var isThreadContextOnly: Bool
    public var routeLabel: String?

    public init(
        nodeID: String,
        level: Level,
        confidence: Confidence,
        score: Double,
        evidenceCount: Int,
        positiveEvidenceCount: Int,
        negativeEvidenceCount: Int,
        lastInteractionAt: Date?,
        title: String,
        summary: String,
        evidenceLines: [String] = [],
        cautionLines: [String] = [],
        isLedgerBacked: Bool,
        isThreadContextOnly: Bool,
        routeLabel: String? = nil
    ) {
        self.nodeID = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.level = level
        self.confidence = confidence
        self.score = min(max(score, -1), 1)
        self.evidenceCount = max(0, evidenceCount)
        self.positiveEvidenceCount = max(0, positiveEvidenceCount)
        self.negativeEvidenceCount = max(0, negativeEvidenceCount)
        self.lastInteractionAt = lastInteractionAt
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.evidenceLines = evidenceLines
        self.cautionLines = cautionLines
        self.isLedgerBacked = isLedgerBacked
        self.isThreadContextOnly = isThreadContextOnly
        self.routeLabel = routeLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
