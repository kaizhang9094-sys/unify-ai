import Foundation

#if DEBUG
@inline(__always)
private func exDiscoveryEngineLog(_ message: @autoclosure () -> String) {
    print("[ExchangeDiscoveryEngine] \(message())")
}
#else
@inline(__always)
private func exDiscoveryEngineLog(_ message: @autoclosure () -> String) { }
#endif

/// Discovers relevant public coordination surfaces for a request-side thread.
///
/// Clean ownership:
/// - DiscoveryEngine  = retrieval + cheap shortlist shaping + domain-correct gating
/// - FitEngine        = deep scoring on shortlist only
/// - DiscoveryService = orchestration / final result shaping
///
/// Key design rules:
/// - do not treat one node as one semantic blob
/// - do not hard-drop because unrelated surfaces do not match
/// - only hard-drop on real permission / visibility / explicit hard constraints
/// - score offer/capability/affinity surfaces differently by query class
public struct ExchangeDiscoveryEngine: Sendable {
    private let store: (any ExchangeStore)?
    private let directoryClient: (any ExchangeDirectoryClient)?
    private let localNodeIDProvider: (@Sendable () async throws -> String?)?
    private let embeddingProvider: (any MemoryEmbeddingProvider)?

    private let retrievalStore: ExchangeRetrievalStore?
    private let retrievalEngine: ExchangeRetrievalEngine?
    private let retrievalIngestor: ExchangeRetrievalIngestor?
    private let retrievalQueryBuilder: ExchangeRetrievalQueryBuilder
    private let retrievalCandidateProjector: ExchangeRetrievalCandidateProjector
    private let placeResolver: ExchangeLocalPlaceResolver
    private let discoveryHeroProgressReporter: (any DiscoveryHeroProgressReporting)?

    public init(
        store: (any ExchangeStore)? = nil,
        directoryClient: (any ExchangeDirectoryClient)? = nil,
        localNodeIDProvider: (@Sendable () async throws -> String?)? = nil,
        embeddingProvider: (any MemoryEmbeddingProvider)? = nil,
        retrievalStore: ExchangeRetrievalStore? = nil,
        retrievalEngine: ExchangeRetrievalEngine? = nil,
        retrievalIngestor: ExchangeRetrievalIngestor? = nil,
        retrievalQueryBuilder: ExchangeRetrievalQueryBuilder = .init(),
        retrievalCandidateProjector: ExchangeRetrievalCandidateProjector = .init(),
        placeResolver: ExchangeLocalPlaceResolver = .init(),
        discoveryHeroProgressReporter: (any DiscoveryHeroProgressReporting)? = nil
    ) {
        self.store = store
        self.directoryClient = directoryClient
        self.localNodeIDProvider = localNodeIDProvider
        self.embeddingProvider = embeddingProvider
        self.retrievalStore = retrievalStore
        self.retrievalEngine = retrievalEngine
        self.retrievalIngestor = retrievalIngestor
        self.retrievalQueryBuilder = retrievalQueryBuilder
        self.retrievalCandidateProjector = retrievalCandidateProjector
        self.placeResolver = placeResolver
        self.discoveryHeroProgressReporter = discoveryHeroProgressReporter
    }

    public func discover(
        thread: ExchangeThread,
        limit: Int = 12,
        progressContext: DiscoveryHeroProgressContext? = nil
    ) async throws -> DiscoveryResult {
        exDiscoveryEngineLog(
            "discover start " +
            "threadID=\(thread.id.uuidString) " +
            "state=\(thread.state.phaseTitle) " +
            "mode=\(thread.mode.rawValue) " +
            "intent=\(thread.intent.kind.rawValue) " +
            "limit=\(limit)"
        )

        guard limit > 0 else {
            exDiscoveryEngineLog("discover invalid limit=\(limit)")
            throw ExchangeStoreError.invalidLimit
        }

        let searchPlan = SearchPlan.build(for: thread)
        let anchorSource = searchPlan.requesterSpatialAnchor?.source.rawValue ?? "nil"
        let anchorResolved = searchPlan.requesterSpatialAnchor?.hasResolvedSpatial == true
        exDiscoveryEngineLog(
            "searchPlan built " +
            "queryIntentClass=\(searchPlan.queryIntentClass.rawValue) " +
            "surfacePreference=\(searchPlan.surfacePreference.rawValue) " +
            "rawQuery=\(searchPlan.rawQueryText ?? "nil") " +
            "targetDescription=\(searchPlan.targetDescription ?? "nil") " +
            "preferredQuery=\(searchPlan.preferredQueryText ?? "nil") " +
            "fallbackQuery=\(searchPlan.fallbackQueryText ?? "nil") " +
            "requesterSpatialAnchor.source=\(anchorSource) resolved=\(anchorResolved) " +
            "semanticTags=\(searchPlan.semanticTags) " +
            "targetTags=\(searchPlan.targetTags) " +
            "discoveryKeywords=\(searchPlan.discoveryKeywords) " +
            "providerTerms=\(searchPlan.providerTerms) " +
            "capabilityTerms=\(searchPlan.capabilityTerms) " +
            "affinityTerms=\(searchPlan.affinityTerms) " +
            "regionTerms=\(searchPlan.regionTerms) " +
            "trustFloor=\(searchPlan.trustFloor?.rawValue ?? "nil") " +
            "trustPreference=\(searchPlan.trustPreference.rawValue) " +
            "surfaceRequirement=\(searchPlan.surfaceRequirement.rawValue)"
        )

        let localNodeID = try await localNodeIDProvider?()
        exDiscoveryEngineLog("localNodeID=\(localNodeID ?? "nil")")

        let shortlistLimit = max(limit * 2, limit)
        let sourceSummary: String
        let candidates: [DiscoveryCandidate]

        if let directoryClient {
            exDiscoveryEngineLog("discover path=directoryClient")
            
            let queryEmbeddingText = bestQueryEmbeddingText(for: searchPlan)
            let queryEmbedding: [Float]?

            if let embeddingProvider, let queryEmbeddingText {
                let builtEmbedding = ExchangeDirectoryQueryEmbedding.embedQueryText(
                    queryEmbeddingText,
                    provider: embeddingProvider
                )
                queryEmbedding = builtEmbedding?.isEmpty == false ? builtEmbedding : nil

                exDiscoveryEngineLog(
                    "query embedding built " +
                    "textChars=\(queryEmbeddingText.count) " +
                    "dims=\(queryEmbedding?.count ?? 0)"
                )
            } else {
                queryEmbedding = nil

                exDiscoveryEngineLog(
                    "query embedding skipped " +
                    "hasProvider=\(embeddingProvider != nil) " +
                    "hasText=\(queryEmbeddingText != nil)"
                )
            }

            let canonicalDirectory = searchPlan.usesCanonicalDirectoryRecall
            let directoryOpenToTags = canonicalDirectory
                ? searchPlan.affinityTerms
                : searchPlan.affinityTerms + searchPlan.secondaryKeywords
            let directoryOfferTags = canonicalDirectory
                ? searchPlan.providerTerms + searchPlan.capabilityTerms
                : searchPlan.providerTerms + searchPlan.capabilityTerms + searchPlan.primaryKeywords
            let directoryQueryText =
                searchPlan.directoryQueryEmbeddingText ?? searchPlan.preferredQueryText

            let request = ExchangeDirectorySearchRequest(
                threadID: thread.id,
                localNodeID: localNodeID,
                mode: thread.mode,
                intentKind: thread.intent.kind,
                targetDescription: searchPlan.targetDescription,
                queryText: directoryQueryText,
                queryEmbedding: queryEmbedding,
                tags: searchPlan.requestTokens,
                openToTags: directoryOpenToTags,
                offerTags: directoryOfferTags,
                excludedTags: [],
                regionTags: searchPlan.regionTerms,
                trustFloor: searchPlan.trustFloor,
                statuses: [.active],
                limit: max(limit * 4, limit),
                trustPreference: searchPlan.trustPreference,
                scope: .hybridAllowed,
                routeRequirement: directoryRouteRequirement(for: searchPlan),
                accessRequirement: directoryAccessRequirement(for: searchPlan),
                disclosureRequirement: directoryDisclosureRequirement(for: thread),
                retrievalResponseMode: .clientRerank
            )

            DiscoveryHeroProgressNotifier.report(
                discoveryHeroProgressReporter,
                context: progressContext,
                stage: .searchingPublicNodes,
                threadID: thread.id
            )

            let response = try await directoryClient.search(request)
            sourceSummary = response.summary ?? sourceDescription(response.source)

            exDiscoveryEngineLog(
                "directory response " +
                "source=\(response.source.rawValue) " +
                "matches=\(response.matches.count) " +
                "counterparties=\(response.counterparties.count)"
            )

            if let retrievalIngestor, let retrievalEngine {
                exDiscoveryEngineLog("directory branch using hybrid retrieval")

                await retrievalIngestor.ingestDirectoryMatches(
                    response.matches,
                    sourceKind: response.source == .local ? .local : .remote
                )

                let retrievalQuery = retrievalQueryBuilder.build(from: thread)

                let retrievalAnchorSource = retrievalQuery.requesterSpatialAnchor?.source.rawValue ?? "nil"
                let retrievalAnchorResolved = retrievalQuery.requesterSpatialAnchor?.hasResolvedSpatial == true
                exDiscoveryEngineLog(
                    "retrieval query " +
                    "queryText=\(retrievalQuery.queryText ?? "nil") " +
                    "semanticText=\(retrievalQuery.semanticText ?? "nil") " +
                    "queryIntentClass=\(retrievalQuery.queryIntentClass.rawValue) " +
                    "surfacePreference=\(retrievalQuery.surfacePreference.rawValue) " +
                    "requesterSpatialAnchor.source=\(retrievalAnchorSource) resolved=\(retrievalAnchorResolved) " +
                    "softRegionTerms=\(retrievalQuery.softRegionTerms) " +
                    "keywords=\(retrievalQuery.keywords) " +
                    "providerTerms=\(retrievalQuery.providerTerms) " +
                    "capabilityTerms=\(retrievalQuery.capabilityTerms) " +
                    "affinityTerms=\(retrievalQuery.affinityTerms) " +
                    "regionTerms=\(retrievalQuery.regionTerms) " +
                    "explicitHardConstraints=\(retrievalQuery.explicitHardConstraints.map { "\($0.key)=\($0.value)" }) " +
                    "explicitRegionRequired=\(retrievalQuery.explicitRegionRequired) " +
                    "explicitFulfillmentRequired=\(retrievalQuery.explicitFulfillmentRequired) " +
                    "targetKind=\(retrievalQuery.targetKind ?? "nil") " +
                    "fulfillmentMode=\(retrievalQuery.fulfillmentMode ?? "nil") " +
                    "reachabilityRequirement=\(retrievalQuery.reachabilityRequirement.rawValue)"
                )

                DiscoveryHeroProgressNotifier.report(
                    discoveryHeroProgressReporter,
                    context: progressContext,
                    stage: .rankingResults,
                    threadID: thread.id
                )

                let retrievalCandidates = await retrievalEngine.retrieve(
                    query: retrievalQuery,
                    lexicalLimit: max(limit * 4, limit),
                    vectorLimit: max(limit * 4, limit),
                    fusedLimit: shortlistLimit
                )

                exDiscoveryEngineLog(
                    "hybrid retrieval returned count=\(retrievalCandidates.count)"
                )

                let projected = retrievalCandidateProjector.project(
                    retrievalCandidates,
                    knownMatches: response.matches,
                    thread: thread
                )

                let rerankedProjected = rerankProjectedCandidates(
                    projected,
                    thread: thread,
                    plan: searchPlan,
                    localNodeID: localNodeID,
                    shortlistLimit: shortlistLimit
                )

                if !response.matches.isEmpty && retrievalCandidates.isEmpty {
                    exDiscoveryEngineLog(
                        "directory recall diagnostic " +
                        "remoteMatches=\(response.matches.count) " +
                        "retrievalCandidates=0 " +
                        "remoteOnlyResultsNotSurfaced=true"
                    )
                }

                candidates = rerankedProjected

                exDiscoveryEngineLog(
                    "projected+rereanked candidates count=\(candidates.count)"
                )
            } else {
                exDiscoveryEngineLog("directory branch falling back to legacy candidate builder")

                candidates = try await buildCandidates(
                    from: response.matches,
                    thread: thread,
                    plan: searchPlan,
                    localNodeID: localNodeID,
                    shortlistLimit: shortlistLimit
                )
            }
        } else if let store {
            exDiscoveryEngineLog("discover path=store")

            let counterparties = try await discoverFromStore(
                plan: searchPlan,
                store: store,
                limit: limit
            )
            sourceSummary = "Local public-surface directory search"

            exDiscoveryEngineLog("store response counterparties=\(counterparties.count)")

            candidates = try await buildCandidates(
                from: counterparties,
                thread: thread,
                plan: searchPlan,
                localNodeID: localNodeID,
                shortlistLimit: shortlistLimit
            )
        } else {
            exDiscoveryEngineLog("discover failed no source configured")
            throw ExchangeDiscoveryEngineError.noDiscoverySourceConfigured
        }

        exDiscoveryEngineLog("discover candidates ready count=\(candidates.count)")

        let result = classify(
            candidates: candidates,
            thread: thread,
            searchPlan: searchPlan,
            sourceSummary: sourceSummary,
            limit: limit
        )

        switch result {
        case .found(let found):
            exDiscoveryEngineLog(
                "discover result=found candidates=\(found.candidates.count) summary=\(found.summary)"
            )
        case .weak(let weak):
            exDiscoveryEngineLog(
                "discover result=weak candidates=\(weak.candidates.count) summary=\(weak.summary)"
            )
        case .none(let none):
            exDiscoveryEngineLog(
                "discover result=none summary=\(none.summary) recommendation=\(none.recommendation)"
            )
        }

        return result
    }
}

public extension ExchangeDiscoveryEngine {
    enum DiscoveryResult: Sendable, Hashable {
        case found(Found)
        case weak(Weak)
        case none(None)

        public var candidates: [DiscoveryCandidate] {
            switch self {
            case .found(let value): return value.candidates
            case .weak(let value): return value.candidates
            case .none: return []
            }
        }

        public var counterparties: [ExchangeCounterparty] {
            candidates.map(\.counterparty)
        }

        public var visibleSummary: String {
            switch self {
            case .found(let value): return value.summary
            case .weak(let value): return value.summary
            case .none(let value): return value.summary
            }
        }
    }

