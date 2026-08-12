import Foundation

#if DEBUG

public enum MultilingualRetrievalE2EMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Deterministic fixture with English retrieval carrier injected on indexed surface.
    case injectedCarrierFixture
    /// Raw Chinese seller text through indexed-surface builder + live enricher + retrieval docs.
    case livePublishEnricher
    /// Raw Chinese seller text through ExchangeFacade save/publish + federation retrieval docs.
    case fullFacadePublishPath

    /// Legacy `/debug/retrieval-smoke/manifest` fixtures are not used by current multilingual modes.
    public var requiresLegacyRetrievalSmokeManifest: Bool {
        switch self {
        case .injectedCarrierFixture, .livePublishEnricher, .fullFacadePublishPath:
            return false
        }
    }
}

#endif
