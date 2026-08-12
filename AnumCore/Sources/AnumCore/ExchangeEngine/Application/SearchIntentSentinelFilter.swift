import Foundation

/// Filters sentinel placeholder tokens from search-intent extraction lanes.
enum SearchIntentSentinelFilter {
    static let tokens: Set<String> = ["none", "null", "nil", "n/a", "na", "unknown"]

    static func isSentinel(_ value: String) -> Bool {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
        return trimmed.isEmpty || tokens.contains(trimmed)
    }

    static func nilIfSentinel(_ value: String?) -> String? {
        guard let value else { return nil }
        return isSentinel(value) ? nil : value
    }

    static func filterSentinels(_ values: [String]) -> [String] {
        values.filter { !isSentinel($0) }
    }
}
