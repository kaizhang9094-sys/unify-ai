import Foundation

/// Builds a compact retrieval query from canonical intent + facets.
///
/// Design rule:
/// - this builder is not an interpreter
/// - it should preserve raw user meaning strongly
/// - it should preserve literal constraints strongly
/// - it should use canonical intent/facets as soft routing bias
/// - it should avoid inventing large handcrafted term families
///
/// In the target architecture, semantic lane selection should come from:
/// - structural state
/// - interpretation prior / canonical intent
/// - not from this builder re-guessing the request again
public struct ExchangeRetrievalQueryBuilder: Sendable {
    private let entityExtractor: ExchangeQueryEntityExtractor
    private let placeResolver: ExchangeLocalPlaceResolver

    public init(
        entityExtractor: ExchangeQueryEntityExtractor = ExchangeQueryEntityExtractor(),
        placeResolver: ExchangeLocalPlaceResolver = ExchangeLocalPlaceResolver()
    ) {
        self.entityExtractor = entityExtractor
        self.placeResolver = placeResolver
    }

    public func build(from thread: ExchangeThread) -> ExchangeRetrievalQuery {
        if let facets = thread.facets, let si = facets.searchIntent {
            return buildFromCanonicalSearchIntent(thread: thread, facets: facets, searchIntent: si)
        }

        return buildLegacy(from: thread)
    }

    private func buildLegacy(from thread: ExchangeThread) -> ExchangeRetrievalQuery {
        let interpretation = thread.interpretation
        let facets = thread.facets
        let intent = thread.intent

        let queryText = buildQueryText(
            thread: thread,
            interpretation: interpretation,
            facets: facets
        )

        let semanticText = buildSemanticText(
            thread: thread,
            interpretation: interpretation,
            queryText: queryText
        )
        let semanticEmbeddingText = semanticText

        let queryIntentClass = resolvedQueryIntentClass(
            facets: facets,
            intent: intent
        )
        let surfacePreference = resolvedSurfacePreference(
            facets: facets,
            intent: intent
        )

        let providerTerms = buildProviderTerms(
            intent: intent,
            interpretation: interpretation,
            facets: facets
        )

        let capabilityTerms = buildCapabilityTerms(
            intent: intent,
            interpretation: interpretation,
            facets: facets
        )

        let affinityTerms = buildAffinityTerms(
            intent: intent,
            interpretation: interpretation,
            facets: facets
        )

        // Raw facet/interpreter location strings are soft evidence only; never populate
        // `regionTerms` for lexical retrieval (BM25 uses `softRegionTerms` + typed fields).
        let regionTerms: [String] = []
        let queryEntities = buildQueryEntities(
            queryText: queryText,
            intent: intent,
            facets: facets
        )
        let resolvedPlaces = buildResolvedPlaces(
            from: queryEntities,
            facets: facets
        )
        let hardRegionIDs = buildHardRegionIDs(from: resolvedPlaces)
        let softRegionTerms = buildSoftRegionTerms(
            thread: thread,
            facets: facets,
            intent: intent,
            resolvedPlaces: resolvedPlaces,
            queryEntities: queryEntities
        )
        let commercialIntentTerms = buildCommercialIntentTerms(from: queryEntities)
        let timeTerms = buildTimeTerms(from: queryEntities)

        let keywords = buildKeywords(
            intent: intent,
            interpretation: interpretation,
            facets: facets,
            queryText: queryText,
            queryEntities: queryEntities
        )

        let explicitHardConstraints = buildExplicitHardConstraints(
            thread: thread,
            facets: facets
        )

        var explicitRegionRequired = !hardRegionIDs.isEmpty
        var resolvedHardRegionIDs = hardRegionIDs
        var resolvedSoftRegionTerms = softRegionTerms

        if let locationRequirement = facets?.locationRequirement
            ?? facets.flatMap({ ExchangeLocationRequirementMapping.buildFromFacets($0) }) {
            resolvedSoftRegionTerms = normalizeTerms(
                resolvedSoftRegionTerms + locationRequirement.lexicalSearchTerms,
                maxCount: 32
            )
            if locationRequirement.strictness == .required {
                explicitRegionRequired = true
                resolvedHardRegionIDs = []
            }
        }

        if ExchangeNearMeLexicalSanitizer.shouldStripNearMeLexicals(facets) {
            resolvedSoftRegionTerms = normalizeTerms(
                ExchangeNearMeLexicalSanitizer.filterTerms(resolvedSoftRegionTerms),
                maxCount: 32
            )
        }

        var resolvedProviderTerms = providerTerms
        var resolvedCapabilityTerms = capabilityTerms
        var resolvedAffinityTerms = affinityTerms
        var resolvedKeywords = keywords
        applyNearMeLexicalGuard(
            providerTerms: &resolvedProviderTerms,
            capabilityTerms: &resolvedCapabilityTerms,
            affinityTerms: &resolvedAffinityTerms,
            keywords: &resolvedKeywords,
            facets: facets
        )

        let explicitFulfillmentRequired = inferExplicitFulfillmentRequired(
            thread: thread,
            facets: facets
        )

        let visibilityAllowList = visibilityAllowList(for: thread)
        let availabilityAllowList = availabilityAllowList(for: thread)
        let reachabilityRequirement = reachabilityRequirement(for: thread)

        let targetKind = facets?.targetKind.rawValue
        let fulfillmentMode = facets?.fulfillmentMode.rawValue
        let anchorSource = facets?.requesterSpatialAnchor?.source.rawValue ?? "nil"
        let anchorResolved = facets?.requesterSpatialAnchor?.hasResolvedSpatial == true

        exRetrievalQueryBuilderLog(
            "build " +
            "threadID=\(thread.id.uuidString) " +
            "intent=\(intent.kind.rawValue) " +
            "mode=\(thread.mode.rawValue) " +
            "queryIntentClass=\(queryIntentClass.rawValue) " +
            "surfacePreference=\(surfacePreference.rawValue) " +
            "queryText=\(queryText ?? "nil") " +
            "semanticText=\(semanticText ?? "nil") " +
            "requesterSpatialAnchor.source=\(anchorSource) resolved=\(anchorResolved) " +
            "providerTerms=\(resolvedProviderTerms) " +
            "capabilityTerms=\(resolvedCapabilityTerms) " +
            "affinityTerms=\(resolvedAffinityTerms) " +
            "regionTerms=\(regionTerms) " +
            "hardRegionIDs=\(resolvedHardRegionIDs) " +
            "softRegionTerms=\(resolvedSoftRegionTerms) " +
            "commercialIntentTerms=\(commercialIntentTerms) " +
            "timeTerms=\(timeTerms) " +
            "keywords=\(resolvedKeywords) " +
            "explicitHardConstraints=\(explicitHardConstraints.map { "\($0.key)=\($0.value)" }) " +
            "explicitRegionRequired=\(explicitRegionRequired) " +
            "explicitFulfillmentRequired=\(explicitFulfillmentRequired) " +
            "reachabilityRequirement=\(reachabilityRequirement.rawValue)"
        )

        let allowedSurfaceTypes = ExchangeRetrievalQuery.derivedLaneAllowedSurfaceTypes(
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference
        )

        return ExchangeRetrievalQuery(
            queryText: queryText,
            semanticText: semanticText,
            semanticEmbeddingText: semanticEmbeddingText,
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference,
            allowedSurfaceTypes: allowedSurfaceTypes,
            providerTerms: resolvedProviderTerms,
            capabilityTerms: resolvedCapabilityTerms,
            affinityTerms: resolvedAffinityTerms,
            regionTerms: regionTerms,
            queryEntities: queryEntities,
            resolvedPlaces: resolvedPlaces,
            hardRegionIDs: resolvedHardRegionIDs,
            softRegionTerms: resolvedSoftRegionTerms,
            requesterSpatialAnchor: facets?.requesterSpatialAnchor,
            commercialIntentTerms: commercialIntentTerms,
            timeTerms: timeTerms,
            keywords: resolvedKeywords,
            explicitHardConstraints: explicitHardConstraints,
            explicitRegionRequired: explicitRegionRequired,
            explicitFulfillmentRequired: explicitFulfillmentRequired,
            targetKind: targetKind,
            fulfillmentMode: fulfillmentMode,
            reachabilityRequirement: reachabilityRequirement,
            visibilityAllowList: visibilityAllowList,
            availabilityAllowList: availabilityAllowList,
            limit: 24
        )
    }

