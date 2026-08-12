import Foundation

/// Lightweight context threaded through submit/discovery for live hero progress updates.
public struct DiscoveryHeroProgressContext: Sendable, Hashable {
    public let generation: UInt64
    public let originalText: String

    public init(generation: UInt64, originalText: String) {
        self.generation = generation
        self.originalText = originalText
    }
}

/// Transient stage update for Discovery hero live progress.
public struct DiscoveryHeroProgressUpdate: Sendable, Hashable {
    public enum Stage: String, Sendable, Hashable, CaseIterable {
        case understandingRequest
        case searchingPublicNodes
        case rankingResults
        case finalizing
    }

    public let generation: UInt64
    public let stage: Stage
    public let activeThreadID: ExchangeThread.ID?
    public let originalText: String?
    public let updatedAt: Date

    public init(
        generation: UInt64,
        stage: Stage,
        activeThreadID: ExchangeThread.ID? = nil,
        originalText: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.generation = generation
        self.stage = stage
        self.activeThreadID = activeThreadID
        self.originalText = originalText
        self.updatedAt = updatedAt
    }
}

/// Optional UI-agnostic reporter for Discovery hero live progress. Implementations must not block callers.
public protocol DiscoveryHeroProgressReporting: Sendable {
    func reportDiscoveryHeroProgress(_ update: DiscoveryHeroProgressUpdate)
}

enum DiscoveryHeroProgressNotifier {
    static func report(
        _ reporter: (any DiscoveryHeroProgressReporting)?,
        context: DiscoveryHeroProgressContext?,
        stage: DiscoveryHeroProgressUpdate.Stage,
        threadID: ExchangeThread.ID? = nil
    ) {
        guard let context else { return }
        guard let reporter else { return }

        let update = DiscoveryHeroProgressUpdate(
            generation: context.generation,
            stage: stage,
            activeThreadID: threadID,
            originalText: context.originalText
        )

        #if DEBUG
        let threadTag = threadID.map { $0.uuidString } ?? "nil"
        print(
            "[DiscoveryHeroProgress] update generation=\(context.generation) " +
            "stage=\(stage.rawValue) thread=\(threadTag)"
        )
        #endif

        reporter.reportDiscoveryHeroProgress(update)
    }
}
