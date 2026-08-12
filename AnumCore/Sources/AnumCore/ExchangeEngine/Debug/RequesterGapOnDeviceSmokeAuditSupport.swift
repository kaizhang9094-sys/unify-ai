#if DEBUG
import Foundation

// MARK: - Fixtures

public enum RequesterGapOnDeviceSmokeAuditFixtures {
    public struct Fixture: Sendable, Hashable {
        public var id: String
        public var langCategory: String
        public var userRequest: String
        public var objectType: String
        public var domainCategory: ExchangeIntentFacets.DomainCategory
        public var semanticConcepts: [String]
        public var broadRecallTokens: [String]
        public var placeText: String?
        public var timeText: String?
        public var offerTitle: String
        public var offerSummary: String
        public var profileHeadline: String?
        public var profileSummary: String?
        public var serviceAreaNote: String?
        public var expectedGapPhrase: String
        public var expectedQuestionContains: [String]
        public var shouldDetectGap: Bool
        public var shouldBeSatisfied: Bool

        public init(
            id: String,
            langCategory: String,
            userRequest: String,
            objectType: String,
            domainCategory: ExchangeIntentFacets.DomainCategory,
            semanticConcepts: [String],
            broadRecallTokens: [String],
            placeText: String? = nil,
            timeText: String? = nil,
            offerTitle: String,
            offerSummary: String,
            profileHeadline: String? = nil,
            profileSummary: String? = nil,
            serviceAreaNote: String? = nil,
            expectedGapPhrase: String,
            expectedQuestionContains: [String],
            shouldDetectGap: Bool,
            shouldBeSatisfied: Bool
        ) {
            self.id = id
            self.langCategory = langCategory
            self.userRequest = userRequest
            self.objectType = objectType
            self.domainCategory = domainCategory
            self.semanticConcepts = semanticConcepts
            self.broadRecallTokens = broadRecallTokens
            self.placeText = placeText
            self.timeText = timeText
            self.offerTitle = offerTitle
            self.offerSummary = offerSummary
            self.profileHeadline = profileHeadline
            self.profileSummary = profileSummary
            self.serviceAreaNote = serviceAreaNote
            self.expectedGapPhrase = expectedGapPhrase
            self.expectedQuestionContains = expectedQuestionContains
            self.shouldDetectGap = shouldDetectGap
            self.shouldBeSatisfied = shouldBeSatisfied
        }
    }

