#if DEBUG
import Foundation

// MARK: - Run options

public struct ProviderInquiryAnswerOnDeviceSmokeAuditRunOptions: Sendable, Hashable {
    /// 0-based index into `ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all`.
    public var startIndex: Int
    /// Maximum fixtures to run; nil = through end of catalog.
    public var limit: Int?
    /// When set, only fixtures with these ids run (after range slice).
    public var fixtureIDs: Set<String>?
    /// Human label, e.g. `01_05` or `all`.
    public var runRangeLabel: String

    public init(
        startIndex: Int = 0,
        limit: Int? = nil,
        fixtureIDs: Set<String>? = nil,
        runRangeLabel: String = "all"
    ) {
        self.startIndex = startIndex
        self.limit = limit
        self.fixtureIDs = fixtureIDs
        self.runRangeLabel = runRangeLabel
    }

    public static let all = ProviderInquiryAnswerOnDeviceSmokeAuditRunOptions()

    public static func oneBasedRange(_ range: ClosedRange<Int>) -> ProviderInquiryAnswerOnDeviceSmokeAuditRunOptions {
        let start = max(0, range.lowerBound - 1)
        let count = range.count
        let label = String(format: "%02d_%02d", range.lowerBound, range.upperBound)
        return ProviderInquiryAnswerOnDeviceSmokeAuditRunOptions(
            startIndex: start,
            limit: count,
            runRangeLabel: label
        )
    }
}

// MARK: - Row

public struct ProviderInquiryAnswerOnDeviceSmokeAuditRow: Codable, Sendable, Hashable {
    public var id: String
    public var fixtureIndex: Int
    public var totalFixtures: Int
    public var runRangeLabel: String
    public var requesterQuestion: String
    public var liveLLM: Bool
    public var source: String
    public var task: String
    public var elapsedMs: Int?
    public var queryIntentClass: String
    public var surfacePreference: String
    public var allowedFactBlocks: String
    public var expectedAnswerability: String
    public var expectedAllowedSources: String
    public var boundaryExpectation: String
    public var publicProfileSnapshot: String
    public var commercialOfferSnapshot: String
    public var modelAnswer: String
    public var draftReply: String?
    public var answerableFromOffer: Bool?
    public var needsProviderInput: Bool?
    public var recommendedDisposition: String?
    public var canSendWithinConsent: Bool?
    public var governedAction: String?
    public var governorDowngradeReason: String?
    public var knownAnswers: [String]
    public var knownFacts: [String]
    public var missingFacts: [String]
    public var compareReason: String?
    public var compareJSON: String?
    public var validatorViolations: [String]
    public var requiredNeedlesHit: Bool
    public var requiredMatchedGroupCount: Int?
    public var requiredMinimumGroupCount: Int?
    public var missingRequiredIdeas: [String]
    public var forbiddenNeedlesHit: Bool
    public var forbiddenPass: Bool
    public var inventedCommercialClaimDetected: Bool
    public var inventedPass: Bool
    public var publicCommercialBoundaryViolation: Bool
    public var unsafeCommitmentDetected: Bool
    public var commitmentPass: Bool
    public var sourceBoundaryPass: Bool
    public var softObservations: [String]
    public var payloadDiagnostics: PayloadDiagnostics?
    public var success: Bool
    public var failureReason: String?
    public var usedPublic: Bool
    public var usedCommercial: Bool
    /// Deterministic claim-boundary policy trace (log-only phase; does not affect `success`).
    public var claimBoundaryTrace: ProviderClaimBoundaryTraceSummary?
    /// Report-only validator outcome (does not affect `success`).
    public var claimBoundaryValidationValid: Bool?
    public var claimBoundaryValidationSeverity: String?
    public var claimBoundaryValidationReasons: [String]?
    /// Report-only: whether claim-boundary gate would block compare-first auto-send for this draft.
    public var claimBoundaryBlockedAutoSend: Bool?
    /// Haystack vs ledger policy comparison (DEBUG; does not affect `success`).
    public var claimLedgerPolicyCompare: ProviderClaimLedgerPolicyComparison?

