import Foundation

/// Phase 2B seam: plug in LLM-backed generation later without changing `discoverForYou` call sites.
public protocol ForYouStandingInterestGenerating: Sendable {
    func generate(from profile: ExchangePublicNodeProfile) async throws -> ForYouStandingInterest
}

/// Cheap deterministic generator (Phase 2A heuristic) wrapped for async generation.
public struct ForYouStandingInterestHeuristicGenerator: ForYouStandingInterestGenerating {
    public init() {}

    public func generate(from profile: ExchangePublicNodeProfile) async throws -> ForYouStandingInterest {
        ForYouStandingInterestHeuristicBuilder.build(from: profile)
    }
}