    public static let all: [Fixture] = [
        Fixture(
            id: "plumber.leak.missing",
            langCategory: "en/homeService",
            userRequest: "Find me a plumber in Austin for a leak repair this Saturday afternoon.",
            objectType: "plumber",
            domainCategory: .homeService,
            semanticConcepts: ["leak repair"],
            broadRecallTokens: ["leak repair"],
            placeText: "Austin",
            timeText: "this Saturday afternoon",
            offerTitle: "Licensed plumber in Austin",
            offerSummary: "General plumbing services, pipe installation, drain cleaning.",
            expectedGapPhrase: "leak repair",
            expectedQuestionContains: ["leak repair", "leak", "handle leaks", "leaks"],
            shouldDetectGap: true,
            shouldBeSatisfied: false
        ),
        Fixture(
            id: "plumber.leak.satisfied",
            langCategory: "en/homeService",
            userRequest: "Find me a plumber in Austin for a leak repair this Saturday afternoon.",
            objectType: "plumber",
            domainCategory: .homeService,
            semanticConcepts: ["leak repair"],
            broadRecallTokens: ["leak repair"],
            placeText: "Austin",
            timeText: "this Saturday afternoon",
            offerTitle: "Licensed plumber in Austin",
            offerSummary: "Specializing in leak repair, pipe leaks, and emergency leak service.",
            expectedGapPhrase: "leak repair",
            expectedQuestionContains: ["leak repair", "leak"],
            shouldDetectGap: false,
            shouldBeSatisfied: true
        ),
        Fixture(
            id: "contractor.kitchen_remodel.missing",
            langCategory: "zh-mixed/homeService",
            userRequest: "Need 装修 contractor in 北京 Chaoyang this 下周 for kitchen remodel.",
            objectType: "contractor",
            domainCategory: .homeService,
            semanticConcepts: ["kitchen remodel"],
            broadRecallTokens: ["kitchen remodel"],
            placeText: "北京 Chaoyang",
            timeText: "下周",
            offerTitle: "General contractor in Chaoyang",
            offerSummary: "Painting, flooring, small repairs.",
            expectedGapPhrase: "kitchen remodel",
            expectedQuestionContains: ["kitchen remodel", "kitchen", "remodel", "renovation"],
            shouldDetectGap: true,
            shouldBeSatisfied: false
        ),
        Fixture(
            id: "contractor.kitchen_remodel.satisfied",
            langCategory: "zh-mixed/homeService",
            userRequest: "Need 装修 contractor in 北京 Chaoyang this 下周 for kitchen remodel.",
            objectType: "contractor",
            domainCategory: .homeService,
            semanticConcepts: ["kitchen remodel"],
            broadRecallTokens: ["kitchen remodel"],
            placeText: "北京 Chaoyang",
            timeText: "下周",
            offerTitle: "Renovation contractor in Chaoyang",
            offerSummary: "Kitchen remodels, cabinet work, renovation planning.",
            expectedGapPhrase: "kitchen remodel",
            expectedQuestionContains: ["kitchen remodel", "kitchen"],
            shouldDetectGap: false,
            shouldBeSatisfied: true
        ),
        Fixture(
            id: "tutor.conversation.missing",
            langCategory: "en/professionalService",
            userRequest: "Remote Spanish tutor for conversational practice on weekday mornings EST.",
            objectType: "Spanish tutor",
            domainCategory: .professionalService,
            semanticConcepts: ["conversational practice"],
            broadRecallTokens: ["conversational practice"],
            timeText: "weekday mornings EST",
            offerTitle: "Spanish tutor",
            offerSummary: "Grammar, vocabulary, and homework help.",
            expectedGapPhrase: "conversational practice",
            expectedQuestionContains: [
                "conversational practice",
                "conversation practice",
                "speaking practice",
                "conversation"
            ],
            shouldDetectGap: true,
            shouldBeSatisfied: false
        ),
        Fixture(
            id: "tutor.conversation.satisfied",
            langCategory: "en/professionalService",
            userRequest: "Remote Spanish tutor for conversational practice on weekday mornings EST.",
            objectType: "Spanish tutor",
            domainCategory: .professionalService,
            semanticConcepts: ["conversational practice"],
            broadRecallTokens: ["conversational practice"],
            timeText: "weekday mornings EST",
            offerTitle: "Spanish tutor",
            offerSummary: "Conversation practice, speaking sessions, weekday morning availability.",
            expectedGapPhrase: "conversational practice",
            expectedQuestionContains: ["conversational practice", "conversation practice"],
            shouldDetectGap: false,
            shouldBeSatisfied: true
        ),
        Fixture(
            id: "electrician.check_circuit.missing",
            langCategory: "zh-mixed/homeService",
            userRequest: "上海 Pudong 周末 need a certified electrician 上门检查电路。",
            objectType: "electrician",
            domainCategory: .homeService,
            semanticConcepts: ["check circuit at home"],
            broadRecallTokens: ["check circuit at home"],
            placeText: "上海 Pudong",
            timeText: "周末",
            offerTitle: "Certified electrician in Pudong",
            offerSummary: "Wiring, outlets, breaker panels.",
            expectedGapPhrase: "check circuit",
            expectedQuestionContains: [
                "check circuit",
                "circuit inspection",
                "inspect circuit",
                "电路",
                "检查电路"
            ],
            shouldDetectGap: true,
            shouldBeSatisfied: false
        )
    ]
}

// MARK: - Artifact row

