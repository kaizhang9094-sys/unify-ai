#if DEBUG
import Foundation

// MARK: - Fixtures

public enum RequesterComposeOnDeviceSmokeAuditFixtures {
    public struct Fixture: Sendable, Hashable {
        public var id: String
        public var userRequest: String
        public var objectType: String
        public var domainCategory: ExchangeIntentFacets.DomainCategory
        public var semanticConcepts: [String]
        public var broadRecallTokens: [String]
        public var placeText: String?
        public var timeText: String?
        public var offerTitle: String
        public var offerSummary: String
        public var pass2LLMCompareSucceeded: Bool
        public var providerDirectedOverride: [String]
        /// When set, accepted bodies should contain this substance (lowercased match).
        public var expectedDirectedSubstance: String?
        /// When set, replaces policy-derived outbound compose contract (fixture control).
        public var composeContractOverride: RequesterOutboundComposeContract?
        public var queryIntentClass: ExchangeIntent.QueryIntentClass
        public var surfacePreference: ExchangeIntent.SurfacePreference

        public init(
            id: String,
            userRequest: String,
            objectType: String,
            domainCategory: ExchangeIntentFacets.DomainCategory,
            semanticConcepts: [String],
            broadRecallTokens: [String],
            placeText: String? = nil,
            timeText: String? = nil,
            offerTitle: String,
            offerSummary: String,
            pass2LLMCompareSucceeded: Bool,
            providerDirectedOverride: [String],
            expectedDirectedSubstance: String? = nil,
            composeContractOverride: RequesterOutboundComposeContract? = nil,
            queryIntentClass: ExchangeIntent.QueryIntentClass = .offerSearch,
            surfacePreference: ExchangeIntent.SurfacePreference = .offer
        ) {
            self.id = id
            self.userRequest = userRequest
            self.objectType = objectType
            self.domainCategory = domainCategory
            self.semanticConcepts = semanticConcepts
            self.broadRecallTokens = broadRecallTokens
            self.placeText = placeText
            self.timeText = timeText
            self.offerTitle = offerTitle
            self.offerSummary = offerSummary
            self.pass2LLMCompareSucceeded = pass2LLMCompareSucceeded
            self.providerDirectedOverride = providerDirectedOverride
            self.expectedDirectedSubstance = expectedDirectedSubstance
            self.composeContractOverride = composeContractOverride
            self.queryIntentClass = queryIntentClass
            self.surfacePreference = surfacePreference
        }
    }

