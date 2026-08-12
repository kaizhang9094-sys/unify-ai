import Foundation

/// Deterministic reducer: user intent facets vs selected provider surface (+ optional LLM compare + match cautions).
public struct ExchangeRequesterIntentGapReducer: Sendable {
    public init() {}

    public struct Input: Sendable {
        public var thread: ExchangeThread
        public var facets: ExchangeIntentFacets?
        public var searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent?
        public var offer: ExchangeOffer?
        public var publicProfile: ExchangePublicNodeProfile?
        public var operatingMemory: ExchangeStructuredOperatingMemory
        public var knownFactLines: [String]
        public var selectedMatch: ExchangeMatch?
        public var matchCompare: ExchangeRequesterMatchCompareResult?

        public init(
            thread: ExchangeThread,
            facets: ExchangeIntentFacets? = nil,
            searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent? = nil,
            offer: ExchangeOffer? = nil,
            publicProfile: ExchangePublicNodeProfile? = nil,
            operatingMemory: ExchangeStructuredOperatingMemory,
            knownFactLines: [String] = [],
            selectedMatch: ExchangeMatch? = nil,
            matchCompare: ExchangeRequesterMatchCompareResult? = nil
        ) {
            self.thread = thread
            let resolvedFacets = facets ?? thread.facets
            self.facets = resolvedFacets
            self.searchIntent = searchIntent ?? resolvedFacets?.searchIntent ?? thread.facets?.searchIntent
            self.offer = offer
            self.publicProfile = publicProfile
            self.operatingMemory = operatingMemory
            self.knownFactLines = knownFactLines
            self.selectedMatch = selectedMatch
            self.matchCompare = matchCompare
        }
    }

    public struct Output: Sendable {
        public var gaps: [ExchangeRequesterIntentGap]
        public var combinedProviderQuestion: String?

        public init(gaps: [ExchangeRequesterIntentGap], combinedProviderQuestion: String?) {
            self.gaps = gaps
            self.combinedProviderQuestion = combinedProviderQuestion
        }
    }

    public func reduce(input: Input) -> Output {
        var gaps: [ExchangeRequesterIntentGap] = []
        let locationFact = ExchangeSecondHalfLocationResolver.resolve(facets: input.facets)
        var skippedLocationGaps = 0

        // Surface + durable facts only. User objective / raw search text must not count as evidence
        // that the selected offer/profile already answers a facet (would false-satisfy region, timing, budget, etc.).
        let hay = Self.evidenceHaystack(
            offer: input.offer,
            profile: input.publicProfile,
            memory: input.operatingMemory,
            knownFacts: input.knownFactLines
        )

        if let si = input.searchIntent {
            gaps.append(
                contentsOf: gapsFromCanonicalSearchIntent(
                    si,
                    hay: hay,
                    offer: input.offer,
                    profile: input.publicProfile,
                    locationFact: locationFact,
                    skippedLocationGaps: &skippedLocationGaps
                )
            )
        }

        gaps.append(contentsOf: gapsFromIntentConstraints(input.thread.intent.constraints, hay: hay))

        gaps.append(contentsOf: gapsFromDesiredOutcomes(input.thread.intent.desiredOutcomes, hay: hay))

        gaps.append(
            contentsOf: gapsFromFacetsRail(
                input.facets,
                hay: hay,
                offer: input.offer,
                profile: input.publicProfile,
                locationFact: locationFact,
                skippedLocationGaps: &skippedLocationGaps
            )
        )

        gaps.append(contentsOf: gapsFromMatch(input.selectedMatch))

        gaps.append(contentsOf: gapsFromLLMCompare(input.matchCompare, existingKeys: Set(gaps.map(\.stableKey))))

        gaps = Self.applyLocationFactConsolidation(
            gaps: gaps,
            locationFact: locationFact,
            skippedLocationGaps: &skippedLocationGaps
        )

        gaps = Self.dedupeGaps(gaps)
        gaps.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.stableKey < rhs.stableKey
        }

        let hasAnchoredProviderSurface = input.offer != nil || input.publicProfile != nil
        let combined = Self.buildCombinedProviderQuestion(
            gaps: gaps,
            compare: input.matchCompare,
            hasAnchoredProviderSurface: hasAnchoredProviderSurface
        )

