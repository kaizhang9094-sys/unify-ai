#if DEBUG
import Foundation

/// Controlled three-way parity check for Phase 4I verification (extractor / interpreter / facade inference).
public enum ExchangePhase4IParityVerification {
    public struct QueryCase: Sendable {
        public var query: String
        public var fixtureCompactJSON: String

        public init(query: String, fixtureCompactJSON: String) {
            self.query = query
            self.fixtureCompactJSON = fixtureCompactJSON
        }
    }

    public struct ExtractorPathSnapshot: Sendable {
        public var rawLLMOutput: String
        public var compactDecodeSucceeded: Bool
        public var objectBeforeSanitize: String?
        public var objectAfterSanitize: String?
        public var compactMapped: Bool
        public var materiallyActionable: Bool
        public var repairAttempted: Bool
        public var fallbackReason: String?
        public var extractionSource: String?
        public var canonicalObjectType: String?
        public var domainCategory: String?
        public var transactionIntent: String?
    }

    public struct InterpreterPathSnapshot: Sendable {
        public var resultKind: String
        public var queryIntentClass: String?
        public var facetsQueryIntentClass: String?
        public var surfacePreference: String?
        public var objectType: String?
        public var domainCategory: String?
        public var transactionIntent: String?
        public var shouldDiscover: Bool
        public var reasonCode: String?
        public var objectLaneActive: Bool
        public var intentClassDesync: Bool
    }

    public struct FacadePathInference: Sendable {
        public var durableThreadCreated: Bool
        public var discoveryCalled: Bool
        public var transientNonPersistent: Bool
        public var objectType: String?
        public var objectLaneActive: Bool
    }

    public struct Row: Sendable {
        public var query: String
        public var extractor: ExtractorPathSnapshot
        public var interpreter: InterpreterPathSnapshot
        public var facade: FacadePathInference
        public var verdict: String
    }

    public static let failingQueries: [QueryCase] = [
        .init(
            query: "computer",
            fixtureCompactJSON: """
            {"raw":"computer","object":"computer","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking computer offer"}
            """
        ),
        .init(
            query: "car",
            fixtureCompactJSON: """
            {"raw":"car","object":"car","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking car offer"}
            """
        ),
        .init(
            query: "laptop",
            fixtureCompactJSON: """
            {"raw":"laptop","object":"laptop","need":null,"place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking laptop offer"}
            """
        ),
        .init(
            query: "computer under 500 tomorrow",
            fixtureCompactJSON: """
            {"raw":"computer under 500 tomorrow","object":"computer","need":null,"place":null,"time":"tomorrow","budget":"under 500","commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.90,"routeClass":"offerSearch","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.85,"routeRationale":"seeking computer with budget and time"}
            """
        ),
        .init(
            query: "how long does photo delivery take?",
            fixtureCompactJSON: """
            {"raw":"how long does photo delivery take?","object":null,"need":"photo delivery timing","place":null,"time":null,"budget":null,"commercial":null,"mods":[],"hard":[],"soft":[],"gaps":[],"confidence":0.88,"routeClass":"followUp","surfacePreference":"offer","targetKind":"provider","mode":"transactional","routeConfidence":0.80,"routeRationale":"FAQ follow-up about delivery"}
            """
        )
    ]

    public static func runAll(
        timingLabel: String = "immediate"
    ) async -> [Row] {
        var rows: [Row] = []
        rows.reserveCapacity(failingQueries.count)
        for queryCase in failingQueries {
            let row = await runOne(queryCase: queryCase, timingLabel: timingLabel)
            rows.append(row)
            printRow(row, timingLabel: timingLabel)
        }
        printSummary(rows: rows, timingLabel: timingLabel)
        return rows
    }

    public static func runOne(
        queryCase: QueryCase,
        timingLabel: String
    ) async -> Row {
        let extractor = await runExtractorPath(queryCase: queryCase)
        let interpreter = await runInterpreterPath(queryCase: queryCase)
        let facade = inferFacadePath(extractor: extractor, interpreter: interpreter)
        let verdict = classifyVerdict(
            queryCase: queryCase,
            extractor: extractor,
            interpreter: interpreter,
            facade: facade
        )
        return Row(
            query: queryCase.query,
            extractor: extractor,
            interpreter: interpreter,
            facade: facade,
            verdict: verdict
        )
    }