    public static let all: [Fixture] = [
        Fixture(
            id: "satisfied.empty_directed",
            userRequest: "Find me a plumber in Austin for a leak repair this Saturday afternoon.",
            objectType: "plumber",
            domainCategory: .homeService,
            semanticConcepts: ["leak repair"],
            broadRecallTokens: ["leak repair"],
            placeText: "Austin",
            timeText: "this Saturday afternoon",
            offerTitle: "Licensed plumber in Austin",
            offerSummary: "Specializing in leak repair, pipe leaks, and emergency leak service.",
            pass2LLMCompareSucceeded: true,
            providerDirectedOverride: []
        ),
        Fixture(
            id: "missing.directed.no_enrichment",
            userRequest: "Find me a plumber in Austin for a leak repair this Saturday afternoon.",
            objectType: "plumber",
            domainCategory: .homeService,
            semanticConcepts: ["leak repair"],
            broadRecallTokens: ["leak repair"],
            placeText: "Austin",
            timeText: "this Saturday afternoon",
            offerTitle: "Licensed plumber in Austin",
            offerSummary: "General plumbing services, pipe installation, drain cleaning.",
            pass2LLMCompareSucceeded: true,
            providerDirectedOverride: ["Do you handle leak repairs?"],
            expectedDirectedSubstance: "leak repair",
            composeContractOverride: RequesterOutboundComposeContract(
                routingSurface: "provider/offer",
                requiredProviderQuestionLines: ["Do you handle leak repairs?"],
                allowedEnrichmentDimensions: [],
                allowedEnrichmentHints: [],
                maxOptionalEnrichmentCount: 0
            )
        ),
        Fixture(
            id: "missing.directed.pricing_enrichment_allowed",
            userRequest: "Find me a plumber in Austin for a leak repair this Saturday afternoon.",
            objectType: "plumber",
            domainCategory: .homeService,
            semanticConcepts: ["leak repair"],
            broadRecallTokens: ["leak repair"],
            placeText: "Austin",
            timeText: "this Saturday afternoon",
            offerTitle: "Licensed plumber in Austin",
            offerSummary: "General plumbing services, pipe installation, drain cleaning.",
            pass2LLMCompareSucceeded: true,
            providerDirectedOverride: ["Do you handle leak repairs?"],
            expectedDirectedSubstance: "leak repair",
            composeContractOverride: RequesterOutboundComposeContract(
                routingSurface: "provider/offer",
                requiredProviderQuestionLines: ["Do you handle leak repairs?"],
                allowedEnrichmentDimensions: [.pricingProcess],
                allowedEnrichmentHints: [RequesterOutboundEnrichmentPolicy.hint(for: .pricingProcess)],
                maxOptionalEnrichmentCount: 1
            )
        ),
        Fixture(
            id: "missing.directed.credential_forbidden",
            userRequest: "Find me a plumber in Austin for a leak repair this Saturday afternoon.",
            objectType: "plumber",
            domainCategory: .homeService,
            semanticConcepts: ["leak repair"],
            broadRecallTokens: ["leak repair"],
            placeText: "Austin",
            timeText: "this Saturday afternoon",
            offerTitle: "Licensed plumber in Austin",
            offerSummary: "General plumbing services, pipe installation, drain cleaning.",
            pass2LLMCompareSucceeded: true,
            providerDirectedOverride: ["Do you handle leak repairs?"],
            expectedDirectedSubstance: "leak repair",
            composeContractOverride: RequesterOutboundComposeContract(
                routingSurface: "provider/offer",
                requiredProviderQuestionLines: ["Do you handle leak repairs?"],
                allowedEnrichmentDimensions: [.pricingProcess],
                allowedEnrichmentHints: [RequesterOutboundEnrichmentPolicy.hint(for: .pricingProcess)],
                maxOptionalEnrichmentCount: 1
            )
        ),
        Fixture(
            id: "social.tennis.no_pricing",
            userRequest: "Find people nearby who want a tennis partner for weekday evenings.",
            objectType: "people",
            domainCategory: .general,
            semanticConcepts: ["tennis partner"],
            broadRecallTokens: ["tennis partner"],
            timeText: "weekday evenings",
            offerTitle: "Weekend tennis group",
            offerSummary: "Casual doubles and weekday evening meetups.",
            pass2LLMCompareSucceeded: true,
            providerDirectedOverride: [],
            composeContractOverride: RequesterOutboundComposeContract(
                routingSurface: "social/affinity",
                requiredProviderQuestionLines: [],
                allowedEnrichmentDimensions: [],
                allowedEnrichmentHints: [],
                maxOptionalEnrichmentCount: 0
            ),
            queryIntentClass: .socialAffinitySearch,
            surfacePreference: .affinity
        )
    ]
}

// MARK: - Row

public struct RequesterComposeOnDeviceSmokeAuditRow: Codable, Sendable, Hashable {
    public var id: String
    public var success: Bool
    public var accepted: Bool
    public var inventedQuestion: Bool
    public var preservedDirected: Bool
    public var extraDiligence: Bool
    public var elapsedMs: Int?
    public var body: String
    public var rejectionReasons: [String]
    public var pass2LLMCompareSucceeded: Bool
    public var providerDirectedQuestionLines: [String]
    public var failureReason: String?
    public var outboundComposeContractPresent: Bool
    public var allowedEnrichmentDimensions: [String]
    public var allowedEnrichmentHints: [String]
    public var requiredDirectedCount: Int
    public var enrichmentAllowed: Bool
    public var enrichmentDetectedInBody: Bool

