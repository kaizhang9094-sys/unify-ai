import Foundation

public struct ExchangeServiceAreaMatchResult: Sendable, Hashable {
    public enum Tier: String, Sendable, Hashable {
        case exact
        case alias
        case containment
        case fuzzy
        case remoteAccepted
        case none
        case requiresClarification
    }

    public var tier: Tier
    public var scoreDelta: Double
    public var evidence: String
    public var matchedArea: ExchangeDeclaredServiceArea?
    public var isCompatible: Bool
    public var isHardMismatch: Bool

    public init(
        tier: Tier,
        scoreDelta: Double,
        evidence: String,
        matchedArea: ExchangeDeclaredServiceArea? = nil,
        isCompatible: Bool,
        isHardMismatch: Bool
    ) {
        self.tier = tier
        self.scoreDelta = scoreDelta
        self.evidence = evidence
        self.matchedArea = matchedArea
        self.isCompatible = isCompatible
        self.isHardMismatch = isHardMismatch
    }

    public static let neutral = ExchangeServiceAreaMatchResult(
        tier: .none,
        scoreDelta: 0,
        evidence: "no location signal",
        isCompatible: true,
        isHardMismatch: false
    )
}

/// Deterministic declared service-area compatibility (gazetteer-optional).
public enum ExchangeServiceAreaMatcher: Sendable {
    private static let fuzzyThreshold = 0.88

    public static func match(
        requirement: ExchangeLocationRequirement?,
        serviceAreas: [ExchangeDeclaredServiceArea],
        fulfillmentRemoteFriendly: Bool = false
    ) -> ExchangeServiceAreaMatchResult {
        guard let requirement, requirement.kind != .none else {
            return .neutral
        }

        if requirement.needsClarification {
            return ExchangeServiceAreaMatchResult(
                tier: .requiresClarification,
                scoreDelta: 0,
                evidence: "location clarification required",
                isCompatible: true,
                isHardMismatch: false
            )
        }

        let areas = resolvedServiceAreas(serviceAreas)
        if areas.isEmpty {
            if requirement.kind == .remote {
                return fulfillmentRemoteFriendly
                    ? remoteAcceptedResult(evidence: "remote request, fulfillment allows remote")
                    : ExchangeServiceAreaMatchResult(
                        tier: .none,
                        scoreDelta: requirement.strictness == .required ? -0.12 : 0,
                        evidence: "no declared service areas",
                        isCompatible: requirement.strictness != .required,
                        isHardMismatch: requirement.strictness == .required
                    )
            }
            return ExchangeServiceAreaMatchResult(
                tier: .none,
                scoreDelta: requirement.strictness == .required ? -0.20 : 0,
                evidence: "seller has no declared service areas",
                isCompatible: requirement.strictness != .required,
                isHardMismatch: requirement.strictness == .required
            )
        }

        if requirement.kind == .remote {
            if areas.contains(where: \.acceptsRemote) {
                return remoteAcceptedResult(
                    matchedArea: areas.first(where: \.acceptsRemote),
                    evidence: "remote chip on offer"
                )
            }
            if fulfillmentRemoteFriendly {
                return remoteAcceptedResult(evidence: "remote-friendly fulfillment")
            }
            return ExchangeServiceAreaMatchResult(
                tier: .none,
                scoreDelta: -0.08,
                evidence: "remote request without remote service area",
                isCompatible: true,
                isHardMismatch: false
            )
        }

        guard let requestKey = requirement.normalizedName, !requestKey.isEmpty else {
            if requirement.strictness == .required {
                return ExchangeServiceAreaMatchResult(
                    tier: .none,
                    scoreDelta: -0.35,
                    evidence: "required location missing normalized name",
                    isCompatible: false,
                    isHardMismatch: true
                )
            }
            return .neutral
        }

        let requestAliases = Set(
            ([requestKey] + requirement.aliases.map {
                ExchangeLocationNormalization.normalize($0, stripRegionalSuffixes: true)
            }).filter { !$0.isEmpty }
        )

        var best: ExchangeServiceAreaMatchResult?

        for area in areas {
            if let candidate = scoreAreaMatch(
                requestKey: requestKey,
                requestAliases: requestAliases,
                area: area,
                requirement: requirement
            ) {
                if best == nil || candidate.scoreDelta > (best?.scoreDelta ?? -1) {
                    best = candidate
                }
            }
        }

        if let best {
            if requirement.strictness == .required && !best.isCompatible {
                return ExchangeServiceAreaMatchResult(
                    tier: .none,
                    scoreDelta: -0.35,
                    evidence: best.evidence,
                    matchedArea: best.matchedArea,
                    isCompatible: false,
                    isHardMismatch: true
                )
            }
            return best
        }

        let hard = requirement.strictness == .required
        return ExchangeServiceAreaMatchResult(
            tier: .none,
            scoreDelta: hard ? -0.35 : -0.06,
            evidence: "no declared area match for \(requestKey)",
            isCompatible: !hard,
            isHardMismatch: hard
        )
    }