        #if DEBUG
        let sat = gaps.filter { $0.status == .satisfied }.count
        let unk = gaps.filter { $0.status == .unknown }.count
        let mis = gaps.filter { $0.status == .mismatch }.count
        let opt = gaps.filter { $0.status == .optionalUnknown }.count
        let top = gaps.filter { $0.status != .satisfied }.prefix(5).map(\.label).joined(separator: ", ")
        let pqCount = input.matchCompare?.providerQuestions.count ?? 0
        let emittedLocationGaps = gaps.filter { $0.kind == .region && Self.isLocationManagedGap($0) }.count
        Swift.print(
            "[RequesterIntentGapReducer] thread=\(input.thread.id.uuidString) " +
                "total=\(gaps.count) satisfied=\(sat) unknown=\(unk) mismatch=\(mis) optionalUnknown=\(opt) " +
                "topGaps=\(top) providerQuestions=\(pqCount)"
        )
        Swift.print(
            "[RequesterIntentGapReducer] locationFact source=\(locationFact.source.rawValue) " +
                "satisfied=\(locationFact.isSatisfiedForCurrentStep) hasSpatial=\(locationFact.hasSpatialAnchor) " +
                "askClarification=\(locationFact.shouldAskClarification) " +
                "skippedLocationGaps=\(skippedLocationGaps) emittedLocationGaps=\(emittedLocationGaps)"
        )
        #endif