    public init(
        id: String,
        success: Bool,
        accepted: Bool,
        inventedQuestion: Bool,
        preservedDirected: Bool,
        extraDiligence: Bool,
        elapsedMs: Int?,
        body: String,
        rejectionReasons: [String],
        pass2LLMCompareSucceeded: Bool,
        providerDirectedQuestionLines: [String],
        failureReason: String? = nil,
        outboundComposeContractPresent: Bool = false,
        allowedEnrichmentDimensions: [String] = [],
        allowedEnrichmentHints: [String] = [],
        requiredDirectedCount: Int = 0,
        enrichmentAllowed: Bool = false,
        enrichmentDetectedInBody: Bool = false
    ) {
        self.id = id
        self.success = success
        self.accepted = accepted
        self.inventedQuestion = inventedQuestion
        self.preservedDirected = preservedDirected
        self.extraDiligence = extraDiligence
        self.elapsedMs = elapsedMs
        self.body = body
        self.rejectionReasons = rejectionReasons
        self.pass2LLMCompareSucceeded = pass2LLMCompareSucceeded
        self.providerDirectedQuestionLines = providerDirectedQuestionLines
        self.failureReason = failureReason
        self.outboundComposeContractPresent = outboundComposeContractPresent
        self.allowedEnrichmentDimensions = allowedEnrichmentDimensions
        self.allowedEnrichmentHints = allowedEnrichmentHints
        self.requiredDirectedCount = requiredDirectedCount
        self.enrichmentAllowed = enrichmentAllowed
        self.enrichmentDetectedInBody = enrichmentDetectedInBody
    }
}

// MARK: - Runner

public enum RequesterComposeOnDeviceSmokeAuditSupport {
    public static func run(
        intelligenceProvider: OnDeviceExchangeIntelligenceProvider,
        pauseBetweenRowsNanoseconds: UInt64 = 600_000_000
    ) async -> [RequesterComposeOnDeviceSmokeAuditRow] {
        var rows: [RequesterComposeOnDeviceSmokeAuditRow] = []
        rows.reserveCapacity(RequesterComposeOnDeviceSmokeAuditFixtures.all.count)

        for (index, fixture) in RequesterComposeOnDeviceSmokeAuditFixtures.all.enumerated() {
            var packet = buildAutonomousPacket(fixture: fixture)
            if let override = fixture.composeContractOverride {
                packet.outboundComposeContract = override
            }
            let wall = CFAbsoluteTimeGetCurrent()
            let compose = await intelligenceProvider.composeRequesterAutonomousOutbound(packet: packet)
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - wall) * 1000)

            let directed = packet.providerDirectedQuestionLines ?? []
            let contract = packet.outboundComposeContract
            let enrichmentDetected = detectsEnrichmentInBody(
                body: compose.body,
                directedLines: directed
            )
            let invented = detectsInventedProviderQuestion(
                body: compose.body,
                directedEmpty: directed.isEmpty
            )
            let extra = detectsExtraDiligenceBeyondDirected(
                body: compose.body,
                directedLines: directed
            )
            let preserved = detectsPreservedDirectedSubstance(
                body: compose.body,
                fixture: fixture,
                directedLines: directed
            )

            let evaluation = evaluateRow(
                fixture: fixture,
                compose: compose,
                inventedQuestion: invented,
                preservedDirected: preserved,
                extraDiligence: extra,
                enrichmentDetected: enrichmentDetected
            )

            let row = RequesterComposeOnDeviceSmokeAuditRow(
                id: fixture.id,
                success: evaluation.success,
                accepted: compose.accepted,
                inventedQuestion: invented,
                preservedDirected: preserved,
                extraDiligence: extra,
                elapsedMs: elapsedMs,
                body: compose.body,
                rejectionReasons: compose.rejectionReasons,
                pass2LLMCompareSucceeded: fixture.pass2LLMCompareSucceeded,
                providerDirectedQuestionLines: directed,
                failureReason: evaluation.failureReason,
                outboundComposeContractPresent: contract != nil,
                allowedEnrichmentDimensions: contract?.allowedEnrichmentDimensions.map(\.rawValue) ?? [],
                allowedEnrichmentHints: contract?.allowedEnrichmentHints ?? [],
                requiredDirectedCount: directed.count,
                enrichmentAllowed: !(contract?.allowedEnrichmentDimensions.isEmpty ?? true),
                enrichmentDetectedInBody: enrichmentDetected
            )
            rows.append(row)
            printSmokeAuditRow(row, index: index + 1, total: RequesterComposeOnDeviceSmokeAuditFixtures.all.count)