    /// Phase 4: structured canonical search intent drives retrieval payloads (no lexical sentence rails).
    private func buildFromCanonicalSearchIntent(
        thread: ExchangeThread,
        facets: ExchangeIntentFacets,
        searchIntent si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> ExchangeRetrievalQuery {
        let intent = thread.intent
        let queryIntentClass = resolvedQueryIntentClass(facets: facets, intent: intent)
        let surfacePreference = resolvedSurfacePreference(facets: facets, intent: intent)

        let regionTerms: [String] = []

        let resolvedPlacesFromCanonical = buildCanonicalResolvedPlaces(from: si)
        let canonicalEntities = buildCanonicalQueryEntities(from: si)

        let queryText = canonicalBroadQuerySentence(
            si: si,
            queryIntentClass: queryIntentClass
        )
        let semanticText = canonicalSemanticText(
            si: si,
            queryText: queryText
        )
        let semanticEmbeddingText = canonicalSemanticEmbeddingText(si: si)

        let lexicalAtoms = canonicalLexicalAtoms(si: si, queryIntentClass: queryIntentClass)
        let (providerTerms, capabilityTerms, affinityTerms) =
            canonicalRoutedLexicalRails(
                si: si,
                facets: facets,
                intent: intent,
                lexicalAtoms: lexicalAtoms
            )

        let keywords = lexicalAtoms.isEmpty ? [] : normalizeTerms(lexicalAtoms, maxCount: 16)

        let queryEntities = dedupeEntities(canonicalEntities)
        let resolvedPlaces = mergedResolvedPlaces(
            canonicalPlaces: resolvedPlacesFromCanonical,
            facetPlaces: facets.resolvedPlaces
        )

        let authorizesHardRegionGate = si.extractionSource != .heuristicFallback

        let hardRegionIDs: [String]
        let softRegionTerms: [String]
        let baseSoft = buildCanonicalSoftRegionTerms(si: si, resolvedPlaces: resolvedPlaces)
        if authorizesHardRegionGate {
            hardRegionIDs = buildHardRegionIDs(from: resolvedPlaces)
            softRegionTerms = baseSoft
        } else {
            hardRegionIDs = []
            let fusedSoftHints = resolvedPlaces.flatMap { place in
                [place.normalizedText] + place.aliases + [place.canonicalID]
            }
            softRegionTerms = normalizeTerms(baseSoft + fusedSoftHints, maxCount: 32)
                .filter { !$0.isEmpty && !Self.isClauseJoinedFragment($0) }
        }

        let commercialIntentTerms = normalizeTerms(canonicalCommercialPhrases(si: si, hardOnly: false), maxCount: 12)
        let timeTerms = normalizeTerms(
            si.timeConstraints.map(\.text),
            maxCount: 12
        )

        let explicitHardConstraints = canonicalExplicitHardConstraints(
            si: si,
            facets: facets
        )

        var explicitRegionRequired =
            authorizesHardRegionGate &&
            (!hardRegionIDs.isEmpty || si.places.contains(where: { $0.isHard }))
        var resolvedHardRegionIDs = hardRegionIDs
        var resolvedSoftRegionTerms = softRegionTerms

        if let locationRequirement = facets.locationRequirement
            ?? ExchangeLocationRequirementMapping.buildFromFacets(facets) {
            resolvedSoftRegionTerms = normalizeTerms(
                resolvedSoftRegionTerms + locationRequirement.lexicalSearchTerms,
                maxCount: 32
            )
            switch locationRequirement.strictness {
            case .required:
                explicitRegionRequired = true
                resolvedHardRegionIDs = []
            case .preferred:
                if locationRequirement.hasNamedPlace {
                    explicitRegionRequired = false
                }
            case .requiresClarification, .notLocal, .unspecified:
                break
            }
        }

        if ExchangeNearMeLexicalSanitizer.shouldStripNearMeLexicals(facets) {
            resolvedSoftRegionTerms = normalizeTerms(
                ExchangeNearMeLexicalSanitizer.filterTerms(resolvedSoftRegionTerms),
                maxCount: 32
            )
        }

        var resolvedProviderTerms = providerTerms
        var resolvedCapabilityTerms = capabilityTerms
        var resolvedAffinityTerms = affinityTerms
        var resolvedKeywords = keywords
        applyNearMeLexicalGuard(
            providerTerms: &resolvedProviderTerms,
            capabilityTerms: &resolvedCapabilityTerms,
            affinityTerms: &resolvedAffinityTerms,
            keywords: &resolvedKeywords,
            facets: facets
        )

        let explicitFulfillmentRequired = inferExplicitFulfillmentRequired(
            thread: thread,
            facets: facets
        )

        let visibilityAllowList = visibilityAllowList(for: thread)
        let availabilityAllowList = availabilityAllowList(for: thread)
        let reachabilityRequirement = reachabilityRequirement(for: thread)

        let targetKind = facets.targetKind.rawValue
        let fulfillmentMode = facets.fulfillmentMode.rawValue
        let anchorSource = facets.requesterSpatialAnchor?.source.rawValue ?? "nil"
        let anchorResolved = facets.requesterSpatialAnchor?.hasResolvedSpatial == true

        exRetrievalQueryBuilderLog(
            "build canonical " +
            "threadID=\(thread.id.uuidString) " +
            "queryIntentClass=\(queryIntentClass.rawValue) " +
            "surfacePreference=\(surfacePreference.rawValue) " +
            "queryText=\(queryText ?? "nil") " +
            "semanticText=\(semanticText ?? "nil") " +
            "requesterSpatialAnchor.source=\(anchorSource) resolved=\(anchorResolved) " +
            "providerTerms=\(resolvedProviderTerms) " +
            "capabilityTerms=\(resolvedCapabilityTerms) " +
            "affinityTerms=\(resolvedAffinityTerms) " +
            "softRegionTerms=\(resolvedSoftRegionTerms) " +
            "commercialIntentTerms=\(commercialIntentTerms) " +
            "timeTerms=\(timeTerms) " +
            "keywords=\(resolvedKeywords) " +
            "explicitHardConstraints=\(explicitHardConstraints.map { "\($0.key)=\($0.value)(\($0.isHardConstraint ? "hard" : "soft"))" })"
        )

        let allowedSurfaceTypes = ExchangeRetrievalQuery.derivedLaneAllowedSurfaceTypes(
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference
        )

        return ExchangeRetrievalQuery(
            queryText: queryText,
            semanticText: semanticText,
            semanticEmbeddingText: semanticEmbeddingText,
            queryIntentClass: queryIntentClass,
            surfacePreference: surfacePreference,
            allowedSurfaceTypes: allowedSurfaceTypes,
            providerTerms: resolvedProviderTerms,
            capabilityTerms: resolvedCapabilityTerms,
            affinityTerms: resolvedAffinityTerms,
            regionTerms: regionTerms,
            queryEntities: queryEntities,
            resolvedPlaces: resolvedPlaces,
            hardRegionIDs: resolvedHardRegionIDs,
            softRegionTerms: resolvedSoftRegionTerms,
            requesterSpatialAnchor: facets.requesterSpatialAnchor,
            commercialIntentTerms: commercialIntentTerms,
            timeTerms: timeTerms,
            keywords: resolvedKeywords,
            explicitHardConstraints: explicitHardConstraints,
            explicitRegionRequired: explicitRegionRequired,
            explicitFulfillmentRequired: explicitFulfillmentRequired,
            targetKind: targetKind,
            fulfillmentMode: fulfillmentMode,
            reachabilityRequirement: reachabilityRequirement,
            visibilityAllowList: visibilityAllowList,
            availabilityAllowList: availabilityAllowList,
            limit: 24,
            queryObjectText: ExchangeOfferObjectLane.queryObjectText(thread: thread),
            semanticTarget: thread.facets.map { ExchangeSemanticTarget.from(facets: $0) }
        )
    }
}

#if DEBUG
@inline(__always)
private func exRetrievalQueryBuilderLog(_ message: @autoclosure () -> String) {
    print("[ExchangeRetrievalQueryBuilder] \(message())")
}
#else
@inline(__always)
private func exRetrievalQueryBuilderLog(_ message: @autoclosure () -> String) { }
#endif

private extension ExchangeRetrievalQueryBuilder {
    // MARK: - Canonical routing ownership

