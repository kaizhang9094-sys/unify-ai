import Foundation

public enum ForYouStandingInterestResolutionSource: String, Sendable {
    case cache
    case llm
    case heuristic
}

/// Coordinates cache, validation, and background regeneration for `ForYouStandingInterest`.
public actor ForYouStandingInterestService {
    private let store: ForYouStandingInterestStore
    private let generator: any ForYouStandingInterestGenerating
    /// Monotonic per node — stale generation completions must not clear a newer in-flight task.
    private var generationEpochByNodeID: [String: UInt64] = [:]
    private var generationTasksByNodeID: [String: Task<Void, Never>] = [:]

    public init(
        store: ForYouStandingInterestStore = ForYouStandingInterestStore(),
        generator: any ForYouStandingInterestGenerating = ForYouStandingInterestHeuristicGenerator()
    ) {
        self.store = store
        self.generator = generator
    }

    /// Returns a cache entry only when fingerprint + TTL match the given profile.
    public func standingInterestForQuery(
        nodeID: String,
        profile: ExchangePublicNodeProfile
    ) -> ForYouStandingInterest? {
        let nid = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nid.isEmpty else { return nil }
        guard let cached = store.load(nodeID: nid),
              store.isValid(cached, for: profile) else { return nil }
        return cached
    }

    /// Resolves standing interest for a directory pass: valid cache, else awaits generator (LLM + heuristic fallback), persists when valid.
    public func resolveForDirectoryQuery(
        nodeID: String,
        profile: ExchangePublicNodeProfile,
        forceRefresh: Bool
    ) async -> (interest: ForYouStandingInterest, source: ForYouStandingInterestResolutionSource, cacheHit: Bool) {
        let nid = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = ForYouStandingInterestProfileFingerprint.make(for: profile)

        if !forceRefresh,
           let cached = standingInterestForQuery(nodeID: nid, profile: profile) {
            Self.logResolution(
                store: store,
                nodeID: nid,
                interest: cached,
                source: .cache,
                cacheHit: true,
                profile: profile
            )
            return (cached, .cache, true)
        }

        if forceRefresh {
            invalidate(nodeID: nid)
        }

        do {
            let raw = try await self.generator.generate(from: profile)
            guard let sanitized = ForYouStandingInterestSanitizer.sanitizedForPersist(
                raw,
                profile: profile,
                expectedFingerprint: expected
            ) else {
                return persistHeuristicFallback(
                    nodeID: nid,
                    profile: profile,
                    expectedFingerprint: expected
                )
            }
            store.save(sanitized, nodeID: nid)
            let source: ForYouStandingInterestResolutionSource =
                sanitized.debugSummary == "heuristic profile fallback" ? .heuristic : .llm
            Self.logResolution(
                store: store,
                nodeID: nid,
                interest: sanitized,
                source: source,
                cacheHit: false,
                profile: profile
            )
            return (sanitized, source, false)
        } catch {
            return persistHeuristicFallback(
                nodeID: nid,
                profile: profile,
                expectedFingerprint: expected
            )
        }
    }

    private func persistHeuristicFallback(
        nodeID: String,
        profile: ExchangePublicNodeProfile,
        expectedFingerprint: String
    ) -> (interest: ForYouStandingInterest, source: ForYouStandingInterestResolutionSource, cacheHit: Bool) {
        let built = ForYouStandingInterestHeuristicBuilder.build(from: profile)
        let queryAdjusted = ForYouStandingInterestSanitizer.directorySearchQueryText(from: built, profile: profile)
        let patched = ForYouStandingInterest(
            queryText: queryAdjusted,
            searchTags: built.searchTags,
            lookingForTags: built.lookingForTags,
            interestTags: built.interestTags,
            roleTags: built.roleTags,
            regionTags: built.regionTags,
            excludedTags: built.excludedTags,
            confidence: built.confidence,
            generatedAt: built.generatedAt,
            sourceProfileFingerprint: built.sourceProfileFingerprint,
            debugSummary: built.debugSummary
        )
        guard let sanitized = ForYouStandingInterestSanitizer.sanitizedForPersist(
            patched,
            profile: profile,
            expectedFingerprint: expectedFingerprint
        ) else {
            Self.logResolution(
                store: self.store,
                nodeID: nodeID,
                interest: patched,
                source: .heuristic,
                cacheHit: false,
                profile: profile
            )
            return (patched, .heuristic, false)
        }
        self.store.save(sanitized, nodeID: nodeID)
        Self.logResolution(
            store: self.store,
            nodeID: nodeID,
            interest: sanitized,
            source: .heuristic,
            cacheHit: false,
            profile: profile
        )
        return (sanitized, .heuristic, false)
    }

    #if DEBUG
    private static func logResolution(
        store: ForYouStandingInterestStore,
        nodeID: String,
        interest: ForYouStandingInterest,
        source: ForYouStandingInterestResolutionSource,
        cacheHit: Bool,
        profile: ExchangePublicNodeProfile
    ) {
        let preview = [profile.headline, profile.summary]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        let previewShort = String(preview.prefix(160))
        let cleanedTerms = interest.directoryTags.joined(separator: ",")
        let lookingFor = interest.lookingForTags.joined(separator: ",")
        let interests = interest.interestTags.joined(separator: ",")
        let roles = interest.roleTags.joined(separator: ",")
        let regions = interest.regionTags.joined(separator: ",")
        let key = store.debugStorageKey(forNodeID: nodeID)
        print(
            "[ForYouStandingInterest] resolved source=\(source.rawValue) cacheHit=\(cacheHit) " +
            "query=\(interest.queryText) tags=\(interest.directoryTags) lookingFor=[\(lookingFor)] interests=[\(interests)] roles=[\(roles)] regions=[\(regions)]"
        )
        print(
            "[ForYouStandingInterest] rawProfilePreview=\(previewShort) cleanedTerms=\(cleanedTerms)"
        )
        print(
            "[ForYouStandingInterest] cache key=\(key)"
        )
    }
    #else
    private static func logResolution(
        store: ForYouStandingInterestStore,
        nodeID: String,
        interest: ForYouStandingInterest,
        source: ForYouStandingInterestResolutionSource,
        cacheHit: Bool,
        profile: ExchangePublicNodeProfile
    ) {}
    #endif

    public func invalidate(nodeID: String) {
        let nid = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nid.isEmpty else { return }
        bumpEpoch(nid)
        generationTasksByNodeID[nid]?.cancel()
        generationTasksByNodeID[nid] = nil
        store.clear(nodeID: nid)
    }

    /// Schedules background generation when cache is missing/stale, or when `force` is true.
    /// Does not block on generation completion. Dedupes concurrent work per node ID.
    public func ensureGeneratedInBackground(
        nodeID: String,
        profile: ExchangePublicNodeProfile,
        force: Bool
    ) {
        let nid = nodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nid.isEmpty else { return }

        if !force,
           let cached = store.load(nodeID: nid),
           store.isValid(cached, for: profile) {
            return
        }

        if !force, generationTasksByNodeID[nid] != nil {
            return
        }

        generationTasksByNodeID[nid]?.cancel()
        bumpEpoch(nid)
        let epoch = generationEpochByNodeID[nid] ?? 0

        let generator = self.generator
        let task = Task {
            await self.runGenerationWork(
                generator: generator,
                nodeID: nid,
                profile: profile,
                epoch: epoch
            )
        }
        generationTasksByNodeID[nid] = task
    }

    private func bumpEpoch(_ nodeID: String) {
        generationEpochByNodeID[nodeID, default: 0] &+= 1
    }

    private func completeGeneration(nodeID: String, epoch: UInt64) {
        guard generationEpochByNodeID[nodeID] == epoch else { return }
        generationTasksByNodeID[nodeID] = nil
    }

    private func runGenerationWork(
        generator: any ForYouStandingInterestGenerating,
        nodeID: String,
        profile: ExchangePublicNodeProfile,
        epoch: UInt64
    ) async {
        await Self.runGeneration(
            store: ForYouStandingInterestStore(),
            generator: generator,
            nodeID: nodeID,
            profile: profile
        )
        completeGeneration(nodeID: nodeID, epoch: epoch)
    }

    nonisolated private static func runGeneration(
        store: ForYouStandingInterestStore,
        generator: any ForYouStandingInterestGenerating,
        nodeID: String,
        profile: ExchangePublicNodeProfile
    ) async {
        let expected = ForYouStandingInterestProfileFingerprint.make(for: profile)
        do {
            let raw = try await generator.generate(from: profile)
            guard let sanitized = ForYouStandingInterestSanitizer.sanitizedForPersist(
                raw,
                profile: profile,
                expectedFingerprint: expected
            ) else {
                return
            }
            store.save(sanitized, nodeID: nodeID)
        } catch {
            return
        }
    }
}