        return Output(gaps: gaps, combinedProviderQuestion: combined)
    }

    /// Human-readable lines merged ahead of publication templates on the requester agency context.
    public static func userFacingMissingLines(
        from gaps: [ExchangeRequesterIntentGap],
        locationFact: ExchangeSecondHalfLocationFact? = nil
    ) -> [String] {
        let lines = gaps.compactMap { g -> String? in
            switch g.status {
            case .satisfied:
                return nil
            case .optionalUnknown:
                return "Intent gap (\(g.label) · optional): \(g.requestedValue)"
            case .unknown, .mismatch:
                return "Intent gap (\(g.label) · \(g.status.rawValue)): \(g.requestedValue)"
            }
        }
        return ExchangeSecondHalfLocationResolver.filterRequesterLocationMissingFactLines(
            lines,
            locationFact: locationFact
        )
    }

    // MARK: - Evidence

    private static func evidenceHaystack(
        offer: ExchangeOffer?,
        profile: ExchangePublicNodeProfile?,
        memory: ExchangeStructuredOperatingMemory,
        knownFacts: [String]
    ) -> String {
        var parts: [String] = []

        if let offer {
            parts.append(offer.title.lowercased())
            parts.append((offer.summary ?? "").lowercased())
            parts.append((offer.category ?? "").lowercased())
            parts.append(offer.tags.map { $0.lowercased() }.joined(separator: " "))
            parts.append(offer.regionTags.map { $0.lowercased() }.joined(separator: " "))
            parts.append(offer.regionAliases.map { $0.lowercased() }.joined(separator: " "))
            parts.append((offer.fulfillment.leadTimeNote ?? "").lowercased())
            parts.append((offer.fulfillment.capacityNote ?? "").lowercased())
            parts.append((offer.commercialFacts.priceDisplay ?? "").lowercased())
            parts.append((offer.commercialFacts.serviceAreaNote ?? "").lowercased())
            parts.append(offer.commercialSurfaceSkimLines.map { $0.lowercased() }.joined(separator: " "))
            parts.append((offer.semantic.notes ?? "").lowercased())
            parts.append(offer.semantic.domains.map { $0.lowercased() }.joined(separator: " "))
            parts.append(offer.semantic.serviceKinds.map { $0.lowercased() }.joined(separator: " "))
        }

        if let profile {
            parts.append((profile.displayName ?? "").lowercased())
            parts.append((profile.headline ?? "").lowercased())
            parts.append((profile.summary ?? "").lowercased())
            parts.append(profile.regionTags.map { $0.lowercased() }.joined(separator: " "))
            parts.append(profile.interests.map { $0.lowercased() }.joined(separator: " "))
            parts.append(profile.activityTags.map { $0.lowercased() }.joined(separator: " "))
        }

        for line in memory.standardPolicies.prefix(6) {
            parts.append("\(line.title) \(line.details)".lowercased())
        }
        for line in knownFacts.prefix(16) {
            parts.append(line.lowercased())
        }

        return parts.joined(separator: " | ")
    }

    private static func haystackContainsTokens(_ hay: String, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        return tokens.contains { !$0.isEmpty && hay.contains($0) }
    }

    private static func normalizedTokens(_ text: String) -> [String] {
        let lower = text.lowercased()
        let seps = CharacterSet.alphanumerics.inverted
        return lower
            .components(separatedBy: seps)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
    }

    private static func providerServiceGapQuestion(
        taskPhrase: String?,
        recall: String,
        domainCategory: ExchangeIntentFacets.DomainCategory
    ) -> String {
        if let taskPhrase, !taskPhrase.isEmpty {
            return ExchangeCanonicalSearchIntentTaskPhrases.providerServiceGapQuestion(
                taskPhrase: taskPhrase,
                domainCategory: domainCategory
            )
        }
        return "Do you provide services matching \"\(recall)\" for this request?"
    }

    // MARK: - Canonical search intent

    private func gapsFromCanonicalSearchIntent(
        _ si: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        hay: String,
        offer: ExchangeOffer?,
        profile: ExchangePublicNodeProfile?,
        locationFact: ExchangeSecondHalfLocationFact,
        skippedLocationGaps: inout Int
    ) -> [ExchangeRequesterIntentGap] {
        var out: [ExchangeRequesterIntentGap] = []

        let recall = (si.broadRecallTokens + si.semanticConcepts).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPhrases = ExchangeCanonicalSearchIntentTaskPhrases.topTaskPhrases(from: si, maxCount: 2)
        let primaryTask = taskPhrases.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasServiceSignal = !recall.isEmpty || !(primaryTask?.isEmpty ?? true)

        if hasServiceSignal {
            let requestedValue = (primaryTask?.isEmpty == false ? primaryTask : nil) ?? recall
            let evaluationPhrase = (primaryTask?.isEmpty == false ? primaryTask : nil) ?? recall
            var tokens = Self.normalizedTokens(evaluationPhrase)
            if let primaryTask, !primaryTask.isEmpty {
                tokens.append(contentsOf: Self.normalizedTokens(primaryTask))
            }
            tokens = Array(Set(tokens)).filter { !$0.isEmpty }

            let hit = Self.haystackContainsTokens(hay, tokens: tokens)
                || Self.haystackContainsTokens(hay, tokens: [evaluationPhrase.lowercased()])
            let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
            let q = st == .unknown
                ? Self.providerServiceGapQuestion(
                    taskPhrase: primaryTask,
                    recall: recall,
                    domainCategory: si.domainCategory
                )
                : nil
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(.service, requestedValue),
                    kind: .service,
                    status: st,
                    label: "Service / category",
                    requestedValue: requestedValue,
                    evidence: hit ? "Matched published title, tags, or summary." : nil,
                    questionForProvider: q,
                    priority: st == .unknown ? 3 : 20,
                    source: "canonicalIntent"
                )
            )
        }

        for place in si.places {
            let req = place.normalizedText
            if ExchangeSecondHalfLocationResolver.suppressesRequesterLocationGaps(locationFact) {
                skippedLocationGaps += 1
                continue
            }
            if locationFact.isSatisfiedForCurrentStep,
               ExchangeSecondHalfLocationResolver.isPoisonedLocationText(req) {
                skippedLocationGaps += 1
                continue
            }
            let label = "Place / region"
            let tokens = [req.lowercased()] + place.aliases.map { $0.lowercased() }
            let regionTags = (offer?.regionTags ?? []) + (profile?.regionTags ?? []) + (offer?.regionAliases ?? [])
            let tagHay = regionTags.joined(separator: " ").lowercased()
            let hitInSurface = Self.haystackContainsTokens(tagHay + " " + hay, tokens: tokens)
                || Self.haystackContainsTokens(hay, tokens: tokens)

            if hitInSurface {
                out.append(
                    ExchangeRequesterIntentGap(
                        stableKey: Self.key(.region, req),
                        kind: .region,
                        status: .satisfied,
                        label: label,
                        requestedValue: req,
                        evidence: "Region appears on published surface or supporting copy.",
                        questionForProvider: nil,
                        priority: 20,
                        source: "canonicalIntent"
                    )
                )
            } else if place.isHard, !regionTags.isEmpty,
                      Self.regionTagsContradict(tokens: tokens, regionTags: regionTags) {
                out.append(
                    ExchangeRequesterIntentGap(
                        stableKey: Self.key(.region, req),
                        kind: .region,
                        status: .mismatch,
                        label: label,
                        requestedValue: req,
                        evidence: "Published regions do not include the requested place: \(regionTags.joined(separator: ", ")).",
                        questionForProvider: "Can you confirm whether you serve \(req) given your published service areas?",
                        priority: 0,
                        source: "canonicalIntent"
                    )
                )
            } else {
                out.append(
                    ExchangeRequesterIntentGap(
                        stableKey: Self.key(.region, req),
                        kind: .region,
                        status: .unknown,
                        label: label,
                        requestedValue: req,
                        evidence: nil,
                        questionForProvider: "Can you confirm whether you serve \(req) for this job?",
                        priority: 2,
                        source: "canonicalIntent"
                    )
                )
            }
        }

        for tc in si.timeConstraints {
            let req = tc.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !req.isEmpty else { continue }
            let timeTokens = Self.normalizedTokens(req) + [req.lowercased()]
            let availTokens = ["available", "availability", "open", "slot", "schedule", "book", "appointment", "tomorrow", "pm", "am"]
            let hit = Self.haystackContainsTokens(hay, tokens: timeTokens)
                || (Self.haystackContainsTokens(hay, tokens: availTokens) && Self.haystackContainsTokens(hay, tokens: timeTokens))
            let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(.timing, req),
                    kind: .timing,
                    status: st,
                    label: "Timing",
                    requestedValue: req,
                    evidence: hit ? "Timing or availability language appears on the published surface." : nil,
                    questionForProvider: st == .unknown
                        ? "Can you confirm whether you are available around \(req) for this request?"
                        : nil,
                    priority: st == .unknown ? 1 : 20,
                    source: "canonicalIntent"
                )
            )
        }

        for cc in si.commercialConstraints {
            let req = "\(cc.key): \(cc.value)".trimmingCharacters(in: .whitespacesAndNewlines)
            guard !req.isEmpty else { continue }
            let kind: ExchangeRequesterIntentGap.Kind = cc.kind == .budget ? .budget : .other
            let tokens = Self.normalizedTokens(cc.value) + [cc.value.lowercased()]
            let priceHit = Self.haystackContainsTokens(hay, tokens: tokens)
                || hay.contains("$")
                || hay.contains("quote")
                || hay.contains("pricing")
            let st: ExchangeRequesterIntentGap.Status = priceHit ? .satisfied : .unknown
            let label = cc.kind == .budget ? "Budget / price" : "Commercial constraint"
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(kind, req),
                    kind: kind,
                    status: st,
                    label: label,
                    requestedValue: req,
                    evidence: priceHit ? "Pricing or quote language appears on the published surface." : nil,
                    questionForProvider: st == .unknown && cc.kind == .budget
                        ? "Can you confirm whether initial pricing or a visit can work within \(cc.value)?"
                        : (st == .unknown ? "Could you clarify how this applies: \(req)?" : nil),
                    priority: st == .unknown && cc.kind == .budget ? 2 : (st == .unknown ? 4 : 20),
                    source: "canonicalIntent"
                )
            )
        }

        for pref in si.preferences {
            let req = "\(pref.key)\(pref.value.map { ": \($0)" } ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
            guard !req.isEmpty else { continue }
            let tokens = Self.normalizedTokens(pref.value ?? pref.key)
            let hit = Self.haystackContainsTokens(hay, tokens: tokens + [pref.key.lowercased()])
            switch pref.strength {
            case .required:
                let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
                out.append(
                    ExchangeRequesterIntentGap(
                        stableKey: Self.key(.preference, req),
                        kind: .preference,
                        status: st,
                        label: "Preference (required)",
                        requestedValue: req,
                        evidence: hit ? "Preference appears addressed in published copy." : nil,
                        questionForProvider: st == .unknown ? "Could you confirm whether you can meet this preference: \(req)?" : nil,
                        priority: st == .unknown ? 3 : 20,
                        source: "canonicalIntent"
                    )
                )
            case .preferred, .optional:
                let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .optionalUnknown
                out.append(
                    ExchangeRequesterIntentGap(
                        stableKey: Self.key(.preference, req),
                        kind: .preference,
                        status: st,
                        label: "Preference (soft)",
                        requestedValue: req,
                        evidence: hit ? "Preference appears in published copy." : nil,
                        questionForProvider: st == .optionalUnknown ? "If possible, could you share whether \(req) applies?" : nil,
                        priority: 12,
                        source: "canonicalIntent"
                    )
                )
            }
        }

        for attr in si.attributes {
            let req = "\(attr.key): \(attr.value)".trimmingCharacters(in: .whitespacesAndNewlines)
            guard !req.isEmpty else { continue }
            let tokens = Self.normalizedTokens(attr.value) + [attr.key.lowercased()]
            let hit = Self.haystackContainsTokens(hay, tokens: tokens)
            let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(.taskDetail, req),
                    kind: .taskDetail,
                    status: st,
                    label: "Task detail",
                    requestedValue: req,
                    evidence: hit ? "Task detail appears reflected in published copy." : nil,
                    questionForProvider: st == .unknown ? "Could you confirm whether you handle work like: \(req)?" : nil,
                    priority: st == .unknown ? 4 : 20,
                    source: "canonicalIntent"
                )
            )
        }

        if let ti = si.transactionIntent {
            let req = ti.rawValue
            let hit = hay.contains(ti.rawValue.lowercased()) || hay.contains("quote") || hay.contains("book")
            let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(.other, req),
                    kind: .other,
                    status: st,
                    label: "Desired action",
                    requestedValue: req,
                    evidence: hit ? "Published surface mentions related next-step language." : nil,
                    questionForProvider: st == .unknown ? "Could you confirm the typical next step (quote, visit, booking) for requests like this?" : nil,
                    priority: st == .unknown ? 6 : 20,
                    source: "canonicalIntent"
                )
            )
        }

        return out
    }

    private static func regionTagsContradict(tokens: [String], regionTags: [String]) -> Bool {
        let tagsLower = regionTags.map { $0.lowercased() }
        let hasUser = tokens.contains { t in tagsLower.contains { $0.contains(t) || t.contains($0) } }
        if hasUser { return false }
        return !tagsLower.isEmpty
    }

    // MARK: - Constraints / outcomes / rails

    private func gapsFromIntentConstraints(
        _ constraints: [ExchangeIntent.Constraint],
        hay: String
    ) -> [ExchangeRequesterIntentGap] {
        var out: [ExchangeRequesterIntentGap] = []
        for c in constraints {
            let key = c.key.lowercased()
            let val = c.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !val.isEmpty else { continue }

            if key.contains("insur") || val.lowercased().contains("insur") || val.lowercased().contains("bond") {
                let hit = hay.contains("insur") || hay.contains("bond") || hay.contains("licens")
                let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
                out.append(
                    ExchangeRequesterIntentGap(
                        stableKey: Self.key(.credential, val),
                        kind: .credential,
                        status: st,
                        label: "Credential / proof",
                        requestedValue: val,
                        evidence: hit ? "Insurance or licensing language appears on the published surface." : nil,
                        questionForProvider: st == .unknown ? "Can you confirm whether you are insured (and any relevant licensing) for this work?" : nil,
                        priority: st == .unknown ? 2 : 20,
                        source: "constraint"
                    )
                )
            } else if key.contains("budget") || key.contains("price") || val.contains("$") {
                let hit = hay.contains("$") || hay.contains("price") || hay.contains("quote") || hay.contains("rate")
                let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
                out.append(
                    ExchangeRequesterIntentGap(
                        stableKey: Self.key(.budget, val),
                        kind: .budget,
                        status: st,
                        label: "Budget",
                        requestedValue: val,
                        evidence: hit ? "Budget or pricing language appears on the published surface." : nil,
                        questionForProvider: st == .unknown ? "Can you confirm whether pricing can align with: \(val)?" : nil,
                        priority: st == .unknown ? 2 : 20,
                        source: "constraint"
                    )
                )
            }
        }
        return out
    }

    private func gapsFromDesiredOutcomes(
        _ outcomes: [ExchangeIntent.DesiredOutcome],
        hay: String
    ) -> [ExchangeRequesterIntentGap] {
        guard outcomes.contains(.quote) || outcomes.contains(.proposal) else { return [] }
        let req = outcomes.map(\.rawValue).sorted().joined(separator: ", ")
        let hit = hay.contains("quote") || hay.contains("pricing") || hay.contains("estimate")
        let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
        return [
            ExchangeRequesterIntentGap(
                stableKey: Self.key(.other, req),
                kind: .other,
                status: st,
                label: "Desired outcome",
                requestedValue: req,
                evidence: hit ? "Quote or estimate language appears on the published surface." : nil,
                questionForProvider: st == .unknown ? "Could you outline how quoting or estimates typically works for this request?" : nil,
                priority: st == .unknown ? 5 : 20,
                source: "canonicalIntent"
            )
        ]
    }

    private func gapsFromFacetsRail(
        _ facets: ExchangeIntentFacets?,
        hay: String,
        offer: ExchangeOffer?,
        profile: ExchangePublicNodeProfile?,
        locationFact: ExchangeSecondHalfLocationFact,
        skippedLocationGaps: inout Int
    ) -> [ExchangeRequesterIntentGap] {
        guard let facets else { return [] }
        var out: [ExchangeRequesterIntentGap] = []

        if let tt = facets.timeText?.trimmingCharacters(in: .whitespacesAndNewlines), !tt.isEmpty {
            let tokens = Self.normalizedTokens(tt) + [tt.lowercased()]
            let hit = Self.haystackContainsTokens(hay, tokens: tokens)
            let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(.timing, tt),
                    kind: .timing,
                    status: st,
                    label: "Timing (facets)",
                    requestedValue: tt,
                    evidence: hit ? "Timing cues appear on the published surface." : nil,
                    questionForProvider: st == .unknown ? "Can you confirm timing availability for: \(tt)?" : nil,
                    priority: st == .unknown ? 1 : 20,
                    source: "canonicalIntent"
                )
            )
        }

        for req in facets.hardRequirements {
            let line = "\(req.key): \(req.value)".trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if ExchangeSecondHalfLocationResolver.shouldSkipRequesterLocationRail(
                key: req.key,
                value: req.value,
                locationFact: locationFact
            ) {
                skippedLocationGaps += 1
                continue
            }
            let tokens = Self.normalizedTokens(req.value) + [req.key.lowercased()]
            let hit = Self.haystackContainsTokens(hay, tokens: tokens)
            let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(.other, line),
                    kind: .other,
                    status: st,
                    label: "Hard requirement",
                    requestedValue: line,
                    evidence: hit ? "Requirement appears reflected in published copy." : nil,
                    questionForProvider: st == .unknown ? "Could you confirm this requirement: \(line)?" : nil,
                    priority: st == .unknown ? 3 : 20,
                    source: "canonicalIntent"
                )
            )
        }

        for pref in facets.softPreferences {
            let line = "\(pref.key): \(pref.value)".trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if ExchangeSecondHalfLocationResolver.shouldSkipRequesterLocationRail(
                key: pref.key,
                value: pref.value,
                locationFact: locationFact
            ) {
                skippedLocationGaps += 1
                continue
            }
            let tokens = Self.normalizedTokens(pref.value) + [pref.key.lowercased()]
            let hit = Self.haystackContainsTokens(hay, tokens: tokens)
            let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .optionalUnknown
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(.preference, line),
                    kind: .preference,
                    status: st,
                    label: "Soft preference",
                    requestedValue: line,
                    evidence: hit ? "Preference appears in published copy." : nil,
                    questionForProvider: st == .optionalUnknown ? "If relevant, could you comment on: \(line)?" : nil,
                    priority: 14,
                    source: "canonicalIntent"
                )
            )
        }

        if let loc = facets.locationText?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty,
           facets.searchIntent == nil {
            if ExchangeSecondHalfLocationResolver.suppressesRequesterLocationGaps(locationFact)
                || (locationFact.isSatisfiedForCurrentStep
                    && ExchangeSecondHalfLocationResolver.isPoisonedLocationText(loc)) {
                skippedLocationGaps += 1
            } else {
            let tokens = Self.normalizedTokens(loc) + [loc.lowercased()]
            let regionTags = (offer?.regionTags ?? []) + (profile?.regionTags ?? [])
            let tagHay = regionTags.joined(separator: " ").lowercased()
            let hit = Self.haystackContainsTokens(hay + " " + tagHay, tokens: tokens)
            let st: ExchangeRequesterIntentGap.Status = hit ? .satisfied : .unknown
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(.region, loc),
                    kind: .region,
                    status: st,
                    label: "Region (facets)",
                    requestedValue: loc,
                    evidence: hit ? "Location appears consistent with published regions." : nil,
                    questionForProvider: st == .unknown ? "Can you confirm service coverage for \(loc)?" : nil,
                    priority: st == .unknown ? 3 : 20,
                    source: "canonicalIntent"
                )
            )
            }
        }

        return out
    }

    private static func applyLocationFactConsolidation(
        gaps: [ExchangeRequesterIntentGap],
        locationFact: ExchangeSecondHalfLocationFact,
        skippedLocationGaps: inout Int
    ) -> [ExchangeRequesterIntentGap] {
        var filtered = gaps

        if ExchangeSecondHalfLocationResolver.suppressesRequesterLocationGaps(locationFact) {
            let before = filtered.count
            filtered.removeAll {
                ExchangeSecondHalfLocationResolver.isRequesterLocationIntentGap($0, locationFact: locationFact)
                    || isLocationNoiseGap($0)
            }
            skippedLocationGaps += max(0, before - filtered.count)
        } else if locationFact.isSatisfiedForCurrentStep {
            let before = filtered.count
            filtered.removeAll { isLocationNoiseGap($0) }
            skippedLocationGaps += max(0, before - filtered.count)
        }

        if locationFact.shouldAskClarification {
            filtered.removeAll { isLocationNoiseGap($0) }
            if !filtered.contains(where: { $0.stableKey == Self.searchAreaClarificationKey }) {
                filtered.append(Self.searchAreaClarificationGap(question: locationFact.clarificationQuestion))
            }
        }

        return dedupeLocationGaps(filtered, locationFact: locationFact)
    }

    private static let searchAreaClarificationKey = "region|search-area-needed"

    private static func searchAreaClarificationGap(question: String?) -> ExchangeRequesterIntentGap {
        let prompt = question ?? "What city or area should I search in?"
        return ExchangeRequesterIntentGap(
            stableKey: searchAreaClarificationKey,
            kind: .region,
            status: .unknown,
            label: "Search area",
            requestedValue: prompt,
            evidence: nil,
            questionForProvider: nil,
            priority: 0,
            source: "secondHalfLocation"
        )
    }

    private static func isLocationManagedGap(_ gap: ExchangeRequesterIntentGap) -> Bool {
        gap.source == "secondHalfLocation" || gap.label == "Search area"
    }

    private static func isLocationNoiseGap(_ gap: ExchangeRequesterIntentGap) -> Bool {
        if gap.source == "secondHalfLocation" { return false }
        let requested = gap.requestedValue.lowercased()
        if ExchangeSecondHalfLocationResolver.isPoisonedMissingFactLine(gap.requestedValue) {
            return true
        }
        if gap.kind == .region,
           ExchangeSecondHalfLocationResolver.isPoisonedLocationText(gap.requestedValue) {
            return true
        }
        if gap.label.lowercased().contains("hard requirement"),
           requested.contains("locationtext") {
            return true
        }
        if gap.label.lowercased().contains("soft preference"),
           requested.hasPrefix("location:") {
            return true
        }
        return false
    }

    private static func dedupeLocationGaps(
        _ gaps: [ExchangeRequesterIntentGap],
        locationFact: ExchangeSecondHalfLocationFact
    ) -> [ExchangeRequesterIntentGap] {
        var regionGaps = gaps.filter { $0.kind == .region }
        let nonRegion = gaps.filter { $0.kind != .region }
        guard regionGaps.count > 1 else { return gaps }

        if locationFact.shouldAskClarification {
            regionGaps = regionGaps.filter { $0.stableKey == searchAreaClarificationKey }
        } else if ExchangeSecondHalfLocationResolver.suppressesRequesterLocationGaps(locationFact) {
            regionGaps = regionGaps.filter {
                !ExchangeSecondHalfLocationResolver.isRequesterLocationIntentGap($0, locationFact: locationFact)
            }
        } else if locationFact.isSatisfiedForCurrentStep {
            regionGaps = []
        } else {
            regionGaps = Array(regionGaps.prefix(1))
        }

        return nonRegion + regionGaps
    }

    private func gapsFromMatch(_ match: ExchangeMatch?) -> [ExchangeRequesterIntentGap] {
        guard let match else { return [] }
        var out: [ExchangeRequesterIntentGap] = []
        for c in match.cautions {
            let summary = c.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { continue }
            if RequesterInquiryQuestionNormalizer.isInternalDraftScaffold(summary) { continue }
            let lower = summary.lowercased()
            let kind: ExchangeRequesterIntentGap.Kind
            switch c.kind {
            case .location, .offerMismatch:
                kind = .region
            case .timing, .unclearAvailability:
                kind = .timing
            case .priceMismatch:
                kind = .budget
            default:
                kind = .other
            }
            let status: ExchangeRequesterIntentGap.Status =
                lower.contains("mismatch") || c.kind == .priceMismatch || c.kind == .offerMismatch ? .mismatch : .unknown
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: Self.key(kind, "match:\(c.kind.rawValue):\(summary.prefix(80))"),
                    kind: kind,
                    status: status,
                    label: "Match caution",
                    requestedValue: summary,
                    evidence: "Fit engine caution on selected candidate.",
                    questionForProvider: nil,
                    priority: status == .mismatch ? 0 : 4,
                    source: "matchCaution"
                )
            )
        }
        return out
    }

    private func gapsFromLLMCompare(
        _ compare: ExchangeRequesterMatchCompareResult?,
        existingKeys: Set<String>
    ) -> [ExchangeRequesterIntentGap] {
        guard let compare else { return [] }
        var out: [ExchangeRequesterIntentGap] = []
        for line in compare.missingFacts.prefix(12) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if ExchangeSecondHalfLocationResolver.isPoisonedMissingFactLine(trimmed) {
                continue
            }
            let key = Self.key(.other, "llm:\(trimmed.prefix(120))")
            guard !existingKeys.contains(key) else { continue }
            out.append(
                ExchangeRequesterIntentGap(
                    stableKey: key,
                    kind: .other,
                    status: .unknown,
                    label: "Compare gap",
                    requestedValue: trimmed,
                    evidence: nil,
                    questionForProvider: trimmed.hasSuffix("?") ? trimmed : "Could you clarify: \(trimmed)?",
                    priority: 5,
                    source: "llmCompare"
                )
            )
        }
        return out
    }

    // MARK: - Dedupe / combine

    private static func key(_ kind: ExchangeRequesterIntentGap.Kind, _ value: String) -> String {
        let v = value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(120)
        return "\(kind.rawValue)|\(v)"
    }

    private static func dedupeGaps(_ gaps: [ExchangeRequesterIntentGap]) -> [ExchangeRequesterIntentGap] {
        var seen = Set<String>()
        var out: [ExchangeRequesterIntentGap] = []
        for g in gaps {
            guard seen.insert(g.stableKey).inserted else { continue }
            out.append(g)
        }
        return out
    }

    private static func buildCombinedProviderQuestion(
        gaps: [ExchangeRequesterIntentGap],
        compare: ExchangeRequesterMatchCompareResult?,
        hasAnchoredProviderSurface: Bool
    ) -> String? {
        let actionable = gaps
            .filter { $0.status == .unknown || $0.status == .mismatch }
            .sorted { $0.priority < $1.priority }

        var sentences: [String] = []
        for g in actionable.prefix(4) {
            if let q = g.questionForProvider, !q.isEmpty {
                if !hasAnchoredProviderSurface,
                   ExchangeSecondHalfLocationResolver.isProviderServeLocationQuestion(q) {
                    continue
                }
                sentences.append(q)
            }
        }

        if let pq = compare?.providerQuestions {
            for q in pq.prefix(2) {
                let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { continue }
                if !hasAnchoredProviderSurface,
                   ExchangeSecondHalfLocationResolver.isProviderServeLocationQuestion(t) {
                    continue
                }
                if !sentences.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                    sentences.append(t)
                }
            }
        }

        sentences = ExchangeSecondHalfLocationResolver.filterProviderQuestionsWithoutSurface(
            sentences,
            hasAnchoredProviderSurface: hasAnchoredProviderSurface
        )

        guard !sentences.isEmpty else { return nil }
        if sentences.count == 1 { return sentences[0] }
        return sentences.joined(separator: " ")
    }
}
