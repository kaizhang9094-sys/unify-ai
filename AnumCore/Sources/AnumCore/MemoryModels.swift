import Foundation

public enum MemorySource: String, Codable, CaseIterable {
    case user
    case assistant
    case system
}

public enum MemoryKind: String, Codable, CaseIterable {
    /// Atomic factual statement (e.g., "my name is Kai")
    case fact
    /// Preference or aversion (e.g., "I like jazz", "I hate spam")
    case preference
    /// User state/feeling (e.g., "I feel anxious")
    case state
    /// Instruction/directive (e.g., "stop doing X", "do X")
    case instruction
    /// Past event / experience (e.g., "I went to Toronto last week")
    case event
    /// Procedure / how-to (e.g., "When I say X, do Y")
    case procedure
}

public enum MemoryStatus: String, Codable, CaseIterable {
    /// Normal memory; eligible for retrieval/injection.
    case active
    /// Known-wrong or user-forgotten memory; should be excluded from retrieval/injection by default.
    case deprecated
}

public enum MemoryTrust: String, Codable, CaseIterable {
    /// Not explicitly confirmed by the user as a durable personal fact/preference.
    case unconfirmed
    /// Explicitly confirmed (e.g., via “remember this / my name is … / yes that’s correct”).
    case confirmed
}

public enum MemoryItemType: String, Codable, CaseIterable {
    case episodic
    case semantic
    case procedural
}

public struct MemoryItem: Identifiable, Codable, Hashable {
    public let id: String
    public var type: MemoryItemType
    public var title: String
    public var body: String

    /// Separates memory spaces (e.g., identityId, userId, profile scope). Critical to avoid leakage.
    public var scope: String

    /// More specific semantic meaning than `type` (fact/preference/state/instruction/...)
    public var kind: MemoryKind

    /// Where this memory came from (user/assistant/system)
    public var source: MemorySource

    /// 0..1 confidence the parse/store is correct
    public var confidence: Double

    /// Lifecycle status of this memory (active/deprecated).
    public var status: MemoryStatus

    /// Trust level used by retrieval gating (unconfirmed vs confirmed).
    public var trust: MemoryTrust

    /// If deprecated, when it was deprecated.
    public var deprecatedAt: Date?

    /// If deprecated/superseded, the ID of the newer memory item that replaces it.
    public var replacedBy: String?

    /// Number of times this fact/preference has been explicitly confirmed.
    public var confirmedCount: Int

    /// Last time it was explicitly confirmed.
    public var lastConfirmedAt: Date?

    public var createdAt: Date
    public var lastAccessed: Date
    public var updatedAt: Date

    public var importance: Double   // 0..1
    public var salience: Double     // 0..1
    public var stability: Double    // 0..1
    public var pinned: Bool

    public var sourceTurnId: UUID?
    public var hash: String

    public init(
        id: String,
        type: MemoryItemType,
        title: String,
        body: String,
        scope: String = "global",
        kind: MemoryKind = .fact,
        source: MemorySource = .user,
        confidence: Double = 0.75,
        status: MemoryStatus = .active,
        trust: MemoryTrust = .unconfirmed,
        deprecatedAt: Date? = nil,
        replacedBy: String? = nil,
        confirmedCount: Int = 0,
        lastConfirmedAt: Date? = nil,
        createdAt: Date,
        lastAccessed: Date,
        updatedAt: Date? = nil,
        importance: Double,
        salience: Double,
        stability: Double,
        pinned: Bool,
        sourceTurnId: UUID?,
        hash: String
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body

        self.scope = scope
        self.kind = kind
        self.source = source
        self.confidence = confidence

        self.status = status
        self.trust = trust
        self.deprecatedAt = deprecatedAt
        self.replacedBy = replacedBy
        self.confirmedCount = confirmedCount
        self.lastConfirmedAt = lastConfirmedAt

        self.createdAt = createdAt
        self.lastAccessed = lastAccessed
        self.updatedAt = updatedAt ?? createdAt

        self.importance = importance
        self.salience = salience
        self.stability = stability
        self.pinned = pinned
        self.sourceTurnId = sourceTurnId
        self.hash = hash
    }
}

public struct MemoryCandidate: Identifiable, Hashable {
    public let id: String
    public let item: MemoryItem
    public let ftsRankRaw: Double?     // smaller is better (FTS bm25)
    public let score: Double           // bigger is better

    public init(item: MemoryItem, ftsRankRaw: Double?, score: Double) {
        self.id = item.id
        self.item = item
        self.ftsRankRaw = ftsRankRaw
        self.score = score
    }
}

public struct MemoryUsedItem: Codable, Hashable {
    public var id: String
    public var scope: String?
    public var kind: MemoryKind?
    public var score: Double
    public var type: MemoryItemType
    public var pinned: Bool

    public init(id: String, score: Double, type: MemoryItemType, pinned: Bool, scope: String? = nil, kind: MemoryKind? = nil) {
        self.id = id
        self.scope = scope
        self.kind = kind
        self.score = score
        self.type = type
        self.pinned = pinned
    }
}

public struct MemoryInjectionBlock: Codable, Hashable {
    public var text: String
    public var used: [MemoryUsedItem]
    public var strategy: String

    public init(text: String, used: [MemoryUsedItem] = [], strategy: String = "") {
        self.text = text
        self.used = used
        self.strategy = strategy
    }
}

public struct MemoryDebugInfo: Codable, Hashable {
    public var used: [MemoryUsedItem]
    public var query: String
    public var strategy: String

    public init(used: [MemoryUsedItem], query: String, strategy: String) {
        self.used = used
        self.query = query
        self.strategy = strategy
    }

    // Convenience initializer so existing call sites that pass tuples keep working.
    public init(used: [(id: String, score: Double, type: MemoryItemType, pinned: Bool)], query: String, strategy: String) {
        self.used = used.map { MemoryUsedItem(id: $0.id, score: $0.score, type: $0.type, pinned: $0.pinned) }
        self.query = query
        self.strategy = strategy
    }
}

public struct MemoryContextPack: Codable, Hashable {
    public var facts: [String]        // semantic
    public var events: [String]       // episodic
    public var procedures: [String]   // procedural
    public var debug: MemoryDebugInfo?

    public init(facts: [String], events: [String], procedures: [String], debug: MemoryDebugInfo?) {
        self.facts = facts
        self.events = events
        self.procedures = procedures
        self.debug = debug
    }

    public var isEmpty: Bool {
        facts.isEmpty && events.isEmpty && procedures.isEmpty
    }

    public func renderForSystem(maxLinesPerSection: Int = 8) -> String {
        guard !isEmpty else { return "" }

        func bullets(_ arr: [String]) -> String {
            arr.prefix(maxLinesPerSection).map { "- \($0)" }.joined(separator: "\n")
        }

        var out = "\n\n### MEMORY_CONTEXT (read-only)\n"
        if !facts.isEmpty {
            out += "\n[FACTS]\n" + bullets(facts) + "\n"
        }
        if !events.isEmpty {
            out += "\n[PAST_EVENTS]\n" + bullets(events) + "\n"
        }
        if !procedures.isEmpty {
            out += "\n[PROCEDURES]\n" + bullets(procedures) + "\n"
        }

        out += "\nRules:\n- Use MEMORY_CONTEXT only for factual continuity.\n- Do NOT change writing style/tone based on memory.\n"

        return out
    }
}