    public struct PayloadDiagnostics: Codable, Sendable, Hashable {
        public var sellerControlledFactsContainsLeadTimeNote: Bool
        public var sellerControlledFactsContainsRequiredBuyerInputs: Bool
        public var operatingMemorySummaryContainsLeadTime: Bool
        public var operatingMemorySummaryContainsBuyerInputs: Bool
        public var offerSummaryContainsLeadTime: Bool

        public init(
            sellerControlledFactsContainsLeadTimeNote: Bool,
            sellerControlledFactsContainsRequiredBuyerInputs: Bool,
            operatingMemorySummaryContainsLeadTime: Bool,
            operatingMemorySummaryContainsBuyerInputs: Bool,
            offerSummaryContainsLeadTime: Bool
        ) {
            self.sellerControlledFactsContainsLeadTimeNote = sellerControlledFactsContainsLeadTimeNote
            self.sellerControlledFactsContainsRequiredBuyerInputs = sellerControlledFactsContainsRequiredBuyerInputs
            self.operatingMemorySummaryContainsLeadTime = operatingMemorySummaryContainsLeadTime
            self.operatingMemorySummaryContainsBuyerInputs = operatingMemorySummaryContainsBuyerInputs
            self.offerSummaryContainsLeadTime = offerSummaryContainsLeadTime
        }
    }
}

// MARK: - Runner

public enum ProviderInquiryAnswerOnDeviceSmokeAuditSupport {
    public static let sourceTaskName = "providerInquiryCompare"
    public static let llmTaskName = "providerInquiryCompare"