    struct Found: Sendable, Hashable {
        public var candidates: [DiscoveryCandidate]
        public var summary: String
        public var sourceSummary: String
        public var searchPlan: SearchPlan
    }

    struct Weak: Sendable, Hashable {
        public var candidates: [DiscoveryCandidate]
        public var summary: String
        public var recommendation: String
        public var sourceSummary: String
        public var searchPlan: SearchPlan
    }

    struct None: Sendable, Hashable {
        public var summary: String
        public var recommendation: String
        public var sourceSummary: String
        public var searchPlan: SearchPlan
    }

    struct SearchPlan: Sendable, Hashable {
        public enum SurfaceRequirement: String, Sendable, Hashable {
            case anyVisibleSurface
            case contactableIfPossible
            case introCapable
        }

        public var rawQueryText: String?
        public var targetDescription: String?

        public var semanticTags: [String]
        public var targetTags: [String]
        public var discoveryKeywords: [String]

        public var providerTerms: [String]
        public var capabilityTerms: [String]
        public var affinityTerms: [String]
        public var regionTerms: [String]

        public var mode: ExchangeMode
        public var kind: ExchangeIntent.Kind
        public var queryIntentClass: ExchangeIntent.QueryIntentClass
        public var surfacePreference: ExchangeIntent.SurfacePreference

        public var trustFloor: ExchangeCounterparty.TrustSnapshot.Level?
        public var trustPreference: ExchangeDirectorySearchRequest.TrustPreference
        public var surfaceRequirement: SurfaceRequirement

        public var targetKind: ExchangeIntentFacets.TargetKind?
        public var marketType: ExchangeIntentFacets.MarketType?
        public var fulfillmentMode: ExchangeIntentFacets.FulfillmentMode?
        public var explicitRegionRequired: Bool
        public var explicitProfessionalNeed: Bool
        public var explicitAffinityNeed: Bool

        public var placeName: String?
        public var locationText: String?
        public var locationRequirement: ExchangeLocationRequirement?
        public var requesterSpatialAnchor: ExchangeRequesterSpatialAnchor?
        public var timeText: String?
        public var timePreference: ExchangeIntentFacets.TimePreference?
        public var primaryKeywords: [String]
        public var secondaryKeywords: [String]
        public var hardRequirements: [ExchangeIntentFacets.Requirement]
        public var softPreferences: [ExchangeIntentFacets.Requirement]

        public var preferredQueryText: String? {
            rawQueryText?.exchangeNilIfBlank ?? targetDescription?.exchangeNilIfBlank
        }

        public var fallbackQueryText: String? {
            targetDescription?.exchangeNilIfBlank ?? rawQueryText?.exchangeNilIfBlank
        }

        /// When present, `/directory/search` and local tag filters use canonical broad-recall chips
        /// instead of fused legacy rails (`semanticTags` + full `discoveryKeywords`, etc.).
        public var usesCanonicalDirectoryRecall: Bool

        /// Tags driving directory `tags` plus optional query embedding synthesis when canonical.
        public var canonicalDirectoryRequestTags: [String]

        /// Short directory query / embedding carrier that avoids threading full user paragraphs through HTTP.
        public var directoryQueryEmbeddingText: String?

        /// English-only query carrier when canonical search intent includes translation.
        public var canonicalEnglishSearchText: String?

        /// Structural semantic target for proof-aware discovery and selection.
        public var semanticTarget: ExchangeSemanticTarget?

        public var requestTokens: [String] {
            if usesCanonicalDirectoryRecall {
                return Self.sanitizeRawList(canonicalDirectoryRequestTags, maxCount: 36)
            }
            return Self.sanitizeRawList(
                semanticTags +
                targetTags +
                discoveryKeywords +
                providerTerms +
                capabilityTerms +
                affinityTerms +
                regionTerms +
                primaryKeywords +
                secondaryKeywords,
                maxCount: 36
            )
        }

        static func build(for thread: ExchangeThread) -> SearchPlan {
            let facets = thread.facets
            let interpretation = thread.interpretation

            let rawQueryText = firstNonBlank(
                thread.primarySearchText,
                thread.intent.objective,
                interpretation?.userQuestion,
                interpretation?.userSummary
            )

            let canonicalSearchIntent = facets?.searchIntent

            let targetDescription: String? = {
                if canonicalSearchIntent != nil {
                    return thread.intent.targetDescription?.exchangeNilIfBlank
                }
                return firstNonBlank(
                    thread.intent.targetDescription,
                    facets?.searchableText
                )
            }()

            let stripNearMeLexicals = ExchangeNearMeLexicalSanitizer.shouldStripNearMeLexicals(facets)

            var semanticTags = sanitizeRawList(
                interpretation?.semanticTags ?? [],
                maxCount: 12
            )
            if stripNearMeLexicals {
                semanticTags = sanitizeRawList(
                    ExchangeNearMeLexicalSanitizer.filterInterpretationTags(semanticTags),
                    maxCount: 12
                )
            }

            var targetTags = sanitizeRawList(
                interpretation?.targetTags ?? [],
                maxCount: 10
            )
            if stripNearMeLexicals {
                targetTags = sanitizeRawList(
                    ExchangeNearMeLexicalSanitizer.filterInterpretationTags(targetTags),
                    maxCount: 10
                )
            }

            var discoveryKeywords = sanitizeRawList(
                interpretation?.discoveryKeywords ?? [],
                maxCount: 12
            )
            if stripNearMeLexicals {
                discoveryKeywords = sanitizeRawList(
                    ExchangeNearMeLexicalSanitizer.filterInterpretationTags(discoveryKeywords),
                    maxCount: 12
                )
            }

            let providerTerms = sanitizeRawList(
                facets?.providerTerms ?? [],
                maxCount: 12
            )

            let capabilityTerms = sanitizeRawList(
                facets?.capabilityTerms ?? [],
                maxCount: 12
            )

            let affinityTerms = sanitizeRawList(
                facets?.affinityTerms ?? [],
                maxCount: 12
            )

            var regionTerms = sanitizeRawList(
                canonicalSearchIntent != nil
                    ? Self.directoryRegionTerms(from: canonicalSearchIntent!)
                    : buildRawRegionTerms(for: thread),
                maxCount: 12
            )
            if stripNearMeLexicals {
                regionTerms = sanitizeRawList(
                    ExchangeNearMeLexicalSanitizer.filterTerms(regionTerms),
                    maxCount: 12
                )
            }
            if let locationRequirement = facets?.locationRequirement
                ?? facets.flatMap({ ExchangeLocationRequirementMapping.buildFromFacets($0) }) {
                let locationTerms = locationRequirement.lexicalSearchTerms
                if !locationTerms.isEmpty {
                    regionTerms = sanitizeRawList(regionTerms + locationTerms, maxCount: 12)
                }
            }

            let primaryKeywords = sanitizeRawList(
                facets?.primaryKeywords ?? [],
                maxCount: 12
            )

            let secondaryKeywords = sanitizeRawList(
                facets?.secondaryKeywords ?? [],
                maxCount: 12
            )

            let trustFloor: ExchangeCounterparty.TrustSnapshot.Level? = {
                if thread.posture.openness == .selective || thread.posture.privacy == .guarded {
                    return .moderate
                }
                if facets?.targetKind == .person || facets?.marketType == .relationshipLed {
                    return .moderate
                }
                return nil
            }()

            let trustPreference: ExchangeDirectorySearchRequest.TrustPreference = {
                if thread.posture.openness == .selective || thread.posture.privacy == .guarded {
                    return .preferTrusted
                }
                if facets?.targetKind == .person || facets?.marketType == .relationshipLed {
                    return .preferTrusted
                }
                return .neutral
            }()

            let surfaceRequirement: SurfaceRequirement = {
                switch thread.intent.kind {
                case .message, .followUp, .checkStatus, .introduce, .requestQuote, .negotiate, .arrangeCall, .arrangeMeeting, .invite, .coordinate:
                    if thread.metadata["trusted_path_id"]?.exchangeNilIfBlank != nil {
                        return .introCapable
                    }
                    return .contactableIfPossible

                case .find, .source, .plan, .other:
                    return .anyVisibleSurface
                }
            }()

            let canonicalMode = canonicalSearchIntent != nil
            let canonicalTags = canonicalSearchIntent.map {
                Self.directoryRequestTags(from: $0)
            } ?? []

            let directoryQueryEmbeddingText: String? = {
                guard canonicalMode else { return nil }
                if let english = canonicalSearchIntent?.canonicalEnglishSearchText?.exchangeNilIfBlank {
                    return String(english.prefix(480))
                }
                return Self.clipDirectoryQuery(from: canonicalTags)
            }()

            return SearchPlan(
                rawQueryText: rawQueryText?.exchangeNilIfBlank,
                targetDescription: targetDescription?.exchangeNilIfBlank,
                semanticTags: semanticTags,
                targetTags: targetTags,
                discoveryKeywords: discoveryKeywords,
                providerTerms: providerTerms,
                capabilityTerms: capabilityTerms,
                affinityTerms: affinityTerms,
                regionTerms: regionTerms,
                mode: thread.mode,
                kind: thread.intent.kind,
                queryIntentClass: facets?.queryIntentClass ?? thread.intent.queryIntentClass,
                surfacePreference: facets?.surfacePreference ?? thread.intent.surfacePreference,
                trustFloor: trustFloor,
                trustPreference: trustPreference,
                surfaceRequirement: surfaceRequirement,
                targetKind: facets?.targetKind,
                marketType: facets?.marketType,
                fulfillmentMode: facets?.fulfillmentMode,
                explicitRegionRequired: facets?.explicitRegionRequired ?? false,
                explicitProfessionalNeed: facets?.explicitProfessionalNeed ?? false,
                explicitAffinityNeed: facets?.explicitAffinityNeed ?? false,
                placeName: facets?.placeName,
                locationText: facets?.locationText,
                locationRequirement: facets?.locationRequirement
                    ?? facets.flatMap { ExchangeLocationRequirementMapping.buildFromFacets($0) },
                requesterSpatialAnchor: facets?.requesterSpatialAnchor,
                timeText: facets?.timeText,
                timePreference: facets?.timePreference,
                primaryKeywords: primaryKeywords,
                secondaryKeywords: secondaryKeywords,
                hardRequirements: facets?.hardRequirements ?? [],
                softPreferences: facets?.softPreferences ?? [],
                usesCanonicalDirectoryRecall: canonicalMode,
                canonicalDirectoryRequestTags: canonicalTags,
                directoryQueryEmbeddingText: directoryQueryEmbeddingText,
                canonicalEnglishSearchText: canonicalSearchIntent?.canonicalEnglishSearchText?.exchangeNilIfBlank,
                semanticTarget: facets.map { ExchangeSemanticTarget.from(facets: $0) }
            )
        }

        /// Region tags for directory payloads: atomic place shards + GTA alias expansion only (canonical mode).
        fileprivate static func directoryRegionTerms(
            from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
        ) -> [String] {
            var shards: [String] = []

            func appendAtom(_ raw: String) {
                let atoms = normalizedPlaceShards(from: raw)
                shards.append(contentsOf: atoms)
            }

            for place in searchIntent.places {
                if let id = place.canonicalID?.exchangeNilIfBlank {
                    appendAtom(id)
                }
                appendAtom(place.normalizedText)
                for alias in place.aliases {
                    appendAtom(alias)
                }
            }

            var deduped = sanitizeRawList(shards, maxCount: 12)
            deduped = augmentGreaterTorontoArea(in: deduped)
            return sanitizeRawList(
                deduped.filter { !isClauseJoinedFragment($0) },
                maxCount: 12
            )
        }

        /// Tags for directory recall: trimmed `broadRecallTokens` + deterministic broad-safe synonyms.
        /// Omits literal bedrooms / financing / temporal chips so directory recall stays wide.
        fileprivate static func directoryRequestTags(
            from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
        ) -> [String] {
            if let english = searchIntent.canonicalEnglishSearchText?.exchangeNilIfBlank {
                let englishTokens = sanitizeRawList(
                    english
                        .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && !isClauseJoinedFragment($0) && !isNarrowDirectoryRecallChip($0) },
                    maxCount: 32
                )
                if !englishTokens.isEmpty {
                    return englishTokens
                }
            }

            let seed = sanitizeRawList(
                searchIntent.englishFilteredRecallTokens().filter {
                    $0.exchangeNilIfBlank != nil &&
                    !isClauseJoinedFragment($0) &&
                    !isNarrowDirectoryRecallChip($0)
                },
                maxCount: 32
            )

            let semanticTaskTags = ExchangeCanonicalSearchIntentTaskPhrases
                .directoryTagsMissingFromBroadRecall(from: searchIntent)
                .filter {
                    $0.exchangeNilIfBlank != nil &&
                    !isClauseJoinedFragment($0) &&
                    !isNarrowDirectoryRecallChip($0)
                }

            let boosted = sanitizeRawList(
                seed + semanticTaskTags + directoryBroadRecallExpansions(from: searchIntent),
                maxCount: 48
            )
            return boosted.filter { $0.exchangeNilIfBlank != nil && !isClauseJoinedFragment($0) }
        }

        fileprivate static func clipDirectoryQuery(from tags: [String]) -> String? {
            let joined = sanitizeRawList(tags, maxCount: 48).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !joined.isEmpty else { return nil }
            return String(joined.prefix(480))
        }