    // MARK: - Path A

    private static func runExtractorPath(queryCase: QueryCase) async -> ExtractorPathSnapshot {
        let mapper = LLMOpenEndedSearchIntentExtractor()
        let seed = seedIntent(for: queryCase.query)
        let fingerprint = mapper.compactSentenceFingerprint(queryCase.query)

        var objectBefore: String?
        var objectAfter: String?
        var compactDecodeSucceeded = false

        if let compact = mapper.decodeCompactSearchSummaryDTO(queryCase.fixtureCompactJSON) {
            compactDecodeSucceeded = true
            objectBefore = compact.object
            objectAfter = mapper.sanitizeText(
                compact.object,
                role: .objectText,
                sentenceFingerprint: fingerprint
            )
        }

        let syncCanonical = mapper.processSearchIntentFlatPipelineCanonical(
            cleaned: queryCase.fixtureCompactJSON,
            userText: queryCase.query,
            intent: seed
        )
        let syncMapped = syncCanonical != nil
        let syncActionable = syncCanonical.map { mapper.isMateriallyActionable($0) } ?? false

        let diagnosticsStore = SearchIntentExtractionDiagnosticsStore()
        let asyncExtractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: FixtureSearchIntentJSONProvider(json: queryCase.fixtureCompactJSON),
            diagnosticsStore: diagnosticsStore
        )
        let asyncCanonical = await asyncExtractor.extract(sourceText: queryCase.query, intent: seed)
        let diagnostics = await asyncExtractor.lastExtractionDiagnostics()