    func resolvedQueryIntentClass(
        facets: ExchangeIntentFacets?,
        intent: ExchangeIntent
    ) -> ExchangeIntent.QueryIntentClass {
        if let facets {
            return facets.queryIntentClass
        }
        return intent.queryIntentClass
    }

    func resolvedSurfacePreference(
        facets: ExchangeIntentFacets?,
        intent: ExchangeIntent
    ) -> ExchangeIntent.SurfacePreference {
        if let facets {
            return facets.surfacePreference
        }
        return intent.surfacePreference
    }

    // MARK: - Canonical `searchIntent` retrieval (Phase 4)

    func buildCanonicalResolvedPlaces(
        from si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> [ExchangeResolvedPlace] {
        var output: [ExchangeResolvedPlace] = []
        output.reserveCapacity(si.places.count)

        for place in si.places {
            let raw = place.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }

            let normalizedLower = Self.canonicalNormalizePlaceToken(raw)

            let canonicalShard = Self.stripClauseJoinedTrail(raw).lowercased()
            guard !canonicalShard.isEmpty else { continue }

            let canonicalID = Self.stripClauseJoinedTrail(
                place.canonicalID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? canonicalShard
            )

            let displayName = canonicalID.isEmpty ? normalizedLower : canonicalID

            var aliases = normalizeTerms(place.aliases, maxCount: 12)

            aliases.append(contentsOf: Self.placeAliasExpansions(forCanonicalToken: canonicalShard.lowercased()))
            aliases = normalizeTerms(aliases + [canonicalShard.lowercased()], maxCount: 16)

            let resolved = ExchangeResolvedPlace(
                rawText: raw,
                normalizedText: normalizedLower,
                canonicalName: displayName.lowercased(),
                canonicalID: canonicalID.lowercased(),
                aliases: aliases.filter { !$0.isEmpty },
                confidence: Self.clampUnitIntervalStatic(place.confidence),
                source: .publisherProvided
            )
            output.append(resolved)
        }

        return dedupeResolvedPlaces(output)
    }