    public static func artifactURL(runRangeLabel: String = "all") -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let base = "provider_inquiry_answer_on_device_smoke_audit"
        let name = runRangeLabel == "all" ? "\(base).jsonl" : "\(base)_\(runRangeLabel).jsonl"
        return docs
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
    }

    public static func fixtures(for options: ProviderInquiryAnswerOnDeviceSmokeAuditRunOptions) -> [(
        index: Int,
        fixture: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture
    )] {
        let all = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all
        let start = min(max(0, options.startIndex), all.count)
        let end: Int = {
            if let limit = options.limit, limit > 0 {
                return min(all.count, start + limit)
            }
            return all.count
        }()
        var slice = Array(all[start..<end]).enumerated().map { offset, fixture in
            (index: start + offset, fixture: fixture)
        }
        if let ids = options.fixtureIDs, !ids.isEmpty {
            slice = slice.filter { ids.contains($0.fixture.id) }
        }
        return slice
    }

    public static func run(
        intelligenceProvider: OnDeviceExchangeIntelligenceProvider,
        options: ProviderInquiryAnswerOnDeviceSmokeAuditRunOptions = .all,
        styleProfile: ExchangeSecretaryStyleProfile = .default,
        pauseBetweenRowsNanoseconds: UInt64 = 600_000_000
    ) async -> [ProviderInquiryAnswerOnDeviceSmokeAuditRow] {
        let catalog = ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.all
        let batch = fixtures(for: options)
        print(
            "[ProviderInquiryAnswerSmokeAudit] begin runRange=\(options.runRangeLabel) " +
            "fixtures=\(batch.count)/\(catalog.count) startIndex=\(options.startIndex)"
        )

        var rows: [ProviderInquiryAnswerOnDeviceSmokeAuditRow] = []
        rows.reserveCapacity(batch.count)

        let governor = ProviderInquiryCompareGovernor()
        let total = catalog.count

        for (fixtureIndex, fixture) in batch {
            let profile = buildProfile(from: fixture)
            let offer = buildOffer(from: fixture)
            let memory = ExchangeSellerSurfaceOperatingMemoryHydrator.hydrate(
                publicProfile: profile,
                offer: offer
            )

            let inboundExtraction = ProviderInquiryCompareSmokeInputAssembly.syntheticInboundIntentExtraction(
                requesterQuestion: fixture.requesterQuestion,
                queryIntentClass: fixture.queryIntentClass,
                surfacePreference: fixture.surfacePreference
            )
            let hasOffer = offer != nil
            let hasProfile = profile != nil
            let allowedSurfaces = ProviderAllowedFactSurfaces.derive(
                from: inboundExtraction,
                hasHydratedOffer: hasOffer,
                hasHydratedProfile: hasProfile
            )
            let allowedFactBlocks = allowedSurfaces.allowedFactBlocksMetadataLine()

            let offerSummary = ProviderInquiryCompareSmokeInputAssembly.compactOfferSummaryForCompare(offer: offer)
            let profileSummary = ProviderInquiryCompareSmokeInputAssembly.compactProfileSummaryForCompare(
                profile: profile,
                allowedSurfaces: allowedSurfaces
            )
            let osmSummary = ProviderInquiryCompareSmokeInputAssembly.operatingMemorySummary(memory)
            let sellerControlledFacts = ProviderInquiryCompareSmokeInputAssembly.sellerControlledFactsBlock(
                profile: profile,
                offer: offer,
                operatingMemory: memory,
                allowedSurfaces: allowedSurfaces
            )
            ProviderInquiryCompareProfileSummaryGate.logProfileSummarySurfaceAlignment(
                profileSummary: profileSummary,
                sellerControlledFacts: sellerControlledFacts,
                allowedSurfaces: allowedSurfaces,
                applyFactSurfaceGating: true,
                context: "smoke_audit_\(fixture.id)"
            )
            let claimDetection = ProviderInboundDimensionDetector.detect(requesterText: fixture.requesterQuestion)
            let claimPolicyInput = ProviderInboundClaimPolicyInput(
                requesterText: fixture.requesterQuestion,
                detection: claimDetection,
                allowedSurfaces: allowedSurfaces,
                applyFactSurfaceGating: true,
                offer: offer,
                profile: profile,
                sellerControlledFacts: sellerControlledFacts
            )
            let claimLedger = ProviderClaimLedgerBuilder.build(profile: profile, offer: offer)
            let claimPolicyCompared = ProviderInboundClaimPolicyEngine.compareHaystackWithLedger(
                claimPolicyInput,
                ledger: claimLedger
            )
            let claimBoundaryPacket = claimPolicyCompared.haystackPacket
            ProviderInboundClaimPolicyEngine.logLedgerPolicyComparisonForSmoke(
                fixtureID: fixture.id,
                comparison: claimPolicyCompared.comparison
            )
            let primarySurface = ProviderInquiryCompareSmokeInputAssembly.primaryOpportunitySurfaceLabel(
                boundaryExpectation: fixture.boundaryExpectation,
                hasOffer: offer != nil,
                hasProfile: profile != nil
            )

            let payloadDiagnostics = PayloadDiagnostics(
                sellerControlledFacts: sellerControlledFacts,
                osmSummary: osmSummary,
                offerSummary: offerSummary ?? ""
            )

            let wall = CFAbsoluteTimeGetCurrent()
            let compare = await intelligenceProvider.compareProviderInquiryVsOffer(
                inboundInquiry: fixture.requesterQuestion,
                offerSummary: offerSummary,
                profileSummary: profileSummary,
                operatingMemorySummary: osmSummary,
                styleProfile: styleProfile,
                consentAutomationSummary: ProviderInquiryCompareSmokeInputAssembly.consentAutomationSummary(offer: offer),
                sellerControlledFacts: sellerControlledFacts,
                queryIntentClass: inboundExtraction.compareRoutingInquiryKindLabel,
                surfacePreference: inboundExtraction.compareRoutingRequestedSurfacesLabel,
                primaryOpportunitySurface: primarySurface,
                selectedProfileID: profile?.id,
                selectedOfferID: offer?.id,
                allowedFactBlocksMetadata: allowedFactBlocks,
                inboundIntentContext: inboundExtraction
            )
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - wall) * 1000)

            let governed = governor.evaluate(
                compare: compare,
                permissionPolicy: ProviderInquiryCompareSmokeInputAssembly.governorPermissionPolicy(from: offer),
                boundaryHints: ProviderInquiryCompareGovernor.BoundaryHints()
            )

            let draftBody = compare.draftReply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let validatorOutcome = ExchangeProviderInquiryCompareDraftReplyValidator.validate(
                rawDraft: draftBody,
                compare: compare
            )

            let claimBoundaryValidation = ProviderClaimBoundaryValidator.validate(
                body: draftBody,
                packet: claimBoundaryPacket,
                requesterText: fixture.requesterQuestion
            )

            let publicSnapshot = ProviderInquiryAnswerSmokeAuditEvaluator.PublicSnapshot(profile: profile!)
            let commercialSnapshot = ProviderInquiryAnswerSmokeAuditEvaluator.CommercialSnapshot(offer: offer)
            let evaluation = ProviderInquiryAnswerSmokeAuditEvaluator.evaluate(
                fixture: fixture,
                body: draftBody,
                commercialSnapshot: commercialSnapshot,
                publicSnapshot: publicSnapshot
            )

            let usedPublic = fixture.expectedAllowedSources == .publicProfile
                || fixture.expectedAllowedSources == .both
                || fixture.boundaryExpectation == .publicOnly
            let usedCommercial = fixture.expectedAllowedSources == .commercialOffer
                || fixture.expectedAllowedSources == .both
                || fixture.boundaryExpectation == .commercialOnly

            let row = ProviderInquiryAnswerOnDeviceSmokeAuditRow(
                id: fixture.id,
                fixtureIndex: fixtureIndex + 1,
                totalFixtures: total,
                runRangeLabel: options.runRangeLabel,
                requesterQuestion: fixture.requesterQuestion,
                liveLLM: true,
                source: sourceTaskName,
                task: llmTaskName,
                elapsedMs: elapsedMs,
                queryIntentClass: inboundExtraction.compareRoutingInquiryKindLabel,
                surfacePreference: inboundExtraction.compareRoutingRequestedSurfacesLabel,
                allowedFactBlocks: allowedFactBlocks,
                expectedAnswerability: fixture.expectedAnswerability.rawValue,
                expectedAllowedSources: fixture.expectedAllowedSources.rawValue,
                boundaryExpectation: fixture.boundaryExpectation.rawValue,
                publicProfileSnapshot: publicSnapshot.haystack,
                commercialOfferSnapshot: commercialSnapshot.haystack,
                modelAnswer: draftBody,
                draftReply: compare.draftReply,
                answerableFromOffer: compare.answerableFromOffer,
                needsProviderInput: compare.needsProviderInput,
                recommendedDisposition: compare.recommendedDisposition,
                canSendWithinConsent: compare.canSendWithinConsent,
                governedAction: governed.normalizedAction.rawValue,
                governorDowngradeReason: governed.downgradeReason,
                knownAnswers: compare.knownAnswers,
                knownFacts: compare.knownFacts.map { $0.fact },
                missingFacts: compare.missingFacts,
                compareReason: compare.reason,
                compareJSON: encodeCompareJSON(compare),
                validatorViolations: validatorOutcome.violations,
                requiredNeedlesHit: evaluation.requiredNeedlesHit,
                requiredMatchedGroupCount: evaluation.requiredNeedleMatch.matchedGroupCount,
                requiredMinimumGroupCount: evaluation.requiredNeedleMatch.requiredGroupCount,
                missingRequiredIdeas: evaluation.requiredNeedleMatch.missingRequiredIdeas,
                forbiddenNeedlesHit: evaluation.forbiddenNeedlesHit,
                forbiddenPass: evaluation.forbiddenPass,
                inventedCommercialClaimDetected: evaluation.inventedCommercialClaimDetected,
                inventedPass: evaluation.inventedPass,
                publicCommercialBoundaryViolation: evaluation.publicCommercialBoundaryViolation,
                unsafeCommitmentDetected: evaluation.unsafeCommitmentDetected,
                commitmentPass: evaluation.commitmentPass,
                sourceBoundaryPass: evaluation.sourceBoundaryPass,
                softObservations: evaluation.softObservations,
                payloadDiagnostics: payloadDiagnostics,
                success: evaluation.success,
                failureReason: evaluation.failureReason,
                usedPublic: usedPublic,
                usedCommercial: usedCommercial,
                claimBoundaryTrace: claimBoundaryPacket.traceSummary,
                claimBoundaryValidationValid: claimBoundaryValidation.isValid,
                claimBoundaryValidationSeverity: claimBoundaryValidation.severity.rawValue,
                claimBoundaryValidationReasons: claimBoundaryValidation.reasons.map(\.code),
                claimBoundaryBlockedAutoSend: !ProviderClaimBoundaryValidator.claimBoundaryAllowsAutoSend(
                    claimBoundaryValidation
                ),
                claimLedgerPolicyCompare: claimPolicyCompared.comparison
            )
            rows.append(row)
            printSmokeAuditRow(row, displayIndex: rows.count, batchTotal: batch.count)

            if rows.count < batch.count, pauseBetweenRowsNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: pauseBetweenRowsNanoseconds)
            }
        }

        let succeeded = rows.filter(\.success).count
        print(
            "[ProviderInquiryAnswerSmokeAudit] complete runRange=\(options.runRangeLabel) " +
            "succeeded=\(succeeded)/\(rows.count)"
        )
        printLedgerDisagreementProbeSummary(rows: rows)
        return rows
    }

    private static func printLedgerDisagreementProbeSummary(
        rows: [ProviderInquiryAnswerOnDeviceSmokeAuditRow]
    ) {
        let probes = rows.filter {
            ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.ledgerDisagreementProbeIDs.contains($0.id)
        }
        guard !probes.isEmpty else { return }
        print("[ProviderClaimLedgerSmoke] disagreement probe summary count=\(probes.count)")
        for row in probes {
            guard let compare = row.claimLedgerPolicyCompare else {
                print("[ProviderClaimLedgerSmoke] fixture=\(row.id) comparison=nil")
                continue
            }
            print(
                "[ProviderClaimLedgerSmoke] fixture=\(row.id) disagreement=\(compare.disagreement) " +
                "detectedDimensions=\(compare.detectedDimensions.joined(separator: ",")) " +
                "oldAllowed=\(compare.oldAllowed) newAllowed=\(compare.newAllowed) " +
                "oldMissing=\(compare.oldMissing) newMissing=\(compare.newMissing)"
            )
        }
    }

    public static func writeJSONL(rows: [ProviderInquiryAnswerOnDeviceSmokeAuditRow], to url: URL) throws {
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

    // MARK: - Builders

    static func buildProfile(
        from fixture: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture
    ) -> ExchangePublicNodeProfile? {
        let spec = fixture.profile
        return ExchangePublicNodeProfile(
            id: "provider-smoke-\(fixture.id)-profile",
            nodeID: "provider-smoke-node",
            displayName: spec.displayName,
            headline: spec.headline,
            summary: spec.summary,
            visibility: .discoverable,
            interests: spec.interests,
            offers: spec.offers,
            openTo: spec.openTo,
            activityTags: spec.activityTags,
            regionTags: spec.regionTags
        )
    }

    static func buildOffer(
        from fixture: ProviderInquiryAnswerOnDeviceSmokeAuditFixtures.Fixture
    ) -> ExchangeOffer? {
        guard let spec = fixture.offer else { return nil }
        var fulfillment = ExchangeOffer.Fulfillment()
        if let lead = spec.leadTimeNote?.trimmingCharacters(in: .whitespacesAndNewlines), !lead.isEmpty {
            fulfillment.leadTimeNote = lead
        }
        return ExchangeOffer(
            id: "provider-smoke-\(fixture.id)-offer",
            nodeID: "provider-smoke-node",
            title: spec.title,
            summary: spec.summary,
            category: spec.category,
            tags: spec.tags,
            fulfillment: fulfillment,
            status: .active,
            visibility: .publicDiscoverable,
            commercialFacts: spec.commercialFacts
        )
    }

    private static func encodeCompareJSON(_ compare: ExchangeProviderInquiryCompareResult) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(compare) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func PayloadDiagnostics(
        sellerControlledFacts: String,
        osmSummary: String,
        offerSummary: String
    ) -> ProviderInquiryAnswerOnDeviceSmokeAuditRow.PayloadDiagnostics {
        let factsLower = sellerControlledFacts.lowercased()
        let osmLower = osmSummary.lowercased()
        let offerLower = offerSummary.lowercased()
        return .init(
            sellerControlledFactsContainsLeadTimeNote: factsLower.contains("lead_time_note:"),
            sellerControlledFactsContainsRequiredBuyerInputs: factsLower.contains("required_buyer_input:"),
            operatingMemorySummaryContainsLeadTime: osmLower.contains("lead time:"),
            operatingMemorySummaryContainsBuyerInputs: osmLower.contains("buyer input:"),
            offerSummaryContainsLeadTime: offerLower.contains("lead time:")
        )
    }

    // MARK: - Console

    private static func printSmokeAuditRow(
        _ row: ProviderInquiryAnswerOnDeviceSmokeAuditRow,
        displayIndex: Int,
        batchTotal: Int
    ) {
        let bodySnippet = auditBodyPrefix(row.modelAnswer, maxLen: 360)
        let disposition = row.recommendedDisposition ?? "nil"
        let governed = row.governedAction ?? "nil"
        print(
            "[ProviderInquiryAnswerSmokeAudit] \(displayIndex)/\(batchTotal) " +
            "fixture=\(row.fixtureIndex)/\(row.totalFixtures) runRange=\(row.runRangeLabel) " +
            "id=\(row.id) liveLLM=\(row.liveLLM) source=\(row.source) task=\(row.task) " +
            "answerability=\(row.expectedAnswerability) disposition=\(disposition) " +
            "governed=\(governed) success=\(row.success) elapsedMs=\(row.elapsedMs ?? -1)"
        )
        print(
            "[ProviderInquiryAnswerSmokeAudit] sources=\(row.expectedAllowedSources) " +
            "usedPublic=\(row.usedPublic) usedCommercial=\(row.usedCommercial) " +
            "boundary=\(row.boundaryExpectation)"
        )
        print("[ProviderInquiryAnswerSmokeAudit] body=\"\(bodySnippet)\"")
        print(
            "[ProviderInquiryAnswerSmokeAudit] checks " +
            "requiredPass=\(row.requiredNeedlesHit) forbiddenPass=\(row.forbiddenPass) " +
            "inventedPass=\(row.inventedPass) commitmentPass=\(row.commitmentPass) " +
            "boundaryPass=\(row.sourceBoundaryPass)"
        )
        if !row.softObservations.isEmpty {
            print(
                "[ProviderInquiryAnswerSmokeAudit]   soft=\(row.softObservations.joined(separator: ","))"
            )
        }
        if !row.missingRequiredIdeas.isEmpty {
            print(
                "[ProviderInquiryAnswerSmokeAudit]   missingRequiredIdeas=\(row.missingRequiredIdeas.joined(separator: ","))"
            )
        }
        if let diag = row.payloadDiagnostics {
            print(
                "[ProviderInquiryAnswerSmokeAudit]   payload leadTimeInFacts=\(diag.sellerControlledFactsContainsLeadTimeNote) " +
                "buyerInputsInFacts=\(diag.sellerControlledFactsContainsRequiredBuyerInputs) " +
                "leadTimeInOSM=\(diag.operatingMemorySummaryContainsLeadTime) " +
                "buyerInputsInOSM=\(diag.operatingMemorySummaryContainsBuyerInputs)"
            )
        }
        if let trace = row.claimBoundaryTrace {
            print(
                "[ProviderInquiryAnswerSmokeAudit]   claimBoundary dimensions=\(trace.dimensions.joined(separator: ",")) " +
                "riskTier=\(trace.riskTier) answerability=\(trace.answerabilityStatus) " +
                "allowed=\(trace.allowedClaimsCount) missing=\(trace.missingClaimsCount) " +
                "forbidden=\(trace.forbiddenClaimsCount)"
            )
        }
        if let valid = row.claimBoundaryValidationValid {
            let reasons = row.claimBoundaryValidationReasons?.joined(separator: ",") ?? ""
            print(
                "[ProviderInquiryAnswerSmokeAudit]   claimBoundaryValidation valid=\(valid) " +
                "severity=\(row.claimBoundaryValidationSeverity ?? "nil") reasons=\(reasons)"
            )
        }
        if let ledgerCompare = row.claimLedgerPolicyCompare {
            let dims = ledgerCompare.detectedDimensions.joined(separator: ",")
            let fallback = ledgerCompare.fallbackHaystackUsed.isEmpty
                ? "none"
                : ledgerCompare.fallbackHaystackUsed.joined(separator: ",")
            print(
                "[ProviderInquiryAnswerSmokeAudit]   claimLedgerCompare fixture=\(row.id) " +
                "detectedDimensions=\(dims) oldAllowed=\(ledgerCompare.oldAllowed) " +
                "newAllowed=\(ledgerCompare.newAllowed) oldMissing=\(ledgerCompare.oldMissing) " +
                "newMissing=\(ledgerCompare.newMissing) fallbackHaystackUsed=\(fallback) " +
                "disagreement=\(ledgerCompare.disagreement)"
            )
        }
        if !row.validatorViolations.isEmpty {
            print(
                "[ProviderInquiryAnswerSmokeAudit]   validator=\(row.validatorViolations.joined(separator: ","))"
            )
            let roleReversal = row.validatorViolations.filter { $0.hasPrefix("role_reversal_") }
            if !roleReversal.isEmpty {
                print(
                    "[ProviderInquiryAnswerSmokeAudit]   roleReversalDetected fixture=\(row.id) " +
                    "codes=\(roleReversal.joined(separator: ","))"
                )
            }
        }
        if !row.success {
            print(
                "[ProviderInquiryAnswerSmokeAudit]   compare answerable=\(row.answerableFromOffer.map(String.init(describing:)) ?? "nil") " +
                "needsProviderInput=\(row.needsProviderInput.map(String.init(describing:)) ?? "nil")"
            )
            if !row.knownAnswers.isEmpty {
                print(
                    "[ProviderInquiryAnswerSmokeAudit]   knownAnswers=\(row.knownAnswers.joined(separator: " | "))"
                )
            }
            if !row.missingFacts.isEmpty {
                print(
                    "[ProviderInquiryAnswerSmokeAudit]   missingFacts=\(row.missingFacts.joined(separator: " | "))"
                )
            }
            if let downgrade = row.governorDowngradeReason, !downgrade.isEmpty {
                print("[ProviderInquiryAnswerSmokeAudit]   governorDowngrade=\(downgrade)")
            }
            if let failure = row.failureReason {
                print("[ProviderInquiryAnswerSmokeAudit]   auditFailure=\(failure)")
            }
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