        let canonical = asyncCanonical ?? syncCanonical
        return ExtractorPathSnapshot(
            rawLLMOutput: queryCase.fixtureCompactJSON,
            compactDecodeSucceeded: compactDecodeSucceeded,
            objectBeforeSanitize: objectBefore,
            objectAfterSanitize: objectAfter,
            compactMapped: syncMapped,
            materiallyActionable: syncActionable,
            repairAttempted: diagnostics?.repairAttempted ?? false,
            fallbackReason: diagnostics?.fallbackReason?.rawValue,
            extractionSource: diagnostics?.source.rawValue ?? canonical?.extractionSource?.rawValue,
            canonicalObjectType: canonical?.objectType,
            domainCategory: canonical?.domainCategory.rawValue,
            transactionIntent: canonical?.transactionIntent?.rawValue
        )
    }

    // MARK: - Path B

    private static func runInterpreterPath(queryCase: QueryCase) async -> InterpreterPathSnapshot {
        let diagnosticsStore = SearchIntentExtractionDiagnosticsStore()
        let asyncExtractor = AsyncLLMOpenEndedSearchIntentExtractor(
            provider: FixtureSearchIntentJSONProvider(json: queryCase.fixtureCompactJSON),
            diagnosticsStore: diagnosticsStore
        )
        let interpreter = ExchangeInterpreter(
            intelligenceProvider: NoOpExchangeIntelligenceProvider(),
            asyncSearchIntentExtractor: asyncExtractor
        )
        let result = await interpreter.interpret(
            userText: queryCase.query,
            threadContext: nil,
            entrySurface: .searchComposer
        )

        switch result {
        case .needsClarification(let failure, _, _, _):
            return InterpreterPathSnapshot(
                resultKind: "needsClarification",
                queryIntentClass: nil,
                facetsQueryIntentClass: nil,
                surfacePreference: nil,
                objectType: nil,
                domainCategory: nil,
                transactionIntent: nil,
                shouldDiscover: false,
                reasonCode: failure.reasonCode,
                objectLaneActive: false,
                intentClassDesync: false
            )
        case .interpreted(let request):
            let thread = ExchangeThread(
                id: UUID(),
                mode: .transactional,
                intent: request.intent,
                posture: request.posture,
                facets: request.facets,
                state: .searching(.init())
            )
            let objectLane = ExchangeOfferObjectLane.isObjectLaneActive(thread: thread)
            let desync = request.intent.queryIntentClass != request.facets.queryIntentClass
            return InterpreterPathSnapshot(
                resultKind: "interpreted",
                queryIntentClass: request.intent.queryIntentClass.rawValue,
                facetsQueryIntentClass: request.facets.queryIntentClass.rawValue,
                surfacePreference: request.intent.surfacePreference.rawValue,
                objectType: request.facets.searchIntent?.objectType,
                domainCategory: request.facets.searchIntent?.domainCategory.rawValue,
                transactionIntent: request.facets.searchIntent?.transactionIntent?.rawValue,
                shouldDiscover: request.shouldDiscover,
                reasonCode: nil,
                objectLaneActive: objectLane,
                intentClassDesync: desync
            )
        }
    }

    // MARK: - Path C (inferred from orchestrator contract)

    private static func inferFacadePath(
        extractor: ExtractorPathSnapshot,
        interpreter: InterpreterPathSnapshot
    ) -> FacadePathInference {
        let transient = interpreter.resultKind == "needsClarification"
            && (interpreter.reasonCode == "search_intent_extractor_unavailable"
                || extractor.fallbackReason == "repairFailed")
        let durable = interpreter.resultKind == "interpreted" && !transient
        let discovery = durable && interpreter.shouldDiscover
        return FacadePathInference(
            durableThreadCreated: durable,
            discoveryCalled: discovery,
            transientNonPersistent: transient,
            objectType: interpreter.objectType ?? extractor.canonicalObjectType,
            objectLaneActive: interpreter.objectLaneActive
        )
    }

    private static func classifyVerdict(
        queryCase: QueryCase,
        extractor: ExtractorPathSnapshot,
        interpreter: InterpreterPathSnapshot,
        facade: FacadePathInference
    ) -> String {
        if extractor.objectBeforeSanitize != nil,
           extractor.objectAfterSanitize == nil,
           !extractor.compactMapped {
            return "real app bug (sanitize strips atomic object → compactMapped=false → repairFailed)"
        }
        if extractor.compactMapped,
           interpreter.resultKind == "interpreted",
           !facade.objectLaneActive,
           queryCase.query.contains("computer"),
           queryCase.query.contains("500") {
            if extractor.domainCategory != "product" || extractor.transactionIntent == "inquire" {
                return "real app bug (offerSearch object present but domain/transaction not product+buy → objectLane inactive)"
            }
        }
        if interpreter.intentClassDesync {
            return "real app bug (facets/intent queryIntentClass desync)"
        }
        if facade.transientNonPersistent {
            return "real app bug (4H facade path: transient non-persistent, no discovery)"
        }
        return "path OK on fixture replay"
    }

    private static func seedIntent(for text: String) -> ExchangeIntent {
        ExchangeIntent(
            kind: .find,
            mode: .transactional,
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            title: "parity-verify",
            objective: text
        )
    }

    private static func printRow(_ row: Row, timingLabel: String) {
        print(
            """
            [PHASE4I-PARITY] timing=\(timingLabel) query="\(row.query)"
              A: objectBefore=\(row.extractor.objectBeforeSanitize ?? "nil") objectAfter=\(row.extractor.objectAfterSanitize ?? "nil") compactDecode=\(row.extractor.compactDecodeSucceeded) compactMapped=\(row.extractor.compactMapped) actionable=\(row.extractor.materiallyActionable) repairAttempted=\(row.extractor.repairAttempted) fallback=\(row.extractor.fallbackReason ?? "nil") source=\(row.extractor.extractionSource ?? "nil") canonicalObject=\(row.extractor.canonicalObjectType ?? "nil") domain=\(row.extractor.domainCategory ?? "nil") tx=\(row.extractor.transactionIntent ?? "nil")
              B: kind=\(row.interpreter.resultKind) intentClass=\(row.interpreter.queryIntentClass ?? "nil") facetsClass=\(row.interpreter.facetsQueryIntentClass ?? "nil") object=\(row.interpreter.objectType ?? "nil") domain=\(row.interpreter.domainCategory ?? "nil") tx=\(row.interpreter.transactionIntent ?? "nil") shouldDiscover=\(row.interpreter.shouldDiscover) objectLane=\(row.interpreter.objectLaneActive) desync=\(row.interpreter.intentClassDesync) reason=\(row.interpreter.reasonCode ?? "nil")
              C: durableThread=\(row.facade.durableThreadCreated) discovery=\(row.facade.discoveryCalled) transient=\(row.facade.transientNonPersistent) objectLane=\(row.facade.objectLaneActive)
              verdict=\(row.verdict)
            """
        )
    }

    private static func printSummary(rows: [Row], timingLabel: String) {
        print("[PHASE4I-PARITY-SUMMARY] timing=\(timingLabel) rows=\(rows.count)")
        for row in rows {
            print(
                "[PHASE4I-PARITY-TABLE] \(row.query)|\(row.extractor.objectBeforeSanitize ?? "nil")|\(row.extractor.objectAfterSanitize ?? "nil")|\(row.extractor.canonicalObjectType ?? "nil")|\(row.interpreter.objectType ?? "nil")|\(row.facade.objectType ?? "nil")|\(row.interpreter.domainCategory ?? "nil")|\(row.interpreter.transactionIntent ?? "nil")|\(row.facade.objectLaneActive)|\(row.extractor.fallbackReason ?? "nil")|\(row.facade.discoveryCalled)|\(row.facade.durableThreadCreated)|\(row.verdict)"
            )
        }
    }
}

