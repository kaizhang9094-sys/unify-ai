import Foundation

/// Doc-kind boundaries for retrieval **embedding** text (not BM25 `searchableText`).
enum ExchangeRetrievalDocumentEmbeddingPolicy {
    static func retrievalEmbeddingText(for document: ExchangeRetrievalDocument) -> String {
        switch document.docKind {
        case .offerObject:
            return offerObjectEmbeddingText(from: document)
        case .offerDetail, .offer:
            return offerDetailEmbeddingText(from: document)
        case .offerPackage:
            return offerPackageEmbeddingText(from: document)
        case .offerFAQ:
            return offerFAQEmbeddingText(from: document)
        case .profileIntro:
            return profileIntroEmbeddingText(from: document)
        case .profileAbout:
            return profileAboutEmbeddingText(from: document)
        case .profileCapability:
            return profileCapabilityEmbeddingText(from: document)
        case .profileSeeking:
            return profileSeekingEmbeddingText(from: document)
        case .profileAffinity:
            return profileAffinityEmbeddingText(from: document)
        case nil:
            return legacyEmbeddingText(from: document)
        }
    }

    static func offerObjectEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            document.canonicalEnglishRetrievalText
        ) {
            return joinedEmbeddingParts([
                english,
                document.semanticText,
                document.category,
                document.tags.joined(separator: " "),
                document.capabilityTerms.joined(separator: " ")
            ])
        }

        return ExchangeRetrievalEnglishProjection.normalizeWhitespace(
            [
                document.title,
                document.category,
                document.tags.joined(separator: " "),
                document.capabilityTerms.joined(separator: " ")
            ]
            .compactMap { trimmedNonEmpty($0) }
            .joined(separator: ". ")
        )
    }

    private static func offerDetailEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            document.canonicalEnglishRetrievalText
        ) {
            return joinedEmbeddingParts([
                english,
                document.semanticText,
                document.category,
                document.tags.joined(separator: " ")
            ])
        }

        return joinedEmbeddingParts([
            document.title,
            document.summary,
            document.category,
            document.tags.joined(separator: " "),
            document.semanticText,
            document.primaryText
        ])
    }

    private static func offerPackageEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            document.canonicalEnglishRetrievalText
        ) {
            return joinedEmbeddingParts([
                english,
                document.title,
                document.summary,
                document.primaryText,
                document.semanticText
            ])
        }

        return joinedEmbeddingParts([
            document.title,
            document.summary,
            document.primaryText,
            document.semanticText
        ])
    }

    private static func offerFAQEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            document.canonicalEnglishRetrievalText
        ) {
            return joinedEmbeddingParts([
                english,
                document.title,
                document.summary,
                document.primaryText,
                document.semanticText
            ])
        }

        return joinedEmbeddingParts([
            document.title,
            document.summary,
            document.primaryText,
            document.semanticText
        ])
    }

    private static func profileIntroEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            document.canonicalEnglishRetrievalText
        ) {
            return joinedEmbeddingParts([
                english,
                document.primaryText,
                document.title,
                document.summary
            ])
        }

        return joinedEmbeddingParts([
            document.primaryText,
            document.title,
            document.summary
        ])
    }

    private static func profileAboutEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            document.canonicalEnglishRetrievalText
        ) {
            return joinedEmbeddingParts([
                english,
                document.semanticText,
                document.primaryText,
                document.secondaryText
            ])
        }

        return joinedEmbeddingParts([
            document.primaryText,
            document.secondaryText,
            document.semanticText
        ])
    }

    private static func profileCapabilityEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            document.canonicalEnglishRetrievalText
        ) {
            return joinedEmbeddingParts([
                english,
                document.semanticText,
                document.capabilityTerms.joined(separator: " "),
                document.tags.joined(separator: " ")
            ])
        }

        return joinedEmbeddingParts([
            document.primaryText,
            document.secondaryText,
            document.semanticText,
            document.capabilityTerms.joined(separator: " "),
            document.tags.joined(separator: " ")
        ])
    }

    private static func profileSeekingEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            document.canonicalEnglishRetrievalText
        ) {
            return joinedEmbeddingParts([
                english,
                document.primaryText,
                document.secondaryText,
                document.semanticText,
                document.capabilityTerms.joined(separator: " ")
            ])
        }

        return joinedEmbeddingParts([
            document.primaryText,
            document.secondaryText,
            document.semanticText,
            document.capabilityTerms.joined(separator: " ")
        ])
    }

    private static func profileAffinityEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(
            document.canonicalEnglishRetrievalText
        ) {
            return joinedEmbeddingParts([
                english,
                document.primaryText,
                document.secondaryText,
                document.affinityTerms.joined(separator: " "),
                document.tags.joined(separator: " ")
            ])
        }

        return joinedEmbeddingParts([
            document.primaryText,
            document.secondaryText,
            document.affinityTerms.joined(separator: " "),
            document.tags.joined(separator: " ")
        ])
    }

    private static func legacyEmbeddingText(from document: ExchangeRetrievalDocument) -> String {
        switch document.surfaceType {
        case .offer:
            return offerDetailEmbeddingText(from: document)
        case .publicProfileCapability:
            return profileCapabilityEmbeddingText(from: document)
        case .publicProfileSeeking:
            return profileSeekingEmbeddingText(from: document)
        case .publicProfileAffinity:
            return profileAffinityEmbeddingText(from: document)
        case .publicProfile, .unknown:
            return joinedEmbeddingParts([
                document.primaryText,
                document.semanticText,
                document.title,
                document.summary
            ])
        }
    }

    private static func joinedEmbeddingParts(_ values: [String?]) -> String {
        ExchangeRetrievalEnglishProjection.normalizeWhitespace(
            values.compactMap { trimmedNonEmpty($0) }.joined(separator: ". ")
        )
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