public struct RequesterGapOnDeviceSmokeAuditRow: Codable, Sendable, Hashable {
    public var id: String
    public var success: Bool
    public var sourceTask: String
    public var elapsedMs: Int?
    public var userRequest: String
    public var canonicalSearchIntentSummary: String
    public var candidateSurfaceSummary: String
    public var rawLLMOutputExact: String?
    public var parsedCompareSummary: String?
    public var llmProviderDirectedQuestions: [String]
    public var deterministicProviderDirectedQuestions: [String]
    public var finalProviderDirectedQuestions: [String]
    public var missingFacts: [String]
    /// Whether this fixture expects a task-specific missing confirmation (`shouldDetectGap`).
    public var expectedGap: Bool
    public var detectedExpectedGap: Bool
    /// Mirrors final guarded production false positive (success uses this, not raw).
    public var falsePositiveGapOnSatisfiedCase: Bool
    /// Raw LLM providerQuestions before output guard (diagnostics only).
    public var rawFalsePositiveGapOnSatisfiedCase: Bool
    public var finalFalsePositiveGapOnSatisfiedCase: Bool
    public var rawLlmProviderDirectedQuestions: [String]
    public var hallucinatedCommitmentDetected: Bool
    public var failureReason: String?
    public var promptPreview: String?
    public var promptHash: String?

    public init(
        id: String,
        success: Bool,
        sourceTask: String,
        elapsedMs: Int?,
        userRequest: String,
        canonicalSearchIntentSummary: String,
        candidateSurfaceSummary: String,
        rawLLMOutputExact: String?,
        parsedCompareSummary: String?,
        llmProviderDirectedQuestions: [String],
        deterministicProviderDirectedQuestions: [String],
        finalProviderDirectedQuestions: [String],
        missingFacts: [String],
        expectedGap: Bool,
        detectedExpectedGap: Bool,
        falsePositiveGapOnSatisfiedCase: Bool,
        rawFalsePositiveGapOnSatisfiedCase: Bool,
        finalFalsePositiveGapOnSatisfiedCase: Bool,
        rawLlmProviderDirectedQuestions: [String] = [],
        hallucinatedCommitmentDetected: Bool,
        failureReason: String?,
        promptPreview: String? = nil,
        promptHash: String? = nil
    ) {
        self.id = id
        self.success = success
        self.sourceTask = sourceTask
        self.elapsedMs = elapsedMs
        self.userRequest = userRequest
        self.canonicalSearchIntentSummary = canonicalSearchIntentSummary
        self.candidateSurfaceSummary = candidateSurfaceSummary
        self.rawLLMOutputExact = rawLLMOutputExact
        self.parsedCompareSummary = parsedCompareSummary
        self.llmProviderDirectedQuestions = llmProviderDirectedQuestions
        self.deterministicProviderDirectedQuestions = deterministicProviderDirectedQuestions
        self.finalProviderDirectedQuestions = finalProviderDirectedQuestions
        self.missingFacts = missingFacts
        self.expectedGap = expectedGap
        self.detectedExpectedGap = detectedExpectedGap
        self.falsePositiveGapOnSatisfiedCase = falsePositiveGapOnSatisfiedCase
        self.rawFalsePositiveGapOnSatisfiedCase = rawFalsePositiveGapOnSatisfiedCase
        self.finalFalsePositiveGapOnSatisfiedCase = finalFalsePositiveGapOnSatisfiedCase
        self.rawLlmProviderDirectedQuestions = rawLlmProviderDirectedQuestions
        self.hallucinatedCommitmentDetected = hallucinatedCommitmentDetected
        self.failureReason = failureReason
        self.promptPreview = promptPreview
        self.promptHash = promptHash
    }
}

// MARK: - Runner

public enum RequesterGapOnDeviceSmokeAuditSupport {
    public static let sourceTaskName = "requesterMatchCompare"

