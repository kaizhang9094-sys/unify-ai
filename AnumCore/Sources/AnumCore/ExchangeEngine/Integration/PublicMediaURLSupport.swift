import Foundation

/// Result of a remote public media delete request (non-throwing for expected server outcomes).
public enum ExchangePublicMediaDeleteOutcome: Sendable, Equatable {
    case deleted
    case notFound
    case stillReferenced
    case ownershipMismatch
    case invalidStorageKey
    case failed(reason: String)
}

/// Helpers for federation `/media/upload/<storageKey>` URLs.
public enum PublicMediaURLSupport: Sendable {
    private static let uploadPathMarker = "/media/upload/"

    /// Server-generated storage key pattern (basename only).
    private static let storageKeyPattern =
        #"^[a-f0-9]{32}_[a-zA-Z0-9._-]+\.(?:jpe?g|png|heic|heif|webp)$"#

    /// Extracts a storage key from an absolute or relative public media URL.
    /// Returns nil for non-media URLs, traversal, or invalid key shapes.
    public static func storageKeyFromPublicMediaURL(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let path: String
        if let url = URL(string: trimmed) {
            let extracted = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !extracted.isEmpty else { return nil }
            path = extracted
        } else if trimmed.hasPrefix("/") {
            path = trimmed
        } else if trimmed.contains(uploadPathMarker) {
            guard let range = trimmed.range(of: uploadPathMarker) else { return nil }
            path = String(trimmed[range.lowerBound...])
        } else {
            return nil
        }

        guard path.contains(uploadPathMarker) else { return nil }

        let suffix = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true).first
            .map(String.init) ?? path
        guard let markerRange = suffix.range(of: uploadPathMarker) else { return nil }

        let afterMarker = String(suffix[markerRange.upperBound...])
        let basename = (afterMarker as NSString).lastPathComponent
        guard !basename.isEmpty else { return nil }
        guard basename == afterMarker, !basename.contains("/"), !basename.contains("..") else { return nil }
        guard basename.range(of: storageKeyPattern, options: .regularExpression) != nil else { return nil }
        return basename
    }

    public static func storageKeys(
        profileImageURL: String?,
        offerImageURL: String?,
        offerGalleryImageURLs: [String]
    ) -> Set<String> {
        var keys = Set<String>()
        if let key = storageKeyFromPublicMediaURL(profileImageURL) { keys.insert(key) }
        if let key = storageKeyFromPublicMediaURL(offerImageURL) { keys.insert(key) }
        for url in offerGalleryImageURLs {
            if let key = storageKeyFromPublicMediaURL(url) { keys.insert(key) }
        }
        return keys
    }

    public static func storageKeys(
        profile: ExchangePublicNodeProfile,
        offer: ExchangeOffer?
    ) -> Set<String> {
        var keys = storageKeys(
            profileImageURL: profile.primaryImageURL,
            offerImageURL: nil,
            offerGalleryImageURLs: []
        )
        if let offer {
            keys.formUnion(storageKeys(in: offer))
        }
        return keys
    }

    public static func storageKeys(in offer: ExchangeOffer) -> Set<String> {
        storageKeys(
            profileImageURL: nil,
            offerImageURL: offer.primaryImageURL,
            offerGalleryImageURLs: offer.galleryImageURLs
        )
    }

    public static func storageKeys(in workspace: ExchangeModels.SellerWorkspaceSummary?) -> Set<String> {
        guard let workspace else { return [] }
        var keys = Set<String>()
        if let profile = workspace.publicProfile?.profile {
            keys.formUnion(storageKeys(profile: profile, offer: nil))
        }
        for offerView in workspace.offers {
            keys.formUnion(storageKeys(in: offerView.offer))
        }
        return keys
    }

    /// Maps an HTTP status + JSON body to a delete outcome (for tests and HTTP client).
    public static func deleteOutcome(
        statusCode: Int,
        responseData: Data
    ) -> ExchangePublicMediaDeleteOutcome {
        switch statusCode {
        case 403:
            if responseIndicatesStillReferenced(responseData) {
                return .stillReferenced
            }
            return .ownershipMismatch
        case 409:
            return .stillReferenced
        case 200...299:
            return deleteOutcomeFromSuccessBody(responseData)
        default:
            let fallback = "HTTP \(statusCode)"
            let message = FederationHTTPErrorMessage.userFacingReason(data: responseData, fallback: fallback)
            return .failed(reason: message)
        }
    }

    private static func deleteOutcomeFromSuccessBody(_ data: Data) -> ExchangePublicMediaDeleteOutcome {
        struct Body: Decodable {
            let ok: Bool?
            let deleted: Bool?
            let reason: String?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            return .failed(reason: "Media delete returned an unreadable response.")
        }
        if body.deleted == true {
            return .deleted
        }
        let reason = body.reason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if reason == "not_found" || reason == "already_deleted" {
            return .notFound
        }
        if body.ok == true {
            return .notFound
        }
        return .failed(reason: "Media delete was not confirmed by the server.")
    }

    private static func responseIndicatesStillReferenced(_ data: Data) -> Bool {
        struct Body: Decodable {
            let error: String?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return false }
        let code = body.error?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return code == "MEDIA_STILL_REFERENCED"
    }
}