    func mergedResolvedPlaces(
        canonicalPlaces: [ExchangeResolvedPlace],
        facetPlaces: [ExchangeResolvedPlace]
    ) -> [ExchangeResolvedPlace] {
        guard !facetPlaces.isEmpty else { return canonicalPlaces }

        var seen = Set(
            canonicalPlaces
                .map { $0.canonicalID.lowercased() }
                .filter { !$0.isEmpty }
        )
        var merged = canonicalPlaces

        for place in facetPlaces {
            let key = place.canonicalID.lowercased()
            guard !key.isEmpty else { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(place)
        }

        return merged
    }

    func dedupeResolvedPlaces(_ values: [ExchangeResolvedPlace]) -> [ExchangeResolvedPlace] {
        var seen = Set<String>()
        var output: [ExchangeResolvedPlace] = []
        for place in values {
            let key = place.canonicalID.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(place)
        }
        return output
    }

    func buildCanonicalQueryEntities(
        from si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> [ExchangeQueryEntity] {
        var entities: [ExchangeQueryEntity] = []

        for place in si.places {
            let text = Self.stripClauseJoinedTrail(place.normalizedText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let clampedConfidence = clampUnitInterval(place.confidence)
            let hardEligible = place.isHard && clampedConfidence >= 0.80

            entities.append(
                ExchangeQueryEntity(
                    kind: .place,
                    rawText: text,
                    confidence: clampedConfidence,
                    provenance: .carriedForward,
                    hardConstraintEligible: hardEligible
                )
            )
        }

        for timing in si.timeConstraints {
            let trimmed = timing.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            entities.append(
                ExchangeQueryEntity(
                    kind: .time,
                    rawText: trimmed,
                    confidence: 0.78,
                    provenance: .carriedForward,
                    hardConstraintEligible: false
                )
            )
        }

        let commercialPieces = normalizeTerms(canonicalCommercialPieces(si: si, hardOnly: false), maxCount: 12)
        for piece in commercialPieces
            where !piece.isEmpty && !Self.isClauseJoinedFragment(piece)
        {
            entities.append(
                ExchangeQueryEntity(
                    kind: .commercialIntent,
                    rawText: piece,
                    confidence: 0.70,
                    provenance: .carriedForward,
                    hardConstraintEligible: false
                )
            )
        }

        return entities
    }

    func canonicalCommercialPhrases(si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent, hardOnly: Bool) -> [String] {
        canonicalCommercialPieces(si: si, hardOnly: hardOnly).filter {
            !$0.isEmpty &&
            !$0.lowercased().contains("seller offers") &&
            !Self.isClauseJoinedFragment($0)
        }
    }

    func canonicalCommercialPieces(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        hardOnly: Bool
    ) -> [String] {
        si.commercialConstraints
            .filter { $0.isHard == hardOnly }
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func canonicalBroadQuerySentence(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        queryIntentClass: ExchangeIntent.QueryIntentClass
    ) -> String? {
        let placeLabels = Self.canonicalDisplayedPlacePhrase(si.places)
        let taskPhrases = ExchangeCanonicalSearchIntentTaskPhrases.topTaskPhrases(from: si)
        let taskClause = ExchangeCanonicalSearchIntentTaskPhrases.taskClauseForBroadQuery(
            phrases: taskPhrases,
            domainCategory: si.domainCategory
        )

        switch si.domainCategory {
        case .realEstate:
            var sentence = "Residential homes and properties"
            if si.transactionIntent == .forSale {
                sentence += " for sale"
            } else if si.transactionIntent == .rent {
                sentence += " for rent"
            }
            if !placeLabels.isEmpty {
                sentence += " in \(placeLabels)"
            }
            sentence += "."
            return sentence

        case .homeService:
            let role = si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "local professional"
            let capitalizedRole = role.prefix(1).uppercased() + role.dropFirst()
            var sentence = "\(capitalizedRole) services"
            sentence += taskClause
            if !placeLabels.isEmpty {
                sentence += " near \(placeLabels)"
            }
            sentence += "."
            return sentence

        case .professionalService:
            let focus = si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "professional expertise"
            var sentence = "Professional expertise related to \(focus)"
            sentence += taskClause
            if !placeLabels.isEmpty {
                sentence += " near \(placeLabels)"
            }
            sentence += "."
            return sentence

        case .product, .general:
            var sentence = "Search for relevant offers and profiles"
            sentence += taskClause
            if !placeLabels.isEmpty {
                sentence += " near \(placeLabels)"
            }
            sentence += "."
            return sentence
        }
    }

    func canonicalSemanticText(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        queryText: String?
    ) -> String? {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(si.canonicalEnglishSearchText) {
            var segments = [english]
            segments.append(contentsOf: si.englishFilteredSemanticConcepts()
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !Self.isClauseJoinedFragment($0) })
            let joined = normalizeWhitespaceList(segments).trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.nilIfBlank
        }

        var segments = canonicalSemanticEmbeddingSegments(si: si)

        if let queryText, !queryText.isEmpty {
            segments.insert(queryText, at: 0)
        }

        let joined = normalizeWhitespaceList(segments).trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.nilIfBlank
    }

    /// Semantic content for vector embedding — excludes generated broad query templates.
    func canonicalSemanticEmbeddingText(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> String? {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(si.canonicalEnglishSearchText) {
            var segments = [english]
            segments.append(contentsOf: si.englishFilteredSemanticConcepts()
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !Self.isClauseJoinedFragment($0) })
            let joined = normalizeWhitespaceList(segments).trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.nilIfBlank
        }

        let segments = canonicalSemanticEmbeddingSegments(si: si)
        guard !segments.isEmpty else { return nil }

        let joined = normalizeWhitespaceList(segments).trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.nilIfBlank
    }

    func canonicalSemanticEmbeddingSegments(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> [String] {
        var segments: [String] = []

        let concepts = si.semanticConcepts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !Self.isClauseJoinedFragment($0) }
        segments.append(contentsOf: concepts)

        for attribute in si.attributes {
            let key = attribute.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = attribute.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            if let numericValue = attribute.numericValue {
                let bedrooms = Int(numericValue.rounded())
                if key.lowercased().contains("bed") {
                    segments.append("\(bedrooms) bedrooms")
                } else {
                    segments.append("\(key): \(bedrooms)")
                }
            } else if !key.isEmpty {
                segments.append("\(key): \(value)")
            } else {
                segments.append(value)
            }
        }

        for preference in si.preferences {
            guard preference.strength != .required else { continue }

            let key = preference.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }

            if let value = preference.value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
                segments.append("\(key): \(value)")
            } else {
                segments.append(key)
            }
        }

        for commercial in si.commercialConstraints where !commercial.isHard {
            let value = commercial.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            segments.append(value)
            if commercial.kind == .financing {
                segments.append(contentsOf: ["vendor take-back", "vtb"])
            }
        }

        for constraint in si.timeConstraints {
            let trimmed = constraint.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            segments.append("timing preference \(trimmed)")
        }

        let collapsed = segments
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }

        var seenSemantics = Set<String>()
        return collapsed.filter { token in
            let key = token.lowercased()
            guard !key.isEmpty, !seenSemantics.contains(key) else { return false }
            seenSemantics.insert(key)
            return true
        }
    }