    public static func run(
        intelligenceProvider: OnDeviceExchangeIntelligenceProvider,
        styleProfile: ExchangeSecretaryStyleProfile = .default,
        pauseBetweenRowsNanoseconds: UInt64 = 600_000_000
    ) async -> [RequesterGapOnDeviceSmokeAuditRow] {
        var rows: [RequesterGapOnDeviceSmokeAuditRow] = []
        rows.reserveCapacity(RequesterGapOnDeviceSmokeAuditFixtures.all.count)

        for (index, fixture) in RequesterGapOnDeviceSmokeAuditFixtures.all.enumerated() {
            await RequesterGapSmokeAuditDebugTrace.shared.reset()

            let searchIntent = buildSearchIntent(from: fixture)
            let offer = buildOffer(from: fixture)
            let profile = buildProfile(from: fixture)
            let thread = buildThread(fixture: fixture, searchIntent: searchIntent)
            let offerSummary = pass2CompactOfferSummary(offer: offer)
            let profileSummary = pass2CompactProfileSummary(profile: profile)

            let deterministic = buildDeterministicOutputs(
                fixture: fixture,
                thread: thread,
                searchIntent: searchIntent,
                offer: offer,
                profile: profile,
                matchCompare: nil
            )

            let wall = CFAbsoluteTimeGetCurrent()
            let requirementsSummary = ExchangeRequesterCompareGroundingSummary.render(
                originalRequesterMessage: fixture.userRequest,
                searchIntent: searchIntent,
                thread: thread,
                facets: thread.facets
            )
            let compare = await intelligenceProvider.compareRequesterMatchToSurface(
                originalRequesterMessage: fixture.userRequest,
                selectedOfferSummary: offerSummary,
                selectedProfileSummary: profileSummary,
                counterpartyDisplayName: profile?.displayName,
                knownFacts: [],
                styleProfile: styleProfile,
                requesterRequirementsSummary: requirementsSummary
            )
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - wall) * 1000)
            let trace = await RequesterGapSmokeAuditDebugTrace.shared.currentSnapshot()

            let llmLines = trimmedNonEmpty(compare.providerQuestions)
            let rawLlmLines = trimmedNonEmpty(trace.rawParsedProviderQuestions)
            let compareSucceeded = !compare.reason.lowercased().contains("requester_match_compare_failed")
            let finalLines = resolvePass2DirectedLines(
                compare: compare,
                compareSucceeded: compareSucceeded,
                deterministicSeed: deterministic.providerDirectedQuestions
            )

            let evaluation = evaluateRow(
                fixture: fixture,
                compare: compare,
                rawLlmLines: rawLlmLines,
                llmLines: llmLines,
                deterministicLines: deterministic.providerDirectedQuestions,
                finalLines: finalLines,
                gapOutput: deterministic.gapOutput
            )

            let promptHash = trace.promptSentToLLMExact.map { stableHash($0) }
            let promptPreview = trace.promptSentToLLMExact.map { preview($0, max: 480) }

            let row = RequesterGapOnDeviceSmokeAuditRow(
                id: fixture.id,
                success: evaluation.success,
                sourceTask: sourceTaskName,
                elapsedMs: elapsedMs,
                userRequest: fixture.userRequest,
                canonicalSearchIntentSummary: canonicalSummary(searchIntent),
                candidateSurfaceSummary: candidateSummary(
                    offerSummary: offerSummary,
                    profileSummary: profileSummary
                ),
                rawLLMOutputExact: trace.rawLLMOutputExact,
                parsedCompareSummary: parsedCompareSummary(compare),
                llmProviderDirectedQuestions: llmLines,
                deterministicProviderDirectedQuestions: deterministic.providerDirectedQuestions,
                finalProviderDirectedQuestions: finalLines,
                missingFacts: compare.missingFacts,
                expectedGap: evaluation.expectedGap,
                detectedExpectedGap: evaluation.detectedExpectedGap,
                falsePositiveGapOnSatisfiedCase: evaluation.finalFalsePositiveGapOnSatisfiedCase,
                rawFalsePositiveGapOnSatisfiedCase: evaluation.rawFalsePositiveGapOnSatisfiedCase,
                finalFalsePositiveGapOnSatisfiedCase: evaluation.finalFalsePositiveGapOnSatisfiedCase,
                rawLlmProviderDirectedQuestions: rawLlmLines,
                hallucinatedCommitmentDetected: evaluation.hallucinatedCommitmentDetected,
                failureReason: evaluation.failureReason,
                promptPreview: promptPreview,
                promptHash: promptHash
            )
            rows.append(row)
            printSmokeAuditRow(row, index: index + 1, total: RequesterGapOnDeviceSmokeAuditFixtures.all.count)

