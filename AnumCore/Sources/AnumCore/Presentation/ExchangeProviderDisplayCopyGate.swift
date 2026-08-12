import Foundation

/// Filters provider display copy so user-facing surfaces never show routing/retrieval/debug tokens.
enum ExchangeProviderDisplayCopyGate {
    private static let forbiddenSubstrings: [String] = [
        "matchcandidatesweak",
        "noviablematch",
        "publicdiscoverable",
        "semanticproof",
        "bm25",
        " vector",
        "vector ",
        "rrf",
        "retrievalscore",
        "thin_pool",
        "thin pool",
        "activethreadexcluded",
        "publicprofilecapability",
        "candidatecoordination",
        "umbrellasearch",
        "umbrella search",
        "cached suggestion",
        "directory",
        "retrieval document",
        "seller surface",
        "unify node",
        "profile-node",
        "node-owned",
        "coordination surface",
        "fit-engine",
        "semantic proof",
        "match reason:",
        "matched offer ids",
        "public profile id",
        "primary offer id",
        "offline",
    ]

    static func acceptsUserFacingLine(_ raw: String?) -> String? {
        guard var line = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
            return nil
        }

        let lower = line.lowercased()
        if shouldDropEntirely(lower) {
            return nil
        }

        if let sanitized = ExchangeUserFacingCopySanitizer.sanitize(line, field: .general) {
            line = sanitized
        } else {
            return nil
        }

        let recheck = line.lowercased()
        if shouldDropEntirely(recheck) {
            return nil
        }

        return line.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    static func acceptsBadgeLabel(_ raw: String?) -> String? {
        guard let line = acceptsUserFacingLine(raw) else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 48 else {
            return String(trimmed.prefix(48)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func acceptsCategoryBadge(_ raw: String?) -> String? {
        guard let line = acceptsUserFacingLine(raw) else { return nil }
        let lower = line.lowercased()
        if lower == "profile" || lower == "offer" {
            return nil
        }
        return line
    }

    private static func shouldDropEntirely(_ lower: String) -> Bool {
        if forbiddenSubstrings.contains(where: { lower.contains($0) }) {
            return true
        }
        if lower.contains("public_profile_") || lower.contains("selected_offer_") {
            return true
        }
        if lower.hasPrefix("match ") && lower.contains("reason") {
            return true
        }
        if lower.contains("why it matched") || lower.contains("why this matched") {
            return true
        }
        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
