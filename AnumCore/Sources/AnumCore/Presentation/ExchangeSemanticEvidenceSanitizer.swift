import Foundation

/// Strips internal scaffold/status copy before strings enter second-half evidence,
/// gap detection, probe blobs, or LLM/agency context. Returns `nil` to omit pure scaffold
/// (never UI replacement phrases like "New inquiry received").
public enum ExchangeSemanticEvidenceSanitizer: Sendable {

    private static let standaloneScaffoldLower: Set<String> = [
        "response received",
        "counterparty is asking for additional information.",
        "counterparty is asking for additional information"
    ]

    private static let leadingPrefixPatterns = [
        "(?i)^response\\s*-\\s*response\\s+received\\s*-\\s*",
        "(?i)^response\\s+received\\s*-\\s*"
    ]

    public static func sanitize(_ raw: String?) -> String? {
        guard var line = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
            return nil
        }

        line = collapseWhitespace(line)

        for pattern in leadingPrefixPatterns {
            line = line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        line = collapseWhitespace(line)
        guard !line.isEmpty else { return nil }

        if standaloneScaffoldLower.contains(line.lowercased()) {
            return nil
        }

        return line
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
