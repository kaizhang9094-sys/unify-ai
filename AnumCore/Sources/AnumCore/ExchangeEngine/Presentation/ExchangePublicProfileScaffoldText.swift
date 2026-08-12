import Foundation

/// Rejects legacy/default public-profile scaffold strings from publish and retrieval projection.
enum ExchangePublicProfileScaffoldText: Sendable {

    private static let blockedSubstrings: [String] = [
        "public coordination surface for offers and seller-side discovery",
        "offers and seller-side discovery",
        "public coordination surface",
        "seller-side discovery",
        "coordination surface",
        "seller surface",
        "buyer requests",
        "inbound coordination",
        "node-owned public seller surface"
    ]

    private static let blockedExactOpenToTokens: Set<String> = [
        "buyer requests",
        "inbound coordination",
        "introductions",
        "seller surface"
    ]

    static func isGenerated(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        let lower = trimmed.lowercased()
        if blockedExactOpenToTokens.contains(lower) { return true }

        for needle in blockedSubstrings where lower.contains(needle) {
            return true
        }

        if lower.hasSuffix(" seller surface") && trimmed.count <= 80 {
            return true
        }

        if lower == "seller surface" { return true }

        return false
    }

    static func filteredOptional(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerated(trimmed) else { return nil }
        return trimmed
    }

    static func filteredBlocks(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            guard let kept = filteredOptional(value) else { continue }
            let key = kept.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(kept)
        }
        return out
    }
}