            if index < RequesterGapOnDeviceSmokeAuditFixtures.all.count - 1,
               pauseBetweenRowsNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: pauseBetweenRowsNanoseconds)
            }
        }

        return rows
    }

    public static func writeJSONL(rows: [RequesterGapOnDeviceSmokeAuditRow], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = Data()
        for (idx, row) in rows.enumerated() {
            data.append(try encoder.encode(row))
            if idx < rows.count - 1 { data.append(Data("\n".utf8)) }
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Production-shaped summaries (mirrors ExchangeFacade pass-2 compact blocks)

    static func pass2CompactOfferSummary(offer: ExchangeOffer?) -> String? {
        guard let offer else { return nil }
        var parts: [String] = []
        let title = offer.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { parts.append(title) }
        if let summary = offer.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            parts.append(summary)
        }
        if let area = offer.commercialFacts.serviceAreaNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !area.isEmpty {
            parts.append("service area: \(area)")
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    static func pass2CompactProfileSummary(profile: ExchangePublicNodeProfile?) -> String? {
        guard let profile else { return nil }
        var parts: [String] = []
        if let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            parts.append(name)
        }
        if let headline = profile.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !headline.isEmpty {
            parts.append(headline)
        }
        parts.append("availability: \(profile.availability.rawValue)")
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    // MARK: - Fixture builders

    private static func buildSearchIntent(
        from fixture: RequesterGapOnDeviceSmokeAuditFixtures.Fixture
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        var places: [ExchangeIntentFacets.StructuredPlace] = []
        if let placeText = fixture.placeText?.trimmingCharacters(in: .whitespacesAndNewlines), !placeText.isEmpty {
            places.append(
                .init(
                    normalizedText: placeText.lowercased(),
                    aliases: [placeText]
                )
            )
        }
        var timeConstraints: [ExchangeIntentFacets.StructuredTimeConstraint] = []
        if let timeText = fixture.timeText?.trimmingCharacters(in: .whitespacesAndNewlines), !timeText.isEmpty {
            timeConstraints.append(.init(kind: .flexible, text: timeText))
        }
        return ExchangeIntentFacets.ExchangeCanonicalSearchIntent(
            domainCategory: fixture.domainCategory,
            objectType: fixture.objectType,
            places: places,
            timeConstraints: timeConstraints,
            broadRecallTokens: fixture.broadRecallTokens,
            semanticConcepts: fixture.semanticConcepts,
            rawUserText: fixture.userRequest,
            extractionSource: .llmFlatSummary
        )
    }

    private static func buildOffer(
        from fixture: RequesterGapOnDeviceSmokeAuditFixtures.Fixture
    ) -> ExchangeOffer {
        let area = fixture.serviceAreaNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let commercial = ExchangeOffer.CommercialFacts(
            serviceAreaNote: area?.isEmpty == false ? area : nil
        )
        return ExchangeOffer(
            id: "smoke-\(fixture.id)-offer",
            nodeID: "smoke-node",
            title: fixture.offerTitle,
            summary: fixture.offerSummary,
            category: fixture.objectType,
            status: .active,
            visibility: .publicDiscoverable,
            commercialFacts: commercial
        )
    }

    private static func buildProfile(
        from fixture: RequesterGapOnDeviceSmokeAuditFixtures.Fixture
    ) -> ExchangePublicNodeProfile? {
        let headline = fixture.profileHeadline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let summary = fixture.profileSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !headline.isEmpty || !summary.isEmpty else { return nil }
        return ExchangePublicNodeProfile(
            id: "smoke-\(fixture.id)-profile",
            nodeID: "smoke-node",
            displayName: "Smoke Provider",
            headline: headline.isEmpty ? nil : headline,
            summary: summary.isEmpty ? nil : summary,
            visibility: .discoverable
        )
    }

    private static func buildThread(
        fixture: RequesterGapOnDeviceSmokeAuditFixtures.Fixture,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> ExchangeThread {
        let intent = ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "smoke-\(fixture.id)",
            objective: fixture.userRequest
        )
        let facets = ExchangeIntentFacets(searchIntent: searchIntent)
        return ExchangeThread(
            mode: .transactional,
            intent: intent,
            posture: ExchangePosture(),
            facets: facets,
            state: .matchFound(
                .init(
                    candidateCount: 1,
                    summary: "smoke-audit match",
                    selectedOfferID: "smoke-\(fixture.id)-offer"
                )
            )
        )
    }

    private struct DeterministicOutputs {
        var gapOutput: ExchangeRequesterIntentGapReducer.Output
        var providerDirectedQuestions: [String]
    }

    private static func buildDeterministicOutputs(
        fixture: RequesterGapOnDeviceSmokeAuditFixtures.Fixture,
        thread: ExchangeThread,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent,
        offer: ExchangeOffer,
        profile: ExchangePublicNodeProfile?,
        matchCompare: ExchangeRequesterMatchCompareResult?
    ) -> DeterministicOutputs {
        let gapOutput = ExchangeRequesterIntentGapReducer().reduce(
            input: .init(
                thread: thread,
                searchIntent: searchIntent,
                offer: offer,
                publicProfile: profile,
                operatingMemory: .empty,
                matchCompare: matchCompare
            )
        )
        let agencyContext = ExchangeAgencyContextBuilder.buildRequesterContext(
            threadID: thread.id,
            selectedOfferID: offer.id,
            userIntent: fixture.userRequest,
            publicProfile: profile,
            offer: offer,
            operatingMemory: .empty,
            intentGaps: gapOutput.gaps,
            intentGapCombinedClarificationQuestion: gapOutput.combinedProviderQuestion
        )
        let decisionNeeds = ExchangeRequesterDecisionNeedsEngine().evaluate(context: agencyContext)
        let execution = ExchangeSecondHalfExecutionContext(
            threadID: thread.id,
            role: .requester,
            currentState: .awaitingProviderClarification
        )
        let directed = ExchangeAgencyDraftPacketBuilder.resolvedProviderDirectedQuestionLines(
            executionContext: execution,
            pass2DirectedOverride: nil,
            agencyContext: agencyContext,
            decisionNeeds: decisionNeeds
        ) ?? []
        return DeterministicOutputs(
            gapOutput: gapOutput,
            providerDirectedQuestions: directed
        )
    }

    /// Mirrors `ExchangeFacade.resolveRequesterMatchCompareForPass2` (LLM-primary; no gap-template override on success).
    private static func resolvePass2DirectedLines(
        compare: ExchangeRequesterMatchCompareResult,
        compareSucceeded: Bool,
        deterministicSeed: [String]
    ) -> [String] {
        let failed = compare.reason.lowercased().contains("requester_match_compare_failed")
        if compareSucceeded && !failed {
            return compare.providerQuestions
        }
        if failed {
            return Array(deterministicSeed.prefix(6))
        }
        return []
    }

    // MARK: - Evaluation

    public struct RowEvaluation: Sendable {
        public var success: Bool
        public var expectedGap: Bool
        public var detectedExpectedGap: Bool
        public var rawFalsePositiveGapOnSatisfiedCase: Bool
        public var finalFalsePositiveGapOnSatisfiedCase: Bool
        public var hallucinatedCommitmentDetected: Bool
        public var failureReason: String?
    }

    /// DEBUG unit-test entry point mirroring on-device smoke audit scoring.
    public static func evaluateRow(
        fixture: RequesterGapOnDeviceSmokeAuditFixtures.Fixture,
        compare: ExchangeRequesterMatchCompareResult,
        rawLlmLines: [String],
        llmLines: [String],
        deterministicLines: [String],
        finalLines: [String],
        gapOutput: ExchangeRequesterIntentGapReducer.Output
    ) -> RowEvaluation {
        let compareFailed = compare.reason.lowercased().contains("requester_match_compare_failed")
        let gapSignalHaystack = gapSignalHaystack(
            compare: compare,
            llmLines: llmLines,
            deterministicLines: deterministicLines,
            finalLines: finalLines,
            gapOutput: gapOutput
        )
        let providerFacingHaystack = providerFacingHaystack(
            llmLines: llmLines,
            deterministicLines: deterministicLines,
            finalLines: finalLines,
            gapOutput: gapOutput
        )

        let expectedGap = fixture.shouldDetectGap
        let detectedExpectedGap = mentionsExpectedGap(fixture: fixture, haystack: gapSignalHaystack)
        let rawHaystack = rawLlmLines.joined(separator: "\n").lowercased()
        let finalHaystack = finalLines.joined(separator: "\n").lowercased()
        let rawTaskGapSignal = hasTaskGapSignal(
            fixture: fixture,
            gapSignalHaystack: rawHaystack,
            gapOutput: gapOutput,
            includeDeterministicGapQuestions: false
        )
        let finalTaskGapSignal = hasTaskGapSignal(
            fixture: fixture,
            gapSignalHaystack: finalHaystack,
            gapOutput: gapOutput,
            includeDeterministicGapQuestions: true
        )
        let genericOnly = isGenericInformationAskOnly(haystack: gapSignalHaystack, fixture: fixture)
        let hallucinated = detectsHallucinatedCommitment(haystack: providerFacingHaystack)
        let internalLeak = detectsInternalLeak(haystack: providerFacingHaystack)

        let rawFalsePositive = fixture.shouldBeSatisfied && rawTaskGapSignal
        let finalFalsePositive = fixture.shouldBeSatisfied && finalTaskGapSignal

        var failureReasons: [String] = []
        if compareFailed {
            failureReasons.append("compareFailed:\(compare.reason)")
        }
        if expectedGap {
            if !detectedExpectedGap {
                failureReasons.append("expectedGapNotDetected")
            }
            if genericOnly {
                failureReasons.append("genericAskOnly")
            }
        }
        if finalFalsePositive {
            failureReasons.append("finalFalsePositiveGapOnSatisfiedCase")
        }
        if rawFalsePositive && !finalFalsePositive {
            // Diagnostic only — raw LLM re-ask removed by guard; do not fail success.
        }
        if hallucinated {
            failureReasons.append("hallucinatedCommitment")
        }
        if internalLeak {
            failureReasons.append("internalTermLeak")
        }

        let success = failureReasons.isEmpty
        return RowEvaluation(
            success: success,
            expectedGap: expectedGap,
            detectedExpectedGap: detectedExpectedGap,
            rawFalsePositiveGapOnSatisfiedCase: rawFalsePositive,
            finalFalsePositiveGapOnSatisfiedCase: finalFalsePositive,
            hallucinatedCommitmentDetected: hallucinated,
            failureReason: failureReasons.isEmpty ? nil : failureReasons.joined(separator: ";")
        )
    }

    /// Compare output + provider-directed lines + unsatisfied intent gaps only (excludes satisfied facet values).
    private static func gapSignalHaystack(
        compare: ExchangeRequesterMatchCompareResult,
        llmLines: [String],
        deterministicLines: [String],
        finalLines: [String],
        gapOutput: ExchangeRequesterIntentGapReducer.Output
    ) -> String {
        var parts: [String] = []
        parts.append(contentsOf: compare.missingFacts)
        parts.append(contentsOf: llmLines)
        parts.append(contentsOf: deterministicLines)
        parts.append(contentsOf: finalLines)
        if let combined = gapOutput.combinedProviderQuestion {
            parts.append(combined)
        }
        for gap in gapOutput.gaps where gap.status != .satisfied {
            if let q = gap.questionForProvider { parts.append(q) }
            parts.append(gap.label)
            parts.append(gap.requestedValue)
        }
        return parts.joined(separator: "\n").lowercased()
    }

    /// Provider-facing question lines only (for leak / hallucination checks).
    private static func providerFacingHaystack(
        llmLines: [String],
        deterministicLines: [String],
        finalLines: [String],
        gapOutput: ExchangeRequesterIntentGapReducer.Output
    ) -> String {
        var parts: [String] = []
        parts.append(contentsOf: llmLines)
        parts.append(contentsOf: deterministicLines)
        parts.append(contentsOf: finalLines)
        if let combined = gapOutput.combinedProviderQuestion {
            parts.append(combined)
        }
        for gap in gapOutput.gaps where gap.status != .satisfied {
            if let q = gap.questionForProvider { parts.append(q) }
        }
        return parts.joined(separator: "\n").lowercased()
    }

    private static func mentionsExpectedGap(
        fixture: RequesterGapOnDeviceSmokeAuditFixtures.Fixture,
        haystack: String
    ) -> Bool {
        let phrase = fixture.expectedGapPhrase.lowercased()
        if !phrase.isEmpty, haystack.contains(phrase) { return true }
        return fixture.expectedQuestionContains.contains { needle in
            let n = needle.lowercased()
            return !n.isEmpty && haystack.contains(n)
        }
    }

    private static func hasTaskGapSignal(
        fixture: RequesterGapOnDeviceSmokeAuditFixtures.Fixture,
        gapSignalHaystack: String,
        gapOutput: ExchangeRequesterIntentGapReducer.Output,
        includeDeterministicGapQuestions: Bool
    ) -> Bool {
        if mentionsExpectedGap(fixture: fixture, haystack: gapSignalHaystack) { return true }
        guard includeDeterministicGapQuestions else { return false }
        return gapOutput.gaps.contains { gap in
            gap.label.lowercased().contains("service") && gap.status != .satisfied
        }
    }

    private static func isGenericInformationAskOnly(
        haystack: String,
        fixture: RequesterGapOnDeviceSmokeAuditFixtures.Fixture
    ) -> Bool {
        let genericNeedles = [
            "need more information",
            "more information",
            "additional information",
            "clarify your request",
            "could you share more"
        ]
        let hasGeneric = genericNeedles.contains { haystack.contains($0) }
        guard hasGeneric else { return false }
        return !mentionsExpectedGap(fixture: fixture, haystack: haystack)
    }

    private static let hallucinationNeedles: [String] = [
        "confirmed availability",
        "we can confirm",
        "i can confirm your",
        "booked for",
        "scheduled for you",
        "final price is",
        "quoted price",
        "will arrive at",
        "guaranteed availability"
    ]

    private static let internalLeakNeedles: [String] = [
        "canonicalintent",
        "canonical intent",
        "intent gap",
        "services matching",
        "unknown service gap",
        "service gap"
    ]

    private static func detectsHallucinatedCommitment(haystack: String) -> Bool {
        hallucinationNeedles.contains { haystack.contains($0) }
    }

    private static func detectsInternalLeak(haystack: String) -> Bool {
        internalLeakNeedles.contains { haystack.contains($0) }
    }

    // MARK: - Formatting / logging

    private static func canonicalSummary(_ intent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent) -> String {
        let concepts = intent.semanticConcepts.joined(separator: ", ")
        let recall = intent.broadRecallTokens.joined(separator: ", ")
        let places = intent.places.map(\.normalizedText).joined(separator: ", ")
        let times = intent.timeConstraints.map(\.text).joined(separator: ", ")
        return [
            "objectType=\(intent.objectType ?? "")",
            "domain=\(intent.domainCategory.rawValue)",
            "concepts=[\(concepts)]",
            "recall=[\(recall)]",
            "places=[\(places)]",
            "time=[\(times)]"
        ].joined(separator: " ")
    }

    private static func candidateSummary(offerSummary: String?, profileSummary: String?) -> String {
        [
            offerSummary.map { "offer=\($0)" },
            profileSummary.map { "profile=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " | ")
    }

    private static func parsedCompareSummary(_ compare: ExchangeRequesterMatchCompareResult) -> String {
        let qs = compare.providerQuestions.joined(separator: " | ")
        let missing = compare.missingFacts.joined(separator: " | ")
        return "shouldAsk=\(compare.shouldAskProvider) missing=[\(missing)] questions=[\(qs)] reason=\(compare.reason)"
    }

    private static func trimmedNonEmpty(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func preview(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "…"
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }

    private static func firstRelevantProviderQuestion(for row: RequesterGapOnDeviceSmokeAuditRow) -> String {
        row.finalProviderDirectedQuestions.first
            ?? row.llmProviderDirectedQuestions.first
            ?? row.deterministicProviderDirectedQuestions.first
            ?? ""
    }

    private static func printSmokeAuditRow(
        _ row: RequesterGapOnDeviceSmokeAuditRow,
        index: Int,
        total: Int
    ) {
        let question = firstRelevantProviderQuestion(for: row)
        let qSnippet = question.isEmpty ? "—" : "\"\(question)\""
        print(
            "[RequesterGapSmokeAudit] \(index)/\(total) id=\(row.id) " +
            "expectedGap=\(row.expectedGap) " +
            "detectedExpectedGap=\(row.detectedExpectedGap) " +
            "success=\(row.success) elapsedMs=\(row.elapsedMs ?? -1) " +
            "question=\(qSnippet) " +
            "rawFalsePositive=\(row.rawFalsePositiveGapOnSatisfiedCase) " +
            "finalFalsePositive=\(row.finalFalsePositiveGapOnSatisfiedCase)"
        )
        if let reason = row.failureReason, !row.success {
            print("[RequesterGapSmokeAudit]   failure=\(reason)")
        }
    }
}
#endif
