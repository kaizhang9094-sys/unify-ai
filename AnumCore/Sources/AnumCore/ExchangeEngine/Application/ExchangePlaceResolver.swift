import Foundation

public protocol ExchangePlaceResolving: Sendable {
    func resolvePlace(_ entity: ExchangeQueryEntity) async -> ExchangeResolvedPlace?
}

public struct ExchangeLocalPlaceResolver: ExchangePlaceResolving {
    public init() {}

    public func resolvePlace(_ entity: ExchangeQueryEntity) async -> ExchangeResolvedPlace? {
        resolvePlaceSync(entity)
    }

    public func resolvePlaceSync(_ entity: ExchangeQueryEntity) -> ExchangeResolvedPlace? {
        guard entity.kind == .place else { return nil }

        let key = normalize(entity.normalizedText)
        guard !key.isEmpty else { return nil }
        guard let hit = Self.aliasTable[key] else { return nil }

        return ExchangeResolvedPlace(
            id: hit.canonicalID,
            rawText: entity.rawText,
            normalizedText: key,
            canonicalName: hit.canonicalName,
            canonicalID: hit.canonicalID,
            aliases: hit.aliases,
            parentRegionIDs: hit.parentRegionIDs,
            confidence: max(entity.confidence, 0.82),
            source: .localGazetteer
        )
    }
}

private extension ExchangeLocalPlaceResolver {
    struct AliasHit: Sendable {
        let canonicalName: String
        let canonicalID: String
        let aliases: [String]
        let parentRegionIDs: [String]
    }

    static let aliasTable: [String: AliasHit] = {
        let markham = AliasHit(
            canonicalName: "Markham",
            canonicalID: "place:ca:on:markham",
            aliases: ["markham"],
            parentRegionIDs: ["place:ca:on:gta"]
        )
        let toronto = AliasHit(
            canonicalName: "Toronto",
            canonicalID: "place:ca:on:toronto",
            aliases: ["toronto"],
            parentRegionIDs: ["place:ca:on:gta"]
        )
        let gta = AliasHit(
            canonicalName: "Greater Toronto Area",
            canonicalID: "place:ca:on:gta",
            aliases: ["gta", "greater toronto area"],
            parentRegionIDs: ["place:ca:on"]
        )

        var out: [String: AliasHit] = [:]
        for hit in [markham, toronto, gta] {
            for alias in hit.aliases {
                out[normalize(alias)] = hit
            }
        }
        return out
    }()

    static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    func normalize(_ text: String) -> String {
        Self.normalize(text)
    }
}
