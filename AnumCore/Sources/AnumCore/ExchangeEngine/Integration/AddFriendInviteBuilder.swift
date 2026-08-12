import Foundation

/// Centralized builders for Add Contact invite share text, node-only copy/QR payloads, and legacy web invite URLs.
public enum AddFriendInviteBuilder: Sendable {
    public static let appStoreDownloadURL = "https://apps.apple.com/app/id6757502298"

    public static func inviteShareText(nodeID: String, displayName: String? = nil) -> String {
        let trimmedNodeID = normalizedNodeID(nodeID)
        let trimmedDisplayName = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank

        if let trimmedDisplayName {
            return """
            \(trimmedDisplayName) invited you to connect on Unify.

            Download Unify:
            \(appStoreDownloadURL)

            Node ID:
            \(trimmedNodeID)
            """
        }

        return """
        Add me on Unify.

        Download Unify:
        \(appStoreDownloadURL)

        My node ID:
        \(trimmedNodeID)
        """
    }

    public static func nodeIDForCopy(_ nodeID: String) -> String {
        normalizedNodeID(nodeID)
    }

    public static func nodeIDQRPayload(_ nodeID: String) -> String {
        normalizedNodeID(nodeID)
    }

    /// Legacy web invite URL for parser backward compatibility and tests only.
    public static func legacyInviteWebURL(nodeID: String) -> String {
        let trimmed = normalizedNodeID(nodeID)
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return "https://unify-now.com/invite/\(encoded)"
    }

    private static func normalizedNodeID(_ nodeID: String) -> String {
        nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
