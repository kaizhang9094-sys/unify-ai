import Foundation

/// User-facing secretary copy only — derived from deterministic pause evidence + style.
/// Must never replace thread state or pause semantics; validated before projection/persistence.
public struct ExchangeRequesterClosureComposedCopy: Codable, Hashable, Sendable {
    public var title: String
    public var summary: String
    public var answeredBullets: [String]
    public var stillOpenBullets: [String]
    public var recommendation: String
    public var nextActionLabel: String

    public init(
        title: String,
        summary: String,
        answeredBullets: [String] = [],
        stillOpenBullets: [String] = [],
        recommendation: String,
        nextActionLabel: String
    ) {
        self.title = title
        self.summary = summary
        self.answeredBullets = answeredBullets
        self.stillOpenBullets = stillOpenBullets
        self.recommendation = recommendation
        self.nextActionLabel = nextActionLabel
    }
}
