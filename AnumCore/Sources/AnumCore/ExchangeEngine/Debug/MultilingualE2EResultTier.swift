import Foundation

#if DEBUG

public enum MultilingualE2EResultTier: String, Sendable, Hashable, Codable, CaseIterable {
    /// Passed local-only modes: injected baseline or live enricher core path.
    case passLocal
    /// Passed full facade publish with federation search probe verified (no roofer overlay).
    case passTrueFederation
    /// Passed full facade publish; production publish/doc build OK but federation probe used overlay fallback.
    case passOverlayFallback
    case fail
}

public enum MultilingualE2EProductionParityConfidence: String, Sendable, Hashable, Codable, CaseIterable {
    case high
    case medium
    case low
    case failed
}

public enum MultilingualE2EResultTierResolver {
    public struct Outcome: Sendable, Hashable, Codable {
        public var resultTier: MultilingualE2EResultTier
        public var federationVerified: Bool
        public var overlayFallbackUsed: Bool
        public var productionParityConfidence: MultilingualE2EProductionParityConfidence

        public init(
            resultTier: MultilingualE2EResultTier,
            federationVerified: Bool,
            overlayFallbackUsed: Bool,
            productionParityConfidence: MultilingualE2EProductionParityConfidence
        ) {
            self.resultTier = resultTier
            self.federationVerified = federationVerified
            self.overlayFallbackUsed = overlayFallbackUsed
            self.productionParityConfidence = productionParityConfidence
        }
    }

    public static func resolve(
        runMode: MultilingualRetrievalE2EMode,
        passed: Bool,
        publication: MultilingualRetrievalE2EFullFacadePublicationSnapshot?
    ) -> Outcome {
        guard passed else {
            return Outcome(
                resultTier: .fail,
                federationVerified: false,
                overlayFallbackUsed: publication?.usesOverlayFallbackForRoofer ?? false,
                productionParityConfidence: .failed
            )
        }

        switch runMode {
        case .fullFacadePublishPath:
            let federationOK = publication?.federationRoundTripSucceeded == true
            let overlayFallback = publication?.usesOverlayFallbackForRoofer == true
            if federationOK && !overlayFallback {
                return Outcome(
                    resultTier: .passTrueFederation,
                    federationVerified: true,
                    overlayFallbackUsed: false,
                    productionParityConfidence: .high
                )
            }
            return Outcome(
                resultTier: .passOverlayFallback,
                federationVerified: false,
                overlayFallbackUsed: overlayFallback,
                productionParityConfidence: .medium
            )
        case .livePublishEnricher:
            return Outcome(
                resultTier: .passLocal,
                federationVerified: false,
                overlayFallbackUsed: false,
                productionParityConfidence: .medium
            )
        case .injectedCarrierFixture:
            return Outcome(
                resultTier: .passLocal,
                federationVerified: false,
                overlayFallbackUsed: false,
                productionParityConfidence: .low
            )
        }
    }

    public static func consoleSummaryLabel(
        tier: MultilingualE2EResultTier,
        runMode: MultilingualRetrievalE2EMode
    ) -> String {
        switch (runMode, tier) {
        case (.fullFacadePublishPath, .passTrueFederation):
            return "PASS — true federation round-trip verified"
        case (.fullFacadePublishPath, .passOverlayFallback):
            return "PASS WITH OVERLAY FALLBACK — production publish/doc build passed, federation search probe failed"
        case (_, .fail):
            return "FAIL"
        case (.injectedCarrierFixture, .passLocal):
            return "PASS — local diagnostic baseline"
        case (.livePublishEnricher, .passLocal):
            return "PASS — live enricher core path"
        default:
            return tier == .fail ? "FAIL" : "PASS"
        }
    }

    public static func outcome(for run: MultilingualE2ERunSnapshot) -> Outcome {
        let runMode = MultilingualRetrievalE2EMode(rawValue: run.runMode) ?? .injectedCarrierFixture
        return resolve(
            runMode: runMode,
            passed: run.passed,
            publication: run.providerIndexing.fullFacadePublication
        )
    }
}

#endif