        /// Splits commas and strips relational clause tails so region tags stay atomic.
        fileprivate static func normalizedPlaceShards(from raw: String) -> [String] {
            let clipped = stripClauseJoinedTail(raw)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard clipped.exchangeNilIfBlank != nil else { return [] }

            let segments = clipped.split(separator: ",").map {
                stripClauseJoinedTail(String($0))
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let candidates = segments.isEmpty ? [clipped] : segments
            var output: [String] = []

            for item in candidates {
                guard item.exchangeNilIfBlank != nil, !item.isEmpty else { continue }
                guard !isClauseJoinedFragment(item) else { continue }
                output.append(String(item.prefix(96)).lowercased())
            }

            return output
        }

        fileprivate static func stripClauseJoinedTail(_ value: String) -> String {
            let boundaries = [",", ".", ";", " and ", " who ", " with ", " that ", " can ", " offers ", " offer "]
            var out = value
            let lower = value.lowercased()
            for boundary in boundaries where boundary != "," && boundary != "." && boundary != ";" {
                if let range = lower.range(of: boundary) {
                    out = String(value[..<range.lowerBound])
                }
            }
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        fileprivate static func augmentGreaterTorontoArea(in regions: [String]) -> [String] {
            let lowers = regions.map { $0.lowercased() }
            let containsGTA = lowers.contains(where: { $0 == "gta" || $0.hasPrefix("gta ") || $0.contains("greater toronto") })
            guard containsGTA else { return regions }
            return regions + ["greater toronto area"]
        }

        fileprivate static func directoryBroadRecallExpansions(
            from searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
        ) -> [String] {
            var parts: [String] = []

            switch searchIntent.domainCategory {
            case .realEstate:
                parts += ["real estate", "property", "home"]

                let objectText = (searchIntent.objectType ?? "").lowercased()
                if objectText.contains("house") || objectText.contains("home") {
                    parts += ["house", "home"]
                }

                if searchIntent.transactionIntent == .forSale {
                    parts.append("for sale")
                }

                let placeLower = searchIntent.places.map { $0.normalizedText.lowercased() }
                if placeLower.contains(where: {
                    $0 == "gta" || $0.contains("greater toronto")
                }) {
                    parts += ["gta", "greater toronto area"]
                }

            case .homeService:
                let objectText = (searchIntent.objectType ?? "").lowercased()
                if objectText.contains("roofer") || objectText.contains("roof") {
                    parts.append("roofing")
                }

            case .professionalService:
                break

            case .product, .general:
                break
            }

            return parts
        }

        /// Attributes / nuanced financing / urgency tokens must not choke directory lexical recall.
        fileprivate static func isNarrowDirectoryRecallChip(_ value: String) -> Bool {
            let t = value.lowercased()
            let boundaryFragments = [" who ", " with ", ", and ", "; and ", " seller ", " financing ", " mortgage "]
            if boundaryFragments.contains(where: { t.contains($0) }) {
                return true
            }
            if t.range(of: #"\d+\s*(bed|bedroom|br)s?\b"#, options: .regularExpression) != nil { return true }
            if t.range(of: #"\bvtb\b"#, options: .regularExpression) != nil { return true }
            if t.contains("vendor take") || t.contains("vendor-take-back") || t.contains("seller financing") || t.contains("take back mortgage") || t.contains("take-back") {
                return true
            }
            if t.contains("mortgage") { return true }
            if ["tomorrow", "today", "tonight", "morning"].contains(where: { t == $0 || t.hasSuffix(" \($0)") }) || t.contains(" next week ") {
                return true
            }
            return false
        }

        fileprivate static func isClauseJoinedFragment(_ value: String) -> Bool {
            let t = value.lowercased()
            if t.contains(", and ") { return true }
            if t.contains(" and ") && t.contains(",") { return true }
            if t.contains(" who ") || t.contains(" with ") || t.contains(" offers ") || t.contains(" offer ") || t.contains(" that ") || t.contains(" can ") {
                return true
            }
            let wordCount = t.split(whereSeparator: { $0.isWhitespace }).count
            return wordCount > 4 && (t.contains(" and ") || t.contains(","))
        }

        /// Allows compiled short `targetDescription` (house · locale · financing) in coarse token overlap; rejects raw objectives.
        fileprivate static func isCanonicalSafeCoarseTargetDescription(_ value: String) -> Bool {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 320 else { return false }
            if isClauseJoinedFragment(trimmed) { return false }
            let lower = trimmed.lowercased()
            if lower.contains("help me find") || lower.contains("help me ") { return false }
            if lower.contains("find a ") && lower.split(whereSeparator: { $0.isWhitespace }).count > 6 { return false }
            return true
        }

        private static func firstNonBlank(_ values: String?...) -> String? {
            values.first(where: { $0?.exchangeNilIfBlank != nil }) ?? nil
        }

        private static func buildRawRegionTerms(for thread: ExchangeThread) -> [String] {
            var values: [String] = []

            if let placeName = thread.facets?.placeName?.exchangeNilIfBlank {
                values.append(placeName)
            }
            if let locationText = thread.facets?.locationText?.exchangeNilIfBlank {
                values.append(locationText)
            }

            for item in thread.intent.constraints {
                if let value = item.value.exchangeNilIfBlank {
                    let key = item.key.lowercased()
                    if key.contains("location") || key.contains("region") || key.contains("place") || key.contains("city") {
                        values.append(value)
                    }
                }
            }

            return values
        }

        fileprivate static func sanitizeRawList(
            _ values: [String],
            maxCount: Int
        ) -> [String] {
            var seen = Set<String>()
            var output: [String] = []

            for value in values {
                guard let cleaned = value.exchangeNilIfBlank?
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression),
                      !cleaned.isEmpty else {
                    continue
                }

                let key = cleaned.lowercased()
                guard !seen.contains(key) else { continue }

                seen.insert(key)
                output.append(String(cleaned.prefix(120)))

                if output.count >= maxCount {
                    break
                }
            }

            return output
        }
    }

    struct DiscoveryCandidate: Sendable, Hashable {
        public enum Provenance: String, Sendable, Hashable {
            case retrievalProjected
            case legacyDirectory
            case localStore
            case unknown
        }

        public struct DirectoryEvidence: Sendable, Hashable {
            public var retrievalDocuments: [ExchangeRetrievalDocument]
            public var score: Double?
            public var matchReason: String?
            public var matchedTerms: [String]
            public var reachability: ExchangeDirectoryMatch.ReachabilityPreview?
            public var sourceMatchID: String?
            /// Lexical snapshot of the fused retrieval hit used to rebuild coarse overlap after projection.
            public var retrievalScratchText: String?

            public init(
                retrievalDocuments: [ExchangeRetrievalDocument] = [],
                score: Double? = nil,
                matchReason: String? = nil,
                matchedTerms: [String] = [],
                reachability: ExchangeDirectoryMatch.ReachabilityPreview? = nil,
                sourceMatchID: String? = nil,
                retrievalScratchText: String? = nil
            ) {
                self.retrievalDocuments = retrievalDocuments
                self.score = score
                self.matchReason = matchReason
                self.matchedTerms = matchedTerms
                self.reachability = reachability
                self.sourceMatchID = sourceMatchID
                self.retrievalScratchText = retrievalScratchText
            }
        }

        public enum SurfaceType: String, Sendable, Hashable {
            case offer
            case capability
            case affinity
            case mixed
            case unknown
        }

        public var publicProfile: ExchangePublicNodeProfile?
        public var counterparty: ExchangeCounterparty
        public var matchedOffers: [ExchangeOffer]
        public var coarse: CoarseSignal
        public var posture: ContactPosture
        public var dominantSurface: SurfaceType
        public var overallScore: Double
        public var provenance: Provenance
        public var directoryEvidence: DirectoryEvidence?
        /// Offer IDs proven by `offer_object` embedding evidence when object lane is active.
        public var provenObjectOfferIDs: Set<String>
        /// Cosine scores for proven offer IDs from the object lane.
        public var objectEvidenceScoreByOfferID: [String: Double]
        /// Semantic attach proof for selection and second-half gates.
        public var semanticProof: ExchangeCandidateSemanticProof

        public init(
            publicProfile: ExchangePublicNodeProfile?,
            counterparty: ExchangeCounterparty,
            matchedOffers: [ExchangeOffer] = [],
            coarse: CoarseSignal,
            posture: ContactPosture,
            dominantSurface: SurfaceType = .unknown,
            overallScore: Double,
            provenance: Provenance = .unknown,
            directoryEvidence: DirectoryEvidence? = nil,
            provenObjectOfferIDs: Set<String> = [],
            objectEvidenceScoreByOfferID: [String: Double] = [:],
            semanticProof: ExchangeCandidateSemanticProof = .empty
        ) {
            self.publicProfile = publicProfile
            self.counterparty = counterparty
            self.matchedOffers = matchedOffers
            self.coarse = coarse
            self.posture = posture
            self.dominantSurface = dominantSurface
            self.overallScore = overallScore
            self.provenance = provenance
            self.directoryEvidence = directoryEvidence
            self.provenObjectOfferIDs = provenObjectOfferIDs
            self.objectEvidenceScoreByOfferID = objectEvidenceScoreByOfferID
            self.semanticProof = semanticProof
        }

        public var publicProfileID: String? {
            publicProfile?.id
        }

        public var hasPublicProfile: Bool {
            publicProfile != nil
        }
    }

    struct CoarseSignal: Sendable, Hashable {
        public var queryTokenOverlap: Int
        public var explicitTokenOverlap: Int
        public var regionOverlap: Int

        public var offerOverlap: Int
        public var capabilityOverlap: Int
        public var affinityOverlap: Int

        public var hasPublicProfile: Bool
        public var hasOffers: Bool
        public var kindCompatible: Bool
        public var placeCompatible: Bool

        public var trustHintScore: Double
        public var retrievalScore: Double
        public var rationale: String

        public init(
            queryTokenOverlap: Int,
            explicitTokenOverlap: Int,
            regionOverlap: Int,
            offerOverlap: Int,
            capabilityOverlap: Int,
            affinityOverlap: Int,
            hasPublicProfile: Bool,
            hasOffers: Bool,
            kindCompatible: Bool,
            placeCompatible: Bool,
            trustHintScore: Double,
            retrievalScore: Double,
            rationale: String
        ) {
            self.queryTokenOverlap = queryTokenOverlap
            self.explicitTokenOverlap = explicitTokenOverlap
            self.regionOverlap = regionOverlap
            self.offerOverlap = offerOverlap
            self.capabilityOverlap = capabilityOverlap
            self.affinityOverlap = affinityOverlap
            self.hasPublicProfile = hasPublicProfile
            self.hasOffers = hasOffers
            self.kindCompatible = kindCompatible
            self.placeCompatible = placeCompatible
            self.trustHintScore = trustHintScore
            self.retrievalScore = retrievalScore
            self.rationale = rationale
        }

        public var isRetrievable: Bool {
            kindCompatible && placeCompatible && (
                queryTokenOverlap > 0 ||
                explicitTokenOverlap > 0 ||
                regionOverlap > 0 ||
                offerOverlap > 0 ||
                capabilityOverlap > 0 ||
                affinityOverlap > 0
            )
        }
    }

    struct ContactPosture: Sendable, Hashable {
        public enum Bucket: Int, Sendable, Hashable {
            case contactable = 4
            case introRequired = 3
            case visibleButBlocked = 2
            case visibleButWeak = 1
            case unusable = 0
        }

        public var bucket: Bucket
        public var preview: String
        public var explicitOpenness: Bool
        public var requiresIntroduction: Bool

        public init(
            bucket: Bucket,
            preview: String,
            explicitOpenness: Bool,
            requiresIntroduction: Bool
        ) {
            self.bucket = bucket
            self.preview = preview
            self.explicitOpenness = explicitOpenness
            self.requiresIntroduction = requiresIntroduction
        }
    }
}

extension ExchangeDiscoveryEngine {
    /// Coarse token bag used for discovery shortlist overlap; exposed for `@testable` requester invariants.
    func retrievalIntentTokens(for plan: SearchPlan) -> Set<String> {
        if plan.usesCanonicalDirectoryRecall {
            var parts: [String] = []
            parts.append(contentsOf: plan.canonicalDirectoryRequestTags)
            parts.append(contentsOf: plan.regionTerms)
            parts.append(contentsOf: plan.semanticTags)
            parts.append(contentsOf: plan.targetTags)
            parts.append(contentsOf: plan.providerTerms)
            parts.append(contentsOf: plan.capabilityTerms)
            parts.append(contentsOf: plan.affinityTerms)
            if let td = plan.targetDescription?.exchangeNilIfBlank,
               SearchPlan.isCanonicalSafeCoarseTargetDescription(td) {
                parts.append(td)
            }
            return Set(tokenize(parts.joined(separator: " ")))
        }

        return Set(
            tokenize(
                (
                    plan.semanticTags +
                    plan.targetTags +
                    plan.discoveryKeywords +
                    plan.providerTerms +
                    plan.capabilityTerms +
                    plan.affinityTerms +
                    plan.regionTerms +
                    plan.primaryKeywords +
                    plan.secondaryKeywords +
                    [plan.rawQueryText, plan.targetDescription].compactMap { $0 }
                ).joined(separator: " ")
            )
        )
    }
}

private extension ExchangeDiscoveryEngine {
    func discoverFromStore(
        plan: SearchPlan,
        store: any ExchangeStore,
        limit: Int
    ) async throws -> [ExchangeCounterparty] {
        exDiscoveryEngineLog(
            "discoverFromStore start " +
            "limit=\(limit) " +
            "requestTokens=\(plan.requestTokens) " +
            "preferredQuery=\(plan.preferredQueryText ?? "nil") " +
            "fallbackQuery=\(plan.fallbackQueryText ?? "nil")"
        )

        let trustLevels = plan.trustFloor.map { Set([$0]) }
        let workingLimit = max(limit * 6, 48)

        var collected: [String: ExchangeCounterparty] = [:]

        func merge(_ items: [ExchangeCounterparty], label: String) {
            exDiscoveryEngineLog("discoverFromStore merge source=\(label) count=\(items.count)")
            for item in items {
                collected[item.id] = item
            }
        }

        let storeSearchQueryText = plan.directoryQueryEmbeddingText ?? plan.preferredQueryText

        if !plan.requestTokens.isEmpty || storeSearchQueryText != nil {
            let primary = try await store.listCounterparties(
                filter: ExchangeCounterpartyFilter(
                    tags: Set(plan.requestTokens),
                    status: [.active],
                    trustLevels: trustLevels,
                    searchText: storeSearchQueryText,
                    limit: workingLimit
                )
            )
            merge(primary, label: "requestTokens+preferredQuery")
        }

        if collected.count < limit, let preferredQueryText = storeSearchQueryText {
            let queryOnly = try await store.listCounterparties(
                filter: ExchangeCounterpartyFilter(
                    tags: [],
                    status: [.active],
                    trustLevels: trustLevels,
                    searchText: preferredQueryText,
                    limit: workingLimit
                )
            )
            merge(queryOnly, label: "preferredQueryOnly")
        }

        if collected.count < limit,
           let fallbackQueryText = plan.fallbackQueryText,
           fallbackQueryText != plan.preferredQueryText {
            let fallback = try await store.listCounterparties(
                filter: ExchangeCounterpartyFilter(
                    tags: [],
                    status: [.active],
                    trustLevels: trustLevels,
                    searchText: fallbackQueryText,
                    limit: workingLimit
                )
            )
            merge(fallback, label: "fallbackQueryOnly")
        }

        let rows = Array(collected.values)
        exDiscoveryEngineLog("discoverFromStore final count=\(rows.count)")
        return rows
    }
    
    func bestQueryEmbeddingText(
        for plan: SearchPlan
    ) -> String? {
        if let english = plan.canonicalEnglishSearchText?.exchangeNilIfBlank {
            let anchored = compactDiscoveryParts([
                english,
                plan.directoryQueryEmbeddingText,
                plan.regionTerms.joined(separator: " ")
            ])
            let canonical = anchored
                .joined(separator: ". ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(
                    of: #"\s+"#,
                    with: " ",
                    options: .regularExpression
                )
            if !canonical.isEmpty {
                return String(canonical.prefix(1200))
            }
        }

        if plan.usesCanonicalDirectoryRecall {
            let anchored = compactDiscoveryParts([
                plan.directoryQueryEmbeddingText,
                plan.targetDescription,
                plan.providerTerms.joined(separator: " "),
                plan.capabilityTerms.joined(separator: " "),
                plan.affinityTerms.joined(separator: " "),
                plan.regionTerms.joined(separator: " ")
            ])

            let canonical = anchored
                .joined(separator: ". ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(
                    of: #"\s+"#,
                    with: " ",
                    options: .regularExpression
                )

            if !canonical.isEmpty {
                return String(canonical.prefix(1200))
            }
        }

        let parts = compactDiscoveryParts([
            plan.preferredQueryText,
            plan.targetDescription,
            plan.fallbackQueryText,
            plan.providerTerms.joined(separator: " "),
            plan.capabilityTerms.joined(separator: " "),
            plan.affinityTerms.joined(separator: " "),
            plan.discoveryKeywords.joined(separator: " "),
            plan.semanticTags.joined(separator: " "),
            plan.targetTags.joined(separator: " "),
            plan.primaryKeywords.joined(separator: " "),
            plan.secondaryKeywords.joined(separator: " "),
            plan.regionTerms.joined(separator: " ")
        ])

        let text = parts
            .joined(separator: ". ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )

        return text.isEmpty ? nil : String(text.prefix(1200))
    }
    
    func compactDiscoveryParts(_ values: [String?]) -> [String] {
        values.compactMap {
            let trimmed = $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    func normalizedDiscoveryTerms(_ values: [String]) -> [String] {
        Array(
            Set(
                values.compactMap {
                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return trimmed.isEmpty ? nil : trimmed
                }
            )
        )
        .sorted()
    }

    func rerankProjectedCandidates(
        _ projected: [DiscoveryCandidate],
        thread: ExchangeThread,
        plan: SearchPlan,
        localNodeID: String?,
        shortlistLimit: Int
    ) -> [DiscoveryCandidate] {
        exDiscoveryEngineLog(
            "rerankProjectedCandidates start count=\(projected.count) shortlistLimit=\(shortlistLimit)"
        )

        let commercialObjectOfferSearch = commercialObjectOfferSearchActive(
            thread: thread,
            plan: plan
        )

        var rescored: [DiscoveryCandidate] = []
        rescored.reserveCapacity(projected.count)

        for candidate in projected {
            let projectedRetrievalScore = candidate.overallScore
            let posture = contactPosture(
                for: candidate.counterparty,
                thread: thread
            )

            let matchedOffers = candidate.matchedOffers

            let trustedProfile: ExchangeTrustedNodeProfile? = nil
            let trustHintScore = baseDiscoveryScore(
                for: candidate.counterparty,
                trustedProfile: trustedProfile
            )

            let coarse = coarseSignal(
                for: candidate.counterparty,
                matchedOffers: matchedOffers,
                plan: plan,
                trustHintScore: trustHintScore,
                retrievalScratchText: candidate.directoryEvidence?.retrievalScratchText
            )

            let dominantSurface = dominantSurfaceType(
                matchedOffers: matchedOffers,
                counterparty: candidate.counterparty,
                plan: plan,
                coarse: coarse
            )

            var score = finalDiscoveryScore(
                coarse: coarse,
                posture: posture,
                dominantSurface: dominantSurface,
                plan: plan
            )

            if commercialObjectOfferSearch {
                score += objectLaneDiscoveryScoreBonus(
                    projectedRetrievalScore: projectedRetrievalScore,
                    candidate: candidate
                )
            }

            let maxObjectEvidence = commercialObjectOfferSearch
                ? maxQualifyingObjectEvidenceScore(for: candidate)
                : 0

            exDiscoveryEngineLog(
                "rerankProjectedCandidates candidate " +
                "nodeID=\(candidate.counterparty.id) " +
                "surface=\(dominantSurface.rawValue) " +
                "offerOverlap=\(coarse.offerOverlap) " +
                "capabilityOverlap=\(coarse.capabilityOverlap) " +
                "affinityOverlap=\(coarse.affinityOverlap) " +
                "queryOverlap=\(coarse.queryTokenOverlap) " +
                "explicitOverlap=\(coarse.explicitTokenOverlap) " +
                "regionOverlap=\(coarse.regionOverlap) " +
                "kindCompatible=\(coarse.kindCompatible) " +
                "placeCompatible=\(coarse.placeCompatible) " +
                "isRetrievable=\(coarse.isRetrievable) " +
                "hasOffers=\(coarse.hasOffers) " +
                "hasProfile=\(coarse.hasPublicProfile) " +
                "bucket=\(posture.bucket.rawValue) " +
                "score=\(String(format: "%.3f", score))" +
                (commercialObjectOfferSearch
                    ? " provenObjectOffers=\(candidate.provenObjectOfferIDs.count)" +
                      " maxObjectEvidence=\(String(format: "%.3f", maxObjectEvidence))" +
                      " projectedRetrievalScore=\(String(format: "%.3f", projectedRetrievalScore))"
                    : "")
            )

            if commercialObjectOfferSearch {
                let tokenScore = finalDiscoveryScore(
                    coarse: coarse,
                    posture: posture,
                    dominantSurface: dominantSurface,
                    plan: plan
                )
                exDiscoveryEngineLog(
                    "[DiscoveryObjectLaneRerank] nodeID=\(candidate.counterparty.id) " +
                    "provenObjectOfferIDs=\(Array(candidate.provenObjectOfferIDs).sorted().joined(separator: ",")) " +
                    "maxObjectEvidence=\(String(format: "%.3f", maxObjectEvidence)) " +
                    "projectedRetrievalScore=\(String(format: "%.3f", projectedRetrievalScore)) " +
                    "tokenScore=\(String(format: "%.3f", tokenScore)) " +
                    "finalScore=\(String(format: "%.3f", score))"
                )
            }

            // Do not let contact posture rescue candidates that fail explicit target-kind compatibility:
            // `isRetrievable` already requires `kindCompatible`, so widening the guard must still
            // require `kindCompatible` for the intro/posture escape hatch.
            let postureRescueAllowed =
                coarse.kindCompatible &&
                hasProfileSemanticOverlap(coarse) &&
                posture.bucket.rawValue >= ContactPosture.Bucket.introRequired.rawValue
            guard coarse.isRetrievable || postureRescueAllowed else {
                if hasProfileSemanticOverlap(coarse) && !coarse.kindCompatible {
                    logProfileCompatibilityDecision(
                        nodeID: candidate.counterparty.id,
                        reason: "profile_incompatible_despite_overlap",
                        plan: plan,
                        dominantSurface: dominantSurface,
                        coarse: coarse,
                        matchedOfferCount: matchedOffers.count
                    )
                }
                exDiscoveryEngineLog("rerankProjectedCandidates drop nodeID=\(candidate.counterparty.id) reason=not_retrievable_and_not_viable")
                continue
            }

            if profileCompatibleDiscoveryFallbackAccepted(
                counterparty: candidate.counterparty,
                matchedOffers: matchedOffers,
                plan: plan,
                coarse: coarse
            ) {
                logProfileCompatibilityDecision(
                    nodeID: candidate.counterparty.id,
                    reason: "profile_compatible_provider_fallback",
                    plan: plan,
                    dominantSurface: dominantSurface,
                    coarse: coarse,
                    matchedOfferCount: matchedOffers.count
                )
            }

            let profileOfferKeepLog =
                !matchedOffers.isEmpty &&
                dominantSurface != .offer &&
                (plan.queryIntentClass == .providerSearch || plan.queryIntentClass == .offerSearch) &&
                (plan.surfacePreference == .offer || plan.surfacePreference == .mixed)
            if profileOfferKeepLog {
                exDiscoveryEngineLog(
                    "rerankProjectedCandidates keep reason=profile_hit_with_matching_offer " +
                    "offerID=\(matchedOffers.first?.id ?? "nil") " +
                    "nodeID=\(candidate.counterparty.id) surface=\(dominantSurface.rawValue)"
                )
            }

            rescored.append(
                DiscoveryCandidate(
                    publicProfile: candidate.publicProfile,
                    counterparty: candidate.counterparty,
                    matchedOffers: matchedOffers,
                    coarse: coarse,
                    posture: posture,
                    dominantSurface: dominantSurface,
                    overallScore: score,
                    provenance: candidate.provenance,
                    directoryEvidence: candidate.directoryEvidence,
                    provenObjectOfferIDs: candidate.provenObjectOfferIDs,
                    objectEvidenceScoreByOfferID: candidate.objectEvidenceScoreByOfferID,
                    semanticProof: candidate.semanticProof
                )
            )
        }

        let sorted = rescored.sorted { lhs, rhs in
            discoveryCandidateOrdering(
                lhs: lhs,
                rhs: rhs,
                commercialObjectOfferSearch: commercialObjectOfferSearch
            )
        }
        let shortlisted = Array(sorted.prefix(shortlistLimit))

        exDiscoveryEngineLog(
            "rerankProjectedCandidates done count=\(shortlisted.count)"
        )

        if let top = shortlisted.first, let offerID = top.matchedOffers.first?.id {
            exDiscoveryEngineLog(
                "selected offerID=\(offerID) nodeID=\(top.counterparty.id)"
            )
        }

        return shortlisted
    }

    func buildCandidates(
        from matches: [ExchangeDirectoryMatch],
        thread: ExchangeThread,
        plan: SearchPlan,
        localNodeID: String?,
        shortlistLimit: Int
    ) async throws -> [DiscoveryCandidate] {
        exDiscoveryEngineLog(
            "buildCandidates(directory matches) start matches=\(matches.count) localNodeID=\(localNodeID ?? "nil") shortlistLimit=\(shortlistLimit)"
        )

        var coarseCandidates: [DiscoveryCandidate] = []
        coarseCandidates.reserveCapacity(matches.count)

        for match in matches {
            let counterparty = match.counterparty
            let trustedNodeID = counterparty.identity?.nodeID ?? counterparty.id

            let trustedProfile: ExchangeTrustedNodeProfile?
            if let store {
                trustedProfile = try await store.fetchTrustedNodeProfile(
                    nodeID: trustedNodeID,
                    forSourceNodeID: localNodeID
                )
            } else {
                trustedProfile = nil
            }

            let publicProfile = match.publicProfile ?? counterparty.publicProfile
            let hydratedOffers = match.offers.filter {
                $0.status == .active &&
                ($0.visibility == .publicDiscoverable || $0.visibility == .limitedSurface)
            }
            let objectLaneAttachment = ExchangeOfferObjectLane.applyObjectLaneOfferAttachmentPolicy(
                thread: thread,
                offers: hydratedOffers,
                provenObjectOfferIDs: [],
                objectEvidenceScoreByOfferID: [:]
            )
            let matchedOffers = objectLaneAttachment.matchedOffers

            let posture = contactPosture(
                for: counterparty,
                thread: thread
            )

            let trustHintScore = baseDiscoveryScore(
                for: counterparty,
                trustedProfile: trustedProfile
            )

            let coarse = coarseSignal(
                for: counterparty,
                matchedOffers: matchedOffers,
                plan: plan,
                trustHintScore: trustHintScore,
                retrievalScratchText: nil
            )

            let dominantSurface = dominantSurfaceType(
                matchedOffers: matchedOffers,
                counterparty: counterparty,
                plan: plan,
                coarse: coarse
            )

            let score = finalDiscoveryScore(
                coarse: coarse,
                posture: posture,
                dominantSurface: dominantSurface,
                plan: plan
            )

            exDiscoveryEngineLog(
                "buildCandidates(directory matches) coarse " +
                "nodeID=\(counterparty.id) " +
                "surface=\(dominantSurface.rawValue) " +
                "offers=\(matchedOffers.count) " +
                "offerOverlap=\(coarse.offerOverlap) " +
                "capabilityOverlap=\(coarse.capabilityOverlap) " +
                "affinityOverlap=\(coarse.affinityOverlap) " +
                "queryOverlap=\(coarse.queryTokenOverlap) " +
                "explicitOverlap=\(coarse.explicitTokenOverlap) " +
                "regionOverlap=\(coarse.regionOverlap) " +
                "kindCompatible=\(coarse.kindCompatible) " +
                "placeCompatible=\(coarse.placeCompatible) " +
                "hasProfile=\(coarse.hasPublicProfile) " +
                "trustHint=\(String(format: "%.3f", coarse.trustHintScore)) " +
                "score=\(String(format: "%.3f", score)) " +
                "bucket=\(posture.bucket.rawValue) " +
                "rationale=\(coarse.rationale)"
            )

            let postureRescueDirectory =
                coarse.kindCompatible &&
                hasProfileSemanticOverlap(coarse) &&
                posture.bucket.rawValue >= ContactPosture.Bucket.introRequired.rawValue
            guard coarse.isRetrievable || postureRescueDirectory else {
                exDiscoveryEngineLog("buildCandidates(directory matches) drop nodeID=\(counterparty.id) reason=not_retrievable_and_not_viable")
                continue
            }

            coarseCandidates.append(
                DiscoveryCandidate(
                    publicProfile: publicProfile,
                    counterparty: counterparty,
                    matchedOffers: matchedOffers,
                    coarse: coarse,
                    posture: posture,
                    dominantSurface: dominantSurface,
                    overallScore: score,
                    provenance: .legacyDirectory,
                    directoryEvidence: .init(
                        retrievalDocuments: match.retrievalDocuments,
                        score: match.score,
                        matchReason: match.matchReason,
                        matchedTerms: match.matchedTerms,
                        reachability: match.reachability,
                        sourceMatchID: match.id
                    ),
                    provenObjectOfferIDs: objectLaneAttachment.provenObjectOfferIDs,
                    objectEvidenceScoreByOfferID: objectLaneAttachment.objectEvidenceScoreByOfferID
                )
            )
        }

        let sorted = coarseCandidates.sorted(by: rankedOrdering)
        let shortlisted = Array(sorted.prefix(shortlistLimit))

        exDiscoveryEngineLog(
            "buildCandidates(directory matches) shortlisted count=\(shortlisted.count) from=\(coarseCandidates.count)"
        )

        return shortlisted
    }

    func buildCandidates(
        from counterparties: [ExchangeCounterparty],
        thread: ExchangeThread,
        plan: SearchPlan,
        localNodeID: String?,
        shortlistLimit: Int
    ) async throws -> [DiscoveryCandidate] {
        exDiscoveryEngineLog(
            "buildCandidates start counterparties=\(counterparties.count) localNodeID=\(localNodeID ?? "nil") shortlistLimit=\(shortlistLimit)"
        )

        var coarseCandidates: [DiscoveryCandidate] = []
        coarseCandidates.reserveCapacity(counterparties.count)

        for counterparty in counterparties {
            let trustedNodeID = counterparty.identity?.nodeID ?? counterparty.id

            let trustedProfile: ExchangeTrustedNodeProfile?
            if let store {
                trustedProfile = try await store.fetchTrustedNodeProfile(
                    nodeID: trustedNodeID,
                    forSourceNodeID: localNodeID
                )
            } else {
                trustedProfile = nil
            }

            let posture = contactPosture(
                for: counterparty,
                thread: thread
            )

            let trustHintScore = baseDiscoveryScore(
                for: counterparty,
                trustedProfile: trustedProfile
            )

            let coarse = coarseSignal(
                for: counterparty,
                matchedOffers: [],
                plan: plan,
                trustHintScore: trustHintScore,
                retrievalScratchText: nil
            )

            let dominantSurface = dominantSurfaceType(
                matchedOffers: [],
                counterparty: counterparty,
                plan: plan,
                coarse: coarse
            )

            let score = finalDiscoveryScore(
                coarse: coarse,
                posture: posture,
                dominantSurface: dominantSurface,
                plan: plan
            )

            exDiscoveryEngineLog(
                "buildCandidates coarse " +
                "nodeID=\(counterparty.id) " +
                "surface=\(dominantSurface.rawValue) " +
                "offerOverlap=\(coarse.offerOverlap) " +
                "capabilityOverlap=\(coarse.capabilityOverlap) " +
                "affinityOverlap=\(coarse.affinityOverlap) " +
                "queryOverlap=\(coarse.queryTokenOverlap) " +
                "explicitOverlap=\(coarse.explicitTokenOverlap) " +
                "regionOverlap=\(coarse.regionOverlap) " +
                "kindCompatible=\(coarse.kindCompatible) " +
                "placeCompatible=\(coarse.placeCompatible) " +
                "hasProfile=\(coarse.hasPublicProfile) " +
                "trustHint=\(String(format: "%.3f", coarse.trustHintScore)) " +
                "score=\(String(format: "%.3f", score)) " +
                "bucket=\(posture.bucket.rawValue) " +
                "rationale=\(coarse.rationale)"
            )

            let postureRescueLocalStore =
                coarse.kindCompatible &&
                hasProfileSemanticOverlap(coarse) &&
                posture.bucket.rawValue >= ContactPosture.Bucket.introRequired.rawValue
            guard coarse.isRetrievable || postureRescueLocalStore else {
                exDiscoveryEngineLog("buildCandidates drop nodeID=\(counterparty.id) reason=not_retrievable_and_not_viable")
                continue
            }

            coarseCandidates.append(
                DiscoveryCandidate(
                    publicProfile: counterparty.publicProfile,
                    counterparty: counterparty,
                    matchedOffers: [],
                    coarse: coarse,
                    posture: posture,
                    dominantSurface: dominantSurface,
                    overallScore: score,
                    provenance: .localStore
                )
            )
        }

        let coarseSorted = coarseCandidates.sorted(by: rankedOrdering)
        let shortlistedBase = Array(coarseSorted.prefix(shortlistLimit))

        exDiscoveryEngineLog(
            "buildCandidates coarse shortlist count=\(shortlistedBase.count) from=\(coarseCandidates.count)"
        )

        var enriched: [DiscoveryCandidate] = []
        enriched.reserveCapacity(shortlistedBase.count)

        for base in shortlistedBase {
            let counterparty = base.counterparty
            let publicProfile = base.publicProfile

            let matchedOffers: [ExchangeOffer]
            let provenObjectOfferIDs: Set<String>
            let objectEvidenceScoreByOfferID: [String: Double]

            if ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) {
                matchedOffers = []
                provenObjectOfferIDs = []
                objectEvidenceScoreByOfferID = [:]
            } else if let store, let publicProfileID = publicProfile?.id {
                let fetchedOffers = try await store.listOffers(
                    filter: ExchangeOfferFilter(
                        publicProfileID: publicProfileID,
                        statuses: Set<ExchangeOffer.Status>([.active]),
                        visibility: Set<ExchangeOffer.Visibility>([.publicDiscoverable, .limitedSurface]),
                        categories: Set<String>(),
                        searchText: plan.preferredQueryText,
                        limit: 6
                    )
                )

                matchedOffers = relevanceOrderedMatchedOffers(
                    fetchedOffers,
                    plan: plan,
                    thread: thread
                )
                provenObjectOfferIDs = []
                objectEvidenceScoreByOfferID = [:]
            } else {
                matchedOffers = []
                provenObjectOfferIDs = []
                objectEvidenceScoreByOfferID = [:]
            }

            let trustHintScore = base.coarse.trustHintScore
            let refreshedCoarse = coarseSignal(
                for: counterparty,
                matchedOffers: matchedOffers,
                plan: plan,
                trustHintScore: trustHintScore,
                retrievalScratchText: nil
            )

            let dominantSurface = dominantSurfaceType(
                matchedOffers: matchedOffers,
                counterparty: counterparty,
                plan: plan,
                coarse: refreshedCoarse
            )

            let refreshedScore = finalDiscoveryScore(
                coarse: refreshedCoarse,
                posture: base.posture,
                dominantSurface: dominantSurface,
                plan: plan
            )

            exDiscoveryEngineLog(
                "buildCandidates shortlisted " +
                "nodeID=\(counterparty.id) " +
                "surface=\(dominantSurface.rawValue) " +
                "offerCount=\(matchedOffers.count) " +
                "offerOverlap=\(refreshedCoarse.offerOverlap) " +
                "capabilityOverlap=\(refreshedCoarse.capabilityOverlap) " +
                "affinityOverlap=\(refreshedCoarse.affinityOverlap) " +
                "queryOverlap=\(refreshedCoarse.queryTokenOverlap) " +
                "explicitOverlap=\(refreshedCoarse.explicitTokenOverlap) " +
                "regionOverlap=\(refreshedCoarse.regionOverlap) " +
                "score=\(String(format: "%.3f", refreshedScore)) " +
                "bucket=\(base.posture.bucket.rawValue)"
            )

            enriched.append(
                DiscoveryCandidate(
                    publicProfile: publicProfile,
                    counterparty: counterparty,
                    matchedOffers: matchedOffers,
                    coarse: refreshedCoarse,
                    posture: base.posture,
                    dominantSurface: dominantSurface,
                    overallScore: refreshedScore,
                    provenance: base.provenance,
                    directoryEvidence: base.directoryEvidence,
                    provenObjectOfferIDs: provenObjectOfferIDs,
                    objectEvidenceScoreByOfferID: objectEvidenceScoreByOfferID
                )
            )
        }

        let sorted = enriched.sorted(by: rankedOrdering)

        if let top = sorted.first {
            exDiscoveryEngineLog(
                "buildCandidates top counterpartyID=\(top.counterparty.id) profileID=\(top.publicProfileID ?? "nil") offers=\(top.matchedOffers.count) surface=\(top.dominantSurface.rawValue) score=\(String(format: "%.3f", top.overallScore)) bucket=\(top.posture.bucket.rawValue)"
            )
        }

        return sorted
    }

    func retrievalScratchTokenOverlay(_ text: String?) -> Set<String> {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        let clipped = String(raw.prefix(1200))
        return Set(tokenize(clipped))
    }

    func coarseSignal(
        for counterparty: ExchangeCounterparty,
        matchedOffers: [ExchangeOffer],
        plan: SearchPlan,
        trustHintScore: Double,
        retrievalScratchText: String? = nil
    ) -> CoarseSignal {
        let requestTokens = retrievalIntentTokens(for: plan)
        let offerTokens = offerSurfaceTokens(matchedOffers: matchedOffers)
        let scratchOverlay = retrievalScratchTokenOverlay(retrievalScratchText)
        let capabilityTokens = capabilitySurfaceTokens(counterparty: counterparty).union(scratchOverlay)
        let affinityTokens = affinitySurfaceTokens(counterparty: counterparty)

        let explicitTokens = explicitSurfaceTokens(
            counterparty: counterparty,
            matchedOffers: matchedOffers
        )

        let allTokens = offerTokens
            .union(capabilityTokens)
            .union(affinityTokens)
            .union(explicitTokens)

        let requestedRegionTokens = Set(tokenize(plan.regionTerms.joined(separator: " ")))
        let candidateRegionTokens = regionTokens(
            counterparty: counterparty,
            matchedOffers: matchedOffers
        )

        let queryOverlap = requestTokens.intersection(allTokens).count
        let explicitOverlap = requestTokens.intersection(explicitTokens).count
        let regionOverlap: Int = {
            if let requirement = plan.locationRequirement, requirement.kind != .none {
                let areas = matchedOffers.flatMap(\.effectiveServiceAreas)
                let match = ExchangeServiceAreaMatcher.match(
                    requirement: requirement,
                    serviceAreas: areas,
                    fulfillmentRemoteFriendly: matchedOffers.contains(where: \.fulfillment.remoteFriendly)
                )
                return ExchangeServiceAreaMatcher.tierOrdinal(match.tier)
            }
            return requestedRegionTokens.intersection(candidateRegionTokens).count
        }()

        let providerAreas = matchedOffers.flatMap(\.effectiveServiceAreas)
        let textRegionMatchSucceeded: Bool = {
            if regionOverlap > 0 { return true }
            if let requirement = plan.locationRequirement, requirement.kind != .none {
                let match = ExchangeServiceAreaMatcher.match(
                    requirement: requirement,
                    serviceAreas: providerAreas,
                    fulfillmentRemoteFriendly: matchedOffers.contains(where: \.fulfillment.remoteFriendly)
                )
                return match.tier != .none && match.isCompatible
            }
            return regionOverlap > 0
        }()

        let offerOverlap = requestTokens.intersection(offerTokens).count
        let capabilityOverlap = requestTokens.intersection(capabilityTokens).count
        let affinityOverlap = requestTokens.intersection(affinityTokens).count

        let kindCompatible = isTargetKindCompatible(
            counterparty: counterparty,
            matchedOffers: matchedOffers,
            plan: plan,
            offerOverlap: offerOverlap,
            capabilityOverlap: capabilityOverlap,
            affinityOverlap: affinityOverlap,
            queryTokenOverlap: queryOverlap
        )
        let placeCompatible = isPlaceCompatible(
            counterparty: counterparty,
            plan: plan,
            matchedOffers: matchedOffers
        )

        var retrievalScore = 0.0
        if kindCompatible { retrievalScore += 0.20 }
        if placeCompatible { retrievalScore += 0.15 }
        if counterparty.publicProfile != nil { retrievalScore += 0.10 }
        if !matchedOffers.isEmpty { retrievalScore += 0.08 }

        retrievalScore += weightedSurfaceEvidence(
            offerOverlap: offerOverlap,
            capabilityOverlap: capabilityOverlap,
            affinityOverlap: affinityOverlap,
            plan: plan
        )

        retrievalScore += min(Double(explicitOverlap) * 0.06, 0.18)
        retrievalScore += min(Double(queryOverlap) * 0.03, 0.15)
        retrievalScore += min(Double(regionOverlap) * 0.08, 0.16)
        retrievalScore += min(trustHintScore * 0.12, 0.18)

        let spatialAdjustment = ExchangeSpatialOverlapScoring.evaluate(
            requesterAnchor: plan.requesterSpatialAnchor,
            providerAreas: providerAreas,
            explicitRegionRequired: plan.explicitRegionRequired,
            textRegionMatchSucceeded: textRegionMatchSucceeded
        )
        retrievalScore += spatialAdjustment.boost
        retrievalScore -= spatialAdjustment.demotion

        #if DEBUG
        if plan.requesterSpatialAnchor?.hasResolvedSpatial == true
            || ExchangeSpatialOverlapScoring.providerHasResolvedH3(providerAreas) {
            print(
                ExchangeSpatialOverlapScoring.discoveryLogLine(
                    adjustment: spatialAdjustment,
                    requesterResolved: plan.requesterSpatialAnchor?.hasResolvedSpatial == true,
                    providerHasResolvedH3: ExchangeSpatialOverlapScoring.providerHasResolvedH3(providerAreas)
                )
            )
        }
        #endif

        let rationale = rationaleForSurfaceEvidence(
            offerOverlap: offerOverlap,
            capabilityOverlap: capabilityOverlap,
            affinityOverlap: affinityOverlap,
            explicitOverlap: explicitOverlap,
            regionOverlap: regionOverlap,
            plan: plan
        )

        return CoarseSignal(
            queryTokenOverlap: queryOverlap,
            explicitTokenOverlap: explicitOverlap,
            regionOverlap: regionOverlap,
            offerOverlap: offerOverlap,
            capabilityOverlap: capabilityOverlap,
            affinityOverlap: affinityOverlap,
            hasPublicProfile: counterparty.publicProfile != nil,
            hasOffers: !matchedOffers.isEmpty,
            kindCompatible: kindCompatible,
            placeCompatible: placeCompatible,
            trustHintScore: trustHintScore,
            retrievalScore: retrievalScore,
            rationale: rationale
        )
    }
    
    func relevanceOrderedMatchedOffers(
        _ offers: [ExchangeOffer],
        plan: SearchPlan,
        thread: ExchangeThread? = nil
    ) -> [ExchangeOffer] {
        if let thread, ExchangeOfferObjectLane.isObjectLaneActive(thread: thread) {
            return []
        }

        guard offers.count > 1 else { return offers }

        let requestTokens = Set(
            tokenize(
                [
                    plan.preferredQueryText,
                    plan.placeName,
                    plan.locationText,
                    plan.regionTerms.joined(separator: " "),
                    plan.discoveryKeywords.joined(separator: " "),
                    plan.targetTags.joined(separator: " ")
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            )
        )

        guard !requestTokens.isEmpty else { return offers }

        func offerText(_ offer: ExchangeOffer) -> String {
            var values: [String] = [
                offer.title,
                offer.summary ?? "",
                offer.category ?? "",
                offer.tags.joined(separator: " "),
                offer.regionTags.joined(separator: " "),
                offer.regionAliases.joined(separator: " ")
            ]

            values.append(String(describing: offer.commercialFacts))
            values.append(String(describing: offer.fulfillment))

            return values.joined(separator: " ")
        }

        func score(_ offer: ExchangeOffer) -> Int {
            let tokens = Set(tokenize(offerText(offer)))
            return requestTokens.intersection(tokens).count
        }

        return offers.sorted { lhs, rhs in
            let ls = score(lhs)
            let rs = score(rhs)

            if ls != rs { return ls > rs }

            let lt = lhs.updatedAt
            let rt = rhs.updatedAt
            if lt != rt { return lt > rt }

            return lhs.id < rhs.id
        }
    }

    func offerSurfaceTokens(
        matchedOffers: [ExchangeOffer]
    ) -> Set<String> {
        var values: [String] = []

        for offer in matchedOffers {
            let primaryText = compactDiscoveryParts([
                offer.title,
                offer.summary,
                offer.category
            ]).joined(separator: ". ")

            let secondaryText = compactDiscoveryParts([
                offer.tags.joined(separator: " "),
                offer.regionTags.joined(separator: " "),
                offer.regionAliases.joined(separator: " "),
                offer.fulfillment.leadTimeNote,
                offer.fulfillment.capacityNote
            ]).joined(separator: ". ")

            let semanticText = compactDiscoveryParts([
                offer.semantic.domains.joined(separator: " "),
                offer.semantic.serviceKinds.joined(separator: " "),
                offer.semantic.audienceKinds.map(\.rawValue).joined(separator: " "),
                offer.semantic.fulfillmentModes.map(\.rawValue).joined(separator: " "),
                offer.semantic.notes
            ]).joined(separator: ". ")

            let providerTerms = normalizedDiscoveryTerms(
                [offer.title] +
                [offer.summary].compactMap { $0 } +
                [offer.category].compactMap { $0 } +
                offer.tags +
                offer.semantic.domains +
                offer.semantic.serviceKinds
            )

            let capabilityTerms = normalizedDiscoveryTerms(
                offer.semantic.serviceKinds +
                offer.semantic.audienceKinds.map(\.rawValue) +
                offer.semantic.fulfillmentModes.map(\.rawValue)
            )

            let filterTokens = normalizedDiscoveryTerms(
                offer.tags +
                [offer.category].compactMap { $0 } +
                providerTerms +
                capabilityTerms +
                offer.regionTags
            )

            values.append(contentsOf: [
                primaryText,
                secondaryText,
                semanticText,
                providerTerms.joined(separator: " "),
                capabilityTerms.joined(separator: " "),
                filterTokens.joined(separator: " ")
            ])
        }

        return Set(tokenize(values.joined(separator: " ")))
    }

    func capabilitySurfaceTokens(
        counterparty: ExchangeCounterparty
    ) -> Set<String> {
        guard let profile = counterparty.publicProfile else { return [] }

        let title = profile.displayName ?? counterparty.displayName
        let summary = profile.summaryLine

        let primaryText = compactDiscoveryParts([
            title,
            profile.headline,
            summary
        ]).joined(separator: ". ")

        let secondaryText = compactDiscoveryParts([
            profile.offers.joined(separator: " "),
            profile.openTo.joined(separator: " "),
            profile.activityTags.joined(separator: " "),
            profile.regionTags.joined(separator: " ")
        ]).joined(separator: ". ")

        let semanticText = compactDiscoveryParts([
            profile.semantic.domains.joined(separator: " "),
            profile.semantic.intentKinds.joined(separator: " "),
            profile.semantic.audienceKinds.map(\.rawValue).joined(separator: " "),
            profile.semantic.fulfillmentModes.map(\.rawValue).joined(separator: " "),
            profile.semantic.notes
        ]).joined(separator: ". ")

        let providerTerms = normalizedDiscoveryTerms([
            title,
            profile.headline,
            summary
        ].compactMap { $0 })

        let capabilityTerms = normalizedDiscoveryTerms(
            profile.semantic.domains +
            profile.semantic.intentKinds +
            profile.offers +
            profile.openTo +
            profile.semantic.audienceKinds.map(\.rawValue) +
            profile.semantic.fulfillmentModes.map(\.rawValue)
        )

        let filterTokens = normalizedDiscoveryTerms(
            profile.offers +
            profile.openTo +
            profile.activityTags +
            capabilityTerms +
            providerTerms +
            profile.regionTags
        )

        let values: [String] = [
            primaryText,
            secondaryText,
            semanticText,
            providerTerms.joined(separator: " "),
            capabilityTerms.joined(separator: " "),
            filterTokens.joined(separator: " ")
        ]

        return Set(tokenize(values.joined(separator: " ")))
    }

    func affinitySurfaceTokens(
        counterparty: ExchangeCounterparty
    ) -> Set<String> {
        guard let profile = counterparty.publicProfile else { return [] }

        let title = profile.displayName ?? counterparty.displayName
        let summary = profile.summaryLine

        let primaryText = compactDiscoveryParts([
            title,
            summary
        ]).joined(separator: ". ")

        let secondaryText = compactDiscoveryParts([
            profile.interests.joined(separator: " "),
            profile.activityTags.joined(separator: " "),
            profile.openTo.joined(separator: " "),
            profile.regionTags.joined(separator: " ")
        ]).joined(separator: ". ")

        let semanticText = compactDiscoveryParts([
            profile.semantic.intentKinds.joined(separator: " "),
            profile.semantic.notes
        ]).joined(separator: ". ")

        let providerTerms = normalizedDiscoveryTerms([
            title,
            profile.headline,
            summary
        ].compactMap { $0 })

        let affinityTerms = normalizedDiscoveryTerms(
            profile.interests +
            profile.activityTags +
            profile.openTo +
            profile.semantic.intentKinds
        )

        let filterTokens = normalizedDiscoveryTerms(
            profile.interests +
            profile.activityTags +
            profile.openTo +
            affinityTerms +
            providerTerms +
            profile.regionTags
        )

        let values: [String] = [
            primaryText,
            secondaryText,
            semanticText,
            providerTerms.joined(separator: " "),
            affinityTerms.joined(separator: " "),
            filterTokens.joined(separator: " ")
        ]

        return Set(tokenize(values.joined(separator: " ")))
    }

    func explicitSurfaceTokens(
        counterparty: ExchangeCounterparty,
        matchedOffers: [ExchangeOffer]
    ) -> Set<String> {
        var values: [String] = []

        if let profile = counterparty.publicProfile {
            let title = profile.displayName ?? counterparty.displayName
            let summary = profile.summaryLine

            let providerTerms = normalizedDiscoveryTerms([
                title,
                profile.headline,
                summary
            ].compactMap { $0 })

            values.append(providerTerms.joined(separator: " "))
            values.append(profile.regionTags.joined(separator: " "))
        }

        for offer in matchedOffers {
            let providerTerms = normalizedDiscoveryTerms(
                [offer.title] +
                [offer.summary].compactMap { $0 } +
                [offer.category].compactMap { $0 } +
                offer.tags +
                offer.semantic.domains +
                offer.semantic.serviceKinds
            )

            values.append(providerTerms.joined(separator: " "))
            values.append(offer.regionTags.joined(separator: " "))
            values.append(offer.regionAliases.joined(separator: " "))
        }

        return Set(tokenize(values.joined(separator: " ")))
    }

    func regionTokens(
        counterparty: ExchangeCounterparty,
        matchedOffers: [ExchangeOffer]
    ) -> Set<String> {
        var values: [String] = []

        if let profile = counterparty.publicProfile {
            let title = profile.displayName ?? counterparty.displayName
            let summary = profile.summaryLine

            let secondaryText = compactDiscoveryParts([
                profile.offers.joined(separator: " "),
                profile.openTo.joined(separator: " "),
                profile.activityTags.joined(separator: " "),
                profile.regionTags.joined(separator: " ")
            ]).joined(separator: ". ")

            values.append(contentsOf: [
                counterparty.location?.summaryLine ?? "",
                profile.regionTags.joined(separator: " "),
                title,
                profile.headline ?? "",
                summary,
                secondaryText
            ])
        } else {
            values.append(counterparty.location?.summaryLine ?? "")
        }

        for offer in matchedOffers {
            let secondaryText = compactDiscoveryParts([
                offer.tags.joined(separator: " "),
                offer.regionTags.joined(separator: " "),
                offer.regionAliases.joined(separator: " "),
                offer.fulfillment.leadTimeNote,
                offer.fulfillment.capacityNote
            ]).joined(separator: ". ")

            values.append(contentsOf: [
                offer.regionTags.joined(separator: " "),
                offer.regionAliases.joined(separator: " "),
                offer.title,
                offer.summary ?? "",
                offer.category ?? "",
                secondaryText
            ])
        }

        return Set(tokenize(values.joined(separator: " ")))
    }

    func weightedSurfaceEvidence(
        offerOverlap: Int,
        capabilityOverlap: Int,
        affinityOverlap: Int,
        plan: SearchPlan
    ) -> Double {
        let offerScore = min(Double(offerOverlap) * 0.08, 0.32)
        let capabilityScore = min(Double(capabilityOverlap) * 0.07, 0.28)
        let affinityScore = min(Double(affinityOverlap) * 0.07, 0.28)

        switch plan.queryIntentClass {
        case .providerSearch, .offerSearch:
            return offerScore * 1.8 + capabilityScore * 0.9 + affinityScore * 0.1
        case .capabilitySearch, .collaborationSearch:
            return offerScore * 0.8 + capabilityScore * 1.5 + affinityScore * 0.4
        case .socialAffinitySearch, .relationshipSearch:
            return offerScore * 0.2 + capabilityScore * 0.8 + affinityScore * 1.8
        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return offerScore * 0.9 + capabilityScore * 1.0 + affinityScore * 0.6
        }
    }

    func rationaleForSurfaceEvidence(
        offerOverlap: Int,
        capabilityOverlap: Int,
        affinityOverlap: Int,
        explicitOverlap: Int,
        regionOverlap: Int,
        plan: SearchPlan
    ) -> String {
        if offerOverlap >= capabilityOverlap && offerOverlap >= affinityOverlap && offerOverlap > 0 {
            return "offer-led surface overlap for \(plan.queryIntentClass.rawValue)"
        }
        if capabilityOverlap >= offerOverlap && capabilityOverlap >= affinityOverlap && capabilityOverlap > 0 {
            return "capability-led surface overlap for \(plan.queryIntentClass.rawValue)"
        }
        if affinityOverlap > 0 {
            return "affinity-led surface overlap for \(plan.queryIntentClass.rawValue)"
        }
        if explicitOverlap > 0 {
            return "explicit public surface overlap"
        }
        if regionOverlap > 0 {
            return "region overlap only"
        }
        return "weak coarse retrieval signal"
    }

    func dominantSurfaceType(
        matchedOffers: [ExchangeOffer],
        counterparty: ExchangeCounterparty,
        plan: SearchPlan,
        coarse: CoarseSignal
    ) -> DiscoveryCandidate.SurfaceType {
        if coarse.offerOverlap >= coarse.capabilityOverlap &&
            coarse.offerOverlap >= coarse.affinityOverlap &&
            coarse.offerOverlap > 0 {
            return .offer
        }

        if coarse.affinityOverlap >= coarse.offerOverlap &&
            coarse.affinityOverlap >= coarse.capabilityOverlap &&
            coarse.affinityOverlap > 0 {
            return .affinity
        }

        if coarse.capabilityOverlap > 0 {
            return .capability
        }

        switch plan.surfacePreference {
        case .offer:
            return matchedOffers.isEmpty ? .mixed : .offer
        case .capability:
            return .capability
        case .affinity:
            return .affinity
        case .mixed:
            return matchedOffers.isEmpty ? .capability : .mixed
        }
    }

    func finalDiscoveryScore(
        coarse: CoarseSignal,
        posture: ContactPosture,
        dominantSurface: DiscoveryCandidate.SurfaceType,
        plan: SearchPlan
    ) -> Double {
        let postureBonus = contactabilityScoreBonus(posture.bucket)
        let surfaceBonus = dominantSurfaceBonus(dominantSurface, plan: plan)
        let offerBonus = coarse.hasOffers ? 0.08 : 0.0
        return coarse.retrievalScore + postureBonus + surfaceBonus + offerBonus
    }

    func commercialObjectOfferSearchActive(
        thread: ExchangeThread,
        plan: SearchPlan
    ) -> Bool {
        guard plan.queryIntentClass == .offerSearch else { return false }
        guard plan.surfacePreference == .offer else { return false }
        return ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
    }

    func maxQualifyingObjectEvidenceScore(
        for candidate: DiscoveryCandidate
    ) -> Double {
        candidate.objectEvidenceScoreByOfferID
            .filter { entry in
                candidate.provenObjectOfferIDs.contains(entry.key)
                    && entry.value >= ExchangeOfferObjectLane.minimumObjectEvidenceScore
            }
            .values
            .max() ?? 0
    }

    func objectLaneDiscoveryScoreBonus(
        projectedRetrievalScore: Double,
        candidate: DiscoveryCandidate
    ) -> Double {
        guard !candidate.provenObjectOfferIDs.isEmpty else { return 0 }
        let maxObject = maxQualifyingObjectEvidenceScore(for: candidate)
        guard maxObject > 0 else { return 0 }

        let objectLift = maxObject * 0.45
        let retrievalCarryover = min(max(projectedRetrievalScore, 0), 3.0) * 0.10
        return objectLift + retrievalCarryover
    }

    func baseDiscoveryScore(
        for counterparty: ExchangeCounterparty,
        trustedProfile: ExchangeTrustedNodeProfile?
    ) -> Double {
        var score = 0.0

        switch counterparty.trust.level {
        case .high:
            score += 0.40
        case .moderate:
            score += 0.25
        case .low:
            score += 0.10
        case .unverified:
            score += counterparty.identity?.verification == .cryptographicallyVerified ? 0.15 : 0.0
        }

        if counterparty.publicProfile != nil {
            score += 0.20
        }

        if let trustedProfile {
            if trustedProfile.isLocallyTrusted { score += 0.75 }
            if trustedProfile.isMutual { score += 0.20 }
            score += min(Double(trustedProfile.networkTrust.trustedByYourTrustedCount) * 0.08, 0.24)
            score += min(Double(trustedProfile.networkTrust.trustedByHighTrustCount) * 0.05, 0.15)
            score += min(Double(trustedProfile.networkTrust.mutualTrustCount) * 0.04, 0.12)
        }

        return score
    }

    func contactPosture(
        for counterparty: ExchangeCounterparty,
        thread: ExchangeThread
    ) -> ContactPosture {
        guard let publicProfile = counterparty.publicProfile else {
            return .init(
                bucket: .visibleButWeak,
                preview: "No explicit public profile is attached; relevance may exist, but openness is not explicit.",
                explicitOpenness: false,
                requiresIntroduction: false
            )
        }

        guard publicProfile.visibility != .hidden else {
            return .init(
                bucket: .unusable,
                preview: "The public surface is hidden.",
                explicitOpenness: false,
                requiresIntroduction: false
            )
        }

        guard publicProfile.availability != .unavailable else {
            return .init(
                bucket: .visibleButBlocked,
                preview: "The public surface exists, but the profile is currently unavailable.",
                explicitOpenness: true,
                requiresIntroduction: false
            )
        }

        guard publicProfile.reachability.acceptingInbound else {
            return .init(
                bucket: .visibleButBlocked,
                preview: "The public surface exists, but the profile is not currently accepting inbound coordination.",
                explicitOpenness: true,
                requiresIntroduction: false
            )
        }

        if let minimumTrust = publicProfile.reachability.minimumTrustLevel,
           trustRank(counterparty.trust.level) < trustRank(minimumTrust) {
            return .init(
                bucket: .visibleButBlocked,
                preview: "The public surface exists, but trust is below the required threshold.",
                explicitOpenness: true,
                requiresIntroduction: false
            )
        }

        switch publicProfile.reachability.accessMode {
        case .direct:
            return .init(
                bucket: .contactable,
                preview: "Relevant public surface with direct contact allowed.",
                explicitOpenness: true,
                requiresIntroduction: false
            )
        case .introPreferred:
            return .init(
                bucket: .contactable,
                preview: "Relevant public surface with direct contact allowed; introduction is preferred.",
                explicitOpenness: true,
                requiresIntroduction: false
            )
        case .introRequired:
            if threadHasTrustedIntroduction(thread) {
                return .init(
                    bucket: .contactable,
                    preview: "Relevant public surface with an introduction-qualified path.",
                    explicitOpenness: true,
                    requiresIntroduction: true
                )
            }

            return .init(
                bucket: .introRequired,
                preview: "Relevant public surface found, but introduction is required.",
                explicitOpenness: true,
                requiresIntroduction: true
            )
        case .closed:
            return .init(
                bucket: .visibleButBlocked,
                preview: "Relevant public surface found, but contact is currently closed.",
                explicitOpenness: true,
                requiresIntroduction: false
            )
        }
    }

    func contactabilityScoreBonus(_ bucket: ContactPosture.Bucket) -> Double {
        switch bucket {
        case .contactable:
            return 0.30
        case .introRequired:
            return 0.14
        case .visibleButBlocked:
            return 0.02
        case .visibleButWeak:
            return 0.00
        case .unusable:
            return -0.20
        }
    }

    func dominantSurfaceBonus(
        _ surface: DiscoveryCandidate.SurfaceType,
        plan: SearchPlan
    ) -> Double {
        switch plan.queryIntentClass {
        case .providerSearch, .offerSearch:
            switch surface {
            case .offer: return 0.20
            case .capability: return 0.08
            case .affinity: return -0.10
            case .mixed: return 0.10
            case .unknown: return 0.0
            }
        case .capabilitySearch, .collaborationSearch:
            switch surface {
            case .offer: return 0.04
            case .capability: return 0.18
            case .affinity: return -0.02
            case .mixed: return 0.10
            case .unknown: return 0.0
            }
        case .socialAffinitySearch, .relationshipSearch:
            switch surface {
            case .offer: return -0.10
            case .capability: return 0.05
            case .affinity: return 0.20
            case .mixed: return 0.08
            case .unknown: return 0.0
            }
        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            switch surface {
            case .offer: return 0.08
            case .capability: return 0.10
            case .affinity: return 0.04
            case .mixed: return 0.10
            case .unknown: return 0.0
            }
        }
    }

    func rankedOrdering(
        lhs: DiscoveryCandidate,
        rhs: DiscoveryCandidate
    ) -> Bool {
        discoveryCandidateOrdering(
            lhs: lhs,
            rhs: rhs,
            commercialObjectOfferSearch: false
        )
    }

    func discoveryCandidateOrdering(
        lhs: DiscoveryCandidate,
        rhs: DiscoveryCandidate,
        commercialObjectOfferSearch: Bool
    ) -> Bool {
        if commercialObjectOfferSearch {
            let lhsProven = !lhs.provenObjectOfferIDs.isEmpty
            let rhsProven = !rhs.provenObjectOfferIDs.isEmpty
            if lhsProven != rhsProven {
                return lhsProven && !rhsProven
            }

            if lhsProven && rhsProven {
                let lhsObject = maxQualifyingObjectEvidenceScore(for: lhs)
                let rhsObject = maxQualifyingObjectEvidenceScore(for: rhs)
                if lhsObject != rhsObject {
                    return lhsObject > rhsObject
                }
            }
        }

        if lhs.posture.bucket != rhs.posture.bucket {
            return lhs.posture.bucket.rawValue > rhs.posture.bucket.rawValue
        }

        if lhs.coarse.isRetrievable != rhs.coarse.isRetrievable {
            return lhs.coarse.isRetrievable && !rhs.coarse.isRetrievable
        }

        if lhs.overallScore != rhs.overallScore {
            return lhs.overallScore > rhs.overallScore
        }

        if lhs.coarse.explicitTokenOverlap != rhs.coarse.explicitTokenOverlap {
            return lhs.coarse.explicitTokenOverlap > rhs.coarse.explicitTokenOverlap
        }

        let lhsPrimarySurfaceOverlap = max(lhs.coarse.offerOverlap, max(lhs.coarse.capabilityOverlap, lhs.coarse.affinityOverlap))
        let rhsPrimarySurfaceOverlap = max(rhs.coarse.offerOverlap, max(rhs.coarse.capabilityOverlap, rhs.coarse.affinityOverlap))
        if lhsPrimarySurfaceOverlap != rhsPrimarySurfaceOverlap {
            return lhsPrimarySurfaceOverlap > rhsPrimarySurfaceOverlap
        }

        if lhs.coarse.queryTokenOverlap != rhs.coarse.queryTokenOverlap {
            return lhs.coarse.queryTokenOverlap > rhs.coarse.queryTokenOverlap
        }

        if lhs.counterparty.updatedAt != rhs.counterparty.updatedAt {
            return lhs.counterparty.updatedAt > rhs.counterparty.updatedAt
        }

        return lhs.counterparty.id < rhs.counterparty.id
    }

    func classify(
        candidates: [DiscoveryCandidate],
        thread: ExchangeThread,
        searchPlan: SearchPlan,
        sourceSummary: String,
        limit: Int
    ) -> DiscoveryResult {
        exDiscoveryEngineLog(
            "classify start candidates=\(candidates.count) sourceSummary=\(sourceSummary) limit=\(limit)"
        )

        guard !candidates.isEmpty else {
            return .none(
                .init(
                    summary: buildNoneSummary(for: thread, plan: searchPlan),
                    recommendation: buildNoneRecommendation(for: thread, plan: searchPlan),
                    sourceSummary: sourceSummary,
                    searchPlan: searchPlan
                )
            )
        }

        let shortlisted = Array(candidates.prefix(limit))

        let contactable = shortlisted.filter { $0.posture.bucket == .contactable }
        let introRequired = shortlisted.filter { $0.posture.bucket == .introRequired }
        let blocked = shortlisted.filter { $0.posture.bucket == .visibleButBlocked }
        let weakOpenness = shortlisted.filter {
            $0.posture.bucket == .visibleButWeak || $0.posture.bucket == .unusable
        }

        exDiscoveryEngineLog(
            "classify buckets " +
            "shortlisted=\(shortlisted.count) " +
            "contactable=\(contactable.count) " +
            "introRequired=\(introRequired.count) " +
            "blocked=\(blocked.count) " +
            "weak=\(weakOpenness.count)"
        )

        if !contactable.isEmpty {
            return .found(
                .init(
                    candidates: contactable,
                    summary: buildFoundSummary(from: contactable, plan: searchPlan),
                    sourceSummary: sourceSummary,
                    searchPlan: searchPlan
                )
            )
        }

        if !introRequired.isEmpty {
            return .weak(
                .init(
                    candidates: introRequired,
                    summary: "I found relevant public surfaces, but the best paths require an introduction or trusted route.",
                    recommendation: "Review the shortlist and decide whether to pursue an introduction path.",
                    sourceSummary: sourceSummary,
                    searchPlan: searchPlan
                )
            )
        }

        if !blocked.isEmpty {
            return .weak(
                .init(
                    candidates: blocked,
                    summary: "I found relevant public surfaces, but they are not currently contactable under their public posture.",
                    recommendation: "Review the shortlist, widen the search, or choose a different path.",
                    sourceSummary: sourceSummary,
                    searchPlan: searchPlan
                )
            )
        }

        return .weak(
            .init(
                candidates: shortlisted,
                summary: "I found relevant public surfaces, but the current paths are still weak and need deeper fit review.",
                recommendation: "Review the shortlist, refine the request, or widen the search.",
                sourceSummary: sourceSummary,
                searchPlan: searchPlan
            )
        )
    }

    func isTargetKindCompatible(
        counterparty: ExchangeCounterparty,
        matchedOffers: [ExchangeOffer],
        plan: SearchPlan,
        offerOverlap: Int = 0,
        capabilityOverlap: Int = 0,
        affinityOverlap: Int = 0,
        queryTokenOverlap: Int = 0
    ) -> Bool {
        guard let targetKind = plan.targetKind, targetKind != .unknown else {
            return true
        }

        let offerText = matchedOffers
            .map { offer in
                [
                    offer.title,
                    offer.summary,
                    offer.category,
                    offer.tags.joined(separator: " "),
                    offer.semantic.domains.joined(separator: " "),
                    offer.semantic.serviceKinds.joined(separator: " "),
                    offer.semantic.notes
                ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            }
            .joined(separator: " ")

        let primaryCompatible: Bool
        switch targetKind {
        case .secretaryNode:
            primaryCompatible = counterparty.kind == .secretaryNode

        case .group:
            primaryCompatible = counterparty.kind == .group ||
                publicOpportunityText(counterparty).contains(anyOf: ["group", "community", "club", "team"]) ||
                offerText.contains(anyOf: ["group", "community", "club", "team"])

        case .business, .organization:
            primaryCompatible = counterparty.kind == .business ||
                counterparty.kind == .organization ||
                !matchedOffers.isEmpty

        case .person:
            primaryCompatible = counterparty.kind == .person ||
                entityText(counterparty).contains(anyOf: ["person", "individual", "member"])

        case .provider:
            primaryCompatible = isTargetKindCompatiblePrimary(
                counterparty: counterparty,
                matchedOffers: matchedOffers,
                targetKind: .provider
            )

        case .unknown:
            return true
        }

        if primaryCompatible {
            if matchedOffers.isEmpty &&
                !hasProfileSemanticOverlap(
                    CoarseSignal(
                        queryTokenOverlap: queryTokenOverlap,
                        explicitTokenOverlap: 0,
                        regionOverlap: 0,
                        offerOverlap: offerOverlap,
                        capabilityOverlap: capabilityOverlap,
                        affinityOverlap: affinityOverlap,
                        hasPublicProfile: counterparty.publicProfile != nil,
                        hasOffers: !matchedOffers.isEmpty,
                        kindCompatible: true,
                        placeCompatible: true,
                        trustHintScore: 0,
                        retrievalScore: 0,
                        rationale: ""
                    )
                ) &&
                !isStructuralProviderKindMatch(counterparty: counterparty) {
                return profileCompatibleDiscoveryFallback(
                    plan: plan,
                    targetKind: targetKind,
                    offerOverlap: offerOverlap,
                    capabilityOverlap: capabilityOverlap,
                    affinityOverlap: affinityOverlap,
                    queryTokenOverlap: queryTokenOverlap
                )
            }
            return true
        }

        return profileCompatibleDiscoveryFallback(
            plan: plan,
            targetKind: targetKind,
            offerOverlap: offerOverlap,
            capabilityOverlap: capabilityOverlap,
            affinityOverlap: affinityOverlap,
            queryTokenOverlap: queryTokenOverlap
        )
    }

    func profileCompatibleDiscoveryFallback(
        plan: SearchPlan,
        targetKind: ExchangeIntentFacets.TargetKind,
        offerOverlap: Int,
        capabilityOverlap: Int,
        affinityOverlap: Int,
        queryTokenOverlap: Int
    ) -> Bool {
        guard hasProfileSemanticOverlap(
            CoarseSignal(
                queryTokenOverlap: queryTokenOverlap,
                explicitTokenOverlap: 0,
                regionOverlap: 0,
                offerOverlap: offerOverlap,
                capabilityOverlap: capabilityOverlap,
                affinityOverlap: affinityOverlap,
                hasPublicProfile: true,
                hasOffers: false,
                kindCompatible: false,
                placeCompatible: true,
                trustHintScore: 0,
                retrievalScore: 0,
                rationale: ""
            )
        ) else {
            return false
        }

        func capabilityAlignedEvidence() -> Bool {
            capabilityOverlap > 0
        }

        func affinityAlignedEvidence() -> Bool {
            affinityOverlap > 0
        }

        switch plan.queryIntentClass {
        case .providerSearch:
            guard targetKind == .provider || targetKind == .person else { return false }
            return capabilityAlignedEvidence()

        case .offerSearch:
            guard targetKind == .provider || targetKind == .business || targetKind == .organization else {
                return false
            }
            return offerOverlap == 0 && capabilityOverlap > 0

        case .socialAffinitySearch, .relationshipSearch:
            return affinityAlignedEvidence()

        case .capabilitySearch, .collaborationSearch:
            return capabilityOverlap > 0

        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return false
        }
    }

    func isStructuralProviderKindMatch(counterparty: ExchangeCounterparty) -> Bool {
        counterparty.kind == .provider ||
            counterparty.kind == .business ||
            counterparty.kind == .organization
    }

    func isTargetKindCompatiblePrimary(
        counterparty: ExchangeCounterparty,
        matchedOffers: [ExchangeOffer],
        targetKind: ExchangeIntentFacets.TargetKind
    ) -> Bool {
        let offerText = matchedOffers
            .map { offer in
                [
                    offer.title,
                    offer.summary,
                    offer.category,
                    offer.tags.joined(separator: " "),
                    offer.semantic.domains.joined(separator: " "),
                    offer.semantic.serviceKinds.joined(separator: " "),
                    offer.semantic.notes
                ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            }
            .joined(separator: " ")

        switch targetKind {
        case .secretaryNode:
            return counterparty.kind == .secretaryNode

        case .group:
            return counterparty.kind == .group ||
                publicOpportunityText(counterparty).contains(anyOf: ["group", "community", "club", "team"]) ||
                offerText.contains(anyOf: ["group", "community", "club", "team"])

        case .business, .organization:
            return counterparty.kind == .business ||
                counterparty.kind == .organization ||
                !matchedOffers.isEmpty

        case .person:
            return counterparty.kind == .person ||
                entityText(counterparty).contains(anyOf: ["person", "individual", "member"])

        case .provider:
            if counterparty.kind == .provider ||
                counterparty.kind == .business ||
                counterparty.kind == .organization {
                return true
            }
            if !matchedOffers.isEmpty {
                return true
            }
            return publicOpportunityText(counterparty).contains(
                anyOf: ["service", "provider", "vendor", "contractor", "facility", "studio", "gym", "club", "business"]
            )

        case .unknown:
            return true
        }
    }

    func hasProfileSemanticOverlap(_ coarse: CoarseSignal) -> Bool {
        coarse.queryTokenOverlap > 0 ||
            coarse.capabilityOverlap > 0 ||
            coarse.affinityOverlap > 0 ||
            coarse.offerOverlap > 0
    }

    func profileCompatibleDiscoveryFallbackAccepted(
        counterparty: ExchangeCounterparty,
        matchedOffers: [ExchangeOffer],
        plan: SearchPlan,
        coarse: CoarseSignal
    ) -> Bool {
        guard coarse.kindCompatible else { return false }
        guard let targetKind = plan.targetKind, targetKind != .unknown else { return false }
        guard !isTargetKindCompatiblePrimary(
            counterparty: counterparty,
            matchedOffers: matchedOffers,
            targetKind: targetKind
        ) else {
            return false
        }

        return profileCompatibleDiscoveryFallback(
            plan: plan,
            targetKind: targetKind,
            offerOverlap: coarse.offerOverlap,
            capabilityOverlap: coarse.capabilityOverlap,
            affinityOverlap: coarse.affinityOverlap,
            queryTokenOverlap: coarse.queryTokenOverlap
        )
    }

    func logProfileCompatibilityDecision(
        nodeID: String,
        reason: String,
        plan: SearchPlan,
        dominantSurface: DiscoveryCandidate.SurfaceType,
        coarse: CoarseSignal,
        matchedOfferCount: Int
    ) {
        exDiscoveryEngineLog(
            "rerankProjectedCandidates \(reason) " +
            "nodeID=\(nodeID) " +
            "queryClass=\(plan.queryIntentClass.rawValue) " +
            "surfacePreference=\(plan.surfacePreference.rawValue) " +
            "targetKind=\(plan.targetKind?.rawValue ?? "nil") " +
            "surfaceType=\(dominantSurface.rawValue) " +
            "offerOverlap=\(coarse.offerOverlap) " +
            "capabilityOverlap=\(coarse.capabilityOverlap) " +
            "affinityOverlap=\(coarse.affinityOverlap) " +
            "queryTokenOverlap=\(coarse.queryTokenOverlap) " +
            "matchedOffers=\(matchedOfferCount)"
        )
    }

    func isPlaceCompatible(
        counterparty: ExchangeCounterparty,
        plan: SearchPlan,
        matchedOffers: [ExchangeOffer] = []
    ) -> Bool {
        if let requirement = plan.locationRequirement, requirement.kind != .none {
            let areas = matchedOffers.flatMap(\.effectiveServiceAreas)
            let match = ExchangeServiceAreaMatcher.match(
                requirement: requirement,
                serviceAreas: areas,
                fulfillmentRemoteFriendly: matchedOffers.contains(where: \.fulfillment.remoteFriendly)
            )
            if requirement.strictness == .required {
                return match.isCompatible && !match.isHardMismatch
            }
            if match.tier != .none {
                return true
            }
            if requirement.kind == .remote {
                return match.isCompatible
            }
        }

        let requiresLocal =
            plan.fulfillmentMode == .localOnly ||
            (plan.explicitRegionRequired && !plan.regionTerms.isEmpty) ||
            plan.placeName != nil ||
            plan.locationText != nil

        if !requiresLocal {
            return true
        }

        let locationText = counterparty.location?.summaryLine.lowercased() ?? ""
        let profileRegions = counterparty.publicProfile?.regionTags.joined(separator: " ") ?? ""
        let publicText = publicOpportunityText(counterparty)

        var haystackParts: [String] = [locationText, profileRegions, publicText]
        for offer in matchedOffers {
            haystackParts.append(offer.regionTags.joined(separator: " "))
            haystackParts.append(offer.regionAliases.joined(separator: " "))
            if let summary = offer.summary { haystackParts.append(summary.lowercased()) }
            if let category = offer.category { haystackParts.append(category.lowercased()) }
            haystackParts.append(offer.title.lowercased())
        }

        let haystack = haystackParts
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !haystack.isEmpty else {
            return !plan.explicitRegionRequired && plan.fulfillmentMode != .localOnly
        }

        let desiredTokens = Set(
            tokenize(plan.placeName ?? "") +
            tokenize(plan.locationText ?? "") +
            tokenize(plan.regionTerms.joined(separator: " "))
        )

        if desiredTokens.isEmpty {
            return true
        }

        let candidateTokens = Set(tokenize(haystack))
        let hasIntersection = !desiredTokens.intersection(candidateTokens).isEmpty

        if hasIntersection {
            return true
        }

        return !plan.explicitRegionRequired && plan.fulfillmentMode != .localOnly
    }

    func publicOpportunityText(_ counterparty: ExchangeCounterparty) -> String {
        if let profile = counterparty.publicProfile {
            return [
                profile.displayName,
                profile.headline,
                profile.summary,
                profile.interests.joined(separator: " "),
                profile.offers.joined(separator: " "),
                profile.openTo.joined(separator: " "),
                profile.activityTags.joined(separator: " "),
                profile.regionTags.joined(separator: " "),
                profile.semantic.searchableTerms.joined(separator: " "),
                profile.semantic.notes,
                profile.approach.note,
                counterparty.location?.summaryLine
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        }

        return entityText(counterparty)
    }

    func entityText(_ counterparty: ExchangeCounterparty) -> String {
        [
            counterparty.displayName,
            counterparty.handle,
            counterparty.bio,
            counterparty.location?.summaryLine,
            counterparty.tags.joined(separator: " "),
            counterparty.capabilities.map(\.label).joined(separator: " "),
            counterparty.capabilities.compactMap(\.category).joined(separator: " "),
            counterparty.capabilities.compactMap(\.notes).joined(separator: " "),
            counterparty.semantic.searchableTerms.joined(separator: " "),
            counterparty.semantic.notes
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    func buildFoundSummary(
        from candidates: [DiscoveryCandidate],
        plan: SearchPlan
    ) -> String {
        guard let first = candidates.first else {
            return "I found relevant public surfaces."
        }

        switch plan.queryIntentClass {
        case .providerSearch, .offerSearch:
            if first.dominantSurface == .offer {
                return "I found relevant provider-facing public surfaces worth deeper fit review."
            }
            return "I found relevant public surfaces for the provider search."

        case .socialAffinitySearch, .relationshipSearch:
            if first.dominantSurface == .affinity {
                return "I found relevant social and affinity-oriented public surfaces worth deeper fit review."
            }
            return "I found relevant public surfaces for the affinity search."

        case .capabilitySearch, .collaborationSearch:
            if first.dominantSurface == .capability {
                return "I found relevant capability-oriented public surfaces worth deeper fit review."
            }
            return "I found relevant collaboration-oriented public surfaces."

        case .directOutreach, .followUp, .statusCheck, .generalDiscovery:
            return "I found relevant public surfaces worth deeper fit review."
        }
    }

    func buildNoneSummary(
        for thread: ExchangeThread,
        plan: SearchPlan
    ) -> String {
        if let target = plan.targetDescription, !target.isEmpty {
            return "I understood the request, but I could not find public surfaces for “\(target)”."
        }
        return "I understood the request, but I could not find relevant public surfaces yet."
    }

    func buildSemanticNoneSummary(
        for thread: ExchangeThread,
        plan: SearchPlan
    ) -> String {
        if let target = plan.targetDescription, !target.isEmpty {
            return "I found public records, but none looked aligned enough with “\(target)”."
        }
        return "I found public records, but none looked aligned enough to shortlist."
    }

    func buildNoneRecommendation(
        for thread: ExchangeThread,
        plan: SearchPlan
    ) -> String {
        if thread.posture.openness == .selective {
            return "Refine the request or widen the criteria only if you want broader discovery."
        }

        if let place = plan.placeName {
            return "Try widening the search beyond \(place), or relax the locality requirement."
        }

        return "Refine the search terms, widen the scope, or wait for better public surfaces."
    }

    func buildSemanticNoneRecommendation(
        for thread: ExchangeThread,
        plan: SearchPlan
    ) -> String {
        if plan.fulfillmentMode == .localOnly || plan.fulfillmentMode == .localPreferred {
            return "Try widening the place constraint or broadening the description of what you want."
        }

        if let targetKind = plan.targetKind, targetKind == .person {
            return "Try describing the person, activity, place, or timing more specifically before advancing discovery."
        }

        return "Refine the target description, place, or timing before advancing discovery."
    }

    func sourceDescription(_ source: ExchangeDirectorySearchResponse.Source) -> String {
        switch source {
        case .local:
            return "Local directory search"
        case .remote:
            return "Remote directory search"
        case .hybrid:
            return "Hybrid directory search"
        }
    }

    func directoryRouteRequirement(
        for plan: SearchPlan
    ) -> ExchangeDirectorySearchRequest.RouteRequirement {
        switch plan.surfaceRequirement {
        case .anyVisibleSurface:
            return .any
        case .contactableIfPossible, .introCapable:
            return .routeableOnly
        }
    }
    
    func directoryAccessRequirement(
        for plan: SearchPlan
    ) -> ExchangeDirectorySearchRequest.AccessRequirement {
        switch plan.surfaceRequirement {
        case .anyVisibleSurface:
            return .discoverableOnly

        case .contactableIfPossible:
            return .routeableOnly

        case .introCapable:
            return .introductionRequiredOnly
        }
    }

    func directoryDisclosureRequirement(
        for thread: ExchangeThread
    ) -> ExchangeDirectorySearchRequest.DisclosureRequirement {
        switch thread.posture.privacy {
        case .guarded:
            return .minimalOrLower

        default:
            return .any
        }
    }

    func threadHasTrustedIntroduction(_ thread: ExchangeThread) -> Bool {
        if let selectedPath = thread.selectedPath,
           selectedPath.accessMode == .introOnly && selectedPath.status == .selected {
            return true
        }

        if let mode = thread.metadata["contact_mode"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           mode == "introduced" || mode == "trusted_path" {
            return true
        }

        if let trustedPathID = thread.metadata["trusted_path_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !trustedPathID.isEmpty {
            return true
        }

        return false
    }

    func trustRank(_ level: ExchangeCounterparty.TrustSnapshot.Level) -> Int {
        switch level {
        case .unverified: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        }
    }

    func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && !$0.isStopWord && !$0.isDiscoveryActionWord }
    }
}

public enum ExchangeDiscoveryEngineError: Error, Sendable, Hashable {
    case noDiscoverySourceConfigured
}

private extension String {
    var normalizedLooseEnum: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    var exchangeNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isStopWord: Bool {
        [
            "the", "a", "an", "for", "to", "with", "and", "or", "of", "in", "on",
            "my", "me", "someone", "somebody", "person", "people", "company",
            "help", "need", "want", "looking", "look", "good", "best", "top"
        ].contains(self)
    }

    var isDiscoveryActionWord: Bool {
        [
            "find", "search", "source", "locate", "draft", "drafted", "outreach",
            "message", "messages", "email", "emails", "contact", "contacting",
            "send", "sending", "reach", "reaching", "prepare", "prepared", "show"
        ].contains(self)
    }

    func contains(anyOf values: [String]) -> Bool {
        values.contains { contains($0) }
    }
}

extension ExchangeDiscoveryEngine {
    func rerankProjectedCandidatesForTests(
        _ projected: [DiscoveryCandidate],
        thread: ExchangeThread,
        plan: SearchPlan,
        shortlistLimit: Int
    ) -> [DiscoveryCandidate] {
        rerankProjectedCandidates(
            projected,
            thread: thread,
            plan: plan,
            localNodeID: nil,
            shortlistLimit: shortlistLimit
        )
    }

    func evaluateTargetKindCompatibilityForTests(
        counterparty: ExchangeCounterparty,
        matchedOffers: [ExchangeOffer],
        plan: SearchPlan,
        offerOverlap: Int,
        capabilityOverlap: Int,
        affinityOverlap: Int,
        queryTokenOverlap: Int
    ) -> Bool {
        isTargetKindCompatible(
            counterparty: counterparty,
            matchedOffers: matchedOffers,
            plan: plan,
            offerOverlap: offerOverlap,
            capabilityOverlap: capabilityOverlap,
            affinityOverlap: affinityOverlap,
            queryTokenOverlap: queryTokenOverlap
        )
    }
}