            if index < RequesterComposeOnDeviceSmokeAuditFixtures.all.count - 1,
               pauseBetweenRowsNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: pauseBetweenRowsNanoseconds)
            }
        }

        return rows
    }

    public static func writeJSONL(rows: [RequesterComposeOnDeviceSmokeAuditRow], to url: URL) throws {
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

    // MARK: - Packet build

    private static func buildAutonomousPacket(
        fixture: RequesterComposeOnDeviceSmokeAuditFixtures.Fixture
    ) -> RequesterClarificationDraftPacket {
        let searchIntent = buildSearchIntent(from: fixture)
        let thread = buildThread(fixture: fixture, searchIntent: searchIntent)
        let offer = buildOffer(from: fixture)
        let gapOutput = ExchangeRequesterIntentGapReducer().reduce(
            input: .init(
                thread: thread,
                searchIntent: searchIntent,
                offer: offer,
                operatingMemory: ExchangeStructuredOperatingMemory()
            )
        )
        let context = ExchangeAgencyContextBuilder.buildRequesterContext(
            threadID: thread.id,
            selectedOfferID: offer.id,
            userIntent: fixture.userRequest,
            offer: offer,
            operatingMemory: ExchangeStructuredOperatingMemory(),
            intentGaps: gapOutput.gaps,
            intentGapCombinedClarificationQuestion: gapOutput.combinedProviderQuestion
        )
        let decisionNeeds = ExchangeRequesterDecisionNeedsEngine().evaluate(context: context)
        let execution = ExchangeSecondHalfExecutionContext(
            threadID: thread.id,
            role: .requester,
            currentState: .requesterReview,
            selectedOfferID: offer.id
        )
        return ExchangeAgencyDraftPacketBuilder.buildRequesterAutonomousOutboundPacket(
            context: context,
            decisionNeeds: decisionNeeds,
            executionContext: execution,
            styleProfile: .default,
            composeMode: .askClarification,
            maxLength: 420,
            providerDirectedQuestionLinesResolved: fixture.providerDirectedOverride,
            pass2LLMCompareSucceeded: fixture.pass2LLMCompareSucceeded,
            facets: thread.facets,
            searchIntent: searchIntent
        )
    }

    // MARK: - Evaluation

    private struct RowEvaluation {
        var success: Bool
        var failureReason: String?
    }

    private static func evaluateRow(
        fixture: RequesterComposeOnDeviceSmokeAuditFixtures.Fixture,
        compose: ExchangeAgencyDraftRewriteEngine.ExchangeAgencyAutonomousComposeResult,
        inventedQuestion: Bool,
        preservedDirected: Bool,
        extraDiligence: Bool,
        enrichmentDetected: Bool
    ) -> RowEvaluation {
        let directedEmpty = fixture.providerDirectedOverride.isEmpty
        var failureReasons: [String] = []

        if fixture.id == "satisfied.empty_directed" {
            if compose.accepted {
                if inventedQuestion {
                    failureReasons.append("accepted_body_invented_provider_question")
                }
                if enrichmentDetected {
                    failureReasons.append("accepted_uncontracted_enrichment")
                }
            } else if !rejectionIndicatesCompareGuard(compose.rejectionReasons) {
                failureReasons.append("rejected_without_compare_guard:\(compose.rejectionReasons.joined(separator: ","))")
            }
        } else if fixture.id == "missing.directed.no_enrichment" {
            if compose.accepted {
                if enrichmentDetected {
                    failureReasons.append("accepted_pricing_without_enrichment_contract")
                }
                if extraDiligence {
                    failureReasons.append("extra_diligence_beyond_directed")
                }
            } else if !rejectionIndicatesCompareGuard(compose.rejectionReasons) {
                failureReasons.append("expected_rejection_for_uncontracted_pricing")
            }
        } else if fixture.id == "missing.directed.pricing_enrichment_allowed" {
            if !compose.accepted {
                failureReasons.append("expected_accept_with_pricing_enrichment:\(compose.rejectionReasons.joined(separator: ","))")
            } else if !preservedDirected {
                failureReasons.append("missing_directed_substance")
            }
        } else if fixture.id == "missing.directed.credential_forbidden" {
            if compose.accepted {
                failureReasons.append("accepted_credential_enrichment")
            } else if !rejectionIndicatesCompareGuard(compose.rejectionReasons) {
                failureReasons.append("expected_rejection_for_credential")
            }
        } else if fixture.id == "social.tennis.no_pricing" {
            if compose.accepted && (enrichmentDetected || inventedQuestion) {
                failureReasons.append("accepted_social_pricing_or_question")
            } else if !compose.accepted && !rejectionIndicatesCompareGuard(compose.rejectionReasons) {
                failureReasons.append("expected_rejection_for_social_pricing")
            }
        } else if directedEmpty {
            if compose.accepted && inventedQuestion {
                failureReasons.append("accepted_body_invented_provider_question")
            }
        } else if compose.accepted && extraDiligence {
            failureReasons.append("extra_diligence_beyond_directed")
        }

        if compose.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           compose.rejectionReasons.isEmpty {
            failureReasons.append("empty_body_without_reason")
        }

        return RowEvaluation(
            success: failureReasons.isEmpty,
            failureReason: failureReasons.isEmpty ? nil : failureReasons.joined(separator: ";")
        )
    }

    private static func rejectionIndicatesCompareGuard(_ reasons: [String]) -> Bool {
        let guardNeedles = [
            "invented_provider_question_when_compare_empty",
            "invented_provider_diligence_when_compare_empty",
            "extra_provider_diligence_beyond_compare_directed",
            "extra_provider_questions_beyond_compare_directed"
        ]
        let joined = reasons.joined(separator: " ").lowercased()
        return guardNeedles.contains { joined.contains($0) }
    }

    private static let inventedProviderQuestionNeedles: [String] = [
        "can you confirm",
        "could you confirm",
        "are you available",
        "what is your pricing",
        "pricing",
        "credential",
        "certification",
        "for this request",
        "for this job",
        "hardened timeline",
        "high-level cues",
        "underspecified publicly",
        "services matching"
    ]

    private static func detectsInventedProviderQuestion(body: String, directedEmpty: Bool) -> Bool {
        guard directedEmpty else { return false }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if trimmed.contains("?") { return true }
        return inventedProviderQuestionNeedles.contains { lower.contains($0) }
    }

    private static func detectsExtraDiligenceBeyondDirected(
        body: String,
        directedLines: [String]
    ) -> Bool {
        guard !directedLines.isEmpty else { return false }
        let lower = body.lowercased()
        let directedHaystack = directedLines.joined(separator: " ").lowercased()
        let extraNeedles = [
            "are you available",
            "what is your pricing",
            "certification",
            "credential",
            "for this request?",
            "for this job?"
        ]
        if extraNeedles.contains(where: { lower.contains($0) && !directedHaystack.contains($0) }) {
            return true
        }
        let questionMarkCount = body.filter { $0 == "?" }.count
        let directedQuestionMarks = directedLines.reduce(0) { $0 + $1.filter { $0 == "?" }.count }
        return questionMarkCount > directedQuestionMarks
    }

    private static func detectsPreservedDirectedSubstance(
        body: String,
        fixture: RequesterComposeOnDeviceSmokeAuditFixtures.Fixture,
        directedLines: [String]
    ) -> Bool {
        guard !directedLines.isEmpty else { return true }
        let lower = body.lowercased()
        if let substance = fixture.expectedDirectedSubstance?.lowercased(), !substance.isEmpty {
            if lower.contains(substance) { return true }
        }
        return directedLines.contains { line in
            let token = line.lowercased()
            return !token.isEmpty && lower.contains(token)
        }
    }

    // MARK: - Fixture builders

    private static func buildSearchIntent(
        from fixture: RequesterComposeOnDeviceSmokeAuditFixtures.Fixture
    ) -> ExchangeIntentFacets.ExchangeCanonicalSearchIntent {
        var places: [ExchangeIntentFacets.StructuredPlace] = []
        if let placeText = fixture.placeText?.trimmingCharacters(in: .whitespacesAndNewlines), !placeText.isEmpty {
            places.append(.init(normalizedText: placeText.lowercased(), aliases: [placeText]))
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

    private static func buildOffer(from fixture: RequesterComposeOnDeviceSmokeAuditFixtures.Fixture) -> ExchangeOffer {
        ExchangeOffer(
            id: "compose-smoke-\(fixture.id)-offer",
            nodeID: "compose-smoke-node",
            title: fixture.offerTitle,
            summary: fixture.offerSummary,
            category: fixture.objectType,
            status: .active,
            visibility: .publicDiscoverable
        )
    }

    private static func buildThread(
        fixture: RequesterComposeOnDeviceSmokeAuditFixtures.Fixture,
        searchIntent: ExchangeIntentFacets.ExchangeCanonicalSearchIntent
    ) -> ExchangeThread {
        ExchangeThread(
            mode: .transactional,
            intent: ExchangeIntent(
                kind: .find,
                mode: .transactional,
                queryIntentClass: fixture.queryIntentClass,
                surfacePreference: fixture.surfacePreference,
                title: "Compose smoke",
                objective: fixture.userRequest
            ),
            posture: ExchangePosture(privacy: .balanced),
            facets: ExchangeIntentFacets(
                searchIntent: searchIntent,
                queryIntentClass: fixture.queryIntentClass,
                surfacePreference: fixture.surfacePreference
            ),
            state: .searching(.init())
        )
    }

    private static func detectsEnrichmentInBody(body: String, directedLines: [String]) -> Bool {
        let lower = body.lowercased()
        let directedHaystack = directedLines.joined(separator: " ").lowercased()
        let pricingNeedles = ["pricing", "price", "quote", "estimate", "how estimates", "cost"]
        return pricingNeedles.contains { lower.contains($0) && !directedHaystack.contains($0) }
    }

    // MARK: - Console

    private static func printSmokeAuditRow(
        _ row: RequesterComposeOnDeviceSmokeAuditRow,
        index: Int,
        total: Int
    ) {
        let bodySnippet = auditBodyPrefix(row.body, maxLen: 360)
        print(
            "[RequesterComposeSmokeAudit] \(index)/\(total) id=\(row.id) " +
            "accepted=\(row.accepted) inventedQuestion=\(row.inventedQuestion) " +
            "preservedDirected=\(row.preservedDirected) extraDiligence=\(row.extraDiligence) " +
            "success=\(row.success) elapsedMs=\(row.elapsedMs ?? -1) " +
            "contract=\(row.outboundComposeContractPresent) requiredDirected=\(row.requiredDirectedCount) " +
            "enrichmentAllowed=\(row.enrichmentAllowed) enrichmentDetected=\(row.enrichmentDetectedInBody)"
        )
        if !row.allowedEnrichmentDimensions.isEmpty {
            print(
                "[RequesterComposeSmokeAudit]   allowedEnrichment=\(row.allowedEnrichmentDimensions.joined(separator: ",")) " +
                "hints=\(row.allowedEnrichmentHints.joined(separator: " | "))"
            )
        }
        print("[RequesterComposeSmokeAudit] body=\"\(bodySnippet)\"")
        if !row.rejectionReasons.isEmpty {
            print(
                "[RequesterComposeSmokeAudit]   rejection=\(row.rejectionReasons.joined(separator: ","))"
            )
        }
        if let failure = row.failureReason, !row.success {
            print("[RequesterComposeSmokeAudit]   auditFailure=\(failure)")
        }
    }

    private static func auditBodyPrefix(_ text: String, maxLen: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard trimmed.count > maxLen else { return trimmed }
        return String(trimmed.prefix(maxLen)) + "…"
    }
}

#endif