    func canonicalLexicalAtoms(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        queryIntentClass: ExchangeIntent.QueryIntentClass
    ) -> [String] {
        if let english = ExchangeRetrievalEnglishProjection.trimmedCanonicalEnglish(si.canonicalEnglishSearchText) {
            return normalizeTerms(
                english
                    .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !Self.isClauseJoinedFragment($0) },
                maxCount: 16
            )
        }

        var values: [String] = []

        if let ot = si.objectType?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank {
            values.append(ot)
        }

        for token in si.broadRecallTokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !Self.isClauseJoinedFragment(trimmed) else { continue }
            guard !Self.isCanonicallyNarrowLexicalChip(trimmed) else { continue }
            values.append(trimmed)
        }

        var seenTaskPhraseKeys = Set(
            values.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )

        for taskPhrase in ExchangeCanonicalSearchIntentTaskPhrases.topTaskPhrases(from: si) {
            let trimmed = taskPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.lowercased()
            guard !seenTaskPhraseKeys.contains(key) else { continue }
            guard !Self.isClauseJoinedFragment(trimmed) else { continue }
            guard !Self.isCanonicallyNarrowLexicalChip(trimmed) else { continue }

            seenTaskPhraseKeys.insert(key)
            values.append(trimmed)
        }

        switch si.domainCategory {
        case .realEstate where queryIntentClass == .offerSearch || queryIntentClass == .providerSearch:
            values += ["listing", "property", "home", "house", "real estate"]
            if si.transactionIntent == .forSale {
                values.append("for sale")
            }

        case .homeService:
            values.append("contractor")
            let ot = si.objectType?.lowercased() ?? ""
            if ot.contains("roof") || ot.contains("roofing") || ot.contains("roofer") {
                values += ["roofing", "roof"]
            }

        default:
            break
        }

