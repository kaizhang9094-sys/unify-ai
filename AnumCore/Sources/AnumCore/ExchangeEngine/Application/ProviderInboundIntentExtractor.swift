import Foundation

/// Maps compact LLM JSON into `ProviderInboundIntentExtraction` (no keyword overrides).
public enum ProviderInboundIntentExtractor: Sendable {
    struct CompactDTO: Decodable {
        let normalizedRequesterQuestion: String?
        let askSummary: String?
        let inquiryKind: String?
        let requestedFactSurfaces: [String]?
        let requestedClaims: [String]?
        let commercialIntent: Bool?
        let asksForCommitment: Bool?
        let asksForSensitiveInfo: Bool?
        let needsProviderInputLikely: Bool?
        let needsCompareLLM: Bool?
        let confidence: Double?
        let rationaleShort: String?
    }

    public static func decode(cleanedJSON: String, rawRequesterAsk: String) throws -> ProviderInboundIntentExtraction {
        let dto = try JSONDecoder().decode(CompactDTO.self, from: Data(cleanedJSON.utf8))
        return mapDecoded(dto: dto, rawRequesterAsk: rawRequesterAsk)
    }

    static func mapDecoded(
        dto: CompactDTO,
        rawRequesterAsk: String
    ) -> ProviderInboundIntentExtraction {
        let raw = rawRequesterAsk.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trim(dto.normalizedRequesterQuestion, fallback: raw, limit: 500)
        let summary = trim(dto.askSummary, fallback: normalized, limit: 220)
        let kind = mapInquiryKind(dto.inquiryKind)
        let surfaces = mapSurfaces(dto.requestedFactSurfaces)
        let claims = mapClaims(dto.requestedClaims)
        let confidence = clampConfidence(dto.confidence ?? 0.5)
        let rationale = trim(dto.rationaleShort, fallback: "provider_inbound_extraction", limit: 160)

        return ProviderInboundIntentExtraction(
            rawRequesterAsk: raw.isEmpty ? rawRequesterAsk : raw,
            normalizedRequesterQuestion: normalized,
            askSummary: summary,
            inquiryKind: kind,
            requestedFactSurfaces: surfaces,
            requestedClaims: claims,
            commercialIntent: dto.commercialIntent ?? false,
            asksForCommitment: dto.asksForCommitment ?? false,
            asksForSensitiveInfo: dto.asksForSensitiveInfo ?? false,
            needsProviderInputLikely: dto.needsProviderInputLikely ?? (kind == .unclear),
            needsCompareLLM: dto.needsCompareLLM ?? true,
            confidence: confidence,
            rationaleShort: rationale
        )
    }

    public static func conservativeDecodeFailed(rawRequesterAsk: String) -> ProviderInboundIntentExtraction {
        let raw = rawRequesterAsk.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderInboundIntentExtraction(
            rawRequesterAsk: raw.isEmpty ? "Inbound message." : raw,
            normalizedRequesterQuestion: raw.isEmpty ? "Inbound message." : raw,
            askSummary: "Inbound inquiry (extraction decode failed).",
            inquiryKind: .unclear,
            requestedFactSurfaces: [],
            requestedClaims: [],
            commercialIntent: false,
            asksForCommitment: false,
            asksForSensitiveInfo: false,
            needsProviderInputLikely: true,
            needsCompareLLM: true,
            confidence: 0,
            rationaleShort: "extraction_decode_failed"
        )
    }

    // MARK: - Enum mapping

    private static func mapInquiryKind(_ raw: String?) -> ProviderInboundInquiryKind {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .unclear
        }
        return ProviderInboundInquiryKind(rawValue: raw) ?? .unclear
    }

    private static func mapSurfaces(_ raw: [String]?) -> Set<ProviderInboundRequestedFactSurface> {
        guard let raw else { return [] }
        var out = Set<ProviderInboundRequestedFactSurface>()
        for item in raw {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if let mapped = ProviderInboundRequestedFactSurface(rawValue: t) {
                out.insert(mapped)
            }
        }
        return out
    }

    private static func mapClaims(_ raw: [String]?) -> Set<ProviderInboundRequestedClaim> {
        guard let raw else { return [] }
        var out = Set<ProviderInboundRequestedClaim>()
        for item in raw {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if let mapped = ProviderInboundRequestedClaim(rawValue: t) {
                out.insert(mapped)
            }
        }
        return out
    }

    private static func trim(_ value: String?, fallback: String, limit: Int) -> String {
        let t = (value?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        if t.count <= limit { return t }
        return String(t.prefix(limit))
    }

    private static func clampConfidence(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
