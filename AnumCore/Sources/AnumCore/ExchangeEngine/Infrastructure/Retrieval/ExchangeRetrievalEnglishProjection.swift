import Foundation

/// English-only retrieval projection when canonical English text is present.
enum ExchangeRetrievalEnglishProjection {
    static func trimmedCanonicalEnglish(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func normalizeWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Drops tokens that still carry non-English script when an English carrier exists.
    static func englishOnlyTokens(from values: [String]) -> [String] {
        values.filter { !containsSignificantNonEnglish($0) }
    }

    static func containsSignificantNonEnglish(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF, 0x31F0...0x31FF,
                 0xAC00...0xD7AF, 0x1100...0x11FF, 0x0600...0x06FF, 0x0590...0x05FF,
                 0x0400...0x04FF, 0x0370...0x03FF, 0x0900...0x097F, 0x0E00...0x0E7F:
                return true
            default:
                continue
            }
        }
        return false
    }
}

extension ExchangeRetrievalDocument {
    var usesEnglishOnlyRetrievalProjection: Bool {
        ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(canonicalEnglishRetrievalText) != nil
    }

    /// Text passed to the embedder. Doc-kind boundaries enforced by `ExchangeRetrievalDocumentEmbeddingPolicy`.
    var retrievalEmbeddingText: String {
        ExchangeRetrievalDocumentEmbeddingPolicy.retrievalEmbeddingText(for: self)
    }
}

extension ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
    var usesEnglishOnlyRetrievalProjection: Bool {
        ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(canonicalEnglishSearchText) != nil
    }

    func englishFilteredRecallTokens() -> [String] {
        guard usesEnglishOnlyRetrievalProjection else { return broadRecallTokens }
        return ExchangeRetrievalEnglishProjection.englishOnlyTokens(from: broadRecallTokens)
    }

    func englishFilteredSemanticConcepts() -> [String] {
        guard usesEnglishOnlyRetrievalProjection else { return semanticConcepts }
        return ExchangeRetrievalEnglishProjection.englishOnlyTokens(from: semanticConcepts)
    }
}
