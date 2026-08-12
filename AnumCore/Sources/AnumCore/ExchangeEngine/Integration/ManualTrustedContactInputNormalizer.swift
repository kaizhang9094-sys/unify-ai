import Foundation

/// Normalizes user paste input for "Add contact" / "Add trusted node" into a canonical node id string.
public enum ManualTrustedContactInputNormalizer: Sendable {
    public enum Source: String, Sendable {
        case raw
        case embedded
        case link
        case failed
    }

    public struct ParseResult: Sendable, Hashable {
        public let nodeID: String?
        public let source: Source
    }

    /// Returns a trimmed node id, optionally extracted from a pasted URL or query string.
    public static func normalizedNodeID(from raw: String) -> String? {
        parse(raw).nodeID
    }

    /// Returns node id and coarse parse source token for UI diagnostics.
    public static func parse(_ raw: String) -> ParseResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ParseResult(nodeID: nil, source: .failed) }

        if let embedded = extractEmbeddedNodeID(from: trimmed) {
            return ParseResult(nodeID: embedded, source: .embedded)
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            if let fromURL = extractNodeIDFromURL(url) {
                return ParseResult(nodeID: fromURL, source: .link)
            }
        }

        if looksLikeNodeID(trimmed) {
            return ParseResult(nodeID: trimmed, source: .raw)
        }

        return ParseResult(nodeID: nil, source: .failed)
    }

    private static func extractNodeIDFromURL(_ url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let names = Set(["nodeid", "node_id", "node", "target", "id", "n"])
            for item in components.queryItems ?? [] {
                guard names.contains(item.name.lowercased()),
                      let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty
                else { continue }
                if let embedded = extractEmbeddedNodeID(from: value) { return embedded }
                return value
            }
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty {
            let segments = path.split(separator: "/").map(String.init)
            for segment in segments.reversed() {
                let candidate = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.isEmpty { continue }
                if let embedded = extractEmbeddedNodeID(from: candidate) { return embedded }
                if looksLikeNodeID(candidate) { return candidate }
            }
        }

        return nil
    }

    private static func extractEmbeddedNodeID(from text: String) -> String? {
        let pattern = #"(?i)\b(node-[a-z0-9][a-z0-9\-._]{2,})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func looksLikeNodeID(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("node-")
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