    public static func tierOrdinal(_ tier: ExchangeServiceAreaMatchResult.Tier) -> Int {
        switch tier {
        case .exact: return 6
        case .alias: return 5
        case .remoteAccepted: return 4
        case .containment: return 3
        case .fuzzy: return 2
        case .requiresClarification: return 1
        case .none: return 0
        }
    }

    // MARK: - Private

    private static func resolvedServiceAreas(
        _ serviceAreas: [ExchangeDeclaredServiceArea]
    ) -> [ExchangeDeclaredServiceArea] {
        if !serviceAreas.isEmpty { return serviceAreas }
        return []
    }

    private static func remoteAcceptedResult(
        matchedArea: ExchangeDeclaredServiceArea? = nil,
        evidence: String
    ) -> ExchangeServiceAreaMatchResult {
        ExchangeServiceAreaMatchResult(
            tier: .remoteAccepted,
            scoreDelta: 0.18,
            evidence: evidence,
            matchedArea: matchedArea,
            isCompatible: true,
            isHardMismatch: false
        )
    }

    private static func scoreAreaMatch(
        requestKey: String,
        requestAliases: Set<String>,
        area: ExchangeDeclaredServiceArea,
        requirement: ExchangeLocationRequirement
    ) -> ExchangeServiceAreaMatchResult? {
        let areaKey = area.normalizedName
        guard !areaKey.isEmpty else { return nil }

        let areaAliases = Set(
            ([areaKey, area.displayName] + area.aliases).map {
                ExchangeLocationNormalization.normalize($0, stripRegionalSuffixes: true)
            }.filter { !$0.isEmpty }
        )

        if requestKey == areaKey || requestAliases.contains(areaKey) {
            return ExchangeServiceAreaMatchResult(
                tier: .exact,
                scoreDelta: 0.22,
                evidence: "exact match \(areaKey)",
                matchedArea: area,
                isCompatible: true,
                isHardMismatch: false
            )
        }

        for alias in requestAliases {
            if areaAliases.contains(alias) {
                return ExchangeServiceAreaMatchResult(
                    tier: .alias,
                    scoreDelta: 0.20,
                    evidence: "alias match \(alias)",
                    matchedArea: area,
                    isCompatible: true,
                    isHardMismatch: false
                )
            }
        }

        if let containment = containmentMatch(requestKey: requestKey, areaKey: areaKey) {
            return ExchangeServiceAreaMatchResult(
                tier: .containment,
                scoreDelta: 0.12,
                evidence: containment,
                matchedArea: area,
                isCompatible: true,
                isHardMismatch: false
            )
        }

        if fuzzyRatio(requestKey, areaKey) >= fuzzyThreshold {
            return ExchangeServiceAreaMatchResult(
                tier: .fuzzy,
                scoreDelta: 0.06,
                evidence: "fuzzy match \(areaKey)",
                matchedArea: area,
                isCompatible: true,
                isHardMismatch: false
            )
        }

        _ = requirement
        return nil
    }

    private static func containmentMatch(requestKey: String, areaKey: String) -> String? {
        let requestTokens = ExchangeLocationNormalization.tokens(from: requestKey)
        let areaTokens = ExchangeLocationNormalization.tokens(from: areaKey)
        guard requestTokens.count >= 2 || areaTokens.count >= 2 else { return nil }

        let requestJoined = requestTokens.joined(separator: " ")
        let areaJoined = areaTokens.joined(separator: " ")

        if requestJoined.contains(areaJoined) && areaTokens.count >= 2 {
            return "request contains area phrase"
        }
        if areaJoined.contains(requestJoined) && requestTokens.count >= 2 {
            return "area contains request phrase"
        }
        return nil
    }

    private static func fuzzyRatio(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        let distance = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 0 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        var matrix = Array(repeating: Array(repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
        for i in 0...aChars.count { matrix[i][0] = i }
        for j in 0...bChars.count { matrix[0][j] = j }
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        for i in 1...aChars.count {
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        return matrix[aChars.count][bChars.count]
    }
}