private struct FixtureSearchIntentJSONProvider: AsyncSearchIntentJSONProvider {
    var json: String

    func isReadyForImmediateExtraction() async -> Bool { true }

    func extractSearchIntentJSON(prompt: String) async throws -> String { json }
}

private struct NoOpExchangeIntelligenceProvider: ExchangeIntelligenceProvider {
    func classifyIntentFast(
        _ request: ExchangeIntelligenceFastClassificationRequest
    ) async throws -> ExchangeIntelligenceFastClassificationResponse {
        ExchangeIntelligenceFastClassificationResponse(
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            mode: .transactional,
            kind: .find,
            readiness: .ready,
            confidence: 0.8,
            needsFullLLMInterpretation: true
        )
    }

    func interpret(
        _ request: ExchangeIntelligenceInterpretationRequest
    ) async throws -> ExchangeIntelligenceInterpretationResponse {
        ExchangeIntelligenceInterpretationResponse(
            queryIntentClass: .generalDiscovery,
            surfacePreference: .mixed,
            mode: .transactional,
            kind: .find,
            title: String(request.userText.prefix(40)),
            objective: request.userText,
            constraints: [],
            desiredOutcomes: [.shortlist],
            readiness: .ready,
            confidence: 0.8,
            needsClarification: false,
            shouldDiscover: true,
            shouldDraft: false
        )
    }

    func modelPosture(
        _ request: ExchangeIntelligencePostureRequest
    ) async throws -> ExchangeIntelligencePostureResponse {
        ExchangeIntelligencePostureResponse(
            urgency: .normal,
            warmth: .neutral,
            directness: .balanced,
            openness: .open,
            commitment: .exploring,
            privacy: .balanced,
            priceSensitivity: .moderate,
            flexibility: .flexible,
            confidence: 0.5
        )
    }

    func composeDraft(
        _ request: ExchangeIntelligenceDraftRequest
    ) async throws -> ExchangeIntelligenceDraftResponse {
        ExchangeIntelligenceDraftResponse(body: "stub", confidence: 0.5)
    }

    func classifyInboundInquiry(
        _ request: ExchangeIntelligenceInboundInquiryRequest
    ) async throws -> ExchangeIntelligenceInboundInquiryResponse {
        ExchangeIntelligenceInboundInquiryResponse(
            inquirySummary: "stub",
            requesterAsk: request.requesterAsk,
            answerabilityStatus: .insufficientContext,
            classification: .routine,
            confidence: 0.5
        )
    }

}
#endif
