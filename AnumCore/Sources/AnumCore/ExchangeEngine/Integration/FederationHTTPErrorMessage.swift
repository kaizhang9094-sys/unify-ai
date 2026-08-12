import Foundation

/// JSON body shape for federation non-2xx responses (tolerant of unknown keys).
public struct FederationJSONErrorEnvelope: Decodable, Sendable {
    public let ok: Bool?
    public let error: String?
    public let code: String?
    public let detail: String?
    public let retryAfterSeconds: Int?

    public init(
        ok: Bool? = nil,
        error: String? = nil,
        code: String? = nil,
        detail: String? = nil,
        retryAfterSeconds: Int? = nil
    ) {
        self.ok = ok
        self.error = error
        self.code = code
        self.detail = detail
        self.retryAfterSeconds = retryAfterSeconds
    }
}

public enum FederationHTTPErrorMessage: Sendable {
    /// Default backoff when a 429 response omits `retryAfterSeconds` and `Retry-After`.
    public static let defaultRateLimitFallbackSeconds = 60

    /// Returns trimmed `error` from JSON when present and non-empty; otherwise `fallback`.
    public static func userFacingReason(data: Data, fallback: String) -> String {
        guard !data.isEmpty else { return fallback }
        guard
            let envelope = try? JSONDecoder().decode(FederationJSONErrorEnvelope.self, from: data)
        else {
            return fallback
        }

        if let detail = envelope.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            return detail
        }
        if let trimmed = envelope.error?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            if trimmed == "QUOTA_EXCEEDED" || trimmed == "RATE_LIMIT_EXCEEDED" {
                return fallback
            }
            return trimmed
        }
        return fallback
    }

    public static func isQuotaOrRateLimitResponse(data: Data, statusCode: Int) -> Bool {
        guard statusCode == 429 else { return false }
        guard
            let envelope = try? JSONDecoder().decode(FederationJSONErrorEnvelope.self, from: data)
        else {
            return true
        }
        let errorToken = envelope.error?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let codeToken = envelope.code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if errorToken == "QUOTA_EXCEEDED" || codeToken == "QUOTA_EXCEEDED" {
            return true
        }
        if errorToken == "RATE_LIMIT_EXCEEDED" || codeToken == "RATE_LIMIT_EXCEEDED" {
            return true
        }
        return true
    }

    public static func retryAfterSeconds(data: Data, http: HTTPURLResponse) -> Int? {
        if
            let envelope = try? JSONDecoder().decode(FederationJSONErrorEnvelope.self, from: data),
            let bodyRetry = envelope.retryAfterSeconds,
            bodyRetry > 0
        {
            return bodyRetry
        }

        if let header = http.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !header.isEmpty,
           let seconds = Int(header),
           seconds > 0
        {
            return seconds
        }

        return nil
    }

    public static func resolvedRateLimitRetryAfterSeconds(data: Data, http: HTTPURLResponse) -> Int {
        retryAfterSeconds(data: data, http: http) ?? defaultRateLimitFallbackSeconds
    }
}