        return normalizeTerms(values, maxCount: 24).filter { !$0.isEmpty && !Self.isClauseJoinedFragment($0) }
    }

    func canonicalRoutedLexicalRails(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        facets: ExchangeIntentFacets,
        intent: ExchangeIntent,
        lexicalAtoms: [String]
    ) -> ([String], [String], [String]) {
        let routed = resolvedQueryIntentClass(facets: facets, intent: intent)

        var providerTerms: [String] = []
        var capabilityTerms: [String] = []
        var affinityTerms: [String] = []

        func atomicFacetTerms(_ values: [String]) -> [String] {
            normalizeTerms(values, maxCount: 12).filter {
                !$0.isEmpty && !Self.isClauseJoinedFragment($0)
            }
        }

        switch routed {
        case .offerSearch, .providerSearch:
            providerTerms =
                facets.providerTerms.isEmpty
                ? atomicFacetTerms(lexicalAtoms)
                : atomicFacetTerms(facets.providerTerms)

            if providerTerms.isEmpty {
                providerTerms = atomicFacetTerms(lexicalAtoms)
            }

        case .capabilitySearch, .collaborationSearch, .directOutreach, .followUp, .statusCheck:
            capabilityTerms =
                facets.capabilityTerms.isEmpty
                ? atomicFacetTerms(lexicalAtoms + si.semanticConcepts)
                : atomicFacetTerms(facets.capabilityTerms)

            if capabilityTerms.isEmpty {
                capabilityTerms = atomicFacetTerms(si.semanticConcepts + lexicalAtoms)
            }

        case .socialAffinitySearch, .relationshipSearch:
            affinityTerms =
                facets.affinityTerms.isEmpty
                ? atomicFacetTerms(lexicalAtoms + si.semanticConcepts)
                : atomicFacetTerms(facets.affinityTerms)

        case .generalDiscovery:
            capabilityTerms = atomicFacetTerms(si.semanticConcepts + lexicalAtoms)
        }

        return (providerTerms, capabilityTerms, affinityTerms)
    }

    func buildCanonicalSoftRegionTerms(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        resolvedPlaces: [ExchangeResolvedPlace]
    ) -> [String] {
        var values: [String] = []

        for place in si.places {
            let cleaned = Self.canonicalNormalizePlaceToken(place.normalizedText)
            guard !cleaned.isEmpty else { continue }

            values.append(cleaned)
            values.append(
                contentsOf: place.aliases
                    .map { Self.canonicalNormalizePlaceToken($0) }
                    .filter { !$0.isEmpty }
            )
            values.append(contentsOf: Self.placeAliasExpansions(forCanonicalToken: cleaned))
        }

        for resolved in resolvedPlaces {
            values.append(resolved.normalizedText)
            values.append(contentsOf: resolved.aliases)
        }

        return normalizeTerms(values, maxCount: 24)
            .filter { !$0.isEmpty && !Self.isClauseJoinedFragment($0) }
    }

    func canonicalExplicitHardConstraints(
        si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        facets _: ExchangeIntentFacets?
    ) -> [ExchangeIntent.Constraint] {
        var aggregated: [ExchangeIntent.Constraint] = []

        for item in si.hardConstraints {
            guard item.isHardConstraint else { continue }
            guard !Self.isLocationLikeConstraintKey(item.key) else { continue }

            aggregated.append(item)
        }

        for pref in si.preferences where pref.strength == .required {
            guard let rawValue = pref.value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank else {
                continue
            }

            let key = pref.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            guard !Self.isLocationLikeConstraintKey(key) else { continue }

            aggregated.append(
                ExchangeIntent.Constraint(
                    key: key,
                    value: rawValue,
                    isHardConstraint: true
                )
            )
        }

        for commercial in si.commercialConstraints where commercial.isHard {
            aggregated.append(
                ExchangeIntent.Constraint(
                    key: commercial.key.trimmingCharacters(in: .whitespacesAndNewlines),
                    value: commercial.value.trimmingCharacters(in: .whitespacesAndNewlines),
                    isHardConstraint: true
                )
            )
        }

        let filtered = aggregated.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return normalizeConstraints(filtered)
    }

    func normalizeWhitespaceList(_ segments: [String]) -> String {
        segments.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    func clampUnitInterval(_ value: Double) -> Double {
        Self.clampUnitIntervalStatic(value)
    }

    static func clampUnitIntervalStatic(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func canonicalNormalizePlaceToken(_ raw: String) -> String {
        stripClauseJoinedTrail(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func canonicalDisplayedPlacePhrase(_ places: [ExchangeIntentFacets.StructuredPlace]) -> String {
        let phrases: [String] = places.map { place in
            let token = canonicalNormalizePlaceToken(place.normalizedText)
            guard !token.isEmpty else { return "" }

            if token == "gta" {
                return "the Greater Toronto Area"
            }

            if token.contains("toronto") {
                return token.capitalized
            }

            return token.split(separator: " ").map { piece in
                let lower = piece.lowercased()
                guard let first = lower.first else { return "" }
                return String(first).uppercased() + lower.dropFirst()
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return phrases.joined(separator: ", ")
    }

    static func placeAliasExpansions(forCanonicalToken token: String) -> [String] {
        switch canonicalNormalizePlaceToken(token) {
        case "gta":
            return ["greater toronto area"]
        default:
            return []
        }
    }

    /// Avoid polluting lexical rails / keywords with nuanced attributes.
    static func isCanonicallyNarrowLexicalChip(_ value: String) -> Bool {
        let t = value.lowercased()
        if Self.isClauseJoinedFragment(t) { return true }

        if t.range(of: #"\d+\s*(bed|bedroom|br)s?\b"#, options: .regularExpression) != nil {
            return true
        }

        if t.range(of: #"\bvtb\b"#, options: .regularExpression) != nil {
            return true
        }

        if t.contains("seller financing") ||
            t.contains("vendor take") ||
            t.contains("take back mortgage") ||
            t.contains("mortgage") {
            return true
        }

        if ["tomorrow", "today", "tonight", "morning", "evening"].contains(t) ||
            (t.range(of: "next week") != nil) {
            return true
        }

        return false
    }

    static func isClauseJoinedFragment(_ value: String) -> Bool {
        let lower = value.lowercased()

        let boundarySlices = [" who ", " with ", ", and ", " and seller", " seller offers"]
        guard !boundarySlices.contains(where: { lower.contains($0) }) else {
            return true
        }

        let clauseSeparators = [",", ".", ";", "?", "!"]
        if clauseSeparators.contains(where: { lower.contains("\($0) ") }),
           lower.contains(" and ") {
            return true
        }

        if lower.contains(" and ")
            && (lower.contains(",") || lower.count > 64) {
            return true
        }

        let wordCount = lower.split(whereSeparator: { $0.isWhitespace }).count
        return wordCount > 5
    }

    static func stripClauseJoinedTrail(_ raw: String) -> String {
        let loweredMarkers = [" and ", " who ", " with ", " that ", " can ", " offers ", " offer "]
        var out = raw

        for marker in loweredMarkers {
            let lowered = out.lowercased()
            guard let range = lowered.range(of: marker) else { continue }
            out = String(out[..<range.lowerBound])
        }

        if let comma = out.firstIndex(of: ",") {
            out = String(out[..<comma])
        } else if let semi = out.firstIndex(of: ";") {
            out = String(out[..<semi])
        } else if let dot = out.firstIndex(of: ".") {
            out = String(out[..<dot])
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Core text

    func buildQueryText(
        thread: ExchangeThread,
        interpretation: ExchangeThread.InterpretationSnapshot?,
        facets: ExchangeIntentFacets?
    ) -> String? {
        firstNonBlank(
            thread.primarySearchText,
            thread.intent.objective,
            thread.intent.targetDescription,
            interpretation?.userQuestion,
            interpretation?.userSummary,
            facets?.searchableText
        )
    }

    func buildSemanticText(
        thread: ExchangeThread,
        interpretation: ExchangeThread.InterpretationSnapshot?,
        queryText: String?
    ) -> String? {
        firstNonBlank(
            interpretation?.userSummary,
            thread.intent.objective,
            thread.intent.targetDescription,
            queryText
        )
    }

    // MARK: - Soft routing term families
    //
    // Important:
    // These are NOT semantic truth.
    // They are lightweight query rails only.
    // Prefer canonical facet-owned terms when available.
    // Otherwise use narrow fallbacks rather than re-interpreting aggressively.

    func buildProviderTerms(
        intent: ExchangeIntent,
        interpretation: ExchangeThread.InterpretationSnapshot?,
        facets: ExchangeIntentFacets?
    ) -> [String] {
        if let facets, !facets.providerTerms.isEmpty {
            return normalizeTerms(facets.providerTerms)
        }

        let queryIntentClass = resolvedQueryIntentClass(
            facets: facets,
            intent: intent
        )

        guard queryIntentClass == .providerSearch || queryIntentClass == .offerSearch else {
            return []
        }

        var values: [String] = []
        values.append(contentsOf: interpretation?.targetTags ?? [])
        values.append(contentsOf: interpretation?.discoveryKeywords ?? [])
        if let targetDescription = intent.targetDescription { values.append(targetDescription) }
        if let objective = intent.objective.nilIfBlank { values.append(objective) }

        return normalizeTerms(values, maxCount: 10)
    }

    func buildCapabilityTerms(
        intent: ExchangeIntent,
        interpretation: ExchangeThread.InterpretationSnapshot?,
        facets: ExchangeIntentFacets?
    ) -> [String] {
        if let facets, !facets.capabilityTerms.isEmpty {
            return normalizeTerms(facets.capabilityTerms)
        }

        let queryIntentClass = resolvedQueryIntentClass(
            facets: facets,
            intent: intent
        )

        guard queryIntentClass == .capabilitySearch ||
              queryIntentClass == .collaborationSearch ||
              queryIntentClass == .directOutreach ||
              queryIntentClass == .followUp ||
              queryIntentClass == .statusCheck else {
            return []
        }

        var values: [String] = []
        values.append(contentsOf: interpretation?.semanticTags ?? [])
        values.append(contentsOf: interpretation?.targetTags ?? [])
        if let targetDescription = intent.targetDescription { values.append(targetDescription) }
        if let objective = intent.objective.nilIfBlank { values.append(objective) }

        return normalizeTerms(values, maxCount: 10)
    }

    func buildAffinityTerms(
        intent: ExchangeIntent,
        interpretation: ExchangeThread.InterpretationSnapshot?,
        facets: ExchangeIntentFacets?
    ) -> [String] {
        if let facets, !facets.affinityTerms.isEmpty {
            return normalizeTerms(facets.affinityTerms)
        }

        let queryIntentClass = resolvedQueryIntentClass(
            facets: facets,
            intent: intent
        )

        guard queryIntentClass == .socialAffinitySearch ||
              queryIntentClass == .relationshipSearch else {
            return []
        }

        var values: [String] = []
        values.append(contentsOf: interpretation?.semanticTags ?? [])
        values.append(contentsOf: interpretation?.targetTags ?? [])
        if let targetDescription = intent.targetDescription { values.append(targetDescription) }
        if let objective = intent.objective.nilIfBlank { values.append(objective) }

        return normalizeTerms(values, maxCount: 10)
    }

    // MARK: - General keywords

    func buildKeywords(
        intent: ExchangeIntent,
        interpretation: ExchangeThread.InterpretationSnapshot?,
        facets: ExchangeIntentFacets?,
        queryText: String?,
        queryEntities: [ExchangeQueryEntity]
    ) -> [String] {
        var values: [String] = []

        values.append(contentsOf: interpretation?.discoveryKeywords ?? [])
        values.append(contentsOf: interpretation?.semanticTags ?? [])
        values.append(contentsOf: interpretation?.targetTags ?? [])
        values.append(contentsOf: facets?.primaryKeywords ?? [])
        values.append(contentsOf: facets?.secondaryKeywords ?? [])

        if let queryText = queryText?.nilIfBlank {
            values.append(queryText)
        }

        if let targetDescription = intent.targetDescription?.nilIfBlank {
            values.append(targetDescription)
        }
        values.append(contentsOf: queryEntities.map(\.normalizedText))

        return normalizeTerms(values, maxCount: 16)
    }

    func buildQueryEntities(
        queryText: String?,
        intent: ExchangeIntent,
        facets: ExchangeIntentFacets?
    ) -> [ExchangeQueryEntity] {
        let text = firstNonBlank(
            queryText,
            facets?.searchableText,
            intent.objective,
            intent.targetDescription
        ) ?? ""

        let extracted = entityExtractor.extractEntities(
            from: text,
            intent: intent,
            facets: facets
        )

        if let facets, !facets.queryEntities.isEmpty {
            return dedupeEntities(facets.queryEntities + extracted)
        }

        return dedupeEntities(extracted)
    }

    func buildResolvedPlaces(
        from entities: [ExchangeQueryEntity],
        facets: ExchangeIntentFacets?
    ) -> [ExchangeResolvedPlace] {
        var seen = Set<String>()
        var output: [ExchangeResolvedPlace] = []

        if let facets {
            for place in facets.resolvedPlaces {
                let key = place.canonicalID.lowercased()
                guard !key.isEmpty, !seen.contains(key) else { continue }
                seen.insert(key)
                output.append(place)
            }
        }

        for entity in entities where entity.kind == .place {
            guard let resolved = placeResolver.resolvePlaceSync(entity) else { continue }
            let key = resolved.canonicalID.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(resolved)
        }
        return output
    }

    func buildHardRegionIDs(from resolvedPlaces: [ExchangeResolvedPlace]) -> [String] {
        normalizeTerms(
            resolvedPlaces
                .filter { $0.confidence >= 0.80 }
                .map(\.canonicalID),
            maxCount: 8
        )
    }

    func buildSoftRegionTerms(
        thread: ExchangeThread,
        facets: ExchangeIntentFacets?,
        intent: ExchangeIntent,
        resolvedPlaces: [ExchangeResolvedPlace],
        queryEntities: [ExchangeQueryEntity]
    ) -> [String] {
        var values = facets?.softLocationTerms ?? []
        values.append(contentsOf: resolvedPlaces.flatMap(\.aliases))
        values.append(contentsOf: resolvedPlaces.map(\.normalizedText))
        values.append(contentsOf: facetDerivedPlaceHints(facets: facets, intent: intent))
        values.append(contentsOf: intentLocationConstraintPlaceHints(thread: thread, intent: intent, facets: facets))
        values.append(contentsOf: queryEntities.compactMap { entity in
            guard entity.kind == .place else { return nil }
            guard !entity.hardConstraintEligible || entity.confidence < 0.80 else { return nil }
            return entity.normalizedText
        })
        return normalizeTerms(values, maxCount: 24)
    }

    /// Runs the deterministic extractor on facet/interpreter location strings so only
    /// structured place candidates become soft hints (never raw polluted sentences).
    func facetDerivedPlaceHints(
        facets: ExchangeIntentFacets?,
        intent: ExchangeIntent
    ) -> [String] {
        guard let facets else { return [] }

        var hints: [String] = []
        if let placeName = facets.placeName?.nilIfBlank {
            let places = entityExtractor.extractEntities(from: placeName, intent: intent, facets: facets)
                .filter { $0.kind == .place }
            hints.append(contentsOf: places.map(\.normalizedText))
        }
        for raw in facets.regionTerms {
            let places = entityExtractor.extractEntities(from: raw, intent: intent, facets: facets)
                .filter { $0.kind == .place }
            hints.append(contentsOf: places.map(\.normalizedText))
        }

        if let locationText = facets.locationText?.nilIfBlank {
            let places = entityExtractor.extractEntities(from: locationText, intent: intent, facets: facets)
                .filter { $0.kind == .place }
            hints.append(contentsOf: places.map(\.normalizedText))
        }

        return hints
    }

    func intentLocationConstraintPlaceHints(
        thread: ExchangeThread,
        intent: ExchangeIntent,
        facets: ExchangeIntentFacets?
    ) -> [String] {
        var hints: [String] = []
        for constraint in thread.intent.constraints where constraint.isHardConstraint {
            let key = constraint.key.lowercased()
            guard key.contains("location") ||
                key.contains("region") ||
                key.contains("place") ||
                key.contains("city") else { continue }

            let value = constraint.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let places = entityExtractor.extractEntities(from: value, intent: intent, facets: facets)
                .filter { $0.kind == .place }
            hints.append(contentsOf: places.map(\.normalizedText))
        }
        return hints
    }

    func buildCommercialIntentTerms(from entities: [ExchangeQueryEntity]) -> [String] {
        normalizeTerms(
            entities
                .filter { $0.kind == .commercialIntent }
                .map(\.normalizedText),
            maxCount: 8
        )
    }

    func buildTimeTerms(from entities: [ExchangeQueryEntity]) -> [String] {
        normalizeTerms(
            entities
                .filter { $0.kind == .time }
                .map(\.normalizedText),
            maxCount: 8
        )
    }

    // MARK: - Constraints

    func buildExplicitHardConstraints(
        thread: ExchangeThread,
        facets: ExchangeIntentFacets?
    ) -> [ExchangeIntent.Constraint] {
        let threadHard = thread.intent.constraints
            .filter(\.isHardConstraint)
            .filter { !Self.isLocationLikeConstraintKey($0.key) }

        let facetHard: [ExchangeIntent.Constraint] = (facets?.hardRequirements ?? [])
            .filter(\.isHard)
            .filter { !Self.isLocationLikeConstraintKey($0.key) }
            .map {
                ExchangeIntent.Constraint(
                    key: $0.key,
                    value: $0.value,
                    isHardConstraint: true
                )
            }

        return normalizeConstraints(threadHard + facetHard)
    }

    static func isLocationLikeConstraintKey(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return k.contains("location") ||
            k.contains("region") ||
            k.contains("place") ||
            k.contains("city") ||
            k.contains("geo")
    }

    func inferExplicitFulfillmentRequired(
        thread: ExchangeThread,
        facets: ExchangeIntentFacets?
    ) -> Bool {
        if thread.intent.constraints.contains(where: {
            $0.isHardConstraint &&
            (
                $0.key.lowercased().contains("fulfillment") ||
                $0.key.lowercased().contains("delivery") ||
                $0.key.lowercased().contains("remote") ||
                $0.key.lowercased().contains("local")
            )
        }) {
            return true
        }

        guard let fulfillmentMode = facets?.fulfillmentMode else {
            return false
        }

        switch fulfillmentMode {
        case .localOnly, .digitalDelivery, .shippable:
            return true
        case .localPreferred, .remoteFriendly, .unknown:
            return false
        }
    }

    // MARK: - Operational gating

    func reachabilityRequirement(for thread: ExchangeThread) -> ExchangeRetrievalQuery.ReachabilityRequirement {
        switch thread.intent.kind {
        case .message,
             .followUp,
             .requestQuote,
             .negotiate,
             .arrangeCall,
             .arrangeMeeting,
             .invite,
             .coordinate:
            if thread.metadata["trusted_path_id"]?.nilIfBlank != nil {
                return .introAllowed
            }
            return .acceptingInboundOnly

        case .introduce:
            return .introAllowed

        case .find, .source, .plan, .checkStatus, .other:
            return .any
        }
    }

    func visibilityAllowList(for thread: ExchangeThread) -> [String] {
        switch thread.intent.kind {
        case .find,
             .source,
             .plan,
             .message,
             .followUp,
             .introduce,
             .requestQuote,
             .negotiate,
             .arrangeCall,
             .arrangeMeeting,
             .invite,
             .coordinate,
             .checkStatus,
             .other:
            return ["discoverable", "limited", "publicdiscoverable", "limitedsurface"]
        }
    }

    func availabilityAllowList(for thread: ExchangeThread) -> [String] {
        switch thread.intent.kind {
        case .message,
             .followUp,
             .requestQuote,
             .negotiate,
             .arrangeCall,
             .arrangeMeeting,
             .invite,
             .coordinate:
            return ["open", "limited"]

        case .find, .source, .plan, .introduce, .checkStatus, .other:
            return ["open", "limited", "paused"]
        }
    }

    // MARK: - Utilities

    func firstNonBlank(_ values: String?...) -> String? {
        values.first {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        } ?? nil
    }

    func normalizeTerms(
        _ values: [String],
        maxCount: Int = 24
    ) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for value in values {
            let cleaned = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !cleaned.isEmpty else { continue }

            let collapsed = cleaned
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            guard !collapsed.isEmpty else { continue }
            guard !seen.contains(collapsed) else { continue }

            seen.insert(collapsed)
            output.append(String(collapsed.prefix(160)))

            if output.count >= maxCount {
                break
            }
        }

        return output
    }

    func normalizeConstraints(_ values: [ExchangeIntent.Constraint]) -> [ExchangeIntent.Constraint] {
        var seen = Set<String>()
        var output: [ExchangeIntent.Constraint] = []

        for item in values {
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard !key.isEmpty, !value.isEmpty else { continue }

            let dedupe = "\(key)|||\(value)|||\(item.isHardConstraint)"
            guard !seen.contains(dedupe) else { continue }

            seen.insert(dedupe)
            output.append(
                ExchangeIntent.Constraint(
                    id: item.id,
                    key: String(item.key.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
                    value: String(item.value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)),
                    isHardConstraint: item.isHardConstraint
                )
            )
        }

        return output
    }

    func dedupeEntities(_ values: [ExchangeQueryEntity]) -> [ExchangeQueryEntity] {
        var seen = Set<String>()
        var output: [ExchangeQueryEntity] = []
        for entity in values {
            guard !entity.normalizedText.isEmpty else { continue }
            let key = "\(entity.kind.rawValue)||\(entity.normalizedText)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(entity)
        }
        return output
    }

    func applyNearMeLexicalGuard(
        providerTerms: inout [String],
        capabilityTerms: inout [String],
        affinityTerms: inout [String],
        keywords: inout [String],
        facets: ExchangeIntentFacets?
    ) {
        guard ExchangeNearMeLexicalSanitizer.shouldStripNearMeLexicals(facets) else { return }
        providerTerms = normalizeTerms(
            ExchangeNearMeLexicalSanitizer.filterInterpretationTags(providerTerms),
            maxCount: 24
        )
        capabilityTerms = normalizeTerms(
            ExchangeNearMeLexicalSanitizer.filterInterpretationTags(capabilityTerms),
            maxCount: 24
        )
        affinityTerms = normalizeTerms(
            ExchangeNearMeLexicalSanitizer.filterInterpretationTags(affinityTerms),
            maxCount: 24
        )
        keywords = normalizeTerms(
            ExchangeNearMeLexicalSanitizer.filterInterpretationTags(keywords),
            maxCount: 24
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
