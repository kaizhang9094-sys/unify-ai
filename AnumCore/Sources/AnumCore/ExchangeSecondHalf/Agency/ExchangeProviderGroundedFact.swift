import Foundation

public enum ExchangeProviderFactSource: String, Codable, Hashable, Sendable {
    case offer
    case publicProfile
    case operatingMemory
    case thread
}

public struct ExchangeProviderGroundedFact: Codable, Hashable, Sendable {
    public var text: String
    public var source: ExchangeProviderFactSource
    public var field: String?

    public init(
        text: String,
        source: ExchangeProviderFactSource,
        field: String? = nil
    ) {
        self.text = text
        self.source = source
        self.field = field
    }
}
