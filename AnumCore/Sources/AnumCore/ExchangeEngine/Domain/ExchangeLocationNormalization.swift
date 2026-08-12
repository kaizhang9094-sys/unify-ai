import Foundation

/// Shared normalization for declared service areas and request location requirements.
/// Gazetteer-optional: does not infer parent regions or expand GTA unless caller supplies aliases.
public enum ExchangeLocationNormalization: Sendable {
    private static let remoteLabels: Set<String> = [
        "online", "remote", "virtual", "anywhere", "worldwide", "global"
    ]

    private static let optionalSuffixes: [String] = [
        ", on", ", ontario", ", on.", ", canada", ", ca"
    ]

    /// Normalizes a freeform location or service-area label for matching.
    public static func normalize(_ raw: String, stripRegionalSuffixes: Bool = true) -> String {
        var value = normalizeWhitespace(raw).lowercased()
        guard !value.isEmpty else { return "" }

        value = stripDiacritics(value)
        value = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"[^a-z0-9\s\-.]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if stripRegionalSuffixes {
            for suffix in optionalSuffixes {
                if value.hasSuffix(suffix) {
                    value = String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return value
    }

    public static func normalizeWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    public static func isRemoteServiceAreaLabel(_ displayOrNormalized: String) -> Bool {
        let key = normalize(displayOrNormalized, stripRegionalSuffixes: false)
        guard !key.isEmpty else { return false }
        return remoteLabels.contains(key)
    }

    /// Token set for containment checks (multi-word phrases preserved via normalized full string).
    public static func tokens(from normalized: String) -> [String] {
        let trimmed = normalize(normalized, stripRegionalSuffixes: false)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    private static func stripDiacritics(_ value: String) -> String {
        value.decomposedStringWithCompatibilityMapping
            .unicodeScalars
            .filter { scalar in
                let category = scalar.properties.generalCategory
                return category != .nonspacingMark && category != .spacingMark
            }
            .map(String.init)
            .joined()
    }
}
