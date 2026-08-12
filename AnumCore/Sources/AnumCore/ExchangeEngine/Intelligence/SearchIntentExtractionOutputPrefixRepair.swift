import Foundation

/// Reattaches a partial JSON assistant prefix for `searchIntentExtraction` when the model stream returns only the value continuation (compact `raw` field).
public enum SearchIntentExtractionOutputPrefixRepair: Sendable {
    /// - Returns: `(output, didRepair)` where `didRepair` is true when `{"raw":` was prepended or a closing `}` was added for a compact summary object.
    public static func reconstructJSONIfNeeded(_ text: String) -> (output: String, didRepair: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("{") {
            return (trimmed, false)
        }

        if trimmed.hasPrefix("\""), trimmed.hasSuffix("}") {
            return ("{\"raw\":" + trimmed, true)
        }

        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            return ("{\"raw\":" + trimmed + "}", true)
        }

        return (text, false)
    }
}

/// Repairs narrowly scoped flat-summary JSON glitches from on-device models (escaped key/value separators).
public enum SearchIntentExtractionFlatSummaryJSONRepair: Sendable {
    private static let knownKeys: [String] = [
        "raw", "object", "need", "place", "time", "budget", "commercial",
        "mods", "hard", "soft", "gaps", "confidence"
    ]

    /// Fixes `"time\":\"value"` and similar escaped known-key separators → `"time":"value"`.
    public static func repairEscapedKeyValueSeparators(_ text: String) -> String {
        guard text.contains("\\\"") else { return text }

        // Do literal known-key prefix repair first. This is the exact live failure shape:
        // `"time\":\"this Saturday...` → `"time":"this Saturday...`
        let literalRepaired = literalEscapedSeparatorRepair(text)

        if let regex = escapedSeparatorRegex {
            let range = NSRange(literalRepaired.startIndex..., in: literalRepaired)
            return regex.stringByReplacingMatches(
                in: literalRepaired,
                options: [],
                range: range,
                withTemplate: #""$1":""#
            )
        }

        return literalRepaired
    }

    private static let escapedSeparatorRegex: NSRegularExpression? = {
        let keys = knownKeys.joined(separator: "|")
        let pattern = "\"(\(keys))(?:\\\\\")+:(?:\\\\\")+"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private static func literalEscapedSeparatorRepair(_ text: String) -> String {
        var out = text

        for key in knownKeys {
            let fixed = "\"\(key)\":\""

            let variants = [
                "\"\(key)\\\":\\\"",
                "\"\(key)\\\\\":\\\\\"",
                "\"\(key)\\\\\\\":\\\\\\\"",
                "\\\"\(key)\\\":\\\"",
                "\\\"\(key)\\\\\":\\\\\"",
                "\\\"\(key)\\\\\\\":\\\\\\\""
            ]

            for broken in variants where out.contains(broken) {
                out = out.replacingOccurrences(of: broken, with: fixed)
            }
        }

        out = out.replacingOccurrences(of: "\\\",\\\"", with: "\",\"")
        out = out.replacingOccurrences(of: "\\\",", with: "\",")

        return out
    }
}
