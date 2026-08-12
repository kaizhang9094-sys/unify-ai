import Foundation

#if DEBUG

/// DEBUG-only capture of the last seller publication coordinator build/publish cycle.
public enum ExchangeSellerPublicationDebugCapture: Sendable {
    public struct BuildSnapshot: Sendable {
        public var nodeID: String
        public var profileID: String
        public var canonicalEnglishCarrierBeforePublish: String?
        public var canonicalEnglishCarrierAfterPublish: String?
        public var enrichedIndexedSurface: ExchangeIndexedProviderSurface
        public var retrievalDocuments: [ExchangeRetrievalDocument]
        public var publishRetrievalDocumentsAttempted: Bool
        public var publishRetrievalDocumentsSucceeded: Bool
        public var publishSellerSurfaceAttempted: Bool
        public var publishSellerSurfaceSucceeded: Bool
        public var publishFailureReason: String?

        public init(
            nodeID: String,
            profileID: String,
            canonicalEnglishCarrierBeforePublish: String?,
            canonicalEnglishCarrierAfterPublish: String?,
            enrichedIndexedSurface: ExchangeIndexedProviderSurface,
            retrievalDocuments: [ExchangeRetrievalDocument],
            publishRetrievalDocumentsAttempted: Bool,
            publishRetrievalDocumentsSucceeded: Bool,
            publishSellerSurfaceAttempted: Bool,
            publishSellerSurfaceSucceeded: Bool,
            publishFailureReason: String?
        ) {
            self.nodeID = nodeID
            self.profileID = profileID
            self.canonicalEnglishCarrierBeforePublish = canonicalEnglishCarrierBeforePublish
            self.canonicalEnglishCarrierAfterPublish = canonicalEnglishCarrierAfterPublish
            self.enrichedIndexedSurface = enrichedIndexedSurface
            self.retrievalDocuments = retrievalDocuments
            self.publishRetrievalDocumentsAttempted = publishRetrievalDocumentsAttempted
            self.publishRetrievalDocumentsSucceeded = publishRetrievalDocumentsSucceeded
            self.publishSellerSurfaceAttempted = publishSellerSurfaceAttempted
            self.publishSellerSurfaceSucceeded = publishSellerSurfaceSucceeded
            self.publishFailureReason = publishFailureReason
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _lastBuild: BuildSnapshot?

    public static var lastBuild: BuildSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return _lastBuild
    }

    public static func clear() {
        lock.lock()
        _lastBuild = nil
        lock.unlock()
    }

    public static func recordBuild(
        nodeID: String,
        profileID: String,
        deterministicSurface: ExchangeIndexedProviderSurface,
        enrichedSurface: ExchangeIndexedProviderSurface,
        retrievalDocuments: [ExchangeRetrievalDocument]
    ) {
        let before = carrierText(from: deterministicSurface)
        let after = carrierText(from: enrichedSurface)
        lock.lock()
        _lastBuild = BuildSnapshot(
            nodeID: nodeID,
            profileID: profileID,
            canonicalEnglishCarrierBeforePublish: before,
            canonicalEnglishCarrierAfterPublish: after,
            enrichedIndexedSurface: enrichedSurface,
            retrievalDocuments: retrievalDocuments,
            publishRetrievalDocumentsAttempted: false,
            publishRetrievalDocumentsSucceeded: false,
            publishSellerSurfaceAttempted: false,
            publishSellerSurfaceSucceeded: false,
            publishFailureReason: nil
        )
        lock.unlock()
    }

    public static func recordPublishAttemptStarted() {
        lock.lock()
        if var build = _lastBuild {
            build.publishSellerSurfaceAttempted = true
            build.publishRetrievalDocumentsAttempted = !build.retrievalDocuments.isEmpty
            _lastBuild = build
        }
        lock.unlock()
    }

    public static func recordPublishSucceeded(retrievalDocumentsPublished: Bool) {
        lock.lock()
        if var build = _lastBuild {
            build.publishSellerSurfaceSucceeded = true
            build.publishRetrievalDocumentsSucceeded = retrievalDocumentsPublished
            build.publishFailureReason = nil
            _lastBuild = build
        }
        lock.unlock()
    }

    public static func recordPublishFailed(reason: String) {
        lock.lock()
        if var build = _lastBuild {
            build.publishFailureReason = reason
            _lastBuild = build
        }
        lock.unlock()
    }

    private static func carrierText(from surface: ExchangeIndexedProviderSurface) -> String? {
        let offer = surface.offers.first
        let trimmed = offer?.canonicalEnglishRetrievalText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

#endif
